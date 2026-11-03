//========================================================
// 模块：isp_top —— ISP 图像处理顶层（去马赛克 + 白平衡）
// 数据流：RAW(40位) → demosaic去马赛克(→128位RGB) → data128_96(→96位) → awb白平衡(96位) → data_96bit_to_128bit(→128位) → 输出
// ★ 算法插入点：awb 之后（awb_O_tdata 是 96 位 RGB，在这里插灰度化/二值化/Sobel）
//========================================================
module isp_top (
    input 			axi4s_video_aclk,   //时钟（像素时钟）
    input 			I_rst_n,             //复位，低有效
    input 			I_tlast,             //输入：行结束
    input 			I_tuser,             //输入：帧开始
    input [39:0] 	I_tdata,             //输入：RAW10 数据（40 位）
    input 			I_tvalid,            //输入：数据有效
    input [9:0] 	I_tdest,             //输入：目标（未用）
    input 			O_tready,            //下游就绪（透传）
    input [2:0] 	I_algo_mode,         //算法模式：0=原样 1=灰度 2=二值 3=Sobel（来自 algo_mode_sel）
    input [7:0] 	I_threshold,         //二值化阈值（0~255，来自 threshold_set）
    input [10:0] 	I_sobel_threshold,   //Sobel 阈值（0~2040，来自 sobel_threshold_set）
    input 			I_sw4,               //SW4：模式选择低两位（与 SW3 组合四模式，模式2/3/4触发背景采集）
    input 			I_sw3,               //SW3：模式选择高两位
    input 			I_ae_chg,            //2026-11-03 AE 变化沿（24M 域生成，自动状态曝光/增益变化→重采背景）
    input [95:0] 	I_bg_data,          //背景 96 位 RGB（来自 bg_read，DDR 读出的背景）
    input 			I_bg_valid,          //背景有效（来自 bg_read）
    input 			I_bg_frame_start,    //背景帧开始（来自 bg_read，帧同步对齐用）
    output [127:0] 	O_tdata,             //输出：128 位打包 RGB
    output 			O_tlast,             //输出：行结束
    output 			O_tuser,             //输出：帧开始
    output 			O_tvalid,            //输出：数据有效
    output 			I_tready,            //输出就绪（给上游）
    output [7:0] 	O_brightness_avg,    //输出：平均亮度（自动曝光用，像素域）
    output 			O_brightness_adjust,  //输出：调节脉冲（每10帧一个，自动曝光用）
    output 			O_bg_capture,         //输出：背景采集标志（覆盖完整一帧，给 DDR 背景写）
    output 			O_bg_captured,        //输出：背景已采锁存（门控 bg_read：采完才跑检测）
    output 			O_awb_tuser          //输出：AWB 帧开始（给背景读帧同步，独立于 motion 帧开始）
);

//------------ 内部连线 ------------
wire         m_aixs_tvalid;   //demosaic 输出有效
  wire [127:0] m_aixs_tdata;  //demosaic 输出数据（128 位 RGB）
  wire         m_aixs_tuser;  //demosaic 输出帧开始
  wire         m_aixs_tlast;  //demosaic 输出行结束
  wire         m_aixs_tready; //demosaic 输出就绪

  wire [ 95:0] m_aixs_tdata_96;  //128 位转 96 位后的数据

  wire         awb_O_tlast;   //AWB 输出行结束
  wire         awb_O_tuser;   //AWB 输出帧开始
  wire [ 95:0] awb_O_tdata;   //AWB 输出数据（96 位 RGB）★ 算法插入点在这
  wire         awb_O_tvalid;  //AWB 输出有效
  wire         awb_O_tready;  //AWB 输出就绪

  wire         awb_O_tuser_128;   //96 转 128 后帧开始
  wire         awb_O_tvalid_128;  //96 转 128 后有效
  wire [127:0] awb_O_tdata_128;   //96 转 128 后数据（最终输出）

  // 输出 = AWB 处理完、转回 128 位的结果
  assign awb_O_tready = O_tready;
  assign O_tdata  = awb_O_tdata_128;
  assign O_tlast  = algo_tlast    ;
  assign O_tuser  = awb_O_tuser_128    ;
  assign O_tvalid = awb_O_tvalid_128   ;
  assign O_awb_tuser = awb_O_tuser;  //AWB 帧开始引出（给背景读帧同步）

  //（下面是直通版本，被注释掉了，当前走 AWB 处理链路）
  //assign m_aixs_tready = O_tready;
  //assign O_tdata  = m_aixs_tdata;
  //assign O_tlast  = m_aixs_tlast    ;
  //assign O_tuser  = m_aixs_tuser    ;
  //assign O_tvalid = m_aixs_tvalid   ;

//------------ 第 1 步：去马赛克 demosaic ------------
// 把 RAW（每个像素只有一种颜色）插值成每个像素 RGB 三色
demosaic #(
    .IMG_HEIGHT          (720 ),   //图像高度
    .IMG_WIDTH           (1280),   //图像宽度
    .data_complete_delay (50  ),
    .BAYER_MODE          ("BGGR")  //Bayer 排列模式
)
u_demosaic
(
    .I_clk   			(axi4s_video_aclk),   //时钟
    .I_rst_n 			(I_rst_n),            //复位，低有效
    .axi4s_video_tdata 	(I_tdata),            //输入 RAW 数据
    .axi4s_video_tdest 	(I_tdest),
    .axi4s_video_tlast 	(I_tlast),            //行结束
    .axi4s_video_tvalid	(I_tvalid),           //数据有效
    .axi4s_video_tuser 	(I_tuser),            //帧开始
    .axi4s_video_tready	(I_tready),
    .O_tlast  			(m_aixs_tlast),       //输出行结束
    .O_tuser  			(m_aixs_tuser),       //输出帧开始
    .O_tdata  			(m_aixs_tdata),       //输出数据（128 位 RGB）
    .O_tvalid 			(m_aixs_tvalid),      //输出有效
    .O_tready   		(m_aixs_tready)       //输出就绪
);

//------------ 第 2 步：128 位 → 96 位（AWB 模块按 96 位处理）------------
data128_96 u_data128_96 (
    .I_tdata(m_aixs_tdata),     //输入 128 位
    .O_tdata(m_aixs_tdata_96)   //输出 96 位
);

//------------ 第 3 步：白平衡 AWB ------------
// 校正颜色偏色，让画面颜色正常
awb #(
    .IMG_HEIGHT(720 ),
    .IMG_WIDTH (1280)
) u_awb (
    .I_clk   (axi4s_video_aclk),
    .I_rst_n (I_rst_n),
    .I_tlast (m_aixs_tlast),
    .I_tuser (m_aixs_tuser),
    .I_tdata (m_aixs_tdata_96),   //输入 96 位 RGB
    .I_tvalid(m_aixs_tvalid),
    .I_tready(m_aixs_tready),
    .O_tlast (awb_O_tlast ),
    .O_tuser (awb_O_tuser ),
    .O_tdata (awb_O_tdata ),      //输出 96 位 RGB  ★ 算法插在这之后
    .O_tvalid(awb_O_tvalid),
    .O_tready(awb_O_tready)
);

//------------ 第 3.5 步：坏点校正 BPC（AWB 之后、算法之前）------------
// 【旁路调试版】直连 awb，验证「最右列密集白点+红黄点」是否 BPC 引入（用户直觉：数据少了一列）
// 若旁路后最右列干净 → BPC 的帧尾/边界丢了最后一组，修 BPC；若还在 → 读路径，恢复 BPC 后继续查
wire [95:0] bpc_data;
wire        bpc_valid;
wire        bpc_tlast;
wire        bpc_tuser;
assign bpc_data  = awb_O_tdata;
assign bpc_valid = awb_O_tvalid;
assign bpc_tlast = awb_O_tlast;
assign bpc_tuser = awb_O_tuser;
//（BPC 旁路后延迟 0 拍，统一 8 拍对齐回到 BPC 前：原样/灰度/二值 8 拍 = canny 8 拍 ✓）
//bad_pixel_correct u_bad_pixel_correct (
//    .I_clk       (axi4s_video_aclk),
//    .I_rst_n     (I_rst_n),
//    .I_tdata     (awb_O_tdata),   //输入 96 位 RGB（AWB 后）
//    .I_tvalid    (awb_O_tvalid),
//    .I_tlast     (awb_O_tlast),
//    .I_tuser     (awb_O_tuser),
//    .I_threshold (8'd64),         //坏点阈值（中心与邻域差超此值判坏点）
//    .O_tdata     (bpc_data),
//    .O_tvalid    (bpc_valid),
//    .O_tlast     (bpc_tlast),
//    .O_tuser     (bpc_tuser)
//);

//------------ 第 3.6 步：灰度化 + 算法选择 MUX（BPC 之后）------------
// gray_convert：RGB888 → 灰度（gray = R/4 + G/2 + B/4，纯组合逻辑，不打拍，不破坏 tlast 对齐）
wire [95:0] gray_data;
gray_convert u_gray_convert (
    .I_tdata(bpc_data),       //输入 96 位 RGB（4 像素，坏点校正后）
    .O_tdata(gray_data)      //输出 96 位灰度（4 像素，R=G=B=gray）
);

// binary_convert：RGB888 → 二值化（纯黑白，纯组合逻辑）
wire [95:0] binary_data;
binary_convert u_binary_convert (
    .I_tdata(bpc_data),
    .I_threshold(I_threshold),  //阈值（可调）
    .O_tdata(binary_data)
);

// canny_top：灰度 → Canny 边缘检测（Sobel + 非极大值抑制 + 双阈值，边缘细化成1像素）
// 注：由 sobel_top 升级而来，加了 NMS（边缘细化）+ 双阈值（去弱噪声边缘）
wire [95:0] sobel_data;
wire        sobel_valid;   //Canny 输出有效（延迟 4 拍）
wire        sobel_tlast;   //Canny 输出行结束（延迟 4 拍）
wire        sobel_tuser;   //Canny 输出帧开始（延迟 4 拍）
canny_top u_sobel_top (
    .I_clk       (axi4s_video_aclk),
    .I_rst_n     (I_rst_n),
    .I_tdata     (gray_data),         //输入 96 位灰度（坏点校正后）
    .I_tvalid    (bpc_valid),         //BPC 延迟 3 拍后的同步信号
    .I_tlast     (bpc_tlast),
    .I_tuser     (bpc_tuser),
    .I_threshold (I_sobel_threshold), //高阈值（手动可调，Sobel 阈值复用）
    .O_tdata     (sobel_data),
    .O_tvalid    (sobel_valid),
    .O_tlast     (sobel_tlast),
    .O_tuser     (sobel_tuser)
);

// motion_detect：灰度 → 帧差法运动检测（降采样+存帧+帧差+放大回显，延迟 1 拍）
wire [95:0] motion_data;
wire        motion_valid;   //运动检测输出有效（延迟 1 拍）
wire        motion_tlast;   //运动检测输出行结束（延迟 1 拍）
wire        motion_tuser;   //运动检测输出帧开始（延迟 1 拍）
wire [95:0] motion_cur_data;//读出的当前帧（跟 motion_data 对齐，供原样叠加回显）
// 2026-11-03 I_ae_chg 跨域打 2 拍（24M 域 → 60M 摄像头域；24M 脉冲宽 41.7ns > 60M 周期，采样可靠）
reg ae_chg_d1, ae_chg_d2;
always @(posedge axi4s_video_aclk or negedge I_rst_n) begin
    if(!I_rst_n) begin ae_chg_d1 <= 1'b0; ae_chg_d2 <= 1'b0; end
    else begin ae_chg_d1 <= I_ae_chg; ae_chg_d2 <= ae_chg_d1; end
end
motion_detect u_motion_detect (
    .I_clk    (axi4s_video_aclk),
    .I_rst_n  (I_rst_n),
    .I_tdata  (bpc_data),        //输入 96 位 RGB（坏点校正后，RGB 减背景保留颜色信息）
    .I_tvalid (bpc_valid),
    .I_tlast  (bpc_tlast),
    .I_tuser  (bpc_tuser),
    .I_sw4    (I_sw4),             //模式选择低两位（SW4）
    .I_sw3    (I_sw3),             //模式选择高两位（SW3）
    .I_ae_chg (ae_chg_d2),         //2026-11-03 AE 变化沿（打 2 拍后）
    .I_bg_data(I_bg_data),         //背景 96 位 RGB（来自 bg_read）
    .I_bg_valid(I_bg_valid),       //背景有效（来自 bg_read）
    .I_bg_frame_start(I_bg_frame_start), //背景帧开始（帧同步对齐）
    .O_tdata  (motion_data),
    .O_cur_data(motion_cur_data),   //读出的当前帧（供原样叠加）
    .O_tvalid (motion_valid),
    .O_tlast  (motion_tlast),
    .O_tuser  (motion_tuser),
    .O_bg_capture (O_bg_capture),   //背景采集标志引出（给 DDR 背景写）
    .O_bg_captured (O_bg_captured)  //背景已采锁存引出（门控 bg_read）
);

// brightness_stat：灰度 → 亮度统计（自动曝光用，统计一帧平均亮度）
wire [7:0] brightness_avg;
wire       brightness_adjust;
brightness_stat u_brightness_stat (
    .I_clk    (axi4s_video_aclk),
    .I_rst_n  (I_rst_n),
    .I_tdata  (gray_data),         //输入 96 位灰度（坏点校正后）
    .I_tvalid (bpc_valid),
    .I_tuser  (bpc_tuser),
    .O_avg    (brightness_avg),
    .O_adjust (brightness_adjust)
);
assign O_brightness_avg    = brightness_avg;
assign O_brightness_adjust = brightness_adjust;

// I_algo_mode 跨时钟域同步（按键在 24M 域，这里是像素时钟域）
// 3 位二进制直接打 2 拍会采到中间态（如 001→010 时 bit0/bit1 同时翻转），
// 切换算法瞬间 MUX 选错模式产生异常像素。改用格雷码（相邻值只变 1 位）打 2 拍。
wire [2:0] algo_mode_gray = I_algo_mode ^ {1'b0, I_algo_mode[2:1]};
reg [2:0] algo_gray_1d, algo_gray_2d;
always @(posedge axi4s_video_aclk or negedge I_rst_n) begin
    if(!I_rst_n) begin
        algo_gray_1d <= 3'd0;
        algo_gray_2d <= 3'd0;
    end else begin
        algo_gray_1d <= algo_mode_gray;
        algo_gray_2d <= algo_gray_1d;
    end
end
// 格雷码转回二进制
wire [2:0] algo_mode_2d;
assign algo_mode_2d[2] = algo_gray_2d[2];
assign algo_mode_2d[1] = algo_gray_2d[2] ^ algo_gray_2d[1];
assign algo_mode_2d[0] = algo_gray_2d[2] ^ algo_gray_2d[1] ^ algo_gray_2d[0];
// 2026-11-02 帧同步修复：算法模式切换在帧开始（bpc_tuser）才生效。
// 根因：KEY 脉冲随机落在帧中间，algo_mode_2d 帧中跳变 → 数据链延迟跳变
//   （原样/灰度/二值 0 拍 vs Sobel 8 拍）→ 画面持续错位（再按键/复位才恢复）。
// 帧同步后：切换帧干净、延迟差只影响切换前最后一帧（完整显示），根治。
reg [2:0] algo_applied;
always @(posedge axi4s_video_aclk or negedge I_rst_n) begin
    if(!I_rst_n) algo_applied <= 3'd0;
    else if(bpc_tuser) algo_applied <= algo_mode_2d;   //帧开始采样应用
end
wire algo_tuser = (algo_applied == 3'd3) ? sobel_tuser : bpc_tuser;
wire algo_tlast = (algo_applied == 3'd3) ? sobel_tlast : bpc_tlast;

//------------ 统一延迟 8 拍【已撤销做二分实验】------------
// 撤销原因：最右列 3 像素异常定位——「官方无、当前有」的差异中唯一没验证的就是统一 8 拍。
// 撤销后：原样/灰度/二值 0 拍直出、Sobel 8 拍（canny 内部）→ 切算法闪会回来（已知代价）。
// 若最右列消失 → 统一 8 拍的打拍链在行尾有错位，重做对齐；
// 若还在 → 排除统一 8 拍，恢复此段。
/*
reg [95:0] awb_d1, awb_d2, awb_d3, awb_d4, awb_d5, awb_d6, awb_d7, awb_d8;
reg [95:0] gray_d1, gray_d2, gray_d3, gray_d4, gray_d5, gray_d6, gray_d7, gray_d8;
reg [95:0] binary_d1, binary_d2, binary_d3, binary_d4, binary_d5, binary_d6, binary_d7, binary_d8;
reg        awb_valid_d1, awb_valid_d2, awb_valid_d3, awb_valid_d4, awb_valid_d5, awb_valid_d6, awb_valid_d7, awb_valid_d8;
reg        awb_tlast_d1, awb_tlast_d2, awb_tlast_d3, awb_tlast_d4, awb_tlast_d5, awb_tlast_d6, awb_tlast_d7, awb_tlast_d8;
reg        awb_tuser_d1, awb_tuser_d2, awb_tuser_d3, awb_tuser_d4, awb_tuser_d5, awb_tuser_d6, awb_tuser_d7, awb_tuser_d8;
reg [2:0]  algo_d1, algo_d2, algo_d3, algo_d4, algo_d5, algo_d6, algo_d7, algo_d8;

always @(posedge axi4s_video_aclk or negedge I_rst_n) begin
    if(!I_rst_n) begin
        awb_d1 <= 96'd0; awb_d2 <= 96'd0; awb_d3 <= 96'd0; awb_d4 <= 96'd0; awb_d5 <= 96'd0; awb_d6 <= 96'd0; awb_d7 <= 96'd0; awb_d8 <= 96'd0;
        gray_d1 <= 96'd0; gray_d2 <= 96'd0; gray_d3 <= 96'd0; gray_d4 <= 96'd0; gray_d5 <= 96'd0; gray_d6 <= 96'd0; gray_d7 <= 96'd0; gray_d8 <= 96'd0;
        binary_d1 <= 96'd0; binary_d2 <= 96'd0; binary_d3 <= 96'd0; binary_d4 <= 96'd0; binary_d5 <= 96'd0; binary_d6 <= 96'd0; binary_d7 <= 96'd0; binary_d8 <= 96'd0;
        awb_valid_d1 <= 1'b0; awb_valid_d2 <= 1'b0; awb_valid_d3 <= 1'b0; awb_valid_d4 <= 1'b0; awb_valid_d5 <= 1'b0; awb_valid_d6 <= 1'b0; awb_valid_d7 <= 1'b0; awb_valid_d8 <= 1'b0;
        awb_tlast_d1 <= 1'b0; awb_tlast_d2 <= 1'b0; awb_tlast_d3 <= 1'b0; awb_tlast_d4 <= 1'b0; awb_tlast_d5 <= 1'b0; awb_tlast_d6 <= 1'b0; awb_tlast_d7 <= 1'b0; awb_tlast_d8 <= 1'b0;
        awb_tuser_d1 <= 1'b0; awb_tuser_d2 <= 1'b0; awb_tuser_d3 <= 1'b0; awb_tuser_d4 <= 1'b0; awb_tuser_d5 <= 1'b0; awb_tuser_d6 <= 1'b0; awb_tuser_d7 <= 1'b0; awb_tuser_d8 <= 1'b0;
        algo_d1 <= 3'd0; algo_d2 <= 3'd0; algo_d3 <= 3'd0; algo_d4 <= 3'd0; algo_d5 <= 3'd0; algo_d6 <= 3'd0; algo_d7 <= 3'd0; algo_d8 <= 3'd0;
    end else begin
        awb_d1 <= bpc_data; awb_d2 <= awb_d1; awb_d3 <= awb_d2; awb_d4 <= awb_d3; awb_d5 <= awb_d4; awb_d6 <= awb_d5; awb_d7 <= awb_d6; awb_d8 <= awb_d7;
        gray_d1 <= gray_data; gray_d2 <= gray_d1; gray_d3 <= gray_d2; gray_d4 <= gray_d3; gray_d5 <= gray_d4; gray_d6 <= gray_d5; gray_d7 <= gray_d6; gray_d8 <= gray_d7;
        binary_d1 <= binary_data; binary_d2 <= binary_d1; binary_d3 <= binary_d2; binary_d4 <= binary_d3; binary_d5 <= binary_d4; binary_d6 <= binary_d5; binary_d7 <= binary_d6; binary_d8 <= binary_d7;
        awb_valid_d1 <= bpc_valid; awb_valid_d2 <= awb_valid_d1; awb_valid_d3 <= awb_valid_d2; awb_valid_d4 <= awb_valid_d3; awb_valid_d5 <= awb_valid_d4; awb_valid_d6 <= awb_valid_d5; awb_valid_d7 <= awb_valid_d6; awb_valid_d8 <= awb_valid_d7;
        awb_tlast_d1 <= bpc_tlast; awb_tlast_d2 <= awb_tlast_d1; awb_tlast_d3 <= awb_tlast_d2; awb_tlast_d4 <= awb_tlast_d3; awb_tlast_d5 <= awb_tlast_d4; awb_tlast_d6 <= awb_tlast_d5; awb_tlast_d7 <= awb_tlast_d6; awb_tlast_d8 <= awb_tlast_d7;
        awb_tuser_d1 <= bpc_tuser; awb_tuser_d2 <= awb_tuser_d1; awb_tuser_d3 <= awb_tuser_d2; awb_tuser_d4 <= awb_tuser_d3; awb_tuser_d5 <= awb_tuser_d4; awb_tuser_d6 <= awb_tuser_d5; awb_tuser_d7 <= awb_tuser_d6; awb_tuser_d8 <= awb_tuser_d7;
        algo_d1 <= algo_mode_2d; algo_d2 <= algo_d1; algo_d3 <= algo_d2; algo_d4 <= algo_d3; algo_d5 <= algo_d4; algo_d6 <= algo_d5; algo_d7 <= algo_d6; algo_d8 <= algo_d7;
    end
end
*/

//------------ 模式0（原样）：SW4 控制运动检测叠加开关 ------------
// SW4 跨时钟域同步（24M 域 → 像素域，打两拍）
reg sw4_1d, sw4_2d;
always @(posedge axi4s_video_aclk or negedge I_rst_n) begin
    if(!I_rst_n) begin sw4_1d <= 1'b0; sw4_2d <= 1'b0; end
    else begin sw4_1d <= I_sw4; sw4_2d <= sw4_1d; end
end

// 原样（模式0）直接用实时 awb 数据（禁用运动检测叠加，后续恢复背景读再启用）
// 算法 MUX【二分实验版：撤销统一 8 拍，组合直选】——原样/灰度/二值 0 拍、Sobel 8 拍（canny 内部）
reg [95:0] algo_data;
always @(*) begin
    case(algo_applied)
    3'd0 : algo_data = bpc_data;      //模式0：原样（禁用运动检测，直通 awb）
    3'd1 : algo_data = gray_data;     //模式1：灰度化
    3'd2 : algo_data = binary_data;   //模式2：二值化
    3'd3 : algo_data = sobel_data;    //模式3：Sobel 边缘检测（canny 内部 8 拍）
    default : algo_data = bpc_data;
    endcase
end

// valid/tlast/tuser MUX：Sobel 用 sobel_*（8 拍），其他（原样/灰度/二值）用实时组合
wire algo_valid = (algo_applied == 3'd3) ? sobel_valid : bpc_valid;

//------------ 第 4 步：96 位 → 128 位（输出要 128 位）------------
// 注：data_96bit_to_128bit 模块定义在 data96_128.v 文件里（那个文件有两个模块）
data_96bit_to_128bit u_data_96bit_to_128bit(
    .I_clk              ( axi4s_video_aclk  ),
    .I_rst_n            ( I_rst_n           ),

    .I_96b_frame_start  ( algo_tuser	    ),
    .I_96b_valid        ( algo_valid 	),
    .I_96b_data         ( algo_data	    ),

    .O_128b_frame_start ( awb_O_tuser_128  ),
    .O_128b_valid       ( awb_O_tvalid_128 ),
    .O_128b_data        ( awb_O_tdata_128  )
);


//（下面是旧版 data96_128 模块的直连方式，被注释掉了）
//data96_128 u_data96_128 (
//    .I_tdata(awb_O_tdata),
//    .O_tdata(awb_O_tdata_128)
//);

endmodule
