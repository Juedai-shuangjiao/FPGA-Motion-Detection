//========================================================
// tb_algo_mode_sel —— 算法模式使能锁定验证（2026-11-02 KEY4 双驱动修复）
// 验证点：
//   ① en=1：KEY4 脉冲正常循环 0→1→2→3→0
//   ② en=0：KEY4 脉冲不切换，mode 锁定/复位 0（原样）
//   ③ en 从 1 切 0：mode 立即回 0；再切回 1：从 0 重新开始循环
//   ④ 与 disp_mode_sel 组合：填充模式（en=0）按 KEY4 只动 disp_mode 不动 algo_mode
// 编译：verilator_bin --binary --timing -Wno-fatal --public-flat-rw --top-module tb_algo_mode_sel algo_mode_sel.v disp_mode_sel.v tb_algo_mode_sel.v
//========================================================
`timescale 1ns/1ps
module tb_algo_mode_sel;

    reg clk, rst_n, key_pulse, en_fill;
    wire [2:0] mode;
    wire [1:0] disp_mode;
    // en_fill = 区域填充模式使能（SW3&&SW4）：disp_mode_sel 在 en_fill=1 时吃 KEY4，
    // algo_mode_sel 在 en_fill=0 时吃 KEY4（两模块互斥，KEY4 只归一个模块）
    wire en_algo = ~en_fill;

    algo_mode_sel u_algo (
        .clk(clk), .rst_n(rst_n), .key_pulse(key_pulse), .en(en_algo), .mode(mode)
    );
    disp_mode_sel u_disp (
        .clk(clk), .rst_n(rst_n), .key_pulse(key_pulse), .en(en_fill), .mode(disp_mode)
    );

    integer err_cnt;

    task check;
        input [31:0] cond;
        input [255*8:1] msg;
        begin
            if(!cond) begin
                err_cnt = err_cnt + 1;
                $display("FAIL [t=%0t] %0s", $time, msg);
            end
        end
    endtask

    // 按一次 KEY4（单拍脉冲）
    task press_key;
        begin
            @(negedge clk); key_pulse = 1'b1;
            @(posedge clk);
            @(negedge clk); key_pulse = 1'b0;
            @(posedge clk);
        end
    endtask

    always #5 clk = ~clk;

    initial begin
        clk = 0; rst_n = 0; key_pulse = 0; en_fill = 0; err_cnt = 0;
        repeat(5) @(posedge clk);
        @(negedge clk); rst_n = 1'b1;
        @(posedge clk);

        //========== ① 非填充（en_fill=0 → algo en=1）正常循环 ==========
        check(mode == 3'd0, "复位后 mode=0");
        press_key; check(mode == 3'd1, "①第1按 mode=1");
        press_key; check(mode == 3'd2, "①第2按 mode=2");
        press_key; check(mode == 3'd3, "①第3按 mode=3");
        press_key; check(mode == 3'd0, "①第4按回绕 mode=0");
        press_key; check(mode == 3'd1, "①第5按 mode=1");

        //========== ② 进填充（en_fill=1）：algo 锁定/复位原样 ==========
        @(negedge clk); en_fill = 1'b1;
        @(posedge clk);      //DUT 采样 en 变化
        @(posedge clk);      //mode <= 0 生效
        check(mode == 3'd0, "②进填充立即回0");
        press_key; check(mode == 3'd0, "②填充按键不切 mode=0");
        press_key; check(mode == 3'd0, "②填充再按仍 mode=0");

        //========== ③ 退出填充：algo 从 0 重新循环 ==========
        @(negedge clk); en_fill = 1'b0;
        @(posedge clk); @(posedge clk);
        press_key; check(mode == 3'd1, "③退出后第1按 mode=1");
        press_key; check(mode == 3'd2, "③第2按 mode=2");

        //========== ④ 组合：填充模式（en_fill=1）按 KEY4 只动 disp_mode ==========
        // 先把 algo_mode 停在 2，再进填充：algo_mode 应回 0
        @(negedge clk); en_fill = 1'b1;
        @(posedge clk); @(posedge clk);
        check(mode == 3'd0, "④进填充 algo_mode 回0");
        check(disp_mode == 2'd0, "④进填充 disp_mode=0(涂白)");
        press_key;   //KEY4：disp_mode 0→1（边缘），algo_mode 不动
        check(mode == 3'd0, "④填充按KEY4 algo_mode 仍0");
        check(disp_mode == 2'd1, "④填充按KEY4 disp_mode=1(边缘)");
        press_key;   //KEY4：disp_mode 1→2（原图），algo_mode 不动
        check(mode == 3'd0, "④填充再按 algo_mode 仍0");
        check(disp_mode == 2'd2, "④填充再按 disp_mode=2(原图)");
        press_key;   //KEY4：disp_mode 2→0 回绕
        check(mode == 3'd0, "④填充三按 algo_mode 仍0");
        check(disp_mode == 2'd0, "④填充三按 disp_mode 回0(涂白)");

        //========== ⑤ 退出填充：algo_mode 仍 0，KEY4 恢复算法循环 ==========
        @(negedge clk); en_fill = 1'b0;
        @(posedge clk); @(posedge clk);
        press_key; check(mode == 3'd1, "⑤退出填充第1按 mode=1");
        press_key; check(mode == 3'd2, "⑤第2按 mode=2");

        if(err_cnt == 0) $display("ALL PASS");
        else             $display("FAILED: %0d errors", err_cnt);
        $finish;
    end

endmodule
