module design_top_wrapper (
    //时钟与复位
    input wire        I_sys_clk,            //输入  系统时钟，50MHz，板子晶振（引脚 C4）
    input wire        I_rst_n,              //输入  复位，低有效（引脚 R10）   

    output wire       O_cam_scl,            //输出  摄像头 I2C 时钟（引脚 K3）
    inout  wire       IO_cam_sda,           //inout 摄像头 I2C 数据，双向（引脚 J3）
    output wire       O_cam_24m,            //输出  摄像头工作时钟 24MHz（引脚 L3）
    output wire       O_cam_rst,            //输出  摄像头复位（引脚 L2）
    //按键
    input wire [2:0]  I_button,             //inout  3个按键 [0]=加 [1]=减 [2]=保留
    //sw的输入
    input wire [3:0]  I_sw, 
    // led显示模式几
    output reg [3:0]  O_led,        //led输出
    //数码管显示曝光值
    output wire [7:0] O_seg,   //数码管 8 段（DIG，共阳，0点亮）
    output wire [7:0] O_sel,    //数码管 8 个位选（SEL，1选中）
    //HDMI 输出（TMDS 差分信号） HDMI 是 4 对差分线：3 对数据（RGB 编码后）+ 1 对时钟。画面就从这 4 对线送到显示器。
    output wire       O_screen_pwm,         //输出  屏幕背光控制（引脚 R11，代码里固定拉高=常亮）
    output wire       uart_tx,              //输出  UART 诊断发送（引脚 H1，115200 8N1）
    output wire       O_tmds_ch0_p,         //输出  HDMI 数据通道 0 差分正（引脚 G16）
    output wire       O_tmds_ch1_p,         //输出  HDMI 数据通道 1 差分正（引脚 F17）
    output wire       O_tmds_ch2_p,         //输出  HDMI 数据通道 2 差分正（引脚 H14）
    output wire       O_tmds_clk_p,         //输出  HDMI 时钟通道差分正（引脚 C17）
    //MIPI 摄像头输入（差分对，接收 SC500 的图像数据）摄像头拍到的图像，就是通过这几对高速差分线送进来的。时钟 1 对 + 数据 4 对（实际用 2 lane）。
    //这些引脚没有在 pin.adc 里约束，因为是 MIPI 硬核专用引脚，由 IP 自动绑定。
    inout wire        IO_rx_clk_pad_n,      //inout  MIPI 时钟差分对（负）
    inout wire        IO_rx_clk_pad_p,      //inout  MIPI 时钟差分对（正）
    inout wire[3:0]   IO_rx_data_pad_n,     //inout  MIPI 数据差分对（负，4 lane）
    inout wire[3:0]   IO_rx_data_pad_p,     //inout  MIPI 数据差分对（正，4 lane）
    //DDR 内存接口（片内 DDR，帧缓存用）
    //这一大坨就是 DDR 内存的标准接口：地址 + 命令（ras/cas/we）+ 数据 + 差分时钟。
    //它是「帧缓存」——摄像头进来的画面先写进 DDR，HDMI 再读出来显示（两边时钟不同，靠 DDR 缓冲）。
    //这些引脚也不在 pin.adc 里，由 DDR IP 核自动绑定片内 DDR。
    output wire[12:0] ddr_addr,             //输出  地址总线，13 位（寻址内存单元）
    output wire[ 1:0] ddr_ba,               //输出  bank 地址，2 位（选存储块）
    output wire[ 0:0] ddr_cke,              //输出  时钟使能
    output wire[ 0:0] ddr_odt,              //输出  片内终端电阻（信号完整性）
    output wire[ 0:0] ddr_cs_n,             //输出  片选，低有效
    output wire       ddr_ras_n,            //输出  行地址选通，低有效
    output wire       ddr_cas_n,            //输出  列地址选通，低有效
    output wire       ddr_we_n,             //输出  写使能，低有效
    output wire[ 0:0] ddr_ck_p,             //输出  差分时钟（正）
    output wire[ 0:0] ddr_ck_n,             //输出  差分时钟（负）
    inout wire[1:0]   ddr_dm,               //inout  数据掩码（写时屏蔽某些字节）
    inout wire[15:0]  ddr_dq,               //inout  数据总线，16 位（读写数据）
    inout wire[1:0]   ddr_dqs_p,            //inout 数据选通差分（正），2 组
    inout wire[1:0]   ddr_dqs_n            //inout 数据选通差分（负），2 组
);

    //================ ① 时钟与复位 ================
    wire        	S_100m_clk;             //100MHz（MIPI/DDR 参考）
    wire        	S_24m_clk;              //24MHz（摄像头工作 + I2C）
    wire        	S_aux_50m_clk;          //50MHz 辅助时钟
	wire        	S_10m_clk;              //10MHz
	wire        	S_pll_lock;             //PLL 锁定标志
    wire        	S_rst_n;                //系统复位（= S_pll_lock，PLL 锁定了才释放复位）

	//================ ② 摄像头曝光/增益（按键调节的链路）================
	wire [15:0] 	S_ae;                   //曝光值（16 位）
    wire [15:0] 	S_ag;                   //增益值（16 位）
    wire 			S_cam_cfg_done;         //摄像头寄存器初始化完成
    wire 			S_ae_cfg_done;          //曝光配置完成
    wire 			S_ae_req;               //曝光调节请求（按键 → ae_set 算 S_ae/S_ag → uicfgcs500 通过 I2C 写给摄像头）

	//================ ③ MIPI 接收 → CSI 解析（画面数据进来的前半段）================
	wire        	S_csi_rx_clk;           //MIPI 恢复出来的像素时钟
    wire        	S_hs_rx_valid;          //HS 高速数据有效
    wire[15:0]  	S_hs_rx_data;           //HS 数据（16 位）
	wire[1:0]   	S_lane_error;           //lane 错误标志

	wire        	S_csi_frame_start;      //CSI 帧开始
	wire        	S_csi_frame_end;        //CSI 帧结束
	wire        	S_csi_valid;            //CSI 像素有效
	wire[31:0]  	S_csi_data;             //CSI 像素字（32 位）

	wire        	S_raw10_frame_start;    //RAW10 帧开始
	wire        	S_raw10_frame_end;      //RAW10 帧结束
	wire        	S_raw10_valid;          //RAW10 有效
	wire [39:0] 	S_raw10_data;           //RAW10 数据（40 位）

	wire 			S_axis_tlast;           //AXI-Stream 行结束
	wire 			S_axis_tuser;           //AXI-Stream 帧开始
	wire [39:0]		S_axis_tdata;           //AXI-Stream 数据（40 位）
	wire 			S_axis_tvalid;          //AXI-Stream 有效

	//================ ④ RAW 直通 + ISP 输出 ================
	wire [39:0]		S_raw_tdata;            //RAW 数据（40 位，直连 ISP）
	wire			S_raw_tlast;            //RAW 行结束
	wire 			S_raw_tvalid;           //RAW 有效
	wire 			S_raw_tuser;            //RAW 帧开始

	wire			S_ISP_O_tready;         //ISP 输出就绪
	wire [127:0]	S_ISP_O_tdata;          //ISP 输出数据（128 位打包 RGB）
	wire 			S_ISP_O_tlast;          //ISP 输出行结束
	wire 			S_ISP_O_tuser;          //ISP 输出帧开始
	wire 			S_ISP_O_tvalid;         //ISP 输出有效

    //================ ⑤ DDR / HDMI 时钟 ================
    wire        S_ddr_clk;              //DDR 时钟
    wire        S_hdmi_pixel_clk;       //HDMI 像素时钟
    wire        S_hdmi_serial_clk;      //HDMI 串行时钟
    wire        S_hdmi_rst_n;           //HDMI 复位
    wire        S_video_out_rst_n;      //视频输出复位

    //================ ⑥ 帧缓存（video_in 写 DDR / video_out 读 DDR）================
    wire        S_vi_128b_frame_start;  //video_in 帧开始
    wire        S_vi_128b_valid;        //video_in 有效
    wire[127:0] S_vi_128b_data;         //video_in 数据（128 位）

    wire        S_video_out_rd_busy;    //video_out 读忙
    wire [8:0]  S_vo_fifo_level;        //video_out 等效水位（FIFO已写+在途，bg_read 读门控用）
    wire        S_video_in_wr_busy;     //video_in 写忙
    wire[1:0]   S_video_out_rp;         //video_out 读指针（乒乓）

    wire        S_ddr_user_wr_en;       //DDR 用户写使能
    wire        S_ddr_user_rd_en;       //DDR 用户读使能
    wire[24:0]  S_ddr_user_addr;        //DDR 用户地址（25 位）
    wire[127:0] S_ddr_user_wr_data;     //DDR 用户写数据（128 位）
    wire        S_ddr_user_ready;       //DDR 用户就绪
    wire        S_ddr_user_rd_valid;    //DDR 用户读有效
    wire[127:0] S_ddr_user_rd_data;     //DDR 用户读数据（128 位）

    wire        S_vi_ddr_wr_en;         //video_in → DDR 写使能
    wire[24:0]  S_vi_ddr_wr_addr;       //video_in → DDR 写地址
    wire[127:0] S_vi_ddr_wr_data;       //video_in → DDR 写数据
    wire        S_vi_ddr_wr_ready;      //video_in → DDR 写就绪

    wire        S_vo_ddr_rd_en;         //video_out → DDR 读使能
    wire[24:0]  S_vo_ddr_rd_addr;       //video_out → DDR 读地址
    wire        S_vo_ddr_rd_ready;      //video_out → DDR 读就绪

    wire        S_bg_capture;           //背景采集标志（motion_detect → video_in，覆盖完整一帧）
    wire        S_bg_captured_isp;      //背景已采锁存（motion_detect 输出，ISP 像素域，门控 bg_read 启动）
    wire        S_frame_start_ddr;      //DDR 域帧开始（video_in 引出 → bg_read 帧同步读）
    wire        S_awb_tuser;            //AWB 帧开始（摄像头域，给背景读帧同步）
    wire        S_frame_start_awb;      //DDR 域帧开始（AWB 帧开始跨时钟域，给 bg_read 帧同步读）
    wire        S_bg_rd_busy;           //bg_read 读忙
    wire        S_bg_rd_en;             //bg_read → DDR 读使能
    wire        S_vo_rd_req;            //video_out 读请求（给仲裁器）
    wire        S_vi_wr_req;            //video_in 写请求（给仲裁器）
    wire        S_bg_req;               //bg_read 读请求（给仲裁器）
    wire[24:0]  S_bg_rd_addr;           //bg_read → DDR 读地址
    wire[127:0] S_bg_data;              //背景数据（128 位，摄像头域，阶段 2 用）
    wire        S_bg_valid;             //背景有效（摄像头域，阶段 2 用）
    wire        S_bg_frame_start;       //背景帧开始（摄像头域，帧同步对齐用）
    reg         grant_rd, grant_wr, grant_bg;   //DDR 仲裁 grant（显示读/采集写/背景读）
    reg [7:0]   wr_wait_cnt, bg_wait_cnt;       //仲裁饿死等待计数

    //================ ⑦ 内存控制器接口（mc = memory controller）================
    wire        S_init_calib_complete;  //DDR 初始化校准完成
    wire[24:0]  S_mc_app_addr;          //内存控制器地址
    wire[2:0]   S_mc_app_cmd;           //内存控制器命令
    wire        S_mc_app_en;            //内存控制器使能
    wire[127:0] S_mc_app_wdf_data;      //写数据
    wire        S_mc_app_wdf_end;       //写数据结束
    wire[15:0]  S_mc_app_wdf_mask;      //写数据掩码
    wire        S_mc_app_wdf_wren;      //写使能
    wire[127:0] S_mc_app_rd_data;       //读数据
    wire        S_mc_app_rd_data_end;   //读数据结束
    wire        S_mc_app_rd_data_valid; //读数据有效
    wire        S_mc_app_rdy;           //内存控制器就绪
    wire        S_mc_app_wdf_rdy;       //写数据就绪

    //================ ⑧ HDMI 时序与输出 ================
    wire        S_hdmi_vsync;           //HDMI 场同步
    wire        S_hdmi_hsync;           //HDMI 行同步
    wire        S_hdmi_de;              //HDMI 数据有效
    wire        S_hdmi_user;            //HDMI 帧开始
    wire        S_hdmi_last;            //HDMI 行结束
    wire        S_video_out_vsync;      //video_out 场同步
    wire        S_hdmi_window_rd_en;    //HDMI 读窗口使能
    wire        S_hdmi_out_vsync;       //HDMI 输出场同步
    wire        S_hdmi_out_hsync;       //HDMI 输出行同步
    wire        S_hdmi_out_de;          //HDMI 输出数据有效
    wire[23:0]  S_hdmi_out_data;        //HDMI 输出数据（24 位 RGB）

    wire[23:0]  S_video_rd_data;        //从 DDR 读出的像素（24 位 RGB）
    wire[1:0]   S_mode;
    wire[2:0]   S_debounced;      //消抖后电平
    wire        S_inc_tick;    //加长按 tick
    wire        S_dec_tick;    //减长按 tick
    wire [15:0] S_bcd_ae;   //曝光值转出的 BCD（4个数字）
    wire [15:0] S_bcd_ag;   //增益值转出的 BCD（4个数字）
    wire        S_key_pulse;     //KEY4 短按脉冲（释放沿+未长按成立，key_short_press 判定）
    wire        S_key4_tick;     //KEY4 长按 tick（key_hold 输出，按住每 200ms 一个）
    wire        S_auto_manual;   //自动/手动曝光状态（KEY4 长按切换：0=自动 1=手动，仅 SW34=00 生效）
    wire [2:0]  S_algo_mode;      //算法模式：0=原样 1=灰度（KEY4 切换）
    //================ 前景标记 ERAM 连线（主线：消隐期 bg_read 写 / 显示期 hdmi_mixer 读）================
    wire [14:0] S_fg_wr_addr;    //ERAM 写地址（bg_read → ERAM A 口）
    wire [39:0] S_fg_wr_data;    //ERAM 写数据（bg_read → ERAM A 口）
    wire        S_fg_wr_en;      //ERAM 写使能（bg_read → ERAM A 口）
    wire        S_fg_init;       //ERAM 首轮写满（bg_read 输出，DDR 域）
    wire [14:0] S_dbg_first_addr;   //首字写拍地址（串口诊断）
    wire [39:0] S_dbg_first_data;   //首字写拍数据（错位拍数诊断，10-31 加）
    wire        [1:0]  S_dbg_first_half;   //首字写拍半帧（串口诊断）
    wire        S_dbg_first_valid;  //首字写拍锁存脉冲（串口诊断）
    wire        S_uart_tx;          //UART 诊断发送
    wire [14:0] S_fg_rd_addr;    //ERAM 读地址（hdmi_mixer → ERAM B 口）
    wire [39:0] S_fg_rd_data;    //ERAM 读数据（ERAM B 口 → hdmi_mixer）
    //（S_blank_trig 声明已退役：消隐窗口改由 S_ddr_win 状态机生成 S_blank_trig_new）
    wire        S_fg_init_hdmi;  //ERAM 首轮写满（同步到 HDMI 域，叠加使能）
    wire [18:0] S_fg_dbg_rd_cnt; //debug：消隐期读总数（未接显示，仿真/信号观测用）
    //================ 外接框/质心/跟踪 统计连线（bbox_stat → hdmi_mixer，模式 3）================
    wire        S_fs_pulse;      //帧开始延迟 512 拍脉冲（bg_read → bbox_stat 帧边界）
    wire [1:0]  S_half_sel;      //段选择（bg_read → bbox_stat 统计分组：0=A 1=B1 2=B2）
    wire        S_bbox_valid;    //整帧统计有效
    wire [10:0] S_bbox_min_x, S_bbox_max_x;   //外接框左右边界
    wire [9:0]  S_bbox_min_y, S_bbox_max_y;   //外接框上下边界
    wire [10:0] S_bbox_cx;       //质心 X
    wire [9:0]  S_bbox_cy;       //质心 Y
    wire [4:0]  S_bbox_dir_dx, S_bbox_dir_dy;   //方向块偏移（有符号）
    wire        S_bbox_dir_valid; //方向有效
    wire [19:0] S_bbox_cnt;      //标记像素总数（诊断）
    wire [7:0]  S_threshold;      //二值化阈值（0~255）
    wire [15:0] S_bcd_threshold;  //阈值 BCD（4位十进制）
    wire [10:0] S_sobel_threshold;      //Sobel 阈值（0~2040）
    wire [15:0] S_bcd_sobel_threshold;  //Sobel 阈值 BCD（4位十进制）
    wire [7:0]  S_brightness_avg;  //平均亮度（isp_top 输出，像素域）
    wire        S_brightness_adjust;//调节脉冲（isp_top 输出，像素域）
    wire [7:0]  S_target;          //目标亮度（target_set 输出）
    wire [15:0] S_bcd_target;      //目标亮度 BCD（4位十进制）
    //================ 一些简单的连线 ================
    assign O_screen_pwm = 1'b1;             //屏幕背光固定拉高（常亮）
    assign S_video_out_vsync = ~S_hdmi_vsync;  //场同步取反给 video_out

    assign S_rst_n 		= S_pll_lock;         //系统复位 = PLL 锁定（不等 DDR，避免卡死在复位）
    assign S_hdmi_rst_n = S_pll_lock;       //HDMI 复位 = PLL 锁定

    assign O_cam_rst 	= 1'b1;               //摄像头复位固定拉高（不复位）
    assign O_cam_24m 	= S_24m_clk;          //摄像头 24M 工作时钟

    //================ 模块例化：PLL 时钟生成 ================
    // 输入 50M 时钟，生成 100M / 24M / HDMI 像素 / HDMI 串行 四路时钟
    PLL u_PLL(
        .refclk      ( I_sys_clk         ),   //输入 50MHz
        .reset   	 ( ~I_rst_n          ),   //复位（高有效，取反）

        .clk0_out    ( S_100m_clk        ),   //100MHz
        .clk1_out    ( S_24m_clk         ),   //24MHz（摄像头）

        .clk4_out    ( S_hdmi_pixel_clk  ),   //HDMI 像素时钟
        .clk5_out    ( S_hdmi_serial_clk ),   //HDMI 串行时钟

        .lock        ( S_pll_lock        )    //锁定标志
    );
    //实例化mode
    sw_mode u_sw_mode (
        .clk(S_24m_clk), 
        .rst_n(S_rst_n), 
        .sw(I_sw), 
        .mode(S_mode)
    );
    reg S_diag_vsync_latch, S_diag_bg_active_latch, S_diag_bg_grant_latch;
    //------------ LED4 = 背景已采集锁存（2026-11-01 恢复正式语义，替代调试期 S_fg_init 常亮）------------
    // SW4 拨下采集过背景后 LED4 保持亮（提示背景已就绪），复位清零
    reg S_bg_capture_d1, S_bg_capture_d2;    //跨域打 2 拍
    reg S_bg_captured_latch;
    always @(posedge S_24m_clk or negedge S_rst_n) begin
        if(!S_rst_n) begin
            S_bg_capture_d1    <= 1'b0;
            S_bg_capture_d2    <= 1'b0;
            S_bg_captured_latch <= 1'b0;
        end else begin
            S_bg_capture_d1    <= S_bg_capture;
            S_bg_capture_d2    <= S_bg_capture_d1;
            if(S_bg_capture_d2)
                S_bg_captured_latch <= 1'b1;    //采过背景，锁存保持
        end
    end
    always @(*) begin
        case(S_mode)
            2'd0 : O_led = 4'b0001;   //算法模式1（原样）：LED1
            2'd1 : O_led = 4'b0010;   //算法模式2（灰度）：LED2
            2'd2 : O_led = 4'b0100;   //算法模式3（二值）：LED3
            2'd3 : O_led = 4'b1000;   //算法模式4（边缘）：LED4
            default : O_led = 4'b0000;
        endcase
    end
    //实例化按键（长按短按）
    debounce #(.CLK_FREQ(24_000_000), .DEBOUNCE_MS(20)) u_debounce_1 (
        .clk(S_24m_clk), 
        .rst_n(S_rst_n), 
        .key_in(I_button[0]), 
        .debounced(S_debounced[0])
    );
    debounce #(.CLK_FREQ(24_000_000), .DEBOUNCE_MS(20)) u_debounce_2 (
        .clk(S_24m_clk), 
        .rst_n(S_rst_n), 
        .key_in(I_button[1]), 
        .debounced(S_debounced[1])
    );
    debounce #(.CLK_FREQ(24_000_000), .DEBOUNCE_MS(20)) u_debounce_3 (
        .clk(S_24m_clk), 
        .rst_n(S_rst_n), 
        .key_in(I_button[2]), 
        .debounced(S_debounced[2])
    );
    key_hold #(.CLK_FREQ(24_000_000), .HOLD_MS(200)) u_key_hold_inc (
        .clk(S_24m_clk), 
        .rst_n(S_rst_n),
        .debounced(S_debounced[0]), 
        .key_tick(S_inc_tick)
    );
    key_hold #(.CLK_FREQ(24_000_000), .HOLD_MS(200)) u_key_hold_dec (
        .clk(S_24m_clk), 
        .rst_n(S_rst_n),
        .debounced(S_debounced[1]), 
        .key_tick(S_dec_tick)
    );
    // KEY4 一 key 两用：短按=切算法画面、长按=切自动/手动曝光（长短按必须分清，
    // 长按开头也是一次按下沿，故短按判定用「释放沿+未长按成立」，见 key_short_press）
    key_hold #(.CLK_FREQ(24_000_000), .HOLD_MS(200)) u_key_hold_key4 (
        .clk(S_24m_clk),
        .rst_n(S_rst_n),
        .debounced(S_debounced[2]),
        .key_tick(S_key4_tick)
    );
    key_short_press u_key_short_press (
        .clk(S_24m_clk),
        .rst_n(S_rst_n),
        .debounced(S_debounced[2]),
        .long_tick(S_key4_tick),
        .short_pulse(S_key_pulse)
    );
    // 自动/手动曝光切换（KEY4 长按成立切一次，仅 SW34=00；其他模式锁定自动）
    auto_manual_sel u_auto_manual_sel (
        .clk(S_24m_clk),
        .rst_n(S_rst_n),
        .en(~I_sw[2] && ~I_sw[3]),
        .debounced(S_debounced[2]),
        .tick(S_key4_tick),
        .mode(S_auto_manual)
    );
    //================ 阈值联动自动调节（2026-11-03 新增）================
    // SW34=00 且自动曝光状态时，二值化/Sobel 阈值跟随平均亮度查表自动联动，
    // 保证自动曝光调节亮度时各算法画面不随曝光/增益变化而剧烈漂移；
    // 手动状态（KEY4 长按切换）按键手动调，自动不覆盖。
    wire S_auto_en_24 = ~I_sw[2] && ~I_sw[3] && ~S_auto_manual;   //自动联动使能（24M 域）
    // 2026-11-03 AE 变化沿（自动状态下曝光/增益变化 → 重采背景，保证拨到检测模式时背景新鲜）
    reg [15:0] S_ae_d1, S_ag_d1;
    always @(posedge S_24m_clk or negedge S_rst_n) begin
        if(!S_rst_n) begin S_ae_d1 <= 16'd0; S_ag_d1 <= 16'd0; end
        else begin S_ae_d1 <= S_ae; S_ag_d1 <= S_ag; end
    end
    wire S_ae_chg = ((S_ae != S_ae_d1) || (S_ag != S_ag_d1)) && S_auto_en_24;  //仅自动状态有效
    //（2026-11-03 提交版：阈值联动自动调节已回退——实测跟随效果不好，改回纯手动；
    //  S_auto_en_24 保留给 AE 变化重采背景用）
    //实例化算法模式切换（KEY4 按下循环切换：原样→灰度）
    algo_mode_sel u_algo_mode_sel (
        .clk(S_24m_clk),
        .rst_n(S_rst_n),
        .key_pulse(S_key_pulse),
        .en(~I_sw[2] && ~I_sw[3]),   //2026-11-02 修复：算法切换仅原样模式（SW3SW4=00）。
                                      //检测模式（01/10/11）锁算法=原样：否则差分对 Sobel/灰度图
                                      //→ 全图全白，且切换回原样时画面错位
        .mode(S_algo_mode)
    );

    //实例化显示模式三态切换（区域填充功能：SW3SW4=11 时 KEY4 循环切换 涂白→边缘→原图）
    wire [1:0] S_disp_mode;   //显示模式（24M 域）：0=涂白(填充后) 1=边缘 2=原图
    disp_mode_sel u_disp_mode_sel (
        .clk(S_24m_clk),
        .rst_n(S_rst_n),
        .key_pulse(S_key_pulse),
        .en(I_sw[2] && I_sw[3]),
        .mode(S_disp_mode)
    );
    //实例化阈值调节（S_mode==2'd2 第3种模式时 KEY2/KEY3 调二值化阈值）
    threshold_set u_threshold_set (
        .I_clk(S_24m_clk),
        .I_rst(~S_rst_n),
        .I_inc_tick(S_inc_tick),
        .I_dec_tick(S_dec_tick),
        .I_enable(S_mode == 2'd2),
        .I_auto_en(1'b0),                   //提交版：阈值联动已回退，恒手动（2026-11-03）
        .I_auto_val(8'd0),
        .O_threshold(S_threshold)
    );
    //实例化 Sobel 阈值调节（S_mode==2'd3 第4种模式时 KEY2/KEY3 调 Sobel 阈值）
    sobel_threshold_set u_sobel_threshold_set (
        .I_clk(S_24m_clk),
        .I_rst(~S_rst_n),
        .I_inc_tick(S_inc_tick),
        .I_dec_tick(S_dec_tick),
        .I_enable(S_mode == 2'd3),
        .I_auto_en(1'b0),                   //提交版：阈值联动已回退，恒手动（2026-11-03）
        .I_auto_val(11'd0),
        .O_threshold(S_sobel_threshold)
    );
    
    //================ 调节曝光/增益（手动+自动合并，共享同一曝光值）================
   ae_set u_ae_set (
        .I_clk(S_24m_clk),
        .I_rst(~S_rst_n),
        .I_inc_tick(S_inc_tick),          //加长按（KEY2）
        .I_dec_tick(S_dec_tick),          //减长按（KEY3）
        .I_enable(~S_mode[1] && ((S_auto_manual && ~I_sw[3]) || I_sw[2])), //手动状态按键调曝光/增益：仅 00（SW4=0）或 SW3 高（10/11 功能模式现状）；01 检测模式冻结防漂移（2026-11-03 状态保持后补门控）
        .I_mode(S_mode[0]),             //0=调曝光，1=调增益
        .I_auto_en(S_auto_en_24),       //自动使能（仅原样模式 SW34=00 且自动状态；背景检测/框/填充模式冻结参数，防背景差分漂移）
        .I_avg(S_brightness_avg),       //平均亮度（像素域，跨时钟域在模块内做）
        .I_adjust(S_brightness_adjust), //调节脉冲（每10帧一个）
        .I_target(S_target),            //目标亮度
        .I_cam_cfg_done(S_cam_cfg_done),
        .I_ae_cfg_done(S_ae_cfg_done),
        .O_ae_req(S_ae_req),
        .O_ae(S_ae),
        .O_ag(S_ag)
    );
    //实例化目标亮度调节（自动模式下 S_mode 0 调目标亮度）
    target_set u_target_set (
        .I_clk(S_24m_clk),
        .I_rst(~S_rst_n),
        .I_inc_tick(S_inc_tick),
        .I_dec_tick(S_dec_tick),
        .I_enable(1'b0),  //2026-11-03 用户决策：目标亮度固定初值不再按键可调（自动状态按键全禁；手动状态 S_mode0 调曝光，双调目标会串）
        .O_target(S_target)
    );
    bin2bcd u_bin2bcd_ae (
        .bin(S_ae),      //曝光值（16位二进制）
        .bcd(S_bcd_ae)   //→ BCD
    );
    bin2bcd u_bin2bcd_ag (
        .bin(S_ag),      //增益值
        .bcd(S_bcd_ag)
    );
    bin2bcd u_bin2bcd_threshold (
        .bin({8'd0, S_threshold}),   //阈值（8位扩展成16位再转BCD）
        .bcd(S_bcd_threshold)         //→ 阈值BCD
    );
    bin2bcd u_bin2bcd_sobel_threshold (
        .bin({5'd0, S_sobel_threshold}),   //Sobel 阈值（手动可调实时值）
        .bcd(S_bcd_sobel_threshold)         //→ Sobel 阈值BCD
    );
    bin2bcd u_bin2bcd_target (
        .bin({8'd0, S_target}),   //目标亮度（8位扩展成16位再转BCD）
        .bcd(S_bcd_target)         //→ 目标亮度BCD
    );
    wire [17:0] S_dbg_rd_cnt;   //debug：每帧读总数（期望 0x2A300 = 172800）
    wire [17:0] S_dbg_wr_cnt;   //debug：每帧写总数（验证写侧提前结束：正常 2A300，少 3 = 2A2FD）
    wire        S_fifo_full_latch;  //诊断：采集 FIFO 满过锁存（LED4，写不准实锤）
    //数码管显示内容：按 S_mode 选（0=曝光/目标亮度 1=增益 2=二值化阈值 3=Sobel阈值）
    //（SW4 已恢复正式用途=背景采集，不再占数码管显示写计数 debug）
    reg [31:0] seg_data;
    always @(*) begin
        case(S_mode)
                2'd0 : seg_data = ((S_auto_manual || I_sw[2]) ? {16'hFFFF, S_bcd_ae} : {16'hFFFF, S_bcd_target});  //手动状态=曝光值 / 自动状态=目标亮度
                2'd1 : seg_data = {16'hFFFF, S_bcd_ag};        //增益
                2'd2 : seg_data = {16'hFFFF, S_bcd_threshold}; //二值化阈值
                2'd3 : seg_data = {16'hFFFF, S_bcd_sobel_threshold};  //Sobel 阈值
                default : seg_data = 32'hFFFFFFFF;   //未定义模式：全灭
            endcase
    end
    seg7 #(.CLK_FREQ(100_000_000), .SCAN_MS(1)) u_seg7 (
        .clk(S_100m_clk),      //100MHz 扫描
        .rst_n(S_rst_n),
        .data(seg_data),   //先固定值，验证 8 个数码管显示 1~8
        .seg(O_seg),
        .sel(O_sel)
    );
    //================ 模块例化：摄像头 I2C 配置（写寄存器表）================
    uicfgcs500_720p #(
        .CLK_DIV(24000000 / 100000 - 1)      //24MHz 分频到 100kHz I2C
    ) u_uicfgcs500 (
        .I_clk(S_24m_clk),                   //系统时钟输入
        .I_rst_n(S_rst_n),                   //系统复位输入
        .I_ae_req(S_ae_req),                 //曝光调节请求
        .I_ae(S_ae),                         //曝光值
        .I_ag(S_ag),                         //增益值
        .O_cam_scl(O_cam_scl),               //I2C 总线，SCL 时钟
        .IO_cam_sda(IO_cam_sda),             //I2C 总线，SDA 数据
        .O_cfg_done(S_cam_cfg_done),         //摄像头寄存器初始化完成
        .O_ae_cfg_done(S_ae_cfg_done)        //AE 配置完成
    );

    //================ 模块例化：MIPI DPHY 接收（硬核 IP）================
    // mipi_dphy_rx 模块：MIPI DPHY 接收器（物理层）。摄像头通过 MIPI 接口吐出来的是一对一对的高速差分信号（微小的电压差）
    //这个模块就是把这些差分信号「解码」成 FPGA 内部能用的并行数据（HS 字节流，从 O_hs_rx_data 出来）。
    mipi_dphy_rx_ph1p_mipiio_wrapper#(
        .DPHY_RX_LOCATION      ( "DPHY0" ),  //用 DPHY0
        .HS_EQUALIZER          ( "0dB"   ),  //均衡器
        .HS_VGA_GAIN           ( "8dB"   ),  //增益
        .LANE_NUM              ( 2       ),  //数据 lane（通道）数量 = 2
        .BYTE_NUM              ( 1       )   //每个 lane 每个时钟周期收 1 个字节（8 位）
    )u_mipi_dphy_rx_ph1p_mipiio_wrapper(
        .I_lp_clk              ( S_100m_clk       ),   //低速时钟
        .I_rst                 ( ~S_rst_n         ),   //复位

        .I_clk_lane_in_delay   ( 6'd0             ),   //时钟 lane 延迟
        .I_data_lane0_in_delay ( 6'd0             ),   //数据 lane0 延迟
        .I_data_lane1_in_delay ( 6'd0             ),
        .I_data_lane2_in_delay ( 6'd0             ),
        .I_data_lane3_in_delay ( 6'd0             ),

        .I_lane_invert         ( 4'b0000          ),   //lane 极性不翻转

        .O_hs_rx_clk           ( S_csi_rx_clk     ),   //恢复的像素时钟
        .O_hs_rx_valid         ( S_hs_rx_valid    ),   //HS 数据有效
        .O_hs_rx_data          ( S_hs_rx_data     ),   //HS 数据

        .O_lp_rx_lane0_p       (  ),                // LP 接收 lane0 差分（正）—— 悬空 = 没用 LP 接收
        .O_lp_rx_lane0_n       (  ),                //LP 接收 lane0 差分（负）—— 悬空 = 没用 LP 接收

        .I_lp_tx_en            ( 1'b0             ),// LP 发送使能 —— 固定 0 = 不发送 LP 数据
        .I_lp_tx_lane0_p       ( 1'b1             ),// LP 发送 lane0（正）—— 固定 1 = 空闲态（因为上面禁用发送了）
        .I_lp_tx_lane0_n       ( 1'b1             ),// LP 发送 lane0（负）—— 固定 1 = 空闲态（因为上面禁用发送了）

        .O_lane_match_error    (                  ),// lane 匹配错误标志 —— 悬空 = 没用到
        .O_lane_error          ( S_lane_error     ),   //lane 错误

        .IO_rx_clk_pad_n       ( IO_rx_clk_pad_n  ),   //MIPI 时钟差分（负）
        .IO_rx_clk_pad_p       ( IO_rx_clk_pad_p  ),   //MIPI 时钟差分（正）
        .IO_rx_data_pad_n      ( IO_rx_data_pad_n ),   //MIPI 数据差分（负）
        .IO_rx_data_pad_p      ( IO_rx_data_pad_p )    //MIPI 数据差分（正）
    );

    //================ 模块例化：CSI-2 协议解析 ================
    // 把 MIPI 字节流解析成像素字（32 位）+ 帧同步信号
    csi_unpacket_2lane u_csi_unpacket(
        .I_clk                 ( S_csi_rx_clk       ),
        .I_rst_n               ( S_rst_n       	  ),
        .I_hs_valid            ( S_hs_rx_valid     ),
        .I_hs_data             ( S_hs_rx_data      ),

        .O_csi_frame_start     ( S_csi_frame_start ),
        .O_csi_frame_end       ( S_csi_frame_end   ),
        .O_csi_valid           ( S_csi_valid       ),
        .O_csi_data            ( S_csi_data        )
    );

    //================ 模块例化：RAW10 解包 ================
    // 数据是以8位传输的，但是SC500 摄像头输出的是 RAW10 数据（10位），说以这个模块的作用就是将8位传过来的数据改回10位（4个数据用5次传输，4个0.8 4个0.2）
    raw10_unpacket_2lane u_raw10_unpacket (
        .I_clk  (S_csi_rx_clk),
        .I_rst_n(S_rst_n),

        .I_csi_frame_start(S_csi_frame_start),
        .I_csi_frame_end  (S_csi_frame_end),
        .I_csi_valid      (S_csi_valid),
        .I_csi_data       (S_csi_data),

        .O_raw10_frame_start(S_raw10_frame_start),
        .O_raw10_frame_end  (S_raw10_frame_end),
        .O_raw10_valid      (S_raw10_valid),
        .O_raw10_data       (S_raw10_data)
    );

    //================ 模块例化：转 AXI-Stream 流 ================
    //AXI-Stream 是一种「流水传输」协议，用 5 个信号描述一串连续的数据流：
    //tdata   数据本体
    //tvalid  发送端：数据有效（这一拍有数据）
    //tready  接收端：我能收（本工程多数恒 1 或不接）
    //tlast   一行的最后一个数据（行结束标志）
    //tuser   一帧的第一个数据（帧开始标志）
    uial2axis #(
        .IMG_WIDTH(1280),
        .IMG_HEIGHT(720),
        .INPUT_DATA_WIDTH(40)
    )
    u_uial2axis (
        .I_native_clk(S_csi_rx_clk),
        .I_rst_n     (S_rst_n),
        .I_data      (S_raw10_data       ),
        .I_data_valid(S_raw10_valid      ),
        .I_data_start(S_raw10_frame_start),
        .I_data_end  (S_raw10_frame_end  ),
        .axis_tvalid (S_axis_tvalid),
        .axis_tdata  (S_axis_tdata ),
        .axis_tuser  (S_axis_tuser ),
        .axis_tlast  (S_axis_tlast )
    );

    // SC500 已经输出原生 1280x720 RAW10，直接透传给 ISP（不做裁剪）
    assign S_raw_tdata  = S_axis_tdata;
    assign S_raw_tvalid = S_axis_tvalid;
    assign S_raw_tlast  = S_axis_tlast;
    assign S_raw_tuser  = S_axis_tuser;

    //================ 模块例化：ISP（去马赛克 + 白平衡）================
    //把摄像头传来的 RAW 原始数据，处理成能直接看的 RGB 彩色图像
    // ★ 这就是你要加算法（灰度/二值化/Sobel）的地方：在 isp_top 内部 AWB 之后
    isp_top u_isp_top (
        .axi4s_video_aclk(S_csi_rx_clk),
        .I_rst_n         (S_rst_n),
        .I_tlast         (S_raw_tlast	),
        .I_tuser         (S_raw_tuser	),
        .I_tdata         (S_raw_tdata	),
        .I_tvalid        (S_raw_tvalid	),
        .I_tdest         (),
        .I_algo_mode      (S_algo_mode),   //算法模式：0=原样 1=灰度 2=二值 3=Sobel
        .I_threshold      (S_threshold),   //二值化阈值
        .I_sobel_threshold(S_sobel_threshold), //Sobel 阈值
        .I_sw4            (I_sw[3]),   //SW4 模式选择低两位
        .I_sw3            (I_sw[2]),   //SW3 模式选择高两位（组合变化触发背景采集）
        .I_ae_chg         (S_ae_chg),  //2026-11-03 AE 变化沿（自动状态曝光/增益变化→重采背景）
        .I_bg_data        (96'd0), //背景 96 位输入（bg_read 已改消隐期读，不再输出 96 位流）
        .I_bg_valid       (1'b0),  //背景有效（bg_read 已改消隐期读，不再输出 96 位流）
        .I_bg_frame_start (1'b0),  //背景帧开始（bg_read 已改消隐期读，不再输出 96 位流）
        .O_tready        (S_ISP_O_tready),
        .O_tdata         (S_ISP_O_tdata ),
        .O_tlast         (S_ISP_O_tlast ),
        .O_tuser         (S_ISP_O_tuser ),
        .O_tvalid        (S_ISP_O_tvalid),
        .I_tready        (),
        .O_brightness_avg   (S_brightness_avg),   //平均亮度（自动曝光用）
        .O_brightness_adjust(S_brightness_adjust), //调节脉冲（自动曝光用）
        .O_bg_capture       (S_bg_capture),        //背景采集标志（给 video_in 背景写）
        .O_bg_captured      (S_bg_captured_isp),   //背景已采锁存（门控 bg_read 启动）
        .O_awb_tuser        (S_awb_tuser)          //AWB 帧开始（给背景读帧同步）
    );


    //================ 模块例化：video_in（ISP 输出 → 写 DDR）================
    //就是把 ISP 处理完的数据写进 DDR 内存
    //⚠️ 串行仲裁 grant 声明必须在此例化之前（HDL-7225 隐式网教训：先使用后声明 → TD 拆网接 0）
    wire S_vi_grant, S_vo_grant, S_bg_grant;   //串行仲裁时间片（写/显示读/背景读）
    video_in u_video_in(
        .I_rst_n              (  S_rst_n             ),

        .I_camera_clk         ( S_csi_rx_clk          ),   //摄像头侧时钟
        .I_camera_frame_start ( S_ISP_O_tuser  ),          //帧开始
        .I_camera_valid       ( S_ISP_O_tvalid ),          //有效
        .I_camera_data        ( S_ISP_O_tdata  ),          //数据（128 位）
        .I_mipi_rx_error      ( 1'b0			      ),
        .I_ae_cfg_done        ( S_ae_cfg_done         ),   //曝光配置完成（I2C写完，对齐跳帧时机）
        .I_auto_en            ( ~I_sw[2]              ),   //自动模式（SW3低），自动才跳帧、手动不跳帧防卡顿
        .I_bg_capture         ( S_bg_capture          ),   //背景采集标志（ISP 域，内部跨时钟域同步）
        .I_init_calib_done    ( S_init_calib_complete ),   //DDR 训练完成（复位重训后清采集 FIFO 残字）

        .I_ddr_clk            ( S_ddr_clk             ),   //DDR 侧时钟
		.I_display_pause      ( 1'b0                  ),
        .I_video_out_rd_busy  ( S_video_out_rd_busy   ),   //写避让读（恢复官方双向互斥）
        .I_wr_grant           ( S_vi_grant             ),   //写 grant：串行仲裁写时间片
        .O_wr_req             ( S_vi_wr_req           ),   //写请求（给仲裁器）
        .O_video_in_wr_busy   ( S_video_in_wr_busy    ),
        .O_video_out_rp       ( S_video_out_rp        ),
        .O_frame_start_ddr    ( S_frame_start_ddr     ),   //DDR 域帧开始（给 bg_read）
        .O_dbg_wr_cnt         ( S_dbg_wr_cnt          ),   //debug：每帧写总数（数码管显示）
        .O_fifo_full_latch    ( S_fifo_full_latch     ),   //诊断：采集 FIFO 满过（LED4）

        .O_ddr_user_wr_en     ( S_vi_ddr_wr_en        ),   //DDR 写使能
        .O_ddr_user_addr      ( S_vi_ddr_wr_addr      ),   //DDR 写地址
        .O_ddr_user_wr_data   ( S_vi_ddr_wr_data      ),   //DDR 写数据
        .I_ddr_user_ready     ( S_ddr_user_ready      )    //DDR 就绪
    );

    //================ 串行状态机仲裁（写批 → 显示读批 → 背景读批 轮转，批原子无交织）================
    // 每个状态服务一个完整 burst（240 拍），批未完成绝不切换——命令流严格串行。
    wire [1:0] S_ser_state;    //当前服务状态：0=写批 1=显示读批 2=背景读批
    ser_arbiter u_ser_arbiter (
        .I_clk      ( S_ddr_clk          ),
        .I_rst_n    ( S_rst_n            ),
        .I_vi_busy  ( S_vi_wr_req | S_vi_ddr_wr_en ),   //写批进行中（valid 展宽到写命令拍：wr_en 打 1 拍，valid 降拍后写命令还在发，展宽防仲裁切走后写读同拍）
        .I_vo_busy  ( S_video_out_rd_busy),   //显示读批进行中（trig|valid）
        .I_bg_busy  ( S_bg_rd_busy       ),   //背景读批进行中（含批边界空隙）
        .O_state    ( S_ser_state        ),
        .O_vi_grant ( S_vi_grant         ),
        .O_vo_grant ( S_vo_grant         ),
        .O_bg_grant ( S_bg_grant         )
    );

    //------------ 读命令标签 FIFO（读数据隔离，按读命令顺序路由读数据到对应 FIFO）------------
    // 读延迟不固定（bank 切换/刷新会变），用 grant 打固定拍对不齐。
    // 改用标签 FIFO：读命令发出时压入「来源标签」（显示读=1/背景读=0），读数据返回时弹出标签，
    // 读数据归属 = 弹出的标签。DDR 读命令和读数据顺序严格一致，天然对齐，与延迟拍数无关。
    // ⚠️ 深度必须 ≥ 最大在途读命令数：mc_to_user_interface 有 512 深命令 FIFO，
    //    bg 连续读灌满命令队列时在途读命令可达 512 + MC 内部延迟(约 40) 拍，
    //    原 64 深标签 FIFO 溢出 → 压弹错位 → 显示读数据路由全乱（花屏/撕裂根因）。
    // ⚠️ 2026-10-29 标签 FIFO 改 TD FIFO IP 实现（读延迟固定）：
    //   reg 数组实现会被 TD 综合成 BRAM → mem[rptr] 读延迟多 1 拍 → rd_tag 与 rd_valid_d1
    //   对齐错 1 拍 → bg 收数/ret_total 计数错 → 帧头误丢 1 字 → cur 数据左移 40 像素
    //   （实机水管涂白偏左+卷绕+白点根因；tb 的 reg 数组组合读 1 拍与实机 BRAM 不同 → tb 全绿实机错）。
    //   IP 读时序固定（NOREG：re 拍后 1 拍 dout）→ rd_tag = rd_valid 后 1 拍 = rd_valid_d1 对齐。
    //   深度 512 与 mc 命令队列同深：标签 FIFO 满前 mc 队列已先满拉低 ready → 命令停发 → 不溢出。
    wire [127:0] S_tag_dout;
    w128_d512_fifo u_rd_tag_fifo (
        .rst        ( ~S_rst_n              ),   //复位（高有效）
        .clkw       ( S_ddr_clk             ),   //写时钟（DDR 域）
        .we         ( S_ddr_user_rd_en      ),   //读命令发出拍压标签
        .di         ( {127'b0, S_vo_grant}  ),   //来源标签 = 命令发出拍的服务状态（VO=1/BG=0）
        .wrusedw    (),
        .afull      (),
        .full_flag  (),
        .clkr       ( S_ddr_clk             ),   //读时钟（同域）
        .re         ( S_ddr_user_rd_valid   ),   //返回落地拍弹标签
        .dout       ( S_tag_dout            ),
        .rdusedw    (),
        .valid      (),
        .empty_flag (),
        .aempty     ()
    );
    wire rd_tag = S_tag_dout[0];   //当前读数据的来源（1=显示读，0=背景读；re 后 1 拍与 rd_valid_d1 对齐）

    // DDR 读写信号复用（写优先；写拍精确门控——三轮下板血泪教训：写命令打 1 拍，写批 valid 降拍仲裁已切走，
    // 写命令尾拍与读命令同拍 → DDR 写优先吞读命令 → 标签 FIFO 压弹错位 → 显示错位/水管涂白/bg 读计数错乱全链崩）
    assign S_ddr_user_wr_en    = S_vi_ddr_wr_en && S_init_calib_complete;    // 写使能直连（官方同款）
    // 读使能：写命令拍强制关读（标签压同步关 → 压弹匹配；vo/bg 内部计数也同步关，见各自 grant/避让接线）
    assign S_ddr_user_rd_en    = (S_vo_ddr_rd_en || S_bg_rd_en) && !S_vi_ddr_wr_en && S_init_calib_complete;
    assign S_ddr_user_addr     = S_vi_ddr_wr_en ? S_vi_ddr_wr_addr :
                                 S_vo_ddr_rd_en ? S_vo_ddr_rd_addr :
                                 S_bg_rd_addr;  // 地址复用（写使能优先，撤销 grant 后按使能选）
    assign S_ddr_user_wr_data  = S_vi_ddr_wr_data;  // 写数据 = video_in 的写数据（直通）

    assign S_video_out_rst_n = S_hdmi_rst_n;        //video_out 复位跟着 HDMI 复位走

    //================ 模块例化：video_out（读 DDR → 显示）================
    //「读 DDR → 跨时钟域 → 解包成 24 位像素 → 按 HDMI 节奏送出」。它就是 video_in 的镜像，一个写、一个读，中间隔着 DDR 那片帧缓存。
    video_out u_video_out(
        .I_rst_n             ( S_video_out_rst_n    ),
        .I_ddr_clk           ( S_ddr_clk            ),

        .O_rd_req            ( S_vo_rd_req          ),   //读请求（给仲裁器）
        .I_rd_grant          ( S_vo_grant && !S_vi_ddr_wr_en ),   //读 grant：串行仲裁时间片 && 写拍门控（写命令拍撤 grant → vo 读计数/地址与 DDR 实际执行同步，防吞命令错位）
        .I_rd_tag            ( rd_tag               ),   //读数据来源标签（FIFO 写使能）
        .I_video_in_wr_busy  ( S_video_in_wr_busy   ),   //写忙避让（恢复官方，读写命令不交织）
        .O_video_out_rd_busy ( S_video_out_rd_busy  ),
        .O_fifo_level        ( S_vo_fifo_level      ),   //等效水位（给 bg_read 读门控，双阈值错峰防花屏）
        .O_dbg_rd_cnt        ( S_dbg_rd_cnt         ),   //debug：每帧读总数（数码管显示）
        .I_video_out_rp      ( S_video_out_rp       ),

        .O_ddr_user_rd_en    ( S_vo_ddr_rd_en       ),   //DDR 读使能
        .O_ddr_user_addr     ( S_vo_ddr_rd_addr     ),   //DDR 读地址
        .I_ddr_user_ready    ( S_ddr_user_ready     ),
        .I_ddr_user_rd_valid ( S_ddr_user_rd_valid  ),
        .I_ddr_user_rd_data  ( S_ddr_user_rd_data   ),

        .I_dsi_clk           ( S_hdmi_pixel_clk     ),   //HDMI 像素时钟
        .I_video_vsync       ( S_video_out_vsync    ),
        .I_video_rd_en       ( S_hdmi_window_rd_en  ),   //读使能（什么时候读像素）
        .O_vdieo_data        ( S_video_rd_data      )    //读出的像素（24 位）
    );

    //================ 模块例化：bg_read（消隐期读状态机：读当前帧+背景帧 → 比较 → 写前景标记 ERAM）================
    // ⚠️ S_bg_frame_start_ddr 必须先声明后使用（TD 对「先使用后声明 + 带初始化 wire」会拆成两个网，
    //    隐式网无驱动被接 0 → bg_read 的 I_frame_start 恒 0 读永不启动；iverilog 会合并所以仿真正常）
    //=========== 显示期电平跨域（S_hdmi_de → DDR 域，bg 读消隐期放行门控用）===========
    // 消隐期 vo 不消耗 FIFO → 水位冻结在显示期末值（可能落在 200~300 死锁带）→ 水位门控把 bg 饿死整个消隐期。
    // de 打 3 拍作为「显示期窗口」：显示期才做水位门控，消隐期 bg 全速读。
    reg S_de_s1, S_de_s2, S_de_s3;
    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n) begin
            S_de_s1 <= 1'b0;
            S_de_s2 <= 1'b0;
            S_de_s3 <= 1'b0;
        end else begin
            S_de_s1 <= S_hdmi_de;
            S_de_s2 <= S_de_s1;
            S_de_s3 <= S_de_s2;
        end
    end
    wire S_disp_win = S_de_s3;   //显示期电平（DDR 域）

    wire S_bg_frame_start_ddr;
    // 2026-11-03 用户决策：背景差分阈值固定 40（原亮度自适应查表删除——SW1/SW2 管显示模式，
    // 阈值无人调、OSD 也没位置显示；S_brightness_avg 仍供 ae_set 自动曝光用）
    bg_read u_bg_read(
        .I_disp_mode         ( S_disp_mode_ddr     ),   //显示模式三态（DDR 域同步后）：0=涂白 1=边缘 2=原图
        .I_fill_en           ( S_fill_en_ddr       ),   //区域填充模式使能（SW3&&SW4，DDR 域）
        .I_rst_n             ( S_rst_n             ),
        .I_ddr_clk           ( S_ddr_clk           ),
        .I_frame_start       ( S_bg_frame_start_ddr ),   //帧开始（vsync 打拍，DDR 域）：启动本帧读（诊断：仅模式3）
        .I_video_out_rp      ( S_video_out_rp      ),   //读指针（当前帧所在乒乓块）
        .I_bg_grant          ( S_bg_grant          ),   //串行仲裁背景读时间片
        .I_rd_tag            ( rd_tag              ),   //读返回来源标签（1=显示读 0=背景读）
        .I_vo_fifo_level     ( S_vo_fifo_level     ),   //video_out 等效水位（显示期 >=300 才读，防挤垮显示）
        .I_disp_win          ( S_disp_win          ),   //显示期电平（消隐期水位门控放行，防 bg 饿死）
        .I_video_in_wr_busy  ( S_vi_ddr_wr_en      ),   //写命令拍精确避让（写批 valid 降拍后写命令仍发 1 拍，本拍 bg 读被写优先吞 → 计数/标签错位全链根因）
        .I_thr_sel           ( 2'd2                 ),   //2026-11-03 固定 40 档（用户决策：阈值固定，亮度自适应删除）
        .I_ddr_user_ready    ( S_ddr_user_ready    ),
        .I_ddr_user_rd_valid ( S_ddr_user_rd_valid ),
        .I_ddr_user_rd_data  ( S_ddr_user_rd_data  ),
        .O_ddr_user_rd_en    ( S_bg_rd_en          ),
        .O_ddr_user_addr     ( S_bg_rd_addr        ),
        .O_bg_rd_busy        ( S_bg_rd_busy        ),   //背景读批进行中（串行仲裁）
        .O_fg_wr_addr        ( S_fg_wr_addr        ),   //前景标记 ERAM 写地址
        .O_fg_wr_data        ( S_fg_wr_data        ),   //前景标记 ERAM 写数据
        .O_fg_wr_en          ( S_fg_wr_en          ),   //前景标记 ERAM 写使能
        .O_fg_init           ( S_fg_init           ),   //首轮写满标志（叠加使能）
        .O_dbg_rd_cnt        ( S_fg_dbg_rd_cnt     ),   //debug：本帧读总数
        .O_dbg_first_addr    ( S_dbg_first_addr    ),   //debug：首字写拍地址（串口诊断）
        .O_dbg_first_data    ( S_dbg_first_data    ),   //debug：首字写拍数据（错位拍数诊断）
        .O_dbg_first_half    ( S_dbg_first_half    ),   //debug：首字写拍半帧
        .O_dbg_first_valid   ( S_dbg_first_valid   ),   //debug：首字写拍锁存脉冲
        .O_fs_pulse          ( S_fs_pulse          ),   //帧开始延迟512拍脉冲（bbox_stat 帧边界）
        .O_half_sel          ( S_half_sel          )    //段选择（bbox_stat 统计分组）
    );

    //================ 模块例化：bbox_stat（外接框/质心/跟踪统计，挂在 bg_read 写流上）================
    // 写流三件套直连 bg_read 输出（写拍语义：addr=本字实际 ERAM 地址、data=40 像素标记），
    // 帧边界 = S_fs_d512（写流已静默）、分组 = S_half_sel（三段轮转）。纯寄存器+加法器，零存储开销。
    bbox_stat u_bbox_stat (
        .I_clk         ( S_ddr_clk      ),   //DDR 域时钟
        .I_rst_n       ( S_rst_n        ),
        .I_wr_en       ( S_fg_wr_en     ),   //写流使能（bg_read O_fg_wr_en）
        .I_wr_addr     ( S_fg_wr_addr   ),   //写流地址
        .I_wr_data     ( S_fg_wr_data   ),   //写流数据
        .I_fs_pulse    ( S_fs_pulse     ),   //帧开始脉冲（bg_read S_fs_d512）
        .I_half_sel    ( S_half_sel     ),   //段选择
        .O_valid       ( S_bbox_valid   ),   //统计有效
        .O_min_x       ( S_bbox_min_x   ),   //外接框左边界
        .O_max_x       ( S_bbox_max_x   ),   //外接框右边界
        .O_min_y       ( S_bbox_min_y   ),   //外接框上边界
        .O_max_y       ( S_bbox_max_y   ),   //外接框下边界
        .O_cx          ( S_bbox_cx      ),   //质心 X
        .O_cy          ( S_bbox_cy      ),   //质心 Y
        .O_dir_dx      ( S_bbox_dir_dx  ),   //方向块偏移 X
        .O_dir_dy      ( S_bbox_dir_dy  ),   //方向块偏移 Y
        .O_dir_valid   ( S_bbox_dir_valid ), //方向有效
        .O_cnt         ( S_bbox_cnt     )    //标记像素总数（诊断）
    );

    //================ UART 诊断发送（24M 域，帧开始触发，2026-10-29 错位串口诊断）================
    // 帧开始脉冲（DDR 域）打 2 拍跨到 24M 域取上升沿 → 每帧发 12 字节诊断帧（消隐期发完）
    reg S_fs24_s1, S_fs24_s2, S_fs24_s3;
    always @(posedge S_24m_clk or negedge S_rst_n) begin
        if(!S_rst_n) begin
            S_fs24_s1 <= 1'b0; S_fs24_s2 <= 1'b0; S_fs24_s3 <= 1'b0;
        end else begin
            S_fs24_s1 <= S_frame_start_ddr;
            S_fs24_s2 <= S_fs24_s1;
            S_fs24_s3 <= S_fs24_s2;
        end
    end
    wire S_uart_send = S_fs24_s2 && ~S_fs24_s3;   //帧开始上升沿（打 2 拍后）
    uart_dbg_tx u_uart_dbg (
        .I_clk        ( S_24m_clk                    ),
        .I_rst_n      ( S_rst_n                      ),
        .I_send_pulse ( S_uart_send                  ),
        .I_b0         ( 8'hAA                        ),   //帧头
        .I_b1         ( 8'h55                        ),
        .I_b2         ( {7'd0, S_dbg_first_half}     ),   //首字写拍所在半帧（0=A 1=B）
        .I_b3         ( {7'd0, S_fg_init}            ),   //ERAM 首轮写满
        .I_b4         ( S_dbg_first_addr[7:0]        ),   //首字写拍地址低 8（A 半应 0x00 / B 半应 0x00）
        .I_b5         ( {2'd0, S_dbg_first_valid, S_dbg_first_half, S_dbg_first_addr[14:8]} ),   //高 7 位 + 标志
        .I_b6         ( S_fg_dbg_rd_cnt[7:0]         ),   //读总数低 8
        .I_b7         ( S_fg_dbg_rd_cnt[15:8]        ),   //读总数中 8
        .I_b8         ( {5'd0, S_fg_dbg_rd_cnt[18:16]} ), //读总数高 3
        .I_b9         ( {7'd0, I_sw[3]}              ),   //SW4 状态
        .I_b10        ( 8'd0                         ),   //预留
        .I_b11        ( 8'hEE                        ),   //帧尾
        .O_tx         ( S_uart_tx                    ),
        .O_busy       (                              )
    );

    //================ vsync 跨域打拍（DDR 域，给 bg_read 帧开始脉冲）================
    reg S_vsync_s1, S_vsync_s2, S_vsync_s3;
    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n) begin
            S_vsync_s1 <= 1'b0; S_vsync_s2 <= 1'b0; S_vsync_s3 <= 1'b0;
        end else begin
            S_vsync_s1 <= S_video_out_vsync;
            S_vsync_s2 <= S_vsync_s1;
            S_vsync_s3 <= S_vsync_s2;
        end
    end
    wire S_vsync_pulse_ddr = S_vsync_s2 && ~S_vsync_s3;   //vsync 上升沿（DDR 域）

    //------------ 诊断：算法模式跨域（bg 读仅在模式3使能，二分隔离 bg 参与对显示的影响）------------
    reg [2:0] S_algo_mode_ddr_1, S_algo_mode_ddr_2;
    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n) begin
            S_algo_mode_ddr_1 <= 3'd0; S_algo_mode_ddr_2 <= 3'd0;
        end else begin
            S_algo_mode_ddr_1 <= S_algo_mode;
            S_algo_mode_ddr_2 <= S_algo_mode_ddr_1;
        end
    end

    //=========== SW4 背景采集电平 → DDR 域同步（bg_read 启动门控）===========
    // 原「仅模式3启动bg读」为调试期隔离残留——正式用途 = SW4 拨下采背景后，
    // bg_read 消隐期读两帧做差写 ERAM（原样模式下，与 KEY4 算法模式无关）
    reg S_sw4_ddr_1, S_sw4_ddr_2;
    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n) begin
            S_sw4_ddr_1 <= 1'b0;
            S_sw4_ddr_2 <= 1'b0;
        end else begin
            S_sw4_ddr_1 <= I_sw[3];
            S_sw4_ddr_2 <= S_sw4_ddr_1;
        end
    end

    //=========== 显示模式三态跨域（24M 域 → DDR 域，格雷码防采中间态闪错）===========
    // disp_mode 2bit 循环 0→1→2→0，二进制跨值可能两 bit 同时变（如 01→10），
    // 格雷码一次只变 1 位，DDR 域打 2 拍解码（与 hdmi_mixer 里 algo_mode 同款做法）。
    wire [1:0] S_disp_mode_gray;
    assign S_disp_mode_gray = {S_disp_mode[1], S_disp_mode[0] ^ S_disp_mode[1]};
    reg [1:0] S_disp_mode_g1, S_disp_mode_g2;
    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n) begin
            S_disp_mode_g1 <= 2'd0;
            S_disp_mode_g2 <= 2'd0;
        end else begin
            S_disp_mode_g1 <= S_disp_mode_gray;
            S_disp_mode_g2 <= S_disp_mode_g1;
        end
    end
    wire [1:0] S_disp_mode_ddr;
    assign S_disp_mode_ddr[1] = S_disp_mode_g2[1];
    assign S_disp_mode_ddr[0] = S_disp_mode_g2[1] ^ S_disp_mode_g2[0];

    //=========== SW3 电平 → DDR 域同步（区域填充模式使能 = SW3&&SW4）===========
    reg S_sw3_ddr_1, S_sw3_ddr_2;
    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n) begin
            S_sw3_ddr_1 <= 1'b0;
            S_sw3_ddr_2 <= 1'b0;
        end else begin
            S_sw3_ddr_1 <= I_sw[2];
            S_sw3_ddr_2 <= S_sw3_ddr_1;
        end
    end
    wire S_fill_en_ddr;
    assign S_fill_en_ddr = S_sw3_ddr_2 && S_sw4_ddr_2;   //区域填充模式使能（SW3&&SW4，DDR 域）

    //背景已采锁存跨域（ISP 像素域 → DDR 域，门控 bg_read 启动：采完才跑检测）
    reg S_bg_captured_ddr_1, S_bg_captured_ddr_2;
    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n) begin
            S_bg_captured_ddr_1 <= 1'b0;
            S_bg_captured_ddr_2 <= 1'b0;
        end else begin
            S_bg_captured_ddr_1 <= S_bg_captured_isp;
            S_bg_captured_ddr_2 <= S_bg_captured_ddr_1;
        end
    end

    // SW4 或 SW3 拨下才启动 bg 读，且必须「背景已采」——否则用上电随机背景立即差出满屏乱涂白，
    // 视觉上像「延迟 1 秒没生效」（防抖只推迟采集，bg_read 此前照样开跑用旧背景）
    assign S_bg_frame_start_ddr = S_vsync_pulse_ddr && (S_sw4_ddr_2 || S_sw3_ddr_2) && S_bg_captured_ddr_2;   //（声明已前移到 bg_read 例化前）

    //（2026-11-03 提交版：snapshot_tx 采集旁路已移除，uart_tx 恢复纯诊断帧）
    assign uart_tx = S_uart_tx;

    //=========== 诊断 v2：bg 读启动链四信号锁存（SW4 拨下后数码管高 4 位直读断点）===========
    // [最高位] S_sw4_ddr_2：SW4 电平到达 DDR 域（1=到了）
    // [次位]   S_diag_vsync_latch：复位后见过 vsync 脉冲（1=vsync 链通）
    // [三位]   S_diag_bg_active_latch：bg 读状态机 active 过（1=frame_start 已置位）
    // [末位]   S_diag_bg_grant_latch：仲裁给过 bg 时间片（1=ser_arbiter 轮转正常）
    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n) begin
            S_diag_vsync_latch     <= 1'b0;
            S_diag_bg_active_latch <= 1'b0;
            S_diag_bg_grant_latch  <= 1'b0;
        end else begin
            if(S_vsync_pulse_ddr)  S_diag_vsync_latch     <= 1'b1;
            if(S_bg_rd_busy)       S_diag_bg_active_latch <= 1'b1;
            if(S_bg_grant)         S_diag_bg_grant_latch  <= 1'b1;
        end
    end

    //=========== 首字写拍地址诊断（2026-10-29 串口改数码管）：锁存 B 半首字写拍地址 ===========
    // 判读：SW4 拨下数码管低 4 位应显示 1600（5632=B 半首字）；非预期值 = 写地址时序错位实锤
    reg [14:0] S_dbg_first_latch;
    reg [39:0] S_dbg_first_data_latch;
    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n) begin
            S_dbg_first_latch <= 15'd0;
            S_dbg_first_data_latch <= 40'd0;
        end
        else if(S_dbg_first_valid && S_dbg_first_half) begin
            S_dbg_first_latch <= S_dbg_first_addr;   //只锁 B 半（稳定显示）
            S_dbg_first_data_latch <= S_dbg_first_data;   //首字内容（错位拍数诊断）
        end
    end
    reg [14:0] S_dbg_first_s1, S_dbg_first_s2;
    reg [3:0]  S_dbg_first_data_s1, S_dbg_first_data_s2;
    always @(posedge S_24m_clk or negedge S_rst_n) begin
        if(!S_rst_n) begin
            S_dbg_first_s1 <= 15'd0;
            S_dbg_first_s2 <= 15'd0;
            S_dbg_first_data_s1 <= 4'd0;
            S_dbg_first_data_s2 <= 4'd0;
        end else begin
            S_dbg_first_s1 <= S_dbg_first_latch;
            S_dbg_first_s2 <= S_dbg_first_s1;
            S_dbg_first_data_s1 <= S_dbg_first_data_latch[3:0];
            S_dbg_first_data_s2 <= S_dbg_first_data_s1;
        end
    end


    //================ 前景标记 ERAM 首轮写满跨域（DDR → HDMI，叠加使能）================
    reg S_fg_init_s1, S_fg_init_s2, S_fg_init_s3;
    always @(posedge S_hdmi_pixel_clk) begin
        S_fg_init_s1 <= S_fg_init;
        S_fg_init_s2 <= S_fg_init_s1;
        S_fg_init_s3 <= S_fg_init_s2;
    end
    assign S_fg_init_hdmi = S_fg_init_s3;

    //================ 模块例化：前景标记 ERAM（40bit×23040 = 45 块，主线正式接线）================
    // A 口（DDR 域 100M）：消隐期 bg_read 写前景标记；B 口（HDMI 域 75M）：显示期 hdmi_mixer 读前景标记叠加。
    fg_mark_eram u_fg_mark_eram (
        .I_clka ( S_ddr_clk         ),   //写时钟（DDR 域，消隐期写）
        .I_addra( S_fg_wr_addr      ),   //写地址（bg_read 输出）
        .I_dia  ( S_fg_wr_data      ),   //写数据（bg_read 输出，40 像素前景标记）
        .I_wea  ( S_fg_wr_en        ),   //写使能（bg_read 输出）
        .I_clkb ( S_hdmi_pixel_clk  ),   //读时钟（HDMI 域，显示期读）
        .I_addrb( S_fg_rd_addr      ),   //读地址（hdmi_mixer 输出）
        .O_dob  ( S_fg_rd_data      )    //读数据（给 hdmi_mixer 叠加）
    );

    //================ 模块例化：用户接口 → 内存控制器接口 ================
    mc_to_user_interface u_mc_to_user_interface(
        .I_clk                   ( S_ddr_clk               ),
        .I_rst_n                 ( S_rst_n                 ),

        .I_ddr_user_wr_en        ( S_ddr_user_wr_en        ),
        .I_ddr_user_rd_en        ( S_ddr_user_rd_en        ),
        .I_ddr_user_addr         ( S_ddr_user_addr         ),
        .I_ddr_user_wr_data      ( S_ddr_user_wr_data      ),
        .O_ddr_user_ready        ( S_ddr_user_ready        ),
        .O_ddr_user_rd_valid     ( S_ddr_user_rd_valid     ),
        .O_ddr_user_rd_data      ( S_ddr_user_rd_data      ),

        .O_mc_app_en             ( S_mc_app_en             ),
        .O_mc_app_addr           ( S_mc_app_addr           ),
        .O_mc_app_cmd            ( S_mc_app_cmd            ),
        .I_mc_app_rdy            ( S_mc_app_rdy            ),
        .O_mc_app_wdf_wren       ( S_mc_app_wdf_wren       ),
        .O_mc_app_wdf_data       ( S_mc_app_wdf_data       ),
        .O_mc_app_wdf_end        ( S_mc_app_wdf_end        ),
        .O_mc_app_wdf_mask       ( S_mc_app_wdf_mask       ),
        .I_mc_app_wdf_rdy        ( S_mc_app_wdf_rdy        ),
        .I_mc_app_rd_data        ( S_mc_app_rd_data        ),
        .I_mc_app_rd_data_end    ( S_mc_app_rd_data_end    ),
        .I_mc_app_rd_data_valid  ( S_mc_app_rd_data_valid  )
    );

    //================ DDR 参考时钟：100MHz 差分晶振（K5/L5）→ 差分转单端（IBUF_DIFF）================
    // SIT9121 LVDS 差分晶振（100MHz）经 IBUF_DIFF 转单端给 DDR ref_clk，满速 1066Mbps。
    // DIFF_TERM=TRUE 片内端接（R262 未焊，靠片内端接）。
    //================ 模块例化：DDR 控制器（硬核 IP）================
    // 满速模式：ref_clk 用 100M 差分晶振（K5/L5），内存 1066Mbps，usr_clk 133.3M
    ph1p35_324_ddr_wrapper u_ph1p35_324_ddr_wrapper(
        .I_sys_clk              ( I_sys_clk             ),   //DDR ref_clk 50M（与官方同款：共用 C4 晶振）
        .I_sys_rst_n            ( S_rst_n                ),

        .O_ddr_clk              ( S_ddr_clk              ),   //DDR 时钟
        .O_init_calib_complete  ( S_init_calib_complete  ),   //初始化校准完成
        .I_mc_app_addr          ( S_mc_app_addr          ),
        .I_mc_app_cmd           ( S_mc_app_cmd           ),
        .I_mc_app_en            ( S_mc_app_en            ),
        .I_mc_app_wdf_data      ( S_mc_app_wdf_data      ),
        .I_mc_app_wdf_end       ( S_mc_app_wdf_end       ),
        .I_mc_app_wdf_mask      ( S_mc_app_wdf_mask      ),
        .I_mc_app_wdf_wren      ( S_mc_app_wdf_wren      ),
        .O_mc_app_rd_data       ( S_mc_app_rd_data       ),
        .O_mc_app_rd_data_end   ( S_mc_app_rd_data_end   ),
        .O_mc_app_rd_data_valid ( S_mc_app_rd_data_valid ),
        .O_mc_app_rdy           ( S_mc_app_rdy           ),
        .O_mc_app_wdf_rdy       ( S_mc_app_wdf_rdy       ),

        .ddr_addr               ( ddr_addr               ),
        .ddr_ba                 ( ddr_ba                 ),
        .ddr_cke                ( ddr_cke                ),
        .ddr_odt                ( ddr_odt                ),
        .ddr_cs_n               ( ddr_cs_n               ),
        .ddr_ras_n              ( ddr_ras_n              ),
        .ddr_cas_n              ( ddr_cas_n              ),
        .ddr_we_n               ( ddr_we_n               ),
        .ddr_ck_p               ( ddr_ck_p               ),
        .ddr_ck_n               ( ddr_ck_n               ),
        .ddr_dm                 ( ddr_dm                 ),
        .ddr_dq                 ( ddr_dq                 ),
        .ddr_dqs_p              ( ddr_dqs_p              ),
        .ddr_dqs_n              ( ddr_dqs_n              )
    );

    //================ 模块例化：HDMI 时序控制器（行场同步）================
    uivtc #(
        .H_ActiveSize ( 1280 ),   //一行有效像素
        .H_FrameSize  ( 1650 ),   //一行总像素（含消隐）
        .H_SyncStart  ( 1390 ),   //行同步开始
        .H_SyncEnd    ( 1430 ),   //行同步结束
        .V_ActiveSize ( 720  ),   //一帧有效行
        .V_FrameSize  ( 750  ),   //一帧总行数
        .V_SyncStart  ( 725  ),   //场同步开始
        .V_SyncEnd    ( 730  )    //场同步结束
    )u_hdmi_vtc(
        .I_vtc_rstn    ( S_hdmi_rst_n    ),
        .I_vtc_clk     ( S_hdmi_pixel_clk ),
        .O_vtc_vs      ( S_hdmi_vsync     ),
        .O_vtc_hs      ( S_hdmi_hsync     ),
        .O_vtc_de_valid( S_hdmi_de        ),
        .O_vtc_user    ( S_hdmi_user      ),
        .O_vtc_last    ( S_hdmi_last      )
    );

    //================ 模块例化：HDMI 混叠（时序对齐 + 读 DDR 像素）================
    //将数据帧生成
    hdmi_mixer #(
        .H_OFFSET   ( 0    ),
        .V_OFFSET   ( 0    ),
        .IMG_WIDTH  ( 1280 ),
        .IMG_HEIGHT ( 720  ),
        .DEBUG_MODE ( 0    )   //正常模式，显示 SC500 1280x720 画面
    )u_hdmi_mixer(
        .I_clk           ( S_hdmi_pixel_clk   ),
        .I_rst_n         ( S_hdmi_rst_n       ),
        .I_video_vsync   ( S_hdmi_vsync       ),
        .I_video_hsync   ( S_hdmi_hsync       ),
        .I_video_de      ( S_hdmi_de          ),
        .I_video_user    ( S_hdmi_user        ),
        .I_video_last    ( S_hdmi_last        ),
        .I_debug_status  ( 4'd0 ),
        .I_ae            ( S_ae ),          //曝光值
        .I_ag            ( S_ag ),          //增益值
        .I_algo_mode      ( S_algo_mode ),   //算法模式：0=原样 1=灰度 2=二值 3=Sobel
        .I_threshold      ( S_threshold ),   //二值化阈值
        .I_sobel_threshold( S_sobel_threshold ), //Sobel 阈值
        .I_auto_mode      ( ~I_sw[2] && ~I_sw[3] && !S_auto_manual ),      //自动曝光标志（SW34=00 且 KEY4 状态=自动，与 ae_set 使能一致）
        .I_am_sel         ( S_auto_manual ),      //2026-11-03 自动/手动状态（行11「当前模式」专用，123 模式锁自动显示「自动」）
        .I_target         ( S_target ),      //目标亮度
        .I_sw3            ( I_sw[2]            ),       //SW3 拨码电平（OSD 功能模式提示）
        .I_sw4            ( I_sw[3] && S_bg_captured_ddr_2 ),       //SW4 实时电平 && 本次背景已采（涂白叠加使能：防采集等待期旧标记残影）
        .I_bg_captured    ( S_bg_captured_latch ),     //背景已采集锁存（仅 OSD「已采」文字显示）
        .O_fg_rd_addr     ( S_fg_rd_addr      ),   //前景标记 ERAM 读地址
        .I_fg_rd_data     ( S_fg_rd_data      ),   //前景标记 ERAM 读数据（40 像素标记）
        .I_fg_init        ( S_fg_init_hdmi    ),   //ERAM 首轮写满（叠加使能）
        .I_bbox_valid     ( S_bbox_valid      ),   //外接框统计有效
        .I_bbox_min_x     ( S_bbox_min_x      ),   //外接框左边界
        .I_bbox_max_x     ( S_bbox_max_x      ),   //外接框右边界
        .I_bbox_min_y     ( S_bbox_min_y      ),   //外接框上边界
        .I_bbox_max_y     ( S_bbox_max_y      ),   //外接框下边界
        .I_bbox_cx        ( S_bbox_cx         ),   //质心 X
        .I_bbox_cy        ( S_bbox_cy         ),   //质心 Y
        .I_bbox_dir_dx    ( S_bbox_dir_dx     ),   //方向块偏移 X（有符号）
        .I_bbox_dir_dy    ( S_bbox_dir_dy     ),   //方向块偏移 Y（有符号）
        .I_bbox_dir_valid ( S_bbox_dir_valid  ),   //方向有效
        .O_video_rd_en   ( S_hdmi_window_rd_en),   //读窗口使能
        .I_video_rd_data ( S_video_rd_data    ),   //读出的像素
        .O_hdmi_vsync    ( S_hdmi_out_vsync   ),
        .O_hdmi_hsync    ( S_hdmi_out_hsync   ),
        .O_hdmi_de       ( S_hdmi_out_de      ),
        .O_hdmi_data     ( S_hdmi_out_data    )    //HDMI 输出（24 位 RGB）
    );

    //================ 模块例化：HDMI TMDS 发送（编码 + 串行输出）================
    //将数据帧发送
    hdmi_tx u_hdmi_tx(
        .I_pixel_clk        ( S_hdmi_pixel_clk  ),
        .I_serial_clk       ( S_hdmi_serial_clk ),
        .I_rst              ( ~S_hdmi_rst_n     ),
        .I_key_in           ( 1'b0              ),
        .I_edid_read_trig   ( 1'b0              ),
        .O_edid_read_valid  (                   ),
        .O_edid_read_data   (                   ),
        .I_video_rgb_enable ( 1'b1              ),   //使能 RGB 视频
        .I_video_in_vs      ( S_hdmi_out_vsync  ),
        .I_video_in_de      ( S_hdmi_out_de     ),
        .I_video_in_user    ( 1'b0              ),
        .I_video_in_valid   ( 1'b0              ),
        .I_video_in_last    ( 1'b0              ),
        .O_video_in_ready   (                   ),
        .I_video_in_data    ( S_hdmi_out_data   ),   //HDMI 视频数据
        .I_audio_valid      ( 1'b0              ),
        .I_audio_left_data  ( 24'd0             ),
        .I_audio_right_data ( 24'd0             ),
        .I_i2s_BCLK         ( 1'b0              ),
        .I_i2s_LRCK         ( 1'b0              ),
        .I_i2s_DOUT         ( 1'b0              ),
        .O_ddc_scl          (                   ),
        .O_hdmi_clk_p       (                   ),
        .O_hdmi_tx_p        (                   ),
        .O_tmds_ch0_p       ( O_tmds_ch0_p      ),   //TMDS 通道 0
        .O_tmds_ch1_p       ( O_tmds_ch1_p      ),   //TMDS 通道 1
        .O_tmds_ch2_p       ( O_tmds_ch2_p      ),   //TMDS 通道 2
        .O_tmds_clk_p       ( O_tmds_clk_p      )    //TMDS 时钟
    );

endmodule
