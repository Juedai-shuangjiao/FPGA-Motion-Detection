//========================================================
// tb_auto_manual_sel —— 自动/手动曝光切换（KEY4 长按）仿真
// 覆盖用例：
//   ①复位默认自动（mode=0）
//   ②长按成立（tick）切一次 → 手动（mode=1）
//   ③同一长按周期后续 tick 不重复切换（按住期间 mode 稳定）
//   ④松开后再长按 → 切回自动
//   ⑤en=0（非 SW34=00）时 mode 锁定自动、tick 无效
//========================================================
`timescale 1ns/1ps
module tb_auto_manual_sel;

    reg clk, rst_n;
    reg en;
    reg debounced;
    reg tick;
    wire mode;

    auto_manual_sel u_am (
        .clk(clk), .rst_n(rst_n),
        .en(en),
        .debounced(debounced),
        .tick(tick),
        .mode(mode)
    );

    always #20.833 clk = ~clk;

    integer errs;
    integer chk_mode;

    initial begin
        clk = 0; rst_n = 0; en = 1; debounced = 0; tick = 0; errs = 0;
        #200 rst_n = 1;
        #100;

        //==== ① 复位默认自动 ====
        $display("[用例1] 复位后 mode = %0d（期望 0=自动）", mode);
        if(mode != 0) errs = errs + 1;

        //==== ② 长按成立切一次 → 手动 ====
        debounced = 1;
        #2000000;  //200ms 后 tick
        tick = 1; #41; tick = 0;
        #41;
        chk_mode = mode;
        $display("[用例2] 首个长按 tick 后 mode = %0d（期望 1=手动）", chk_mode);
        if(chk_mode != 1) errs = errs + 1;

        //==== ③ 同一长按周期继续 tick，mode 不再变 ====
        #2000000; tick = 1; #41; tick = 0;
        #2000000; tick = 1; #41; tick = 0;
        #41;
        $display("[用例3] 连续 tick 3 次后 mode = %0d（期望仍 1）", mode);
        if(mode != 1) errs = errs + 1;

        //==== ④ 松开再长按 → 切回自动 ====
        debounced = 0;
        #100000;
        debounced = 1;
        #2000000; tick = 1; #41; tick = 0;
        #41;
        $display("[用例4] 第二次长按后 mode = %0d（期望 0）", mode);
        if(mode != 0) errs = errs + 1;
        debounced = 0;
        #100000;

        //==== ⑤ en=0 保持状态（2026-11-03 用户反馈：拨回 00 不丢手动）====
        debounced = 1;
        #2000000; tick = 1; #41; tick = 0;
        #41;
        $display("[用例5a] en=1 长按后 mode = %0d（期望 1）", mode);
        if(mode != 1) errs = errs + 1;
        debounced = 0;
        en = 0;
        #100;
        $display("[用例5b] en=0 后 mode = %0d（期望保持 1，不再锁自动）", mode);
        if(mode != 1) errs = errs + 1;
        debounced = 1;
        #2000000; tick = 1; #41; tick = 0;
        #41;
        $display("[用例5c] en=0 时长按 tick 后 mode = %0d（期望仍 1，tick 无效）", mode);
        if(mode != 1) errs = errs + 1;
        debounced = 0;
        //==== ⑥ 回到 en=1 恢复切换（拨回 00 后长按还能切回自动）====
        en = 1;
        debounced = 1;
        #2000000; tick = 1; #41; tick = 0;
        #41;
        $display("[用例6] en 恢复后长按 mode = %0d（期望 0，切回自动）", mode);
        if(mode != 0) errs = errs + 1;
        debounced = 0;

        if(errs == 0)
            $display("tb_auto_manual_sel PASS");
        else
            $display("tb_auto_manual_sel FAIL: %0d 处不符", errs);
        $finish;
    end

endmodule
