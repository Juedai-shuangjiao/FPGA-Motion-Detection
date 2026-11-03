//========================================================
// 模块：blk_density —— 块密度过滤（防孤立噪声/远距离白点污染统计）
// 思路（block-based adaptive 思想 + 形态学面积滤除）：
//   画面分 16×9=144 块（1280×720 / 80×80 整除），每块帧内计数前景点数；
//   帧末锁存「块有效图」：块点数 ≥ BLK_MIN(5) 才算有效块；
//   下一帧统计（min/max/sum/cnt）只收「有效块内」的前景点——孤立散点所在块被踢出。
//   帧级流水：帧 N 计数 → 帧 N+1 应用（首帧有效图全 1 默认不滤）。
// 资源：144×10bit 计数器 + 144bit 有效图 ≈ 1600 FF ≈ 400 slice（集成时并入 bbox_stat）。
//========================================================
module blk_density (
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire [3:0]  I_fg,          //当前拍 4 像素前景标记（morph 后，bit0=行内最左）
    input  wire        I_vld,         //数据有效拍
    input  wire [9:0]  I_row,         //当前行号 0~719
    input  wire [10:0] I_col_base,    //当前拍 4 像素的基列 0~1276（步进 4）
    input  wire        I_fs_pulse,    //帧开始脉冲（帧末锁存有效图 + 清计数）
    output wire        O_blk_en       //当前拍所在块有效（下一帧生效的过滤门控）
);
    // 块索引：row/80（0~8，9 块）+ col/80（0~15，16 块）→ 144 块
    // 80 非 2 的幂，除法用比较链实现（9+16 个 8bit 比较器 ≈ 50 LUT）
    wire [3:0] W_blk_row = (I_row >= 10'd640) ? 4'd8 : (I_row >= 10'd560) ? 4'd7 :
                           (I_row >= 10'd480) ? 4'd6 : (I_row >= 10'd400) ? 4'd5 :
                           (I_row >= 10'd320) ? 4'd4 : (I_row >= 10'd240) ? 4'd3 :
                           (I_row >= 10'd160) ? 4'd2 : (I_row >= 10'd80)  ? 4'd1 : 4'd0;
    wire [3:0] W_blk_col = (I_col_base >= 11'd1200) ? 4'd15 : (I_col_base >= 11'd1120) ? 4'd14 :
                           (I_col_base >= 11'd1040) ? 4'd13 : (I_col_base >= 11'd960)  ? 4'd12 :
                           (I_col_base >= 11'd880)  ? 4'd11 : (I_col_base >= 11'd800)  ? 4'd10 :
                           (I_col_base >= 11'd720)  ? 4'd9  : (I_col_base >= 11'd640)  ? 4'd8  :
                           (I_col_base >= 11'd560)  ? 4'd7  : (I_col_base >= 11'd480)  ? 4'd6  :
                           (I_col_base >= 11'd400)  ? 4'd5  : (I_col_base >= 11'd320)  ? 4'd4  :
                           (I_col_base >= 11'd240)  ? 4'd3  : (I_col_base >= 11'd160)  ? 4'd2  :
                           (I_col_base >= 11'd80)   ? 4'd1  : 4'd0;
    wire [7:0] W_blk_id = {W_blk_row[3:0], W_blk_col[3:0]};    //8bit 块号（144 块 < 256）

    // 块计数（本帧累计，144×10bit）
    reg [9:0]  R_blk_cnt [0:143];
    reg [3:0]  S_cur_cnt;    //当前块的点数增量（0~4）
    integer i;

    // 当前拍 4 像素置位数
    function [3:0] pop4;
        input [3:0] w;
        begin
            pop4 = w[0] + w[1] + w[2] + w[3];
        end
    endfunction

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            for(i=0; i<144; i=i+1) R_blk_cnt[i] <= 10'd0;
        end else if(I_fs_pulse) begin
            for(i=0; i<144; i=i+1) R_blk_cnt[i] <= 10'd0;   //帧末清零（有效图已锁存）
        end else if(I_vld) begin
            R_blk_cnt[W_blk_id] <= R_blk_cnt[W_blk_id] + {6'd0, pop4(I_fg)};
        end
    end

    // 帧末锁存有效图：cnt >= 5
    reg R_blk_en [0:143];
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            for(i=0; i<144; i=i+1) R_blk_en[i] <= 1'b1;     //首帧默认全有效
        end else if(I_fs_pulse) begin
            for(i=0; i<144; i=i+1) R_blk_en[i] <= (R_blk_cnt[i] >= 10'd5);
        end
    end

    assign O_blk_en = R_blk_en[W_blk_id];
endmodule
