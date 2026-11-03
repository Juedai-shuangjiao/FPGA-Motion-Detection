//========================================================
// 模块：canny_top —— Canny 边缘检测（Sobel 升级版）
// 功能：输入 96 位灰度（4像素），输出 96 位边缘图（黑底白线，1像素细边缘）
// 实现：Sobel 算梯度 → 方向量化（4方向）→ 非极大值抑制(NMS) → 双阈值
// 数据流：
//   3行灰度 line buffer → Sobel 卷积算 Gx/Gy/幅值/方向（4像素并行）
//   → 幅值降位宽8bit存 line buffer（攒3行）+ 方向打2拍 → NMS（沿梯度方向比较2邻居）
//   → 双阈值（高阈值=边缘，低阈值滤弱边缘）
// 说明：
//   · Canny = Sobel + NMS + 双阈值，NMS 把 Sobel 的「粗边缘」细化成「1像素细边缘」
//   · 方向量化：|Gy|>2|Gx|→垂直、|Gx|>2|Gy|→水平、否则 Gx/Gy 同号判 45°/135°
//     （2 倍近似 tan67.5°≈2.414，硬件免 atan2/除法）
//   · 幅值 line buffer 只存 8bit（mag>>3，NMS 只比较大小、8bit 精度够），4像素=32bit
//     正好塞进 line_buffer_demosaic 的 32bit（11bit 幅值 4像素=44bit 塞不下，故降位宽）
//   · 4 像素并行，跨组边界 g3 右邻居复制 g3、g0 左邻居缓存上一组 g3（同 sobel_top）
//   · 双阈值：高阈值 = I_threshold>>3（8bit），低阈值 = 一半，弱边缘丢弃（不做滞后）
//   · 总延迟 10 拍（灰度lb2 + 平滑lb2 + 二次平滑lb2 + mag8lb2 + 强边缘2），O_* 打 10 拍
//   · 2026-11-03 第二级高斯（两级 3×3 级联≈5×5）：高增益下噪声上沿 128 逼近边缘 135，
//     有效阈值窗口仅 16；第二级高斯压噪 ~1.7 倍拓宽窗口
//========================================================
module canny_top (
    input  wire        I_clk,          //像素时钟
    input  wire        I_rst_n,        //复位，低有效
    input  wire [95:0] I_tdata,        //输入 96 位灰度（4像素，R=G=B=gray）
    input  wire        I_tvalid,       //数据有效
    input  wire        I_tlast,        //行结束
    input  wire        I_tuser,        //帧开始
    input  wire [10:0] I_threshold,    //高阈值（0~2040，手动可调，KEY2/KEY3 调节）
    output wire [95:0] O_tdata,        //输出 96 位边缘图
    output wire        O_tvalid,       //输出有效（延迟 4 拍）
    output wire        O_tlast,        //输出行结束（延迟 4 拍）
    output wire        O_tuser         //输出帧开始（延迟 4 拍）
);

    // 高/低阈值（8bit，对齐 mag8）——自适应统计见下方 R_high_8/R_low_8

    //=========== 第一级：Sobel 卷积 + 方向量化 ============

    //------------ 提取 4 个灰度值 ------------
    wire [7:0] g0 = I_tdata[7:0];
    wire [7:0] g1 = I_tdata[31:24];
    wire [7:0] g2 = I_tdata[55:48];
    wire [7:0] g3 = I_tdata[79:72];
    wire [31:0] gray_4p = {g3, g2, g1, g0};

    //------------ 3 行灰度 line buffer ------------
    wire [32:0] data0 = {I_tuser, gray_4p};
    wire        valid0 = I_tvalid;
    wire [32:0] data1, data2;
    wire        valid1, valid2;
    line_buffer_demosaic #(.IMG_HEIGHT(720), .IMG_WIDTH(1280)) u_lb1 (
        .I_clk(I_clk), .I_rst_n(I_rst_n), .I_tuser(data0[32] & valid0),
        .I_valid(valid0), .I_data(data0), .O_valid(valid1), .O_data(data1)
    );
    line_buffer_demosaic #(.IMG_HEIGHT(720), .IMG_WIDTH(1280)) u_lb2 (
        .I_clk(I_clk), .I_rst_n(I_rst_n), .I_tuser(data1[32] & valid1),
        .I_valid(valid1), .I_data(data1), .O_valid(valid2), .O_data(data2)
    );

    //------------ 对齐打拍 ------------
    reg [32:0] data_d0_d, data_d0, data_d1;
    reg        valid_d0, valid_d1;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            data_d0_d <= 33'd0; data_d0 <= 33'd0; data_d1 <= 33'd0;
            valid_d0  <= 1'b0;  valid_d1  <= 1'b0;
        end else begin
            valid_d0  <= valid0; valid_d1 <= valid_d0;
            data_d0_d <= data0;  data_d0   <= data_d0_d; data_d1 <= data1;
        end
    end
    wire [31:0] cur = data_d0[31:0];
    wire [31:0] up  = data_d1[31:0];
    wire [31:0] up2 = data2[31:0];

    //------------ 行/组计数器 ------------
    reg [13:0] h_cnt, v_cnt;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n || I_tuser) begin
            h_cnt <= 14'd0; v_cnt <= 14'd0;
        end else begin
            h_cnt <= valid_d1 ? ((h_cnt == 14'd319) ? 14'd0 : h_cnt + 1'b1) : h_cnt;
            v_cnt <= (valid_d1 && (h_cnt == 14'd319)) ? ((v_cnt == 14'd719) ? 14'd0 : v_cnt + 1'b1) : v_cnt;
        end
    end

    //------------ h_cnt/v_cnt 打 8 拍（对齐滞后输出，供边界屏蔽精确对准输出组号/行号）------------
    // 根因：输出比第一级 Sobel 延迟 8 拍（灰度 lb 2 + 平滑 lb 2 + 二次平滑 lb 2 + mag8 lb 2 + 强边缘 lb 2），
    //       直接用第一级 h_cnt/v_cnt 做边界屏蔽会「错位 8 组/8 行」
    reg [13:0] h_cnt_d1, h_cnt_d2, h_cnt_d3, h_cnt_d4, h_cnt_d5, h_cnt_d6, h_cnt_d7, h_cnt_d8;
    reg [13:0] v_cnt_d1, v_cnt_d2, v_cnt_d3, v_cnt_d4, v_cnt_d5, v_cnt_d6, v_cnt_d7, v_cnt_d8;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            h_cnt_d1 <= 14'd0; h_cnt_d2 <= 14'd0; h_cnt_d3 <= 14'd0; h_cnt_d4 <= 14'd0;
            h_cnt_d5 <= 14'd0; h_cnt_d6 <= 14'd0; h_cnt_d7 <= 14'd0; h_cnt_d8 <= 14'd0;
            v_cnt_d1 <= 14'd0; v_cnt_d2 <= 14'd0; v_cnt_d3 <= 14'd0; v_cnt_d4 <= 14'd0;
            v_cnt_d5 <= 14'd0; v_cnt_d6 <= 14'd0; v_cnt_d7 <= 14'd0; v_cnt_d8 <= 14'd0;
        end else begin
            h_cnt_d1 <= h_cnt; h_cnt_d2 <= h_cnt_d1; h_cnt_d3 <= h_cnt_d2; h_cnt_d4 <= h_cnt_d3;
            h_cnt_d5 <= h_cnt_d4; h_cnt_d6 <= h_cnt_d5; h_cnt_d7 <= h_cnt_d6; h_cnt_d8 <= h_cnt_d7;
            v_cnt_d1 <= v_cnt; v_cnt_d2 <= v_cnt_d1; v_cnt_d3 <= v_cnt_d2; v_cnt_d4 <= v_cnt_d3;
            v_cnt_d5 <= v_cnt_d4; v_cnt_d6 <= v_cnt_d5; v_cnt_d7 <= v_cnt_d6; v_cnt_d8 <= v_cnt_d7;
        end
    end

    //------------ 缓存「上一组 g3」作为左邻居 ------------
    reg [7:0] r_prev_g3_cur, r_prev_g3_up, r_prev_g3_up2;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            r_prev_g3_cur <= 8'd0; r_prev_g3_up <= 8'd0; r_prev_g3_up2 <= 8'd0;
        end else begin
            r_prev_g3_cur <= cur[31:24]; r_prev_g3_up <= up[31:24]; r_prev_g3_up2 <= up2[31:24];
        end
    end

    //------------ 边界有效（用打 8 拍的 h_cnt_d8/v_cnt_d8，对齐输出精确屏蔽边界）------------
    // v_cnt_d8>=10（灰度2 + 平滑2 + 二次平滑2 + mag8 2 + 强边缘 2 行垃圾值）、
    // h_cnt_d8 5~317（2026-11-03 左 3→5 组：高斯+高斯+Sobel 三层左邻居错位扩散到第 5 组附近，
    //   左边界 4 列断续虚线即 3 组屏蔽不足；右 1→2 组：右邻居复制扩散）
    wire cur_valid = (v_cnt_d8 >= 14'd10) && (v_cnt_d8 <= 14'd709) &&
                     (h_cnt_d8 >= 14'd5) && (h_cnt_d8 <= 14'd317);

    //=========== 高斯滤波（3×3 高斯核去噪，标准 Canny 第一步）===========
    // 高斯卷积 function：核 [1 2 1; 2 4 2; 1 2 1]，>>4（除以16）
    function [7:0] gauss3x3;
        input [7:0] a, b, c, d, e, f, g, h, i;
        reg [11:0] sum;
        begin
            sum = {4'd0,a} + {3'd0,b,1'b0} + {4'd0,c}
                + {3'd0,d,1'b0} + {2'd0,e,2'b0} + {3'd0,f,1'b0}
                + {4'd0,g} + {3'd0,h,1'b0} + {4'd0,i};
            gauss3x3 = sum[11:4];
        end
    endfunction

    // 4 像素并行高斯卷积（复用灰度 cur/up/up2 + r_prev_g3 左邻居）
    wire [7:0] sm0 = gauss3x3(r_prev_g3_up2, up2[7:0],  up2[15:8], r_prev_g3_up,  up[7:0],  up[15:8], r_prev_g3_cur, cur[7:0],  cur[15:8]);
    wire [7:0] sm1 = gauss3x3(up2[7:0],  up2[15:8], up2[23:16], up[7:0],  up[15:8], up[23:16], cur[7:0],  cur[15:8], cur[23:16]);
    wire [7:0] sm2 = gauss3x3(up2[15:8], up2[23:16], up2[31:24], up[15:8], up[23:16], up[31:24], cur[15:8], cur[23:16], cur[31:24]);
    wire [7:0] sm3 = gauss3x3(up2[23:16], up2[31:24], up2[31:24], up[23:16], up[31:24], up[31:24], cur[23:16], cur[31:24], cur[31:24]);
    wire [31:0] sm_4p = {sm3, sm2, sm1, sm0};

    // tuser 打 4 拍（对齐二次平滑 lb 输入域 valid_d3，供 ss lb 和 mag8 lb 复位地址）
    reg mtuser_d1, mtuser_d2, mtuser_d3, mtuser_d4;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin mtuser_d1 <= 1'b0; mtuser_d2 <= 1'b0; mtuser_d3 <= 1'b0; mtuser_d4 <= 1'b0; end
        else begin mtuser_d1 <= I_tuser; mtuser_d2 <= mtuser_d1; mtuser_d3 <= mtuser_d2; mtuser_d4 <= mtuser_d3; end
    end
    // valid 打 3 拍（valid_d1 对齐 sm_4p，valid_d3 对齐 ss_4p）
    reg valid_d2, valid_d3;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin valid_d2 <= 1'b0; valid_d3 <= 1'b0; end
        else begin valid_d2 <= valid_d1; valid_d3 <= valid_d2; end
    end

    // 平滑灰度 line buffer（BRAM，line_buffer_demosaic，同步读保证读旧值，避免 reg 数组 write-first 导致上上行错位、Gy 偏小）
    wire [32:0] sm_data0 = {mtuser_d2, sm_4p};
    wire [32:0] sm_data1, sm_data2;
    wire        sm_valid1, sm_valid2;
    line_buffer_demosaic #(.IMG_HEIGHT(720), .IMG_WIDTH(1280)) u_smlb1 (
        .I_clk(I_clk), .I_rst_n(I_rst_n), .I_tuser(sm_data0[32] & valid_d1),
        .I_valid(valid_d1), .I_data(sm_data0), .O_valid(sm_valid1), .O_data(sm_data1)
    );
    line_buffer_demosaic #(.IMG_HEIGHT(720), .IMG_WIDTH(1280)) u_smlb2 (
        .I_clk(I_clk), .I_rst_n(I_rst_n), .I_tuser(sm_data1[32] & sm_valid1),
        .I_valid(sm_valid1), .I_data(sm_data1), .O_valid(sm_valid2), .O_data(sm_data2)
    );
    // 对齐打拍（3 行平滑灰度）
    reg [31:0] sm_d0_d, sm_d0, sm_d1;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin sm_d0_d <= 32'd0; sm_d0 <= 32'd0; sm_d1 <= 32'd0; end
        else begin sm_d0_d <= sm_4p; sm_d0 <= sm_d0_d; sm_d1 <= sm_data1[31:0]; end
    end
    wire [31:0] sm_cur = sm_d0;
    wire [31:0] sm_up  = sm_d1;
    wire [31:0] sm_up2 = sm_data2[31:0];

    //=========== 第二级高斯滤波（2026-11-03 新增：两级 3×3 级联 ≈ 5×5 高斯核，再压噪声 ~1.7 倍）===========
    // 根因：现场 3990/121 高增益下噪声 mag8 上沿 ~128、边缘幅值 ~135~150，有效阈值窗口仅 ~16，
    //       阈值往上全黑、往下全白。第二级高斯把噪声再压 ~1.7 倍（上沿 ~75），窗口拓宽 ~70。
    // 左邻居缓存（上一组 g3 的平滑值，sm_cur 域、未打 1 拍）
    reg [7:0] g2_r_prev_cur, g2_r_prev_up, g2_r_prev_up2;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            g2_r_prev_cur <= 8'd0; g2_r_prev_up <= 8'd0; g2_r_prev_up2 <= 8'd0;
        end else begin
            g2_r_prev_cur <= sm_cur[31:24]; g2_r_prev_up <= sm_up[31:24]; g2_r_prev_up2 <= sm_up2[31:24];
        end
    end
    // 4 像素并行第二级高斯卷积（复用 gauss3x3 function，右邻居复制 g3 同高斯1）
    wire [7:0] ss0 = gauss3x3(g2_r_prev_up2, sm_up2[7:0],  sm_up2[15:8], g2_r_prev_up,  sm_up[7:0],  sm_up[15:8], g2_r_prev_cur, sm_cur[7:0],  sm_cur[15:8]);
    wire [7:0] ss1 = gauss3x3(sm_up2[7:0],  sm_up2[15:8], sm_up2[23:16], sm_up[7:0],  sm_up[15:8], sm_up[23:16], sm_cur[7:0],  sm_cur[15:8], sm_cur[23:16]);
    wire [7:0] ss2 = gauss3x3(sm_up2[15:8], sm_up2[23:16], sm_up2[31:24], sm_up[15:8], sm_up[23:16], sm_up[31:24], sm_cur[15:8], sm_cur[23:16], sm_cur[31:24]);
    wire [7:0] ss3 = gauss3x3(sm_up2[23:16], sm_up2[31:24], sm_up2[31:24], sm_up[23:16], sm_up[31:24], sm_up[31:24], sm_cur[23:16], sm_cur[31:24], sm_cur[31:24]);
    wire [31:0] ss_4p = {ss3, ss2, ss1, ss0};

    // 二次平滑 line buffer（BRAM，与平滑 lb 同构；valid_d3/mtuser_d4 对齐 ss_4p 域）
    wire [32:0] ss_data0 = {mtuser_d4, ss_4p};
    wire [32:0] ss_data1, ss_data2;
    wire        ss_valid1, ss_valid2;
    line_buffer_demosaic #(.IMG_HEIGHT(720), .IMG_WIDTH(1280)) u_sslb1 (
        .I_clk(I_clk), .I_rst_n(I_rst_n), .I_tuser(ss_data0[32] & valid_d3),
        .I_valid(valid_d3), .I_data(ss_data0), .O_valid(ss_valid1), .O_data(ss_data1)
    );
    line_buffer_demosaic #(.IMG_HEIGHT(720), .IMG_WIDTH(1280)) u_sslb2 (
        .I_clk(I_clk), .I_rst_n(I_rst_n), .I_tuser(ss_data1[32] & ss_valid1),
        .I_valid(ss_valid1), .I_data(ss_data1), .O_valid(ss_valid2), .O_data(ss_data2)
    );
    // 对齐打拍（3 行二次平滑）
    reg [31:0] ss_d0_d, ss_d0, ss_d1;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin ss_d0_d <= 32'd0; ss_d0 <= 32'd0; ss_d1 <= 32'd0; end
        else begin ss_d0_d <= ss_4p; ss_d0 <= ss_d0_d; ss_d1 <= ss_data1[31:0]; end
    end
    wire [31:0] ss_cur = ss_d0;
    wire [31:0] ss_up  = ss_d1;
    wire [31:0] ss_up2 = ss_data2[31:0];

    // 二次平滑打 1 拍（延迟 1 组，让 g3 的右邻居 = 下一组的真实像素 0，消除「右邻居复制」导致的竖线右边缘断续）
    reg [31:0] ss_cur_d1, ss_up_d1, ss_up2_d1;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            ss_cur_d1 <= 32'd0; ss_up_d1 <= 32'd0; ss_up2_d1 <= 32'd0;
        end else begin
            ss_cur_d1 <= ss_cur; ss_up_d1 <= ss_up; ss_up2_d1 <= ss_up2;
        end
    end

    // 二次平滑左邻居缓存（g0 的左邻居 = 上一组 g3，缓存打 1 拍后的 ss_cur_d1 的 g3）
    reg [7:0] ss_r_prev_cur, ss_r_prev_up, ss_r_prev_up2;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            ss_r_prev_cur <= 8'd0; ss_r_prev_up <= 8'd0; ss_r_prev_up2 <= 8'd0;
        end else begin
            ss_r_prev_cur <= ss_cur_d1[31:24]; ss_r_prev_up <= ss_up_d1[31:24]; ss_r_prev_up2 <= ss_up2_d1[31:24];
        end
    end

    //------------ 8 方向 Scharr 卷积 function（2026-11-02 升级：2 方向 → 8 方向）------------
    // 核 [3 10 3] 旋转 45°/135° 得对角核；幅值取 8 方向最大响应（论文 FCIS2023：
    // 8 方向比 2 方向合成边缘细节丰富度/连续性显著提升），方向 = argmax
    // 返回 [14:0] = {dir[1:0], mag[12:0]}
    //   方向编码（沿用 NMS）：0=水平梯度 1=45° 2=垂直梯度 3=135°
    //   G0 核 [-3,-10,-3;0,0,0;3,10,3]（水平梯度）| G90 核 [-3,0,3;-10,0,10;-3,0,3]
    //   G45 核 [0,3,10;-3,0,3;-10,-3,0]  | G135 核 [10,3,0;3,0,-3;0,-3,-10]
    function [14:0] sobel_mag_dir;
        input [7:0] a, b, c, d, e, f, g, h, i;
        reg  [11:0] p0, n0, p90, n90, p45, n45, p135, n135;
        reg  [12:0] g0_s, g90_s, g45_s, g135_s;
        reg  [12:0] a0, a90, a45, a135;
        reg  [12:0] mx; reg [1:0] dr;
        begin
            // 3x = 2x+x；10x = 8x+2x（移位加法，免乘法器）
            p0   = ({3'd0, c, 1'b0} + {4'd0, c}) + ({1'd0, f, 3'b0} + {3'd0, f, 1'b0}) + ({3'd0, i, 1'b0} + {4'd0, i});
            n0   = ({3'd0, a, 1'b0} + {4'd0, a}) + ({1'd0, d, 3'b0} + {3'd0, d, 1'b0}) + ({3'd0, g, 1'b0} + {4'd0, g});
            p90  = ({3'd0, g, 1'b0} + {4'd0, g}) + ({1'd0, h, 3'b0} + {3'd0, h, 1'b0}) + ({3'd0, i, 1'b0} + {4'd0, i});
            n90  = ({3'd0, a, 1'b0} + {4'd0, a}) + ({1'd0, b, 3'b0} + {3'd0, b, 1'b0}) + ({3'd0, c, 1'b0} + {4'd0, c});
            // 对角算子用 Sobel 核 [0,1,2;-1,0,1;-2,-1,0]/[2,1,0;1,0,-1;0,-1,-2]（FCIS2023 论文同款，资源省于 Scharr 对角）
            p45  = {4'd0, b} + ({3'd0, c, 1'b0}) + ({3'd0, f, 1'b0});
            n45  = {4'd0, d} + ({3'd0, g, 1'b0}) + {4'd0, h};
            p135 = ({3'd0, a, 1'b0}) + {4'd0, b} + {4'd0, d};
            n135 = ({3'd0, f, 1'b0}) + {4'd0, h} + ({3'd0, i, 1'b0});
            g0_s  = {1'b0, p0}   - {1'b0, n0};
            g90_s = {1'b0, p90}  - {1'b0, n90};
            g45_s = {1'b0, p45}  - {1'b0, n45};
            g135_s= {1'b0, p135} - {1'b0, n135};
            // 2026-11-03 取反改 XOR 掩码（x ^ 12'hFFF）：iverilog 12 对 function 内
            //   ~x[11:0] 有位宽上下文 bug（在 13bit 赋值上下文被先零扩展再取反，
            //   4092→4099→+1→4100，仿真全白）；TD 综合行为正确。XOR 掩码两工具语义一致。
            a0   = g0_s[12]   ? ((g0_s[11:0]   ^ 12'hFFF) + 12'd1) : g0_s[11:0];
            a90  = g90_s[12]  ? ((g90_s[11:0]  ^ 12'hFFF) + 12'd1) : g90_s[11:0];
            a45  = g45_s[12]  ? ((g45_s[11:0]  ^ 12'hFFF) + 12'd1) : g45_s[11:0];
            a135 = g135_s[12] ? ((g135_s[11:0] ^ 12'hFFF) + 12'd1) : g135_s[11:0];
            mx = a0; dr = 2'd0;
            if(a90  > mx) begin mx = a90;  dr = 2'd2; end
            if(a45  > mx) begin mx = a45;  dr = 2'd1; end
            if(a135 > mx) begin mx = a135; dr = 2'd3; end
            sobel_mag_dir = {dr, mx};
        end
    endfunction

    //------------ 4 像素并行 Sobel：幅值（11bit）+ 方向（2bit）------------
    wire [14:0] md0 = sobel_mag_dir(ss_r_prev_up2, ss_up2_d1[7:0],  ss_up2_d1[15:8], ss_r_prev_up,  ss_up_d1[7:0],  ss_up_d1[15:8], ss_r_prev_cur, ss_cur_d1[7:0],  ss_cur_d1[15:8]);
    wire [14:0] md1 = sobel_mag_dir(ss_up2_d1[7:0],  ss_up2_d1[15:8], ss_up2_d1[23:16], ss_up_d1[7:0],  ss_up_d1[15:8], ss_up_d1[23:16], ss_cur_d1[7:0],  ss_cur_d1[15:8], ss_cur_d1[23:16]);
    wire [14:0] md2 = sobel_mag_dir(ss_up2_d1[15:8], ss_up2_d1[23:16], ss_up2_d1[31:24], ss_up_d1[15:8], ss_up_d1[23:16], ss_up_d1[31:24], ss_cur_d1[15:8], ss_cur_d1[23:16], ss_cur_d1[31:24]);
    wire [14:0] md3 = sobel_mag_dir(ss_up2_d1[23:16], ss_up2_d1[31:24], ss_up2[7:0],     ss_up_d1[23:16], ss_up_d1[31:24], ss_up[7:0],     ss_cur_d1[23:16], ss_cur_d1[31:24], ss_cur[7:0]);
    wire [12:0] m0 = md0[12:0];
    wire [12:0] m1 = md1[12:0];
    wire [12:0] m2 = md2[12:0];
    wire [12:0] m3 = md3[12:0];
    wire [1:0] d0 = md0[14:13];
    wire [1:0] d1 = md1[14:13];
    wire [1:0] d2 = md2[14:13];
    wire [1:0] d3 = md3[14:13];

    // 幅值降位宽 8bit（Scharr 幅值 4 倍于 Sobel，>>5 对齐 Sobel 的 >>3 量纲，NMS 只比较大小、8bit 精度够）
    wire [7:0] m8_0 = m0[12:5];
    wire [7:0] m8_1 = m1[12:5];
    wire [7:0] m8_2 = m2[12:5];
    wire [7:0] m8_3 = m3[12:5];
    wire [31:0] mag8_4p = {m8_3, m8_2, m8_1, m8_0};
    //=========== 阈值（2026-11-02 手动回归：自适应两版均全白，恢复手动可调）============
    // 高阈值 = I_threshold[10:3]（11bit 域 0~2040 → mag8 域 0~255）
    // 低阈值 = 高/4（弱边缘由滞后连接决定，减少断链）
    wire [7:0] high_thr = I_threshold[10:3];
    wire [7:0] low_thr  = {2'b0, I_threshold[10:5]};

    //=========== 第二级：幅值 line buffer（攒 3 行 mag8）+ 方向打拍 ===========
    // （mtuser_d1/d2 已在平滑 lb 前声明，这里复用）

    wire [32:0] mdata0 = {mtuser_d4, mag8_4p};
    wire [32:0] mdata1, mdata2;
    wire        mvalid1, mvalid2;
    line_buffer_demosaic #(.IMG_HEIGHT(720), .IMG_WIDTH(1280)) u_mlb1 (
        .I_clk(I_clk), .I_rst_n(I_rst_n), .I_tuser(mdata0[32] & valid_d3),
        .I_valid(valid_d3), .I_data(mdata0), .O_valid(mvalid1), .O_data(mdata1)
    );
    line_buffer_demosaic #(.IMG_HEIGHT(720), .IMG_WIDTH(1280)) u_mlb2 (
        .I_clk(I_clk), .I_rst_n(I_rst_n), .I_tuser(mdata1[32] & mvalid1),
        .I_valid(mvalid1), .I_data(mdata1), .O_valid(mvalid2), .O_data(mdata2)
    );

    // 对齐打拍（mag8 3 行）
    reg [31:0] m_d0_d, m_d0, m_d1;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            m_d0_d <= 32'd0; m_d0 <= 32'd0; m_d1 <= 32'd0;
        end else begin
            m_d0_d <= mag8_4p; m_d0 <= m_d0_d; m_d1 <= mdata1[31:0];
        end
    end
    wire [31:0] mag8_cur = m_d0;      //当前行 mag8
    wire [31:0] mag8_up  = m_d1;      //上一行 mag8
    wire [31:0] mag8_up2 = mdata2[31:0]; //上上两行 mag8

    // 方向打 2 拍（对齐 mag8 line buffer）
    reg [7:0] dir_4p, dir_d1, dir_d2;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            dir_4p <= 8'd0; dir_d1 <= 8'd0; dir_d2 <= 8'd0;
        end else begin
            dir_4p <= {d3, d2, d1, d0};
            dir_d1 <= dir_4p;
            dir_d2 <= dir_d1;
        end
    end

    //=========== 第三级：NMS（沿方向比较 2 邻居幅值）===========

    // 拆 3 行 mag8（每行 4 像素，每像素 8bit）
    wire [7:0] cu0 = mag8_cur[7:0],   cu1 = mag8_cur[15:8],  cu2 = mag8_cur[23:16], cu3 = mag8_cur[31:24];
    wire [7:0] up0 = mag8_up[7:0],    up1 = mag8_up[15:8],   up2_ = mag8_up[23:16], up3 = mag8_up[31:24];
    wire [7:0] u20 = mag8_up2[7:0],   u21 = mag8_up2[15:8],  u22 = mag8_up2[23:16], u23 = mag8_up2[31:24];

    // 缓存上一组 g3 的 mag8（3 行）
    reg [7:0] r_prev_g3_mcu, r_prev_g3_mup, r_prev_g3_mu2;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            r_prev_g3_mcu <= 8'd0; r_prev_g3_mup <= 8'd0; r_prev_g3_mu2 <= 8'd0;
        end else begin
            r_prev_g3_mcu <= cu3; r_prev_g3_mup <= up3; r_prev_g3_mu2 <= u23;
        end
    end

    // NMS function：中心 mag8、方向、8 邻居 mag8 → 是否保留
    // 邻居按 dir 选 2 个：dir0 左右、dir1 右上左下、dir2 上下、dir3 左上右下
    function [0:0] nms;
        input [7:0] m;          //中心幅值
        input [1:0] dir;        //方向
        input [7:0] n_left, n_right, n_up, n_down, n_ul, n_ur, n_dl, n_dr;
        reg  [7:0] n_a, n_b;
        begin
            case(dir)
                2'd0: begin n_a = n_left;  n_b = n_right; end  //水平
                2'd1: begin n_a = n_ur;    n_b = n_dl;    end  //45°（右上/左下）
                2'd2: begin n_a = n_up;    n_b = n_down;  end  //垂直
                default: begin n_a = n_ul; n_b = n_dr;    end  //135°（左上/右下）
            endcase
            nms = ((m >= n_a) && (m >= n_b)) ? 1'b1 : 1'b0;
        end
    endfunction

    // 4 像素并行 NMS（g3 右邻居复制 g3，g0 左邻居缓存上一组 g3）
    // 像素0：左=上一组g3(缓存)，右=组内p1
    wire nms0 = nms(up0, dir_d2[1:0],
                    r_prev_g3_mup, up1, u20, cu0, r_prev_g3_mu2, u21, r_prev_g3_mcu, cu1);
    // 像素1
    wire nms1 = nms(up1, dir_d2[3:2],
                    up0, up2_, u21, cu1, u20, u22, cu0, cu2);
    // 像素2
    wire nms2 = nms(up2_, dir_d2[5:4],
                    up1, up3, u22, cu2, u21, u23, cu1, cu3);
    // 像素3：右邻居复制 g3
    wire nms3 = nms(up3, dir_d2[7:6],
                    up2_, up3, u23, cu3, u22, u23, cu2, cu3);

    //=========== 第四级：双阈值（强边缘 + 弱边缘）===========
    wire s0 = nms0 && (up0 > high_thr);
    wire s1 = nms1 && (up1 > high_thr);
    wire s2 = nms2 && (up2_ > high_thr);
    wire s3 = nms3 && (up3 > high_thr);
    wire w0 = nms0 && (up0 > low_thr) && (up0 <= high_thr);
    wire w1 = nms1 && (up1 > low_thr) && (up1 <= high_thr);
    wire w2 = nms2 && (up2_ > low_thr) && (up2_ <= high_thr);
    wire w3 = nms3 && (up3 > low_thr) && (up3 <= high_thr);

    //------------ tvalid/tuser 打 4 拍（对齐 NMS/双阈值输出）------------
    reg tvalid_d1, tvalid_d2, tvalid_d3, tvalid_d4;
    reg tlast_d1,  tlast_d2,  tlast_d3,  tlast_d4;
    reg tuser_d1,  tuser_d2,  tuser_d3,  tuser_d4;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            tvalid_d1 <= 1'b0; tvalid_d2 <= 1'b0; tvalid_d3 <= 1'b0; tvalid_d4 <= 1'b0;
            tlast_d1  <= 1'b0; tlast_d2  <= 1'b0; tlast_d3  <= 1'b0; tlast_d4  <= 1'b0;
            tuser_d1  <= 1'b0; tuser_d2  <= 1'b0; tuser_d3  <= 1'b0; tuser_d4  <= 1'b0;
        end else begin
            tvalid_d1 <= I_tvalid; tvalid_d2 <= tvalid_d1; tvalid_d3 <= tvalid_d2; tvalid_d4 <= tvalid_d3;
            tlast_d1  <= I_tlast;  tlast_d2  <= tlast_d1;  tlast_d3  <= tlast_d2;  tlast_d4  <= tlast_d3;
            tuser_d1  <= I_tuser;  tuser_d2  <= tuser_d1;  tuser_d3  <= tuser_d2;  tuser_d4  <= tuser_d3;
        end
    end

    //=========== 第五级：滞后阈值（弱边缘连强边缘才保留，修复断链）===========

    // 强边缘 line buffer（reg 数组 4bit×320×2，不占 ERAM，抵消平滑 lb 改 BRAM 的 +8 ERAM）
    // 对齐：scur +2 拍、sup +3 拍、sup2 +4 拍，与 BRAM 版 line_buffer_demosaic 的流水线延迟一致
    wire [3:0]  strong_4p = {s3, s2, s1, s0};
    reg [3:0] s_lb1 [0:319], s_lb2 [0:319];
    reg [3:0] s_lb1_rd, s_lb2_rd;
    reg [3:0] s_d0_d, s_d0;
    reg [3:0] s_d1_d1, s_d1;
    reg [3:0] s_d2_d1, s_d2_d2, s_d2;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            s_lb1_rd <= 4'd0; s_lb2_rd <= 4'd0; s_d0_d <= 4'd0; s_d0 <= 4'd0;
            s_d1_d1 <= 4'd0; s_d1 <= 4'd0; s_d2_d1 <= 4'd0; s_d2_d2 <= 4'd0; s_d2 <= 4'd0;
        end else begin
            s_lb1_rd <= s_lb1[h_cnt_d6[8:0]];  // 上一行（读旧值）
            s_lb2_rd <= s_lb2[h_cnt_d6[8:0]];  // 上上行（读旧值）
            s_lb1[h_cnt_d6[8:0]] <= strong_4p;
            s_lb2[h_cnt_d6[8:0]] <= s_lb1_rd;
            s_d0_d <= strong_4p;   // 当前行 +1 拍
            s_d0   <= s_d0_d;      // 当前行 +2 拍
            s_d1_d1 <= s_lb1_rd;   // 上一行 +2 拍
            s_d1    <= s_d1_d1;    // 上一行 +3 拍
            s_d2_d1 <= s_lb2_rd;   // 上上行 +2 拍
            s_d2_d2 <= s_d2_d1;    // 上上行 +3 拍
            s_d2    <= s_d2_d2;    // 上上行 +4 拍
        end
    end
    wire [3:0] scur = s_d0;        //当前行强边缘
    wire [3:0] sup  = s_d1;        //上一行强边缘
    wire [3:0] sup2 = s_d2;        //上上两行强边缘

    // 弱边缘打 2 拍（对齐强边缘 line buffer 延迟）
    reg [3:0] weak_d1, weak_d2;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin weak_d1 <= 4'd0; weak_d2 <= 4'd0; end
        else begin weak_d1 <= {w3,w2,w1,w0}; weak_d2 <= weak_d1; end
    end

    // 缓存上一组 g3 的强边缘（3 行）
    reg r_prev_g3_scur, r_prev_g3_sup, r_prev_g3_sup2;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin r_prev_g3_scur <= 1'b0; r_prev_g3_sup <= 1'b0; r_prev_g3_sup2 <= 1'b0; end
        else begin r_prev_g3_scur <= scur[3]; r_prev_g3_sup <= sup[3]; r_prev_g3_sup2 <= sup2[3]; end
    end

    // 8 邻居强边缘 OR（滞后判断：弱边缘 8 邻域有强边缘则保留）
    wire hs0 = r_prev_g3_sup2 | sup2[0] | sup2[1] | r_prev_g3_sup | sup[1] | r_prev_g3_scur | scur[0] | scur[1];
    wire hs1 = sup2[0] | sup2[1] | sup2[2] | sup[0] | sup[2] | scur[0] | scur[1] | scur[2];
    wire hs2 = sup2[1] | sup2[2] | sup2[3] | sup[1] | sup[3] | scur[1] | scur[2] | scur[3];
    wire hs3 = sup2[2] | sup2[3] | sup2[3] | sup[2] | sup[3] | scur[2] | scur[3] | scur[3];

    // 滞后：强边缘 || (弱边缘 && 8 邻域有强边缘)
    wire edge0 = sup[0] || (weak_d2[0] && hs0);
    wire edge1 = sup[1] || (weak_d2[1] && hs1);
    wire edge2 = sup[2] || (weak_d2[2] && hs2);
    wire edge3 = sup[3] || (weak_d2[3] && hs3);

    // 输出（边界屏蔽）
    wire [7:0] e0 = (cur_valid && edge0) ? 8'hFF : 8'h00;
    wire [7:0] e1 = (cur_valid && edge1) ? 8'hFF : 8'h00;
    wire [7:0] e2 = (cur_valid && edge2) ? 8'hFF : 8'h00;
    wire [7:0] e3 = (cur_valid && edge3) ? 8'hFF : 8'h00;

    assign O_tdata = {e3,e3,e3, e2,e2,e2, e1,e1,e1, e0,e0,e0};

    //------------ valid/tlast/tuser 打 4 拍（总延迟 10 拍，对齐滞后输出）------------
    reg tvalid_d5, tvalid_d6, tvalid_d7, tvalid_d8, tvalid_d9, tvalid_d10;
    reg tlast_d5,  tlast_d6,  tlast_d7,  tlast_d8,  tlast_d9,  tlast_d10;
    reg tuser_d5,  tuser_d6,  tuser_d7,  tuser_d8,  tuser_d9,  tuser_d10;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            tvalid_d5 <= 1'b0; tvalid_d6 <= 1'b0; tvalid_d7 <= 1'b0; tvalid_d8 <= 1'b0; tvalid_d9 <= 1'b0; tvalid_d10 <= 1'b0;
            tlast_d5  <= 1'b0; tlast_d6  <= 1'b0; tlast_d7  <= 1'b0; tlast_d8  <= 1'b0; tlast_d9  <= 1'b0; tlast_d10  <= 1'b0;
            tuser_d5  <= 1'b0; tuser_d6  <= 1'b0; tuser_d7  <= 1'b0; tuser_d8  <= 1'b0; tuser_d9  <= 1'b0; tuser_d10  <= 1'b0;
        end else begin
            tvalid_d5 <= tvalid_d4; tvalid_d6 <= tvalid_d5; tvalid_d7 <= tvalid_d6; tvalid_d8 <= tvalid_d7;
            tvalid_d9 <= tvalid_d8; tvalid_d10 <= tvalid_d9;
            tlast_d5  <= tlast_d4;  tlast_d6  <= tlast_d5;  tlast_d7  <= tlast_d6;  tlast_d8  <= tlast_d7;
            tlast_d9  <= tlast_d8;  tlast_d10 <= tlast_d9;
            tuser_d5  <= tuser_d4;  tuser_d6  <= tuser_d5;  tuser_d7  <= tuser_d6;  tuser_d8  <= tuser_d7;
            tuser_d9  <= tuser_d8;  tuser_d10 <= tuser_d9;
        end
    end
    assign O_tvalid = tvalid_d10;
    assign O_tlast  = tlast_d10;
    assign O_tuser  = tuser_d10;

endmodule
