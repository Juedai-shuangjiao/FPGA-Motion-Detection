module seg7#(
        parameter CLK_FREQ = 50_000_000,
        parameter SCAN_MS  = 1          //每个数码管点亮1ms
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] data,        //8个数字，每4位一个（data[3:0]=第1个 ... data[31:28]=第8个）
    output reg  [7:0]  sel,         //位选（低电平选中）
    output reg  [7:0]  seg    //段码（输出给 DIG）
);
reg  [3:0]  cur_digit;   //内部信号，供段码译码用
localparam SCAN_MAX = (CLK_FREQ / 1000) * SCAN_MS - 1;   //50MHz*1ms = 50000-1
reg [16:0] scan_cnt;
reg        scan_tick;
    // scan_cnt 数到 SCAN_MAX → scan_tick=1 → 归零重数
reg [2:0] sel_idx;   //3位，0~7
    // 每来一个 scan_tick，sel_idx + 1
    // 3位计数器 7+1=8 溢出自动回 0，所以自然在 0~7 循环
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        scan_cnt <= 0;
        scan_tick <= 0;
    end else if(scan_cnt == SCAN_MAX) begin
        scan_cnt <= 0;
        scan_tick <= 1;          //数满了，冒一个脉冲
    end else begin
        scan_cnt <= scan_cnt + 1'b1;
        scan_tick <= 0;
    end
end
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        sel_idx <= 3'd0;
    else if(scan_tick)           //每来一个扫描脉冲，索引+1
        sel_idx <= sel_idx + 1'b1;   //3位计数器 7+1=8 溢出自动回0
end
always @(*) begin
    case(sel_idx)
        3'd0 : cur_digit = data[31:28];   //最左第1个 ← 最高位
        3'd1 : cur_digit = data[27:24];
        3'd2 : cur_digit = data[23:20];
        3'd3 : cur_digit = data[19:16];
        3'd4 : cur_digit = data[15:12];
        3'd5 : cur_digit = data[11:8];
        3'd6 : cur_digit = data[7:4];
        3'd7 : cur_digit = data[3:0];     //最右第8个 ← 最低位
        default : cur_digit = 4'd0;
    endcase
end
always @(*) begin
     case(sel_idx)
        3'd0 : sel = 8'b1111_1110;   //只 sel[0]=0，选第1个
        3'd1 : sel = 8'b1111_1101;   //只 sel[1]=0，选第2个
        3'd2 : sel = 8'b1111_1011;
        3'd3 : sel = 8'b1111_0111;
        3'd4 : sel = 8'b1110_1111;
        3'd5 : sel = 8'b1101_1111;
        3'd6 : sel = 8'b1011_1111;
        3'd7 : sel = 8'b0111_1111;   //只 sel[7]=0，选第8个
        default : sel = 8'b1111_1111;  //全灭
    endcase
end
always @(*) begin
    case(cur_digit)          //注意：输入从 digit 换成 cur_digit
        4'd0 : seg = 8'hC0;
        4'd1 : seg = 8'hF9;
        4'd2 : seg = 8'hA4;
        4'd3 : seg = 8'hB0;
        4'd4 : seg = 8'h99;
        4'd5 : seg = 8'h92;
        4'd6 : seg = 8'h82;
        4'd7 : seg = 8'hF8;
        4'd8 : seg = 8'h80;
        4'd9 : seg = 8'h90;
        4'd10 : seg = 8'h88;   //A（a,b,c,e,f,g 亮）
        4'd11 : seg = 8'h83;   //b（c,d,e,f,g 亮）
        4'd12 : seg = 8'hC6;   //C（a,d,e,f 亮）
        4'd13 : seg = 8'hA1;   //d（b,c,d,e,g 亮）
        4'd14 : seg = 8'h86;   //E（a,d,e,f,g 亮）
        4'd15 : seg = 8'hFF;   //2026-11-02 修复：0xF 译码改为全灭（占位位不再显示字母F）
        default : seg = 8'hFF;
    endcase
end
endmodule
