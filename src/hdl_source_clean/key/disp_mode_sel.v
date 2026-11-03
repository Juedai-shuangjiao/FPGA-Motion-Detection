//========================================================
// 模块：disp_mode_sel —— 显示模式三态循环切换（区域填充功能，KEY4，2026-11-01）
// 功能：区域填充模式（SW3SW4=11）下每按一次 KEY4，显示模式循环：
//       0=涂白（填充后）→ 1=边缘 → 2=原图 → 回 0。
//       非区域填充模式锁定 0（涂白），KEY4 恢复算法模式切换语义（algo_mode_sel）。
// 说明：enable 用 SW 拨码电平（非按键沿），进入区域填充模式即从涂白态开始演示。
//========================================================
module disp_mode_sel (
    input  wire       clk,        //时钟（24MHz）
    input  wire       rst_n,      //复位，低有效
    input  wire       key_pulse,  //按键按下沿脉冲（KEY4，与 algo_mode_sel 同源）
    input  wire       en,         //区域填充模式使能（SW3&&SW4 拨码电平）
    output reg  [1:0] mode        //显示模式：0=涂白（填充后） 1=边缘 2=原图
);

// 显示模式总数（切到 2 回绕到 0）
localparam DISP_NUM = 3;

always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        mode <= 2'd0;
    else if(!en)
        mode <= 2'd0;               //非区域填充模式锁定涂白（KEY4 归算法模式切换）
    else if(key_pulse) begin
        if(mode >= DISP_NUM - 1)
            mode <= 2'd0;           //到顶回绕
        else
            mode <= mode + 1'b1;    //切到下一显示模式
    end
end

endmodule
