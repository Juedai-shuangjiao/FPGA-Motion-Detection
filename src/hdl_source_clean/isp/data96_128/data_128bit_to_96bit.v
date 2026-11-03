
//========================================================
// 模块：data_128bit_to_96bit —— 128 位流解包回 96 位流
// 功能：data_96bit_to_128bit 的逆运算。3 个 128 位 = 4 个 96 位（128 和 96 最小公倍数 384）。
//       输入 128 位流（3/4 拍有效，有空洞），输出 96 位连续流（4/4 拍）。
//========================================================
module data_128bit_to_96bit (
    input  wire        I_clk,
    input  wire        I_rst_n,

    input  wire        I_128b_frame_start,
    input  wire        I_128b_valid,
    input  wire[127:0] I_128b_data,

    output reg         O_96b_frame_start,
    output reg         O_96b_valid,
    output reg [95:0]  O_96b_data
);

    reg [127:0] S_128b_data_1d;   //上一拍 128 位
    reg [1:0]   S_cnt;            //0~2 循环（3 个 128 位一组）
    reg [95:0]  S_pending;        //缓存的第 4 个 96 位（D，输出节奏多 1 拍）
    reg         S_pending_valid;

    // 128 位打 1 拍 + 帧开始打 1 拍 + 计数（帧开始复位 S_cnt，跟打包的消隐归 0 对应）
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_128b_data_1d <= 128'd0;
            O_96b_frame_start <= 1'b0;
            S_cnt <= 2'd0;
        end else begin
            S_128b_data_1d      <= I_128b_data;
            O_96b_frame_start   <= I_128b_frame_start;
            if (I_128b_frame_start)
                S_cnt <= 2'd0;                       //帧开始，S_cnt 复位（对齐打包相位）
            else if (I_128b_valid)
                S_cnt <= (S_cnt == 2'd2) ? 2'd0 : S_cnt + 1'b1;
        end
    end

    // 解包：每 3 个 128 位拆 4 个 96 位
    // ⚠️ 2026-10-27 修复：加帧开始清 pending——原版 S_pending_valid 无复位（上电 X），
    //    首弹前（vsync→首弹 ~900 拍）解包在输入空洞拍走 else if(X) 分支输出 X 垃圾，
    //    污染 morph 链（行 0 垂直窗口上行 = X → 首行标记不清 → 列错位 + X 态写 ERAM）。
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            O_96b_valid     <= 1'b0;
            O_96b_data      <= 96'd0;
            S_pending       <= 96'd0;
            S_pending_valid <= 1'b0;
        end else if (I_128b_frame_start) begin
            O_96b_valid     <= 1'b0;
            S_pending       <= 96'd0;
            S_pending_valid <= 1'b0;   //帧头清 pending（防跨帧残留/上电 X 垃圾输出）
        end else if (I_128b_valid) begin
            case (S_cnt)
                2'd0: begin  // 输出 A = 128位1[127:32]
                    O_96b_valid <= 1'b1;
                    O_96b_data  <= I_128b_data[127:32];
                end
                2'd1: begin  // 输出 B = {128位1[31:0], 128位2[127:64]}
                    O_96b_valid <= 1'b1;
                    O_96b_data  <= {S_128b_data_1d[31:0], I_128b_data[127:64]};
                end
                2'd2: begin  // 输出 C = {128位2[63:0], 128位3[127:96]}，缓存 D = 128位3[95:0]
                    O_96b_valid    <= 1'b1;
                    O_96b_data     <= {S_128b_data_1d[63:0], I_128b_data[127:96]};
                    S_pending      <= I_128b_data[95:0];
                    S_pending_valid <= 1'b1;
                end
                default: begin
                    O_96b_valid <= 1'b0;
                end
            endcase
        end else if (S_pending_valid) begin  // 输入空洞拍，输出缓存的 D
            O_96b_valid    <= 1'b1;
            O_96b_data     <= S_pending;
            S_pending_valid <= 1'b0;
        end else begin
            O_96b_valid <= 1'b0;
        end
    end

endmodule
