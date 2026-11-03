//========================================================
// 模块：ser_arbiter —— 串行状态机仲裁（单路 DDR 三路严格分时）
// 功能：写批 → 显示读批 → 背景读批 轮转，每个状态服务一个完整 burst，
//       批未完成（busy 未降）绝不切换——命令流严格串行、无交织、无在途拖尾。
// 切换条件：本通道批完成（busy 下降）或本通道无批（busy 恒 0 时 1 拍跳过）。
// 超时保护：批服务超过 256 拍强制切换（防 ready 异常导致死锁）。
//========================================================
module ser_arbiter (
    input  wire     I_clk,           //DDR 域时钟
    input  wire     I_rst_n,         //复位，低有效
    input  wire     I_vi_busy,       //采集写批进行中（video_in 写批 valid）
    input  wire     I_vo_busy,       //显示读批进行中（video_out 读批 valid+trig）
    input  wire     I_bg_busy,       //背景读批进行中（bg_read 读批 active）
    output reg [1:0] O_state,        //当前服务状态：0=写批 1=显示读批 2=背景读批
    output wire     O_vi_grant,      //写批时间片
    output wire     O_vo_grant,      //显示读批时间片
    output wire     O_bg_grant       //背景读批时间片
);

    localparam [1:0] SER_WR = 2'd0, SER_VO = 2'd1, SER_BG = 2'd2;
    localparam [8:0] SRV_TIMEOUT = 9'd256;   //批服务超时（正常批 240 en 拍 + 少量等待）

    reg [8:0] srv_cnt;    //本状态服务拍计数（超时保护用）

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            O_state  <= SER_WR;
            srv_cnt  <= 9'd0;
        end else begin
            case(O_state)
                SER_WR: begin
                    if(!I_vi_busy) begin
                        O_state <= SER_VO;   //写批完成（或没有批）：切显示读
                        srv_cnt <= 9'd0;
                    end else if(srv_cnt == SRV_TIMEOUT) begin
                        O_state <= SER_VO;   //超时保护：强制切
                        srv_cnt <= 9'd0;
                    end else
                        srv_cnt <= srv_cnt + 1'b1;
                end
                SER_VO: begin
                    if(!I_vo_busy) begin
                        O_state <= SER_BG;   //显示读批完成：切背景读
                        srv_cnt <= 9'd0;
                    end else if(srv_cnt == SRV_TIMEOUT) begin
                        O_state <= SER_BG;
                        srv_cnt <= 9'd0;
                    end else
                        srv_cnt <= srv_cnt + 1'b1;
                end
                SER_BG: begin
                    if(!I_bg_busy) begin
                        O_state <= SER_WR;   //背景读批完成：切采集写
                        srv_cnt <= 9'd0;
                    end else if(srv_cnt == SRV_TIMEOUT) begin
                        O_state <= SER_WR;
                        srv_cnt <= 9'd0;
                    end else
                        srv_cnt <= srv_cnt + 1'b1;
                end
                default: begin
                    O_state <= SER_WR;
                    srv_cnt <= 9'd0;
                end
            endcase
        end
    end

    assign O_vi_grant = (O_state == SER_WR);
    assign O_vo_grant = (O_state == SER_VO);
    assign O_bg_grant = (O_state == SER_BG);

endmodule
