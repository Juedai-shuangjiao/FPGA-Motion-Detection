//========================================================
// 模块：ae_auto —— 自动曝光调节（AEC）
// 功能：根据画面平均亮度，闭环自动调节曝光值，使亮度稳定在目标值附近
// 逻辑：平均亮度 > 目标+死区 → 减曝光；< 目标-死区 → 加曝光；死区内不动
// 说明：
//   · 输入 I_avg/I_adjust 来自像素时钟域（brightness_stat），本模块在 24MHz 域，
//     内部打两拍跨时钟域同步
//   · I_adjust 是「每10帧一个」的调节脉冲，收到才调一次（曝光第N+2帧生效，留余量）
//   · 第一版只调曝光，不动增益（曝光范围 2~3990 已覆盖大部分场景）
//========================================================
module ae_auto (
    input  wire        I_clk,       //时钟（24MHz）
    input  wire        I_rst,       //复位，高有效
    input  wire        I_auto_en,   //自动使能（SW3 低电平=自动，高电平=手动）
    input  wire [7:0]  I_avg,       //平均亮度（像素域，来自 brightness_stat）
    input  wire        I_adjust,    //调节脉冲（像素域，每10帧一个）
    output wire [15:0] O_ae,        //自动曝光值（0~3990）
    output reg         O_ae_req     //曝光变化请求脉冲
);

    //------------ 参数 ------------
    localparam TARGET   = 8'd128;   //目标平均亮度
    localparam DEADBAND = 8'd16;    //死区（±16，亮度112~144之间不调，防振荡）
    localparam STEP     = 16'd100;  //曝光调节步进（跟手动一致）
    localparam AE_MAX   = 16'd3990; //曝光上限（数据手册：2×帧长-10）
    localparam AE_MIN   = 16'd2;    //曝光下限

    //------------ 跨时钟域同步（像素域 → 24MHz 域，打两拍）------------
    reg [7:0] avg_sync1, avg_sync2;
    reg       adjust_sync1, adjust_sync2;

    //------------ 当前自动曝光值（初始1990，跟手动一致）------------
    reg [15:0] r_ae = 16'd1990;

    always @(posedge I_clk or posedge I_rst) begin
        if(I_rst) begin
            avg_sync1    <= 8'd0;
            avg_sync2    <= 8'd0;
            adjust_sync1 <= 1'b0;
            adjust_sync2 <= 1'b0;
            r_ae         <= 16'd1990;
            O_ae_req     <= 1'b0;
        end else begin
            //跨时钟域打两拍
            avg_sync1    <= I_avg;
            avg_sync2    <= avg_sync1;
            adjust_sync1 <= I_adjust;
            adjust_sync2 <= adjust_sync1;

            O_ae_req <= 1'b0;   //默认清请求
            if(I_auto_en && adjust_sync2) begin
                //收到调节脉冲：比较平均亮度，调节曝光
                if(avg_sync2 > TARGET + DEADBAND) begin
                    //太亮 → 减曝光
                    if(r_ae > AE_MIN + STEP)
                        r_ae <= r_ae - STEP;
                    else
                        r_ae <= AE_MIN;
                    O_ae_req <= 1'b1;
                end else if(avg_sync2 < TARGET - DEADBAND) begin
                    //太暗 → 加曝光
                    if(r_ae < AE_MAX - STEP)
                        r_ae <= r_ae + STEP;
                    else
                        r_ae <= AE_MAX;
                    O_ae_req <= 1'b1;
                end
                //死区内不动
            end
        end
    end

    assign O_ae = r_ae;

endmodule
