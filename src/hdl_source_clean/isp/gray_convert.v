//========================================================
// 模块：gray_convert —— RGB888 转灰度
// ★ 当前是【临时直通占位版】：O_tdata = I_tdata，不改像素
//   用途：先验证「KEY4 切换 + OSD 算法名显示」框架能否跑通。
//   验证完框架后，把下面唯一的 assign 换成真正的灰度逻辑（你自己写）：
//     gray = (R>>2) + (G>>1) + (B>>2)，4 个像素各算各的，
//     每个像素 R=G=B=gray，拼回 96 位。
//   接口（已定死，别改）：
//     输入 96 位 = 4 像素 RGB888，每像素 R[高8位] G[中8位] B[低8位]
//     输出 96 位 = 4 像素灰度，每像素 R=G=B=gray
//========================================================
module gray_convert (
    input  wire [95:0] I_tdata,   //输入 96 位 RGB（4 像素）
    output wire [95:0] O_tdata    //输出 96 位（临时直通，正式版填灰度）
);
    // 像素0（示例）：R>>2 + G>>1 + B>>2
    wire [7:0] gray0 = (I_tdata[23:16] >> 2) + (I_tdata[15:8] >> 1) + (I_tdata[7:0] >> 2);
    // 像素1（示例）：R>>2 + G>>1 + B>>2
    wire [7:0] gray1 = (I_tdata[47:40] >> 2) + (I_tdata[39:32] >> 1) + (I_tdata[31:24] >> 2);
    // 像素2（示例）：R>>2 + G>>1 + B>>2
    wire [7:0] gray2 = (I_tdata[71:64] >> 2) + (I_tdata[63:56] >> 1) + (I_tdata[55:48] >> 2);
    // 像素3（示例）：R>>2 + G>>1 + B>>2
    wire [7:0] gray3 = (I_tdata[95:88] >> 2) + (I_tdata[87:80] >> 1) + (I_tdata[79:72] >> 2);
    assign O_tdata = {gray3,gray3,gray3, gray2,gray2,gray2, gray1,gray1,gray1, gray0,gray0,gray0};
    
    
endmodule
