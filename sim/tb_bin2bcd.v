// tb_bin2bcd —— bin2bcd 输出验证（数码管「1   E」修复配套）
// 验证：512→0x0512（Sobel 阈值 BCD 显示）、128→0x0128、2040→0x2040、60→0x0060
`timescale 1ns/1ps
module tb_bin2bcd;

    reg  [15:0] bin;
    wire [15:0] bcd;

    bin2bcd dut (.bin(bin), .bcd(bcd));

    integer errors = 0;
    integer total  = 0;

    initial begin
        bin = 16'd512;   #10;
        total = total + 1; if(bcd !== 16'h0512) begin errors = errors + 1; $display("FAIL %0d 512→0512 实际=%h", total, bcd); end else $display("PASS %0d 512→0512", total);
        bin = 16'd128;   #10;
        total = total + 1; if(bcd !== 16'h0128) begin errors = errors + 1; $display("FAIL %0d 128→0128 实际=%h", total, bcd); end else $display("PASS %0d 128→0128", total);
        bin = 16'd2040;  #10;
        total = total + 1; if(bcd !== 16'h2040) begin errors = errors + 1; $display("FAIL %0d 2040→2040 实际=%h", total, bcd); end else $display("PASS %0d 2040→2040", total);
        bin = 16'd60;    #10;
        total = total + 1; if(bcd !== 16'h0060) begin errors = errors + 1; $display("FAIL %0d 60→0060 实际=%h", total, bcd); end else $display("PASS %0d 60→0060", total);
        bin = 16'd576;   #10;
        total = total + 1; if(bcd !== 16'h0576) begin errors = errors + 1; $display("FAIL %0d 576→0576 实际=%h", total, bcd); end else $display("PASS %0d 576→0576", total);

        $display("========================================");
        $display("共 %0d 项，失败 %0d 项", total, errors);
        if(errors == 0) $display("ALL PASS");
        $finish;
    end

endmodule
