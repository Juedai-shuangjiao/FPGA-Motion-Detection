//========================================================
// 模块：ae_set —— 曝光/增益调节（手动 + 自动合并版）
// 功能：手动模式（SW3高）按键调曝光/增益；自动模式（SW3低）按平均亮度闭环调曝光
// 关键：曝光值 r_ae_set 是「同一个寄存器」，手动和自动共用，切换模式不跳变
// 说明：
//   · 自动模式调曝光/增益（曝光/增益按权重分批次交替），目标亮度可调（初始100）、死区±16、每10帧调一次
//   · I_avg/I_adjust 来自像素时钟域（brightness_stat），本模块内部打两拍同步
//========================================================
module ae_set (
    input  wire        I_clk,          //时钟（24MHz）
    input  wire        I_rst,          //复位（高有效）
    input  wire        I_inc_tick,     //加长按 tick（KEY2，手动用）
    input  wire        I_dec_tick,     //减长按 tick（KEY3，手动用）
    input  wire        I_enable,       //手动使能（S_mode 0/1 且 SW3 高）
    input  wire        I_mode,         //手动：0=调曝光，1=调增益
    input  wire        I_auto_en,      //自动使能（SW3 低）
    input  wire [7:0]  I_avg,          //平均亮度（像素域，来自 brightness_stat）
    input  wire        I_adjust,       //调节脉冲（像素域，每10帧一个）
    input  wire [7:0]  I_target,       //目标亮度（0~255，来自 target_set）
    input  wire        I_ae_cfg_done,  //曝光配置完成
    input  wire        I_cam_cfg_done, //摄像头初始化完成
    output wire        O_ae_req,       //曝光调节请求
    output wire [15:0] O_ae,           //曝光值
    output wire [15:0] O_ag            //增益值
);

    //------------ 参数 ------------
    localparam AE_MAX   = 16'd3990;  //曝光上限（数据手册：2×帧长-10）
    localparam AE_MIN   = 16'd2;     //曝光下限
    localparam AE_STEP  = 16'd100;   //曝光步进（粗调）
    localparam AG_MAX   = 16'd143;   //增益上限（8x 档最大，数据手册 ANA GAIN 只有 0x1f 这档，0x2f 非法会花屏）
    localparam AG_MIN   = 16'd16;    //增益下限（1x 档）
    localparam AG_STEP  = 16'd16;    //增益步进（自动调节用，半个档位）
    localparam DEADBAND = 8'd16;     //死区（±16，防振荡）
    localparam AE_WEIGHT = 3'd3;     //太暗时曝光调3次、增益调1次（曝光优先，加曝光不增噪）
    localparam AG_WEIGHT = 3'd3;     //太亮时增益调3次、曝光调1次（增益优先，减增益降噪）

    // 目标亮度上下界（饱和到 0~255，避免 I_target ± 死区溢出）
    wire [7:0] target_upper = (I_target > 8'd239) ? 8'd255 : (I_target + DEADBAND);
    wire [7:0] target_lower = (I_target < DEADBAND) ? 8'd0   : (I_target - DEADBAND);

    //------------ 共享的曝光/增益目标值（手动和自动共用这同一个）------------
    reg [15:0] r_ae_set = 3990;   //曝光目标值（初始1990）
    reg [15:0] r_ag_set = 105;     //增益目标值（初始80）

    reg [15:0] r_ae = 3990;       //当前曝光值（初始1990）
    reg [15:0] r_ag = 105;         //当前增益值（初始80）

    reg [2:0] r_dark_cnt = 3'd0;   //太暗调节计数（曝光/增益分批次交替）
    reg [2:0] r_bright_cnt = 3'd0; //太亮调节计数（增益/曝光分批次交替）

    //------------ 自动曝光跨时钟域同步（像素域 → 24MHz 域）------------
    reg [7:0] avg_sync1, avg_sync2;
    reg       adjust_sync1, adjust_sync2;

    always @(posedge I_clk or posedge I_rst) begin
        if(I_rst) begin
            r_ae_set    <= 3990;
            r_ag_set    <= 105;
            avg_sync1   <= 8'd0;
            avg_sync2   <= 8'd0;
            adjust_sync1 <= 1'b0;
            adjust_sync2 <= 1'b0;
            r_dark_cnt   <= 3'd0;
            r_bright_cnt <= 3'd0;
        end else begin
            //跨时钟域打两拍
            avg_sync1    <= I_avg;
            avg_sync2    <= avg_sync1;
            adjust_sync1 <= I_adjust;
            adjust_sync2 <= adjust_sync1;

            if(I_auto_en) begin
                //========== 自动模式：亮度闭环调曝光/增益（曝光/增益按权重分批次交替）==========
                if(adjust_sync2) begin
                    if(avg_sync2 > target_upper) begin
                        //太亮 → 增益优先：增益调 AG_WEIGHT 次，曝光调 1 次
                        if(r_bright_cnt >= AG_WEIGHT) begin
                            //轮到曝光（减曝光）
                            if(r_ae_set > AE_MIN + AE_STEP)
                                r_ae_set <= r_ae_set - AE_STEP;
                            else
                                r_ae_set <= AE_MIN;
                            r_bright_cnt <= 3'd0;
                        end else begin
                            //调增益（减增益）
                            if(r_ag_set > AG_MIN + AG_STEP)
                                r_ag_set <= r_ag_set - AG_STEP;
                            else
                                r_ag_set <= AG_MIN;
                            r_bright_cnt <= r_bright_cnt + 1'b1;
                        end
                    end else if(avg_sync2 < target_lower) begin
                        //太暗 → 曝光优先：曝光调 AE_WEIGHT 次，增益调 1 次
                        if(r_dark_cnt >= AE_WEIGHT) begin
                            //轮到增益（加增益）
                            if(r_ag_set < AG_MAX - AG_STEP)
                                r_ag_set <= r_ag_set + AG_STEP;
                            else
                                r_ag_set <= AG_MAX;
                            r_dark_cnt <= 3'd0;
                        end else begin
                            //调曝光（加曝光）
                            if(r_ae_set < AE_MAX - AE_STEP)
                                r_ae_set <= r_ae_set + AE_STEP;
                            else
                                r_ae_set <= AE_MAX;
                            r_dark_cnt <= r_dark_cnt + 1'b1;
                        end
                    end
                    //死区内不动
                end
            end else if(I_enable) begin
                //========== 手动模式：按键调曝光/增益（共享 r_ae_set/r_ag_set）==========
                if(I_mode == 1'b0) begin          //调曝光
                    if(I_dec_tick) begin
                        if(r_ae_set > AE_MIN + AE_STEP)
                            r_ae_set <= r_ae_set - AE_STEP;
                        else
                            r_ae_set <= AE_MIN;
                    end else if(I_inc_tick) begin
                        if(r_ae_set < AE_MAX - AE_STEP)
                            r_ae_set <= r_ae_set + AE_STEP;
                        else
                            r_ae_set <= AE_MAX;
                    end
                end else begin                     //调增益
                    if(I_dec_tick) begin
                        if(r_ag_set > AG_MIN)     //增益下限
                            r_ag_set <= r_ag_set - 1'b1;
                    end else if(I_inc_tick) begin
                        if(r_ag_set < AG_MAX)     //增益上限（8x 档，0x2f 非法会花屏）
                                r_ag_set <= r_ag_set + 1'b1;
                    end
                end
            end
        end
    end

    //------------ 目标值变化时，更新输出并触发调节请求 ------------
    reg        r_ae_req = 0; //调节请求脉冲

    assign O_ae = r_ae;
    assign O_ag = r_ag;
    assign O_ae_req = r_ae_req;

    always @(posedge I_clk or posedge I_rst) begin
        if(I_rst) begin
            r_ae_req <= 0;
            r_ae     <= 1990;
            r_ag     <= 80;
        end else if(r_ae_req) begin
            r_ae_req <= 0;                              //请求只保持一拍
        end else if(((r_ae != r_ae_set) || (r_ag != r_ag_set)) && (I_cam_cfg_done==1'b1) && (I_ae_cfg_done==1'b1)) begin
            r_ae     <= r_ae_set;                       //更新曝光值
            r_ag     <= r_ag_set;                       //更新增益值
            r_ae_req <= 1;                              //触发调节请求
        end
    end

endmodule
