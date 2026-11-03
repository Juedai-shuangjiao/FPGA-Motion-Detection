//========================================================
// tb_sobel_thr_set —— sobel_threshold_set 模块仿真
// 验证 2026-11-03 三处改动：①复位值 512 ②步进 16（窗口窄细调）③边界封顶/保底 ④自动联动
//========================================================
`timescale 1ns/1ps
module tb_sobel_thr_set;

    reg         clk;
    reg         rst;
    reg         inc_tick, dec_tick;
    reg         enable;
    reg         auto_en;
    reg  [10:0] auto_val;
    wire [10:0] thr;

    sobel_threshold_set dut (
        .I_clk(clk), .I_rst(rst),
        .I_inc_tick(inc_tick), .I_dec_tick(dec_tick),
        .I_enable(enable),
        .I_auto_en(auto_en), .I_auto_val(auto_val),
        .O_threshold(thr)
    );

    integer errors = 0;
    integer total  = 0;

    initial begin
        clk = 0; rst = 1; inc_tick = 0; dec_tick = 0; enable = 0;
        auto_en = 0; auto_val = 11'd512;
        #50; rst = 0;   //释放复位（I_rst 高有效）
        #40; @(posedge clk); #1;

        total = total + 1;
        if(thr !== 11'd512) begin errors = errors + 1; $display("FAIL %0d 复位=512 实际=%0d", total, thr); end
        else $display("PASS %0d 复位=512", total);

        enable = 1;
        inc_tick = 1; @(posedge clk); #1 inc_tick = 0; @(posedge clk); #1;
        total = total + 1;
        if(thr !== 11'd528) begin errors = errors + 1; $display("FAIL %0d inc1=528 实际=%0d", total, thr); end
        else $display("PASS %0d inc1=528(步进16)", total);

        inc_tick = 1; @(posedge clk); #1 inc_tick = 0; @(posedge clk); #1;
        total = total + 1;
        if(thr !== 11'd544) begin errors = errors + 1; $display("FAIL %0d inc2=544 实际=%0d", total, thr); end
        else $display("PASS %0d inc2=544", total);

        dec_tick = 1; @(posedge clk); #1 dec_tick = 0; @(posedge clk); #1;
        total = total + 1;
        if(thr !== 11'd528) begin errors = errors + 1; $display("FAIL %0d dec1=528 实际=%0d", total, thr); end
        else $display("PASS %0d dec1=528", total);

        enable = 0;
        inc_tick = 1; @(posedge clk); #1 inc_tick = 0; @(posedge clk); #1;
        total = total + 1;
        if(thr !== 11'd528) begin errors = errors + 1; $display("FAIL %0d enable=0不调 实际=%0d", total, thr); end
        else $display("PASS %0d enable=0不调", total);

        //==== 自动联动：跟随联动值、按键忽略 ====
        auto_en = 1;
        auto_val = 11'd1088;
        @(posedge clk); #1;
        total = total + 1;
        if(thr !== 11'd1088) begin errors = errors + 1; $display("FAIL %0d 联动=1088 实际=%0d", total, thr); end
        else $display("PASS %0d 自动联动=1088", total);

        inc_tick = 1; @(posedge clk); #1 inc_tick = 0; @(posedge clk); #1;
        total = total + 1;
        if(thr !== 11'd1088) begin errors = errors + 1; $display("FAIL %0d 联动期按键忽略 实际=%0d", total, thr); end
        else $display("PASS %0d 联动期按键忽略", total);

        auto_en = 0;
        @(posedge clk); #1;

        enable = 1;
        repeat(100) begin inc_tick = 1; @(posedge clk); #1 inc_tick = 0; @(posedge clk); #1; end
        total = total + 1;
        if(thr !== 11'd2040) begin errors = errors + 1; $display("FAIL %0d 封顶2040 实际=%0d", total, thr); end
        else $display("PASS %0d 加满封顶2040", total);

        repeat(140) begin dec_tick = 1; @(posedge clk); #1 dec_tick = 0; @(posedge clk); #1; end
        total = total + 1;
        if(thr !== 11'd0) begin errors = errors + 1; $display("FAIL %0d 保底0 实际=%0d", total, thr); end
        else $display("PASS %0d 减到底保底0", total);

        rst = 1; #30; rst = 0; @(posedge clk); #1;
        total = total + 1;
        if(thr !== 11'd512) begin errors = errors + 1; $display("FAIL %0d 再复位=512 实际=%0d", total, thr); end
        else $display("PASS %0d 再复位=512", total);

        $display("========================================");
        $display("共 %0d 项，失败 %0d 项", total, errors);
        if(errors == 0) $display("ALL PASS");
        else $display("有 FAIL");
        $finish;
    end

    always #5 clk = ~clk;   //100MHz

endmodule
