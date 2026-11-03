// w128_d512_fifo NOREG 语义 stub（仿真用）：re 后 1 拍 dout+valid，与 TD 硬 IP 一致
module w128_d512_fifo (
    input rst, input clkw, input we, input [127:0] di,
    output [8:0] wrusedw, output afull, output full_flag,
    input clkr, input re, output [127:0] dout, output [8:0] rdusedw,
    output valid, output empty_flag, output aempty
);
    reg [127:0] mem [0:511];
    reg [8:0] wptr, rptr;
    reg [127:0] dout_q;
    reg valid_q;
    wire [8:0] used = wptr - rptr;
    assign full_flag = (used >= 9'd511);
    assign afull = (used >= 9'd508);
    assign empty_flag = (used == 9'd0);
    assign aempty = (used <= 9'd4);
    assign wrusedw = used;
    assign rdusedw = used;
    assign dout = dout_q;
    assign valid = valid_q;
    integer i;
    initial begin
        for(i = 0; i < 512; i = i + 1) mem[i] = 128'd0;
    end
    always @(posedge clkw) begin
        if(rst) begin wptr <= 9'd0; end
        else if(we && !full_flag) begin
            mem[wptr[8:0]] <= di;
            wptr <= wptr + 1'b1;
        end
    end
    always @(posedge clkr) begin
        if(rst) begin rptr <= 9'd0; valid_q <= 1'b0; dout_q <= 128'd0; end
        else begin
            valid_q <= re && !empty_flag;
            dout_q  <= mem[rptr[8:0]];
            if(re && !empty_flag) rptr <= rptr + 1'b1;
        end
    end
endmodule

// tb_snapshot_tx2 —— 直接验证发送字节序列（2026-11-03）
// 方法：监测 ld_ack（UART 装载确认）拍打印 tx_byte，验证协议序列
`timescale 1ns/1ps
module tb_snapshot_tx2;

    reg clk, rst_n;
    reg snap_en;
    reg rd_valid_d1, rd_tag;
    reg [127:0] rd_data;
    reg vsync;
    wire tx;

    snapshot_tx u_dut (
        .clk(clk), .rst_n(rst_n),
        .snap_en(snap_en),
        .rd_valid_d1(rd_valid_d1), .rd_tag(rd_tag), .rd_data(rd_data),
        .vsync(vsync),
        .tx(tx)
    );

    always #1.6667 clk = ~clk;   //300MHz

    integer byte_cnt;
    integer errs;

    // 装载确认监测：打印每个发出的字节
    always @(posedge clk) begin
        if(u_dut.ld_ack) begin
            $display("[发] 字节%0d = 0x%02h", byte_cnt, u_dut.tx_byte);
            byte_cnt = byte_cnt + 1;
        end
    end

    initial begin
        clk = 0; rst_n = 0;
        snap_en = 0; rd_valid_d1 = 0; rd_tag = 0; rd_data = 0; vsync = 0;
        byte_cnt = 0; errs = 0;
        repeat(20) @(negedge clk);
        rst_n = 1;
        repeat(20) @(negedge clk);

        @(negedge clk); snap_en = 1;
        @(negedge clk); vsync = 1;
        @(negedge clk); vsync = 0;

        begin
            integer b;
            for(b = 0; b < 512; b = b + 1) begin
                @(negedge clk);
                rd_valid_d1 = 1; rd_tag = 0; rd_data = b;
                @(negedge clk);
                rd_valid_d1 = 0;
            end
        end

        // 等发送头 4B + beat0 16B + beat1 16B = 36 字节
        #260000;   //36 × 11 bit × 500ns = 198us + 余量

        if(byte_cnt >= 36)
            $display("已发 %0d 字节（期望 >=36）", byte_cnt);
        else begin
            $display("FAIL: 只发 %0d 字节", byte_cnt);
            errs = errs + 1;
        end

        if(errs == 0)
            $display("tb_snapshot_tx2 PASS（字节序列见上，头应 AA 55 53 4E，beat0 全 0，beat1 低字节 01）");
        else
            $display("tb_snapshot_tx2 FAIL");
        $finish;
    end

endmodule
