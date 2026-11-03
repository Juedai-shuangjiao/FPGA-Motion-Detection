
//========================================================
// 模块：video_in —— ISP 输出 → 写 DDR 帧缓存
// 功能：把 ISP 处理完的像素流，跨时钟域（摄像头时钟→DDR时钟）写入 DDR。
//       用 4 个缓冲区做乒乓：写第 N 块的同时，video_out 读第 N-2 块，读写不冲突。
//========================================================
module video_in (
    input wire         I_rst_n,               //复位，低有效

    input wire         I_camera_clk,          //摄像头侧时钟
    input wire         I_camera_frame_start,  //帧开始
    input wire         I_camera_valid,        //数据有效
    input wire[127:0]  I_camera_data,         //像素数据（128 位）
    input wire         I_mipi_rx_error,       //MIPI 接收错误
    input wire         I_ae_cfg_done,         //曝光配置完成（24M 域，I2C写完，对齐跳帧时机）
    input wire         I_auto_en,             //自动模式（SW3低），自动模式才跳帧、手动模式不跳帧避免卡顿
    input wire         I_bg_capture,          //背景采集标志（ISP 域，覆盖完整一帧，内部跨时钟域同步）
    input wire         I_init_calib_done,     //DDR 初始化校准完成（DDR 域，训练完成后拉高；复位重训后清采集 FIFO 残字用）

    input wire         I_ddr_clk,             //DDR 侧时钟

    input wire         I_display_pause,       //显示暂停
    input wire         I_video_out_rd_busy,   //显示读忙（写避让读：恢复官方双向互斥，读写命令不交织，读数据流不被写打断）
    input wire         I_wr_grant,            //写 grant（仲裁器授权，1=本拍可写）
    output wire        O_wr_req,              //写请求（写突发有效，给仲裁器）
    output wire        O_video_in_wr_busy,    //video_in 写忙（保留，兼容）
    output reg[1:0]    O_video_out_rp,        //读指针（告诉 video_out 读哪个缓冲区）
    output wire        O_frame_start_ddr,     //DDR 域帧开始（给 bg_read 帧同步读）
    output reg [17:0]  O_dbg_wr_cnt,          //debug：每帧写总数（验证「写侧提前结束」假设）

    output reg         O_ddr_user_wr_en,      //DDR 写使能
    output reg[24:0]   O_ddr_user_addr,       //DDR 写地址
    output wire[127:0] O_ddr_user_wr_data,    //DDR 写数据
    input wire         I_ddr_user_ready,      //DDR 就绪
    output reg         O_fifo_full_latch      //诊断：采集 FIFO 满过（锁存到复位）——写不准的直接实锤
);

    wire        S_fifo_rst;                    //FIFO 复位
    wire        S_fifo_full;                   //采集 FIFO 满（写时钟域）
    // 满标志锁存：一旦满过（溢出丢字）保持到复位，LED 直接观察「写不准」实锤
    always @(posedge I_camera_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            O_fifo_full_latch <= 1'b0;
        else if(S_fifo_full)
            O_fifo_full_latch <= 1'b1;
    end
    reg         S_camera_frame_start_extend;   //帧开始脉冲展宽（同步到 DDR 时钟域）
    reg[3:0]    S_extend_cnt;                  //展宽计数
    reg         S_camera_frame_start_extend_1d;//跨时钟域打拍 1
    reg         S_camera_frame_start_extend_2d;//跨时钟域打拍 2
    reg         S_camera_frame_start_extend_3d;//跨时钟域打拍 3
    wire        S_frame_start;                 //同步后的帧开始
    reg[1:0]    S_video_in_wp;                 //写指针（写哪个缓冲区）
    wire[8:0]   S_fifo_rd_num;                 //FIFO 里可读的数据个数
    wire        S_fifo_rd_en;                  //FIFO 读使能
    wire        S_fifo_rd_valid;
    wire[127:0] S_fifo_rd_data;                //FIFO 读出的数据
    reg         S_ddr_wr_valid;                //DDR 写突发有效
    reg[9:0]    S_ddr_wr_cnt;                  //DDR 写计数

    // 4 个帧缓冲区的起始地址（乒乓用，每块相隔 700 万地址）
    localparam IMAGE_BASE_ADDR_0 = 25'd0;
    localparam IMAGE_BASE_ADDR_1 = 25'd7000000;
    localparam IMAGE_BASE_ADDR_2 = 25'd14000000;
    localparam IMAGE_BASE_ADDR_3 = 25'd21000000;
    localparam IMAGE_BASE_ADDR_4 = 25'd22382400;   //背景缓冲区（紧挨第3块乒乓之后，独立不重叠 + bank切换最少）

    //------------ 帧尾排空批：清残留防卷绕（替代帧头/帧尾复位） ------------
    // 2026-10-28 卷绕根因链（历史「帧尾批跨帧卷绕」再现）：
    //   帧尾批在帧头拍被停 → 残留 K 字留在 FIFO；原实现靠帧头复位清残留，
    //   但复位窗覆盖帧头数据 → 丢帧头 11 字 → 错位 58 像素；改帧尾复位后，
    //   残留又混入新帧第 1 批 → 右边界内容卷到屏幕左侧（「logo 右边出现右边界」）。
    //   正确做法：帧尾（tvalid 低电平持续 2000 拍判定）后强制写 240 拍排空批——
    //   残留 K 字被写进 DDR 帧尾后区域（地址递增，块间隙足够大无害），FIFO 清零；
    //   排空落在垂直消隐期（新帧数据未到）→ 零混批、零丢帧头。
    reg  cam_valid_d1;
    reg [11:0] low_cnt;      //tvalid 低电平持续计数
    reg  fend_extend;
    reg [2:0] fend_cnt;
    reg  fend_s1, fend_s2, fend_s3;
    reg  S_fend_drain;       //帧尾排空批（240 拍）
    reg [7:0] S_drain_cnt;
    wire cam_frame_end;     //摄像头域帧尾：tvalid 低电平持续 2000 拍（非行间空洞）
    always @(posedge I_camera_clk or negedge I_rst_n) begin
        if(!I_rst_n) cam_valid_d1 <= 1'b0;
        else         cam_valid_d1 <= I_camera_valid;
    end
    // 2026-10-28 花屏根因修复：帧尾不能只看 tvalid 下降沿——ISP 输出带行消隐空洞
    //   （tlast 行结束，每行 tvalid 断 ~60 拍），下降沿会每行误触发写 FIFO 打断。
    //   改判：tvalid 低电平持续 > 2000 拍才判帧尾（行间空洞几十拍远达不到、
    //   帧尾垂直消隐 280 行 ×300 拍 = 8.4 万拍远超过 → 只触发一次/帧）。
    always @(posedge I_camera_clk or negedge I_rst_n) begin
        if(!I_rst_n)                    low_cnt <= 12'd0;
        else if(I_camera_valid)         low_cnt <= 12'd0;
        else if(cam_valid_d1)           low_cnt <= 12'd1;   //下降沿起计数
        else if(low_cnt != 12'd0 && low_cnt < 12'd2000) low_cnt <= low_cnt + 12'd1;
    end
    assign cam_frame_end = (low_cnt == 12'd2000);
    // 帧尾脉冲展宽 8 拍（摄像头域）：1 拍脉冲（6.67ns）直接打 3 拍会被 100M 域漏采
    always @(posedge I_camera_clk or negedge I_rst_n) begin
        if(!I_rst_n)               fend_extend <= 1'b0;
        else if(cam_frame_end)     fend_extend <= 1'b1;
        else if(fend_cnt == 3'd7)  fend_extend <= 1'b0;
    end
    always @(posedge I_camera_clk or negedge I_rst_n) begin
        if(!I_rst_n)      fend_cnt <= 3'd0;
        else if(fend_extend) fend_cnt <= fend_cnt + 3'd1;
        else              fend_cnt <= 3'd0;
    end
    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin fend_s1 <= 1'b0; fend_s2 <= 1'b0; fend_s3 <= 1'b0; end
        else begin fend_s1 <= fend_extend; fend_s2 <= fend_s1; fend_s3 <= fend_s2; end
    end
    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n)                    S_fend_drain <= 1'b0;
        else if(fend_s2 && !fend_s3)    S_fend_drain <= 1'b1;      //帧尾展宽下降沿起排空
        else if(S_drain_cnt == 8'd239)  S_fend_drain <= 1'b0;      //240 拍排空结束
    end
    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n)           S_drain_cnt <= 8'd0;
        else if(S_fend_drain)  S_drain_cnt <= S_drain_cnt + 8'd1;
        else                   S_drain_cnt <= 8'd0;
    end
    //------------ 复位重训后清采集 FIFO 指针（bug1 修复，2026-11-01）------------
    // 按键复位后 DDR 重训（ms 级）期间写不进去：采集 FIFO 溢出丢字 + 排空批写不出留残字 →
    // 训练完成后第一帧帧头写进旧残字 → 画面错位（实机复位后错位/概率恢复正常）。
    // 修复：init_calib 上升沿直接清 FIFO 指针（32 拍复位窗）——训练期残字全部丢弃，
    // 下一帧从空 FIFO 开始 → 零错位。实机时序：DDR 训练（~5ms）完成时摄像头流已被
    // uicfgcs500 写 0x0100=0 关断（复位后 ~0.8ms）→ 清窗期间无数据进入 → 丢 0 字；
    // 即使流仍开着，最坏丢清窗内几十字（当前帧 ≤几十字错位，下一帧帧头对齐恢复），
    // 远好于训练期残字导致的整帧错位。
    reg        S_calib_s1;         //init_calib 打 1 拍（上升沿检测）
    reg        S_fifo_rst_int;     //FIFO 复位电平（32 拍窗）
    reg [4:0]  S_fifo_rst_cnt;     //复位窗计数
    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_calib_s1     <= 1'b0;
            S_fifo_rst_int <= 1'b0;
            S_fifo_rst_cnt <= 5'd0;
        end else begin
            S_calib_s1 <= I_init_calib_done;
            if(I_init_calib_done && !S_calib_s1) begin
                S_fifo_rst_int <= 1'b1;                       //训练完成上升沿：直接清
                S_fifo_rst_cnt <= 5'd0;
            end else if(S_fifo_rst_int) begin
                S_fifo_rst_cnt <= S_fifo_rst_cnt + 5'd1;      //32 拍复位窗
                if(S_fifo_rst_cnt == 5'd31)
                    S_fifo_rst_int <= 1'b0;
            end
        end
    end
    assign S_fifo_rst = S_fifo_rst_int;   //bug1 修复：不再恒 0——DDR 训练完成后在排空批末拍清一次指针（残字丢弃，下一帧对齐）

    // 写忙标志 = 正在 DDR 写突发
    assign O_video_in_wr_busy = S_ddr_wr_valid;

    //------------ 跨时钟域 FIFO（摄像头时钟写，DDR 时钟读）------------
    w128_d512_fifo U_w128_d512_fifo(
        .rst        ( S_fifo_rst         ),

        .clkw       ( I_camera_clk       ),    //写时钟（摄像头侧）
        .we         ( I_camera_valid     ),    //写使能（数据有效）
        .di         ( I_camera_data      ),    //写数据
        .afull      (),
        .full_flag  ( S_fifo_full        ),
        .wrusedw    (),

        .clkr       ( I_ddr_clk          ),    //读时钟（DDR 侧）
        .re         ( S_fifo_rd_en       ),    //读使能
        .dout       ( O_ddr_user_wr_data ),    //读数据（128 位）
        .rdusedw    ( S_fifo_rd_num      ),    //可读数据个数
        .valid      (),
        .empty_flag (),
        .aempty     ()
    );

    //------------ 帧开始脉冲展宽（在摄像头时钟域，展宽 8 拍方便跨时钟同步）------------
    always @(posedge I_camera_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            S_camera_frame_start_extend <= 1'b0;
        else
            if(I_camera_frame_start)                    //帧开始来了
                S_camera_frame_start_extend <= 1'b1;
            else if(S_extend_cnt == 'd7)                //展宽 8 拍后拉低
                S_camera_frame_start_extend <= 1'b0;
            else
                S_camera_frame_start_extend <= S_camera_frame_start_extend;
    end

    always @ (posedge I_camera_clk) begin
    	if(S_camera_frame_start_extend)
        	S_extend_cnt <= S_extend_cnt + 'd1;
     	else
          	S_extend_cnt <= 'd0;
    end

    //------------ 跨时钟域同步（摄像头时钟域 → DDR 时钟域，打 3 拍）------------
    always @(posedge I_ddr_clk) begin
        S_camera_frame_start_extend_1d <= S_camera_frame_start_extend;
        S_camera_frame_start_extend_2d <= S_camera_frame_start_extend_1d;
        S_camera_frame_start_extend_3d <= S_camera_frame_start_extend_2d;
    end

    assign S_frame_start = ~S_camera_frame_start_extend_3d & S_camera_frame_start_extend_2d;  //帧开始下降沿

    //------------ debug：每帧写总数计数（帧开始下降沿锁存并复位，SW4 拨上时数码管显示）------------
    // 验证「写侧提前结束」假设：正常 0x2A300（=172800），少 3 个 = 0x2A2FD（=172797）
    reg [17:0] dbg_wr_cnt;
    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            dbg_wr_cnt   <= 18'd0;
            O_dbg_wr_cnt <= 18'd0;
        end else begin
            if(S_frame_start) begin
                O_dbg_wr_cnt <= dbg_wr_cnt;            //锁存本帧写总数
                dbg_wr_cnt   <= 18'd0;                 //复位重新计数
            end else if(O_ddr_user_wr_en && (!S_fend_drain)) begin
                dbg_wr_cnt   <= dbg_wr_cnt + 18'd1;    //每写 1 个 128 位 +1（排空批不算：判据保持 172800）
            end
        end
    end

    assign O_frame_start_ddr = S_frame_start;  //引出给 bg_read 帧同步读

    //------------ 曝光配置完成信号跨时钟域同步（24M 域 → DDR 域），用于跳过切换帧 ------------
    // 自动曝光调节写完摄像头寄存器（I_ae_cfg_done 上升沿）后，摄像头切换曝光/增益，
    // 切换生效期间会输出几帧异常（手电筒强光下最明显）。
    // 这里把「I2C 写完」同步到 DDR 域，触发后连续跳过 3 帧（不写 DDR），异常帧就不显示。
    reg ae_done_s1, ae_done_s2, ae_done_s3;
    always @(posedge I_ddr_clk) begin
        ae_done_s1 <= I_ae_cfg_done;
        ae_done_s2 <= ae_done_s1;
        ae_done_s3 <= ae_done_s2;
    end
    wire ae_done_rise = ae_done_s2 & ~ae_done_s3;  //I2C写完上升沿（DDR 域，一拍）

    //------------ 背景采集标志跨时钟域同步（ISP 域 → DDR 域，打 3 拍）------------
    // bg_capture 覆盖完整一帧（电平），打 3 拍后仍覆盖完整一帧（3 拍延迟相对一帧可忽略）
    reg bg_cap_s1, bg_cap_s2, bg_cap_s3;
    always @(posedge I_ddr_clk) begin
        bg_cap_s1 <= I_bg_capture;
        bg_cap_s2 <= bg_cap_s1;
        bg_cap_s3 <= bg_cap_s2;
    end
    wire bg_capture_ddr = bg_cap_s3;  //DDR 域的采集标志（覆盖完整一帧）

    reg [2:0] r_skip_cnt;   //跳帧计数：I2C写完后连续跳过 3 帧（摄像头切换生效期间的异常帧）
    // ⚠️ 2026-11-01 bug2 修复：跳帧从「屏蔽写」改为「覆盖写同块」——
    //   原实现 r_frame_masked 屏蔽写 3 帧 → 摄像头持续灌采集 FIFO（不复位）→
    //   溢出丢字 + 排空批把旧残字写到帧头 → 恢复帧整帧错位（实机画面平移+颜色错）。
    //   新实现：跳帧期间写照常（写指针 wp 不动 → 地址每帧复位到同一乒乓块帧头 → 覆盖写），
    //   FIFO 正常排空零溢出零丢字；异常帧被写进「显示端不读」的 wp 块，显示冻结 3 帧但不错位。
    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            r_skip_cnt     <= 3'd0;
        end else begin
            if(ae_done_rise && I_auto_en)
                r_skip_cnt <= 3'd3;             //自动模式：I2C写完跳 3 帧（异常帧覆盖写，不屏蔽）；手动模式不跳（跳帧冻结=按键卡顿）
            if(S_frame_start) begin
                if(r_skip_cnt > 3'd0)
                    r_skip_cnt     <= r_skip_cnt - 1'b1;
            end
        end
    end

    //------------ 写指针（每帧 +1，4 个缓冲区轮换；MIPI 出错或跳帧则保持不动）------------
    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            S_video_in_wp <= 'd0;
        else
            if(I_display_pause)
                S_video_in_wp <= S_video_in_wp;
            else if(S_frame_start)
                begin
                    if(I_mipi_rx_error || (r_skip_cnt > 3'd0) || bg_capture_ddr)  //这帧有错/跳帧/采背景，写指针不动
                        S_video_in_wp <= S_video_in_wp;
                    else
                        S_video_in_wp <= S_video_in_wp + 'd1;  //写指针 +1，写下一个缓冲区
                end
            else
                S_video_in_wp <= S_video_in_wp;
    end

    //------------ 读指针（告诉 video_out 读哪个缓冲区，跟写指针错开 2 个 = 乒乓，官方例程方案）------------
    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            O_video_out_rp <= 'd0;
        else
            if(I_display_pause)
                O_video_out_rp <= O_video_out_rp;
            else if(S_frame_start)
                begin
                    case(S_video_in_wp)
                        'd0: O_video_out_rp <= 'd2;
                        'd1: O_video_out_rp <= 'd3;
                        'd2: O_video_out_rp <= 'd0;
                        'd3: O_video_out_rp <= 'd1;
                    endcase
                end
            else
                O_video_out_rp <= O_video_out_rp;
    end

    //------------ DDR 写突发控制（FIFO 攒够 240 个数据才开始写，写 240 个停）------------
    // 注：不再避让 video_out 读，由顶层仲裁器统一 grant 门控
    // 帧开始（S_frame_start_d1）强制停写批：bg_read 挤占命令通道使写批变慢时，写批可能跨过帧开始，
    // 而帧开始拍写地址已复位到新帧头 → 帧尾批数据写到新帧头 → 帧内容卷绕错位。
    // 停批丢弃的帧尾残留（<240 字）由 FIFO 帧复位清除，下一帧从头写，丢尾行比整帧错位可接受得多。
    // 打 1 拍使用：S_frame_start 组合脉冲直接进状态机 hold 违例（-49ps），打拍后转 setup（余量 176ps 够）。
    reg S_frame_start_d1;
    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n) S_frame_start_d1 <= 1'b0;
        else S_frame_start_d1 <= S_frame_start;
    end
    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            S_ddr_wr_valid <= 1'b0;
        else
            if(S_fifo_rst)                                              //清 FIFO 窗：强制停批（防写批读空 FIFO 地址错乱）
                S_ddr_wr_valid <= 1'b0;
            else if(S_frame_start_d1)                                        //帧开始（打 1 拍）：强制停写批
                S_ddr_wr_valid <= 1'b0;
            else if(S_ddr_wr_valid && I_ddr_user_ready && I_wr_grant && S_ddr_wr_cnt == 'd239)   //写完 240 个
                S_ddr_wr_valid <= 1'b0;
            else if(S_fend_drain)                                       //帧尾排空批：清残留（消隐期，新帧数据未到）
                S_ddr_wr_valid <= 1'b1;
            else if(S_fifo_rd_num >= 'd240 && (!I_video_out_rd_busy) && (!S_fifo_rst))  //FIFO 攒够 240 个、读不忙（bug2 修复：去掉跳帧屏蔽，跳帧覆盖写不丢字）
                S_ddr_wr_valid <= 1'b1;
            else
                S_ddr_wr_valid <= S_ddr_wr_valid;
    end

    always @(posedge I_ddr_clk) begin
        if(S_ddr_wr_valid)
            begin
                if(I_ddr_user_ready & I_wr_grant)
                    S_ddr_wr_cnt <= S_ddr_wr_cnt + 'd1;
                else
                    S_ddr_wr_cnt <= S_ddr_wr_cnt;
            end
        else
            S_ddr_wr_cnt <= 'd0;
    end

    assign S_fifo_rd_en = S_ddr_wr_valid & I_ddr_user_ready & I_wr_grant;   //写突发中且 DDR 就绪且 grant，读 FIFO
    assign O_wr_req = S_ddr_wr_valid;   //写请求 = 写突发有效（给仲裁器）

    always @(posedge I_ddr_clk) begin
        O_ddr_user_wr_en <= S_fifo_rd_en;                      //DDR 写使能
    end

    //------------ DDR 写地址（帧开始选缓冲区起始地址，之后每写一次 +8）------------
    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            O_ddr_user_addr <= 1'b0;
        else
            if(S_frame_start && (!I_mipi_rx_error) && bg_capture_ddr)  //采背景帧，写背景缓冲区
                O_ddr_user_addr <= IMAGE_BASE_ADDR_4;
            else if(S_frame_start && (!I_mipi_rx_error))            //正常帧，按写指针选缓冲区
                begin
                    case(S_video_in_wp)
                        'd0: O_ddr_user_addr <= IMAGE_BASE_ADDR_0;
                        'd1: O_ddr_user_addr <= IMAGE_BASE_ADDR_1;
                        'd2: O_ddr_user_addr <= IMAGE_BASE_ADDR_2;
                        'd3: O_ddr_user_addr <= IMAGE_BASE_ADDR_3;
                    endcase
                end
			else if(S_frame_start && I_mipi_rx_error)           //坏帧，回退到上一个缓冲区覆盖
				begin
                	case(S_video_in_wp)
                        'd0: O_ddr_user_addr <= IMAGE_BASE_ADDR_3;
                        'd1: O_ddr_user_addr <= IMAGE_BASE_ADDR_0;
                        'd2: O_ddr_user_addr <= IMAGE_BASE_ADDR_1;
                        'd3: O_ddr_user_addr <= IMAGE_BASE_ADDR_2;
                    endcase
                end
            else if(O_ddr_user_wr_en)
                O_ddr_user_addr <= O_ddr_user_addr + 'd8;      //写数据时地址递增
            else
                O_ddr_user_addr <= O_ddr_user_addr;
    end


endmodule
