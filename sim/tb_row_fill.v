//========================================================
// tb_row_fill —— 行填充单元仿真验证（2026-11-02 多段版）
// 验证点：
//   ① 多段填充：宽间隙（>= GAP_T=64 组）断段——手与远处物体不连；段内各 [L,R] 全 1
//   ② 窄间隙（< GAP_T）视为段内空洞照填
//   ③ 段宽过滤：段宽 < MIN_W=4 组的孤立小块不填
//   ④ 无前景行输出全 0；行尾 gap 空洞拍不推进
//   ⑤ 延迟 321 有效拍、O_valid 与数据同拍
//   ⑥ 帧开始清链（旧数据不泄漏、新数据 321 拍后恢复）
//   ⑦ DRAIN 直通（I_drain 拉高期间输出原值不填充）
//   ⑧ O_edge/O_ori 直通延迟与 O_fill 同拍对齐
// 黄金模型：与 RTL 同构的独立多段算法（GAP_T/MIN_W 与 DUT 默认参数一致）。
// 编译：verilator_bin --binary --timing -Wno-fatal --public-flat-rw --top-module tb_row_fill row_fill.v tb_row_fill.v
//========================================================
`timescale 1ns/1ps
module tb_row_fill;

    reg         clk, rst_n;
    reg         frame_start, valid, drain;
    reg  [3:0]  data, eg;
    wire        o_valid;
    wire [3:0]  o_ori, o_fill, o_edge;

    row_fill dut (
        .I_clk(clk), .I_rst_n(rst_n),
        .I_frame_start(frame_start),
        .I_valid(valid), .I_data(data), .I_edge(eg), .I_drain(drain),
        .O_valid(o_valid), .O_ori(o_ori), .O_fill(o_fill), .O_edge(o_edge)
    );

    // 黄金模型参数（与 DUT 默认一致，任务书「零、用户新增需求」）
    localparam GM_GAP  = 10;   //GAP_T：0 游程 > 10 组（40px）断段
    localparam GM_MINW = 4;    //MIN_W：段内 1 像素数 < 4px 整段不填
    localparam GM_K    = 4;    //每行最多段数

    //---------- 激励序列数组（日历拍 → 信号值）----------
    reg [3:0]  stim_data  [0:16383];
    reg [3:0]  stim_edge  [0:16383];
    reg        stim_valid [0:16383];
    reg        stim_drain [0:16383];
    reg        stim_fs    [0:16383];
    integer    stim_len;

    //---------- 有效拍记录（黄金模型）----------
    integer g_total;
    reg [3:0]  in_data  [0:4095];
    reg [3:0]  in_edge  [0:4095];
    reg [3:0]  in_drain [0:4095];
    // 行段表（黄金模型）
    integer row_cnt [0:15];
    integer row_L [0:15][0:3], row_R [0:15][0:3], row_Lb [0:15][0:3], row_Rb [0:15][0:3];
    integer g0_A_end;                        //场景 A（帧清前）喂入有效拍总数

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

    // 组内最左 1 位号
    function [1:0] gm_left;
        input [3:0] d;
        begin
            if(d[0]) gm_left = 2'd0;
            else if(d[1]) gm_left = 2'd1;
            else if(d[2]) gm_left = 2'd2;
            else gm_left = 2'd3;
        end
    endfunction
    // 组内最右 1 位号
    function [1:0] gm_right;
        input [3:0] d;
        begin
            if(d[3]) gm_right = 2'd3;
            else if(d[2]) gm_right = 2'd2;
            else if(d[1]) gm_right = 2'd1;
            else gm_right = 2'd0;
        end
    endfunction
    // 组内 1 的个数（黄金模型 popcount）
    function [2:0] gm_pc;
        input [3:0] d;
        begin
            gm_pc = d[0] + d[1] + d[2] + d[3];
        end
    endfunction

    // 行统计计算（黄金模型多段算法，与 RTL 同构独立实现；1 像素数过滤）
    task calc_row_stats;
        input [3:0]  y_in;
        input [31:0] base_in;
        integer g, kk;
        integer seg_open, zero_len, cnt, cnt1, L, Lb, R, Rb;
        begin
            seg_open = 0; zero_len = 0; cnt = 0; cnt1 = 0; L = 0; Lb = 0; R = 0; Rb = 0;
            for(g = 0; g < 320; g = g + 1) begin
                kk = base_in + g;
                if(in_data[kk] != 4'd0) begin
                    if(!seg_open) begin
                        seg_open = 1;
                        L = g; Lb = gm_left(in_data[kk]);
                    end
                    R = g; Rb = gm_right(in_data[kk]);
                    cnt1 = cnt1 + gm_pc(in_data[kk]);
                    zero_len = 0;
                end else begin
                    if(seg_open) begin
                        if(zero_len >= GM_GAP) begin
                            if(cnt1 >= GM_MINW && cnt < GM_K) begin
                                row_L[y_in][cnt] = L; row_R[y_in][cnt] = R;
                                row_Lb[y_in][cnt] = Lb; row_Rb[y_in][cnt] = Rb;
                                cnt = cnt + 1;
                            end
                            seg_open = 0; cnt1 = 0; zero_len = 0;
                        end else begin
                            zero_len = zero_len + 1;
                        end
                    end
                end
            end
            // 行末关段（1 像素数含组 319 当拍贡献）
            if(seg_open) begin
                if(cnt1 >= GM_MINW && cnt < GM_K) begin
                    row_L[y_in][cnt] = L; row_R[y_in][cnt] = R;
                    row_Lb[y_in][cnt] = Lb; row_Rb[y_in][cnt] = Rb;
                    cnt = cnt + 1;
                end
            end
            row_cnt[y_in] = cnt;
        end
    endtask

    // 多段填充掩码（黄金模型）：组号 grp 对行 y 的段表
    function [3:0] gm_mask_multi;
        input [8:0] grp;
        input [3:0] y_in;
        integer s;
        reg [3:0] m;
        begin
            m = 4'd0;
            for(s = 0; s < row_cnt[y_in]; s = s + 1) begin
                if(grp < row_L[y_in][s]) begin
                    m = m;
                end else if(grp == row_L[y_in][s] && row_L[y_in][s] == row_R[y_in][s]) begin
                    case({row_Lb[y_in][s][1:0], row_Rb[y_in][s][1:0]})
                        4'b0000 : m = m | 4'b0001;
                        4'b0001 : m = m | 4'b0011;
                        4'b0010 : m = m | 4'b0111;
                        4'b0011 : m = m | 4'b1111;
                        4'b0101 : m = m | 4'b0010;
                        4'b0110 : m = m | 4'b0110;
                        4'b0111 : m = m | 4'b1110;
                        4'b1010 : m = m | 4'b0100;
                        4'b1011 : m = m | 4'b1100;
                        4'b1111 : m = m | 4'b1000;
                        default : m = m;
                    endcase
                end else if(grp == row_L[y_in][s]) begin
                    case(row_Lb[y_in][s][1:0])
                        2'd0 : m = m | 4'b1111;
                        2'd1 : m = m | 4'b1110;
                        2'd2 : m = m | 4'b1100;
                        default : m = m | 4'b1000;
                    endcase
                end else if(grp < row_R[y_in][s]) begin
                    m = 4'b1111;
                end else if(grp == row_R[y_in][s]) begin
                    case(row_Rb[y_in][s][1:0])
                        2'd0 : m = m | 4'b0001;
                        2'd1 : m = m | 4'b0011;
                        2'd2 : m = m | 4'b0111;
                        default : m = m | 4'b1111;
                    endcase
                end
            end
            gm_mask_multi = m;
        end
    endfunction

    //---------- 时钟 ----------
    always #5 clk = ~clk;

    //---------- 序列构建 + 单循环逐拍驱动 ----------
    integer i, lg, yy;
    integer t;
    reg [3:0] d_cur;
    task put_beat;
        input [3:0] d, e, dr;
        begin
            stim_valid[t] = 1'b1; stim_data[t] = d; stim_edge[t] = e; stim_drain[t] = dr; stim_fs[t] = 1'b0;
            in_data[g_total]  = d;
            in_edge[g_total]  = e;
            in_drain[g_total] = dr;
            g_total = g_total + 1;
            t = t + 1;
        end
    endtask
    task put_gap;
        begin
            stim_valid[t] = 1'b0; stim_data[t] = 4'd0; stim_edge[t] = 4'd0;
            stim_drain[t] = 1'b0; stim_fs[t] = 1'b0;
            t = t + 1;
        end
    endtask
    task put_fs;
        begin
            stim_valid[t] = 1'b0; stim_data[t] = 4'd0; stim_edge[t] = 4'd0;
            stim_drain[t] = 1'b0; stim_fs[t] = 1'b1;
            t = t + 1;
        end
    endtask

    initial begin
        clk = 0; rst_n = 0; frame_start = 0; valid = 0; drain = 0;
        data = 0; eg = 0; err_cnt = 0; g_total = 0; t = 0; yy = 0;
        for(i = 0; i < 16; i = i + 1) row_cnt[i] = 0;

        //========== 构建激励序列 ==========
        // 场景 A：4 行 + 行尾 gap 2 拍 + DRAIN 式排空 321 拍
        // 行 0：段1 = 组 5~30（宽 26）；段2 = 组 100~120（宽 21）；间隙 70 组 > 64 → 两段分离
        //       （模拟：手在左、远处物体在右，填充不连）
        for(lg = 0; lg < 320; lg = lg + 1) begin
            if(lg >= 5 && lg <= 30)        d_cur = 4'b1111;
            else if(lg >= 100 && lg <= 120) d_cur = 4'b1111;
            else                           d_cur = 4'd0;
            put_beat(d_cur, d_cur, 1'b0);
        end
        calc_row_stats(yy, yy*320); yy = yy + 1;
        put_gap; put_gap;
        // 行 1：段1 = 组 10~15（4'b1111）+ 组 20（4'b1001，间隙 4 组 < GAP_T=10 → 相连，
        //       段内 1 数 = 6×4+2 = 26 >= MIN_W ✓ 填）；组 60 单 1（4'b0010，1 像素 < 4 → 过滤）；
        //       段2 = 组 150~160（4'b1111）。间隙 20→60→150 都 > 10 → 各自独立
        for(lg = 0; lg < 320; lg = lg + 1) begin
            if(lg >= 10 && lg <= 15)          d_cur = 4'b1111;
            else if(lg == 20)                 d_cur = 4'b1001;
            else if(lg == 60)                 d_cur = 4'b0010;
            else if(lg >= 150 && lg <= 160)   d_cur = 4'b1111;
            else                              d_cur = 4'd0;
            put_beat(d_cur, ~d_cur, 1'b0);
        end
        calc_row_stats(yy, yy*320); yy = yy + 1;
        put_gap; put_gap;
        // 行 2：全 0（无前景）
        for(lg = 0; lg < 320; lg = lg + 1) put_beat(4'd0, 4'd0, 1'b0);
        calc_row_stats(yy, yy*320); yy = yy + 1;
        put_gap; put_gap;
        // 行 3：段1 = 组 20~40（宽 21）；组 200 单组（宽 1 < MIN_W 过滤）；组 100 起 DRAIN
        for(lg = 0; lg < 320; lg = lg + 1) begin
            if(lg >= 20 && lg <= 40) d_cur = 4'b1111;
            else if(lg == 200)       d_cur = 4'b1000;
            else                     d_cur = 4'd0;
            put_beat(d_cur, 4'b1111, (lg >= 100) ? 1'b1 : 1'b0);
        end
        calc_row_stats(yy, yy*320); yy = yy + 1;
        put_gap; put_gap;
        // DRAIN 式排空 321 拍：排出行 3 滞留 320 拍，排空段自身随后被帧清丢弃
        for(lg = 0; lg < 321; lg = lg + 1) put_beat(4'd0, 4'd0, 1'b0);
        calc_row_stats(yy, yy*320); yy = yy + 1;
        g0_A_end = g_total;    //帧清前喂入有效拍总数（1280 + 321）

        // 场景 B：帧清 1 拍 → 1 行（组 0~10 前景，宽 11）→ gap → DRAIN 式排空 321 拍
        put_fs;
        for(lg = 0; lg < 320; lg = lg + 1) begin
            d_cur = (lg <= 10) ? 4'b1111 : 4'd0;
            put_beat(d_cur, d_cur, 1'b0);
        end
        calc_row_stats(yy, g0_A_end); yy = yy + 1;   //场景 B 行：帧清后行号重对齐
        put_gap; put_gap;
        // DRAIN 式排空 321 拍：场景 B 滞留 320 拍全部排出
        for(lg = 0; lg < 321; lg = lg + 1) put_beat(4'd0, 4'd0, 1'b0);
        calc_row_stats(yy, g0_A_end + 320); yy = yy + 1;   //排空段行统计（全 0）
        // 末尾空闲 3000 拍
        for(lg = 0; lg < 3000; lg = lg + 1) put_gap;
        stim_len = t;

        $display("=== 序列构建完成：%0d 拍，有效拍 %0d，帧清前 %0d ===", stim_len, g_total, g0_A_end);

        //========== 复位 + 单循环逐拍驱动 ==========
        repeat(5) @(posedge clk);
        @(negedge clk); rst_n = 1'b1;
        @(posedge clk);
        for(i = 0; i < stim_len; i = i + 1) begin
            @(negedge clk);
            valid       = stim_valid[i];
            data        = stim_data[i];
            eg          = stim_edge[i];
            drain       = stim_drain[i];
            frame_start = stim_fs[i];
            @(posedge clk);
        end
        @(negedge clk); valid = 1'b0; frame_start = 1'b0; drain = 1'b0;
        repeat(1000) @(posedge clk);

        $display("=== 激励完成 g_total=%0d ===", g_total);
    end

    //---------- 输出比对进程 ----------
    // 输出第 j 拍 = 输入第 j 拍（延迟 321 体现在时间上，输出流与输入流同索引）。
    // 帧清后：输出寄存直通 1 拍 0（j=1280），场景 B 数据从 j=1281 起（k=j+320）。
    integer j;
    integer k;
    integer y_out;
    integer grp_out;
    reg [3:0] exp_fill, exp_ori, exp_edge;
    initial j = 0;
    always @(posedge clk) begin
        if(o_valid) begin
            if(j < g0_A_end - 321) begin
                k = j;                     //场景 A：同索引
                y_out   = k / 320;
                grp_out = k % 320;
            end else if(j == g0_A_end - 321) begin
                k = j;                     //帧清后输出寄存直通 1 拍 0
                y_out = 0; grp_out = 0;
            end else begin
                k = j + 320;               //场景 B + 排空段 2：帧清后输出索引跳跃 321 再回 1 拍直通
                y_out   = 5 + (k - g0_A_end) / 320;   //行统计索引：场景 A 占 0~4，场景 B 从 5 起
                grp_out = (k - g0_A_end) % 320;
            end
            if(k < g_total && j != g0_A_end - 321) begin
                // DRAIN 直通：判定与数据同拍 = 输入拍 k 的 drain
                if(in_drain[k])
                    exp_fill = in_data[k];
                else
                    exp_fill = gm_mask_multi(grp_out, y_out) | in_data[k];
                exp_ori  = in_data[k];
                exp_edge = in_edge[k];
                if(o_fill != exp_fill) begin
                    err_cnt = err_cnt + 1;
                    $display("FAIL fill: j=%0d k=%0d y=%0d g=%0d got=%b exp=%b",
                             j, k, y_out, grp_out, o_fill, exp_fill);
                end
                if(o_ori != exp_ori) begin
                    err_cnt = err_cnt + 1;
                    $display("FAIL ori: j=%0d k=%0d got=%b exp=%b",
                             j, k, o_ori, exp_ori);
                end
                if(o_edge != exp_edge) begin
                    err_cnt = err_cnt + 1;
                    $display("FAIL eg: j=%0d k=%0d got=%b exp=%b",
                             j, k, o_edge, exp_edge);
                end
            end else if(j == g0_A_end - 321) begin
                // 直通 0 拍：三通道都应为 0
                if(o_fill != 4'd0 || o_ori != 4'd0 || o_edge != 4'd0) begin
                    err_cnt = err_cnt + 1;
                    $display("FAIL flush: j=%0d got fill=%b ori=%b eg=%b",
                             j, o_fill, o_ori, o_edge);
                end
            end else if(k >= g_total) begin
                err_cnt = err_cnt + 1;
                $display("EXTRA: j=%0d k=%0d beyond total %0d", j, k, g_total);
            end
            j = j + 1;
        end
    end

    //---------- 结束判定 ----------
    initial begin
        #1500000;
        $display("=== 仿真结束：输出拍 %0d、输入拍 %0d、期望输出 %0d、err=%0d ===",
                 j, g_total, g0_A_end - 321 + 1 + 321, err_cnt);
        if(err_cnt == 0 && j == g0_A_end - 321 + 1 + 321) begin
            $display("ALL PASS");
        end else begin
            $display("FAILED: %0d errors", err_cnt);
        end
        $finish;
    end

endmodule
