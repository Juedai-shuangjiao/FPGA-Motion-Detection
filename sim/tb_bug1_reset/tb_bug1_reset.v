//============================================================================
// tb_bug1_reset —— bug1 复现：按键复位 → DDR 重训 → 画面错位
// 场景：摄像头持续满速出流（外部芯片不复位）；FPGA 复位释放后，
//   DDR 硬核训练期 ready=0 保持 5ms（500000 拍@100M）——期间采集 FIFO 持续灌入
//   → 溢出丢字 + 帧尾排空批写不出留残字；训练结束 ready=1 → 观察错位
// 判据：每帧写进 DDR 的字流必须与本帧摄像头数据对齐（miss_cnt）
//   复现预期：训练结束后若干帧错位；修复预期：训练后第 1 帧起零错位（或仅 1 帧残缺）
// 摄像头模型：真实节奏 1650×750 拍/帧（1280×720@60），tdata={frame_id,word_id,94'd0}
// checker 按 wr_addr % 帧长 推期望字序，覆盖全部 4 个乒乓块
//============================================================================
`timescale 1ns/1ps
module tb_bug1_reset;

//------------ 时钟 -------------
reg clk_ddr = 1'b0;   // 100MHz（DDR 域）
reg clk_cam = 1'b0;   // 74.25MHz（摄像头域）
always #5      clk_ddr = ~clk_ddr;
always #6.7340 clk_cam = ~clk_cam;

//------------ 复位（FPGA 侧）------------
reg rst_n;
initial begin
    rst_n = 1'b0;
    #200;
    rst_n = 1'b1;   // PLL 锁定，系统复位释放（DDR 训练从此开始）
end

//------------ 摄像头流模型（cam 域，不复位，从 t=0 持续出流）------------
// 流中断场景（实机 uicfgcs500 复位后重写寄存器表：索引1 写 0x0100=0 关流、
// 索引114 写 0x0100=1 重开流）：复位后 100µs 流关断（valid 全 0、fcyc 冻结在帧尾区），
// 50ms 后流重开（从新帧头出流）。训练期（0~5ms）与流关断重叠。
localparam [20:0] FRAME_CYC  = 21'd1237500;   // 1650×750（60fps@74.25M）
localparam [20:0] ACTIVE_END = 21'd1188000;   // 1650×720
localparam [10:0] LINE_CYC   = 11'd1650;
localparam [7:0]  LINE_ACT   = 8'd240;

reg  [20:0] fcyc;
reg  [15:0] cam_frame_id;
reg         cam_frame_start;
reg         stream_on;     // 1=流开 0=流关断（模拟 0x0100 开关）
wire [10:0] fcyc_col = fcyc % LINE_CYC;
wire [9:0]  fcyc_row = fcyc / LINE_CYC;

initial begin
    fcyc = FRAME_CYC - 21'd2000;   // 从帧尾前 2000 拍起步：第一个帧头脉冲即刻到来
    cam_frame_id = 16'd0;
    cam_frame_start = 1'b0;
    stream_on = 1'b1;
end

// 流关断/重开时序（模拟 uicfgcs500 重配置：复位后 100µs 写 0x0100=0 关流、50ms 后写 0x0100=1 重开）
initial begin
    wait(rst_n === 1'b1);
    #100000;                 // 100µs：0x0100=0 关流
    stream_on = 1'b0;
    #50000000;               // 50ms：0x0100=1 重开流
    stream_on = 1'b1;
end

always @(posedge clk_cam) begin
    cam_frame_start <= 1'b0;
    if(!stream_on) begin
        // 流关断：冻结在帧尾区（valid 全 0），重开时从帧尾拍推进 → 下一拍帧头脉冲 → 干净帧头重同步
        fcyc <= FRAME_CYC - 1'b1;
    end else if(fcyc == FRAME_CYC - 1'b1) begin
        fcyc           <= 21'd0;
        cam_frame_id   <= cam_frame_id + 16'd1;
        cam_frame_start <= 1'b1;
    end else
        fcyc <= fcyc + 21'd1;
end

wire        cam_valid = (fcyc < ACTIVE_END) && (fcyc_col < LINE_ACT);
wire [17:0] cam_word  = (fcyc_row * 9'd240 + {1'b0, fcyc_col});
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

//------------ DDR 训练期模型：复位后 ready=0 保持 TRAIN_TICKS 拍（5ms）------------
localparam integer TRAIN_TICKS = 500000;
reg [23:0] tick;
reg        ddr_ready;
always @(posedge clk_ddr or negedge rst_n) begin
    if(!rst_n) begin
        tick      <= 24'd0;
        ddr_ready <= 1'b0;
    end else begin
        tick <= tick + 24'd1;
        if(tick >= TRAIN_TICKS - 1'b1)
            ddr_ready <= 1'b1;   // 训练完成，ready 恢复
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
    .I_ae_cfg_done        ( 1'b0           ),
    .I_auto_en            ( 1'b1           ),
    .I_bg_capture         ( 1'b0           ),
    .I_init_calib_done    ( ddr_ready      ),   //训练完成拉高（上升沿触发清 FIFO）
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
    .I_ddr_user_ready     ( ddr_ready      ),
    .O_fifo_full_latch    ( fifo_full_latch)
);

//------------ 错位 checker（DDR 域）------------
localparam [24:0] FRAME_BYTES = 25'd172800 * 25'd8;
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
        if(miss_cnt != 32'd0 || miss_latched) begin
            $display("[%0t] 帧结束: 错位字数=%0d 首错字序=%0d (期望帧%0d) dbg=%0d dbg_raw=%0d fifo_full=%0d ready=%0d",
                     $time, miss_cnt, first_miss, expect_frame, dbg_wr_cnt, tb_uut.dbg_wr_cnt,
                     fifo_full_latch, ddr_ready);
            frames_with_miss = frames_with_miss + 1;
            if(miss_cnt > max_miss) max_miss = miss_cnt;
        end else begin
            $display("[%0t] 帧结束: 本帧零错位 dbg=%0d dbg_raw=%0d fifo_full=%0d ready=%0d",
                     $time, dbg_wr_cnt, tb_uut.dbg_wr_cnt, fifo_full_latch, ddr_ready);
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

//------------ 训练完成时刻打印（对齐观察窗口）------------
always @(posedge clk_ddr) begin
    if(tick == TRAIN_TICKS)
        $display("[%0t] ===== DDR 训练完成，ready 恢复 =====", $time);
end

//------------ 总仿真时长与判词 -------------
initial begin
    wait(rst_n === 1'b1);
    repeat(12) @(posedge frame_start_ddr);
    repeat(300000) @(posedge clk_ddr);
    $display("========================================");
    $display("总帧数=%0d 错位帧数=%0d 最大错位字数=%0d fifo_full=%0d", total_frames, frames_with_miss, max_miss, fifo_full_latch);
    if(frames_with_miss > 0)
        $display("复现结论：复位重训后出现错位（bug1 复现）");
    else
        $display("复现结论：本次未错位");
    $finish;
end

endmodule
