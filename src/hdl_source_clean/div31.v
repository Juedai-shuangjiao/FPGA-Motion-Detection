//========================================================
// 模块：div31 —— 恢复余数串行除法器（参数化被除数位宽，商宽固定 11bit）
// 功能：商 = 被除数 / 除数（无符号整数除法），逐拍移位减，DW+1 拍出结果。
//       启动脉冲后输入须保持稳定直到 O_done（调用方保证：被除数为帧末锁存值）。
// 用途：质心 = sum / cnt（sum_x 27bit、sum_y 26bit，cnt 21bit 共用除数）。
// 2026-11-02 压缩：商宽固定 11bit（质心坐标 ≤1279 < 2^11），商寄存器 27bit→11bit；
//       bbox_stat 内 x/y 分时复用同一实例（27+26 拍连除，帧周期 166 万拍绰绰有余），
//       2 实例 → 1 实例省约 100~150 slice。
// ⚠️ 迭代拍数 = 被除数位宽 DW（不是商宽）——恢复余数除法必须把被除数
//   所有位推进余数寄存器，商才精确（低 DW-QW 位对商的影响可达 2^DW/denom）。
// 资源：属性强制比较/减法走 LUT（dsp_style="no"），避免 TD 把大位宽比较
//       映射成 DSP；每帧只跑 2×DW+2 拍，LUT 实现时序无压力。
//========================================================
(* dsp_style = "no" *)
module div31 #(
    parameter DW = 27    //被除数位宽（迭代拍数 = DW）
)(
    input  wire          I_clk,      //时钟
    input  wire          I_rst_n,    //复位，低有效
    input  wire          I_start,    //启动脉冲（高 1 拍）
    input  wire [DW-1:0] I_numer,    //被除数（启动后须保持 DW+1 拍稳定）
    input  wire [20:0]   I_denom,    //除数（须 >= 1，除 0 结果无效）
    output reg  [10:0]   O_quot,     //商（11bit，质心坐标 ≤1279）
    output reg           O_done      //完成脉冲（高 1 拍）
);
    localparam QW = 11;              //商位宽（质心坐标上限 1279 < 2^11）

    reg [DW-1:0] S_rem;      //余数（移位比较寄存器）
    reg [QW-1:0] S_quot;     //商（移位累加，只存低 11 位）
    reg [5:0]    S_step;     //剩余步数（DW → 1）
    reg          S_busy;     //除法进行中

    // 本拍移位后的余数（组合，用于比较）
    wire [DW-1:0] S_rem_shift = {S_rem[DW-2:0], I_numer[S_step-1'b1]};
    // 比较拆段（高 11 位 + 低 20 位），配合属性避免大位宽比较映射 DSP
    wire [10:0] S_rem_hi = S_rem_shift[DW-1:20];
    wire [19:0] S_rem_lo = S_rem_shift[19:0];
    wire        S_sub_ok = (S_rem_hi > {10'd0, I_denom[20]}) ||
                           ((S_rem_hi == {10'd0, I_denom[20]}) && (S_rem_lo >= I_denom[19:0]));

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_rem  <= {DW{1'b0}};
            S_quot <= {QW{1'b0}};
            S_step <= DW;   //复位到 DW：S_rem_shift 的 I_numer[S_step-1] 索引始终有效（防负索引 X）
            S_busy <= 1'b0;
            O_quot <= {QW{1'b0}};
            O_done <= 1'b0;
        end else begin
            O_done <= 1'b0;   //默认无完成脉冲
            if(I_start) begin
                S_rem  <= {DW{1'b0}};
                S_quot <= {QW{1'b0}};
                S_step <= DW;   //从最高位开始
                S_busy <= 1'b1;
            end else if(S_busy) begin
                // 恢复余数：左移进被除数 1 位，够减则减并记商 1
                if(S_sub_ok)
                    S_rem <= S_rem_shift - {{(DW-21){1'b0}}, I_denom};
                else
                    S_rem <= S_rem_shift;
                S_quot <= {S_quot[QW-2:0], S_sub_ok};   //低位追加商位
                if(S_step == 6'd1) begin
                    S_busy <= 1'b0;
                    O_quot <= {S_quot[QW-2:0], S_sub_ok};   //完整商（低 11 位）
                    O_done <= 1'b1;
                end else
                    S_step <= S_step - 1'b1;
            end
        end
    end
endmodule
