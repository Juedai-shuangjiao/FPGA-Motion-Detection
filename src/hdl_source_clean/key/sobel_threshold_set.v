//========================================================
// 模块：sobel_threshold_set —— Sobel 边缘检测阈值调节
// 功能：S_mode==2'd3（第4种模式）时，KEY2/KEY3 长按 tick 调节阈值
//       阈值范围 0~2040（11 位），初始 512，每 tick 加减 16
// 2026-11-03 两处升级：
//   ①步进 64→16（mag8 域 2/档）：高增益下有效阈值窗口极窄（如 3990/121
//     实测窗口 mag8 128~144，步进 64 只有 2 档可选、一档全黑一档全白），
//     步进 16 后窗口内 8 档可调，可细选「噪声上沿」与「边缘幅值」之间
//   ②自动联动：I_auto_en=1（SW34=00 且自动曝光状态）时阈值直接跟随
//     I_auto_val（= 平均亮度查表，wrapper 内），按键忽略
//========================================================
module sobel_threshold_set (
    input  wire        I_clk,          //时钟（24MHz）
    input  wire        I_rst,          //复位（高有效）
    input  wire        I_inc_tick,     //加 tick（KEY2 长按）
    input  wire        I_dec_tick,     //减 tick（KEY3 长按）
    input  wire        I_enable,       //使能（S_mode==2'd3 时才调）
    input  wire        I_auto_en,      //自动联动使能（1=跟随 I_auto_val，按键忽略）
    input  wire [10:0] I_auto_val,     //自动联动值（平均亮度查表）
    output wire [10:0] O_threshold     //阈值（0~2040，11 位）
);

    localparam STEP = 11'd16;          //每 tick 步进 16（11bit 域 = mag8 域 +2；窗口窄时细调，2026-11-03）

    reg [10:0] r_threshold = 11'd48;   //阈值寄存器（2026-11-03 提交版初值 48：用户实测手动甜点，替换原 512）

    always @(posedge I_clk or posedge I_rst) begin
        if(I_rst) begin
            r_threshold <= 11'd48;    //2026-11-03 提交版复位 48（用户实测甜点；512 复位致 mag8 域阈值 64 边缘过稀）
        end else if(I_auto_en) begin
            r_threshold <= I_auto_val;   //自动联动：直接跟随
        end else if(I_enable) begin
            if(I_dec_tick) begin
                if(r_threshold >= STEP)
                    r_threshold <= r_threshold - STEP;
                else
                    r_threshold <= 11'd0;
            end else if(I_inc_tick) begin
                if(r_threshold <= 11'd2040 - STEP)
                    r_threshold <= r_threshold + STEP;
                else
                    r_threshold <= 11'd2040;
            end
        end
    end

    assign O_threshold = r_threshold;

endmodule
