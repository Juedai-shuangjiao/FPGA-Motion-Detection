//========================================================
// tb_snapshot_tx —— 背景数据采集旁路模块仿真（2026-11-03）
// 场景：
//   ① snap_en 上升沿 → 状态机复位 → 头 4 字节 AA 55 53 4E 从 UART 流出
//   ② 模拟 bg 读流（每帧 512 beat × 128bit 递增数据）→ tap 窗口进 FIFO
//      → 数据字节按序从 UART 流出（低字节在前）
//   ③ 头字节后紧跟数据字节（beat0 = 全 0，beat1 = 低位 01）
// UART 监测：按 2Mbps 位流解析 tx 输出，还原字节序列校验。
//========================================================
`timescale 1ns/1ps
module tb_snapshot_tx;

    reg clk, rst_n;
    reg snap_en;
    reg rd_valid_d1, rd_tag;
    reg [127:0] rd_data;
    reg vsync;
    wire tx;

    snapshot_tx u_dut (
        .clk(clk), .rst_n(rst_n),
        .snap_en(snap_en),
        .rd_valid_d1(rd_valid_d1), .rd_tag(rd_tag), .rd_data(rd_data),
        .vsync(vsync),
        .tx(tx)
    );

    always #1.6667 clk = ~clk;   //300MHz

    initial begin
        $dumpfile("/tmp/tb_main.vcd");
        $dumpvars(0, tb_snapshot_tx);
    end

    integer rx_bytes [0:127];
    integer rx_cnt;
    integer errs;

    //---------- 主测试 ----------
    initial begin
        clk = 0; rst_n = 0;
        snap_en = 0; rd_valid_d1 = 0; rd_tag = 0; rd_data = 128'd0; vsync = 0;
        errs = 0;
        rx_cnt = 0;
        repeat(20) @(negedge clk);
        rst_n = 1;
        repeat(20) @(negedge clk);

        // 第一帧：未使能抓取（snap_en=0），bg 读流照发——不应进 FIFO
        begin
            integer b;
            @(negedge clk); vsync = 1;
            @(negedge clk); vsync = 0;
            for(b = 0; b < 512; b = b + 1) begin
                @(negedge clk);
                rd_valid_d1 = 1; rd_tag = 0; rd_data = b * 2;
            end
            @(negedge clk); rd_valid_d1 = 0;
        end

        // 第二帧开始：snap_en 上升沿 → 整机复位 → 头字节发出
        @(negedge clk);
        snap_en = 1;
        @(negedge clk);
        vsync = 1;
        @(negedge clk); vsync = 0;

        // 本帧 bg 读 512 beats（数据递增 0,1,2,...）
        begin
            integer b;
            for(b = 0; b < 512; b = b + 1) begin
                @(negedge clk);
                rd_valid_d1 = 1; rd_tag = 0; rd_data = b;
            end
            @(negedge clk); rd_valid_d1 = 0;
        end

        // 等待 UART 发出 头4B + 前 32 字节数据（36 字节 × 10 bit × 500ns = 180us）
        #190000;

        $display("收到字节数 = %0d", rx_cnt);
        $display("DUT 已发字节 cnt = %0d（st=%0d）", u_dut.cnt, u_dut.st);
        begin
            integer q;
            for(q = 0; q < rx_cnt; q = q + 1)
                $display("  rx[%0d] = %02h", q, rx_bytes[q]);
        end
        if(rx_cnt < 36) begin
            $display("FAIL: 字节不足 36（rx_cnt=%0d）", rx_cnt);
            errs = errs + 1;
        end else begin
            $display("  rx[0..3]   = %02h %02h %02h %02h", rx_bytes[0], rx_bytes[1], rx_bytes[2], rx_bytes[3]);
            $display("  rx[4..7]   = %02h %02h %02h %02h", rx_bytes[4], rx_bytes[5], rx_bytes[6], rx_bytes[7]);
            $display("  rx[16..19] = %02h %02h %02h %02h", rx_bytes[16], rx_bytes[17], rx_bytes[18], rx_bytes[19]);
            $display("  rx[20..23] = %02h %02h %02h %02h", rx_bytes[20], rx_bytes[21], rx_bytes[22], rx_bytes[23]);
            if(rx_bytes[0] != 8'hAA || rx_bytes[1] != 8'h55 || rx_bytes[2] != 8'h53 || rx_bytes[3] != 8'h4E) begin
                $display("FAIL: 帧头错误（期望 AA 55 53 4E）");
                errs = errs + 1;
            end else
                $display("帧头 PASS: AA 55 53 4E");
            // 数据：beat0 = 128'd0 → 16 字节 0（rx[4..19]）
            if(rx_bytes[4] == 8'h00 && rx_bytes[19] == 8'h00) begin
                $display("beat0 数据 PASS: 16 字节全 0");
            end else begin
                $display("FAIL: beat0 数据非全 0");
                errs = errs + 1;
            end
            // beat1 = 128'd1 → rx[20] = 0x01、rx[21..35] = 0
            if(rx_bytes[20] == 8'h01 && rx_bytes[35] == 8'h00) begin
                $display("beat1 数据 PASS: 低字节 01 高字节 0");
            end else begin
                $display("FAIL: beat1 数据错（rx[20]=%02h）", rx_bytes[20]);
                errs = errs + 1;
            end
        end

        if(errs == 0)
            $display("tb_snapshot_tx PASS");
        else
            $display("tb_snapshot_tx FAIL（%0d 项）", errs);
        $finish;
    end

    //---------- 监测器：UART 位流 → 字节（2Mbps：bit = 500ns）----------
    initial begin
        forever begin
            integer k;
            @(negedge tx);          //起始位下降沿
            #750;                   //跳起始位 + 半 bit
            rx_bytes[rx_cnt] = 0;
            for(k = 0; k < 8; k = k + 1) begin
                #500;
                if(tx) rx_bytes[rx_cnt] = rx_bytes[rx_cnt] | (1 << k);
            end
            #500;                   //停止位
            rx_cnt = rx_cnt + 1;
        end
    end

endmodule
