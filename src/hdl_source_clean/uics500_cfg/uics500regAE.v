`timescale 1ns / 1ps
/*******************************MILIANKE*******************************
*Company : MiLianKe Electronic Technology Co., Ltd.
*WebSite:https://www.milianke.com
*TechWeb:https://www.uisrc.com
*tmall-shop:https://milianke.tmall.com
*jd-shop:https://milianke.jd.com
*taobao-shop1: https://milianke.taobao.com
*Create Date: 2019/12/17
*Module Name:HDMI_IN_Test
*File Name:HDMI_IN_Test.v
*Description: 
*The reference demo provided by Milianke is only used for learning. 
*We cannot ensure that the demo itself is free of bugs, so users 
*should be responsible for the technical problems and consequences
*caused by the use of their own products.
*Copyright: Copyright (c) MiLianKe
*All rights reserved.
*Revision: 1.0
*Signal description
*1) _i input
*2) _o output
*3) _n activ low
*4) _dg debug signal 
*5) _r delay or register
*6) _s state mechine
*********************************************************************/

/*******************************ui7611reg***************************
--1.ADV7611оƬ���üĴ������ñ�
*********************************************************************/

module uics500regAE
(  
input      [8 :0]  REG_INDEX,
output reg [31:0]  REG_DATA,
output     [8 :0]  REG_SIZE,
input      [15:0]  I_AE,
input      [15:0]  I_AG
);

assign	REG_SIZE = 9'd9;
//-----------------------------------------------------------------
/////////////////////	Config Data REG	  //////////////////////////	
// 用 Group Hold 打包曝光/增益，0x3800=0x60 让它们在帧内特定时刻统一生效，消除滚动快门撕裂
always@(*)
   case(REG_INDEX)
		0:	REG_DATA = {16'h3800, 8'h00};  // 开始打包到 group 0
		1:	REG_DATA = {16'h3e00, 4'h0, I_AE[15:12]}; 
		2:	REG_DATA = {16'h3e01, I_AE[11: 4]}; 
		3:	REG_DATA = {16'h3e02, I_AE[3:0], 4'h0};
		4:	REG_DATA = {16'h3e03, 8'h0b};  // AGC 手动控制使能（数据手册 2.2.3）
		5:	REG_DATA = {16'h3e08, I_AG[15:8]};
		6:	REG_DATA = {16'h3e09, I_AG[7 :0]};
		7:	REG_DATA = {16'h3800, 8'h10};  // 结束打包到 group 0
		8:	REG_DATA = {16'h3800, 8'h60};  // group 0 帧内特定时刻统一生效（帧同步，不撕裂）
		default:REG_DATA    =   {16'h0000, 8'h00};
   endcase

endmodule
