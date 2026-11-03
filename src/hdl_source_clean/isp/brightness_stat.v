//========================================================
// 模块：brightness_stat —— 亮度统计（自动曝光用）
// 功能：累加一帧的灰度，帧结束时输出平均亮度；每 40 帧输出一个调节脉冲
// 输入：96 位灰度（4像素，R=G=B=gray，接 gray_convert 输出）
// 输出：O_avg（平均亮度 0~255）、O_adjust（每20帧一个调节使能脉冲）
// 时钟：像素时钟（S_csi_rx_clk），跟 gray_data 同域
//========================================================
module brightness_stat (
    input  wire        I_clk,       //像素时钟
    input  wire        I_rst_n,     //复位，低有效
    input  wire [95:0] I_tdata,     //输入 96 位灰度（4像素，R=G=B=gray）
    input  wire        I_tvalid,    //数据有效
    input  wire        I_tuser,     //帧开始
    output reg  [7:0]  O_avg,       //平均亮度（0~255）
    output reg         O_adjust     //调节使能脉冲（每20帧一个）
);

    //------------ 提取 4 个灰度值（每像素取低 8 位，R=G=B=gray）------------
    wire [7:0] g0 = I_tdata[7:0];
    wire [7:0] g1 = I_tdata[31:24];
    wire [7:0] g2 = I_tdata[55:48];
    wire [7:0] g3 = I_tdata[79:72];

    //------------ 累加器（28 位）+ 帧计数（每20帧调一次）------------
    reg [27:0] r_sum;        //一帧灰度累加（最大 921600×255 ≈ 2.35亿，28位够）
    reg [5:0]  r_frame_cnt;  //帧计数 0~39（每40帧调一次，调慢减少移动时的持续切换帧/小白点）

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            r_sum       <= 28'd0;
            r_frame_cnt <= 6'd0;
            O_avg       <= 8'd0;
            O_adjust    <= 1'b0;
        end else begin
            O_adjust <= 1'b0;   //默认清脉冲
            if(I_tuser) begin   //帧开始：输出平均亮度，清累加器
                // 平均 = sum >> 20（921600 ≈ 2^20，近似除以像素数，约14%偏低可接受）
                O_avg <= r_sum[27:20];
                r_sum <= 28'd0;
                // 帧计数：每 40 帧输出一个调节脉冲（切换帧由 video_in 丢弃，不显示）
                if(r_frame_cnt == 6'd39) begin
                    r_frame_cnt <= 6'd0;
                    O_adjust    <= 1'b1;  //第40帧，触发一次调节
                end else begin
                    r_frame_cnt <= r_frame_cnt + 1'b1;
                end
            end else if(I_tvalid) begin
                // 累加本拍 4 个像素的灰度
                r_sum <= r_sum + {20'd0, g0} + {20'd0, g1} + {20'd0, g2} + {20'd0, g3};
            end
        end
    end

endmodule
