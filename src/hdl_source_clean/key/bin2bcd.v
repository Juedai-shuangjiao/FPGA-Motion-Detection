//========================================================
// 模块：bin2bcd —— 16位二进制转 4 位 BCD（十进制）
// 算法：双 dabble（shift-and-add-3），16 次移位
// 输入：bin（16位二进制，值须 ≤ 9999，本工程曝光/增益都满足）
// 输出：bcd（16位 = 4 个 BCD 数字）
//       bcd[15:12]=千位 [11:8]=百位 [7:4]=十位 [3:0]=个位
//========================================================
module bin2bcd (
    input  wire [15:0] bin,
    output reg  [15:0] bcd
);

    integer      i;
    reg  [31:0]  shift_reg;   //高16位=BCD结果，低16位=二进制输入

    always @(*) begin
        shift_reg = {16'd0, bin};   //初始：高16位BCD清零，低16位放二进制
        for(i = 0; i < 16; i = i + 1) begin
            // 每个 BCD 位（4位一组）如果 >=5 就加 3（双 dabble 的核心）
            if(shift_reg[19:16] >= 4'd5)
                shift_reg[19:16] = shift_reg[19:16] + 4'd3;
            if(shift_reg[23:20] >= 4'd5)
                shift_reg[23:20] = shift_reg[23:20] + 4'd3;
            if(shift_reg[27:24] >= 4'd5)
                shift_reg[27:24] = shift_reg[27:24] + 4'd3;
            if(shift_reg[31:28] >= 4'd5)
                shift_reg[31:28] = shift_reg[31:28] + 4'd3;
            // 整体左移 1 位
            shift_reg = shift_reg << 1;
        end
        bcd = shift_reg[31:16];   //高16位就是 BCD 结果
    end

endmodule
