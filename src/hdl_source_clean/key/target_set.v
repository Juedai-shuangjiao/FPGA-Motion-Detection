//========================================================
// 模块：target_set —— 自动曝光目标亮度调节
// 功能：S_mode==0 且自动模式（SW3低）时，KEY2/KEY3 长按 tick 调节目标亮度
//       目标亮度范围 0~255，初始 100，每 tick 加减 8（粗调）
//========================================================
module target_set (
    input  wire        I_clk,          //时钟（24MHz）
    input  wire        I_rst,          //复位（高有效）
    input  wire        I_inc_tick,     //加 tick（KEY2 长按）
    input  wire        I_dec_tick,     //减 tick（KEY3 长按）
    input  wire        I_enable,       //使能（S_mode==0 且 SW3低 时才调）
    output wire [7:0]  O_target        //目标亮度（0~255）
);

    localparam STEP = 8'd8;            //每 tick 步进 8（粗调）

    reg [7:0] r_target = 8'd100;       //目标亮度寄存器（初始100）

    always @(posedge I_clk or posedge I_rst) begin
        if(I_rst) begin
            r_target <= 8'd100;
        end else if(I_enable) begin
            if(I_dec_tick) begin
                if(r_target >= STEP)
                    r_target <= r_target - STEP;
                else
                    r_target <= 8'd0;
            end else if(I_inc_tick) begin
                if(r_target <= 8'd255 - STEP)
                    r_target <= r_target + STEP;
                else
                    r_target <= 8'd255;
            end
        end
    end

    assign O_target = r_target;

endmodule
