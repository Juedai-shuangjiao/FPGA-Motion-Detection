/*******************************MILIANKE*******************************
*（略，米联客版权头）
*信号命名规范：I_ 输入 / O_ 输出 / IO_ 双向 / S_ 内部 / _n 低有效 / _dg 调试 / _r 打拍 / _s 状态机
*********************************************************************/

//========================================================
// 模块：uivtc —— 视频时序控制器（Video Timing Controller）
// 功能：生成 HDMI 显示所需的行同步(hs)/场同步(vs)/数据有效(de)信号
// 原理：两个计数器（行计数器 hcnt、场计数器 vcnt）数像素，
//       数到指定位置就拉高/拉低同步信号，输出标准视频时序
//========================================================

`timescale 1ns / 1ns

module uivtc#
(
parameter H_ActiveSize  =   1980,               //行有效像素数（一行里要显示的像素）
parameter H_FrameSize   =   1920+88+44+148,     //行总像素数（含消隐）
parameter H_SyncStart   =   1920+88,            //行同步脉冲开始位置
parameter H_SyncEnd     =   1920+88+44,         //行同步脉冲结束位置

parameter V_ActiveSize  =   1080,               //场有效行数（一帧里要显示的行）
parameter V_FrameSize   =   1080+4+5+36,        //场总行数（含消隐）
parameter V_SyncStart   =   1080+4,             //场同步脉冲开始位置
parameter V_SyncEnd     =   1080+4+5            //场同步脉冲结束位置
)
(
input           I_vtc_rstn,     //复位，低有效
input			I_vtc_clk,      //像素时钟
output			O_vtc_vs,       //场同步输出
output          O_vtc_hs,       //行同步输出
output          O_vtc_de_valid, //数据有效输出
output          O_vtc_user,     //帧同步（stream 的 user 信号）
output          O_vtc_last      //行结束（stream 的 last 信号）
);


reg [11:0] hcnt = 12'd0;    //行计数器（水平像素计数）
reg [11:0] vcnt = 12'd0;    //场计数器（垂直行计数）
reg [2 :0] rst_cnt = 3'd0;  //复位计数（同步复位用）
wire rst_sync = rst_cnt[2]; //同步复位标志

//------------ 同步复位生成（打 3 拍）------------
always @(posedge I_vtc_clk or negedge I_vtc_rstn)begin
    if(I_vtc_rstn == 1'b0)
        rst_cnt <= 3'd0;
    else if(rst_cnt[2] == 1'b0)
        rst_cnt <= rst_cnt + 1'b1;
end

//------------ 行计数器：数一行总像素，循环 0 ~ H_FrameSize-1 ------------
always @(posedge I_vtc_clk)begin
    if(rst_sync == 1'b0)                       //复位
        hcnt <= 12'd0;
    else if(hcnt < (H_FrameSize - 1'b1))       //没数满继续数
        hcnt <= hcnt + 1'b1;
    else                                        //数满归零
        hcnt <= 12'd0;
end

//------------ 场计数器：每数完一行才 +1，循环 0 ~ V_FrameSize-1 ------------
always @(posedge I_vtc_clk)begin
    if(rst_sync == 1'b0)
        vcnt <= 12'd0;
    else if(hcnt == (H_ActiveSize  - 1'b1)) begin          //一行结束时
           vcnt <= (vcnt == (V_FrameSize - 1'b1)) ? 12'd0 : vcnt + 1'b1;
    end
end

//------------ 组合逻辑：圈出同步信号和有效区间 ------------
wire hs_valid  =  hcnt < H_ActiveSize;                       //行有效（在有效像素区）
wire vs_valid  =  vcnt < V_ActiveSize;                       //场有效（在有效行区）
wire vtc_hs    =  (hcnt >= H_SyncStart && hcnt < H_SyncEnd); //行同步脉冲
wire vtc_vs	   =  (vcnt > V_SyncStart && vcnt <= V_SyncEnd); //场同步脉冲
wire vtc_de    =  hs_valid && vs_valid;                      //数据有效 = 行有效 && 场有效

//**********************  把视频时序转成 stream 流信号  ***************************
reg   vtc_vs_r1  ;
reg   vtc_hs_r1  ;
reg   vtc_de_r1  ;
reg   vtc_user_r1 ,vtc_user_r2;
reg   vtc_valid_r1,vtc_valid_r2;
reg   vtc_last_r2;
reg   vs_start;

//------------ 帧开始标志 vs_start ------------
always @(posedge I_vtc_clk )begin
    if(rst_sync == 1'b0)                       //复位
        vs_start <= 1'b0;
    else if(vtc_user_r1)                       //已发过帧同步，清掉
        vs_start <= 1'b0;
    else if(vtc_vs && vtc_vs_r1==1'b0)         //场同步脉冲上升沿 = 一帧开始
        vs_start <= 1'b1;
end

//------------ 打拍对齐（vs/hs/de/user/last 各延迟 1~2 拍）------------
always @(posedge I_vtc_clk  )begin
    vtc_vs_r1    <= vtc_vs;
    vtc_hs_r1    <= vtc_hs;
    vtc_user_r1  <= ~vtc_user_r1 & vs_start & vtc_de;   //帧同步（user）延迟 1 拍
    vtc_last_r2  <= ~vtc_de & vtc_valid_r1;             //行结束（last）
    vtc_valid_r1 <= vtc_de;                             //有效延迟 1 拍
    vtc_valid_r2 <= vtc_valid_r1;                       //有效延迟 2 拍
    vtc_user_r2  <= vtc_user_r1;                        //帧同步延迟 2 拍
end

assign O_vtc_vs       =  vtc_vs_r1;      //场同步
assign O_vtc_hs       =  vtc_hs_r1;      //行同步
assign O_vtc_de_valid =  vtc_valid_r2;   //数据有效
assign O_vtc_user     =  vtc_user_r2;    //帧同步（stream user）
assign O_vtc_last     =  vtc_last_r2;    //行结束（stream last）


endmodule
