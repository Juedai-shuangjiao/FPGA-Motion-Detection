//========================================================
// 模块：sobel_top —— Sobel 边缘检测
// 功能：输入 96 位灰度（4像素，R=G=B=gray），输出 96 位边缘图（黑底白线）
// 实现：line buffer（复用 line_buffer_demosaic 的 BRAM，级联 2 个）攒三行
//       → 3×3 卷积算 Gx/Gy → 幅值 |Gx|+|Gy| → 阈值比较
// 说明：
//   · line buffer 复用 demosaic 的 line_buffer_demosaic（BRAM 硬核 + 地址计数，
//     只在 valid 时递增、消隐期冻结），天然对齐「上一行」，不受行间消隐影响
//   · 级联 2 个 + 打拍对齐（照搬 raw_matrix_3x3_buffer），得到对齐的三行
//   · 4 像素并行，每组的 g3 右邻居用「复制 g3」近似
//   · 边界：前两行/最后一行（v_cnt<2 或 =719）、第一/最后一组输出 0（黑）
//   · 输出延迟 2 拍（data_d0 打 2 拍），O_tvalid/O_tlast/O_tuser 同步延迟
//========================================================
module sobel_top (
    input  wire        I_clk,          //像素时钟
    input  wire        I_rst_n,        //复位，低有效
    input  wire [95:0] I_tdata,        //输入 96 位灰度（4像素，R=G=B=gray）
    input  wire        I_tvalid,       //数据有效
    input  wire        I_tlast,        //行结束
    input  wire        I_tuser,        //帧开始
    input  wire [10:0] I_threshold,    //Sobel 阈值（0~2040，11位）
    output wire [95:0] O_tdata,        //输出 96 位边缘图
    output wire        O_tvalid,       //输出有效（延迟 2 拍，与数据对齐）
    output wire        O_tlast,        //输出行结束（延迟 2 拍）
    output wire        O_tuser         //输出帧开始（延迟 2 拍）
);

    //------------ 提取 4 个灰度值（每像素取低 8 位，R=G=B=gray）------------
    wire [7:0] g0 = I_tdata[7:0];
    wire [7:0] g1 = I_tdata[31:24];
    wire [7:0] g2 = I_tdata[55:48];
    wire [7:0] g3 = I_tdata[79:72];
    wire [31:0] gray_4p = {g3, g2, g1, g0};   //4像素灰度，32位

    //------------ line buffer：级联 2 个 line_buffer_demosaic（BRAM）------------
    // data0=当前行，data1=延迟一行，data2=延迟两行（每级 33 位：1 tuser + 32 灰度）
    wire [32:0] data0 = {I_tuser, gray_4p};
    wire        valid0 = I_tvalid;
    wire [32:0] data1, data2;
    wire        valid1, valid2;

    line_buffer_demosaic #(
        .IMG_HEIGHT(720 ),
        .IMG_WIDTH (1280)
    ) u_lb1 (
        .I_clk    (I_clk  ),
        .I_rst_n  (I_rst_n),
        .I_tuser  (data0[32] & valid0),
        .I_valid  (valid0 ),
        .I_data   (data0  ),
        .O_valid  (valid1 ),
        .O_data   (data1  )
    );
    line_buffer_demosaic #(
        .IMG_HEIGHT(720 ),
        .IMG_WIDTH (1280)
    ) u_lb2 (
        .I_clk    (I_clk  ),
        .I_rst_n  (I_rst_n),
        .I_tuser  (data1[32] & valid1),
        .I_valid  (valid1 ),
        .I_data   (data1  ),
        .O_valid  (valid2 ),
        .O_data   (data2  )
    );

    //------------ 对齐打拍（照搬 raw_matrix_3x3_buffer）------------
    // data[0] 补 2 拍、data[1] 补 1 拍、data[2] 不补，得到同拍的三行
    reg [32:0] data_d0_d, data_d0, data_d1;
    reg        valid_d0, valid_d1;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            data_d0_d <= 33'd0;
            data_d0   <= 33'd0;
            data_d1   <= 33'd0;
            valid_d0  <= 1'b0;
            valid_d1  <= 1'b0;
        end else begin
            valid_d0  <= valid0;
            valid_d1  <= valid_d0;
            data_d0_d <= data0;
            data_d0   <= data_d0_d;
            data_d1   <= data1;
        end
    end
    wire [32:0] data_d2 = data2;

    //------------ 三行灰度（对齐后同拍）------------
    wire [31:0] cur = data_d0[31:0];   //当前行
    wire [31:0] up  = data_d1[31:0];   //上一行
    wire [31:0] up2 = data_d2[31:0];   //上上两行

    //------------ 行/组计数器（照搬 raw_matrix_3x3_buffer，抗消隐）------------
    reg [13:0] h_cnt;  //组号 0~319
    reg [13:0] v_cnt;  //行号 0~719
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n || I_tuser) begin
            h_cnt <= 14'd0;
            v_cnt <= 14'd0;
        end else begin
            h_cnt <= valid_d1 ? ((h_cnt == 14'd319) ? 14'd0 : h_cnt + 1'b1) : h_cnt;
            v_cnt <= (valid_d1 && (h_cnt == 14'd319)) ? ((v_cnt == 14'd719) ? 14'd0 : v_cnt + 1'b1) : v_cnt;
        end
    end

    //------------ 缓存「上一组 g3」作为本组 g0 的左邻居 ------------
    reg [7:0] r_prev_g3_cur;
    reg [7:0] r_prev_g3_up;
    reg [7:0] r_prev_g3_up2;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            r_prev_g3_cur <= 8'd0;
            r_prev_g3_up  <= 8'd0;
            r_prev_g3_up2 <= 8'd0;
        end else begin
            r_prev_g3_cur <= cur[31:24];
            r_prev_g3_up  <= up[31:24];
            r_prev_g3_up2 <= up2[31:24];
        end
    end

    //------------ 边界有效（屏蔽前两行/最后一行、第一/最后一组）------------
    // 输出延迟一行（窗口中心在 up），故有效行 = v_cnt 2~719（对应第 1~718 行）
    wire cur_valid = (v_cnt >= 14'd2) && (v_cnt <= 14'd719) &&
                     (h_cnt >= 14'd1) && (h_cnt <= 14'd318);

    //------------ 3×3 卷积 function（返回 1=边缘，0=非边缘）------------
    function [0:0] sobel_pixel;
        input [7:0] a, b, c, d, e, f, g, h, i;   //3×3 邻域（a=左上 ... i=右下）
        input [10:0] thr;                         //阈值
        reg  [10:0] gx_pos, gx_neg, gy_pos, gy_neg;
        reg  [11:0] gx_s, gy_s, mag;
        begin
            gx_pos = {3'd0, c} + {2'd0, f, 1'b0} + {3'd0, i};
            gx_neg = {3'd0, a} + {2'd0, d, 1'b0} + {3'd0, g};
            gy_pos = {3'd0, g} + {2'd0, h, 1'b0} + {3'd0, i};
            gy_neg = {3'd0, a} + {2'd0, b, 1'b0} + {3'd0, c};
            gx_s = {1'b0, gx_pos} - {1'b0, gx_neg};
            gy_s = {1'b0, gy_pos} - {1'b0, gy_neg};
            mag = (gx_s[11] ? (~gx_s + 12'd1) : gx_s) + (gy_s[11] ? (~gy_s + 12'd1) : gy_s);
            sobel_pixel = (mag > {1'b0, thr}) ? 1'b1 : 1'b0;
        end
    endfunction

    //------------ 4 像素并行 Sobel（g3 右邻居复制 g3）------------
    wire p0 = sobel_pixel(r_prev_g3_up2, up2[7:0],   up2[15:8],
                          r_prev_g3_up,  up[7:0],    up[15:8],
                          r_prev_g3_cur, cur[7:0],   cur[15:8],   I_threshold);
    wire p1 = sobel_pixel(up2[7:0],  up2[15:8],  up2[23:16],
                          up[7:0],   up[15:8],   up[23:16],
                          cur[7:0],  cur[15:8],  cur[23:16],  I_threshold);
    wire p2 = sobel_pixel(up2[15:8], up2[23:16], up2[31:24],
                          up[15:8],  up[23:16],  up[31:24],
                          cur[15:8], cur[23:16], cur[31:24],  I_threshold);
    wire p3 = sobel_pixel(up2[23:16], up2[31:24], up2[31:24],
                          up[23:16],  up[31:24],  up[31:24],
                          cur[23:16], cur[31:24], cur[31:24],  I_threshold);

    //------------ 输出拼接（边缘=白255，非边缘/边界=黑0）------------
    wire [7:0] e0 = (cur_valid && p0) ? 8'hFF : 8'h00;
    wire [7:0] e1 = (cur_valid && p1) ? 8'hFF : 8'h00;
    wire [7:0] e2 = (cur_valid && p2) ? 8'hFF : 8'h00;
    wire [7:0] e3 = (cur_valid && p3) ? 8'hFF : 8'h00;

    assign O_tdata  = {e3,e3,e3, e2,e2,e2, e1,e1,e1, e0,e0,e0};

    //------------ valid/tlast/tuser 同步延迟 2 拍（与 data_d0 对齐）------------
    reg tvalid_d1, tvalid_d2;
    reg tlast_d1,  tlast_d2;
    reg tuser_d1,  tuser_d2;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            tvalid_d1 <= 1'b0; tvalid_d2 <= 1'b0;
            tlast_d1  <= 1'b0; tlast_d2  <= 1'b0;
            tuser_d1  <= 1'b0; tuser_d2  <= 1'b0;
        end else begin
            tvalid_d1 <= I_tvalid; tvalid_d2 <= tvalid_d1;
            tlast_d1  <= I_tlast;  tlast_d2  <= tlast_d1;
            tuser_d1  <= I_tuser;  tuser_d2  <= tuser_d1;
        end
    end
    assign O_tvalid = tvalid_d2;
    assign O_tlast  = tlast_d2;
    assign O_tuser  = tuser_d2;

endmodule
