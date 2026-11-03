module key_pulse (
    input  wire clk,
    input  wire rst_n,
    input  wire debounced,   //消抖后电平
    output reg  key_pulse    //按下沿脉冲
);
reg debounced_d;
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        debounced_d <= 1'b0;
        key_pulse   <= 1'b0;
    end else begin
        debounced_d <= debounced;
        key_pulse   <= debounced && !debounced_d;   //0→1沿
    end
end
endmodule