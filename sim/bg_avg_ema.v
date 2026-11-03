//========================================================
// 模块：bg_avg_ema —— 背景多帧平均（EMA 指数滑动平均，5 帧等效）
// 功能：bg_new = (4×bg_old + cur) / 5——每帧采一次，等效 5 帧时间平均
//       （专利 CN103325124A 时间平均背景建模思想的「单帧内存」实现：
//        逐像素读改写 DDR 背景区，无需缓存 4 帧）。
// 定点实现（零除法器）：(4a+b)/5 = a + (b-a)/5
//       (b-a)/5 ≈ ((b-a)×205)>>10（205/1024 = 0.2002，误差 0.1%）
//       b-a 用 9bit 有符号扩展；结果 24bit 饱和截断。
// 用法（集成）：bg_capture 帧期间，video_in 逐像素读 DDR 旧背景（bg_read 复用）
//       与当前帧像素同拍对齐送入本模块，输出写回 DDR 背景区。
// 资源：有符号乘法 9×8 + 加法 + 饱和 ≈ 60 LUT
//========================================================
module bg_avg_ema (
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire [23:0] I_cur,       //当前帧像素（RGB888，采集窗口内）
    input  wire [23:0] I_old,       //DDR 背景区旧值（与 I_cur 同拍对齐）
    input  wire        I_vld,
    output reg  [23:0] O_bg,        //EMA 输出（写回背景区）
    output reg         O_vld
);
    // 差分：b-a（24bit → 9bit 有符号可覆盖 -255..+255）
    wire signed [8:0] W_diff = {1'b0, I_cur[7:0]} - {1'b0, I_old[7:0]};  //R 通道演示
    wire signed [8:0] W_diff_g = {1'b0, I_cur[15:8]} - {1'b0, I_old[15:8]};
    wire signed [8:0] W_diff_b = {1'b0, I_cur[23:16]} - {1'b0, I_old[23:16]};

    // (diff × 205) >> 10——每个通道独立
    wire signed [17:0] W_d5_r = W_diff   * 9'sd205;
    wire signed [17:0] W_d5_g = W_diff_g * 9'sd205;
    wire signed [17:0] W_d5_b = W_diff_b * 9'sd205;

    wire signed [8:0] W_corr_r = W_d5_r[17:10];   //>>10（算术右移）
    wire signed [8:0] W_corr_g = W_d5_g[17:10];
    wire signed [8:0] W_corr_b = W_d5_b[17:10];

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            O_bg <= 24'd0;
            O_vld <= 1'b0;
        end else begin
            O_vld <= I_vld;
            O_bg <= { I_old[23:16] + W_corr_b[7:0],
                      I_old[15:8]  + W_corr_g[7:0],
                      I_old[7:0]   + W_corr_r[7:0] };
        end
    end
endmodule
