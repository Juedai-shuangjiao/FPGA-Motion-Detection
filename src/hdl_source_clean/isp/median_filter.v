//========================================================
// 模块：median_filter —— 3×3 中值滤波（Sobel 边缘检测前去噪）
// 功能：输入 96 位灰度（4像素，R=G=B=gray），输出 3×3 中值滤波后的灰度图
// 实现：line buffer 攒 3 行（复用 line_buffer_demosaic，与 sobel_top 同框架）
//       → 3×3 窗口取 9 个灰度值的中值
// 说明：去孤立噪点（椒盐噪声）。配合 Sobel 降阈值使用——降阈值会引入噪点，
//       中值滤波把孤立噪点滤掉，只留下真正的边缘。
//       4 像素并行，g3 右邻居用「复制 g3」近似（与 sobel 一致）。
//       输出延迟 2 拍（line buffer 对齐），O_tvalid/O_tlast/O_tuser 同步延迟。
//========================================================
module median_filter (
    input  wire        I_clk,          //像素时钟
    input  wire        I_rst_n,        //复位，低有效
    input  wire [95:0] I_tdata,        //输入 96 位灰度（4像素，R=G=B=gray）
    input  wire        I_tvalid,       //数据有效
    input  wire        I_tlast,        //行结束
    input  wire        I_tuser,        //帧开始
    output wire [95:0] O_tdata,        //输出 96 位中值图
    output wire        O_tvalid,       //输出有效（延迟 2 拍）
    output wire        O_tlast,        //输出行结束（延迟 2 拍）
    output wire        O_tuser         //输出帧开始（延迟 2 拍）
);

    //------------ 提取 4 个灰度值（每像素取低 8 位，R=G=B=gray）------------
    wire [7:0] g0 = I_tdata[7:0];
    wire [7:0] g1 = I_tdata[31:24];
    wire [7:0] g2 = I_tdata[55:48];
    wire [7:0] g3 = I_tdata[79:72];
    wire [31:0] gray_4p = {g3, g2, g1, g0};   //4像素灰度，32位

    //------------ line buffer：级联 2 个 line_buffer_demosaic（BRAM），攒三行 ------------
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

    //------------ 对齐打拍（照搬 sobel_top：data0 补 2 拍、data1 补 1 拍、data2 不补）------------
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

    //------------ 行/组计数器（照搬 sobel_top，抗消隐）------------
    reg [13:0] h_cnt;
    reg [13:0] v_cnt;
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

    //------------ 3 值中值 function ------------
    function [7:0] med3;
        input [7:0] a, b, c;
        begin
            if (a < b) begin
                if (b < c)      med3 = b;   // a < b < c
                else if (a < c) med3 = c;   // a < c <= b
                else            med3 = a;   // c <= a < b
            end else begin
                if (a < c)      med3 = a;   // b <= a < c
                else if (b < c) med3 = c;   // b < c <= a
                else            med3 = b;   // c <= b <= a
            end
        end
    endfunction

    //------------ 9 值中值 function（3 列分别取中值，再取中值）------------
    // 输入：a b c = 上行，d e f = 中行，g h i = 下行（3×3 窗口）
    function [7:0] median9;
        input [7:0] a, b, c, d, e, f, g, h, i;
        reg [7:0] col0, col1, col2;
        begin
            col0 = med3(a, d, g);   //第 1 列
            col1 = med3(b, e, h);   //第 2 列
            col2 = med3(c, f, i);   //第 3 列
            median9 = med3(col0, col1, col2);
        end
    endfunction

    //------------ 4 像素并行中值（g3 右邻居复制 g3）------------
    wire [7:0] m0 = median9(r_prev_g3_up2, up2[7:0],   up2[15:8],
                            r_prev_g3_up,  up[7:0],    up[15:8],
                            r_prev_g3_cur, cur[7:0],   cur[15:8]);
    wire [7:0] m1 = median9(up2[7:0],  up2[15:8],  up2[23:16],
                            up[7:0],   up[15:8],   up[23:16],
                            cur[7:0],  cur[15:8],  cur[23:16]);
    wire [7:0] m2 = median9(up2[15:8], up2[23:16], up2[31:24],
                            up[15:8],  up[23:16],  up[31:24],
                            cur[15:8], cur[23:16], cur[31:24]);
    wire [7:0] m3 = median9(up2[23:16], up2[31:24], up2[31:24],
                            up[23:16],  up[31:24],  up[31:24],
                            cur[23:16], cur[31:24], cur[31:24]);

    //------------ 边界：前两行/最后一行、第一/最后一组输出 0（黑）------------
    // 不能透传中心值——line buffer 上电未初始化，前几行的「上一行」是垃圾值，
    // 透传会把垃圾值漏给 Sobel，Sobel 把「垃圾值 vs 真实灰度」的跳变当边缘 → 顶部白点
    wire in_border = !((v_cnt >= 14'd2) && (v_cnt <= 14'd719) &&
                       (h_cnt >= 14'd1) && (h_cnt <= 14'd318));

    wire [7:0] o0 = in_border ? 8'h00 : m0;
    wire [7:0] o1 = in_border ? 8'h00 : m1;
    wire [7:0] o2 = in_border ? 8'h00 : m2;
    wire [7:0] o3 = in_border ? 8'h00 : m3;

    //------------ 输出拼接（R=G=B=中值）------------
    assign O_tdata = {o3,o3,o3, o2,o2,o2, o1,o1,o1, o0,o0,o0};

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
