//========================================================
// 模块：key_short_press —— KEY4 短按判定（长按抑制版）
// 功能：KEY4 现在是「短按=切算法画面、长按=切自动/手动」一 key 两用，
//       必须从根上分清长短按：长按（按住满 HOLD_MS）的开头也是一次按下沿，
//       若短按用「按下沿」判定，长按时必然误触发一次短按。
// 方案：短按 = 「释放沿」且「本次按住期间未产生长按 tick」。
//       key_hold 的 tick 在按住满 HOLD_MS 时发出；若在 HOLD_MS 内释放，
//       说明是短按，释放沿发 short_pulse；若 tick 已来过（长按成立），
//       本次按键不再发短按脉冲（long_held 锁存，释放时清零）。
// 代价：短按响应移到手指释放瞬间（点按一般 50~100ms，几乎无感）。
//========================================================
module key_short_press (
    input  wire clk,          //时钟（24MHz）
    input  wire rst_n,        //复位，低有效
    input  wire debounced,    //消抖后按键电平（按下=1，来自 debounce）
    input  wire long_tick,    //长按 tick（key_hold 输出，按住满 HOLD_MS 发出）
    output reg  short_pulse   //短按脉冲（释放沿 + 未长按成立）
);

    reg debounced_d1;   //按键电平打 1 拍（释放沿检测）
    reg long_held;      //本次按键长按已成立锁存（tick 置位、松开清零）

    wire neg_edge = debounced_d1 && !debounced;   //释放沿（1→0）

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            debounced_d1 <= 1'b0;
            long_held    <= 1'b0;
            short_pulse  <= 1'b0;
        end else begin
            debounced_d1 <= debounced;
            if(!debounced)
                long_held <= 1'b0;          //松开清零，下次按键重新判定
            else if(long_tick)
                long_held <= 1'b1;          //长按成立（tick 来过），锁存

            // 短按 = 释放沿 && 本次未长按成立
            if(neg_edge && !long_held)
                short_pulse <= 1'b1;
            else
                short_pulse <= 1'b0;
        end
    end

endmodule
