//========================================================
// lb_stub_impl —— line_buffer_demosaic 仿真 stub（tb_canny_top_link 用）
// 语义与真实 BRAM 版一致：I_valid 时写地址 +1（I_tuser 帧首复位 0），
// 同步读输出「上一行」旧值（输出比输入延迟 1 拍）。
// 深度 512（IMG_WIDTH 320 组够用）。
//========================================================
`timescale 1ns/1ps
module line_buffer_demosaic #(
    parameter IMG_HEIGHT = 720,
    parameter IMG_WIDTH  = 1280
)(
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire        I_tuser,     //帧首（写地址复位）
    input  wire        I_valid,     //写使能
    input  wire [32:0] I_data,      //33bit（32 数据 + 1 tuser 位）
    output wire        O_valid,     //延迟 1 拍的 valid
    output wire [32:0] O_data       //上一行同组数据（读旧值）
);

    reg [8:0]  waddr;
    reg [32:0] mem [0:511];
    reg [32:0] rdata;
    reg        valid_o_r;

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            waddr <= 9'd0;
            rdata <= 33'd0;
            valid_o_r <= 1'b0;
        end else begin
            if(I_tuser)
                waddr <= 9'd0;
            else if(I_valid)
                waddr <= waddr + 1'b1;
            rdata <= mem[waddr];          //读旧值（写前）
            valid_o_r <= I_valid;
            if(I_valid)
                mem[waddr] <= I_data;     //读旧写新
        end
    end

    assign O_data  = rdata;
    assign O_valid = valid_o_r;

endmodule
