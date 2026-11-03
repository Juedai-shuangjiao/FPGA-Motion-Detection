//========================================================
// tb_disp_mode_sel —— 显示模式三态循环切换仿真验证（2026-11-01）
// 验证点：
//   ① en=0（非区域填充模式）按键不响应、mode 锁 0
//   ② en=1 按键循环 0→1→2→0（三态无卡死）
//   ③ en 拉低回锁 0
// 编译：iverilog -g2012 -o tb_disp_mode_sel.vvp disp_mode_sel.v tb_disp_mode_sel.v && vvp tb_disp_mode_sel.vvp
//========================================================
`timescale 1ns/1ps
module tb_disp_mode_sel;

    reg        clk, rst_n, key_pulse, en;
    wire [1:0] mode;

    disp_mode_sel dut (
        .clk(clk), .rst_n(rst_n), .key_pulse(key_pulse), .en(en), .mode(mode)
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

    always #5 clk = ~clk;

    task press_key;
        begin
            @(negedge clk); key_pulse = 1'b1;
            @(posedge clk);
            @(negedge clk); key_pulse = 1'b0;
            @(posedge clk);
        end
    endtask
    task set_en;
        input e;
        begin
            @(negedge clk); en = e;
            @(posedge clk);
        end
    endtask

    initial begin
        clk = 0; rst_n = 0; key_pulse = 0; en = 0; err_cnt = 0;
        repeat(5) @(posedge clk);
        @(negedge clk); rst_n = 1'b1;
        repeat(2) @(posedge clk);

        // ① en=0：按键不响应
        press_key;
        @(posedge clk);
        check(mode == 2'd0, "en=0 按键后 mode 应锁 0");

        // ② en=1：三态循环 0→1→2→0→1
        set_en(1'b1);
        repeat(1) @(posedge clk);
        press_key;
        @(posedge clk);
        check(mode == 2'd1, "第 1 次按键应 0→1");
        press_key;
        @(posedge clk);
        check(mode == 2'd2, "第 2 次按键应 1→2");
        press_key;
        @(posedge clk);
        check(mode == 2'd0, "第 3 次按键应 2→0（回绕）");
        press_key;
        @(posedge clk);
        check(mode == 2'd1, "第 4 次按键应 0→1（回绕后继续）");

        // ③ en 拉低回锁 0
        set_en(1'b0);
        @(posedge clk);
        check(mode == 2'd0, "en 拉低后 mode 应回 0");
        press_key;
        @(posedge clk);
        check(mode == 2'd0, "en=0 再按键仍锁 0");

        // ④ 复位回 0
        @(negedge clk); rst_n = 1'b0;
        @(posedge clk);
        @(negedge clk); rst_n = 1'b1;
        @(posedge clk);
        set_en(1'b1);
        @(posedge clk);
        check(mode == 2'd0, "复位后 mode 应 0");

        $display("=== disp_mode_sel err=%0d ===", err_cnt);
        if(err_cnt == 0) $display("ALL PASS");
        else $display("FAILED");
        $finish;
    end

endmodule
