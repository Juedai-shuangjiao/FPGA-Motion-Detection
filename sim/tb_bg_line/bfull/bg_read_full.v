//========================================================
// 模块：bg_read —— 消隐期读状态机（主线第 2~3 步）
// 功能：HDMI 场消隐期（4.2ms）内从 DDR 读「当前帧 + 背景帧」两帧非对称半帧（上1/4/下3/4，B 半 261120 个 128bit），
//       逐像素比较（任一通道 |cur−bg| > 阈值 40 判前景），前景标记（1bit/像素）打包
//       40bit 写片内 ERAM（fg_mark_eram 的 A 口，40bit×23040）。
//       显示期 DDR 归还显示读/采集写（官方两路配置），消隐期读与显示读天然错峰不竞争。
// 节奏：行块交替读（cur 行 240 个 128bit → bg 行 240 个 128bit → 比较 → 下一行）。
//       读两帧预算 3.57ms < 消隐期 4.2ms（带宽模型验证）。
// 数据流：读返回按顺序路由（mod 480 计数）：前 240 个写 cur FIFO、后 240 个写 bg FIFO；
//       两 FIFO 按 3/4 节流同步弹出 → 各自 128→96 解包 → 96bit 逐拍比较（4 像素/拍）；
//       每 10 个 96bit 攒 40bit 前景标记字，写 ERAM 地址 0~23039 顺序递增（行对齐自动）。
//========================================================
module bg_read (
    input  wire        I_rst_n,             //复位，低有效
    input  wire        I_ddr_clk,           //DDR 侧时钟（usr_clk 100M）
    input  wire        I_frame_start,       //帧开始脉冲（DDR 域，vsync 打拍）：启动本帧读
    input  wire [1:0]  I_video_out_rp,      //读指针（当前帧所在乒乓块）
    input  wire        I_bg_grant,          //串行仲裁背景读时间片（1=本通道可发命令）
    input  wire        I_rd_tag,            //读返回来源标签（1=显示读 0=背景读；2026-10-29 起 bg 收数弃用标签改在途窗口，端口保留兼容顶层接线）
    input  wire [8:0]  I_vo_fifo_level,     //video_out 等效水位（FIFO已写+在途）：显示期 >=300 才允许 bg 读（双阈值错峰防挤垮显示）
    input  wire        I_disp_win,          //显示期电平（S_hdmi_de 跨域打拍）：消隐期 vo 不消耗水位冻结，水位门控必须放行否则 bg 饿死整个消隐期
    input  wire        I_video_in_wr_busy,  //写命令拍精确避让（2026-10-28 恢复三轮下板修复：写命令打 1 拍，写批 valid 降拍后写命令仍在发，本拍 bg 读命令会被写优先吞掉 → rd_total 多计 1 → 计数错乱/标签压弹错位 → 错位+水管涂白+FC88 全链根因）
    input  wire [1:0]  I_thr_sel,           //减背景阈值档位（顶层 SW1/SW2）：00=25 01=40 10=60 11=80
    input  wire        I_ddr_user_ready,    //DDR 就绪
    input  wire        I_ddr_user_rd_valid, //DDR 读有效
    input  wire[127:0] I_ddr_user_rd_data,  //DDR 读数据（128 位）
    output reg         O_ddr_user_rd_en,    //DDR 读使能
    output reg [24:0]  O_ddr_user_addr,     //DDR 读地址
    output wire        O_bg_rd_busy,        //背景读批进行中（串行仲裁用，批边界 1 拍空隙）
    //------------ 前景标记 ERAM 写接口（A 口，40bit×23040）------------
    output reg  [14:0] O_fg_wr_addr,        //ERAM 写地址 0~23039
    output reg  [39:0] O_fg_wr_data,        //ERAM 写数据（40 像素前景标记）
    output reg         O_fg_wr_en,          //ERAM 写使能
    output reg         O_fg_init,           //首轮写满标志（叠加使能，跨时钟域同步由顶层做）
    output reg  [18:0] O_dbg_rd_cnt,        //debug：本帧读 beat 总数（A 帧 88320 / B 帧 261120）
    output reg  [14:0] O_dbg_first_addr,    //debug：首字写拍锁存地址（q 侧拍前值，A 半应 0 / B 半应 5632）
    output reg  [39:0] O_dbg_first_data,    //debug：首字写拍锁存数据（10-31 加：错位拍数诊断，手在最左4px时应0xF）
    output wire        O_dbg_vo_room,    //debug：显示期水位门控判定（ChipWatcher 抓损耗）
    output wire        O_dbg_abort,      //debug：帧头清场标志
    output wire        O_dbg_drain,      //debug：DRAIN 排空进行中（morph 链尾排空）
    output reg  [1:0]  O_dbg_first_half,    //debug：首字写拍所在半帧（0=A 1=B）
    output reg         O_dbg_first_valid    //debug：首字写拍已锁存脉冲
);
    // 写数据链延迟补偿参数（2026-10-31 诊断v4配套：错位N拍→填N；0=直通）
    parameter [3:0] DATA_DLY = 4'd0;
    // 写地址链延迟补偿参数（双向覆盖：内容晚N拍时地址链加N拍；0=直通）
    parameter [3:0] ADDR_DLY = 4'd0;

    //------------ 数据链延迟链（DATA_DLY 拍，40bit×16 级移位）------------
    reg [39:0] S_fg_wr_data_d [0:15];
    integer ddl;
    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            for(ddl=0; ddl<16; ddl=ddl+1) S_fg_wr_data_d[ddl] <= 40'd0;
        end else begin
            S_fg_wr_data_d[0] <= S_fg_wr_data_int;
            for(ddl=1; ddl<16; ddl=ddl+1) S_fg_wr_data_d[ddl] <= S_fg_wr_data_d[ddl-1];
        end
    end

    //------------ 地址链延迟链（ADDR_DLY 拍，15bit×16 级移位）------------
    reg [14:0] S_fg_wr_addr_d [0:15];
    integer adl;
    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            for(adl=0; adl<16; adl=adl+1) S_fg_wr_addr_d[adl] <= 15'd0;
        end else begin
            S_fg_wr_addr_d[0] <= S_fg_wr_addr_int;
            for(adl=1; adl<16; adl=adl+1) S_fg_wr_addr_d[adl] <= S_fg_wr_addr_d[adl-1];
        end
    end

    localparam IMAGE_BASE_ADDR_4 = 25'd22382400;   //背景缓冲区起始地址
    localparam LINE_BEAT         = 9'd240;          //一行 128bit 个数（1280 像素 ×96/128）
    localparam HALF_FULL_LINES     = 10'd720;          //整帧读行数（行 0~719，无分段——根治交界撕裂+停止线）
    localparam TOTAL_BEAT_FULL     = 345600;           //整帧读量：720 行 × 480 拍 = 3.46ms（<消隐 4.2ms，波形实测占空比 99% 支撑）
    localparam THRESHOLD_25       = 8'd25;           //减背景阈值档位（任一通道 |Δ| > 阈值 判前景）
    localparam THRESHOLD_40       = 8'd40;
    localparam THRESHOLD_60       = 8'd60;
    localparam THRESHOLD_80       = 8'd80;
    // 阈值拨码可调（2026-10-27 白斑/手洞现场调参）：SW1/SW2 组合四档

    // ⚠️ 以下 wire 必须先声明后使用（TD 对「先使用后声明 + 带初始化 wire」会拆成两个网，
    //    隐式网无驱动被接 0 → 功能全断；iverilog 会合并所以仿真正常。教训：wire 一律先声明，
    //    驱动放 assign，别用「声明即赋值」且放在使用之后）
    wire        S_fifo_re;             //两 FIFO 弹使能（3/4 节流，行弹控制）
    wire        S_unpack_frame_start;  //解包帧头复位（本消隐期第一次弹）

    //------------ 读使能门控：显示期 vo 等效水位 >=300 才读（2026-10-26 花屏修复）------------
    // bg 批 240 拍期间 vo 读触发后要等仲裁轮转，水位 30 会被打穿 → 花屏。
    // 双阈值错峰：vo 水位 <=200 触发读批（video_out 内），bg 水位 >=300 才读——
    // vo 缓冲充足 bg 才占时间片，vo 快空时 bg 自动让路。
    // ⚠️ 2026-10-26 晚修正：消隐期 vo 不消耗 → 水位冻结在显示期末值（可能 <300）→ 原「消隐期水位自然高」假设不成立，
    //    bg 被门控饿死整个消隐期（仿真实测：vsync 时水位 269 → bg 等 5 万拍到显示期 vo 读批才启动）。
    //    修复：显示期（I_disp_win=1）才做水位门控，消隐期（de 低，vo 不消耗）直接放行 bg 全速读。
    wire S_vo_room = I_disp_win ? (I_vo_fifo_level >= 9'd260) : 1'b1;   //显示期水位门控（2026-11-01 bug3：300→260 扩补读窗口——vo 触发 220 与 bg 门槛 260 错峰 40 拍防同水位竞争），消隐期放行
    assign O_dbg_vo_room = S_vo_room;   //ChipWatcher 观测

    //------------ 读返回 valid 打 1 拍（对齐 rd_tag 的 1 拍延迟）------------
    // 标签 FIFO 同步读输出 rd_tag 比 rd_valid 晚 1 拍（vo 用 rd_valid_d1 对齐，bg 原用 rd_valid 直接配 → 错 1 拍，
    // 每批 240 拍边界丢 1 收 1 = 1/240 数据污染）。打拍后 rd_tag 与 valid_d1 同拍对齐，批边界干净。
    reg        S_rd_valid_d1;
    reg [127:0] S_rd_data_d1;
    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_rd_valid_d1 <= 1'b0;
            S_rd_data_d1  <= 128'd0;
        end else begin
            S_rd_valid_d1 <= I_ddr_user_rd_valid;
            S_rd_data_d1  <= I_ddr_user_rd_data;
        end
    end

    //------------ 读状态机（消隐期触发，行块交替读两帧非对称半帧）------------
    reg        S_rd_phase;     //0=读当前帧行 1=读背景行
    reg  [7:0] S_rd_seg_cnt;   //段内读命令计数 0~239
    reg  [17:0] S_frame_off;   //帧内 128bit 偏移 0~172799（cur/bg 共用，行号×240）
    reg  [18:0] S_rd_total;    //读命令总数（整帧 0~345599）
    reg        S_rd_active;    //本消隐期读进行中（trig 拉高，读满/显示期开始停）
    reg        S_accept_ret;   //（退役：收数改标签门控 I_rd_tag）
    wire [18:0] S_total_cap = 19'd345600;    //整帧读量上限（恒值，无分段）
    reg [18:0] S_total_cap_reg;   //cap 锁存（与 S_total_cap 同值，读满判据用拍前锁存保持一致）
    always @(posedge I_ddr_clk) S_total_cap_reg <= S_total_cap;

    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_rd_active  <= 1'b0;
            
            S_rd_phase   <= 1'b0;
            S_rd_seg_cnt <= 8'd0;
            S_frame_off  <= 18'd0;
            S_rd_total   <= 19'd0;
        end else begin
            if(I_frame_start) begin
                S_rd_active  <= 1'b1;   //帧开始：启动本帧读（读满停，下帧重启）
                S_rd_total   <= 19'd0;  //本帧读计数清零
                S_rd_phase   <= 1'b0;
                S_rd_seg_cnt <= 8'd0;
                S_frame_off  <= 18'd0;
            end else if((S_rd_total == S_total_cap_reg - 1'b1) && O_ddr_user_rd_en && I_ddr_user_ready) begin
                S_rd_active  <= 1'b0;   //发出最后一个读命令，停（整帧读满，下帧头重启）
            end

            if(O_ddr_user_rd_en && I_ddr_user_ready) begin  //发一个读命令
                if(S_rd_seg_cnt == LINE_BEAT - 1'b1) begin  //段满 240
                    S_rd_seg_cnt <= 8'd0;
                    if(S_rd_phase)
                        S_frame_off <= S_frame_off + LINE_BEAT; //bg 行读完，偏移推进一行
                    S_rd_phase <= ~S_rd_phase;              //cur↔bg 交替
                end else
                    S_rd_seg_cnt <= S_rd_seg_cnt + 1'b1;
                S_rd_total <= S_rd_total + 1'b1;            //到本半帧上限停（rd_en 条件已封顶）
            end
        end
    end

    //------------ 读满标志锁存（2026-10-28 非对称半帧修复）------------
    // half_sel 在读满拍立即翻转 → S_total_cap 组合立即变另一半上限 →
    // DRAIN 触发判据 (S_rd_total == S_total_cap) 恒不成立 → DRAIN 失效 → 每半帧尾 65 字丢弃
    //（对称半帧版两半上限相同没暴露；非对称版 A/B 上限 88320/261120 不同则必中）。
    // 加独立锁存 S_full_done：读满拍置 1、帧开始清 0，DRAIN 判据改用它（与 half_sel 翻转同拍，不随 cap 变）。
    reg S_full_done;
    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            S_full_done <= 1'b0;
        else if(I_frame_start)
            S_full_done <= 1'b0;
        else if((S_rd_total == S_total_cap_reg - 1'b1) && O_ddr_user_rd_en && I_ddr_user_ready)
            S_full_done <= 1'b1;
    end

    //------------ 批边界（240 拍一批，批边界 1 拍空隙给串行仲裁切换）------------
    // bg 在时间片内每批读 240 拍，批满降 busy 1 拍 → 仲裁切走 → 下一轮时间片继续下一批
    reg batch_gap;
    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            batch_gap <= 1'b0;
        else if(O_ddr_user_rd_en && I_ddr_user_ready && S_rd_seg_cnt == LINE_BEAT - 1'b1)
            batch_gap <= 1'b1;    //第 240 拍 = 批边界
        else
            batch_gap <= 1'b0;
    end
    // 帧开始清场（300 拍，与 video_out FIFO 复位同宽）：FIFO 复位清残余 + 解包复位清 pending +
    // 弹链复位。清场期间停读（返回数据会被 FIFO 复位丢弃）。读满帧时 FIFO 已弹空清场无害（仅延迟启动 3µs），
    // 读不满帧时清场把半行残留数据丢弃、新帧从头读——消除跨帧错位。
    reg [8:0] S_abort_cnt;
    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            S_abort_cnt <= 9'd0;
        else if(I_frame_start)
            S_abort_cnt <= 9'd300;
        else if(S_abort_cnt != 9'd0)
            S_abort_cnt <= S_abort_cnt - 1'b1;
    end
    wire S_abort_active = (S_abort_cnt != 9'd0);
    assign O_dbg_abort   = S_abort_active;   //ChipWatcher 观测
    wire S_fifo_abort   = S_abort_active;   //FIFO 复位（清残余）
    wire S_unpack_abort = S_abort_active;   //解包复位（清 pending）

    assign O_bg_rd_busy = S_rd_active && !batch_gap && S_vo_room && !S_abort_active;   //vo 水位不足/清场期降 busy 让仲裁跳过 BG

    //------------ 读使能（串行仲裁：时间片内每拍发命令，读满停；vo 水位门控；清场期停读；写拍精确避让）------------
    always @(*) begin
        O_ddr_user_rd_en = S_rd_active && I_bg_grant && I_ddr_user_ready && S_vo_room &&
                           !S_abort_active && !I_video_in_wr_busy &&
                           (S_rd_total != S_total_cap);
    end

    // 读地址辅助：当前帧基址（按读指针选乒乓块），整帧读无段偏移
    reg [24:0] S_cur_base;
    always @(*) begin
        case(I_video_out_rp)
            2'd0 : S_cur_base = 25'd0;
            2'd1 : S_cur_base = 25'd7000000;
            2'd2 : S_cur_base = 25'd14000000;
            2'd3 : S_cur_base = 25'd21000000;
            default : S_cur_base = 25'd0;
        endcase
    end

    // 读地址（2026-10-26 重大修复：原实现行内不递增——240 个命令发同一地址，
    // 读回 240 个相同字 → cur/bg 比较数据全错 → 实机白线飘/手成线不成块。
    // 现改为命令拍递增 +8（16bit 地址单位：128bit 字 = 8 单位），段尾按 cur/bg 交替切换基址，与 video_out 同款节奏）
    // 注意打拍相位：地址在「发命令拍」更新（非阻塞），下一命令伴随新地址——第 k 个命令地址 = 段起点 + (k-1)×8
    // 2026-10-28 非对称半帧读：A 半读行 0~183、B 半读行 176~719（交界重叠 8 行每帧更新 → 中线撕裂消除，撕裂点移到上部 1/4）
    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            O_ddr_user_addr <= 25'd0;
        else if(I_frame_start)
            O_ddr_user_addr <= S_cur_base;   //本帧第一个命令地址 = 帧起点
        else if(O_ddr_user_rd_en && I_ddr_user_ready) begin
            if(S_rd_seg_cnt == LINE_BEAT - 1'b1) begin    //段尾：下一命令切行
                if(S_rd_phase)   //bg 段完 → 下一 cur 行（offset 推进一行，frame_off 拍末 +240 与此同拍一致）
                    O_ddr_user_addr <= S_cur_base + (({1'b0, S_frame_off} + LINE_BEAT) << 3);
                else             //cur 段完 → 同 offset 的 bg 行
                    O_ddr_user_addr <= IMAGE_BASE_ADDR_4 + (S_frame_off << 3);
            end else
                O_ddr_user_addr <= O_ddr_user_addr + 25'd8;   //行内 128bit 字递增（16bit 地址单位 +8）
        end
    end

    //------------ 读返回路由（标签门控，2026-10-29 恢复）------------
    // 返回顺序与命令顺序严格一致（DDR 保序），与读命令暂停/延迟无关；
    // 收数门控 = 标签（I_rd_tag=0 背景读返回）。⚠️ 标签 FIFO 必须用 TD 的 FIFO IP 实现
    // （读延迟固定 1 拍）——reg 数组实现会被 TD 综合成 BRAM、读延迟多 1 拍 → rd_tag 与
    // rd_valid_d1 对齐错 1 拍 → ret_total 少计 → 帧头误丢 1 字 → cur 数据左移 40 像素
    // （实机水管涂白偏左+卷绕+白点根因）。在途窗口方案（S_bg_inflight）已实验否决：
    // 帧内 vo 读批尾 40 拍返回与 bg 批开始重叠、600 拍启动延迟挡不住帧内交替（real tb mis 10172）。
    // ⚠️ 2026-10-28 帧尾在途丢弃：vsync 前 bg 批命令在途，其返回拖过清场窗（300 拍）后落地
    //    → 混入新帧 mod 路由 → cur/bg 分界错位 → 比较数据错位（实机水管误涂白/涂白错位）。
    //    修复：帧开始拍锁存「上一帧在途返回数」（已发命令-已收返回），之后按序丢弃（DDR 保序），
    //    丢完才让 mod 计数——新帧路由零污染。
    reg [9:0]  S_pend_discard;   //帧尾在途返回待丢弃计数
    reg [8:0]  S_ret_mod;    //0~479
    reg [18:0] S_ret_total;  //返回总数（= 本半帧上限）
    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_pend_discard <= 10'd0;
            S_ret_mod   <= 9'd0;
            S_ret_total <= 19'd0;
        end else if(I_frame_start) begin
            // 帧开始无条件复位（2026-10-26 白线错位修复）：原条件 !S_rd_active 在读不满帧时
            // 不成立 → mod 跨帧累积 → cur/bg 分界错乱 → 标记数据错位（实机白线飘+手成线不成块）。
            // 读不满时整帧数据作废（配合清场），无条件复位从新帧头重来。
            S_pend_discard <= S_rd_total[9:0] - S_ret_total[9:0];   //锁存上一帧在途返回数（10 位够）
            S_ret_mod   <= 9'd0;
            S_ret_total <= 19'd0;
        end else if(S_rd_valid_d1 && !I_rd_tag) begin
            // 2026-10-28 口径修正：ret_total 总是计数（含清场期落地 + 残余丢弃拍）——
            //   它是「已收返回总数」，帧开始锁存 pend = rd_total - ret_total 才等于真实在途数；
            //   清场期不计数会让锁存多算（把已丢的当在途）→ 新帧前 N 字被误丢（tb_bg_align2 实锤 mis 1277）。
            //   mod 仍门控清场（20.27 白块修复：清场期在途返回不参与新帧 cur/bg 路由）。
            S_ret_total <= S_ret_total + 1'b1;
            if(S_pend_discard != 10'd0) begin
                S_pend_discard <= S_pend_discard - 1'b1;   //残余丢弃拍（不参与 mod 路由）
            end else if(!S_abort_active) begin
                S_ret_mod <= (S_ret_mod == 9'd479) ? 9'd0 : S_ret_mod + 1'b1;   //正常收数拍
            end
            // 清场期且残余已清完：新帧尚未发命令，理论上无 bg 返回可到；偶发则忽略（防 mod 污染）
        end
    end
    wire S_ret_is_cur = (S_ret_mod < LINE_BEAT);   //当前帧返回


    //------------ 两个 FIFO 缓存一行（cur/bg 各 240 深，用现成 w128_d512_fifo）------------
    wire        S_cur_fifo_valid, S_bg_fifo_valid;
    wire [127:0] S_cur_fifo_dout, S_bg_fifo_dout;
    wire [8:0]  S_cur_fifo_num, S_bg_fifo_num;

    w128_d512_fifo U_cur_fifo (
        .rst        ( ~I_rst_n | S_fifo_abort    ),   //复位（高有效；显示期开始清残余）
        .clkw       ( I_ddr_clk                ),   //写时钟（DDR 侧）
        .we         ( S_rd_valid_d1 && S_ret_is_cur && !I_rd_tag ),   //写使能（当前帧返回，标签门控，valid 打 1 拍对齐 rd_tag）
        .di         ( S_rd_data_d1               ),   //写数据
        .wrusedw    ( S_cur_fifo_num           ),
        .afull      (),
        .full_flag  (),
        .clkr       ( I_ddr_clk                ),   //读时钟（同域）
        .re         ( S_fifo_re                ),   //读使能（3/4 节流）
        .dout       ( S_cur_fifo_dout          ),
        .rdusedw    (),
        .valid      ( S_cur_fifo_valid         ),
        .empty_flag (),
        .aempty     ()
    );

    w128_d512_fifo U_bg_fifo (
        .rst        ( ~I_rst_n | S_fifo_abort    ),
        .clkw       ( I_ddr_clk                ),
        .we         ( S_rd_valid_d1 && !S_ret_is_cur && !I_rd_tag ),  //写使能（背景返回，标签门控，valid 打 1 拍对齐 rd_tag）
        .di         ( S_rd_data_d1               ),
        .wrusedw    ( S_bg_fifo_num            ),
        .afull      (),
        .full_flag  (),
        .clkr       ( I_ddr_clk                ),
        .re         ( S_fifo_re                ),
        .dout       ( S_bg_fifo_dout           ),
        .rdusedw    (),
        .valid      ( S_bg_fifo_valid          ),
        .empty_flag (),
        .aempty     ()
    );

    //------------ 3/4 节流（解包输入节奏：每 4 拍弹 3 拍）------------
    // 行弹控制：行开始（cur 攒满 240 且 bg 非空）→ 弹满 240 对 → 复位等下一行。
    // 注意不能直接拿「cur_fifo_num>=240」当持续条件——弹 1 个就 <240 会立刻停。
    reg [1:0] S_34_cnt;
    reg [7:0] S_row_pop_cnt;   //行内已弹对数 0~239
    reg       S_row_gap;       //行尾强制空洞（给解包 pending D 输出留拍）
    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_34_cnt      <= 2'd0;
            S_row_pop_cnt <= 8'd0;
            S_row_gap     <= 1'b0;
        end else begin
            if(S_abort_active) begin
                S_34_cnt      <= 2'd0;   //清场：弹链复位（节流相位/行弹计数/行尾空洞全清）
                S_row_pop_cnt <= 8'd0;
                S_row_gap     <= 1'b0;
            end else begin
                S_34_cnt <= S_34_cnt + 1'b1;
                if(S_fifo_re) begin
                    S_row_pop_cnt <= (S_row_pop_cnt == LINE_BEAT - 1'b1) ? 8'd0 : S_row_pop_cnt + 1'b1;
                    if(S_row_pop_cnt == LINE_BEAT - 1'b1)
                        S_row_gap <= 1'b1;   //行尾最后一对弹出，下拍强制留空洞给 pending D 输出
                end
                if(S_row_gap && (S_34_cnt == 2'd0))
                    S_row_gap <= 1'b0;       //空洞拍已过（且 cnt 相位归 0），恢复弹
            end
        end
    end
    // 行弹使能：行开始（cur 攒满 240 且 bg 非空）；行进行中需两 FIFO 都非空
    //（写忙会打断读返回，行尾 FIFO 可能临时空——空拍不弹、数据晚到后继续弹，行边界不错乱）
    // ⚠️ 2026-10-26 深夜修复：门控计数不能用 FIFO wrusedw——TD 软 FIFO 的 wrusedw 是
    //    读指针经异步同步链延迟 2~3 拍的值，行弹追尾（弹速 0.75 > 写速 0.55）时门控晚
    //    2~3 拍才见空 → 每行多弹 2~3 字 → FIFO 下溢弹 X → |X−数据| 比较不定 → 前景标记乱涂
    //    （实机白线飘/手成密集线即此表现）。改用 bg_read 内部实时计数（写口径与 FIFO we
    //    完全一致、弹口径 = S_fifo_re，同拍写弹相消）。
    reg [8:0] S_cur_cnt, S_bg_cnt;   //本地实时计数（替代 wrusedw 门控）
    wire S_ret_hit_cur = S_rd_valid_d1 &&  S_ret_is_cur && !I_rd_tag;   //本拍 cur 写（与 U_cur_fifo.we 同口径）
    wire S_ret_hit_bg  = S_rd_valid_d1 && !S_ret_is_cur && !I_rd_tag;   //本拍 bg 写（与 U_bg_fifo.we 同口径）
    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_cur_cnt <= 9'd0;
            S_bg_cnt  <= 9'd0;
        end else if(S_abort_active) begin
            S_cur_cnt <= 9'd0;   //清场：FIFO 复位，本地计数同步清零
            S_bg_cnt  <= 9'd0;
        end else begin
            S_cur_cnt <= S_cur_cnt + S_ret_hit_cur - S_fifo_re;   //同拍写弹相消（re 两 FIFO 同弹）
            S_bg_cnt  <= S_bg_cnt  + S_ret_hit_bg  - S_fifo_re;
        end
    end
    wire S_row_go = (S_row_pop_cnt == 8'd0) ? ((S_cur_cnt >= LINE_BEAT) && (S_bg_cnt >= 1'b1))
                                            : ((S_row_pop_cnt < LINE_BEAT) && (S_cur_cnt >= 1'b1) && (S_bg_cnt >= 1'b1));
    assign S_fifo_re = (S_34_cnt != 2'd0) && S_row_go && !S_row_gap;

    //------------ 128→96 解包（两路，帧头复位对齐打包相位）------------
    // 注意：解包输入 valid 必须接 FIFO 的 valid 输出（与 dout 同拍、均延迟 1 拍），
    //       不能接弹信号 S_fifo_re（re 当拍数据还没出来，会错位 1 拍：帧头数据垃圾、帧尾丢数据）。
    // ⚠️ 2026-10-27 修复：帧头复位从「首弹拍」（S_fifo_re && S_cmp_first）提前到「帧开始拍」——
    //    解包的帧头清 pending 必须在首弹前生效（首弹前 ~900 拍无输入，pending_valid 上电 X
    //    会走 else if(X) 分支输出 X 垃圾污染 morph 链）。提前复位不破坏相位：首弹前无输入，
    //    S_cnt 保持 0，首弹第一个 128bit 仍从 cnt=0 解出 A，与打包相位对齐不变。
    assign S_unpack_frame_start = I_frame_start;

    wire [95:0] S_cur_96, S_bg_96;
    wire        S_cur_96_valid, S_bg_96_valid;

    data_128bit_to_96bit U_unpack_cur (
        .I_clk             ( I_ddr_clk                     ),
        .I_rst_n           ( I_rst_n && !S_unpack_abort    ),   //显示期开始拉低 1 拍：清 pending
        .I_128b_frame_start( S_unpack_frame_start          ),
        .I_128b_valid      ( S_cur_fifo_valid              ),
        .I_128b_data       ( S_cur_fifo_dout               ),
        .O_96b_frame_start (),
        .O_96b_valid       ( S_cur_96_valid                ),
        .O_96b_data        ( S_cur_96                      )
    );

    data_128bit_to_96bit U_unpack_bg (
        .I_clk             ( I_ddr_clk                     ),
        .I_rst_n           ( I_rst_n && !S_unpack_abort    ),
        .I_128b_frame_start( S_unpack_frame_start          ),
        .I_128b_valid      ( S_bg_fifo_valid               ),
        .I_128b_data       ( S_bg_fifo_dout                ),
        .O_96b_frame_start (),
        .O_96b_valid       ( S_bg_96_valid                 ),
        .O_96b_data        ( S_bg_96                       )
    );

    //------------ 逐像素比较（4 像素/拍）→ 4bit 前景标记 ------------
    // 96bit 位序：[23:0]=像素0(最左) … [95:72]=像素3(最右)，cur/bg 同偏移天然对齐
    wire [7:0] cr0 = S_cur_96[23:16], cg0 = S_cur_96[15:8],  cb0 = S_cur_96[7:0];
    wire [7:0] cr1 = S_cur_96[47:40], cg1 = S_cur_96[39:32], cb1 = S_cur_96[31:24];
    wire [7:0] cr2 = S_cur_96[71:64], cg2 = S_cur_96[63:56], cb2 = S_cur_96[55:48];
    wire [7:0] cr3 = S_cur_96[95:88], cg3 = S_cur_96[87:80], cb3 = S_cur_96[79:72];
    wire [7:0] br0 = S_bg_96[23:16],  bg0 = S_bg_96[15:8],  bb0 = S_bg_96[7:0];
    wire [7:0] br1 = S_bg_96[47:40],  bg1 = S_bg_96[39:32], bb1 = S_bg_96[31:24];
    wire [7:0] br2 = S_bg_96[71:64],  bg2 = S_bg_96[63:56], bb2 = S_bg_96[55:48];
    wire [7:0] br3 = S_bg_96[95:88],  bg3 = S_bg_96[87:80], bb3 = S_bg_96[79:72];

    wire [7:0] d0r = (cr0 > br0) ? (cr0 - br0) : (br0 - cr0);
    wire [7:0] d0g = (cg0 > bg0) ? (cg0 - bg0) : (bg0 - cg0);
    wire [7:0] d0b = (cb0 > bb0) ? (cb0 - bb0) : (bb0 - cb0);
    wire [7:0] d1r = (cr1 > br1) ? (cr1 - br1) : (br1 - cr1);
    wire [7:0] d1g = (cg1 > bg1) ? (cg1 - bg1) : (bg1 - cg1);
    wire [7:0] d1b = (cb1 > bb1) ? (cb1 - bb1) : (bb1 - cb1);
    wire [7:0] d2r = (cr2 > br2) ? (cr2 - br2) : (br2 - cr2);
    wire [7:0] d2g = (cg2 > bg2) ? (cg2 - bg2) : (bg2 - cg2);
    wire [7:0] d2b = (cb2 > bb2) ? (cb2 - bb2) : (bb2 - cb2);
    wire [7:0] d3r = (cr3 > br3) ? (cr3 - br3) : (br3 - cr3);
    wire [7:0] d3g = (cg3 > bg3) ? (cg3 - bg3) : (bg3 - cg3);
    wire [7:0] d3b = (cb3 > bb3) ? (cb3 - bb3) : (bb3 - cb3);

    reg [7:0] S_thr;
    always @(*) begin
        case(I_thr_sel)
            2'd0 : S_thr = THRESHOLD_25;
            2'd1 : S_thr = THRESHOLD_40;
            2'd2 : S_thr = THRESHOLD_60;
            default : S_thr = THRESHOLD_80;
        endcase
    end
    wire [3:0] S_mark_4p = {
        ((d3r > S_thr) || (d3g > S_thr) || (d3b > S_thr)),
        ((d2r > S_thr) || (d2g > S_thr) || (d2b > S_thr)),
        ((d1r > S_thr) || (d1g > S_thr) || (d1b > S_thr)),
        ((d0r > S_thr) || (d0g > S_thr) || (d0b > S_thr))
    };

    //------------ 帧开始 512 日历拍延迟（对齐 morph 输出流，2026-10-27 改）------------
    // morph 总延迟 = 644 有效拍（valid 链与数据同深，2026-10-28 修正：原 643 口径少 1 拍），
    // 帧尾 644 拍数据在帧间断层不推进（valid 门控链），
    // 只能由清链丢弃（每半帧丢底部 2 行，fg_init 判据已放宽）。本延迟链的作用 =
    // 让清链落在「旧帧数据已排空/丢弃完成」且「新帧数据尚未到达」的空窗：
    // 新帧首数据 ≥ vsync+600 拍（清场 300 + FIFO 攒行），512 < 600 ✓ 清链不误伤新帧头。
    // 位向量拼接移位（与 reg 数组链等价，仿真快、综合省）
    reg [511:0] fs_chain;
    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            fs_chain <= 512'd0;
        else
            fs_chain <= {fs_chain[510:0], I_frame_start};
    end
    wire S_fs_d512 = fs_chain[511];   //延迟 512 日历拍的帧开始脉冲

    //------------ 帧尾排空状态机（2026-10-28 黑线根治 + 重叠半帧读）------------
    // morph 帧尾 644 有效拍数据在帧间断层排不出（valid 门控链冻结）→ 清链丢弃 →
    //   每帧尾 65 字（约 2 行）标记永不更新。非对称半帧读下：A 半尾丢行 182/183（交界重叠区内，由 B 半每帧更新覆盖，无感）、
    //   B 半尾丢行 718/719 尾（屏幕最底部 2 行，无感）；交界行 176~183 由两半每帧交替更新 → 中线无黑线。
    // 修复：读满（本半帧上限）+ 两 FIFO 弹空 + 解包尾排空（valid 拉低再等 8 拍）后，
    //   进入 DRAIN 状态 644 拍——morph I_valid 强制拉高（假拍），链内滞留的真实标记
    //   自然排出 → 攒字器照收。
    //   假拍输入的 0 数据需 644 拍才到链尾，DRAIN 恰 644 拍结束 → 假数据不输出，零污染。
    //   读满早于 vsync ~2.4ms（消隐期全速 1.74ms 读完），排空窗口充裕；
    //   读不满帧无 DRAIN（丢尾退回旧行为）；DRAIN 期间 vsync 到 → 清链中断丢尾（无害）。
    //   S_drained 防重入：DRAIN 完成后读满条件仍成立，不置标志会无限重触发 → 假数据写越界。
    reg        S_drain_active;
    assign O_dbg_drain = S_drain_active;   //ChipWatcher 观测
    reg        S_wait_drain;
    reg        S_drained;
    reg [9:0]  S_drain_cnt;
    reg [3:0]  S_wait_cnt;
    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_drain_active <= 1'b0;
            S_wait_drain   <= 1'b0;
            S_drained      <= 1'b0;
            S_drain_cnt    <= 10'd0;
            S_wait_cnt     <= 4'd0;
        end else if(I_frame_start) begin
            S_drain_active <= 1'b0;
            S_wait_drain   <= 1'b0;
            S_drained      <= 1'b0;
            S_drain_cnt    <= 10'd0;
            S_wait_cnt     <= 4'd0;
        end else if(S_drain_active) begin
            if(S_drain_cnt == 10'd643) begin
                S_drain_active <= 1'b0;
                S_drained      <= 1'b1;   //本帧已排空，防重入
                S_drain_cnt    <= 10'd0;
            end else
                S_drain_cnt <= S_drain_cnt + 1'b1;
        end else if(S_wait_drain) begin
            if(S_wait_cnt == 4'd8) begin
                S_wait_drain   <= 1'b0;
                S_drain_active <= 1'b1;   //解包尾已排空，开始排空 morph 链
                S_drain_cnt    <= 10'd0;
                S_wait_cnt     <= 4'd0;
            end else
                S_wait_cnt <= S_wait_cnt + 1'b1;
        end else if(S_full_done && !S_drained &&
                    (S_cur_cnt == 9'd0) && (S_bg_cnt == 9'd0) &&
                    !S_cur_96_valid && !S_bg_96_valid) begin
            S_wait_drain <= 1'b1;   //读满且 FIFO 弹空且解包输出停：延迟 8 拍后 DRAIN
            S_wait_cnt   <= 4'd0;
        end
    end

    //------------ 形态学滤波（开运算：去孤立噪点白斑 + 恢复尺寸，2026-10-27 加）------------
    // 比较出的原始标记先过 morph（腐蚀去单点噪点、膨胀复原），再攒字写 ERAM。
    // 总延迟 644 有效拍（valid 门控），valid 对齐输出；帧开始清行缓冲。
    // 2026-10-28：I_valid 在 DRAIN 期强制拉高排空；I_data 在 DRAIN 期强制 0（假拍零污染）。
    wire [3:0] S_mark_filt;
    wire       S_mark_filt_valid;
    morph_filter u_morph (
        .I_clk         ( I_ddr_clk                      ),
        .I_rst_n       ( I_rst_n                        ),
        .I_frame_start ( S_fs_d512                      ),
        .I_valid       ( (S_cur_96_valid && S_bg_96_valid) || S_drain_active ),
        .I_data        ( (S_cur_96_valid && S_bg_96_valid) ? S_mark_4p : 4'd0 ),
        .O_valid       ( S_mark_filt_valid              ),
        .O_data        ( S_mark_filt                    )
    );

    //------------ 攒 40bit 字（10 个 96bit = 40 像素 = 1 字）写 ERAM ------------
    // 字内位序：word[3:0]=第 1 个 96bit（最左 4 像素）… word[39:36]=第 10 个（最右）
    // 2026-10-28 非对称半帧读：A 半写 0~5887（184 行）、B 半写 5632~23039（544 行恰好写满），
    //   交界行 176~183 每帧都写 → 撕裂点移到上部 1/4（行 175/176 与 183/184，静止背景区无感）
    // ⚠️ 2026-10-29 写三件套打 1 拍：实机恒定左移 40 像素根因 = O_fg_wr_addr 路径被 TD 插拍
    //   （addr 比 data/en 晚 1 拍 → 字 k 写进 k-1 → ERAM 内容整体左移 1 字）。
    //   修复：addr/data/en 显式整体打 1 拍直连 ERAM 端口——寄存器输出路径最短、TD 无插拍空间，
    //   且三件套同拍锁存 → 对齐固定。打拍账：写拍 T 内部 en=1，q 三件套 <= T 拍前值（addr=字 k 地址），
    //   拍 T+1 ERAM 采样 q（addr 正确落位）✓；tb 判据兼容（写拍显示 addr 拍前值 0）。
    // ERAM 字起点恒 0（整帧读，无分段基址）
    reg [39:0] S_fg_word;
    reg [3:0]  S_word_cnt;   //0~9
    reg        S_fg_wr_en_int;     //内部写使能（打拍前）
    reg [39:0] S_fg_wr_data_int;   //内部写数据（打拍前）
    reg [14:0] S_fg_wr_addr_int;   //内部写地址（打拍前，递增在写拍）
    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_fg_word        <= 40'd0;
            S_word_cnt       <= 4'd0;
            S_fg_wr_en_int   <= 1'b0;
        end else begin
            S_fg_wr_en_int <= 1'b0;   //默认不写
            if(S_fs_d512) begin
                // 帧开始无条件复位攒字器（读不满帧时 half_sel 未翻转 → 写地址回同半帧起点重写该半；addr 复位在独立块）
                S_fg_word    <= 40'd0;
                S_word_cnt   <= 4'd0;
            end else if(S_mark_filt_valid) begin
                // ⚠️ 2026-10-27 位序修复：右移——最左像素组 0 最终落在 word[3:0]（与注释/读侧 col0=bit0 一致）
                S_fg_word <= {S_mark_filt, S_fg_word[39:4]};   //高 4 位进新标记、旧值右移
                if(S_word_cnt == 4'd9) begin
                    S_fg_wr_data_int <= {S_mark_filt, S_fg_word[39:4]};  //凑满 40bit
                    S_fg_wr_en_int   <= 1'b1;
                    // ⚠️ 2026-10-29 地址时序修复：地址递增必须放「写拍」（en 有效拍），不能放攒满拍——
                    //   攒满拍非阻塞 addr+1 在 en 拍已生效 → ERAM 采样 addr+1 → 字 k 写进 addr+1 → 标记整体右移 1 字（40 像素）
                    //   + 行首字（base 地址）永远写不到 = 左边界 40 像素无标记。实机现象：涂白恒定右移 ~2cm、与摄像头内容无关（恒定 = 结构错位）。
                    S_word_cnt   <= 4'd0;
                end else
                    S_word_cnt <= S_word_cnt + 1'b1;
            end
        end
    end

    //------------ 写地址递增（独立块，2026-10-29 时序修复）------------
    // 攒满拍非阻塞 addr+1 在写拍已生效 → ERAM 采样 addr+1 → 字 k 写进 addr+1 → 标记整体右移 1 字（40 像素）。
    // 修复：地址递增放「写拍」（en 有效拍）——写拍 ERAM 采样旧 addr 正确落位，写后 addr+1 供下一字。
    // 独立 always 块：写拍与下一字首组（S_mark_filt_valid 连续）同拍互不干扰；S_fs_d512 复位优先。
    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            S_fg_wr_addr_int <= 15'd0;
        else if(S_fs_d512)
            S_fg_wr_addr_int <= 15'd0;   //帧开始复位到帧起点（整帧读，读不满重写全帧）
        else if(S_fg_wr_en_int)
            S_fg_wr_addr_int <= (S_fg_wr_addr_int == 15'd23039) ? 15'd23039 : S_fg_wr_addr_int + 1'b1;  //封顶
    end

    //------------ 写三件套显式打 1 拍（2026-10-29 插拍防护 + 写+1补偿）------------
    // ⚠️ 2026-10-30 凌晨 最终组合：读0+写+1（d=-1+0+1=0）。四系数实测：读+1→-1、读-1→+2、写+1→+1、写-1→-2
    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            O_fg_wr_en   <= 1'b0;
            O_fg_wr_data <= 40'd0;
            O_fg_wr_addr <= 15'd0;
        end else begin
            O_fg_wr_en   <= S_fg_wr_en_int;
            O_fg_wr_data <= S_fg_wr_data_d[DATA_DLY];   //数据链延迟补偿（DATA_DLY 拍）
            O_fg_wr_addr <= S_fg_wr_addr_d[ADDR_DLY];   //地址链延迟补偿（ADDR_DLY 拍；写补偿 0 回退保持）
        end
    end

    //------------ debug：首字写拍地址锁存（2026-10-29 串口诊断）------------
    // 帧开始（S_fs_d512）或半帧切换（half_sel 翻转）后第一个写拍 = 该半帧首字。
    // 锁存该写拍当拍 ERAM 端口地址（O_fg_wr_addr 拍前值）→ 串口发回：
    //   A 半首字应 = 0、B 半首字应 = 5632；非预期值 = 写地址时序错位实锤。
    reg S_first_wr_pend;
    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_first_wr_pend   <= 1'b0;
            O_dbg_first_addr  <= 15'd0;
            O_dbg_first_data  <= 40'd0;
            O_dbg_first_half  <= 2'd0;
            O_dbg_first_valid <= 1'b0;
        end else begin
            O_dbg_first_valid <= 1'b0;
            if(S_fs_d512)
                S_first_wr_pend <= 1'b1;
            else if(S_fg_wr_en_int && S_first_wr_pend) begin
                S_first_wr_pend   <= 1'b0;
                O_dbg_first_addr  <= O_fg_wr_addr;    //拍前值 = ERAM 采样地址
                O_dbg_first_data  <= S_fg_wr_data_int; //拍前值 = ERAM 采样数据（首字内容诊断）
                O_dbg_first_half  <= 2'd0;
                O_dbg_first_valid <= 1'b1;
            end
        end
    end

    //------------ 首轮写满标志（写完第 22974 字左右 → 拉高保持，供叠加使能）------------
    // ⚠️ 2026-10-27 修正：morph 帧尾 643 有效拍（≈64 字）在帧间断层不推进、由清链丢弃，
    //    B 半帧实际写 5632~22975 → 原「写完第 23040 字」判据永远等不到 → fg_init 恒 0。
    //    放宽为写地址 >=22960（写满地址约 22974±1，留 14 字余量覆盖残拍误差）；
    //    代价 = ERAM 每帧尾部 64 字（屏幕最底部 2 行）保持上电 0 = 无标记，无感。
    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            O_fg_init <= 1'b0;
        else if(S_fg_wr_en_int && (S_fg_wr_addr_int >= 15'd22960))
            O_fg_init <= 1'b1;   //half1 写满（两半帧共 ~22912 字写完），整帧前景标记就绪
    end

    //------------ debug：读总数 ------------
    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            O_dbg_rd_cnt <= 19'd0;
        else if(I_frame_start)
            O_dbg_rd_cnt <= 19'd0;
        else if(O_ddr_user_rd_en && I_ddr_user_ready)
            O_dbg_rd_cnt <= O_dbg_rd_cnt + 1'b1;
    end

endmodule
