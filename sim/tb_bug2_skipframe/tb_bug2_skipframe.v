//============================================================================
// tb_bug2_skipframe —— bug2 复现：自动曝光跳帧 → 画面错位
// 场景：video_in 正常写 3 帧 → ae_cfg_done 脉冲（自动模式）→ 跳 3 帧 → 恢复
// 判据：每帧写进 DDR 的字流必须与本帧摄像头数据对齐（错位字数 miss_cnt）
// 摄像头模型：cam 域 74.25MHz，真实节奏 1650×750 拍/帧（1280×720@60 + 消隐）
//   行内 240 拍 valid（128bit 字），tdata = {frame_id, word_id, 94'd0}
// DDR 域 100MHz；写 grant 240 拍 + vo 读占用 240 拍轮转（占空比 50%，模拟串行仲裁）
// checker 按 wr_addr % 帧长 推期望字序，覆盖全部 4 个乒乓块，排除排空批越界区
//============================================================================
`timescale 1ns/1ps
module tb_bug2_skipframe;

//------------ 时钟 -------------
reg clk_ddr = 1'b0;   // 100MHz（DDR 域）
reg clk_cam = 1'b0;   // 74.25MHz（摄像头域）
always #5      clk_ddr = ~clk_ddr;
always #6.7340 clk_cam = ~clk_cam;

//------------ 复位 -------------
reg rst_n;
initial begin
    rst_n = 1'b0;
    #200;
    rst_n = 1'b1;
end

//------------ 摄像头流模型（cam 域，连续出流；fcyc 初始在帧尾前，帧头脉冲快速到来）------------
localparam [20:0] FRAME_CYC  = 21'd1237500;   // 1650×750（60fps@74.25M）
localparam [20:0] ACTIVE_END = 21'd1188000;   // 1650×720
localparam [10:0] LINE_CYC   = 11'd1650;
localparam [7:0]  LINE_ACT   = 8'd240;

reg  [20:0] fcyc;
reg  [15:0] cam_frame_id;
reg         cam_frame_start;
wire [10:0] fcyc_col = fcyc % LINE_CYC;
wire [9:0]  fcyc_row = fcyc / LINE_CYC;

initial begin
    fcyc = FRAME_CYC - 21'd2000;   // 从帧尾前 2000 拍起步：第一个帧头脉冲即刻到来
    cam_frame_id = 16'd0;
    cam_frame_start = 1'b0;
end

always @(posedge clk_cam) begin
    cam_frame_start <= 1'b0;
    if(fcyc == FRAME_CYC - 1'b1) begin
        fcyc           <= 21'd0;
        cam_frame_id   <= cam_frame_id + 16'd1;
        cam_frame_start <= 1'b1;    // 帧尾拍置位 → 帧头拍（fcyc=0）可见
    end else
        fcyc <= fcyc + 21'd1;
end

wire        cam_valid = (fcyc < ACTIVE_END) && (fcyc_col < LINE_ACT);
wire [17:0] cam_word  = (fcyc_row * 9'd240 + {1'b0, fcyc_col});
// tdata 内容编码：{frame_id, word_id, 94'd0}
wire [127:0] cam_data = {cam_frame_id, cam_word, 94'd0};

//------------ 帧号跨域打 3 拍（checker 期望值）------------
reg [15:0] fid_s1, fid_s2, fid_s3;
always @(posedge clk_ddr) begin
    fid_s1 <= cam_frame_id;
    fid_s2 <= fid_s1;
    fid_s3 <= fid_s2;
end

//------------ DDR 域：写 grant / vo 读占用模型（WR↔VO 240 拍轮转）------------
reg  [8:0] arb_cnt;
reg        wr_grant;
reg        vo_busy;
always @(posedge clk_ddr or negedge rst_n) begin
    if(!rst_n) begin
        arb_cnt <= 9'd0;
        wr_grant <= 1'b0;
        vo_busy  <= 1'b0;
    end else begin
        arb_cnt <= (arb_cnt == 9'd479) ? 9'd0 : arb_cnt + 9'd1;
        if(arb_cnt == 9'd479) begin
            wr_grant <= 1'b1;
            vo_busy  <= 1'b0;
        end else if(arb_cnt == 9'd239) begin
            wr_grant <= 1'b0;
            vo_busy  <= 1'b1;
        end
    end
end

//------------ DUT：video_in -------------
wire [17:0] dbg_wr_cnt;
wire        fifo_full_latch;
wire        wr_en;
wire [24:0] wr_addr;
wire [127:0] wr_data;
wire [1:0]  video_out_rp;
wire        frame_start_ddr;

video_in tb_uut (
    .I_rst_n              ( rst_n          ),
    .I_camera_clk         ( clk_cam        ),
    .I_camera_frame_start ( cam_frame_start ),
    .I_camera_valid       ( cam_valid      ),
    .I_camera_data        ( cam_data       ),
    .I_mipi_rx_error      ( 1'b0           ),
    .I_ae_cfg_done        ( ae_done_pulse  ),
    .I_auto_en            ( 1'b1           ),   // 自动模式：跳帧
    .I_bg_capture         ( 1'b0           ),
    .I_init_calib_done    ( 1'b1           ),   //无训练场景：恒 1（复位后首排空批清一次，无害）
    .I_ddr_clk            ( clk_ddr        ),
    .I_display_pause      ( 1'b0           ),
    .I_video_out_rd_busy  ( vo_busy        ),
    .I_wr_grant           ( wr_grant       ),
    .O_wr_req             (                ),
    .O_video_in_wr_busy   (                ),
    .O_video_out_rp       ( video_out_rp   ),
    .O_frame_start_ddr    ( frame_start_ddr),
    .O_dbg_wr_cnt         ( dbg_wr_cnt     ),
    .O_ddr_user_wr_en     ( wr_en          ),
    .O_ddr_user_addr      ( wr_addr        ),
    .O_ddr_user_wr_data   ( wr_data        ),
    .I_ddr_user_ready     ( 1'b1           ),
    .O_fifo_full_latch    ( fifo_full_latch)
);

//------------ ae_cfg_done 脉冲注入：第 3 帧开始后 50000 拍给 8 拍脉冲（DDR 域）------------
reg ae_done_pulse;
initial begin
    ae_done_pulse = 1'b0;
    wait(rst_n === 1'b1);
    repeat(3) @(posedge frame_start_ddr);   // 等帧 0/1/2 帧头
    repeat(50000) @(posedge clk_ddr);       // 帧 2 期间注入
    ae_done_pulse = 1'b1;
    repeat(8) @(posedge clk_ddr);
    ae_done_pulse = 1'b0;
end

//------------ 错位 checker（DDR 域）------------
// 期望字序 = 块内偏移/8 = (wr_addr % FRAME_BYTES)/8；帧号 = expect_frame
// 覆盖全部 4 个乒乓块（wr_addr < 4×帧长区域），排除排空批越界区（字序 >= 172800）
localparam [24:0] FRAME_BYTES = 25'd172800 * 25'd8;   // 1382400
reg  [31:0] miss_cnt;
reg  [17:0] first_miss;
reg         miss_latched;
reg  [15:0] expect_frame;
reg  [24:0] frame_base;      // 本帧写入块的基址（帧内首写拍锁存）
integer      total_frames = 0;
integer      frames_with_miss = 0;
integer      max_miss = 0;

// 帧内字序 = (wr_addr - frame_base)/8；frame_base 在帧内首写拍锁存（块基址非帧长整数倍，不能用 mod）
wire [24:0] wr_addr_delta = (wr_addr >= frame_base) ? (wr_addr - frame_base) : 25'h1FFFFFF;
wire [17:0] wr_word_off   = wr_addr_delta[20:3];

always @(posedge clk_ddr) begin
    if(!rst_n) begin
        miss_cnt <= 32'd0;
        first_miss <= 18'd0;
        miss_latched <= 1'b0;
        expect_frame <= 16'd0;
        frame_base <= 25'h1FFFFFF;
    end else if(frame_start_ddr) begin
        // 帧开始拍：打印上一帧统计（dbg_raw = video_in 内部未锁存计数，拍前值 = 上一帧计数）
        if(miss_cnt != 32'd0 || miss_latched) begin
            $display("[%0t] 帧结束: 错位字数=%0d 首错字序=%0d (期望帧%0d) dbg=%0d dbg_raw=%0d fifo_full=%0d 帧头水位=%0d",
                     $time, miss_cnt, first_miss, expect_frame, dbg_wr_cnt, tb_uut.dbg_wr_cnt,
                     fifo_full_latch, tb_uut.S_fifo_rd_num);
            frames_with_miss = frames_with_miss + 1;
            if(miss_cnt > max_miss) max_miss = miss_cnt;
        end else begin
            $display("[%0t] 帧结束: 本帧零错位 dbg=%0d dbg_raw=%0d fifo_full=%0d 帧头水位=%0d",
                     $time, dbg_wr_cnt, tb_uut.dbg_wr_cnt, fifo_full_latch, tb_uut.S_fifo_rd_num);
        end
        miss_cnt <= 32'd0;
        first_miss <= 18'd0;
        miss_latched <= 1'b0;
        expect_frame <= fid_s3;
        frame_base <= 25'h1FFFFFF;   // 重新等首写拍锁存
        total_frames = total_frames + 1;
    end else if(wr_en && (wr_addr < 25'd28000000)) begin
        if(frame_base == 25'h1FFFFFF)
            frame_base <= wr_addr;   // 帧内首写拍 = 帧头基址
        if(frame_base != 25'h1FFFFFF && wr_word_off < 18'd172800) begin
            if((wr_data[127:112] != expect_frame) || (wr_data[111:94] != wr_word_off)) begin
                if(!miss_latched) begin
                    miss_latched <= 1'b1;
                    first_miss <= wr_word_off;
                    $display("[%0t] 首错拍: addr=%0d base=%0d word_off=%0d 写入帧%0d字%0d 期望帧%0d字%0d",
                             $time, wr_addr, frame_base, wr_word_off, wr_data[127:112], wr_data[111:94],
                             expect_frame, wr_word_off);
                end
                miss_cnt <= miss_cnt + 32'd1;
            end
        end
    end
end

//------------ 总仿真时长与判词 -------------
// 调试探针：写批状态机内部信号（编译需 --public-flat-rw）
reg [23:0] dbg_tick = 0;
always @(posedge clk_ddr) dbg_tick <= dbg_tick + 24'd1;
always @(posedge clk_ddr) begin
    if(dbg_tick == 24'd5000000 || dbg_tick == 24'd10000000 || dbg_tick == 24'd15000000)   // 3 个采样点
        $display("[%0t] DBG rdnum=%0d wr_valid=%0d fend_drain=%0d fifo_full=%0d fs_d1=%0d drain_cnt=%0d skip=%0d",
                 $time, tb_uut.S_fifo_rd_num, tb_uut.S_ddr_wr_valid, tb_uut.S_fend_drain,
                 tb_uut.S_fifo_full, tb_uut.S_frame_start_d1,
                 tb_uut.S_drain_cnt, tb_uut.r_skip_cnt);
end
integer evt_cnt = 0;
always @(posedge clk_ddr) begin
    if(tb_uut.S_ddr_wr_valid && !wr_valid_prev && evt_cnt < 30) begin
        $display("[%0t] EVT wr_valid 上升（rdnum=%0d）", $time, tb_uut.S_fifo_rd_num);
        evt_cnt = evt_cnt + 1;
    end
    wr_valid_prev <= tb_uut.S_ddr_wr_valid;
end
reg wr_valid_prev = 0;

initial begin
    // 跑 12 帧（真实节奏每帧 DDR 域 166.7 万拍，12 帧 ≈ 2000 万拍）
    wait(rst_n === 1'b1);
    repeat(12) @(posedge frame_start_ddr);
    repeat(300000) @(posedge clk_ddr);   // 尾帧收尾
    $display("========================================");
    $display("总帧数=%0d 错位帧数=%0d 最大错位字数=%0d fifo_full=%0d", total_frames, frames_with_miss, max_miss, fifo_full_latch);
    if(frames_with_miss > 0)
        $display("复现结论：跳帧后出现错位（bug2 复现）");
    else
        $display("复现结论：本次未错位");
    $finish;
end

endmodule
