//========================================================
// tb：thr_adaptive 亮度自适应阈值查表仿真
// 覆盖：4 档边界值（79/80/139/140/199/200）+ 中间值 + 极端值（0/255）
//========================================================
`timescale 1ns/1ps
module tb_thr_adaptive;
    reg [7:0] avg;
    wire [1:0] sel;
    integer fails = 0;

    thr_adaptive u_dut (.I_avg(avg), .O_thr_sel(sel));

    task check(input [7:0] a, input [1:0] exp);
        begin
            #10; avg = a; #10;
            if(sel !== exp) begin
                $display("FAIL: avg=%0d → sel=%0b 期望 %0b", a, sel, exp);
                fails = fails + 1;
            end else
                $display("PASS: avg=%0d → 档位 %0d", a, sel);
        end
    endtask

    initial begin
        avg = 0; #10;
        check(8'd0,   2'b00);   //全黑 → 25
        check(8'd50,  2'b00);   //暗 → 25
        check(8'd79,  2'b00);   //档 25 上界
        check(8'd80,  2'b01);   //档 40 下界
        check(8'd110, 2'b01);   //室内中间值
        check(8'd139, 2'b01);   //档 40 上界
        check(8'd140, 2'b10);   //档 60 下界
        check(8'd170, 2'b10);   //亮环境
        check(8'd199, 2'b10);   //档 60 上界
        check(8'd200, 2'b11);   //档 80 下界
        check(8'd230, 2'b11);   //强光
        check(8'd255, 2'b11);   //饱和
        $display("===== 结束：%0d 失败 =====", fails);
        $finish;
    end
endmodule
