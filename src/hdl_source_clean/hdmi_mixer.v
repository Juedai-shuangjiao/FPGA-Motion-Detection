//========================================================
// 模块：hdmi_mixer —— HDMI 混叠（时序对齐 + 读 DDR 像素）
// 功能：把 HDMI 时序（vsync/hsync/de）和从 DDR 读出的像素对齐，输出给 hdmi_tx。
//       带 DEBUG_MODE 三种调试显示模式（彩条/调试状态/分块），默认 0 = 正常透传。
// ★ OSD 插入点：在 DEBUG_MODE=0 的 else 分支（O_hdmi_data <= S_video_data_2d 处），
//   这里可以叠加 Logo/字符（判断当前坐标是否在 Logo 区域，是则覆盖像素）。
//========================================================
module hdmi_mixer #(
    parameter H_OFFSET = 128,       //水平偏移（未用）
    parameter V_OFFSET = 60,        //垂直偏移（未用）
    parameter IMG_WIDTH = 1920,     //图像宽度
    parameter IMG_HEIGHT = 1080,    //图像高度
    parameter integer DEBUG_MODE = 0  //调试模式：0=正常透传 1=彩条 2=调试状态 3=分块
)(
    input wire        I_clk,          //HDMI 像素时钟
    input wire        I_rst_n,        //复位，低有效

    input wire        I_video_vsync,  //场同步
    input wire        I_video_hsync,  //行同步
    input wire        I_video_de,     //数据有效
    input wire        I_video_user,   //帧开始
    input wire        I_video_last,   //行结束

    input wire[3:0]   I_debug_status, //调试状态（DEBUG_MODE 用）
    input wire[15:0]  I_ae,           //曝光值（16位，来自 ae_set）
    input wire[15:0]  I_ag,           //增益值（16位，来自 ae_set）
    input wire[2:0]   I_algo_mode,    //算法模式：0=原样 1=灰度 2=二值 3=Sobel（来自 algo_mode_sel）
    input wire[7:0]   I_threshold,    //二值化阈值（0~255，用于OSD显示）
    input wire[10:0]  I_sobel_threshold, //Sobel 阈值（0~2040，用于OSD显示）
    input wire        I_auto_mode,    //自动曝光标志（1=自动，0=手动，用于OSD显示）
    input wire        I_am_sel,       //2026-11-03 自动/手动状态（auto_manual_sel 直出，行11「当前模式」专用——123 模式锁自动仍显示「自动」）
    input wire[7:0]   I_target,       //目标亮度（0~255，自动曝光用，用于OSD显示）
    input wire        I_sw3,          //SW3：拨码电平（功能模式选择，用于OSD功能提示）
    input wire        I_sw4,          //SW4：实时拨码电平（1=拨下，涂白叠加使能）
    input wire        I_bg_captured,  //背景已采集锁存（采过一次=1，仅 OSD「已采」显示用）
    output wire[14:0] O_fg_rd_addr,   //前景标记 ERAM 读地址（40 像素/字）
    input wire[39:0]  I_fg_rd_data,   //前景标记 ERAM 读数据（40 像素标记，延迟 1 拍）
    input wire        I_fg_init,      //ERAM 首轮写满（1=叠加使能，0=ERAM 未初始化不叠加）
    //------------ 外接框/质心/跟踪 统计输入（bbox_stat 输出，顶层直连，模块内跨域，模式 3 显示）------------
    input wire        I_bbox_valid,   //整帧统计有效（cnt >= 最小阈值）
    input wire[10:0]  I_bbox_min_x,   //外接框左边界（ERAM 位号域 0~1279，= 图像坐标）
    input wire[10:0]  I_bbox_max_x,   //外接框右边界
    input wire[9:0]   I_bbox_min_y,   //外接框上边界（0~719）
    input wire[9:0]   I_bbox_max_y,   //外接框下边界
    input wire[10:0]  I_bbox_cx,      //质心 X（ERAM 位号域）
    input wire[9:0]   I_bbox_cy,      //质心 Y
    input wire[4:0]   I_bbox_dir_dx,  //方向块偏移 X（有符号 5bit：-15/-10/0/+10/+15）
    input wire[4:0]   I_bbox_dir_dy,  //方向块偏移 Y（有符号 5bit）
    input wire        I_bbox_dir_valid,//方向有效（速度足够大）

    output wire       O_video_rd_en,  //读使能（什么时候从 DDR 读像素）
    input wire[23:0]  I_video_rd_data,//从 DDR 读出的像素（24 位 RGB）

    output reg        O_hdmi_vsync,   //HDMI 场同步（输出）
    output reg        O_hdmi_hsync,   //HDMI 行同步（输出）
    output reg        O_hdmi_de,      //HDMI 数据有效（输出）
    output reg[23:0]  O_hdmi_data     //HDMI 像素（输出）
);

    reg        S_video_vsync_1d;  //场同步打拍 1
    reg        S_video_vsync_2d;  //场同步打拍 2
    reg        S_video_hsync_1d;  //行同步打拍 1
    reg        S_video_hsync_2d;  //行同步打拍 2
    reg S_video_de_1d;     //数据有效打拍 1（ChipWatcher 抓取）
    reg S_video_de_2d;     //数据有效打拍 2（ChipWatcher 抓取）
    reg        S_video_vsync_3d;  //场同步打拍 3
    reg        S_video_hsync_3d;  //行同步打拍 3
    reg S_video_de_3d;     //数据有效打拍 3（ChipWatcher 抓取）
    reg [23:0] S_video_data_1d;   //像素打拍 1
    reg [23:0] S_video_data_2d;   //像素打拍 2
    reg [11:0] S_x;               //当前像素的列坐标
    reg [11:0] S_y;               //当前像素的行坐标
    reg [11:0] S_x_1d;      //坐标打拍1
    reg [11:0] S_x_2d;      //坐标打拍2（ChipWatcher 抓取）
    reg [11:0] S_y_1d;
    reg [11:0] S_y_2d;

    //------------ 前景标记叠加（主线第 4 步：显示期读 ERAM，前景像素涂白）------------
    // 列/字计数在 x_2d 域（与 de_2d 同拍）：每 40 像素一个字，行内 32 字（1280/40 整除）。
    // 时序：地址组合 = {y_2d,5'b0}+word（寄存器值晚 x_2d 一拍）→ ERAM 读延迟 1 拍 →
    //       dob 当前值 = M[f(x_2d 前 2 拍)]，col_d1 = col(x_2d 前 2 拍) → mark 组合对齐；
    //       mark 组合再被 MUX 采样时与 S_txt_on（打 1 拍）同拍，位置精确对齐。
    reg [5:0] S_fg_col;     //行内像素 mod 40（x_2d 域）
    reg [4:0] S_fg_word;    //行内字 0~31（x_2d 域，ChipWatcher 抓取）
    reg [5:0] S_fg_col_d1;  //col 打 1 拍（对齐 ERAM 读延迟，ChipWatcher 抓取）
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_fg_col    <= 6'd26;   //★B5：初始26（实测两可靠点N30左错2/N34左错4，斜率每+4N左错+2→归零N=26）
            S_fg_word   <= 5'd0;
            S_fg_col_d1 <= 6'd26;   //★B5：同上
        end else begin
            if(S_x_2d == 12'd0) begin                 //行首复位
                S_fg_col  <= 6'd26;   //★B5：行首初始26
                S_fg_word <= 5'd0;
            end else if(S_video_de_2d) begin          //有效像素递增
                if(S_fg_col == 6'd39) begin           //满 40 像素换下一个字
                    S_fg_col  <= 6'd0;
                    S_fg_word <= S_fg_word + 1'b1;
                end else
                    S_fg_col <= S_fg_col + 1'b1;
            end
            S_fg_col_d1 <= S_fg_col;
        end
    end
    // ERAM 读地址 = y*32 + 字偏移（y<<5 + word）
    assign O_fg_rd_addr = {S_y_2d, 5'd0} + {10'd0, S_fg_word};
    // 前景标记展开：当前读数据字里的 col 位（首轮写满 + SW4 拨下才有效；SW4 拨回立即停涂白）
    wire S_fg_mark_comb = I_fg_init && S_sw4_2d && I_fg_rd_data[S_fg_col_d1];
    //------------ 外接框/质心十字/方向块绘制（与涂白同一条对齐链）------------
    // 坐标账：mark_comb = dob[col_d1]，位选择 = (word, col_d1) 组合 = 当前显示的
    //   ERAM 位号 x_mark = word*40 + col_d1。统计侧 min_x/max_x/cx 从 bg_read 写流
    //   地址推导 = 同一 ERAM 位序坐标系（位号 = 图像坐标）。
    //   → 绘制判断直接与位号比较（零补偿），框边与「同位号涂白」同拍同位置显示，
    //     涂白已实测对齐手 → 框自动对齐手，与中间相位账无关（结构自洽）。
    //   垂直：mark_comb 的 y = S_y_2d（ERAM 读 1 拍被显示链打拍自洽抵消），S_yr 同域。
    wire S_bbox_mode = S_sw3_2d && !S_sw4_2d;   //模式 3：外接框 + 质心 + 跟踪
    wire S_bbox_en   = S_bbox_mode && I_fg_init && S_bbox_valid_2d;   //ERAM 写满 + 统计有效才画
    // 当前像素的 ERAM 位号（mark_comb 同域，与涂白位选择完全一致）
    // ⚠️ 相位账：mark_comb = fg_data[col_d1]，fg_data 的字来自「上一拍地址」= word 打 1 拍、
    //   col_d1 = col 打 1 拍 → 位组合 = (word_d1, col_d1) 同拍。word 与 col_d1 各自打 1 拍后
    //   在 col 回绕拍（进位拍）仍严格同步——直接拿「未打拍的 word」配 col_d1 会在进位拍
    //   超前 40（word 已进位、col 未回绕），框/十字在每 40px 边界错 1 拍。
    reg [4:0] S_fg_word_d1;
    reg [11:0] S_y_2d_d1;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_fg_word_d1 <= 5'd0;
            S_y_2d_d1    <= 12'd0;
        end else begin
            S_fg_word_d1 <= S_fg_word;
            S_y_2d_d1    <= S_y_2d;   //垂直同账：mark_comb 的字 = 上一拍地址的行（y_2d 前 1 拍）
        end
    end
    wire [10:0] S_x_mark = (S_fg_word_d1 << 5) + (S_fg_word_d1 << 3) + {5'd0, S_fg_col_d1};
    wire [10:0] S_xr = S_x_mark;   //位号域直接与统计值比较
    wire [9:0]  S_yr = S_y_2d_d1[9:0];   //与 mark_comb 的字行号同域
    // 外接框（四边各 2 像素宽）
    wire S_box_on_l = (S_xr == S_bbox_min_x_2d) || (S_xr == S_bbox_min_x_2d + 11'd1);
    wire S_box_on_r = (S_xr == S_bbox_max_x_2d) || (S_xr == S_bbox_max_x_2d - 11'd1);
    wire S_box_on_t = (S_yr == S_bbox_min_y_2d) || (S_yr == S_bbox_min_y_2d + 10'd1);
    wire S_box_on_b = (S_yr == S_bbox_max_y_2d) || (S_yr == S_bbox_max_y_2d - 10'd1);
    wire S_box_in_x  = (S_xr >= S_bbox_min_x_2d) && (S_xr <= S_bbox_max_x_2d);
    wire S_box_in_y  = (S_yr >= S_bbox_min_y_2d) && (S_yr <= S_bbox_max_y_2d);
    wire S_box_hit   = ((S_box_on_t || S_box_on_b) && S_box_in_x) || ((S_box_on_l || S_box_on_r) && S_box_in_y);
    // 质心十字（17×17：横竖臂各 17 像素长、3 像素粗）
    wire S_cross_h_arm = (S_xr >= S_bbox_cx_2d - 11'd8) && (S_xr <= S_bbox_cx_2d + 11'd8)
                      && (S_yr >= S_bbox_cy_2d - 10'd1) && (S_yr <= S_bbox_cy_2d + 10'd1);
    wire S_cross_v_arm = (S_xr >= S_bbox_cx_2d - 11'd1) && (S_xr <= S_bbox_cx_2d + 11'd1)
                      && (S_yr >= S_bbox_cy_2d - 10'd8) && (S_yr <= S_bbox_cy_2d + 10'd8);
    wire S_cross_hit = S_cross_h_arm || S_cross_v_arm;
    // 方向块（5×5，位于质心 + 速度方向偏移处）
    wire [10:0] S_dir_cx = S_bbox_cx_2d + {{6{S_bbox_dir_dx_2d[4]}}, S_bbox_dir_dx_2d};   //符号扩展
    wire [9:0]  S_dir_cy = S_bbox_cy_2d + {{5{S_bbox_dir_dy_2d[4]}}, S_bbox_dir_dy_2d};
    wire S_dir_hit = S_bbox_dir_valid_2d
                  && (S_xr >= S_dir_cx - 11'd2) && (S_xr <= S_dir_cx + 11'd2)
                  && (S_yr >= S_dir_cy - 10'd2) && (S_yr <= S_dir_cy + 10'd2);
    // 命中与颜色（优先级：框 > 十字 > 方向块）
    reg        S_bbox_hit;
    reg [23:0] S_bbox_color;
    always @(*) begin
        S_bbox_hit  = 1'b0;
        S_bbox_color = 24'd0;
        if(S_bbox_en) begin
            if(S_box_hit) begin
                S_bbox_hit  = 1'b1;
                S_bbox_color = 24'hFF0000;   //外接框：红
            end else if(S_cross_hit) begin
                S_bbox_hit  = 1'b1;
                S_bbox_color = 24'h00FF00;   //质心十字：绿
            end else if(S_dir_hit) begin
                S_bbox_hit  = 1'b1;
                S_bbox_color = 24'hFFFF00;   //方向块：黄
            end
        end
    end
    // ★ 根因修复（2026-10-31）：mark 打 2 拍对齐显示链 video_3d
    //    video 链打 3 拍（1d→2d→3d），mark_comb 相对显示位置早 2 拍（word 晚 1 拍 + 组合零打拍）
    //    → mark 打 2 拍后与 video_3d 同相位，消除 8px 右错
    reg S_fg_mark_1d;
    reg S_fg_mark_2d;
    reg        S_osd_hit;   //OSD 命中标志
    reg [23:0] S_osd_color; //OSD 颜色（24位RGB）
    reg [14:0] S_logo_addr;     //Logo ROM 地址（组合计算）
    reg [14:0] S_logo_addr_d1;  //Logo 地址打 1 拍（拆长路径，加时序裕量）
    wire[24:0] S_logo_pixel;//Logo ROM 像素（bit24=有效，bit23:0=RGB）
    localparam LOGO_X = 12'd0;      //Logo 左上角 X
    localparam LOGO_Y = 12'd0;      //Logo 左上角 Y
    localparam LOGO_W = 12'd160;    //Logo 宽 160
    localparam LOGO_H = 12'd160;    //Logo 高 160
    reg  [3:0] S_txt_idx;   //第几个字符（0~14）
    reg  [3:0] S_row_idx;  //行号（0=名单 1=时间 2=曝光 3=增益 4=算法 5=阈值 6=帧号 7=目标亮度 8=功能提示 10=质心 11=当前模式）
    reg        S_txt_area; //文字区域使能（在有效字符范围内=1）
    reg  [3:0] S_txt_row;   //字符内行（0~15）
    reg  [3:0] S_txt_col;   //字符内列（0~15）
    reg        S_txt_on;    //文字像素点亮
    reg  [7:0] S_txt_char;  //字符码（bit7=1→中文 0x80+索引；bit7=0→ASCII）
    reg [2:0] S_algo_gray_1d, S_algo_gray_2d;  //算法模式格雷码打两拍（跨时钟域同步）
    reg       S_auto_mode_1d, S_auto_mode_2d;  //自动曝光标志打两拍（跨时钟域同步）
    reg       S_am_sel_1d, S_am_sel_2d;        //2026-11-03 自动/手动状态打两拍（行11 用）
    reg [15:0] S_ae_1d, S_ae_2d;                       //曝光值打两拍（跨时钟域同步）
    reg [15:0] S_ag_1d, S_ag_2d;                       //增益值打两拍（跨时钟域同步）
    reg [7:0]  S_threshold_1d, S_threshold_2d;         //二值化阈值打两拍（跨时钟域同步）
    reg [10:0] S_sobel_threshold_1d, S_sobel_threshold_2d; //Sobel阈值打两拍（跨时钟域同步）
    reg [7:0]  S_target_1d, S_target_2d;               //目标亮度打两拍（跨时钟域同步）
    reg       S_sw4_1d, S_sw4_2d;                     //SW4 实时电平打两拍（涂白使能，跨时钟域同步）
    reg       S_bg_captured_1d, S_bg_captured_2d;      //已采锁存打两拍（OSD 显示）
    reg       S_sw3_1d, S_sw3_2d;                     //SW3 拨码电平打两拍（功能模式提示）
    //------------ 外接框统计值跨域打两拍（DDR 域 100M → HDMI 域 75M，值每帧才变）------------
    reg        S_bbox_valid_1d, S_bbox_valid_2d;
    reg [10:0] S_bbox_min_x_1d, S_bbox_min_x_2d;
    reg [10:0] S_bbox_max_x_1d, S_bbox_max_x_2d;
    reg [9:0]  S_bbox_min_y_1d, S_bbox_min_y_2d;
    reg [9:0]  S_bbox_max_y_1d, S_bbox_max_y_2d;
    reg [10:0] S_bbox_cx_1d, S_bbox_cx_2d;
    reg [9:0]  S_bbox_cy_1d, S_bbox_cy_2d;
    reg [4:0]  S_bbox_dir_dx_1d, S_bbox_dir_dx_2d;
    reg [4:0]  S_bbox_dir_dy_1d, S_bbox_dir_dy_2d;
    reg        S_bbox_dir_valid_1d, S_bbox_dir_valid_2d;
    reg [13:0] S_frame_cnt;   // 帧号 0~9999，14 位足够
    wire[15:0] S_bcd_threshold;   //二值化阈值 BCD（4位十进制）
    wire[15:0] S_bcd_sobel_threshold; //Sobel 阈值 BCD（4位十进制）
    wire[15:0] S_bcd_target;      //目标亮度 BCD（4位十进制）
    wire[15:0] S_cn_bits;   //中文字模查表结果
    wire[15:0] S_asc_bits;  //ASCII字模查表结果
    reg [15:0] S_char_bits; //分流后的点阵行
    wire[15:0] S_bcd_ae;    //曝光值转出的 BCD（4个数字）
    wire[15:0] S_bcd_ag;    //增益值转出的 BCD（4个数字）
    reg [23:0] S_video_data_3d;   //像素打拍 3
    wire [15:0] S_bcd_frame;
    localparam TEXT_X = 12'd1020;   //15字符240宽，右边距20：1280-240-20=1020
    localparam TEXT_Y = 12'd640;    //人员名单行
    localparam CHAR_W   = 12'd16;     //字符宽
    localparam CHAR_H   = 12'd16;     //字符高
    localparam COLOR_TEXT = 24'hffffff;  //文字颜色（白色）
    localparam AE_AG_X   = 12'd1068;  //曝光/增益值显示起始 X（右上角，12字符192宽：1280-192-20=1068）
    localparam ALGO_X   = 12'd624;   //算法名起始 X（顶部居中，2字符32宽：(1280-32)/2=624）
    localparam ALGO_Y   = 12'd10;    //算法名起始 Y（顶部，和曝光值同行）
    assign O_video_rd_en = I_video_de;  //数据有效时，才从 DDR 读像素
    //算法模式跨时钟域同步（按键在 24M 域，这里是 HDMI 像素时钟域）
    // 格雷码同步，避免 3 位二进制直接打 2 拍采到中间态（切换算法瞬间 OSD 算法名闪错）
    wire [2:0] algo_mode_gray = I_algo_mode ^ {1'b0, I_algo_mode[2:1]};
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_algo_gray_1d <= 3'd0;
            S_algo_gray_2d <= 3'd0;
        end else begin
            S_algo_gray_1d <= algo_mode_gray;
            S_algo_gray_2d <= S_algo_gray_1d;
        end
    end
    wire [2:0] S_algo_mode_2d;
    assign S_algo_mode_2d[2] = S_algo_gray_2d[2];
    assign S_algo_mode_2d[1] = S_algo_gray_2d[2] ^ S_algo_gray_2d[1];
    assign S_algo_mode_2d[0] = S_algo_gray_2d[2] ^ S_algo_gray_2d[1] ^ S_algo_gray_2d[0];
    //自动曝光标志跨时钟域同步
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_auto_mode_1d <= 1'b0;
            S_auto_mode_2d <= 1'b0;
            S_am_sel_1d <= 1'b0;
            S_am_sel_2d <= 1'b0;
        end else begin
            S_auto_mode_1d <= I_auto_mode;
            S_auto_mode_2d <= S_auto_mode_1d;
            S_am_sel_1d <= I_am_sel;
            S_am_sel_2d <= S_am_sel_1d;
        end
    end
    //SW4 背景采集状态跨时钟域同步
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_sw4_1d <= 1'b0;
            S_sw4_2d <= 1'b0;
            S_bg_captured_1d <= 1'b0;
            S_bg_captured_2d <= 1'b0;
            S_sw3_1d <= 1'b0;
            S_sw3_2d <= 1'b0;
        end else begin
            S_sw4_1d <= I_sw4;
            S_sw4_2d <= S_sw4_1d;
            S_bg_captured_1d <= I_bg_captured;
            S_bg_captured_2d <= S_bg_captured_1d;
            S_sw3_1d <= I_sw3;
            S_sw3_2d <= S_sw3_1d;
        end
    end
    //外接框统计值跨时钟域打两拍（100M 域 → 像素时钟域）
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_bbox_valid_1d <= 1'b0;    S_bbox_valid_2d <= 1'b0;
            S_bbox_min_x_1d <= 11'd0;   S_bbox_min_x_2d <= 11'd0;
            S_bbox_max_x_1d <= 11'd0;   S_bbox_max_x_2d <= 11'd0;
            S_bbox_min_y_1d <= 10'd0;   S_bbox_min_y_2d <= 10'd0;
            S_bbox_max_y_1d <= 10'd0;   S_bbox_max_y_2d <= 10'd0;
            S_bbox_cx_1d <= 11'd0;      S_bbox_cx_2d <= 11'd0;
            S_bbox_cy_1d <= 10'd0;      S_bbox_cy_2d <= 10'd0;
            S_bbox_dir_dx_1d <= 5'd0;   S_bbox_dir_dx_2d <= 5'd0;
            S_bbox_dir_dy_1d <= 5'd0;   S_bbox_dir_dy_2d <= 5'd0;
            S_bbox_dir_valid_1d <= 1'b0; S_bbox_dir_valid_2d <= 1'b0;
        end else begin
            S_bbox_valid_1d <= I_bbox_valid;      S_bbox_valid_2d <= S_bbox_valid_1d;
            S_bbox_min_x_1d <= I_bbox_min_x;      S_bbox_min_x_2d <= S_bbox_min_x_1d;
            S_bbox_max_x_1d <= I_bbox_max_x;      S_bbox_max_x_2d <= S_bbox_max_x_1d;
            S_bbox_min_y_1d <= I_bbox_min_y;      S_bbox_min_y_2d <= S_bbox_min_y_1d;
            S_bbox_max_y_1d <= I_bbox_max_y;      S_bbox_max_y_2d <= S_bbox_max_y_1d;
            S_bbox_cx_1d <= I_bbox_cx;            S_bbox_cx_2d <= S_bbox_cx_1d;
            S_bbox_cy_1d <= I_bbox_cy;            S_bbox_cy_2d <= S_bbox_cy_1d;
            S_bbox_dir_dx_1d <= I_bbox_dir_dx;    S_bbox_dir_dx_2d <= S_bbox_dir_dx_1d;
            S_bbox_dir_dy_1d <= I_bbox_dir_dy;    S_bbox_dir_dy_2d <= S_bbox_dir_dy_1d;
            S_bbox_dir_valid_1d <= I_bbox_dir_valid; S_bbox_dir_valid_2d <= S_bbox_dir_valid_1d;
        end
    end
    //曝光/增益/阈值/Sobel阈值/目标亮度 跨时钟域同步（24M 域 → HDMI 像素时钟域）
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_ae_1d <= 16'd0; S_ae_2d <= 16'd0;
            S_ag_1d <= 16'd0; S_ag_2d <= 16'd0;
            S_threshold_1d <= 8'd0; S_threshold_2d <= 8'd0;
            S_sobel_threshold_1d <= 11'd0; S_sobel_threshold_2d <= 11'd0;
            S_target_1d <= 8'd0; S_target_2d <= 8'd0;
        end else begin
            S_ae_1d <= I_ae; S_ae_2d <= S_ae_1d;
            S_ag_1d <= I_ag; S_ag_2d <= S_ag_1d;
            S_threshold_1d <= I_threshold; S_threshold_2d <= S_threshold_1d;
            S_sobel_threshold_1d <= I_sobel_threshold; S_sobel_threshold_2d <= S_sobel_threshold_1d;
            S_target_1d <= I_target; S_target_2d <= S_target_1d;
        end
    end
    //文字颜色：二值化/Sobel 模式用绿色（黑白背景上都显眼），否则白色
    reg [23:0] S_txt_color;
    always @(*) begin
        if((S_algo_mode_2d == 3'd2) || (S_algo_mode_2d == 3'd3))
            S_txt_color = 24'h00ff00;   //绿色
        else
            S_txt_color = COLOR_TEXT;   //白色
    end
    anlogic_logo_rom u_anlogic_logo_rom(
        .I_addr ( S_logo_addr_d1  ),
        .O_pixel( S_logo_pixel )
    );
    osd_cn_char u_osd_cn_char(
        .I_idx     ( S_txt_char[6:0] ),
        .I_row     ( S_txt_row  ),
        .O_row_bits( S_cn_bits )
    );
    osd_char_lib u_osd_char_lib(
        .I_char    ( S_txt_char ),        //ASCII码（冒号0x3A）
        .I_row     ( S_txt_row  ),
        .O_row_bits( S_asc_bits )
    );
    bin2bcd u_bin2bcd_ae(
        .bin( S_ae_2d ),
        .bcd( S_bcd_ae )
    );
    bin2bcd u_bin2bcd_frame(
        .bin( {2'd0, S_frame_cnt} ),   // 14 位补 0 凑成 16 位
        .bcd( S_bcd_frame )
    );
    bin2bcd u_bin2bcd_ag(
        .bin( S_ag_2d ),
        .bcd( S_bcd_ag )
    );
    bin2bcd u_bin2bcd_threshold(
        .bin( {8'd0, S_threshold_2d} ),
        .bcd( S_bcd_threshold )
    );
    bin2bcd u_bin2bcd_target(
        .bin( {8'd0, S_target_2d} ),
        .bcd( S_bcd_target )
    );
    bin2bcd u_bin2bcd_sobel_threshold(
        .bin( {5'd0, S_sobel_threshold_2d} ),
        .bcd( S_bcd_sobel_threshold )
    );
    //------------ 坐标跟踪：记录当前输出的像素坐标（S_x 列、S_y 行）------------
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_x <= 12'd0;
            S_y <= 12'd0;
        end
        else if(I_video_user) begin       //帧开始，坐标归零
            S_x <= 12'd0;
            S_y <= 12'd0;
        end
        else if(I_video_de) begin         //数据有效时
            if(I_video_last) begin        //行结束，换行
                S_x <= 12'd0;
                S_y <= S_y + 12'd1;
            end
            else begin                    //列 +1
                S_x <= S_x + 12'd1;
            end
        end
    end

    //------------ 时序打拍对齐（vsync/hsync/de/data 都延迟 2 拍，保证对齐）------------
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_video_vsync_1d <= 1'b0;
            S_video_vsync_2d <= 1'b0;
            S_video_vsync_3d <= 1'b0;
            S_video_hsync_1d <= 1'b0;
            S_video_hsync_2d <= 1'b0;
            S_video_hsync_3d <= 1'b0;
            S_video_de_1d    <= 1'b0;
            S_video_de_2d    <= 1'b0;
            S_video_de_3d    <= 1'b0;
            O_hdmi_vsync     <= 1'b0;
            O_hdmi_hsync     <= 1'b0;
            O_hdmi_de        <= 1'b0;
            O_hdmi_data      <= 24'd0;
            S_fg_mark_1d    <= 1'b0;
            S_fg_mark_2d    <= 1'b0;
        end
        else begin
            S_video_vsync_1d <= I_video_vsync;
            S_video_vsync_2d <= S_video_vsync_1d;
            S_video_vsync_3d <= S_video_vsync_2d;
            O_hdmi_vsync     <= S_video_vsync_3d;   //场同步延迟 3 拍输出

            S_video_hsync_1d <= I_video_hsync;
            S_video_hsync_2d <= S_video_hsync_1d;
            S_video_hsync_3d <= S_video_hsync_2d;
            O_hdmi_hsync     <= S_video_hsync_3d;   //行同步延迟 3 拍输出
            S_video_data_3d <= S_video_data_2d;
            S_fg_mark_1d    <= S_fg_mark_comb;
            S_fg_mark_2d    <= S_fg_mark_1d;
            S_video_de_1d    <= I_video_de;
            S_video_de_2d    <= S_video_de_1d;
            S_video_de_3d    <= S_video_de_2d;
            O_hdmi_de        <= S_video_de_3d;      //数据有效延迟 3 拍输出
            S_video_data_1d  <= I_video_rd_data;
            S_video_data_2d  <= S_video_data_1d;
            S_x_1d <= S_x;
            S_x_2d <= S_x_1d;
            S_y_1d <= S_y;
            S_y_2d <= S_y_1d;

            //---------- 各种输出模式 ----------
            if(DEBUG_MODE == 1) begin                  //调试模式1：彩条（8 段颜色）
                if(S_video_de_2d) begin
                    if(S_x < 12'd128)
                        O_hdmi_data <= 24'hff0000;     //红
                    else if(S_x < 12'd256)
                        O_hdmi_data <= 24'h00ff00;     //绿
                    else if(S_x < 12'd384)
                        O_hdmi_data <= 24'h0000ff;     //蓝
                    else if(S_x < 12'd512)
                        O_hdmi_data <= 24'hffff00;     //黄
                    else if(S_x < 12'd640)
                        O_hdmi_data <= 24'h00ffff;     //青
                    else if(S_x < 12'd768)
                        O_hdmi_data <= 24'hff00ff;     //紫
                    else if(S_x < 12'd896)
                        O_hdmi_data <= 24'hffffff;     //白
                    else
                        O_hdmi_data <= 24'h202020;     //灰
                end
                else begin
                    O_hdmi_data <= 24'd0;
                end
            end
            else if(DEBUG_MODE == 2) begin              //调试模式2：按调试状态显示颜色
                if(S_video_de_2d) begin
                    case (I_debug_status)
                        4'b0000: O_hdmi_data <= 24'h000000;   //全黑
                        4'b0001: O_hdmi_data <= 24'hff0000;   //红
                        4'b0011: O_hdmi_data <= 24'hffff00;   //黄
                        4'b0111: O_hdmi_data <= 24'h00ff00;   //绿
                        4'b1111: O_hdmi_data <= I_video_rd_data; //全通过，显示原图
                        default: O_hdmi_data <= 24'h0000ff;   //蓝
                    endcase
                end
                else begin
                    O_hdmi_data <= 24'd0;
                end
            end
            else if(DEBUG_MODE == 3) begin              //调试模式3：分块显示调试状态
                if(S_video_de_2d) begin
                    if(S_x < (IMG_WIDTH/4))
                        O_hdmi_data <= I_debug_status[0] ? 24'hff8000 : 24'h404040;
                    else if(S_x < (IMG_WIDTH/2))
                        O_hdmi_data <= I_debug_status[1] ? 24'hffff00 : 24'h404040;
                    else if(S_x < ((IMG_WIDTH*3)/4))
                        O_hdmi_data <= I_debug_status[2] ? 24'hff0000 : 24'h404040;
                    else
                        O_hdmi_data <= I_debug_status[3] ? 24'h00ffff : 24'h404040;
                end
                else begin
                    O_hdmi_data <= 24'd0;
                end
            end else begin
                if(S_osd_hit)
                    O_hdmi_data <= S_osd_color;
                else if(S_txt_on)                 //← 加回文字
                    O_hdmi_data <= S_txt_color;
                else if(S_video_de_2d && S_bbox_hit)   //← 外接框/质心十字/方向块（与涂白同链，模式3）
                    O_hdmi_data <= S_bbox_color;
                else if(S_video_de_2d && S_fg_mark_comb)  //← 前景标记涂白（★盲修B2：comb直用，相位账=col提前8 抵消8-9px右错）
                    O_hdmi_data <= 24'hFFFFFF;
                else
                    O_hdmi_data <= S_video_data_3d;
            end
        end
    end
    always @(*) begin
        S_logo_addr = 15'd0;
        if((S_x_1d >= LOGO_X) && (S_x_1d < (LOGO_X + LOGO_W)) &&
            (S_y_1d >= LOGO_Y) && (S_y_1d < (LOGO_Y + LOGO_H)))
            // LOGO_W=160=128+32，*160 用移位加法(<<7+<<5)替代 DSP 乘法器，减延迟
            S_logo_addr = ((S_y_1d - LOGO_Y) << 7) + ((S_y_1d - LOGO_Y) << 5) + (S_x_1d - LOGO_X);
    end
    // 地址打 1 拍：把「地址计算」和「ROM 查表」拆成两段，缩短组合路径加裕量
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            S_logo_addr_d1 <= 15'd0;
        else
            S_logo_addr_d1 <= S_logo_addr;
    end
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_osd_hit   <= 1'b0;
            S_osd_color <= 24'd0;
        end else begin
           if(S_video_de_2d && S_logo_pixel[24]) begin
               S_osd_hit   <= 1'b1;
               S_osd_color <= S_logo_pixel[23:0];
           end else begin
               S_osd_hit   <= 1'b0;
               S_osd_color <= 24'd0;
           end
        end
    end
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            S_txt_on <= 1'b0;
        else
            S_txt_on <= (S_txt_area && S_char_bits[15 - S_txt_col]);
    end
    always @(*) begin
        if(S_txt_char[7])   //bit7=1 → 中文（字符码 = 0x80 + osd_cn_char 索引）
            S_char_bits = S_cn_bits;
        else                //bit7=0 → ASCII（osd_char_lib）
            S_char_bits = S_asc_bits;
    end
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            S_frame_cnt <= 14'd0;
        else if(I_video_user) begin          // 每帧开始的脉冲，+1
            if(S_frame_cnt == 14'd9999)
                S_frame_cnt <= 14'd0;        // 到 9999 回绕
            else
                S_frame_cnt <= S_frame_cnt + 1'b1;
        end
    end
    //------------ 文字叠加：行定位 + 字符索引 + 区域使能 ------------
    always @(*) begin
        S_row_idx  = 2'd0;
        S_txt_idx  = 4'd0;
        S_txt_row  = 4'd0;
        S_txt_col  = 4'd0;
        S_txt_area = 1'b0;
        if(S_video_de_2d) begin
            // 行0（人员名单，15字符）：Y 640~656
            if((S_y_2d >= 12'd640) && (S_y_2d < 12'd656)) begin
                S_row_idx = 2'd0;
                S_txt_row = S_y_2d - 12'd640;
                if((S_x_2d >= TEXT_X) && (S_x_2d < (TEXT_X + 15*CHAR_W))) begin
                    S_txt_idx  = (S_x_2d - TEXT_X) >> 4;
                    S_txt_col  = (S_x_2d - TEXT_X) & 12'hF;
                    S_txt_area = 1'b1;
                end
            // 行1（完成时间，10字符）：Y 664~680
            end else if((S_y_2d >= 12'd664) && (S_y_2d < 12'd680)) begin
                S_row_idx = 2'd1;
                S_txt_row = S_y_2d - 12'd664;
                if((S_x_2d >= TEXT_X) && (S_x_2d < (TEXT_X + 10*CHAR_W))) begin
                    S_txt_idx  = (S_x_2d - TEXT_X) >> 4;
                    S_txt_col  = (S_x_2d - TEXT_X) & 12'hF;
                    S_txt_area = 1'b1;
                end
            // 行4（算法名，2字符）：顶部居中 Y 10~26
            end else if((S_y_2d >= ALGO_Y) && (S_y_2d < (ALGO_Y + 12'd16)) && (S_x_2d >= ALGO_X) && (S_x_2d < (ALGO_X + 2*CHAR_W))) begin
                S_row_idx = 3'd4;
                S_txt_row = S_y_2d - ALGO_Y;
                S_txt_idx  = (S_x_2d - ALGO_X) >> 4;
                S_txt_col  = (S_x_2d - ALGO_X) & 12'hF;
                S_txt_area = 1'b1;
            // 行11（当前模式：自动/手动，7字符）：Y 10~26 右上角，全模式显示（2026-11-03 用户决策：SW34=123 也显示）
            end else if((S_y_2d >= 12'd10) && (S_y_2d < 12'd26)) begin
                S_row_idx = 4'd11;
                S_txt_row = S_y_2d - 12'd10;
                if((S_x_2d >= AE_AG_X) && (S_x_2d < (AE_AG_X + 7*CHAR_W))) begin
                    S_txt_idx  = (S_x_2d - AE_AG_X) >> 4;
                    S_txt_col  = (S_x_2d - AE_AG_X) & 12'hF;
                    S_txt_area = 1'b1;
                end
            // 行2（曝光值，8字符）：Y 34~50（2026-11-03 下移，括号自动/手动标记已删、移「当前模式」行）
            end else if((S_y_2d >= 12'd34) && (S_y_2d < 12'd50)) begin
                S_row_idx = 2'd2;
                S_txt_row = S_y_2d - 12'd34;
                if((S_x_2d >= AE_AG_X) && (S_x_2d < (AE_AG_X + 8*CHAR_W))) begin
                    S_txt_idx  = (S_x_2d - AE_AG_X) >> 4;
                    S_txt_col  = (S_x_2d - AE_AG_X) & 12'hF;
                    S_txt_area = 1'b1;
                end
            // 行3（增益值，8字符）：Y 58~74
            end else if((S_y_2d >= 12'd58) && (S_y_2d < 12'd74)) begin
                S_row_idx = 2'd3;
                S_txt_row = S_y_2d - 12'd58;
                if((S_x_2d >= AE_AG_X) && (S_x_2d < (AE_AG_X + 8*CHAR_W))) begin
                    S_txt_idx  = (S_x_2d - AE_AG_X) >> 4;
                    S_txt_col  = (S_x_2d - AE_AG_X) & 12'hF;
                    S_txt_area = 1'b1;
                end
            // 行6：Y 82~98，帧号（7字符）始终显示
            end else if((S_y_2d >= 12'd82) && (S_y_2d < 12'd98)) begin
                S_row_idx = 3'd6;
                S_txt_row = S_y_2d - 12'd82;
                if((S_x_2d >= AE_AG_X) && (S_x_2d < (AE_AG_X + 7*CHAR_W))) begin
                    S_txt_idx  = (S_x_2d - AE_AG_X) >> 4;
                    S_txt_col  = (S_x_2d - AE_AG_X) & 12'hF;
                    S_txt_area = 1'b1;
                end
            // 行5（阈值，7字符）：Y 106~122，二值化(3位)或Sobel(4位)时显示
            end else if(((S_algo_mode_2d == 3'd2) || (S_algo_mode_2d == 3'd3)) && (S_y_2d >= 12'd106) && (S_y_2d < 12'd122)) begin
                S_row_idx = 3'd5;
                S_txt_row = S_y_2d - 12'd106;
                if((S_x_2d >= AE_AG_X) && (S_x_2d < (AE_AG_X + 7*CHAR_W))) begin
                    S_txt_idx  = (S_x_2d - AE_AG_X) >> 4;
                    S_txt_col  = (S_x_2d - AE_AG_X) & 12'hF;
                    S_txt_area = 1'b1;
                end
            // 行8（功能提示）：Y 130~146，功能模式2/3/4 时显示「已采-背景检测/外接显示框/区域填充」
            end else if((S_y_2d >= 12'd130) && (S_y_2d < 12'd146) && ((S_sw4_2d && !S_sw3_2d) || (S_sw3_2d))) begin
                S_row_idx = 4'd8;
                S_txt_row = S_y_2d - 12'd130;
                if((S_x_2d >= AE_AG_X) && (S_x_2d < (AE_AG_X + 8*CHAR_W))) begin
                    S_txt_idx  = (S_x_2d - AE_AG_X) >> 4;
                    S_txt_col  = (S_x_2d - AE_AG_X) & 12'hF;
                    S_txt_area = 1'b1;
                end
            
            // 行7（目标亮度，6字符）：Y 130~146，自动曝光时显示（与「已采」行共用 Y，按模式互斥）
            end else if((S_auto_mode_2d == 1'b1) && (S_y_2d >= 12'd130) && (S_y_2d < 12'd146)) begin
                S_row_idx = 3'd7;
                S_txt_row = S_y_2d - 12'd130;
                if((S_x_2d >= AE_AG_X) && (S_x_2d < (AE_AG_X + 6*CHAR_W))) begin
                    S_txt_idx  = (S_x_2d - AE_AG_X) >> 4;
                    S_txt_col  = (S_x_2d - AE_AG_X) & 12'hF;
                    S_txt_area = 1'b1;
                end
            // 行10（质心坐标，11字符「X:3F2 Y:1A8」）：Y 154~170，模式3（外接框）显示
            // 十六进制显示（零 bin2bcd 零新字模，资源最优）：3 位 hex 覆盖 0~1279/719
            end else if(S_bbox_mode && S_bbox_valid_2d && (S_y_2d >= 12'd154) && (S_y_2d < 12'd170)) begin
                S_row_idx = 4'd10;
                S_txt_row = S_y_2d - 12'd154;
                if((S_x_2d >= AE_AG_X) && (S_x_2d < (AE_AG_X + 11*CHAR_W))) begin
                    S_txt_idx  = (S_x_2d - AE_AG_X) >> 4;
                    S_txt_col  = (S_x_2d - AE_AG_X) & 12'hF;
                    S_txt_area = 1'b1;
                end
            end
        end
    end
    // hex 数字转 ASCII 字符（质心坐标行用）
    function [7:0] hex2char;
        input [3:0] h;
        begin
            hex2char = (h < 4'd10) ? (8'h30 + {4'd0, h}) : (8'h41 + {4'd0, h} - 4'd10);
        end
    endfunction
    always @(*) begin
        S_txt_char = 8'd0;
        case(S_row_idx)
            4'd10: begin   //质心坐标：X:3F2 Y:1A8（hex 3 位）
                case(S_txt_idx)
                    4'd0  : S_txt_char = 8'h58;                     //X
                    4'd1  : S_txt_char = 8'h3A;                     //:
                    4'd2  : S_txt_char = hex2char({1'b0, S_bbox_cx_2d[10:8]});   //cx 11bit 高位补 0 成 4bit
                    4'd3  : S_txt_char = hex2char(S_bbox_cx_2d[7:4]);
                    4'd4  : S_txt_char = hex2char(S_bbox_cx_2d[3:0]);
                    4'd5  : S_txt_char = 8'h20;                     //空格
                    4'd6  : S_txt_char = 8'h59;                     //Y
                    4'd7  : S_txt_char = 8'h3A;                     //:
                    4'd8  : S_txt_char = hex2char({2'b0, S_bbox_cy_2d[9:8]});   //cy 10bit 高位补 0 成 4bit
                    4'd9  : S_txt_char = hex2char(S_bbox_cy_2d[7:4]);
                    4'd10 : S_txt_char = hex2char(S_bbox_cy_2d[3:0]);
                    default : S_txt_char = 8'd0;
                endcase
            end
            2'd0: begin   //组名：逻启工坊
                case(S_txt_idx)
                    4'd0  : S_txt_char = 8'h80 + 8'd13;  //组
                    4'd1  : S_txt_char = 8'h80 + 8'd52;  //名
                    4'd2  : S_txt_char = 8'h3A;          //:
                    4'd3  : S_txt_char = 8'h80 + 8'd48;  //逻
                    4'd4  : S_txt_char = 8'h80 + 8'd49;  //启
                    4'd5  : S_txt_char = 8'h80 + 8'd50;  //工
                    4'd6  : S_txt_char = 8'h80 + 8'd51;  //坊
                    default : S_txt_char = 8'd0;
               endcase end
           2'd1: begin   //完成时间：2026年11月2日
               case(S_txt_idx)
                   4'd0  : S_txt_char = 8'h32;          //2
                   4'd1  : S_txt_char = 8'h30;          //0
                   4'd2  : S_txt_char = 8'h32;          //2
                   4'd3  : S_txt_char = 8'h36;          //6
                   4'd4  : S_txt_char = 8'h80 + 8'd8;   //年
                   4'd5  : S_txt_char = 8'h31;          //1
                   4'd6  : S_txt_char = 8'h31;          //1
                   4'd7  : S_txt_char = 8'h80 + 8'd9;   //月
                   4'd8  : S_txt_char = 8'h32;          //2
                   4'd9  : S_txt_char = 8'h80 + 8'd10;  //日
                   default : S_txt_char = 8'd0;
               endcase end
           2'd2: begin   //曝光值：xxxx（自动/手动标记已移「当前模式」行，2026-11-03）
               case(S_txt_idx)
                   4'd0  : S_txt_char = 8'h80 + 8'd16;  //曝
                   4'd1  : S_txt_char = 8'h80 + 8'd17;  //光
                   4'd2  : S_txt_char = 8'h80 + 8'd18;  //值
                   4'd3  : S_txt_char = 8'h3A;          //:
                   4'd4  : S_txt_char = 8'h30 + S_bcd_ae[15:12];  //千位
                   4'd5  : S_txt_char = 8'h30 + S_bcd_ae[11:8];   //百位
                   4'd6  : S_txt_char = 8'h30 + S_bcd_ae[7:4];    //十位
                   4'd7  : S_txt_char = 8'h30 + S_bcd_ae[3:0];    //个位
                   default : S_txt_char = 8'd0;
               endcase end
           2'd3: begin   //增益值：xxxx
               case(S_txt_idx)
                   4'd0  : S_txt_char = 8'h80 + 8'd19;  //增
                   4'd1  : S_txt_char = 8'h80 + 8'd20;  //益
                   4'd2  : S_txt_char = 8'h80 + 8'd18;  //值
                   4'd3  : S_txt_char = 8'h3A;          //:
                   4'd4  : S_txt_char = 8'h30 + S_bcd_ag[15:12];  //千位
                   4'd5  : S_txt_char = 8'h30 + S_bcd_ag[11:8];   //百位
                   4'd6  : S_txt_char = 8'h30 + S_bcd_ag[7:4];    //十位
                   4'd7  : S_txt_char = 8'h30 + S_bcd_ag[3:0];    //个位
                   default : S_txt_char = 8'd0;
               endcase end
           3'd4: begin   //算法名：按算法模式显示（顶部居中）
               case(S_algo_mode_2d)
                   3'd0: begin   //原样
                       case(S_txt_idx)
                           4'd0  : S_txt_char = 8'h80 + 8'd26;  //原
                           4'd1  : S_txt_char = 8'h80 + 8'd27;  //样
                           default : S_txt_char = 8'd0;
                       endcase
                   end
                   3'd1: begin   //灰度
                       case(S_txt_idx)
                           4'd0  : S_txt_char = 8'h80 + 8'd28;  //灰
                           4'd1  : S_txt_char = 8'h80 + 8'd29;  //度
                           default : S_txt_char = 8'd0;
                       endcase
                   end
                   3'd2: begin   //二值
                       case(S_txt_idx)
                           4'd0  : S_txt_char = 8'h80 + 8'd30;  //二
                           4'd1  : S_txt_char = 8'h80 + 8'd18;  //值（复用索引18）
                           default : S_txt_char = 8'd0;
                       endcase
                   end
                   3'd3: begin   //边缘（Sobel）
                       case(S_txt_idx)
                           4'd0  : S_txt_char = 8'h80 + 8'd34;  //边
                           4'd1  : S_txt_char = 8'h80 + 8'd35;  //缘
                           default : S_txt_char = 8'd0;
                       endcase
                   end
                   3'd4: begin   //运动（帧差法）
                       case(S_txt_idx)
                           4'd0  : S_txt_char = 8'h80 + 8'd41;  //运
                           4'd1  : S_txt_char = 8'h80 + 8'd42;  //动
                           default : S_txt_char = 8'd0;
                       endcase
                   end
                   default : S_txt_char = 8'd0;
               endcase
           end
           3'd5: begin   //阈值：二值化(3位)或Sobel(4位)
               case(S_txt_idx)
                   4'd0  : S_txt_char = 8'h80 + 8'd31;  //阈
                   4'd1  : S_txt_char = 8'h80 + 8'd18;  //值
                   4'd2  : S_txt_char = 8'h3A;          //:
                   4'd3  : S_txt_char = (S_algo_mode_2d == 3'd3) ? (8'h30 + S_bcd_sobel_threshold[15:12]) : (8'h30 + S_bcd_threshold[11:8]);
                   4'd4  : S_txt_char = (S_algo_mode_2d == 3'd3) ? (8'h30 + S_bcd_sobel_threshold[11:8])  : (8'h30 + S_bcd_threshold[7:4]);
                   4'd5  : S_txt_char = (S_algo_mode_2d == 3'd3) ? (8'h30 + S_bcd_sobel_threshold[7:4])   : (8'h30 + S_bcd_threshold[3:0]);
                   4'd6  : S_txt_char = (S_algo_mode_2d == 3'd3) ? (8'h30 + S_bcd_sobel_threshold[3:0])   : 8'd0;  //Sobel个位 或 空
                   default : S_txt_char = 8'd0;
               endcase
           end
           3'd6: begin   //帧号:xxxx（恒显，已采移行8）
               case(S_txt_idx)
                   4'd0  : S_txt_char = 8'h80 + 8'd32;  //帧
                   4'd1  : S_txt_char = 8'h80 + 8'd33;  //号
                   4'd2  : S_txt_char = 8'h3A;          //:
                   4'd3  : S_txt_char = 8'h30 + S_bcd_frame[15:12];  //千位
                   4'd4  : S_txt_char = 8'h30 + S_bcd_frame[11:8];   //百位
                   4'd5  : S_txt_char = 8'h30 + S_bcd_frame[7:4];    //十位
                   4'd6  : S_txt_char = 8'h30 + S_bcd_frame[3:0];    //个位
                   default : S_txt_char = 8'd0;
               endcase
           end
           4'd8: begin   //功能提示：已采-背景检测 / 已采-外接显示框 / 已采-区域填充（模式2/3/4）
               case(S_txt_idx)
                   4'd0  : S_txt_char = S_bg_captured_2d ? (8'h80 + 8'd43) : 8'd0;  //已（采过背景显示）
                   4'd1  : S_txt_char = S_bg_captured_2d ? (8'h80 + 8'd45) : 8'd0;  //采
                   4'd2  : S_txt_char = 8'h2D;          //-
                   // 功能名（SW3 SW4 = 01 背景检测 / 10 外接显示框 / 11 区域填充）
                   4'd3  : S_txt_char = (S_sw3_2d) ? ((S_sw4_2d) ? (8'h80 + 8'd62) : (8'h80 + 8'd57)) : (8'h80 + 8'd53);  //区/外/背
                   4'd4  : S_txt_char = (S_sw3_2d) ? ((S_sw4_2d) ? (8'h80 + 8'd63) : (8'h80 + 8'd58)) : (8'h80 + 8'd54);  //域/接/景
                   4'd5  : S_txt_char = (S_sw3_2d) ? ((S_sw4_2d) ? (8'h80 + 8'd64) : (8'h80 + 8'd59)) : (8'h80 + 8'd55);  //填/显/检
                   4'd6  : S_txt_char = (S_sw3_2d) ? ((S_sw4_2d) ? (8'h80 + 8'd65) : (8'h80 + 8'd60)) : (8'h80 + 8'd56);  //充/示/测
                   4'd7  : S_txt_char = (S_sw3_2d && !S_sw4_2d) ? (8'h80 + 8'd61) : 8'd0;  //框（仅外接显示框有第5字）
                   default : S_txt_char = 8'd0;
               endcase
           end
           3'd7: begin   //目标亮度：目标:xxx（自动曝光时显示）
               case(S_txt_idx)
                   4'd0  : S_txt_char = 8'h80 + 8'd39;  //目
                   4'd1  : S_txt_char = 8'h80 + 8'd40;  //标
                   4'd2  : S_txt_char = 8'h3A;          //:
                   4'd3  : S_txt_char = 8'h30 + S_bcd_target[11:8];  //百位
                   4'd4  : S_txt_char = 8'h30 + S_bcd_target[7:4];   //十位
                   4'd5  : S_txt_char = 8'h30 + S_bcd_target[3:0];   //个位
                   default : S_txt_char = 8'd0;
               endcase
           end
           4'd11: begin   //当前模式：自动/手动（SW34=00 原样模式显示，随 KEY4 长按切换）
               case(S_txt_idx)
                   4'd0  : S_txt_char = 8'h80 + 8'd66;  //当
                   4'd1  : S_txt_char = 8'h80 + 8'd67;  //前
                   4'd2  : S_txt_char = 8'h80 + 8'd68;  //模
                   4'd3  : S_txt_char = 8'h80 + 8'd69;  //式
                   4'd4  : S_txt_char = 8'h3A;          //:
                   4'd5  : S_txt_char = S_am_sel_2d ? (8'h80 + 8'd38) : (8'h80 + 8'd36);  //2026-11-03 用 auto_manual_sel 状态：手动→手 自动→自（123 模式锁自动显示「自动」）
                   4'd6  : S_txt_char = 8'h80 + 8'd37;  //动
                   default : S_txt_char = 8'd0;
               endcase
           end
           default : S_txt_char = 8'd0;
        endcase
    end 
endmodule
