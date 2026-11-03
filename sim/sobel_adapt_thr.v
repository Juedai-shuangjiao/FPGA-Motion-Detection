//========================================================
// 模块：sobel_adapt_thr —— Sobel 梯度自适应阈值（轻量版 Improved Canny 思想）
// 功能：帧内统计梯度幅值总和与点数 → 帧末锁存「自适应阈值 = 均值 × 1.5」；
//       下一帧对梯度流做阈值比较输出二值边缘（帧级流水：帧 N 统计 → 帧 N+1 应用）。
//       自适应依据：光照强时整帧梯度整体抬高，固定阈值会漏边/爆边，
//       阈值跟着梯度均值走（亮度鲁棒，星点分割专利同思路）。
// 实现细节（零除法器）：
//   - 有效像素数每帧恒定（720×1280 = 921600 ≈ 2^19.8），mean = sum/cnt
//     用 sum>>CNT_LOG2 近似（cnt 恒定 → 误差是常数 13.8%，系数里吸收）
//   - T = 1.5×mean ≈ (sum>>20) + (sum>>22) + (sum>>23) + 8（=1.564×mean，饱和 255）
//   - cnt=0（全黑帧）回退默认阈值 64，防除零
//   - 首帧无统计 → 默认阈值 64 不滤
// 资源：28bit 累加器 + 20bit 计数器 + 移位加 ≈ 200 LUT，无除法器
//========================================================
module sobel_adapt_thr (
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire [7:0]  I_grad,       //Sobel 梯度幅值（8bit，每拍一个像素）
    input  wire        I_vld,        //数据有效拍
    input  wire        I_fs_pulse,   //帧开始脉冲（帧末锁存阈值 + 清零累加）
    output wire [7:0]  O_thr,        //当前生效自适应阈值（8bit，供下游比较/调试）
    output reg         O_edge        //梯度 > 阈值 的边缘输出（与 I_vld 对齐，晚一拍）
);
    parameter CNT_LOG2 = 20;   //每帧有效像素数 = 2^CNT_LOG2（真实 921600≈2^19.8；tb 用 10 加速）

    // 帧统计
    reg [27:0] R_sum;    //帧梯度总和（720×1280×255 ≈ 2.35 亿 < 2^28=268M ✓）
    reg [19:0] R_cnt;    //帧点数
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            R_sum <= 28'd0;
            R_cnt <= 20'd0;
        end else if(I_fs_pulse) begin
            R_sum <= 28'd0;
            R_cnt <= 20'd0;
        end else if(I_vld) begin
            R_sum <= R_sum + {20'd0, I_grad};
            R_cnt <= R_cnt + 20'd1;
        end
    end

    // 帧末锁存阈值：T ≈ 1.5×mean（移位加组合，饱和 8bit）
    reg [7:0] R_thr;
    wire [7:0] W_a = R_sum[CNT_LOG2+7 : CNT_LOG2];         //sum>>20 ≈ 1.138×mean（8bit）
    wire [5:0] W_b = R_sum[CNT_LOG2+5 : CNT_LOG2+2];         //sum>>22 ≈ 0.284×mean（6bit）
    wire [4:0] W_c = R_sum[CNT_LOG2+4 : CNT_LOG2+3];         //sum>>23 ≈ 0.142×mean（5bit）
    wire [9:0] W_t = {2'b0, W_a} + {4'b0, W_b} + {5'b0, W_c} + 10'd8;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            R_thr <= 8'd64;   //首帧默认阈值
        end else if(I_fs_pulse) begin
            if(R_cnt == 20'd0)
                R_thr <= 8'd64;   //全黑帧回退默认
            else
                R_thr <= (W_t > 10'd255) ? 8'hFF : W_t[7:0];
        end
    end

    assign O_thr = R_thr;

    // 边缘比较（帧级流水：本帧用上帧阈值）
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) O_edge <= 1'b0;
        else         O_edge <= I_vld && (I_grad > R_thr);
    end
endmodule
