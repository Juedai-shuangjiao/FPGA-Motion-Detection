module key_hold #(
    parameter CLK_FREQ = 50_000_000,
    parameter HOLD_MS  = 500
)(
    input  wire clk,
    input  wire rst_n,
    input  wire debounced,   //消抖后电平
    output reg  key_tick     //长按：按住期间每 HOLD_MS 一个脉冲
);
localparam HOLD_MAX = (CLK_FREQ / 1000) * HOLD_MS - 1;
reg [24:0] hold_cnt;
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        hold_cnt <= 0;
        key_tick  <= 0;
    end else if(!debounced) begin
        hold_cnt <= 0;
        key_tick  <= 0;
    end else if(hold_cnt == HOLD_MAX) begin
        hold_cnt <= 0;
        key_tick  <= 1;
    end else begin
        hold_cnt <= hold_cnt + 1'b1;
        key_tick  <= 0;
    end
end
endmodule