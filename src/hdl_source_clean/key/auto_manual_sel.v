//========================================================
// 模块：auto_manual_sel —— 自动/手动曝光切换（KEY4 长按）
// 功能：SW34=00（原样模式）时，KEY4 长按成立切一次自动/手动曝光模式。
//       0=自动（复位默认） 1=手动。
// 细节：key_hold 的 tick 在按住期间每 HOLD_MS 一个（连续 tick），
//       若每个 tick 都切换会来回翻——用 held_flag 锁存：
//       一次长按周期（按下→松开）内只切一次；松开清零，下次长按再切。
//========================================================
module auto_manual_sel (
    input  wire clk,          //时钟（24MHz）
    input  wire rst_n,        //复位，低有效
    input  wire en,           //使能（仅 SW34=00 原样模式；其他模式锁定自动）
    input  wire debounced,    //消抖后按键电平（KEY4，按下=1）
    input  wire tick,         //长按 tick（key_hold 输出）
    output reg  mode          //0=自动曝光 1=手动曝光
);

    reg held_flag;   //本次长按已切换锁存（tick 置位、松开清零）

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            mode      <= 1'b0;
            held_flag <= 1'b0;
        end else if(!en) begin
            held_flag <= 1'b0;
            // 2026-11-03 用户反馈：非 00 模式不再复位自动，mode 保持——
            //   拨到 123 再拨回 00 手动状态不丢（原实现锁自动，切回 00 变自动）
        end else begin
            if(!debounced)
                held_flag <= 1'b0;    //松开清零
            else if(tick && !held_flag) begin
                mode      <= ~mode;   //长按成立：切一次自动/手动
                held_flag <= 1'b1;
            end
        end
    end

endmodule
