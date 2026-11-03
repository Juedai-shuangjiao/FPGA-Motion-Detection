//========================================================
// tb_motion_ae_chg —— 2026-11-03 AE 变化沿触发重采背景仿真
// 场景：
//   A: 00 模式 I_ae_chg 脉冲 → 防抖 6 帧 → 采一帧 → bg_captured=1
//   B: 冷却期（180 帧）内再发 I_ae_chg → 不重复采
//   C: 01 模式（检测模式）稳定后发 I_ae_chg → 不采（只自动模式用）
//   D: 拨码 00→01 模式变化正常触发（回归原有触发路径）
//========================================================
`timescale 1ns/1ps
module tb_motion_ae_chg;

    reg clk, rst_n;
    reg [95:0] tdata;
    reg tvalid, tlast, tuser;
    reg sw4, sw3;
    reg ae_chg;
    reg [95:0] bg_data;
    reg bg_valid, bg_frame_start;

    wire [95:0] o_tdata;
    wire [95:0] o_cur_data;
    wire o_tvalid, o_tlast, o_tuser;
    wire bg_capture, bg_captured;

    motion_detect u_dut (
        .I_clk(clk), .I_rst_n(rst_n),
        .I_tdata(tdata), .I_tvalid(tvalid), .I_tlast(tlast), .I_tuser(tuser),
        .I_sw4(sw4), .I_sw3(sw3), .I_ae_chg(ae_chg),
        .I_bg_data(bg_data), .I_bg_valid(bg_valid), .I_bg_frame_start(bg_frame_start),
        .O_tdata(o_tdata), .O_cur_data(o_cur_data),
        .O_tvalid(o_tvalid), .O_tlast(o_tlast), .O_tuser(o_tuser),
        .O_bg_capture(bg_capture), .O_bg_captured(bg_captured)
    );

    always #8.335 clk = ~clk;   //60MHz

    integer err;
    integer cap_cnt;   //bg_capture 脉冲计数
    reg cap_prev;

    // 帧驱动：每帧 100 拍，帧首 1 拍 tuser
    task send_frames(input integer n);
        integer i, j;
        begin
            for(i = 0; i < n; i = i + 1) begin
                for(j = 0; j < 100; j = j + 1) begin
                    @(negedge clk);
                    if(j == 0) begin
                        tuser <= 1'b1;
                        tvalid <= 1'b0;
                    end else if(j == 2) begin
                        tuser <= 1'b0;
                        tvalid <= 1'b1;
                    end
                end
            end
            @(negedge clk);
            tvalid <= 1'b0;
        end
    endtask

    initial begin
        clk = 0; rst_n = 0;
        tdata = 96'd0; tvalid = 0; tlast = 0; tuser = 0;
        sw4 = 0; sw3 = 0; ae_chg = 0;
        bg_data = 96'd0; bg_valid = 0; bg_frame_start = 0;
        err = 0;
        cap_cnt = 0; cap_prev = 0;
        repeat(10) @(negedge clk);
        rst_n = 1;
        repeat(10) @(negedge clk);

        //---------- 场景A：00 模式 AE 变化触发 ----------
        @(negedge clk);
        ae_chg <= 1'b1;
        @(negedge clk);
        ae_chg <= 1'b0;
        // 防抖 6 帧 + 采 1 帧 = 发 8 帧，观察 bg_capture 脉冲
        begin
            integer i;
            for(i = 0; i < 8; i = i + 1) begin
                integer j;
                for(j = 0; j < 100; j = j + 1) begin
                    @(negedge clk);
                    cap_prev <= bg_capture;
                    if(bg_capture && !cap_prev) cap_cnt = cap_cnt + 1;
                    if(j == 0) begin tuser <= 1'b1; tvalid <= 1'b0; end
                    else if(j == 2) begin tuser <= 1'b0; tvalid <= 1'b1; end
                end
            end
        end
        @(negedge clk); tvalid <= 1'b0;
        if(cap_cnt != 1) begin
            $display("场景A FAIL: AE 触发后采帧数 = %0d（期望 1）", cap_cnt);
            err = err + 1;
        end else
            $display("场景A PASS: AE 变化触发采 1 帧");
        @(negedge clk);
        if(bg_captured != 1'b1) begin
            $display("场景A2 FAIL: 采集完成后 bg_captured=%b（期望 1）", bg_captured);
            err = err + 1;
        end else
            $display("场景A2 PASS: bg_captured 采集完成后置 1");

        //---------- 场景B：冷却期内 AE 再触发不采 ----------
        cap_cnt = 0;
        @(negedge clk); ae_chg <= 1'b1;
        @(negedge clk); ae_chg <= 1'b0;
        begin
            integer i;
            for(i = 0; i < 10; i = i + 1) begin
                integer j;
                for(j = 0; j < 100; j = j + 1) begin
                    @(negedge clk);
                    cap_prev <= bg_capture;
                    if(bg_capture && !cap_prev) cap_cnt = cap_cnt + 1;
                    if(j == 0) begin tuser <= 1'b1; tvalid <= 1'b0; end
                    else if(j == 2) begin tuser <= 1'b0; tvalid <= 1'b1; end
                end
            end
        end
        @(negedge clk); tvalid <= 1'b0;
        if(cap_cnt != 0) begin
            $display("场景B FAIL: 冷却期内再触发却采了 %0d 帧（期望 0）", cap_cnt);
            err = err + 1;
        end else
            $display("场景B PASS: 冷却期（180帧）内 AE 触发不重复采");

        //---------- 场景C：拨到 01 检测模式，AE 触发不采 ----------
        // 先等冷却结束（场景A 采完启动 180 帧冷却；等 190 帧确保冷却清零）
        begin
            integer i;
            for(i = 0; i < 190; i = i + 1) begin
                integer j;
                for(j = 0; j < 100; j = j + 1) begin
                    @(negedge clk);
                    if(j == 0) begin tuser <= 1'b1; tvalid <= 1'b0; end
                    else if(j == 2) begin tuser <= 1'b0; tvalid <= 1'b1; end
                end
            end
        end
        @(negedge clk); tvalid <= 1'b0;
        cap_cnt = 0;
        @(negedge clk); sw4 <= 1'b1;   //拨到 01（模式2涂白）——本身 mode_changed 会触发一次正常采集
        begin
            integer i;
            for(i = 0; i < 10; i = i + 1) begin
                integer j;
                for(j = 0; j < 100; j = j + 1) begin
                    @(negedge clk);
                    cap_prev <= bg_capture;
                    if(bg_capture && !cap_prev) cap_cnt = cap_cnt + 1;
                    if(j == 0) begin tuser <= 1'b1; tvalid <= 1'b0; end
                    else if(j == 2) begin tuser <= 1'b0; tvalid <= 1'b1; end
                end
            end
        end
        @(negedge clk); tvalid <= 1'b0;
        if(cap_cnt != 1) begin
            $display("场景C FAIL: 拨码模式变化采帧数 = %0d（期望 1，mode_changed 正常触发）", cap_cnt);
            err = err + 1;
        end else
            $display("场景C PASS: 拨码 00→01 正常触发采 1 帧");

        // 模式稳定后（冷却期内 mode_changed 已消）再发 AE 触发 → 不采（01 模式）
        cap_cnt = 0;
        @(negedge clk); ae_chg <= 1'b1;
        @(negedge clk); ae_chg <= 1'b0;
        begin
            integer i;
            for(i = 0; i < 10; i = i + 1) begin
                integer j;
                for(j = 0; j < 100; j = j + 1) begin
                    @(negedge clk);
                    cap_prev <= bg_capture;
                    if(bg_capture && !cap_prev) cap_cnt = cap_cnt + 1;
                    if(j == 0) begin tuser <= 1'b1; tvalid <= 1'b0; end
                    else if(j == 2) begin tuser <= 1'b0; tvalid <= 1'b1; end
                end
            end
        end
        @(negedge clk); tvalid <= 1'b0;
        if(cap_cnt != 0) begin
            $display("场景C2 FAIL: 01 模式下 AE 触发采了 %0d 帧（期望 0：只自动模式用）", cap_cnt);
            err = err + 1;
        end else
            $display("场景C2 PASS: 01 检测模式下 AE 触发不采（只自动模式）");

        //---------- 汇总 ----------
        if(err == 0)
            $display("tb_motion_ae_chg ALL PASS");
        else
            $display("tb_motion_ae_chg FAIL（%0d 项）", err);
        $finish;
    end

endmodule
