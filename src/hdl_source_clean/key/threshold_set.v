//========================================================
// 模块：threshold_set —— 二值化阈值调节
// 功能：S_mode==2'd2（第3种模式）时，KEY2/KEY3 长按 tick 调节阈值
//       阈值范围 0~255，初始 60，每 tick 加减 1（细调）
// 2026-11-03 新增：自动联动——I_auto_en=1（SW34=00 且自动曝光状态）时
//       阈值直接跟随 I_auto_val（= 平均亮度查表，wrapper 内），按键忽略；
//       自动联动保证「比平均亮的部分」占比不随曝光/增益漂移，画面稳定。
//========================================================
module threshold_set (
    input  wire       I_clk,          //时钟（24MHz）
    input  wire       I_rst,          //复位（高有效）
    input  wire       I_inc_tick,     //加 tick（KEY2 长按）
    input  wire       I_dec_tick,     //减 tick（KEY3 长按）
    input  wire       I_enable,       //使能（S_mode==2'd2 时才调）
    input  wire       I_auto_en,      //自动联动使能（1=跟随 I_auto_val，按键忽略）
    input  wire [7:0] I_auto_val,     //自动联动值（平均亮度查表）
    output wire [7:0] O_threshold     //阈值（0~255）
);

    localparam STEP = 8'd1;           //每 tick 步进 1（细调）

    reg [7:0] r_threshold = 8'd60;    //阈值寄存器（初始60，和目标亮度60配套）

    always @(posedge I_clk or posedge I_rst) begin
        if(I_rst) begin
            r_threshold <= 8'd60;
        end else if(I_auto_en) begin
            r_threshold <= I_auto_val;   //自动联动：直接跟随
        end else if(I_enable) begin
            if(I_dec_tick) begin
                if(r_threshold >= STEP)
                    r_threshold <= r_threshold - STEP;
                else
                    r_threshold <= 8'd0;
            end else if(I_inc_tick) begin
                if(r_threshold <= 8'd255 - STEP)
                    r_threshold <= r_threshold + STEP;
                else
                    r_threshold <= 8'd255;
            end
        end
    end

    assign O_threshold = r_threshold;

endmodule
