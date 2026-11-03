//========================================================
// tb_morph_edge —— morph_filter 仿真验证（2026-11-01 区域填充，第二版 DRAM 化回归）
// 验证点：
//   ① 开运算 O_data 行为不回归（5×20 块保持、孤立点消除）
//   ② O_edge = 开运算 XOR 腐蚀（形态学梯度第二版）：块 → 外轮廓环、单点 → 消失
//   ③ O_edge 与 O_data/O_valid 同拍对齐
//   ④ 输出第 j 个有效拍 = 输入流同索引（延迟 645 拍），帧头不丢、帧尾不增
// 黄金模型：帧语义 3×3 窗口（越界 = 0）。图案远离行边界/帧边界，
//   流式水平窗口跨行邻接与帧语义的差异不出现在图案区域。
// ⚠️ 本 tb 同时是第一版→第二版（行缓冲移位链→DRAM 环形）的差分回归：
//   开运算黄金模型不变，全绿 = DRAM 化行为等价。
// 编译：iverilog -g2012 -o tb_morph_edge.vvp morph_filter.v tb_morph_edge.v && vvp tb_morph_edge.vvp
//========================================================
`timescale 1ns/1ps
module tb_morph_edge;

    reg         clk, rst_n;
    reg         frame_start, valid;
    reg  [3:0]  data;
    wire        o_valid;
    wire [3:0]  o_data, o_edge;

    morph_filter dut (
        .I_clk(clk), .I_rst_n(rst_n), .I_frame_start(frame_start),
        .I_valid(valid), .I_data(data),
        .O_valid(o_valid), .O_data(o_data), .O_edge(o_edge)
    );

    localparam ROWS = 8;
    localparam COLS = 1280;

    //---------- 帧数组（黄金模型）----------
    reg [ROWS*COLS-1:0] ori;      //原图
    reg [ROWS*COLS-1:0] ero;      //3×3 腐蚀
    reg [ROWS*COLS-1:0] open;     //开运算（腐蚀后膨胀）
    reg [ROWS*COLS-1:0] dil;      //3×3 膨胀（原图直接膨胀）
    reg [ROWS*COLS-1:0] eg;     //形态学梯度 = dil ^ ori

    integer err_cnt;

    // 帧访问函数：ori[y][x]
    function [0:0] f_ori;
        input [31:0] y, x;
        begin
            if(y >= ROWS || x >= COLS)
                f_ori = 1'b0;      //越界 = 0
            else
                f_ori = ori[y*COLS + x];
        end
    endfunction

    integer y, x, dy, dx;
    integer cnt;

    //---------- 时钟 ----------
    always #5 clk = ~clk;

    //---------- 激励进程 ----------
    integer k, lg, gcnt;
    initial begin
        clk = 0; rst_n = 0; frame_start = 0; valid = 0; data = 0; err_cnt = 0;

        //---------- 建黄金模型帧 ----------
        ori = 0;
        for(y = 0; y < ROWS; y = y + 1)
            for(x = 0; x < COLS; x = x + 1) begin
                if(y >= 2 && y <= 6 && x >= 10 && x <= 29)
                    ori[y*COLS + x] = 1'b1;            //5×20 实心块
                if(y == 2 && x == 50)
                    ori[y*COLS + x] = 1'b1;            //孤立点
            end
        // 3×3 腐蚀
        ero = 0;
        for(y = 0; y < ROWS; y = y + 1)
            for(x = 0; x < COLS; x = x + 1) begin
                cnt = 0;
                for(dy = -1; dy <= 1; dy = dy + 1)
                    for(dx = -1; dx <= 1; dx = dx + 1)
                        if(f_ori(y+dy, x+dx)) cnt = cnt + 1;
                ero[y*COLS + x] = (cnt == 9) ? 1'b1 : 1'b0;
            end
        // 开运算 = 腐蚀后膨胀
        open = 0;
        for(y = 0; y < ROWS; y = y + 1)
            for(x = 0; x < COLS; x = x + 1) begin
                cnt = 0;
                for(dy = -1; dy <= 1; dy = dy + 1)
                    for(dx = -1; dx <= 1; dx = dx + 1)
                        if(f_ori(y+dy, x+dx)) cnt = cnt + 1;   //占位（下面重写）
                open[y*COLS + x] = 1'b0;
            end
        for(y = 0; y < ROWS; y = y + 1)
            for(x = 0; x < COLS; x = x + 1) begin
                open[y*COLS + x] = 1'b0;
                for(dy = -1; dy <= 1; dy = dy + 1)
                    for(dx = -1; dx <= 1; dx = dx + 1)
                        if(y+dy < ROWS && x+dx < COLS && y+dy >= 0 && x+dx >= 0 && ero[(y+dy)*COLS + (x+dx)])
                            open[y*COLS + x] = 1'b1;
            end
        // 3×3 膨胀（原图）
        dil = 0;
        for(y = 0; y < ROWS; y = y + 1)
            for(x = 0; x < COLS; x = x + 1) begin
                dil[y*COLS + x] = 1'b0;
                for(dy = -1; dy <= 1; dy = dy + 1)
                    for(dx = -1; dx <= 1; dx = dx + 1)
                        if(y+dy < ROWS && x+dx < COLS && y+dy >= 0 && x+dx >= 0 && ori[(y+dy)*COLS + (x+dx)])
                            dil[y*COLS + x] = 1'b1;
            end
        // 形态学梯度（第二版 2026-11-01：open ^ erode —— 目标外轮廓环、单点噪点消失）
        for(y = 0; y < ROWS; y = y + 1)
            for(x = 0; x < COLS; x = x + 1)
                eg[y*COLS + x] = open[y*COLS + x] ^ ero[y*COLS + x];

        //---------- 激励 ----------
        repeat(5) @(posedge clk);
        @(negedge clk); rst_n = 1'b1;
        repeat(2) @(posedge clk);
        @(negedge clk); frame_start = 1'b1;
        @(posedge clk);
        @(negedge clk); frame_start = 1'b0;
        @(posedge clk);

        gcnt = 0;
        for(k = 0; k < ROWS * 320; k = k + 1) begin
            y = k / 320;
            x = (k % 320) * 4;
            @(negedge clk);   //negedge 设置、posedge 采样，消除与 DUT 的竞争
            valid = 1'b1;
            data = {ori[y*COLS + x + 3], ori[y*COLS + x + 2],
                    ori[y*COLS + x + 1], ori[y*COLS + x + 0]};
            @(posedge clk);
        end
        @(negedge clk); valid = 1'b0;
        repeat(1000) @(posedge clk);

        $display("=== 激励完成 err=%0d ===", err_cnt);
    end

    //---------- 输出比对进程 ----------
    // 输出第 j 个有效拍 = 输入流同索引（延迟 645 拍抵消 4px/拍相位）：帧流位置 [4j, 4j+3]
    // 帧尾语义：输入 2560 拍后 valid=0，链冻结 → 尾部 644 拍滞留不输出（morph 已知语义），
    // 期望输出 = 2560 - 644 = 1916 拍。
    integer j;
    integer yy_o, xx_o;
    reg [3:0] exp_open, exp_edge;
    integer open_mismatch, edge_mismatch, valid_extra;
    initial begin
        j = 0; open_mismatch = 0; edge_mismatch = 0; valid_extra = 0;
        forever begin
            @(posedge clk);
            if(o_valid) begin
                if(j >= ROWS * 320 - 644) begin
                    valid_extra = valid_extra + 1;
                    $display("FAIL 多余输出拍 j=%0d", j);
                end else begin
                    yy_o = j / 320;
                    xx_o = (j % 320) * 4;
                    exp_open = {open[yy_o*COLS + xx_o + 3], open[yy_o*COLS + xx_o + 2],
                                open[yy_o*COLS + xx_o + 1], open[yy_o*COLS + xx_o + 0]};
                    exp_edge = {eg[yy_o*COLS + xx_o + 3], eg[yy_o*COLS + xx_o + 2],
                                eg[yy_o*COLS + xx_o + 1], eg[yy_o*COLS + xx_o + 0]};
                    if(o_data != exp_open) begin
                        open_mismatch = open_mismatch + 1;
                        if(open_mismatch <= 10)
                            $display("FAIL open j=%0d (y=%0d x=%0d) got=%b exp=%b",
                                     j, yy_o, xx_o, o_data, exp_open);
                    end
                    if(o_edge != exp_edge) begin
                        edge_mismatch = edge_mismatch + 1;
                        if(edge_mismatch <= 10)
                            $display("FAIL eg j=%0d (y=%0d x=%0d) got=%b exp=%b",
                                     j, yy_o, xx_o, o_edge, exp_edge);
                    end
                end
                j = j + 1;
            end
        end
    end

    //---------- 结束判定 ----------
    initial begin
        #400000;
        $display("=== 结果：输出拍 %0d（期望 %0d）open 错 %0d、edge 错 %0d、多余拍 %0d ===",
                 j, ROWS*320-644, open_mismatch, edge_mismatch, valid_extra);
        if(open_mismatch == 0 && edge_mismatch == 0 && valid_extra == 0 && j == ROWS*320-644)
            $display("ALL PASS");
        else
            $display("FAILED");
        $finish;
    end

endmodule
