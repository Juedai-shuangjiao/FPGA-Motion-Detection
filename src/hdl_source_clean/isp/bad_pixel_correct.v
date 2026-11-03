//========================================================
// 模块：bad_pixel_correct —— 传感器坏点校正（BPC）
// 功能：3×3 邻域极值检测，亮点/暗点坏点用邻域同通道值替换（R/G/B 三通道独立校正）
// 说明：
//   · 根因：传感器缺陷像素（坏点簇）漏电流大，增益放大后呈白点
//     （位置固定、随增益变亮、手机摄像头下低增益仍可见 → 坐实传感器缺陷）
//   · 只在「中心是极值（比 8 邻域都大/都小且差超阈值）」时替换，
//     正常像素和边缘不受影响（不糊边缘，跟整帧中值滤波有本质区别）
//   · R/G/B 三通道各自走 2 行 line buffer（与灰度同构），独立校正，
//     输出 = 校正后 RGB（坏点通道被替换为邻域同通道值，颜色自然）
//   · 4 像素并行，跨组边界左邻居缓存上一组 g3、右邻居复制 g3（同 canny_top NMS 做法）
//   · 总延迟 3 拍（lb 内 data_d0 1 拍 + mem 读 1 拍 + 输出寄存 1 拍打断长路径），输出 = 上一行校正结果
//========================================================
module bad_pixel_correct (
    input  wire        I_clk,        //像素时钟
    input  wire        I_rst_n,      //复位，低有效
    input  wire [95:0] I_tdata,      //输入 96 位 RGB（4 像素，R[高]G[中]B[低]）
    input  wire        I_tvalid,     //数据有效
    input  wire        I_tlast,      //行结束
    input  wire        I_tuser,      //帧开始
    input  wire [7:0]  I_threshold,  //坏点阈值（中心与邻域最大/最小的差，大于此值判坏点）
    output wire [95:0] O_tdata,      //输出 96 位 RGB（校正后）
    output wire        O_tvalid,     //输出有效（延迟 2 拍）
    output wire        O_tlast,      //输出行结束（延迟 2 拍）
    output wire        O_tuser       //输出帧开始（延迟 2 拍）
);

    //------------ 拆 R/G/B 三通道（每通道 32 位 = 4 像素）------------
    wire [31:0] ch_r = {I_tdata[95:88], I_tdata[71:64], I_tdata[47:40], I_tdata[23:16]};
    wire [31:0] ch_g = {I_tdata[87:80], I_tdata[63:56], I_tdata[39:32], I_tdata[15:8]};
    wire [31:0] ch_b = {I_tdata[79:72], I_tdata[55:48], I_tdata[31:24], I_tdata[7:0]};

    //------------ R/G/B 三通道各走 2 行 line buffer（攒上一行、上上行）------------
    wire [32:0] d0_r = {I_tuser, ch_r};
    wire [32:0] d0_g = {I_tuser, ch_g};
    wire [32:0] d0_b = {I_tuser, ch_b};
    wire [32:0] d1_r, d2_r, d1_g, d2_g, d1_b, d2_b;
    wire        v1_r, v2_r, v1_g, v2_g, v1_b, v2_b;
    line_buffer_demosaic #(.IMG_HEIGHT(720), .IMG_WIDTH(1280)) u_lb_r1 (
        .I_clk(I_clk), .I_rst_n(I_rst_n), .I_tuser(d0_r[32] & I_tvalid),
        .I_valid(I_tvalid), .I_data(d0_r), .O_valid(v1_r), .O_data(d1_r)
    );
    line_buffer_demosaic #(.IMG_HEIGHT(720), .IMG_WIDTH(1280)) u_lb_r2 (
        .I_clk(I_clk), .I_rst_n(I_rst_n), .I_tuser(d1_r[32] & v1_r),
        .I_valid(v1_r), .I_data(d1_r), .O_valid(v2_r), .O_data(d2_r)
    );
    line_buffer_demosaic #(.IMG_HEIGHT(720), .IMG_WIDTH(1280)) u_lb_g1 (
        .I_clk(I_clk), .I_rst_n(I_rst_n), .I_tuser(d0_g[32] & I_tvalid),
        .I_valid(I_tvalid), .I_data(d0_g), .O_valid(v1_g), .O_data(d1_g)
    );
    line_buffer_demosaic #(.IMG_HEIGHT(720), .IMG_WIDTH(1280)) u_lb_g2 (
        .I_clk(I_clk), .I_rst_n(I_rst_n), .I_tuser(d1_g[32] & v1_g),
        .I_valid(v1_g), .I_data(d1_g), .O_valid(v2_g), .O_data(d2_g)
    );
    line_buffer_demosaic #(.IMG_HEIGHT(720), .IMG_WIDTH(1280)) u_lb_b1 (
        .I_clk(I_clk), .I_rst_n(I_rst_n), .I_tuser(d0_b[32] & I_tvalid),
        .I_valid(I_tvalid), .I_data(d0_b), .O_valid(v1_b), .O_data(d1_b)
    );
    line_buffer_demosaic #(.IMG_HEIGHT(720), .IMG_WIDTH(1280)) u_lb_b2 (
        .I_clk(I_clk), .I_rst_n(I_rst_n), .I_tuser(d1_b[32] & v1_b),
        .I_valid(v1_b), .I_data(d1_b), .O_valid(v2_b), .O_data(d2_b)
    );

    //------------ 对齐打拍（cur = 输入打 2 拍，与 lb 输出 d1 同拍）------------
    reg [31:0] cur_r_d1, cur_r;
    reg [31:0] cur_g_d1, cur_g;
    reg [31:0] cur_b_d1, cur_b;
    reg        valid_d0, valid_d1;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            cur_r_d1 <= 32'd0; cur_r <= 32'd0;
            cur_g_d1 <= 32'd0; cur_g <= 32'd0;
            cur_b_d1 <= 32'd0; cur_b <= 32'd0;
            valid_d0  <= 1'b0;  valid_d1  <= 1'b0;
        end else begin
            valid_d0  <= I_tvalid; valid_d1 <= valid_d0;
            cur_r_d1 <= ch_r; cur_r <= cur_r_d1;
            cur_g_d1 <= ch_g; cur_g <= cur_g_d1;
            cur_b_d1 <= ch_b; cur_b <= cur_b_d1;
        end
    end
    wire [31:0] up_r = d1_r[31:0];   //上一行 R
    wire [31:0] up_g = d1_g[31:0];
    wire [31:0] up_b = d1_b[31:0];
    wire [31:0] up2_r = d2_r[31:0];  //上上行 R
    wire [31:0] up2_g = d2_g[31:0];
    wire [31:0] up2_b = d2_b[31:0];

    //------------ 行/组计数器（边界屏蔽用）------------
    reg [13:0] h_cnt, v_cnt;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n || I_tuser) begin
            h_cnt <= 14'd0; v_cnt <= 14'd0;
        end else begin
            h_cnt <= valid_d1 ? ((h_cnt == 14'd319) ? 14'd0 : h_cnt + 1'b1) : h_cnt;
            v_cnt <= (valid_d1 && (h_cnt == 14'd319)) ? ((v_cnt == 14'd719) ? 14'd0 : v_cnt + 1'b1) : v_cnt;
        end
    end
    // h_cnt/v_cnt 打 1 拍（对齐 lb 输出：h_cnt 内容 = 输入打 1 拍的组号，再打 1 拍 = 打 2 拍）
    reg [13:0] h_cnt_d1;
    reg [13:0] v_cnt_d1;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            h_cnt_d1 <= 14'd0;
            v_cnt_d1 <= 14'd0;
        end else begin
            h_cnt_d1 <= h_cnt;
            v_cnt_d1 <= v_cnt;
        end
    end
    // 边界：组 1~318（首末组的左右邻居跨组不可靠）、行 1~717（行 0 的邻域含 lb 首行垃圾）
    wire bpc_valid = (v_cnt_d1 >= 14'd1) && (v_cnt_d1 <= 14'd717) &&
                     (h_cnt_d1 >= 14'd1) && (h_cnt_d1 <= 14'd318);

    //------------ 极值检测 function（中心 vs 8 邻域同通道）------------
    function [7:0] max2;
        input [7:0] a, b;
        begin max2 = (a > b) ? a : b; end
    endfunction
    function [7:0] min2;
        input [7:0] a, b;
        begin min2 = (a < b) ? a : b; end
    endfunction
    // 8 邻域最大值
    function [7:0] nb_max;
        input [7:0] a,b,c,d,e,f,g,h;
        begin
            nb_max = max2(max2(max2(a,b),max2(c,d)),max2(max2(e,f),max2(g,h)));
        end
    endfunction
    // 8 邻域最小值
    function [7:0] nb_min;
        input [7:0] a,b,c,d,e,f,g,h;
        begin
            nb_min = min2(min2(min2(a,b),min2(c,d)),min2(min2(e,f),min2(g,h)));
        end
    endfunction
    // 坏点校正：返回校正后通道值（亮点→邻域最大，暗点→邻域最小，正常→原中心）
    function [7:0] bpc_fix;
        input [7:0] cen, thr;
        input [7:0] a,b,c,d,e,f,g,h;
        reg [7:0] mx, mn;
        begin
            mx = nb_max(a,b,c,d,e,f,g,h);
            mn = nb_min(a,b,c,d,e,f,g,h);
            if ({1'b0, cen} > ({1'b0, mx} + {1'b0, thr}))       bpc_fix = mx;  //亮点坏点（9 位防溢出）
            else if (({1'b0, cen} + {1'b0, thr}) < {1'b0, mn})  bpc_fix = mn;  //暗点坏点
            else                                                 bpc_fix = cen; //正常
        end
    endfunction

    //------------ 每通道 4 像素并行校正（中心 = up 行，邻域 = cur/up/up2 三行）------------
    // 左邻居 = 上一组 g3（缓存），右邻居 = 组内下一像素（g3 复制）
    reg [7:0] prev_r_cur, prev_r_up, prev_r_up2;
    reg [7:0] prev_g_cur, prev_g_up, prev_g_up2;
    reg [7:0] prev_b_cur, prev_b_up, prev_b_up2;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            prev_r_cur <= 8'd0; prev_r_up <= 8'd0; prev_r_up2 <= 8'd0;
            prev_g_cur <= 8'd0; prev_g_up <= 8'd0; prev_g_up2 <= 8'd0;
            prev_b_cur <= 8'd0; prev_b_up <= 8'd0; prev_b_up2 <= 8'd0;
        end else begin
            prev_r_cur <= cur_r[31:24]; prev_r_up <= up_r[31:24]; prev_r_up2 <= up2_r[31:24];
            prev_g_cur <= cur_g[31:24]; prev_g_up <= up_g[31:24]; prev_g_up2 <= up2_g[31:24];
            prev_b_cur <= cur_b[31:24]; prev_b_up <= up_b[31:24]; prev_b_up2 <= up2_b[31:24];
        end
    end

    // R 通道 4 像素
    wire [7:0] fr0 = bpc_fix(up_r[7:0],  I_threshold, prev_r_cur, cur_r[7:0],  cur_r[15:8],  prev_r_up,  up_r[15:8],  prev_r_up2, up2_r[7:0],  up2_r[15:8]);
    wire [7:0] fr1 = bpc_fix(up_r[15:8], I_threshold, cur_r[7:0],  cur_r[15:8], cur_r[23:16], up_r[7:0],   up_r[23:16], up2_r[7:0],  up2_r[15:8], up2_r[23:16]);
    wire [7:0] fr2 = bpc_fix(up_r[23:16],I_threshold, cur_r[15:8], cur_r[23:16],cur_r[31:24], up_r[15:8],  up_r[31:24], up2_r[15:8], up2_r[23:16],up2_r[31:24]);
    wire [7:0] fr3 = bpc_fix(up_r[31:24],I_threshold, cur_r[23:16],cur_r[31:24],cur_r[31:24], up_r[23:16], up_r[31:24], up2_r[23:16],up2_r[31:24],up2_r[31:24]);
    // G 通道 4 像素
    wire [7:0] fg0 = bpc_fix(up_g[7:0],  I_threshold, prev_g_cur, cur_g[7:0],  cur_g[15:8],  prev_g_up,  up_g[15:8],  prev_g_up2, up2_g[7:0],  up2_g[15:8]);
    wire [7:0] fg1 = bpc_fix(up_g[15:8], I_threshold, cur_g[7:0],  cur_g[15:8], cur_g[23:16], up_g[7:0],   up_g[23:16], up2_g[7:0],  up2_g[15:8], up2_g[23:16]);
    wire [7:0] fg2 = bpc_fix(up_g[23:16],I_threshold, cur_g[15:8], cur_g[23:16],cur_g[31:24], up_g[15:8],  up_g[31:24], up2_g[15:8], up2_g[23:16],up2_g[31:24]);
    wire [7:0] fg3 = bpc_fix(up_g[31:24],I_threshold, cur_g[23:16],cur_g[31:24],cur_g[31:24], up_g[23:16], up_g[31:24], up2_g[23:16],up2_g[31:24],up2_g[31:24]);
    // B 通道 4 像素
    wire [7:0] fb0 = bpc_fix(up_b[7:0],  I_threshold, prev_b_cur, cur_b[7:0],  cur_b[15:8],  prev_b_up,  up_b[15:8],  prev_b_up2, up2_b[7:0],  up2_b[15:8]);
    wire [7:0] fb1 = bpc_fix(up_b[15:8], I_threshold, cur_b[7:0],  cur_b[15:8], cur_b[23:16], up_b[7:0],   up_b[23:16], up2_b[7:0],  up2_b[15:8], up2_b[23:16]);
    wire [7:0] fb2 = bpc_fix(up_b[23:16],I_threshold, cur_b[15:8], cur_b[23:16],cur_b[31:24], up_b[15:8],  up_b[31:24], up2_b[15:8], up2_b[23:16],up2_b[31:24]);
    wire [7:0] fb3 = bpc_fix(up_b[31:24],I_threshold, cur_b[23:16],cur_b[31:24],cur_b[31:24], up_b[23:16], up_b[31:24], up2_b[23:16],up2_b[31:24],up2_b[31:24]);

    //------------ 输出（边界外原样）------------
    wire [23:0] o0 = bpc_valid ? {fr0, fg0, fb0} : {up_r[7:0],  up_g[7:0],  up_b[7:0]};
    wire [23:0] o1 = bpc_valid ? {fr1, fg1, fb1} : {up_r[15:8], up_g[15:8], up_b[15:8]};
    wire [23:0] o2 = bpc_valid ? {fr2, fg2, fb2} : {up_r[23:16],up_g[23:16],up_b[23:16]};
    wire [23:0] o3 = bpc_valid ? {fr3, fg3, fb3} : {up_r[31:24],up_g[31:24],up_b[31:24]};

    //------------ 输出寄存 1 拍（打断 BRAM→组合→下游的长路径，修时序贴边）------------
    // 最差路径：lb BRAM → bpc_fix 8 邻域比较树 → gray_convert → brightness_stat 累加，Slack 仅 100ps
    // 输出打拍后：BRAM→组合→本寄存器 一段、本寄存器→下游 一段，各段裕量充足
    reg tlast_d1,  tlast_d2;
    reg tuser_d1,  tuser_d2;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            tlast_d1  <= 1'b0; tlast_d2  <= 1'b0;
            tuser_d1  <= 1'b0; tuser_d2  <= 1'b0;
        end else begin
            tlast_d1  <= I_tlast; tlast_d2  <= tlast_d1;
            tuser_d1  <= I_tuser; tuser_d2  <= tuser_d1;
        end
    end
    reg [95:0] o_data_reg;
    reg        o_valid_reg, o_last_reg, o_user_reg;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            o_data_reg <= 96'd0;
            o_valid_reg <= 1'b0; o_last_reg <= 1'b0; o_user_reg <= 1'b0;
        end else begin
            o_data_reg <= {o3, o2, o1, o0};
            o_valid_reg <= v1_r;
            o_last_reg  <= tlast_d2;
            o_user_reg  <= tuser_d2;
        end
    end
    assign O_tdata = o_data_reg;
    assign O_tvalid = o_valid_reg;
    assign O_tlast  = o_last_reg;
    assign O_tuser  = o_user_reg;

endmodule
