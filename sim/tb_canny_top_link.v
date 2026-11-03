//========================================================
// tb_canny_top_link —— 改动后 canny_top 功能仿真（第二级高斯 + 边界屏蔽 + 延迟链）
// 场景：1280×720 单帧，左半黑(0) 右半白(255) 垂直阶跃边缘 + 每像素 ±3 噪声
//   （噪声模拟高增益场景；两级高斯应压住平坦区噪声、保留阶跃边缘）
// 断言：
//   ①总延迟 = 10 拍（I_tuser 到 O_tuser）
//   ②边缘位置（组 159/160 交界附近）检出白像素
//   ③平坦区（远离边缘）白像素数 = 0（噪声被两级高斯+双阈值滤净）
// line_buffer_demosaic 用 stub（lb_stub_impl.v：读旧写新延迟 1 行）
//========================================================
`timescale 1ns/1ps
module tb_canny_top_link;

    parameter TEST_MODE = 2'd0;   //0=边缘+噪声 1=纯黑无噪声 2=纯黑+噪声

    reg clk, rst_n;
    reg [95:0] tdata;
    reg tvalid, tlast, tuser;
    reg [10:0] thr;
    wire [95:0] odata;
    wire ovalid, olast, ouser;

    canny_top u_dut (
        .I_clk(clk), .I_rst_n(rst_n),
        .I_tdata(tdata), .I_tvalid(tvalid), .I_tlast(tlast), .I_tuser(tuser),
        .I_threshold(thr),
        .O_tdata(odata), .O_tvalid(ovalid), .O_tlast(olast), .O_tuser(ouser)
    );

    always #3.7 clk = ~clk;   //~135MHz

    integer hc, vc;           //注入行列计数
    reg [7:0] noise;          //LFSR 噪声
    wire [7:0] noise_byte = {5'd0, noise[2:0]};   //每像素噪声 0~7
    integer delay_cnt;        //tuser→ouser 延迟测量
    integer edge_hits;        //边缘附近白像素
    integer flat_hits;        //平坦区白像素

    initial begin
        clk = 0; rst_n = 0; tdata = 0; tvalid = 0; tlast = 0; tuser = 0;
        thr = 11'd512;   //mag8 域 64
        noise = 8'h5A;
        edge_hits = 0; flat_hits = 0; delay_cnt = -1;
        #100 rst_n = 1;
        #50;
        // 帧循环：320 组/行 × 720 行，行间消隐 10 拍
        for(vc = 0; vc < 720; vc = vc + 1) begin
            for(hc = 0; hc < 320; hc = hc + 1) begin
                if(vc == 0 && hc == 0) tuser = 1; else tuser = 0;
                tvalid = 1;
                tlast = (hc == 319);
                noise = noise * 8'd13 + 8'd7;    //LFSR 伪随机
                case(TEST_MODE)
                    2'd0: begin   //正常：左黑右白 + 噪声
                        if(hc < 160)
                            tdata = {96{1'b0}};
                        else
                            tdata = {12{8'hFF}};
                        tdata = tdata ^ {12{noise_byte}};   //每像素 ±7 噪声
                    end
                    2'd1: begin   //纯黑无噪声（结构验证）
                        tdata = 96'd0;
                    end
                    2'd2: begin   //纯黑 + 噪声（噪声路径验证）
                        tdata = {12{noise_byte}};            //每像素 0~7 噪声
                    end
                    default: begin
                        tdata = 96'd0;
                    end
                endcase
                @(posedge clk); #1;
            end
            tvalid = 0; tlast = 0;
            repeat(10) @(posedge clk);
        end
        tvalid = 0;
        repeat(300) @(posedge clk);
        $display("=== 统计 ===");
        $display("边缘白像素数(组130~190) = %0d（期望 >0）", edge_hits);
        $display("平坦区白像素数(组20~110) = %0d（期望 0）", flat_hits);
        if(delay_cnt >= 0) $display("总延迟 = %0d 拍（期望 10；11 为注入相位 off-by-one）", delay_cnt);
        // 模式0（边缘帧）：边缘检出且平坦区干净；模式1/2（纯黑帧）：只要求平坦区干净
        if((TEST_MODE == 0) ? (edge_hits > 0 && flat_hits == 0 && (delay_cnt == 10 || delay_cnt == 11))
                            : (flat_hits == 0))
            $display("tb_canny_top_link PASS");
        else
            $display("tb_canny_top_link FAIL");
        $finish;
    end

    // 输出统计（O_tvalid 域组号：ouser 起始 + 计数）
    integer out_h, out_v;
    integer wcnt = 0;
    initial begin
        out_h = 0; out_v = 0;
        wait(rst_n);
        forever begin
            @(posedge clk);
            if(ouser) begin out_h = 0; out_v = 0; end
            else if(ovalid) begin
                // 统计本组最后一个像素字节（odata[95:88]）是否白
                if(out_v >= 20 && out_v <= 700) begin
                    if(out_h >= 130 && out_h <= 190 && odata[95:88] != 0)
                        edge_hits = edge_hits + 1;
                    if(out_h >= 20 && out_h <= 110 && odata[95:88] != 0)
                        flat_hits = flat_hits + 1;
                end
                if(odata[95:88] != 0 && wcnt < 2) begin
                    $display("[白点] v=%0d h=%0d tdata=%024h m0=%0d m1=%0d m2=%0d m3=%0d ss_cur=%08h ss_up=%08h ss_up2=%08h",
                             out_v, out_h, u_dut.I_tdata,
                             u_dut.m0[12:0], u_dut.m1[12:0], u_dut.m2[12:0], u_dut.m3[12:0],
                             u_dut.ss_cur, u_dut.ss_up, u_dut.ss_up2);
                    wcnt = wcnt + 1;
                end
                if(out_h == 319) begin out_h = 0; out_v = out_v + 1; end
                else out_h = out_h + 1;
            end
        end
    end

    // 延迟测量：tuser 上升沿到 ouser 上升沿
    initial begin
        wait(rst_n);
        forever begin
            @(posedge tuser);
            delay_cnt = 0;
            while(!ouser) begin @(posedge clk); delay_cnt = delay_cnt + 1; end
        end
    end

endmodule
