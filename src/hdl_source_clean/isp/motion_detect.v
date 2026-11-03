
//========================================================
// 模块：motion_detect —— 背景减除（DDR 全分辨率版 + 帧同步对齐）
// 功能：当前帧 96 位 RGB 减 DDR 背景（bg_read 输出的 96 位 RGB），任一通道差超阈值判前景。
//       全分辨率 1280×720（不降采样），前景边界 1 像素精确。
// 帧同步对齐：当前帧存 FIFO，用「背景帧开始」动态对齐，消除 DDR 域↔摄像头域的跨时钟域漂移
//        （不再用固定 DELAY 拍硬凑）。
// 保留：背景采集状态机（SW4 触发）+ 闭运算（水平 3 邻域膨胀去孤立点）。
//========================================================
module motion_detect (
    input  wire        I_clk,            //像素时钟（摄像头域 60M）
    input  wire        I_rst_n,          //复位，低有效
    input  wire [95:0] I_tdata,          //输入 96 位 RGB（4像素，每像素 R/G/B 各 8 位）
    input  wire        I_tvalid,         //数据有效
    input  wire        I_tlast,          //行结束
    input  wire        I_tuser,          //帧开始
    input  wire        I_sw4,            //SW4：模式选择低两位（与 SW3 组合四模式：01=模式2涂白 10=模式3外接框）
    input  wire        I_sw3,            //SW3：模式选择高两位（组合变化触发背景采集）
    input  wire        I_ae_chg,         //2026-11-03 AE 变化沿（自动状态曝光/增益变化 → 00 模式也重采背景）
    input  wire [95:0] I_bg_data,        //背景 96 位 RGB（4像素，来自 bg_read）
    input  wire        I_bg_valid,       //背景有效（来自 bg_read）
    input  wire        I_bg_frame_start, //背景帧开始（来自 bg_read，跟 I_bg_data 对齐）
    output wire [95:0] O_tdata,          //输出 96 位前景图（R=G=B=前景标记）
    output wire [95:0] O_cur_data,       //读出的当前帧（跟 O_tdata 对齐，供原样叠加回显）
    output wire        O_tvalid,         //输出有效
    output wire        O_tlast,          //输出行结束
    output wire        O_tuser,          //输出帧开始
    output wire        O_bg_capture,     //背景采集标志（覆盖完整一帧，给 DDR 背景写）
    output wire        O_bg_captured     //背景已采锁存（采过即保持 1，门控 bg_read 启动：采完才跑检测）
);

    // 减背景阈值（8bit，前景背景差，手肤色 R 差约 70）
    localparam [7:0] THRESHOLD = 8'd40;
    // 当前帧 FIFO 深度（吸收背景读延迟 + 跨时钟域漂移，背景延迟约几十拍 < 128）
    localparam FIFO_DEPTH = 128;

    //------------ 提取当前帧 4 像素 RGB 8bit ------------
    wire [7:0] r0 = I_tdata[23:16], g0 = I_tdata[15:8],  b0 = I_tdata[7:0];
    wire [7:0] r1 = I_tdata[47:40], g1 = I_tdata[39:32], b1 = I_tdata[31:24];
    wire [7:0] r2 = I_tdata[71:64], g2 = I_tdata[63:56], b2 = I_tdata[55:48];
    wire [7:0] r3 = I_tdata[95:88], g3 = I_tdata[87:80], b3 = I_tdata[79:72];

    //------------ 提取背景 4 像素 RGB 8bit ------------
    wire [7:0] br0 = I_bg_data[23:16], bg0 = I_bg_data[15:8],  bb0 = I_bg_data[7:0];
    wire [7:0] br1 = I_bg_data[47:40], bg1 = I_bg_data[39:32], bb1 = I_bg_data[31:24];
    wire [7:0] br2 = I_bg_data[71:64], bg2 = I_bg_data[63:56], bb2 = I_bg_data[55:48];
    wire [7:0] br3 = I_bg_data[95:88], bg3 = I_bg_data[87:80], bb3 = I_bg_data[79:72];

    //------------ 当前帧 FIFO（帧同步对齐，吸收背景延迟 + 漂移）------------
    // 当前帧连续写入 FIFO（数据 + tlast + tuser）。
    // 读指针在「背景帧开始」时重置到「当前帧帧开始」的位置，之后每拍读，
    // 读出的当前帧就跟背景严格同帧对齐，漂移被每帧的「帧开始重置」吸收。
    reg [95:0] cur_fifo [0:FIFO_DEPTH-1];
    reg [FIFO_DEPTH-1:0] cur_tlast_fifo;
    reg [FIFO_DEPTH-1:0] cur_tuser_fifo;
    reg [6:0] cur_wptr;          //写指针（I_tvalid 时 +1，0~127 循环）
    reg [6:0] frame_start_wptr;  //当前帧帧开始时的写指针（I_tuser 时记录）
    reg [6:0] cur_rptr;          //读指针（背景帧开始时重置，之后每拍 +1）
    reg       cur_fifo_valid;    //读指针已对齐（背景帧开始后置 1）

    integer fk;
    always @(posedge I_clk) begin
        if (I_tvalid) begin
            cur_fifo[cur_wptr]       <= I_tdata;
            cur_tlast_fifo[cur_wptr] <= I_tlast;
            cur_tuser_fifo[cur_wptr] <= I_tuser;
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            cur_wptr         <= 7'd0;
            frame_start_wptr <= 7'd0;
        end else begin
            if (I_tvalid)
                cur_wptr <= cur_wptr + 1'b1;
            if (I_tuser)
                frame_start_wptr <= cur_wptr;   //帧开始，记录当前写指针
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            cur_rptr       <= 7'd0;
            cur_fifo_valid <= 1'b0;
        end else begin
            if (I_bg_frame_start) begin
                cur_rptr       <= frame_start_wptr;  //读指针 = 当前帧帧开始的写指针
                cur_fifo_valid <= 1'b1;
            end else if (cur_fifo_valid && I_bg_valid) begin
                cur_rptr <= cur_rptr + 1'b1;
            end
        end
    end

    // 读出的当前帧（跟背景严格同帧对齐）
    wire [95:0] cur_d       = cur_fifo[cur_rptr];
    wire        read_valid  = cur_fifo_valid && I_bg_valid;
    wire        read_tlast  = cur_tlast_fifo[cur_rptr];
    wire        read_tuser  = cur_tuser_fifo[cur_rptr];
    wire [7:0] cr0 = cur_d[23:16], cg0 = cur_d[15:8],  cb0 = cur_d[7:0];
    wire [7:0] cr1 = cur_d[47:40], cg1 = cur_d[39:32], cb1 = cur_d[31:24];
    wire [7:0] cr2 = cur_d[71:64], cg2 = cur_d[63:56], cb2 = cur_d[55:48];
    wire [7:0] cr3 = cur_d[95:88], cg3 = cur_d[87:80], cb3 = cur_d[79:72];

    //------------ 减背景（任一通道差超阈值判前景，4 像素并行，read_valid 门控）------------
    function [7:0] absdiff;
        input [7:0] a, b;
        begin
            if (a > b)
                absdiff = a - b;
            else
                absdiff = b - a;
        end
    endfunction
    wire m0 = read_valid && ((absdiff(cr0,br0) > THRESHOLD) || (absdiff(cg0,bg0) > THRESHOLD) || (absdiff(cb0,bb0) > THRESHOLD));
    wire m1 = read_valid && ((absdiff(cr1,br1) > THRESHOLD) || (absdiff(cg1,bg1) > THRESHOLD) || (absdiff(cb1,bb1) > THRESHOLD));
    wire m2 = read_valid && ((absdiff(cr2,br2) > THRESHOLD) || (absdiff(cg2,bg2) > THRESHOLD) || (absdiff(cb2,bb2) > THRESHOLD));
    wire m3 = read_valid && ((absdiff(cr3,br3) > THRESHOLD) || (absdiff(cg3,bg3) > THRESHOLD) || (absdiff(cb3,bb3) > THRESHOLD));
    wire [3:0] motion_4p = {m3, m2, m1, m0};

    //------------ SW3/SW4 打 2 拍 + 模式组合变化检测 + 背景采集状态机 ------------
    reg sw4_d1, sw4_d2;
    reg sw3_d1, sw3_d2;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin sw4_d1 <= 1'b0; sw4_d2 <= 1'b0; sw3_d1 <= 1'b0; sw3_d2 <= 1'b0; end
        else begin
            sw4_d1 <= I_sw4; sw4_d2 <= sw4_d1;
            sw3_d1 <= I_sw3; sw3_d2 <= sw3_d1;
        end
    end

    // 模式组合（SW3/SW4 拨下=1）：00=模式1显示 01=模式2涂白 10=模式3外接框 11=模式4区域填充
    wire [1:0] mode_now      = {sw3_d2, sw4_d2};
    wire       mode_need_bg  = (mode_now != 2'b00);   //模式2/3/4 都需要背景（涂白/框/填充全吃背景差分）
    reg  [1:0] mode_prev;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) mode_prev <= 2'b00;
        else         mode_prev <= mode_now;
    end
    wire mode_changed = (mode_now != mode_prev);

    // 冷却计数：采集完成后 180 帧（3 秒）内不重复触发，防频繁采集
    localparam COOLDOWN_FRAMES = 8'd180;
    reg [7:0] cooldown_cnt;
    wire      cooling = (cooldown_cnt != 8'd0);
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            cooldown_cnt <= 8'd0;
        else begin
            if(I_tuser && cooling)
                cooldown_cnt <= cooldown_cnt - 8'd1;   //每帧减一
            else if(bg_capture && !S_cap_done_prev)    //采集完成沿：启动冷却（见状态机块）
                cooldown_cnt <= COOLDOWN_FRAMES;
        end
    end

    reg [1:0] bg_state;
    reg       bg_capture;
    reg       bg_captured;   //「本次采集已完成」标志：触发时清 0（门控关，bg_read 暂停）、
                             //采集帧置 1（门控开）——保证每次模式切换都有「100ms 等待→涂白/框出现」的时序
    reg       S_cap_done_prev;
    reg [6:0] bg_delay_cnt;    //防抖延迟计数：触发后等 6 帧再采（拨码/手碰导致摄像头晃动，约 100ms 稳住）
    localparam BG_DELAY_FRAMES = 7'd6;    //6 帧 ≈ 100ms（60fps）；实测 1s（60帧）过长，机械抖动稳定不需要 1s
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            bg_state       <= 2'd0;
            bg_capture     <= 1'b0;
            bg_captured    <= 1'b0;
            bg_delay_cnt   <= 7'd0;
            S_cap_done_prev <= 1'b0;
        end else begin
            S_cap_done_prev <= bg_capture;
            case(bg_state)
                2'd0: if ((mode_changed && mode_need_bg && !cooling) ||
                          (I_ae_chg && (mode_now == 2'b00) && !cooling)) begin   //2026-11-03 AE 变化触发：仅 00 模式（自动状态已在上层门控）
                          bg_state     <= 2'd1;    //进入防抖等待
                          bg_delay_cnt <= 7'd0;
                          bg_captured  <= 1'b0;    //新采集周期开始：门控关闭，画面干净等防抖
                      end
                2'd1: if (I_tuser) begin             //每帧开始计一帧
                          if (bg_delay_cnt >= BG_DELAY_FRAMES) begin
                              bg_state   <= 2'd2;   //延迟满 6 帧，采背景
                              bg_capture <= 1'b1;
                          end else
                              bg_delay_cnt <= bg_delay_cnt + 7'd1;
                      end
                2'd2: if (I_tuser) begin bg_state <= 2'd0; bg_capture <= 1'b0; end
                default: bg_state <= 2'd0;
            endcase
            // 2026-11-02 修复：bg_captured 必须在「采集帧结束」后置 1（bg_capture 下降沿），
            // 不能在 bg_capture=1 的第一拍置 1——否则背景帧（16.7ms）还没写完，
            // bg_read 下一 vsync 就开门读「写了一半的背景」，差分满屏乱标记
            // （实机现象：拨码后画面立即出现未采集数据的检测结果）。
            if(S_cap_done_prev && !bg_capture)
                bg_captured <= 1'b1;   //采集帧完成（背景已完整写入 DDR）：门控打开，检测开始
        end
    end
    assign O_bg_capture  = bg_capture;
    assign O_bg_captured = bg_captured;

    //------------ 减背景打 1 拍 + 闭运算前对齐 ------------
    reg [3:0] motion_d1;
    reg       valid_d1;
    reg       tlast_d1;
    reg       tuser_d1;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            motion_d1 <= 4'd0;
            valid_d1  <= 1'b0;
            tlast_d1  <= 1'b0;
            tuser_d1  <= 1'b0;
        end else begin
            motion_d1 <= motion_4p;
            valid_d1  <= read_valid;
            tlast_d1  <= read_tlast;
            tuser_d1  <= read_tuser;
        end
    end

    //------------ 闭运算（水平 3 邻域膨胀，去孤立点）------------
    // 4 像素并行，每像素做「本像素 | 左邻 | 右邻」。跨组用 m_prev 的 bit3 和下一组 bit0。
    reg [3:0] m_prev;   //上一组 motion（水平左邻居）
    reg [3:0] dilate;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            m_prev <= 4'd0;
            dilate <= 4'd0;
        end else if (valid_d1) begin
            m_prev <= tuser_d1 ? 4'd0 : motion_d1;   //帧开始，左邻居清零
            dilate[0] <= m_prev[3] | motion_d1[0] | motion_d1[1];
            dilate[1] <= motion_d1[0] | motion_d1[1] | motion_d1[2];
            dilate[2] <= motion_d1[1] | motion_d1[2] | motion_d1[3];
            dilate[3] <= motion_d1[2] | motion_d1[3] | motion_d1[2];  //右邻暂用复制（无下一组）
        end
    end

    // 输出（bg_captured 后，前景白；未采集输出黑）
    wire [3:0] out_4p = bg_captured ? dilate : 4'd0;

    // 输出拼接（每像素 R=G=B=前景标记 0/255）
    wire [7:0] px0 = out_4p[0] ? 8'hFF : 8'h00;
    wire [7:0] px1 = out_4p[1] ? 8'hFF : 8'h00;
    wire [7:0] px2 = out_4p[2] ? 8'hFF : 8'h00;
    wire [7:0] px3 = out_4p[3] ? 8'hFF : 8'h00;
    assign O_tdata = {px3,px3,px3, px2,px2,px2, px1,px1,px1, px0,px0,px0};

    // 读出的当前帧打 2 拍（对齐 O_tdata 的 motion_d1 + dilate 2 拍延迟），供原样叠加回显
    reg [95:0] cur_d1, cur_d2;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            cur_d1 <= 96'd0;
            cur_d2 <= 96'd0;
        end else begin
            cur_d1 <= cur_d;
            cur_d2 <= cur_d1;
        end
    end
    assign O_cur_data = cur_d2;

    //------------ valid/tlast/tuser 打 2 拍对齐（motion_d1 + dilate 的 2 拍）------------
    reg tvalid_d2;
    reg tlast_d2;
    reg tuser_d2;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            tvalid_d2 <= 1'b0;
            tlast_d2  <= 1'b0;
            tuser_d2  <= 1'b0;
        end else begin
            tvalid_d2 <= valid_d1;
            tlast_d2  <= tlast_d1;
            tuser_d2  <= tuser_d1;
        end
    end
    assign O_tvalid = tvalid_d2;
    assign O_tlast  = tlast_d2;
    assign O_tuser  = tuser_d2;

endmodule
