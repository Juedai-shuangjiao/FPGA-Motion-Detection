//========================================================
// tb：erode_1bit 双次腐蚀吃噪点团仿真
// 图案（12×16，行扫描）：
//   行0-1：空
//   行2-6：列 11-16 为 1（6 宽 × 5 高目标，0x7E00）
//   行7：空（隔离）
//   行8：3px 横线噪点（0x0038）
//   行9-11：空
// 单次腐蚀（3×3）：3px 横线（高1）被吃 ✓；目标核 = 行3/4 的 4 宽（4×2）
// 双次腐蚀（等效 5×5）：目标核 = 行4 的 2 宽（2×1）仍存活 ✓；横线区干净 ✓
//========================================================
`timescale 1ns/1ps
module tb_erode_1bit;
    reg clk, rst_n;
    reg pix, vld, fs;
    wire o1, v1, o2, v2;
    integer fails = 0;
    integer i, j;

    erode_1bit #(.ROW_W(16)) u_e1 (.I_clk(clk), .I_rst_n(rst_n), .I_pix(pix), .I_vld(vld), .I_fs(fs), .O_pix(o1), .O_vld(v1));
    erode_1bit #(.ROW_W(16)) u_e2 (.I_clk(clk), .I_rst_n(rst_n), .I_pix(o1), .I_vld(v1), .I_fs(fs), .O_pix(o2), .O_vld(v2));

    reg [15:0] frame [0:11];   //12 行图案
    integer t;
    reg [15:0] out1 [0:11];
    reg [15:0] out2 [0:11];

    initial begin clk = 0; forever #5 clk = ~clk; end

    initial begin
        rst_n = 0; pix = 0; vld = 0; fs = 0;
        for(i=0;i<12;i=i+1) begin frame[i] = 16'h0000; out1[i]=0; out2[i]=0; end
        for(i=2;i<=6;i=i+1) frame[i] = 16'h7E00;   //行2-6：6 宽目标（bit14..9）
        frame[8] = 16'h0038;                        //行8：3px 横线（bit5/4/3）
        #30 rst_n = 1;
        #10;

        // 注入 1 帧 + 捕获（输出行 = 输入行同拍，列延迟 1 拍）
        @(posedge clk); fs <= 1'b1;
        @(posedge clk); fs <= 1'b0;
        for(i = 0; i < 12; i = i + 1) begin
            for(j = 1; j <= 16; j = j + 1) begin
                pix <= frame[i][16-j];   //j=1 注入列 0（bit15）
                vld <= 1'b1;
                @(posedge clk);
                // O_pix 拍 j 的中心列 = j-2（R_cur_m 缓存 1 拍 + 注入列 j-1）→ 写 bit 17-j
                // 双次级联：o2 输入流 = o1（列已延迟 j-2）→ o2 中心列 = j-3 → 写 bit 18-j
                // 输出行 = 输入行-1（双次 -2）；首拍中心列无效跳过
                if((i >= 1) && (j >= 2)) begin
                    if(o1) out1[i-1][17-j] = 1'b1;
                end
                if((i >= 2) && (j >= 3)) begin
                    if(o2) out2[i-2][18-j] = 1'b1;
                end
            end
        end
        vld <= 1'b0;

        $display("单次腐蚀输出（目标行2-6，横线行8）：");
        for(i=2;i<=8;i=i+1) $display("  行%0d: %b", i, out1[i]);
        $display("双次腐蚀输出：");
        for(i=2;i<=8;i=i+1) $display("  行%0d: %b", i, out2[i]);

        // 检查 1：单次腐蚀吃 3px 横线（行8 应全 0）
        if(out1[8] != 16'h0000) begin
            $display("FAIL: 单次腐蚀未吃掉 3px 横线（行8=%b）", out1[8]); fails = fails + 1;
        end else $display("PASS: 单次腐蚀吃掉 3px 横线");
        // 检查 2：单次腐蚀目标核 = 输入行3/4（输出对齐后仍行3/4）的 4 宽（bit13..10）
        if(!((out1[3][13:10] == 4'b1111) && (out1[4][13:10] == 4'b1111))) begin
            $display("FAIL: 单次腐蚀目标核异常（行3=%b 行4=%b）", out1[3], out1[4]); fails = fails + 1;
        end else $display("PASS: 单次腐蚀目标核 4x2 正确");
        // 检查 3：双次腐蚀目标存活（输入行4 的 2 宽核 → 输出行4，bit12/11）
        if(out2[4][12:11] != 2'b11) begin
            $display("FAIL: 双次腐蚀目标消失（行4=%b）", out2[4]); fails = fails + 1;
        end else $display("PASS: 双次腐蚀后目标 2x1 核存活");
        // 检查 4：双次腐蚀横线区干净
        if(out2[8] != 16'h0000) begin
            $display("FAIL: 双次腐蚀横线区残留（行8=%b）", out2[8]); fails = fails + 1;
        end else $display("PASS: 双次腐蚀横线区干净");
        // 检查 5：双次腐蚀目标周围无残留散点（除行4 核外全 0）
        if(!((out2[2] == 16'h0000) && (out2[3] == 16'h0000) && (out2[5] == 16'h0000) && (out2[6] == 16'h0000))) begin
            $display("FAIL: 双次腐蚀目标外围残留"); fails = fails + 1;
        end else $display("PASS: 双次腐蚀外围干净");

        $display("===== 结束：%0d 失败 =====", fails);
        $finish;
    end

    always @(posedge clk) t = t + 1;
endmodule
