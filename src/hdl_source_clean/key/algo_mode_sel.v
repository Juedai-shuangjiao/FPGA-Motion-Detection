//========================================================
// 模块：algo_mode_sel —— 算法模式切换（KEY4 按下循环切换）
// 功能：每按一次 KEY4，算法模式 +1，到顶回绕。
//       当前算法：0=原样 1=灰度 2=二值 3=Sobel
//       预留：3 位 mode，最多 8 种算法（后续可加二值化/Sobel 等）
// 2026-11-02 修复：新增 en 使能。区域填充模式（SW3SW4=11）下 KEY4 被
//   disp_mode_sel（显示模式三态）占用，本模块必须锁定算法模式为 0（原样），
//   否则按一次 KEY4 两个模块同时切换 → 图像算法和前景标记叠加乱变
//   （实机现象：画面全白/全黑/边缘线乱跳）。en=0 时锁原样，退出填充后
//   KEY4 恢复算法模式循环（从 0 开始）。
//========================================================
module algo_mode_sel (
    input  wire       clk,        //时钟（24MHz）
    input  wire       rst_n,      //复位，低有效
    input  wire       key_pulse,  //按键按下沿脉冲（来自 key_pulse 模块）
    input  wire       en,         //算法模式切换使能：0=锁定原样（填充模式 KEY4 归显示模式切换）
    output reg  [2:0] mode        //算法模式：0=原样 1=灰度 2=二值 3=Sobel
);

// 当前支持的算法数量（mode 切到这个数就回绕到 0）
localparam ALGO_NUM = 4;

always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        mode <= 3'd0;
    else if(!en)
        mode <= 3'd0;              //填充模式：锁定原样，KEY4 只切显示模式三态
    else if(key_pulse) begin
        if(mode >= ALGO_NUM - 1)
            mode <= 3'd0;          //到顶回绕
        else
            mode <= mode + 1'b1;   //切到下一模式
    end
end

endmodule
