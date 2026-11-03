//========================================================
// ram_c36c2ca3b3a7 仿真 stub（tb_canny_top_link 用）
// 行为模型：真双口 RAM、NOREG（无输出寄存器，异步读）、
// B 口 READBEFOREWRITE（同拍写读旧值——异步读模型天然满足：写发生在时钟沿后）。
// mem 初始清零（真实上电垃圾值由 canny 边界屏蔽挡，仿真清零避免 X 传播）。
//========================================================
`timescale 1ns/1ps
module ram_c36c2ca3b3a7 #(
    parameter DATA_WIDTH_A   = 33,
    parameter ADDR_WIDTH_A   = 9,
    parameter DATA_DEPTH_A   = 512,
    parameter DATA_WIDTH_B   = 33,
    parameter ADDR_WIDTH_B   = 9,
    parameter DATA_DEPTH_B   = 512,
    parameter REGMODE_A      = "NOREG",
    parameter WRITEMODE_A    = "NORMAL",
    parameter RESETMODE_A    = "ASYNC",
    parameter INIT_FILE      = "NONE",
    parameter REGMODE_B      = "NOREG",
    parameter FILL_ALL       = "NONE",
    parameter WRITEMODE_B    = "READBEFOREWRITE",
    parameter RESETMODE_B    = "ASYNC"
)(
    input  wire [DATA_WIDTH_A-1:0] dia,
    input  wire [ADDR_WIDTH_A-1:0] addra,
    input  wire                    wea,
    input  wire                    clka,
    input  wire [DATA_WIDTH_B-1:0] dib,
    input  wire [ADDR_WIDTH_B-1:0] addrb,
    input  wire                    web,
    input  wire                    clkb,
    output wire [DATA_WIDTH_A-1:0] doa,
    output wire [DATA_WIDTH_B-1:0] dob
);

    reg [DATA_WIDTH_A-1:0] mem [0:DATA_DEPTH_A-1];

    integer i;
    initial begin
        for(i = 0; i < DATA_DEPTH_A; i = i + 1)
            mem[i] = {DATA_WIDTH_A{1'b0}};
    end

    always @(posedge clka) begin
        if(wea) mem[addra] <= dia;
    end
    always @(posedge clkb) begin
        if(web) mem[addrb] <= dib;
    end

    assign doa = mem[addra];
    assign dob = mem[addrb];

endmodule
