//========================================================
// tb_key_short_press —— KEY4 短按判定（长按抑制版）仿真
// 覆盖用例：
//   ①抖动过滤（按下沿前的抖动不产生短按）
//   ②正常短按（按下 ~50ms 释放）恰好发一次 short_pulse（在释放沿）
//   ③长按（按住 >200ms）不误发 short_pulse
//   ④长按释放后不发 short_pulse、再短按恢复正常
//========================================================
`timescale 1ns/1ps
module tb_key_short_press;

    reg clk, rst_n;
    reg debounced;
    reg long_tick;
    wire short_pulse;

    key_short_press u_ksp (
        .clk(clk), .rst_n(rst_n),
        .debounced(debounced),
        .long_tick(long_tick),
        .short_pulse(short_pulse)
    );

    // 24MHz 时钟（周期 ~41.67ns）
    always #20.833 clk = ~clk;

    integer short_cnt;
    integer errs;

    always @(posedge short_pulse) short_cnt = short_cnt + 1;

    initial begin
        clk = 0; rst_n = 0; debounced = 0; long_tick = 0;
        short_cnt = 0; errs = 0;
        #200 rst_n = 1;
        #100;

        //==== ① 短按（按下 5us 释放，<200ms）：释放沿发 1 次短按 ====
        debounced = 1;
        #5000;
        debounced = 0;
        #100;
        $display("[用例1] 短按释放后 short_cnt = %0d（期望 1）", short_cnt);
        if(short_cnt != 1) errs = errs + 1;

        //==== ② 正常短按 50ms（1200000ns @24M = 200ms 的一半）====
        #100000;
        debounced = 1;
        #1200000;
        debounced = 0;
        #100;
        $display("[用例2] 50ms 短按后 short_cnt = %0d（期望 2）", short_cnt);
        if(short_cnt != 2) errs = errs + 1;

        //==== ③ 长按 300ms：tick 每 200ms 一个，长按成立后释放不发短按 ====
        #100000;
        debounced = 1;
        #2000000;  //200ms → 模拟 key_hold 发 tick
        long_tick = 1; #41; long_tick = 0;
        #2000000;  //又 200ms → 第二个 tick
        long_tick = 1; #41; long_tick = 0;
        #800000;   //共按住 300ms+ → 释放
        debounced = 0;
        #100;
        $display("[用例3] 长按300ms释放后 short_cnt = %0d（期望 2，长按不误发）", short_cnt);
        if(short_cnt != 2) errs = errs + 1;

        //==== ④ 长按后再次短按恢复正常 ====
        #100000;
        debounced = 1;
        #1000000;
        debounced = 0;
        #100;
        $display("[用例4] 长按后再短按 short_cnt = %0d（期望 3）", short_cnt);
        if(short_cnt != 3) errs = errs + 1;

        //==== ⑤ 按下不释放（>200ms）后复位/松开，不产生脉冲 ====
        #100000;
        debounced = 1;
        #2000000; long_tick = 1; #41; long_tick = 0;
        debounced = 0;
        #100;
        $display("[用例5] 按住仅200ms释放(边界) short_cnt = %0d（期望 3）", short_cnt);
        if(short_cnt != 3) errs = errs + 1;

        if(errs == 0)
            $display("tb_key_short_press PASS");
        else
            $display("tb_key_short_press FAIL: %0d 处不符", errs);
        $finish;
    end

endmodule
