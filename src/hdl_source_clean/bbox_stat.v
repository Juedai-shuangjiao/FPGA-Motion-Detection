//========================================================
// 模块：bbox_stat —— 前景标记外接框/质心/跟踪统计（DDR 域，挂在 bg_read 写流上）
// 功能：对写进 ERAM 的前景标记流（40bit/字）做整帧统计：
//       min_x/max_x/min_y/max_y（外接框四边界）、sum_x/sum_y/cnt（质心累加）、
//       帧末段锁存 + A/B1/B2 三段合并（交界区只由前段统计，零重复）、
//       质心 = sum/cnt（恢复余数除法 x/y 分时复用单实例）、相邻整帧质心差分 = 速度向量。
// 数据源：bg_read 写流三件套（O_fg_wr_en/addr/data）——地址自带行号（addr>>5），
//       每 10 拍才处理一次（vs 4px/拍流的每拍处理），零额外存储。
// 三段边界（2026-11-02 主线均匀三段版）：A 段写 0~7935（行 0~247）、
//       B1 段写 7680~15615（行 240~487）、B2 段写 15360~23039（行 480~719）。
//       交界区 A∩B1=7680~7935（行 240~247）、B1∩B2=15360~15615（行 480~487）
//       → B1 过滤 addr<7936、B2 过滤 addr<15616，交界行仅由前段统计一次，零重复。
// 帧边界：I_fs_pulse（bg_read 的 S_fs_d512）拍锁存上一段统计到对应组、
//       统计清零、三段合并得整帧值、启动除法；除法完成拍做帧间差分。
//========================================================
// 资源：模块级 dsp_style="no" 强制乘法走 LUT——6×11 乘法用 DSP 是杀鸡用牛刀
//       （DSP 10 = 主线 8 + 框 2，+2 就是拍B的两个乘法被 TD 塞进 DSP 18×18）
(* dsp_style = "no" *)
module bbox_stat #(
    parameter MIN_CNT = 20'd100   //最小标记像素数：整帧 cnt 低于此值判无目标（防噪点框）
)(
    input  wire        I_clk,          //DDR 域时钟（usr_clk 100M）
    input  wire        I_rst_n,        //复位，低有效
    input  wire        I_wr_en,        //写流使能（bg_read O_fg_wr_en）
    input  wire [14:0] I_wr_addr,      //写流地址（本字实际写入 ERAM 的地址，拍前值）
    input  wire [39:0] I_wr_data,      //写流数据（40 像素前景标记）
    input  wire        I_fs_pulse,     //帧开始脉冲（bg_read S_fs_d512，写流已静默后到达）
    input  wire [1:0]  I_half_sel,     //段选择（bg_read S_half_sel，本帧统计类型：0=A 1=B1 2=B2）
    output wire        O_valid,        //统计有效（整帧 cnt >= MIN_CNT）
    output wire [10:0] O_min_x,        //外接框左边界（图像坐标 0~1279）
    output wire [10:0] O_max_x,        //外接框右边界
    output wire [9:0]  O_min_y,        //外接框上边界（0~719）
    output wire [9:0]  O_max_y,        //外接框下边界
    output wire [10:0] O_cx,           //质心 X（整除截断）
    output wire [9:0]  O_cy,           //质心 Y
    output wire [4:0]  O_dir_dx,       //方向块偏移 X（有符号 5bit：-15/-10/0/+10/+15）
    output wire [4:0]  O_dir_dy,       //方向块偏移 Y（屏 y 向下为正）
    output wire        O_dir_valid,    //方向有效（速度足够大才画方向块）
    output wire [19:0] O_cnt           //整帧标记像素总数（诊断用）
);

    localparam A_WORDS      = 15'd7936;    //A 段写字数（248 行×32 字）
    localparam B1_CLEAN     = 15'd7936;    //B1 段干净区起点（行 248 首字）：B1 从 >= 此值统计
    localparam B2_CLEAN     = 15'd15616;   //B2 段干净区起点（行 488 首字）：B2 从 >= 此值统计
    localparam SAT_CNT      = 16'd32768;   //半帧饱和点数：半帧前景超 32768 点即饱和（整帧 ≤ 65536）
    localparam SUM_X_W      = 26;          //半帧 sum_x 位宽（≤32768×1279=41.9M < 2^26）
    localparam SUM_Y_W      = 25;          //半帧 sum_y 位宽（≤32768×719=23.5M < 2^25）
    localparam FULL_X_W     = 27;          //整帧合并 sum_x 位宽（≤65536×1279=83.8M < 2^27）
    localparam FULL_Y_W     = 26;          //整帧合并 sum_y 位宽（≤65536×719=47.1M < 2^26）

    //------------ 40bit 字内统计函数（组合，综合成加法树/优先级链）------------
    // 求 40bit 置位数（加法树）
    function [5:0] popcount40;
        input [39:0] w;
        integer i;
        reg [5:0] c;
        begin
            c = 6'd0;
            for(i = 0; i < 40; i = i + 1)
                c = c + w[i];
            popcount40 = c;
        end
    endfunction
    // 求最低置位位号（全 0 返回 0；调用方用 pop>0 门控不使用）
    function [5:0] find_low_bit;
        input [39:0] w;
        integer i;
        reg [5:0] r;
        begin
            r = 6'd0;
            for(i = 39; i >= 0; i = i - 1)
                if(w[i]) r = i[5:0];
            find_low_bit = r;
        end
    endfunction
    // 求最高置位位号（全 0 返回 0；调用方用 pop>0 门控不使用）
    function [5:0] find_high_bit;
        input [39:0] w;
        integer i;
        reg [5:0] r;
        begin
            r = 6'd0;
            for(i = 0; i < 40; i = i + 1)
                if(w[i]) r = i[5:0];
            find_high_bit = r;
        end
    endfunction
    // 求置位位号之和（≤ 39+38+...+0 = 780）
    // 2026-11-02 时序修复3：40 输入 if 加链是 40 级优先级结构，改成 8 组×5 输入的
    //   两级加法树（组内 4 级 + 树 3 级 = 7 级），从 S_wr_word_q 到 S_bit_sx_b
    //   的组合深度减半。
    function [9:0] bit_sum_x;
        input [39:0] w;
        reg [9:0] s0, s1, s2, s3, s4, s5, s6, s7;
        integer i;
        begin
            s0 = 10'd0; s1 = 10'd0; s2 = 10'd0; s3 = 10'd0;
            s4 = 10'd0; s5 = 10'd0; s6 = 10'd0; s7 = 10'd0;
            for(i = 0; i < 5; i = i + 1)    s0 = s0 + (w[i]   ? i[9:0] : 10'd0);
            for(i = 5; i < 10; i = i + 1)   s1 = s1 + (w[i]   ? i[9:0] : 10'd0);
            for(i = 10; i < 15; i = i + 1)  s2 = s2 + (w[i]   ? i[9:0] : 10'd0);
            for(i = 15; i < 20; i = i + 1)  s3 = s3 + (w[i]   ? i[9:0] : 10'd0);
            for(i = 20; i < 25; i = i + 1)  s4 = s4 + (w[i]   ? i[9:0] : 10'd0);
            for(i = 25; i < 30; i = i + 1)  s5 = s5 + (w[i]   ? i[9:0] : 10'd0);
            for(i = 30; i < 35; i = i + 1)  s6 = s6 + (w[i]   ? i[9:0] : 10'd0);
            for(i = 35; i < 40; i = i + 1)  s7 = s7 + (w[i]   ? i[9:0] : 10'd0);
            bit_sum_x = ((s0 + s1) + (s2 + s3)) + ((s4 + s5) + (s6 + s7));
        end
    endfunction

    //------------ 写拍锁存（拆长组合路径：写拍入、下一拍统计）------------
    reg [14:0] S_wr_addr_q;
    reg [39:0] S_wr_word_q;
    reg        S_wr_valid_q;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_wr_addr_q  <= 15'd0;
            S_wr_word_q  <= 40'd0;
            S_wr_valid_q <= 1'b0;
        end else begin
            S_wr_addr_q  <= I_wr_addr;
            S_wr_word_q  <= I_wr_data;
            S_wr_valid_q <= I_wr_en;
        end
    end

    //------------ 拍A：写拍锁存 + 字内统计项（组合）------------
    wire [9:0]  S_wr_y     = S_wr_addr_q[14:5];               //行号 = 地址/32（每行 32 字）
    wire [4:0]  S_wr_word  = S_wr_addr_q[4:0];                //行内字 0~31
    wire [10:0] S_wr_xbase = (S_wr_word << 5) + (S_wr_word << 3);   //字内 x 基址 = word×40 = word×32+word×8
    wire [5:0]  S_pop      = popcount40(S_wr_word_q);
    wire [5:0]  S_low_bit  = find_low_bit(S_wr_word_q);
    wire [5:0]  S_high_bit = find_high_bit(S_wr_word_q);
    wire [9:0]  S_bit_sx   = bit_sum_x(S_wr_word_q);

    //------------ 本帧统计的段类型（帧开始拍锁存 I_half_sel）------------
    reg [1:0] S_frame_seg;   //0=A 段（全收）1=B1 段（过滤交界）2=B2 段（过滤交界）
    // 本字统计使能（按段过滤交界区：交界行只由前段统计）
    reg [14:0] S_seg_clean;
    always @(*) begin
        case(S_frame_seg)
            2'd1    : S_seg_clean = B1_CLEAN;
            2'd2    : S_seg_clean = B2_CLEAN;
            default : S_seg_clean = 15'd0;
        endcase
    end
    wire S_stat_en = S_wr_valid_q && (S_wr_addr_q >= S_seg_clean);

    //------------ 拍B：统计项锁存 + 乘法（流水化拆长路径：乘法单独一拍）------------
    // 路径账：原实现「popcount 树 + 位号和链 + 6×11 乘法 + 30bit 累加」全在一拍，
    //       100MHz 下组合超 10ns（SWNS -3.871ns/49 违例主因）。
    //       拆拍后：拍A 组合 = popcount/位号和（~5 级 LUT）；拍B = 6×11 乘法；
    //       拍C = 30bit 加法（快进位）——每拍 < 6ns，时序余量大。
    // 帧边界安全：fs_pulse 在写流静默 512 拍后到达，2 拍流水早已排空，无丢字。
    reg        S_st_en_b;
    reg [5:0]  S_pop_b, S_low_b, S_high_b;
    reg [9:0]  S_bit_sx_b, S_wr_y_b;
    reg [10:0] S_wr_xbase_b;
    reg [14:0] S_wr_addr_b;    //2026-11-02 块密度过滤：拍B锁存字地址（块号派生源）
    reg [15:0] S_prod_x;   //pop×xbase ≤ 40×1279 = 51160 < 2^16
    reg [15:0] S_prod_y;   //pop×y ≤ 40×719 = 28760 < 2^16
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_st_en_b     <= 1'b0;
            S_pop_b       <= 6'd0; S_low_b <= 6'd0; S_high_b <= 6'd0;
            S_bit_sx_b    <= 10'd0;
            S_wr_y_b      <= 10'd0;
            S_wr_xbase_b  <= 11'd0;
            S_wr_addr_b    <= 15'd0;
            S_prod_x      <= 16'd0;
            S_prod_y      <= 16'd0;
        end else begin
            S_st_en_b     <= S_stat_en;
            S_pop_b       <= S_pop;
            S_low_b       <= S_low_bit;
            S_high_b      <= S_high_bit;
            S_bit_sx_b    <= S_bit_sx;
            S_wr_y_b      <= S_wr_y;
            S_wr_xbase_b  <= S_wr_xbase;
            S_wr_addr_b    <= S_wr_addr_q;
            // 2026-11-02 时序修复2：乘法输入必须用拍B寄存器（_b），不能再用拍A组合
            //   （S_pop/S_bit_sx 组合）——否则「popcount树+位号和链+乘法+加法」全串
            //   一拍 16 级 LUT（SWNS -3.331ns 首恶 add46）。改 _b 后：
            //   拍B组合 = popcount/位号和（~8 级）→ 拍C组合 = 乘法+加法（~8 级）
            //   → 拍D 累加（~5 级）。语义：prod 比 _b 晚 1 拍（同块非阻塞拍前采样），
            //   累加器门控同步延 1 拍（S_st_en_c）。
            S_prod_x      <= S_pop_b * S_wr_xbase_b + {6'd0, S_bit_sx_b};
            S_prod_y      <= S_pop_b * S_wr_y_b;       //6×10 乘法
        end
    end

    //------------ 半帧统计累加器（帧开始拍清零，拍C：用拍B锁存值更新）------------
    reg [10:0] S_min_x;
    reg [10:0] S_max_x;
    reg [9:0]  S_min_y;
    reg [9:0]  S_max_y;
    reg [SUM_X_W-1:0] S_sum_x;
    reg [SUM_Y_W-1:0] S_sum_y;
    reg [19:0] S_cnt;
    reg        S_st_en_c;    //2026-11-02 时序修复2：累加器门控比拍B再晚 1 拍（prod 已晚 1 拍）
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) S_st_en_c <= 1'b0;
        else         S_st_en_c <= S_st_en_b;
    end
    //------------ 块密度过滤（2026-11-02 仿真验证集成：防孤立噪声/远距离白点污染统计）------------
    // 画面分 16×9=144 块（80 行×80 像素=2 字）；帧内计数各块前景点，
    // 帧末（fs_pulse）锁存有效图（块点数 ≥ BLK_MIN=5），下一帧统计只收有效块内点。
    // 孤立散点块被踢出 → 框只包有密度区域；首帧默认全有效不滤。
    wire [8:0]  W_blk_row_9 = S_wr_addr_b[14:5];     //行号 0~719（字/32）
    wire [3:0]  W_blk_row = (W_blk_row_9 >= 9'd640) ? 4'd8 : (W_blk_row_9 >= 9'd560) ? 4'd7 :
                            (W_blk_row_9 >= 9'd480) ? 4'd6 : (W_blk_row_9 >= 9'd400) ? 4'd5 :
                            (W_blk_row_9 >= 9'd320) ? 4'd4 : (W_blk_row_9 >= 9'd240) ? 4'd3 :
                            (W_blk_row_9 >= 9'd160) ? 4'd2 : (W_blk_row_9 >= 9'd80)  ? 4'd1 : 4'd0;
    wire [3:0]  W_blk_col = S_wr_addr_b[4:1];        //列字/2（每行 32 字、块 2 字宽）
    wire [7:0]  W_blk_id  = {W_blk_row, W_blk_col};  //8bit 块号（144 块 < 256）
    localparam  BLK_MIN   = 10'd5;                   //块有效最小点数
    reg [9:0] R_blk_cnt [0:143];
    reg       R_blk_en  [0:143];
    integer bj;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            for(bj=0; bj<144; bj=bj+1) begin
                R_blk_cnt[bj] <= 10'd0;
                R_blk_en[bj]  <= 1'b1;    //首帧默认全有效
            end
        end else if(I_fs_pulse) begin
            for(bj=0; bj<144; bj=bj+1) begin
                R_blk_en[bj]  <= (R_blk_cnt[bj] >= BLK_MIN);
                R_blk_cnt[bj] <= 10'd0;
            end
        end else if(S_st_en_c) begin     //拍C：本字计数入块（S_wr_addr_b 拍B锁存、拍C稳定）
            R_blk_cnt[W_blk_id] <= R_blk_cnt[W_blk_id] + {4'd0, S_pop_b};
        end
    end
    wire W_blk_ok = R_blk_en[W_blk_id];  //当前字所在块有效（拍D 累加时 S_wr_addr_b 保持本字）
    // 半帧点数饱和：cnt 达 SAT_CNT 后 sum/cnt 停止累加（防超大目标位宽溢出；min/max 继续更新保证框完整）
    wire S_cnt_full = (S_cnt >= SAT_CNT);
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_min_x <= 11'h7FF;
            S_max_x <= 11'd0;
            S_min_y <= 10'h3FF;
            S_max_y <= 10'd0;
            S_sum_x <= {SUM_X_W{1'b0}};
            S_sum_y <= {SUM_Y_W{1'b0}};
            S_cnt   <= 20'd0;
        end else if(I_fs_pulse) begin
            // 帧开始：本帧统计结束，清零迎接新半帧（拍B在途字已由写流静默 512 拍保证排空）
            S_min_x <= 11'h7FF;
            S_max_x <= 11'd0;
            S_min_y <= 10'h3FF;
            S_max_y <= 10'd0;
            S_sum_x <= {SUM_X_W{1'b0}};
            S_sum_y <= {SUM_Y_W{1'b0}};
            S_cnt   <= 20'd0;
        end else if(S_st_en_c && W_blk_ok) begin
            // 本字统计（pop=0 时 min/max 不更新，防无标记字污染边界；块无效整字跳过）
            if((S_pop_b != 6'd0) && ((S_wr_xbase_b + {5'd0, S_low_b}) < S_min_x))
                S_min_x <= S_wr_xbase_b + {5'd0, S_low_b};
            if((S_pop_b != 6'd0) && ((S_wr_xbase_b + {5'd0, S_high_b}) > S_max_x))
                S_max_x <= S_wr_xbase_b + {5'd0, S_high_b};
            if((S_pop_b != 6'd0) && (S_wr_y_b < S_min_y))
                S_min_y <= S_wr_y_b;
            if((S_pop_b != 6'd0) && (S_wr_y_b > S_max_y))
                S_max_y <= S_wr_y_b;
            if(!S_cnt_full) begin   //饱和后只停 sum/cnt（min/max 照常 → 框保持完整）
                S_sum_x <= S_sum_x + {10'd0, S_prod_x};
                S_sum_y <= S_sum_y + {9'd0, S_prod_y};
                S_cnt   <= S_cnt + {14'd0, S_pop_b};
            end
        end
    end

    //------------ 帧边界处理：段锁存 + 段类型更新（I_fs_pulse 拍）------------
    // S_frame_seg 拍前值 = 上一帧统计类型 → 锁存目标组（读不满帧 seg 不翻转，
    // 拍前值 = 本段类型，仍锁进正确组）
    reg [10:0] L_min_x_a, L_max_x_a;
    reg [9:0]  L_min_y_a, L_max_y_a;
    reg [SUM_X_W-1:0] L_sum_x_a;
    reg [SUM_Y_W-1:0] L_sum_y_a;
    reg [19:0] L_cnt_a;
    reg [10:0] L_min_x_b1, L_max_x_b1;
    reg [9:0]  L_min_y_b1, L_max_y_b1;
    reg [SUM_X_W-1:0] L_sum_x_b1;
    reg [SUM_Y_W-1:0] L_sum_y_b1;
    reg [19:0] L_cnt_b1;
    reg [10:0] L_min_x_b2, L_max_x_b2;
    reg [9:0]  L_min_y_b2, L_max_y_b2;
    reg [SUM_X_W-1:0] L_sum_x_b2;
    reg [SUM_Y_W-1:0] L_sum_y_b2;
    reg [19:0] L_cnt_b2;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            L_min_x_a <= 11'h7FF; L_max_x_a <= 11'd0; L_min_y_a <= 10'h3FF; L_max_y_a <= 10'd0;
            L_sum_x_a <= {SUM_X_W{1'b0}}; L_sum_y_a <= {SUM_Y_W{1'b0}};  L_cnt_a   <= 20'd0;
            L_min_x_b1 <= 11'h7FF; L_max_x_b1 <= 11'd0; L_min_y_b1 <= 10'h3FF; L_max_y_b1 <= 10'd0;
            L_sum_x_b1 <= {SUM_X_W{1'b0}}; L_sum_y_b1 <= {SUM_Y_W{1'b0}}; L_cnt_b1  <= 20'd0;
            L_min_x_b2 <= 11'h7FF; L_max_x_b2 <= 11'd0; L_min_y_b2 <= 10'h3FF; L_max_y_b2 <= 10'd0;
            L_sum_x_b2 <= {SUM_X_W{1'b0}}; L_sum_y_b2 <= {SUM_Y_W{1'b0}}; L_cnt_b2  <= 20'd0;
            S_frame_seg <= 2'd0;
        end else if(I_fs_pulse) begin
            case(S_frame_seg)              //上一帧是 A/B1/B2 段 → 锁存对应组
                2'd0: begin
                    L_min_x_a <= S_min_x; L_max_x_a <= S_max_x;
                    L_min_y_a <= S_min_y; L_max_y_a <= S_max_y;
                    L_sum_x_a <= S_sum_x; L_sum_y_a <= S_sum_y;
                    L_cnt_a   <= S_cnt;
                end
                2'd1: begin
                    L_min_x_b1 <= S_min_x; L_max_x_b1 <= S_max_x;
                    L_min_y_b1 <= S_min_y; L_max_y_b1 <= S_max_y;
                    L_sum_x_b1 <= S_sum_x; L_sum_y_b1 <= S_sum_y;
                    L_cnt_b1   <= S_cnt;
                end
                default: begin
                    L_min_x_b2 <= S_min_x; L_max_x_b2 <= S_max_x;
                    L_min_y_b2 <= S_min_y; L_max_y_b2 <= S_max_y;
                    L_sum_x_b2 <= S_sum_x; L_sum_y_b2 <= S_sum_y;
                    L_cnt_b2   <= S_cnt;
                end
            endcase
            S_frame_seg <= I_half_sel;   //本帧统计类型（bg_read 读满拍已翻成下一段）
        end
    end

    //------------ 整帧合并（三段，拆两拍：三输入加法/四级比较的 13.6ns 组合链超 10ns 周期）------------
    // 2026-11-02 时序修复：原「四值嵌套三元 + 三输入 27bit 加法」一条组合链被布局拉散
    //   （net 占 55%）→ SWNS -3.815ns 违例。拆两级：
    //   拍1（fs_pulse）第一级：A+B1 双输入加/双值比较 → 中间寄存器；
    //   拍2（S_latch_out）第二级：+B2 → R 锁存 + 除法启动（I_numer 寄存器稳定）。
    reg [10:0] S_m_min_x, S_m_max_x;
    reg [9:0]  S_m_min_y, S_m_max_y;
    reg [FULL_X_W-1:0] S_m_sum_x;
    reg [FULL_Y_W-1:0] S_m_sum_y;
    reg [21:0] S_m_cnt;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_m_min_x <= 11'h7FF; S_m_max_x <= 11'd0;
            S_m_min_y <= 10'h3FF; S_m_max_y <= 10'd0;
            S_m_sum_x <= {FULL_X_W{1'b0}};
            S_m_sum_y <= {FULL_Y_W{1'b0}};
            S_m_cnt   <= 22'd0;
        end else if(I_fs_pulse) begin
            S_m_min_x <= (L_min_x_a < L_min_x_b1) ? L_min_x_a : L_min_x_b1;
            S_m_max_x <= (L_max_x_a > L_max_x_b1) ? L_max_x_a : L_max_x_b1;
            S_m_min_y <= (L_min_y_a < L_min_y_b1) ? L_min_y_a : L_min_y_b1;
            S_m_max_y <= (L_max_y_a > L_max_y_b1) ? L_max_y_a : L_max_y_b1;
            S_m_sum_x <= {1'b0, L_sum_x_a} + {1'b0, L_sum_x_b1};
            S_m_sum_y <= {1'b0, L_sum_y_a} + {1'b0, L_sum_y_b1};
            S_m_cnt   <= {2'b0, L_cnt_a} + {2'b0, L_cnt_b1};
        end
    end
    // 第二级（组合，S_latch_out 拍被 R 锁存采样）：双输入加/双值比较，10ns 内宽松
    wire [10:0] M_min_x = (S_m_min_x < L_min_x_b2) ? S_m_min_x : L_min_x_b2;
    wire [10:0] M_max_x = (S_m_max_x > L_max_x_b2) ? S_m_max_x : L_max_x_b2;
    wire [9:0]  M_min_y = (S_m_min_y < L_min_y_b2) ? S_m_min_y : L_min_y_b2;
    wire [9:0]  M_max_y = (S_m_max_y > L_max_y_b2) ? S_m_max_y : L_max_y_b2;
    wire [FULL_X_W-1:0] M_sum_x = S_m_sum_x + {1'b0, L_sum_x_b2};
    wire [FULL_Y_W-1:0] M_sum_y = S_m_sum_y + {1'b0, L_sum_y_b2};
    wire [21:0] M_cnt   = S_m_cnt + {2'b0, L_cnt_b2};

    //------------ 框值锁存（fs_pulse 后一拍，此时合并组合已稳定）------------
    reg S_latch_out;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            S_latch_out <= 1'b0;
        else
            S_latch_out <= I_fs_pulse;
    end

    reg        R_valid;
    reg [10:0] R_min_x, R_max_x;
    reg [9:0]  R_min_y, R_max_y;
    reg [19:0] R_cnt;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            R_valid <= 1'b0;
            R_min_x <= 11'd0; R_max_x <= 11'd0;
            R_min_y <= 10'd0; R_max_y <= 10'd0;
            R_cnt   <= 20'd0;
        end else if(S_latch_out) begin
            R_valid <= (M_cnt >= MIN_CNT);
            R_min_x <= M_min_x; R_max_x <= M_max_x;
            R_min_y <= M_min_y; R_max_y <= M_max_y;
            R_cnt   <= M_cnt[19:0];
        end
    end

    //------------ 质心除法（sum/cnt，恢复余数串行除法，单实例 x/y 分时复用）------------
    // 2026-11-02 压缩：原双实例（27+26 拍并行各 100~150 slice）→ 单实例分时：
    //   div_start → 算 x（27 拍）→ done_x 拍启动 y（26 拍）→ done_y 拍锁存质心 + 差分。
    //   2×(DW+1)=56 拍 << 帧周期 166 万拍，时间无压力；面积减半。
    // ⚠️ 除 0 保护：cnt < MIN_CNT（无目标）时不启动除法——除数 0 会使商出 X 污染
    //   差分链（prev/方向全部跟随 X），且无目标帧输出保持旧值、O_valid=0 已屏蔽显示
    // ⚠️ 启动拍必须用 S_latch_out（fs_pulse 延迟 1 拍）：fs 拍非阻塞锁存段统计、
    //   合并组合 M_* 拍后才稳定——fs 拍直接启动会采样更新前的旧合并值（晚一帧）
    wire S_div_start = S_latch_out && (M_cnt >= MIN_CNT);
    // 除法输入用 R 锁存（S_latch_out 拍锁存，div31 启动下一拍采样——值稳定无竞态）
    reg [FULL_X_W-1:0] R_sum_x;
    reg [FULL_Y_W-1:0] R_sum_y;
    reg [21:0]         R_mcnt;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            R_sum_x <= {FULL_X_W{1'b0}};
            R_sum_y <= {FULL_Y_W{1'b0}};
            R_mcnt  <= 22'd0;
        end else if(S_latch_out) begin
            R_sum_x <= M_sum_x;
            R_sum_y <= M_sum_y;
            R_mcnt  <= M_cnt;
        end
    end
    // 分时状态机：0=空闲 1=算 x 2=算 y
    reg [1:0] S_div_phase;
    reg [FULL_X_W-1:0] S_div_numer;   //当前除法被除数（mux：x/y）
    wire [10:0] S_quot;
    wire S_done;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_div_phase <= 2'd0;
            S_div_numer <= {FULL_X_W{1'b0}};
        end else if(S_div_start && (S_div_phase == 2'd0)) begin
            S_div_phase <= 2'd1;          //启动 x 除法
            S_div_numer <= R_sum_x;
        end else if((S_div_phase == 2'd1) && S_done) begin
            S_div_phase <= 2'd2;          //x 完成，启动 y
            S_div_numer <= {1'b0, R_sum_y};   //26bit 高位补 0 对齐 27bit
        end else if((S_div_phase == 2'd2) && S_done) begin
            S_div_phase <= 2'd0;          //y 完成，回空闲
        end
    end
    wire S_div_go = (S_div_start && (S_div_phase == 2'd0)) ||   //x 启动
                    ((S_div_phase == 2'd1) && S_done);          //y 启动
    div31 #(.DW(FULL_X_W)) u_div (
        .I_clk   ( I_clk      ),
        .I_rst_n ( I_rst_n    ),
        .I_start ( S_div_go   ),
        .I_numer ( S_div_numer),
        .I_denom ( R_mcnt[20:0]),
        .O_quot  ( S_quot     ),
        .O_done  ( S_done     )
    );
    // 质心坐标锁存（x 完成拍锁 cx，y 完成拍锁 cy；done 后一拍值稳定）
    reg [10:0] R_cx;
    reg [9:0]  R_cy;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            R_cx <= 11'd0;
            R_cy <= 10'd0;
        end else if(S_done) begin
            if(S_div_phase == 2'd1)
                R_cx <= S_quot[10:0];    //x 除法完成：质心 X
            else
                R_cy <= S_quot[9:0];     //y 除法完成：质心 Y
        end
    end
    assign O_cx = R_cx;
    assign O_cy = R_cy;

    //------------ 帧间差分（跟踪：连续整帧质心差分 = 速度向量）------------
    // 以 y 除法 done（分时链最后一拍）为差分拍：x 先算完（27 拍）、y 后完（再 26 拍），
    // y done 时 R_cx/R_cy 均已稳定
    wire S_done_y = S_done && (S_div_phase == 2'd2);
    reg [10:0] S_prev_cx, S_prev_cy;
    reg        S_prev_valid;
    reg [11:0] S_vx, S_vy;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_prev_cx <= 11'd0; S_prev_cy <= 10'd0;
            S_prev_valid <= 1'b0;
            S_vx <= 12'd0; S_vy <= 12'd0;
        end else if(S_done_y) begin
            if(S_prev_valid) begin
                S_vx <= {1'b0, R_cx} - {1'b0, S_prev_cx};   //12bit 有符号（借位=负）
                S_vy <= {1'b0, R_cy} - {1'b0, S_prev_cy};
            end
            S_prev_cx <= R_cx;
            S_prev_cy <= R_cy;
            S_prev_valid <= 1'b1;
        end
    end

    //------------ 方向块偏移量化（|vx|/|vy| 主方向判定，8 方向）------------
    wire [11:0] S_abs_vx = S_vx[11] ? (~S_vx + 1'b1) : S_vx;
    wire [11:0] S_abs_vy = S_vy[11] ? (~S_vy + 1'b1) : S_vy;
    reg        S_dir_update;
    reg [4:0]  R_dir_dx, R_dir_dy;
    reg        R_dir_valid;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_dir_update <= 1'b0;
            R_dir_dx <= 5'd0; R_dir_dy <= 5'd0;
            R_dir_valid <= 1'b0;
        end else if(S_done_y) begin
            S_dir_update <= 1'b1;   //差分拍后一拍更新方向（S_vx/S_vy 拍后有效）
        end else if(S_dir_update) begin
            S_dir_update <= 1'b0;
            if((S_abs_vx < 12'd2) && (S_abs_vy < 12'd2)) begin
                R_dir_valid <= 1'b0;   //速度太小：静止，不画方向块
                R_dir_dx <= 5'd0;
                R_dir_dy <= 5'd0;
            end else if(S_abs_vx >= (S_abs_vy << 1)) begin
                // 水平为主：东/西
                R_dir_dx <= S_vx[11] ? -5'd15 : 5'd15;
                R_dir_dy <= 5'd0;
                R_dir_valid <= 1'b1;
            end else if(S_abs_vy >= (S_abs_vx << 1)) begin
                // 垂直为主：南/北（屏 y 向下为正）
                R_dir_dx <= 5'd0;
                R_dir_dy <= S_vy[11] ? -5'd15 : 5'd15;
                R_dir_valid <= 1'b1;
            end else begin
                // 对角：东北/西北/东南/西南
                R_dir_dx <= S_vx[11] ? -5'd10 : 5'd10;
                R_dir_dy <= S_vy[11] ? -5'd10 : 5'd10;
                R_dir_valid <= 1'b1;
            end
        end
    end

    //------------ 输出------------
    assign O_valid     = R_valid;
    assign O_min_x     = R_min_x;
    assign O_max_x     = R_max_x;
    assign O_min_y     = R_min_y;
    assign O_max_y     = R_max_y;
    assign O_dir_dx    = R_dir_dx;
    assign O_dir_dy    = R_dir_dy;
    assign O_dir_valid = R_dir_valid;
    assign O_cnt       = R_cnt;

endmodule
