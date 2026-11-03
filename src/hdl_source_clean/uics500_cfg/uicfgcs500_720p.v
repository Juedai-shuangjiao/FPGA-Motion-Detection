`timescale 1ns / 1ns

//========================================================
// 模块：uicfgcs500_720p —— 摄像头 SC500 的 I2C 寄存器配置
// 功能：上电后通过 I2C 逐个写寄存器表，把摄像头初始化成 1280x720@60 模式；
//       初始化完成后，如果收到曝光调节请求（I_ae_req），再写曝光/增益寄存器。
//========================================================
module uicfgcs500_720p #(
    parameter CLK_DIV = 16'd239     //I2C 时钟分频：24MHz/100kHz-1=239，产生 100kHz 的 SCL
)(
    input  wire        I_clk,        //时钟（24MHz）
    input  wire        I_rst_n,      //复位，低有效
    input  wire        I_ae_req,     //曝光调节请求（来自 ae_set）
    input  wire [15:0] I_ae,         //曝光值
    input  wire [15:0] I_ag,         //增益值
    output wire        O_cam_scl,    //I2C 时钟（输出给摄像头）
    inout  wire        IO_cam_sda,   //I2C 数据（双向）
    output reg         O_cfg_done,   //初始化完成标志
    output reg         O_ae_cfg_done //曝光配置完成标志
);

localparam CAM_ID = 8'h6c;                       //摄像头 I2C 设备地址（7 位地址 0x36 左移一位 = 0x6c）
localparam [17:0] POST_STREAM_DELAY = 18'd240000;//流开启后的延时（约 10ms，24MHz 下数 24 万）

reg [7:0]  rst_cnt = 8'd0;      //复位计数（上电延时，稳定后再开始配置）
reg        iic_req;             //I2C 写请求
wire       iic_busy;            //I2C 忙标志
reg [31:0] wr_data;             //要写的数据（设备地址+寄存器地址+寄存器值）
reg [1:0]  state;               //状态机
reg [8:0]  reg_index;           //当前写到第几个寄存器
reg [17:0] delay_cnt;           //延时计数

wire [23:0] init_data;          //初始化寄存器表输出的数据（寄存器地址+值）
wire [8:0]  init_size;          //初始化寄存器表的大小（个数）
wire [23:0] ae_data;            //曝光寄存器表输出的数据
wire [8:0]  ae_size;            //曝光寄存器表的大小
wire [23:0] selected_data = O_cfg_done ? ae_data : init_data;  //初始化完成前用初始化表，完成后用曝光表
wire [8:0]  selected_size = O_cfg_done ? ae_size : init_size;

//------------ 上电复位延时（rst_cnt 数到最高位才真正开始工作）------------
always @(posedge I_clk or negedge I_rst_n) begin
    if (!I_rst_n)
        rst_cnt <= 8'd0;
    else if (!rst_cnt[7])
        rst_cnt <= rst_cnt + 1'b1;
end

//------------ 主状态机：4 个状态，逐个写寄存器 ------------
always @(posedge I_clk) begin
    if (!rst_cnt[7]) begin               //复位延时中，全部清零
        reg_index            <= 9'd0;
        iic_req              <= 1'b0;
        wr_data              <= 32'd0;
        O_cfg_done           <= 1'b0;
        O_ae_cfg_done        <= 1'b0;
        delay_cnt            <= 18'd0;
        state                <= 2'd0;
    end else begin
        case (state)
            2'd0: begin                  //状态0：判断——还有寄存器要写吗？
                iic_req <= 1'b0;
                if (!O_cfg_done) begin   //初始化还没完成
                    if ((reg_index == 9'd115) && (delay_cnt < POST_STREAM_DELAY)) begin
                        //第 115 个寄存器后延时 10ms（0x0100=1 和 0x302d=0 之间需要延时）
                        delay_cnt <= delay_cnt + 1'b1;
                    end else if (reg_index == init_size) begin
                        //初始化表写完了
                        O_cfg_done    <= 1'b1;
                        O_ae_cfg_done <= 1'b1;
                        reg_index     <= 9'd0;
                    end else begin
                        state <= 2'd1;   //去写下一个寄存器
                    end
                end else if (I_ae_req) begin  //初始化完成，收到曝光调节请求
                    O_ae_cfg_done <= 1'b0;
                    reg_index     <= 9'd0;    //从曝光表第一个寄存器开始写
                end else if (!O_ae_cfg_done) begin
                    if (reg_index == ae_size) //曝光表写完了
                        O_ae_cfg_done <= 1'b1;
                    else
                        state <= 2'd1;        //去写下一个曝光寄存器
                end
            end
            2'd1: begin                  //状态1：发起一次 I2C 写
                if (!iic_busy) begin
                    iic_req       <= 1'b1;
                    wr_data[7:0]  <= CAM_ID;                 //设备地址
                    wr_data[15:8] <= selected_data[23:16];   //寄存器地址高 8 位
                    wr_data[23:16]<= selected_data[15:8];    //寄存器地址低 8 位
                    wr_data[31:24]<= selected_data[7:0];     //寄存器值
                    state         <= 2'd2;
                end
            end
            2'd2: begin                  //状态2：等 I2C 忙起来
                if (iic_busy) begin
                    iic_req <= 1'b0;
                    state   <= 2'd3;
                end
            end
            2'd3: begin                  //状态3：等 I2C 写完，回到状态0写下一个
                if (!iic_busy) begin
                    reg_index <= reg_index + 1'b1;
                    state     <= 2'd0;
                end
            end
        endcase
    end
end

//------------ I2C 控制器（底层时序，产生 SCL/SDA）------------
uii2c #(
    .WMEN_LEN (4),       //写字节数
    .RMEN_LEN (1),
    .CLK_DIV  (CLK_DIV)  //I2C 时钟分频
) u_i2c (
    .I_clk      (I_clk),
    .I_rstn     (rst_cnt[7]),
    .O_iic_scl  (O_cam_scl),   //SCL
    .IO_iic_sda (IO_cam_sda),  //SDA
    .I_wr_data  (wr_data),     //要写的数据
    .I_wr_cnt   (8'd4),        //写 4 个字节
    .O_rd_data  (),
    .I_rd_cnt   (8'd0),
    .I_iic_mode (1'b0),
    .I_iic_req  (iic_req),
    .O_iic_busy (iic_busy)
);

//------------ 初始化寄存器表（1280x720@60 的完整配置）------------
uics500reg_720p60 u_init_table (
    .REG_INDEX (reg_index),   //寄存器下标
    .REG_DATA  (init_data),   //输出：寄存器地址+值
    .REG_SIZE  (init_size)    //输出：寄存器个数
);

//------------ 增益查找表（把 AG 值映射成增益寄存器值）------------
wire [15:0] gain_value;
SC500GainTbl u_gain_table (
    .I_clk  (I_clk),
    .I_rstn (rst_cnt[7]),
    .I      (I_ag - 16),      //增益值减 16 作为表索引
    .O      (gain_value)      //输出：增益寄存器值
);

//------------ 曝光寄存器表（AE/AG 的寄存器配置）------------
uics500regAE u_ae_table (
    .REG_INDEX (reg_index),
    .REG_DATA  (ae_data),
    .REG_SIZE  (ae_size),
    .I_AG      (gain_value),  //增益值（经 SC500GainTbl 映射后）
    .I_AE      (I_ae)         //曝光值
);

endmodule
