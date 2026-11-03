//========================================================
// 模块：erode_1bit —— 1bit 流式 3×3 腐蚀（原型，验证「级联次数 vs 噪点团宽度」）
// 功能：二值图 3×3 结构元腐蚀：窗口 9 点全 1 才输出 1（孤立点/细线被吃）。
//   级联 N 次 = 等效 (2N+1)×(2N+1) 结构元：N=1 吃 1px 宽噪点、N=2 吃 2-3px 宽噪点团。
//   流式实现：2 行行缓冲（ROW_W bit）+ 3 拍列窗口，无帧缓存。
// 资源（每级）：2×ROW_W FF（原型用 FF；工程集成走 DRAM 化）
//========================================================
module erode_1bit #(
    parameter ROW_W = 16   //每行拍数（行宽/每拍像素数——原型 1 像素/拍）
)(
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire        I_pix,        //当前像素（1bit，行扫描流）
    input  wire        I_vld,
    input  wire        I_fs,         //帧开始（清行缓冲防跨帧污染）
    output wire        O_pix,        //腐蚀输出（延迟 1 行 + 1 拍）
    output wire        O_vld
);
    // 行缓冲：R_ln0 = 上一行、R_ln1 = 上上行（拍索引 mod ROW_W）
    reg R_ln0 [0:ROW_W-1];
    reg R_ln1 [0:ROW_W-1];
    reg [11:0] S_col;      //列拍计数（0~ROW_W-1 循环）
    integer j;

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            for(j=0; j<ROW_W; j=j+1) begin R_ln0[j] <= 1'b0; R_ln1[j] <= 1'b0; end
            S_col <= 12'd0;
        end else if(I_fs) begin
            for(j=0; j<ROW_W; j=j+1) begin R_ln0[j] <= 1'b0; R_ln1[j] <= 1'b0; end
            S_col <= 12'd0;
        end else if(I_vld) begin
            // 读窗口列：上上行同列、上一行同列/左右列（+1 mod ROW_W）、当前行左右列
            R_ln1[S_col] <= R_ln0[S_col];   //行缓冲推进
            R_ln0[S_col] <= I_pix;
            S_col <= (S_col == ROW_W-1) ? 12'd0 : S_col + 12'd1;
        end
    end

    // 窗口读取（组合）：3×3 九点。中心列 C = S_col-1（拍 n-1 的列）
    //   当前行左/中/右 = 拍 n-2/n-1/n；上两行同读 C-1/C/C+1（模 ROW_W）
    wire [11:0] W_cm = (S_col == 0) ? ROW_W-1 : S_col - 12'd1;   //中心列 C
    wire [11:0] W_cl = (W_cm == 0) ? ROW_W-1 : W_cm - 12'd1;     //左列 C-1
    wire [11:0] W_cr = S_col;                                    //右列 C+1
    reg R_cur_l, R_cur_m;        //当前行左、中（1 拍/2 拍前）
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin R_cur_l <= 1'b0; R_cur_m <= 1'b0; end
        else if(I_fs) begin R_cur_l <= 1'b0; R_cur_m <= 1'b0; end
        else begin
            R_cur_m <= I_pix;     //中 = 本拍
            R_cur_l <= R_cur_m;   //左 = 上一拍
        end
    end

    // 窗口九点（中心 = 当前行拍 n-1）
    wire W_l1l = R_ln1[W_cl], W_l1c = R_ln1[W_cm], W_l1r = R_ln1[W_cr];
    wire W_l0l = R_ln0[W_cl], W_l0c = R_ln0[W_cm], W_l0r = R_ln0[W_cr];
    wire W_curl = R_cur_l,    W_curc = R_cur_m,    W_curr = I_pix;

    assign O_pix = W_l1l & W_l1c & W_l1r &
                   W_l0l & W_l0c & W_l0r &
                   W_curl & W_curc & W_curr;
    // valid 延迟：数据延迟 = 1 行 + 1 拍（R_cur_m 是 1 拍前、行缓冲 1 行）——原型简化：
    // 用「valid 打 1 拍 + 行首对齐」近似（tb 按帧边界重对齐，valid 边界 2 行毛刺忽略）
    reg R_vld_d;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) R_vld_d <= 1'b0;
        else         R_vld_d <= I_vld;
    end
    assign O_vld = R_vld_d;
endmodule
