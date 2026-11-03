//========================================================
// tb_thr_auto_link —— 阈值自动联动仿真（threshold_set + sobel_threshold_set）
// 覆盖用例：
//   ①auto_en=1 时二值化阈值跟随 I_auto_val 变化（模拟 avg 波动），按键 tick 被忽略
//   ②auto_en=0 时按键正常调节（+/-、封顶、保底）
//   ③Sobel 阈值 auto_en=1 跟随 11bit 联动值
//   ④Sobel 手动步进 = 16
//   ⑤复位初值：二值化 60、Sobel 512
//========================================================
`timescale 1ns/1ps
module tb_thr_auto_link;

    reg clk, rst;
    reg inc_tick, dec_tick, enable;
    reg auto_en;
    reg [7:0] auto_val;
    reg [10:0] sobel_auto_val;
    wire [7:0] thr;
    wire [10:0] sobel_thr;

    threshold_set u_thr (
        .I_clk(clk), .I_rst(rst),
        .I_inc_tick(inc_tick), .I_dec_tick(dec_tick),
        .I_enable(enable),
        .I_auto_en(auto_en), .I_auto_val(auto_val),
        .O_threshold(thr)
    );
    sobel_threshold_set u_sthr (
        .I_clk(clk), .I_rst(rst),
        .I_inc_tick(inc_tick), .I_dec_tick(dec_tick),
        .I_enable(enable),
        .I_auto_en(auto_en), .I_auto_val(sobel_auto_val),
        .O_threshold(sobel_thr)
    );

    always #20.833 clk = ~clk;

    integer errs;
    task tick_inc;
        begin inc_tick = 1; #41; inc_tick = 0; #100; end
    endtask
    task tick_dec;
        begin dec_tick = 1; #41; dec_tick = 0; #100; end
    endtask

    initial begin
        clk = 0; rst = 1; inc_tick = 0; dec_tick = 0; enable = 0;
        auto_en = 0; auto_val = 60; sobel_auto_val = 512;
        errs = 0;
        #200 rst = 0;
        #100;

        //==== ① 复位初值 ====
        $display("[用例1] 复位后 二值化=%0d（期望60） Sobel=%0d（期望512）", thr, sobel_thr);
        if(thr != 60 || sobel_thr != 512) errs = errs + 1;

        //==== ② 手动模式（auto_en=0）按键调节 ====
        enable = 1;
        tick_inc;
        $display("[用例2] 手动 +1 后 二值化=%0d（期望61）", thr);
        if(thr != 61) errs = errs + 1;
        tick_dec; tick_dec;
        $display("[用例3] 手动 -2 后 二值化=%0d（期望59）", thr);
        if(thr != 59) errs = errs + 1;
        // Sobel 手动步进 16（注意：二值化/Sobel 共享 inc/dec，此前的 tick 也作用于 Sobel：
        //   512 +1 -2 +1 = 512；真实硬件里 enable 按 S_mode 门控不会同时调，此处仅验步进）
        tick_inc;
        $display("[用例4] Sobel 手动再 +1 tick 后 = %0d（期望512，步进16）", sobel_thr);
        if(sobel_thr != 512) errs = errs + 1;

        //==== ③ auto_en=1：跟随联动值，按键忽略 ====
        auto_en = 1;
        auto_val = 50;
        sobel_auto_val = 1088;
        #41;
        $display("[用例5] auto 联动值 50/1088 后 二值化=%0d（期望50） Sobel=%0d（期望1088）", thr, sobel_thr);
        if(thr != 50 || sobel_thr != 1088) errs = errs + 1;
        // 联动期间按加键 → 被忽略
        tick_inc; tick_inc;
        $display("[用例6] 联动期间按键+2 后 二值化=%0d（期望仍50，按键忽略）", thr);
        if(thr != 50) errs = errs + 1;

        //==== ④ 联动值跟随 avg 变化（模拟自动曝光亮度波动）====
        auto_val = 65;
        sobel_auto_val = 768;
        #41;
        $display("[用例7] avg 变化→联动值 65/768 后 二值化=%0d Sobel=%0d（期望65/768）", thr, sobel_thr);
        if(thr != 65 || sobel_thr != 768) errs = errs + 1;

        //==== ⑤ 切回手动：按键恢复调节、值从联动值继续（不跳回初值）====
        auto_en = 0;
        #41;
        tick_inc;
        $display("[用例8] 切回手动 +1 后 二值化=%0d（期望66，连续不跳变）", thr);
        if(thr != 66) errs = errs + 1;
        tick_dec;
        $display("[用例9] 手动 -1 后 Sobel=%0d（期望768：联动768+1-1，与二值化共享tick）", sobel_thr);
        if(sobel_thr != 768) errs = errs + 1;

        //==== ⑥ 封顶/保底 ====
        auto_en = 1; auto_val = 255; sobel_auto_val = 2040;
        #41;
        $display("[用例10] 联动上限 255/2040：二值化=%0d Sobel=%0d（期望255/2040）", thr, sobel_thr);
        if(thr != 255 || sobel_thr != 2040) errs = errs + 1;
        auto_en = 0;
        tick_inc;  //二值化封顶 255 不变；Sobel 2040 封顶
        #41;
        $display("[用例11] 封顶后再+1：二值化=%0d Sobel=%0d（期望255/2040不变）", thr, sobel_thr);
        if(thr != 255 || sobel_thr != 2040) errs = errs + 1;
        auto_en = 1; auto_val = 0; sobel_auto_val = 0;
        #41;
        auto_en = 0;
        tick_dec;  //保底 0
        #41;
        $display("[用例12] 保底 0 后再-1：二值化=%0d Sobel=%0d（期望0/0不变）", thr, sobel_thr);
        if(thr != 0 || sobel_thr != 0) errs = errs + 1;

        if(errs == 0)
            $display("tb_thr_auto_link PASS");
        else
            $display("tb_thr_auto_link FAIL: %0d 处不符", errs);
        $finish;
    end

endmodule
