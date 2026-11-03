
//========================================================
// 模块：video_out —— 读 DDR → 显示
// 功能：从 DDR 读出帧缓存，跨时钟域（DDR时钟→HDMI像素时钟）送到 HDMI。
//       用读指针（I_video_out_rp）选缓冲区，配合 video_in 的写指针做乒乓。
//========================================================
module video_out (
    input wire        I_rst_n,             //复位，低有效

    input wire        I_ddr_clk,           //DDR 侧时钟
    output wire       O_rd_req,            //读请求（读突发有效，给仲裁器）
    input wire        I_rd_grant,          //读 grant（读使能门控）
    input wire        I_rd_tag,            //读数据来源标签（1=显示读，FIFO 写使能门控）
    output reg [17:0] O_dbg_rd_cnt,        //debug：每帧读总数（SW4 拨上时数码管显示）
    input wire        I_video_in_wr_busy,  //video_in 写忙（写忙时读触发停，恢复官方避让：读数据延迟 40 拍返回，写数据上总线会暂停读数据流 → FIFO 读穿白点）
    output wire [8:0] O_fifo_level,        //等效水位 = FIFO 已写 + 在途（给 bg_read 读门控：水位高 bg 才可读，显示期双阈值错峰防 bg 挤垮显示）
    output wire       O_video_out_rd_busy, //video_out 读忙（保留，兼容）
    input wire[1:0]   I_video_out_rp,      //读指针（读哪个缓冲区，来自 video_in）
    output wire       O_ddr_user_rd_en,    //DDR 读使能
    output reg[24:0]  O_ddr_user_addr,     //DDR 读地址
    input wire        I_ddr_user_ready,    //DDR 就绪
    input wire        I_ddr_user_rd_valid, //DDR 读有效
    input wire[127:0] I_ddr_user_rd_data,  //DDR 读数据（128 位）

    input wire        I_dsi_clk,           //HDMI 像素时钟
    input wire        I_video_vsync,       //场同步
    input wire        I_video_rd_en,       //读使能（HDMI 什么时候要像素）
    output reg[23:0]  O_vdieo_data         //输出像素（24 位 RGB）
);

    reg         S_fifo_rst;         //FIFO 复位
    reg[8:0]    S_fifo_rst_cnt;     //FIFO 复位计数
    wire[8:0]   S_fifo_wr_num;      //FIFO 已写数据个数
    reg[9:0]    S_rd_in_flight;     //在途读数据计数（已发读命令-已落地，修过度读用）
    wire        S_fifo_rd_en;       //FIFO 读使能
    wire[127:0] S_fifo_rd_data;     //FIFO 读数据
    reg         S_video_vsync_1d;   //场同步打拍 1
    reg         S_video_vsync_2d;   //场同步打拍 2
    reg         S_video_vsync_3d;   //场同步打拍 3
    wire        S_video_frame_start;//帧开始
    wire        S_ddr_rd_trig;      //DDR 读触发
    reg         S_ddr_rd_valid;     //DDR 读突发有效
    reg[9:0]    S_ddr_rd_cnt;       //DDR 读计数
    reg[3:0]    S_fifo_rd_cnt;      //FIFO 读计数（解包用）
    reg         S_video_rd_en_1d;   //读使能打拍
    reg[3:0]    S_fifo_rd_cnt_1d;   //FIFO 读计数打拍
    reg[127:0]  S_fifo_rd_data_1d;  //FIFO 读数据打拍
	wire        S_fifo_emtpy;       //FIFO 空

    // 4 个帧缓冲区起始地址（跟 video_in 一致）
    localparam IMAGE_BASE_ADDR_0 = 25'd0;
    localparam IMAGE_BASE_ADDR_1 = 25'd7000000;
    localparam IMAGE_BASE_ADDR_2 = 25'd14000000;
    localparam IMAGE_BASE_ADDR_3 = 25'd21000000;

    //------------ 场同步打 3 拍（检测帧开始的下降沿）------------
    always @(posedge I_ddr_clk) begin
        S_video_vsync_1d <= I_video_vsync;
        S_video_vsync_2d <=S_video_vsync_1d;
        S_video_vsync_3d <= S_video_vsync_2d;
    end

    assign S_video_frame_start = ~S_video_vsync_3d & S_video_vsync_2d;  //场同步下降沿 = 帧开始

    //------------ FIFO 复位（每帧开始复位，保持 300 拍）------------
    // 官方坑：异步 FIFO 复位需 8 个慢时钟周期同步、约 60 拍后才能访问，复位位宽要加宽；
    // bg 命令在 mc FIFO 排队会把 vo 帧尾在途返回拖长（远超 40 拍），
    // 300 拍覆盖「FIFO 复位同步 + bg 残余命令执行拖尾」，残余返回在复位期内全部落地丢弃。
    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            S_fifo_rst <= 1'b0;
        else
            if(S_video_frame_start)
                S_fifo_rst <= 1'b1;
            else if(S_fifo_rst_cnt == 'd300)
                S_fifo_rst <= 1'b0;
            else
                S_fifo_rst <= S_fifo_rst;
    end

    always @(posedge I_ddr_clk) begin
        if(S_fifo_rst)
            S_fifo_rst_cnt <= S_fifo_rst_cnt + 'd1;
        else
            S_fifo_rst_cnt <= 'd0;
    end

    //------------ DDR 读触发（FIFO 剩余空间 >= 300 才读，避免写满丢数据）------------
    // DDR 读出有约 40 拍延时，所以留足余量（每次读 240，FIFO 剩余要 >= 300）
    // 写忙避让（恢复官方）：读写命令不交织，读数据流不被写打断
    // 读满即停已撤销（v2 的 rd_frame_start 3 拍同步导致每行错位 3 拍 = 老师的「前 3 个数丢」假设，
    // 官方原版自然停无此问题）
    // ★修复过度读（2026-10-25 晚）：DDR 读数据 40 拍延迟返回，水位滞后 40 拍，
    //   读批结束时滞后水位仍低 → 立即再触发 → 读节奏跑在消耗前头 → FIFO 满丢弃
    //   → 读计数 1.5 倍（实测 0x3F840=260160 vs 正常 0x2A300=172800）、帧末丢半帧 → 错位花屏
    //   修复：水位判定加上「在途读数据数」（已发命令未落地），等效水位 = wrusedw + 在途
    //   且触发水位从 211 降到 30：读批 240 字结束后等效水位 ~240 远高于 30，
    //   必须等消耗把水位压下去才读下一批 → 批间留出消耗间隙，读节奏 = 消耗节奏
    // ★触发水位 30→200（2026-10-26 bg 读启动后花屏修复）：bg 批 240 拍期间 vo 读触发后最多等
    //   bg 批剩余+WR 批 ≈480 拍（消耗 270 字），水位 30 会被打穿 → 显示 FIFO 空 → 花屏。
    //   200 保证最坏等待（扣 bg 让位后 ≈240 拍耗 134 字）不穿底；批后等效水位 200+240=440<512 不溢出、
    //   且 440>200 批后不立即重触发（过度读修复的「触发水位低于批长」原则依然成立：批间有 240 字消耗间隙）。
    assign S_ddr_rd_trig = ((S_fifo_wr_num + S_rd_in_flight[8:0]) <= 'd220) && (!I_video_in_wr_busy) && (!S_ddr_rd_valid) && (!S_fifo_rst) && I_rst_n ? 1'b1 : 1'b0;   //2026-11-01 bug3：200→220（vo 提前补，锯齿 220~280，配合 bg 门槛 260 扩补读窗口；错峰 40 拍）：与 bg 门控 300 恢复双阈值错峰（二分排除 250/250 同水位竞争嫌疑），200 保证最坏等待不穿底
    // 等效水位引出（bg_read 读门控用：bg 只在 vo 水位 >=300 时读，与 vo 触发水位 200 形成双阈值错峰；
    // 消隐期 vo 不消耗水位自然高 → bg 自动全速，无需窗口信号）
    assign O_fifo_level = S_fifo_wr_num + S_rd_in_flight[8:0];

    // 读数据打 1 拍（声明前移到 in_flight 计数之前——TD 先使用后声明拆网教训）
    reg [127:0] rd_data_d1;
    reg         rd_valid_d1;

    //------------ 在途读数据计数（已发读命令 - 已落地数据，FIFO 复位期清零）------------
    // ⚠️ 2026-10-28 口径修正：递减用 rd_valid_d1 && I_rd_tag（与 FIFO we/discard 同拍对齐）——
    //   原用 rd_valid（未打拍）&& I_rd_tag（打 1 拍）→ tag 恒比数据晚 1 拍 → in_flight 恒多计 1
    //   → vsync 锁存的 discard 数 = 真实残余 +1 → 新帧第 1 字被误丢（tb 实锤：帧头字 0 丢失）。
    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            S_rd_in_flight <= 10'd0;
        else if(S_fifo_rst)
            S_rd_in_flight <= 10'd0;        //复位期在途清零（残余返回落地后丢弃）
        else if(O_ddr_user_rd_en && rd_valid_d1 && I_rd_tag)
            S_rd_in_flight <= S_rd_in_flight;   //同拍发+回，净变化 0
        else if(O_ddr_user_rd_en)
            S_rd_in_flight <= S_rd_in_flight + 10'd1;   //发一个读命令
        else if(rd_valid_d1 && I_rd_tag)
            S_rd_in_flight <= (S_rd_in_flight > 10'd0) ? S_rd_in_flight - 10'd1 : 10'd0;   //数据落地（d1 口径）
        else
            S_rd_in_flight <= S_rd_in_flight;
    end

    //------------ DDR 读突发控制（读 240 个停，官方同款）------------
    // 帧开始（vsync）时强制结束读批：bg_read 改变了读批节奏，读批可能撞上 vsync，
    // 若不强制停，读批剩余命令会带着「帧头地址」读数据（地址已复位），
    // 混在帧尾批后进 FIFO → 画面卷绕错位（视野右边缘绕到屏幕左边）。
    // 帧尾批读一半丢掉无损（数据本就会被 FIFO 复位清掉，下一帧从头读）。
    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            S_ddr_rd_valid <= 1'b0;
        else
            if(S_video_frame_start)                     //帧开始：强制停读批
                S_ddr_rd_valid <= 1'b0;
            else if(O_ddr_user_rd_en && S_ddr_rd_cnt == 'd239)   //读完 240 个
                S_ddr_rd_valid <= 1'b0;
            else if(S_ddr_rd_trig)                          //触发读
                S_ddr_rd_valid <= 1'b1;
            else
                S_ddr_rd_valid <= S_ddr_rd_valid;
    end

    assign O_ddr_user_rd_en = S_ddr_rd_valid & I_ddr_user_ready & I_rd_grant;  //DDR 读使能（grant 门控）
    assign O_rd_req = S_ddr_rd_valid;   //读请求 = 读突发有效（给仲裁器）

    always @(posedge I_ddr_clk) begin
        if(S_ddr_rd_valid)
            begin
                if(O_ddr_user_rd_en)
                    S_ddr_rd_cnt <= S_ddr_rd_cnt + 'd1;
                else
                    S_ddr_rd_cnt <= S_ddr_rd_cnt;
            end
        else
            S_ddr_rd_cnt <= 'd0;
    end

    //------------ DDR 读地址（帧开始按读指针选缓冲区，之后每读一次 +8）------------
    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            O_ddr_user_addr <= 'd0;
        else
            if(S_video_frame_start)
                begin
                    case(I_video_out_rp)            //按读指针选缓冲区
                        'd0: O_ddr_user_addr <= IMAGE_BASE_ADDR_0;
                        'd1: O_ddr_user_addr <= IMAGE_BASE_ADDR_1;
                        'd2: O_ddr_user_addr <= IMAGE_BASE_ADDR_2;
                        'd3: O_ddr_user_addr <= IMAGE_BASE_ADDR_3;
                    endcase
                end
            else if(O_ddr_user_rd_en)
                O_ddr_user_addr <= O_ddr_user_addr + 'd8;  //读数据时地址递增
            else
                O_ddr_user_addr <= O_ddr_user_addr;
    end

    assign O_video_out_rd_busy = S_ddr_rd_trig | S_ddr_rd_valid;  //读忙 = 正在读或准备读

    //------------ debug：每帧读总数计数（vsync 下降沿锁存并复位，SW4 拨上时数码管显示）------------
    // 验证「读写指针碰撞/帧尾被写挡住少读」假设：正常值 0x2A300（=172800）
    // 少读 3 个 = 0x2A2FD（=172797），多读 = >0x2A300
    reg [17:0] dbg_rd_cnt;
    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            dbg_rd_cnt   <= 18'd0;
            O_dbg_rd_cnt <= 18'd0;
        end else begin
            if(S_video_frame_start) begin              //场同步下降沿 = 帧结束
                O_dbg_rd_cnt <= dbg_rd_cnt;            //锁存本帧读总数
                dbg_rd_cnt   <= 18'd0;                 //复位重新计数
            end else if(O_ddr_user_rd_en) begin
                dbg_rd_cnt   <= dbg_rd_cnt + 18'd1;    //每读 1 个 128 位 +1
            end
        end
    end

    //------------ 读数据打 1 拍（打断 DDR 读数据 → FIFO 写的长路径，修 800M 时序贴边）------------
    // 现象：最右列 3 像素噪点、位置固定、帧间闪烁（读突发最后一个数据采样偶发违例）
    // 官方半速 533 时序裕量大无此问题，本工程 800M 裕量小 → 打拍缩短组合路径
    //（声明已前移到 in_flight 计数之前）
    always @(posedge I_ddr_clk) begin
        rd_data_d1  <= I_ddr_user_rd_data;
        rd_valid_d1 <= I_ddr_user_rd_valid;
    end

    //------------ 帧尾批残余丢弃门控（2026-10-28：左边界复制右边界 + 内容右移根因）------------
    // 现象：帧尾批命令在 vsync 时未被完全停住（frame_start 打拍延迟 + 批被 grant 切碎），
    //   其返回被 bg 消隐读命令拖长 → 拖过 FIFO 复位窗（300 拍）后落地 → 帧尾字混入新帧头
    //   → 显示「左边界 = 帧尾内容 + 整帧右移 K 字」（实机 + tb_vo_stream 复现实锤：
    //   帧 0 尾 16 字混入帧 1 头，enc 48~63 排在字 0 之前）。
    // 修复：vsync 拍锁存「上一帧在途读数据数」，之后按序丢弃（DDR 保序：残余先于新帧数据落地），
    //   丢完才放行 FIFO 写——新帧数据零污染，FIFO 复位窗长度不再需要覆盖拖尾。
    reg [9:0] S_discard_cnt;   //帧尾残余待丢弃计数（最大 240+512 在途，10 位够）
    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            S_discard_cnt <= 10'd0;
        else if(S_video_frame_start)
            S_discard_cnt <= S_rd_in_flight[9:0];   //锁存 vsync 拍在途数（= 帧尾批残余，新帧尚未发命令）
        else if(rd_valid_d1 && I_rd_tag && (S_discard_cnt != 10'd0))
            S_discard_cnt <= S_discard_cnt - 1'b1;  //残余落地一个丢一个（标签=vo 的按序到达）
    end
    wire S_vo_we = rd_valid_d1 && I_rd_tag && (S_discard_cnt == 10'd0);   //FIFO 写使能（残余丢弃期间拒写）

    //------------ 跨时钟域 FIFO（DDR 时钟写，HDMI 时钟读）------------
    w128_d512_fifo U_w128_d512_fifo(
        .rst        ( S_fifo_rst          ),

        .clkw       ( I_ddr_clk           ),    //写时钟（DDR 侧）
        .we         ( S_vo_we             ),    //写使能（读有效打拍 && 标签 && 帧尾残余丢弃门控）
        .di         ( rd_data_d1          ),    //写数据（128 位，打 1 拍）
        .wrusedw    ( S_fifo_wr_num       ),
        .afull      (),
        .full_flag  (),

        .clkr       ( I_dsi_clk           ),    //读时钟（HDMI 像素时钟）
        .re         ( S_fifo_rd_en        ),    //读使能
        .dout       ( S_fifo_rd_data      ),    //读数据（128 位）
        .rdusedw    (),
        .valid      (),
        .empty_flag ( S_fifo_emtpy        ),
        .aempty     ()
    );

    //------------ FIFO 读计数（0~15 循环，解包用）------------
    always @(posedge I_dsi_clk) begin
       if(I_video_rd_en)
           S_fifo_rd_cnt <= S_fifo_rd_cnt + 'd1;
       else
           S_fifo_rd_cnt <= 'd0;
    end

    // 每 16 个像素周期里，只在特定位置读 FIFO（因为 128 位 = 5.33 个像素，要跨 beat 拼接）
    assign S_fifo_rd_en = I_video_rd_en && (S_fifo_rd_cnt == 'd0)  ? 1'b1 :
                          I_video_rd_en && (S_fifo_rd_cnt == 'd5)  ? 1'b1 :
                          I_video_rd_en && (S_fifo_rd_cnt == 'd10) ? 1'b1 : 1'b0;

    always @(posedge I_dsi_clk) begin
       S_video_rd_en_1d  <= I_video_rd_en;
       S_fifo_rd_cnt_1d  <= S_fifo_rd_cnt;
       S_fifo_rd_data_1d <= S_fifo_rd_data;
    end

    //------------ 128 位数据流 → 24 位像素流（解包）------------
    // 128 和 24 的最小公倍数是 384，所以每 3 个 128 位 beat = 16 个 24 位像素
    // 每个 128 位 beat 拆出 5 个完整 24 位 + 8 位余数，余数跟下一个 beat 拼
    always @(posedge I_dsi_clk) begin
       if(S_video_rd_en_1d)
           begin
               case(S_fifo_rd_cnt_1d)
                   'd0: O_vdieo_data  <= S_fifo_rd_data[127:104];
                   'd1: O_vdieo_data  <= S_fifo_rd_data[103:80];
                   'd2: O_vdieo_data  <= S_fifo_rd_data[79:56];
                   'd3: O_vdieo_data  <= S_fifo_rd_data[55:32];
                   'd4: O_vdieo_data  <= S_fifo_rd_data[31:8];
                   'd5: O_vdieo_data  <= {S_fifo_rd_data_1d[7:0],S_fifo_rd_data[127:112]};  //跨 beat 拼接
                   'd6: O_vdieo_data  <= S_fifo_rd_data[111:88];
                   'd7: O_vdieo_data  <= S_fifo_rd_data[87:64];
                   'd8: O_vdieo_data  <= S_fifo_rd_data[63:40];
                   'd9: O_vdieo_data  <= S_fifo_rd_data[39:16];
                   'd10: O_vdieo_data <= {S_fifo_rd_data_1d[15:0],S_fifo_rd_data[127:120]}; //跨 beat 拼接
                   'd11: O_vdieo_data <= S_fifo_rd_data[119:96];
                   'd12: O_vdieo_data <= S_fifo_rd_data[95:72];
                   'd13: O_vdieo_data <= S_fifo_rd_data[71:48];
                   'd14: O_vdieo_data <= S_fifo_rd_data[47:24];
                   'd15: O_vdieo_data <= S_fifo_rd_data[23:0];
               endcase
           end
       else
           O_vdieo_data <= 'd0;
    end


endmodule
