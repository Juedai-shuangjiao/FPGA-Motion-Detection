//========================================================
// tb：blk_density 块密度过滤仿真
// 场景：80×80 块网格；目标块(行100,列100)撒 16 点；8 个噪声块各 1 点
//   帧 1：计数统计（目标块 16≥5 ✓、噪声块 1<5 ✗）
//   帧 2（fs_pulse 锁存后）：目标块拍 O_blk_en=1（参与统计）、噪声块拍 =0（被踢）
// 验证点：有效图帧级流水、首帧默认全开、块号映射边界
//========================================================
`timescale 1ns/1ps
module tb_blk_density;
    reg clk, rst_n;
    reg [3:0] fg;
    reg vld;
    reg [9:0] row;
    reg [10:0] col;
    reg fs_pulse;
    wire blk_en;
    integer fails = 0;
    integer t;

    blk_density u_dut (
        .I_clk(clk), .I_rst_n(rst_n),
        .I_fg(fg), .I_vld(vld), .I_row(row), .I_col_base(col), .I_fs_pulse(fs_pulse),
        .O_blk_en(blk_en)
    );

    initial begin clk = 0; forever #5 clk = ~clk; end

    task put(input [9:0] r, input [10:0] c, input [3:0] f);
        begin
            @(posedge clk);
            row <= r; col <= c; fg <= f; vld <= 1'b1;
        end
    endtask

    task check(input [31:0] name, input exp);
        begin
            @(posedge clk); #1;   //等 put 的 NBA 生效后再采样 blk_en（参数快照语义坑：cond 不能调用时求值）
            if(blk_en !== exp) begin
                $display("FAIL @%0d : %0d（blk_en=%0b 期望 %0b）", t, name, blk_en, exp);
                fails = fails + 1;
            end else
                $display("PASS @%0d : %0d", t, name);
        end
    endtask

    initial begin
        t = 0;
        rst_n = 0; fg = 0; vld = 0; row = 0; col = 0; fs_pulse = 0;
        #30 rst_n = 1;
        #10;

        // 首帧默认全开：任意块 O_blk_en=1
        put(10'd100, 11'd100, 4'b0000);
        check(32'd1, 1'b1);   //首帧默认全有效
        vld = 0;

        // ---- 帧 1：撒点 ----
        // 目标块（行100~102、列100~112 在块(1,1)）：16 点
        put(10'd100, 11'd100, 4'b1111);
        put(10'd100, 11'd104, 4'b1111);
        put(10'd100, 11'd108, 4'b1111);
        put(10'd100, 11'd112, 4'b1111);
        vld = 0;
        // 噪声块各 1 点（8 块，坐标错开块号 0,0 / 0,2 / 2,0 / 2,2 / 4,4 / 6,6 / 8,8 / 8,15）
        put(10'd10,  11'd10,  4'b0001);
        put(10'd10,  11'd170, 4'b0001);
        put(10'd170, 11'd10,  4'b0001);
        put(10'd170, 11'd170, 4'b0001);
        put(10'd330, 11'd330, 4'b0001);
        put(10'd490, 11'd490, 4'b0001);
        put(10'd650, 11'd650, 4'b0001);
        put(10'd650, 11'd1210,4'b0001);
        vld = 0;

        // 帧 2 开始：锁存有效图
        @(posedge clk); fs_pulse <= 1'b1;
        @(posedge clk); fs_pulse <= 1'b0;
        #1;

        // ---- 帧 2：验证门控 ----
        put(10'd100, 11'd100, 4'b1111);   //目标块拍
        check(32'd2, 1'b1);    //目标块有效
        vld = 0;
        put(10'd10,  11'd10,  4'b0001);   //噪声块拍
        check(32'd3, 1'b0);    //噪声块被踢
        vld = 0;
        put(10'd650, 11'd1210, 4'b0001);  //边角噪声块
        check(32'd4, 1'b0);
        vld = 0;

        // 块号映射边界：行 79/80（块 0/1 交界）、列 79/80（块 0/1 交界）
        // （这两点位于未撒点块——有效图=0，若映射错误会指向有 16 点的目标块而 =1）
        put(10'd79,  11'd79,  4'b0000);   //块(0,0)
        check(32'd5, 1'b0);    //(0,0) 无点应无效
        vld = 0;
        put(10'd80,  11'd80,  4'b0000);   //块(1,1) 边界——目标块有效
        check(32'd6, 1'b1);    //(1,1) 边界归属正确
        vld = 0;

        $display("===== 结束：%0d 失败 =====", fails);
        $finish;
    end

    always @(posedge clk) t = t + 1;
endmodule
