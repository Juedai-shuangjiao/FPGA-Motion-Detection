//========================================================
// tb：sobel_adapt_thr 自适应阈值仿真（CNT_LOG2=10 加速：1024 拍/帧）
// 场景：梯度流 = 噪声（均值 8 的小幅值，占 90%）+ 真边缘（均值 100 大幅值，占 10%）
//   帧 1 统计 → 阈值 ≈ 1.5×mean ≈ 1.5×17.2 ≈ 26 左右
//   帧 2 应用：真边缘拍（100 > 26）O_edge=1 ✓、噪声拍（8 < 26）O_edge=0 ✓
//   光照翻倍场景：帧 3/4 注入「亮场景」（噪声 16、边缘 200）→ 阈值应自动升到 ~52，
//   边缘仍能检出（自适应生效验证）
//========================================================
`timescale 1ns/1ps
module tb_sobel_adapt;
    reg clk, rst_n;
    reg [7:0] grad;
    reg vld, fs;
    wire [7:0] thr;
    wire edge_out;
    integer fails = 0;
    integer i;
    integer edge_cnt, noise_cnt;   //帧 2 统计

    sobel_adapt_thr #(.CNT_LOG2(10)) u_dut (
        .I_clk(clk), .I_rst_n(rst_n), .I_grad(grad), .I_vld(vld),
        .I_fs_pulse(fs), .O_thr(thr), .O_edge(edge_out)
    );

    initial begin clk = 0; forever #5 clk = ~clk; end

    reg is_edge_prev;
    task run_frame(input [7:0] noise_amp, input [7:0] edge_amp, input do_count);
        begin
            edge_cnt = 0; noise_cnt = 0;
            is_edge_prev = 0;
            for(i = 0; i < 1024; i = i + 1) begin
                if((i % 10) == 9) grad <= edge_amp;   //每 10 拍 1 拍真边缘
                else              grad <= noise_amp;  //9 拍噪声
                vld <= 1'b1;
                @(posedge clk);   //NBA 生效，O_edge 已比较本拍 grad
                if(do_count) begin
                    if(edge_out) begin
                        if(is_edge_prev) edge_cnt = edge_cnt + 1;
                        else             noise_cnt = noise_cnt + 1;
                    end
                end
                is_edge_prev = ((i % 10) == 9);
            end
            vld <= 1'b0;
            // 帧末 fs 脉冲：锁存本帧统计 + 清零（对齐真实时序：fs 在帧边界）
            @(posedge clk); fs <= 1'b1;
            @(posedge clk); fs <= 1'b0;
            @(posedge clk);
        end
    endtask

    initial begin
        rst_n = 0; grad = 0; vld = 0; fs = 0;
        #30 rst_n = 1;
        #10;

        // 帧 1：统计（暗场景：噪声 8、边缘 100）
        run_frame(8'd8, 8'd100, 1'b0);
        #10;
        $display("帧1 后阈值 = %0d（期望 ≈ 25~28）", thr);
        if(!((thr >= 8'd22) && (thr <= 8'd32))) begin
            $display("FAIL: 帧1 阈值 %0d 超出预期 22~32", thr);
            fails = fails + 1;
        end else
            $display("PASS: 帧1 阈值自适应正确");

        // 帧 2：应用验证（暗场景）
        run_frame(8'd8, 8'd100, 1'b1);
        $display("帧2: 检出边缘拍 %0d（期望 102）、噪声误检 %0d（期望 0）", edge_cnt, noise_cnt);
        if(edge_cnt != 102) begin
            $display("FAIL: 帧2 边缘检出 %0d != 102", edge_cnt); fails = fails + 1;
        end else $display("PASS: 帧2 真边缘全检出");
        if(noise_cnt != 0) begin
            $display("FAIL: 帧2 噪声误检 %0d", noise_cnt); fails = fails + 1;
        end else $display("PASS: 帧2 噪声零误检");

        // 帧 3：亮场景统计（光照翻倍：噪声 16、边缘 200）
        run_frame(8'd16, 8'd200, 1'b0);
        #10;
        $display("帧3 后阈值 = %0d（期望 ≈ 50~55，自动跟随亮度）", thr);
        if(!((thr >= 8'd44) && (thr <= 8'd62))) begin
            $display("FAIL: 帧3 阈值 %0d 未随亮度抬升", thr); fails = fails + 1;
        end else $display("PASS: 帧3 阈值随亮度自适应");

        // 帧 4：亮场景应用——边缘仍应检出、噪声仍零误检
        run_frame(8'd16, 8'd200, 1'b1);
        $display("帧4: 检出边缘拍 %0d（期望 102）、噪声误检 %0d（期望 0）", edge_cnt, noise_cnt);
        if(edge_cnt != 102) begin
            $display("FAIL: 帧4 边缘检出 %0d != 102", edge_cnt); fails = fails + 1;
        end else $display("PASS: 帧4 亮场景边缘全检出");
        if(noise_cnt != 0) begin
            $display("FAIL: 帧4 噪声误检 %0d", noise_cnt); fails = fails + 1;
        end else $display("PASS: 帧4 亮场景噪声零误检");

        $display("===== 结束：%0d 失败 =====", fails);
        $finish;
    end
endmodule
