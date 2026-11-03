//========================================================
// tb：bg_avg_ema 背景多帧平均仿真
// 场景：背景真值 100，每帧采样值 = 100 ± 噪声（帧 1 开始从初值 0 收敛）
//   帧 1：cur=100（背景区初值 0）→ ema = 0 + 20 = 20
//   帧 2：ema = 20 + (100-20)/5 = 36
//   帧 3：48.8 → 帧 5 后收敛到 ≈100
//   噪声验证：连续 5 帧给 ±20 交替噪声，输出波动应衰减 ≈5 倍
//========================================================
`timescale 1ns/1ps
module tb_bg_avg_ema;
    reg clk, rst_n;
    reg [23:0] cur, old;
    reg vld;
    wire [23:0] obg;
    wire ovld;
    integer fails = 0;
    integer i, f;

    bg_avg_ema u_dut (.I_clk(clk), .I_rst_n(rst_n), .I_cur(cur), .I_old(old), .I_vld(vld), .O_bg(obg), .O_vld(ovld));

    initial begin clk = 0; forever #5 clk = ~clk; end

    // 收敛测试：6 帧、每帧 10 拍（简化帧）
    initial begin
        rst_n = 0; cur = 0; old = 0; vld = 0;
        #30 rst_n = 1;
        #10;
        for(f = 0; f < 6; f = f + 1) begin
            for(i = 0; i < 10; i = i + 1) begin
                cur <= 24'h64_64_64;   //100,100,100
                old <= obg;            //上一拍输出作为旧背景（模拟 DDR 读回）
                vld <= 1'b1;
                @(posedge clk);
            end
        end
        vld <= 1'b0;
        #10;
        $display("收敛测试：6 帧后 obg = %0d（期望 ≈ 98~100）", obg[7:0]);
        if(!((obg[7:0] >= 8'd96) && (obg[7:0] <= 8'd100))) begin
            $display("FAIL: 收敛值 %0d 异常", obg[7:0]); fails = fails + 1;
        end else $display("PASS: 6 帧收敛到背景真值");

        // 噪声衰减测试（真实语义）：old 固定 100 = DDR 背景区上帧值（不逐拍反馈）
        //   cur 交替 80/120（±20 噪声）→ obg = 100±4（输出波动压到输入的 1/5）
        old = 24'h64_64_64;
        for(f = 0; f < 6; f = f + 1) begin
            if(f % 2 == 0) cur <= 24'h50_50_50;   //80
            else           cur <= 24'h78_78_78;   //120
            vld <= 1'b1;
            @(posedge clk);
        end
        vld <= 1'b0;
        @(posedge clk);
        #5;
        $display("噪声测试：±20 交替后 obg = %0d（期望 96 或 104：波动压到 ±4）", obg[7:0]);
        if(!((obg[7:0] == 8'd96) || (obg[7:0] == 8'd104))) begin
            $display("FAIL: 噪声衰减异常 %0d", obg[7:0]); fails = fails + 1;
        end else $display("PASS: ±20 噪声被 EMA 压到 ±4");

        // 单步精确性：old=100、cur=110 → obg = 100 + 10/5 = 102
        old = 24'h64_64_64; cur = 24'h6E_6E_6E;   //110
        vld <= 1'b1; @(posedge clk); @(posedge clk); vld <= 1'b0;
        #5;
        $display("单步测试：old=100 cur=110 → obg=%0d（期望 102）", obg[7:0]);
        if(obg[7:0] != 8'd102) begin
            $display("FAIL: 单步 EMA %0d != 102", obg[7:0]); fails = fails + 1;
        end else $display("PASS: 单步 EMA 精确");

        $display("===== 结束：%0d 失败 =====", fails);
        $finish;
    end
endmodule
