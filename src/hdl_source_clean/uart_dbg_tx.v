//========================================================
// 模块：uart_dbg_tx —— 诊断串口发送（主线错位定位专用）
// 功能：每帧开始脉冲触发一次 12 字节诊断帧发送（115200 8N1）。
//   帧格式：[0]0xAA [1]0x55 [2]half_sel [3]fg_init [4]首字写拍addr低8
//          [5]{valid,addr[14:8]} [6]dbg_rd_cnt低8 [7]中8 [8]高3
//          [9]sw4状态 [10]预留 [11]0xEE
//   12 字节 @115200 ≈ 1.04ms（帧周期 16.6ms，消隐期发完不占显示）。
// 诊断判读：A 半首字写拍 addr 应为 0（B 半 5632=0x1600）——
//   非预期值 = ERAM 写地址时序错位（插拍），数据直接定位。
//========================================================
module uart_dbg_tx #(
    parameter CLK_FRE   = 24,      //时钟频率 MHz（24M 域）
    parameter BAUD_RATE = 115200
)(
    input  wire       I_clk,          //24MHz
    input  wire       I_rst_n,        //复位低有效
    input  wire       I_send_pulse,   //发送触发脉冲（帧开始，跨域已打拍）
    input  wire [7:0] I_b0, I_b1, I_b2, I_b3,   //诊断字节 0~3
    input  wire [7:0] I_b4, I_b5, I_b6, I_b7,   //诊断字节 4~7
    input  wire [7:0] I_b8, I_b9, I_b10, I_b11, //诊断字节 8~11
    output reg        O_tx,           //串口发送（板子 H1 脚）
    output reg        O_busy          //发送中
);

    localparam CYCLE = CLK_FRE * 1000000 / BAUD_RATE;   //208（24M/115200）

    reg [3:0]  r_byte_cnt;   //当前字节 0~11
    reg [7:0]  r_shifter;    //发送移位寄存器
    reg [3:0]  r_bit_cnt;    //位计数 0~9（start+8+stop）
    reg [15:0] r_baud_cnt;   //波特率分频计数
    reg        r_sending;    //发送状态
    reg [7:0]  r_buf [0:11]; //字节组锁存

    integer i;

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            r_byte_cnt <= 4'd0;
            r_shifter  <= 8'd0;
            r_bit_cnt  <= 4'd0;
            r_baud_cnt <= 16'd0;
            r_sending  <= 1'b0;
            O_tx       <= 1'b1;   //空闲高
            O_busy     <= 1'b0;
            for (i = 0; i < 12; i = i + 1) r_buf[i] <= 8'd0;
        end else begin
            if(I_send_pulse && !r_sending) begin
                // 锁存字节组 + 启动发送
                r_buf[0]  <= I_b0;  r_buf[1]  <= I_b1;
                r_buf[2]  <= I_b2;  r_buf[3]  <= I_b3;
                r_buf[4]  <= I_b4;  r_buf[5]  <= I_b5;
                r_buf[6]  <= I_b6;  r_buf[7]  <= I_b7;
                r_buf[8]  <= I_b8;  r_buf[9]  <= I_b9;
                r_buf[10] <= I_b10; r_buf[11] <= I_b11;
                r_sending  <= 1'b1;
                r_byte_cnt <= 4'd0;
                r_bit_cnt  <= 4'd0;
                r_baud_cnt <= 16'd0;
                O_busy     <= 1'b1;
                // 起始位立即发出
                O_tx       <= 1'b0;
                r_shifter  <= I_b0;   //首字节直接用输入（r_buf[0] 当拍还是旧值）
            end else if(r_sending) begin
                r_baud_cnt <= r_baud_cnt + 1'b1;
                if(r_baud_cnt == CYCLE - 1) begin
                    r_baud_cnt <= 16'd0;
                    if(r_bit_cnt == 4'd0) begin
                        // 数据位 0（LSB）
                        O_tx      <= r_shifter[0];
                        r_shifter <= {1'b0, r_shifter[7:1]};
                        r_bit_cnt <= 4'd1;
                    end else if(r_bit_cnt < 4'd8) begin
                        // 数据位 1~7
                        O_tx      <= r_shifter[0];
                        r_shifter <= {1'b0, r_shifter[7:1]};
                        r_bit_cnt <= r_bit_cnt + 1'b1;
                    end else if(r_bit_cnt == 4'd8) begin
                        // 停止位
                        O_tx      <= 1'b1;
                        r_bit_cnt <= 4'd9;
                    end else begin
                        // 字节结束：下一字节或完成
                        r_bit_cnt <= 4'd0;
                        if(r_byte_cnt == 4'd11) begin
                            r_sending <= 1'b0;
                            O_busy    <= 1'b0;
                            O_tx      <= 1'b1;
                        end else begin
                            r_byte_cnt <= r_byte_cnt + 1'b1;
                            r_shifter  <= r_buf[r_byte_cnt + 1'b1];
                            O_tx       <= 1'b0;   //下一字节起始位
                        end
                    end
                end
            end
        end
    end

endmodule
