//============================================================================
// tb_bg_line —— bug3 复现：细线/黑线（bg_read 读侧）
// 场景：全帧差异注入（cur 块编码 8'h55、bg 块编码 8'hAA → 全屏前景），
//   检测每行 ERAM 写拍数——写不满/漏写的行 = 细线/黑线位置（该行标记恒 0 不涂白）。
// 模型：行消隐结构（行 2222 拍、de 高 1724、行消隐 498；720 有效行 + 场消隐 30 行）
//   串行仲裁 WR/VO/BG 240 拍轮转（bg 时间片 1/3）、显示期水位 <300 禁补读
//   DDR 返回 40 拍延迟，按地址编码（cur/bg 块内容不同 = 全屏差异）
// 判读：读满帧 + DRAIN 正常 → 除形态学边界行外每行写满 32 字；
//   读不满帧 → 停止行以下漏写（细线/黑线 = 停止行/交界行/尾行）
//============================================================================
`timescale 1ns/1ps
module tb_bg_line;

//------------ 时钟与复位 -------------
reg clk_ddr = 1'b0;
always #5 clk_ddr = ~clk_ddr;   // 100MHz

reg rst_n;
initial begin
    rst_n = 1'b0;
    #200;
    rst_n = 1'b1;
end

//------------ 行/帧结构（100M 域）：行 2222 拍 = de 高 1724 + 行消隐 498；750 行/帧 ------------
localparam [15:0] LINE_CYC   = 16'd2222;      // 行周期（100M 域）
localparam [15:0] LINE_DE    = 16'd1724;      // 行内 de 高拍数
localparam [9:0]  V_LINES    = 10'd750;       // 帧总行数
localparam [9:0]  V_ACTIVE   = 10'd720;       // 有效行数
localparam [9:0]  VBLANK_L   = 10'd30;        // 场消隐行数

reg  [15:0] h_cnt;
reg  [9:0]  v_cnt;
reg         de;
reg         vsync;
always @(posedge clk_ddr or negedge rst_n) begin
    if(!rst_n) begin
        h_cnt <= 16'd0;
        v_cnt <= 10'd0;
        de    <= 1'b0;
        vsync <= 1'b0;
    end else begin
        vsync <= 1'b0;
        if(h_cnt == LINE_CYC - 1'b1) begin
            h_cnt <= 16'd0;
            if(v_cnt == V_LINES - 1'b1) begin
                v_cnt <= 10'd0;
                vsync <= 1'b1;          // 帧尾拍置位 → 下一拍帧头可见
            end else
                v_cnt <= v_cnt + 10'd1;
        end else
            h_cnt <= h_cnt + 16'd1;
        de <= (v_cnt < V_ACTIVE) && (h_cnt < LINE_DE);
    end
end

//------------ vsync 打 3 拍 → bg_read 帧开始脉冲（I_frame_start）------------
reg vs_s1, vs_s2, vs_s3;
always @(posedge clk_ddr) begin
    vs_s1 <= vsync;
    vs_s2 <= vs_s1;
    vs_s3 <= vs_s2;
end
wire frame_start = vs_s2 && !vs_s3;

//------------ de 打 3 拍 → disp_win（显示期电平，行消隐结构保留）------------
reg de_s1, de_s2, de_s3;
always @(posedge clk_ddr) begin
    de_s1 <= de;
    de_s2 <= de_s1;
    de_s3 <= de_s2;
end
wire disp_win = de_s3;

//------------ 串行仲裁模型（shiyan3 波形实测版）：bg 批忙时片保持——240 拍批 + 2 拍批间隙循环；
// 写批/vo 批的抢占统一由 wr_busy（10%）与 vo 水位门控表达，仲裁本身不再插 WR/VO 片 ------------
reg  [8:0] arb_ph;      //0~239 bg 批、240~241 批间隙
reg        bg_grant;
always @(posedge clk_ddr or negedge rst_n) begin
    if(!rst_n) begin
        arb_ph <= 9'd0;
        bg_grant <= 1'b0;
    end else begin
        arb_ph <= (arb_ph == 9'd241) ? 9'd0 : arb_ph + 9'd1;
        if(arb_ph == 9'd239)      //批读满 240 → 批间隙
            bg_grant <= 1'b0;
        else if(arb_ph == 9'd241) //间隙 2 拍完 → 回 bg 批
            bg_grant <= 1'b1;
    end
end

//------------ vo 水位模型（实机化）：显示期消耗 3 字/4 拍（0.7425）；批补充期间消耗继续 → 净 +0.25/拍 ------------
// 触发水位 220（bug3 修复后）→ 锯齿 220~280 → bg 门槛 260 时段 ≈ 20+27=47/348=13.5% → 补读窗口
reg [8:0] vo_level;
reg       vo_batch;
reg [8:0] vo_batch_cnt;
reg [1:0] vo_cons_ph;   // 消耗相位：每 4 拍消耗 3 字
always @(posedge clk_ddr or negedge rst_n) begin
    if(!rst_n) begin
        vo_level <= 9'd380;
        vo_batch <= 1'b0;
        vo_batch_cnt <= 9'd0;
        vo_cons_ph <= 2'd0;
    end else begin
        if(disp_win) begin   // 显示期：消耗持续 + 读批补充（净 +0.25/拍）
            vo_cons_ph <= vo_cons_ph + 2'd1;
            if(vo_batch) begin
                vo_batch_cnt <= vo_batch_cnt + 9'd1;
                if(vo_cons_ph == 2'd3)
                    vo_level <= vo_level;   // 每 4 拍：+1(补) -0.75(耗) ≈ 净 0
                else if(vo_cons_ph == 2'd0)
                    vo_level <= vo_level + 9'd1;   // 补 1 字（该拍不消耗）
                else
                    vo_level <= vo_level - 9'd1;   // 消耗 1 字（不补）
                if(vo_batch_cnt == 9'd239)
                    vo_batch <= 1'b0;
            end else begin
                if(vo_cons_ph != 2'd3)
                    vo_level <= vo_level - 9'd1;   // 每 4 拍消耗 3 字
                if(vo_level <= 9'd240) begin
                    vo_batch <= 1'b1;          // 触发读批
                    vo_batch_cnt <= 9'd0;
                end
            end
        end
        // 消隐期：水位冻结（vo 不消耗不补充）
    end
end
wire [8:0] vo_fifo_level = vo_level;

//------------ 写批避让模型：每 10 拍 1 拍写命令（占空比 ~10%，模拟 vi 写批 720 批/帧）------------
reg [3:0] wr_ph;
reg       wr_busy;
always @(posedge clk_ddr or negedge rst_n) begin
    if(!rst_n) begin
        wr_ph <= 4'd0;
        wr_busy <= 1'b0;
    end else begin
        wr_ph <= (wr_ph == 4'd9) ? 4'd0 : wr_ph + 4'd1;
        wr_busy <= (wr_ph == 4'd9);   // 每 10 拍末 1 拍写命令
    end
end

//------------ DDR 返回模型：读命令 → 40 拍延迟 → rd_valid/rd_data ------------
// cur 块（地址 < 背景基址）返回编码 8'h55；bg 块（>= IMAGE_BASE_ADDR_4）返回 8'hAA → 全屏差异
localparam [24:0] BG_BASE = 25'd22382400;
reg  [39:0] ret_shift [0:43];   // 40 拍延迟链（命令拍压入 [39]，逐拍右移）
reg  [127:0] ret_data [0:43];
integer ri;
always @(posedge clk_ddr) begin
    if(!rst_n) begin
        for(ri=0; ri<44; ri=ri+1) begin
            ret_shift[ri] = 40'd0;
            ret_data[ri] = 128'd0;
        end
    end else begin
        // 命令拍：压入延迟链
        if(rd_en) begin
            ret_shift[39] = 40'd1;
            ret_data[39]  = (bg_rd_addr >= BG_BASE) ? {16{8'hAA}} : {16{8'h55}};
        end else
            ret_shift[39] = 40'd0;
        for(ri=0; ri<39; ri=ri+1) begin
            ret_shift[ri] = ret_shift[ri+1];
            ret_data[ri]  = ret_data[ri+1];
        end
        ret_shift[40] = 40'd0; ret_shift[41] = 40'd0; ret_shift[42] = 40'd0; ret_shift[43] = 40'd0;
    end
end
wire        ddr_rd_valid = ret_shift[0][0];
wire [127:0] ddr_rd_data = ret_data[0];

//------------ DUT：bg_read -------------
wire [14:0] fg_wr_addr;
wire [39:0] fg_wr_data;
wire        fg_wr_en;
wire        fg_init;
wire [18:0] dbg_rd_cnt;
wire        rd_en;
wire [24:0] bg_rd_addr;
wire        bg_rd_busy;

bg_read tb_uut (
    .I_rst_n             ( rst_n          ),
    .I_ddr_clk           ( clk_ddr        ),
    .I_frame_start       ( frame_start    ),
    .I_video_out_rp      ( 2'd0           ),   //当前帧乒乓块 0
    .I_bg_grant          ( bg_grant       ),
    .I_rd_tag            ( 1'b0           ),   //背景读返回标签恒 0（bg 唯一读源）
    .I_vo_fifo_level     ( vo_fifo_level  ),
    .I_disp_win          ( disp_win       ),
    .I_video_in_wr_busy  ( wr_busy        ),   //写命令拍避让（10% 占空比）
    .I_thr_sel           ( 2'd0           ),   //阈值 25
    .I_ddr_user_ready    ( 1'b1           ),
    .I_ddr_user_rd_valid ( ddr_rd_valid   ),
    .I_ddr_user_rd_data  ( ddr_rd_data    ),
    .O_ddr_user_rd_en    ( rd_en          ),
    .O_ddr_user_addr     ( bg_rd_addr     ),
    .O_bg_rd_busy        ( bg_rd_busy     ),
    .O_fg_wr_addr        ( fg_wr_addr     ),
    .O_fg_wr_data        ( fg_wr_data     ),
    .O_fg_wr_en          ( fg_wr_en       ),
    .O_fg_init           ( fg_init        ),
    .O_dbg_rd_cnt        ( dbg_rd_cnt     ),
    .O_dbg_first_addr    (                ),
    .O_dbg_first_data    (                ),
    .O_dbg_first_half    (                ),
    .O_dbg_vo_room       (                ),
    .O_dbg_abort         (                ),
    .O_dbg_drain         (                ),
    .O_dbg_first_valid   (                )
);

//------------ 每行写拍数统计（fg_wr_en 拍 addr>>5 = 行号）------------
reg [8:0] row_wr_cnt [0:719];   // 每行写拍数（最多 32）
integer rwi;
initial begin
    for(rwi=0; rwi<720; rwi=rwi+1) row_wr_cnt[rwi] = 9'd0;
end
always @(posedge clk_ddr) begin
    if(fg_wr_en && fg_wr_addr[14:5] < 10'd720)
        row_wr_cnt[fg_wr_addr[14:5]] = row_wr_cnt[fg_wr_addr[14:5]] + 9'd1;
end

//------------ 每帧统计打印 ------------
integer frame_idx = 0;
reg [14:0] max_wr_addr;
always @(posedge clk_ddr) begin
    if(!rst_n) begin
        frame_idx <= 0;
        max_wr_addr <= 15'd0;
    end else if(frame_start) begin
        if(frame_idx > 0) begin
            $display("[%0t] 帧%0d 结束: 读总数=%0d fg_init=%0d 停止行=%0d",
                     $time, frame_idx-1, dbg_rd_cnt, fg_init, max_wr_addr[14:5]);
        end
        frame_idx <= frame_idx + 1;
        max_wr_addr <= 15'd0;
    end else if(fg_wr_en && fg_wr_addr > max_wr_addr)
        max_wr_addr <= fg_wr_addr;
end

//------------ 汇总：漏写行清单 ------------
// DRAIN 触发探针
reg drain_prev = 0;
always @(posedge clk_ddr) begin
    if(tb_uut.S_drain_active && !drain_prev)
        $display("[%0t] EVT DRAIN 开始", $time);
    drain_prev <= tb_uut.S_drain_active;
end
always @(posedge clk_ddr) begin
    if(tb_uut.S_wait_drain && !wait_prev)
        $display("[%0t] EVT wait_drain 置位: full_done=%0d drained=%0d cur_cnt=%0d bg_cnt=%0d cur96v=%0d bg96v=%0d",
                 $time, tb_uut.S_full_done, tb_uut.S_drained, tb_uut.S_cur_cnt, tb_uut.S_bg_cnt,
                 tb_uut.S_cur_96_valid, tb_uut.S_bg_96_valid);
    wait_prev <= tb_uut.S_wait_drain;
end
reg wait_prev = 0;
initial begin
    wait(rst_n === 1'b1);
    repeat(8) @(posedge frame_start);   // 跑 8 帧（A/B 半各 4 帧）
    repeat(6000000) @(posedge clk_ddr); // 尾帧收尾（B 半 2.61ms 读 + DRAIN 排空）
    $display("========================================");
    $display("漏写行清单（写拍数 < 32 的行，允许底部 700~719 放弃行）：");
    for(rwi=0; rwi<700; rwi=rwi+1) begin
        if(row_wr_cnt[rwi] < 9'd32)
            $display("  行 %0d: 写拍数 = %0d", rwi, row_wr_cnt[rwi]);
    end
    $display("（底部 700~719 为放弃行，漏写不判错：");
    for(rwi=700; rwi<720; rwi=rwi+1) $display("  行 %0d: 写拍数 = %0d", rwi, row_wr_cnt[rwi]);
    $display("）========================================");
    $finish;
end

endmodule
