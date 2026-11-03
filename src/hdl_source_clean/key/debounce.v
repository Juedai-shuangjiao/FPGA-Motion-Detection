 /*
    输出按键消抖后的信号
 */
 
 module debounce #(
    parameter CLK_FREQ    = 50_000_000,
    parameter DEBOUNCE_MS = 20
)(
    input  wire clk,
    input  wire rst_n,
    input  wire key_in,      //原始按键：按下=0
    output reg  debounced    //消抖后电平：1=按下稳定，0=松开
);
// 打两拍 + 消抖计数 + debounced（照抄 key_debounce 前三段）
localparam CNT_MAX  = (CLK_FREQ / 1000) * DEBOUNCE_MS;
reg        key_d1, key_d2;          // 打两拍用，各 1 位
reg [23:0] cnt;                     // 消抖计数器，24 位
always @(posedge clk or negedge rst_n)begin  // 时钟上升沿 或 复位下降沿 触发
    if(!rst_n) begin
        key_d1 <= 1'b1;   // 复位时默认「松开」状态
        key_d2 <= 1'b1;
    end else begin
        key_d1 <= key_in;   // 第一拍
        key_d2 <= key_d1;   // 第二拍
    end
end
always @(posedge clk or negedge rst_n) begin  // 时钟上升沿 或 复位下降沿 触发
    if(!rst_n)
            cnt <= 0;
    else if(key_d2 == 1'b0) begin      // 按下（低电平）
        if(cnt < CNT_MAX)
            cnt <= cnt + 1'b1;         // 没数满，继续数
        // 数满了就保持不动（cnt 停在 CNT_MAX）
    end else begin
        cnt <= 0; 
    end                      // 松开，立刻清零
end
always @(posedge clk or negedge rst_n) begin
        if(!rst_n)
            debounced <= 1'b0;
        else if(key_d2 == 1'b1)      // 松开 → 清 0
            debounced <= 1'b0;
        else if(cnt == CNT_MAX)      // 按下且数满 → 置 1
            debounced <= 1'b1;
        // 其他情况（按下但还没数满）：debounced 保持上一拍的值
end

endmodule
