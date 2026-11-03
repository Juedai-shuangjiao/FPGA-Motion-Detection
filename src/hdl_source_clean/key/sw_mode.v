module sw_mode( 
    input wire       clk,
    input wire       rst_n,
    input wire [3:0] sw,
    output reg [1:0] mode
);
reg [1:0] sw_d1;
always @(posedge clk or negedge rst_n)begin
    if(!rst_n) begin
        sw_d1 <=2'b0;
        mode <= 2'b0;
     end else begin
        sw_d1 <=sw[1:0];
        mode <= sw_d1;
     end
end
endmodule
