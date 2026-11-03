//========================================================
// 模块：shadow_supp —— 背景差分阴影抑制（仿真原型，组合逻辑）
// 方法：Horprasert 模型 FPGA 简化版（Sensors 2012 论文，首次 FPGA 阴影检测）
//   · 亮度  Y = (R+2G+B)>>2
//   · 色度签名 s = |R-G| + |G-B|（无除法）
//   · 阴影判据：背景色度签名 >= 12 且亮度降幅有限（-70 < dy < -12）且色度差小（|ds| < 25）
//     → 阴影点强制判背景（不涂白）
//   · 亮度降幅下限 -70 兜底：深色实体（亮度砍半）保留为前景
// 数值验证（Python 300 样本）：阴影 300/300 滤除、深灰实体 300/300 保留、
//   前景肤色 300/300 保留
// 集成：bg_read 差分判据旁路——O_shadow=1 的点不判前景
// 资源：3 减法 + 2 绝对值 + 4 比较器 ≈ 40 LUT/像素（4 像素并行 ≈ 160 LUT）
//========================================================
module shadow_supp (
    input  wire [7:0] I_bg_r, I_bg_g, I_bg_b,   //背景像素
    input  wire [7:0] I_cur_r, I_cur_g, I_cur_b, //当前像素
    output wire        O_shadow                  //阴影标志
);
    // 亮度（8bit 差值 9bit 有符号）
    wire [9:0] W_y_bg  = {2'b0, I_bg_r} + ({2'b0, I_bg_g} << 1) + {2'b0, I_bg_b};
    wire [9:0] W_y_cur = {2'b0, I_cur_r} + ({2'b0, I_cur_g} << 1) + {2'b0, I_cur_b};
    wire signed [10:0] W_dy = W_y_cur - W_y_bg;      //亮度差（>>2 不影响比较量级，略）

    // 色度签名（9bit 差值 10bit 有符号）
    wire [8:0] W_s_bg  = absdiff(I_bg_r,  I_bg_g)  + absdiff(I_bg_g,  I_bg_b);
    wire [8:0] W_s_cur = absdiff(I_cur_r, I_cur_g) + absdiff(I_cur_g, I_cur_b);
    wire signed [9:0] W_ds = W_s_cur - W_s_bg;

    // 阴影判据（阈值为 >>2 后亮度域：dy 放大 4 倍，阈值也 ×4）
    // 2026-11-03 回退 v3→v2-单向（757e8bb 版）：v3 相对色度容忍在白墙/低色度背景
    //   （容忍仅 4~5）误滤手内部暗区 → 涂白稀疏。v2 的 s_bg>=12 前置为场景门控：
    //   灰白背景关闭阴影抑制保涂白完整；彩色背景启用滤真影子。ds 单向 <-6。
    assign O_shadow = (W_s_bg >= 9'd12)
                   && (W_dy < -11'sd48) && (W_dy > -11'sd280)
                   && (W_ds < -10'sd6);

    function [8:0] absdiff(input [7:0] a, b);
        absdiff = (a >= b) ? (a - b) : (b - a);
    endfunction
endmodule
