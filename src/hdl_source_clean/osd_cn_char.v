//========================================================
// 模块：osd_cn_char —— 中文字模（16×16 点阵）
// 功能：按索引输出中文/标点的 16 位点阵行，用于 OSD 文字叠加
// 索引：0=李 1=江 2=涛 3=陈 4=锐 5=张 6=展 7=鸣 8=年 9=月 10=日 11=、
// 字模由微软雅黑 Bold（msyhbd）17px 渲染生成（Python + PIL，2026-11-01 全局统一重渲）
//========================================================
module osd_cn_char (
    input  wire [6:0] I_idx,        //字符索引 0~127
    input  wire [3:0] I_row,        //行号 0~15
    output reg  [15:0] O_row_bits   //该行的 16 位点阵（bit15=最左）
);

    always @(*) begin
        case(I_idx)
            4'd0: begin  //李
                case(I_row)
                    4'd0:  O_row_bits = 16'h01C0;
                    4'd1:  O_row_bits = 16'h01C0;
                    4'd2:  O_row_bits = 16'h7FFF;
                    4'd3:  O_row_bits = 16'h7FFF;
                    4'd4:  O_row_bits = 16'h07F0;
                    4'd5:  O_row_bits = 16'h3DFE;
                    4'd6:  O_row_bits = 16'h71CF;
                    4'd7:  O_row_bits = 16'h1FFD;
                    4'd8:  O_row_bits = 16'h1FFC;
                    4'd9:  O_row_bits = 16'h0078;
                    4'd10: O_row_bits = 16'h00E0;
                    4'd11: O_row_bits = 16'h7FFF;
                    4'd12: O_row_bits = 16'h7FFF;
                    4'd13: O_row_bits = 16'h00C0;
                    4'd14: O_row_bits = 16'h07C0;
                    4'd15: O_row_bits = 16'h0780;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            4'd1: begin  //江
                case(I_row)
                    4'd0:  O_row_bits = 16'h2000;
                    4'd1:  O_row_bits = 16'h73FF;
                    4'd2:  O_row_bits = 16'h3BFF;
                    4'd3:  O_row_bits = 16'h1070;
                    4'd4:  O_row_bits = 16'h4070;
                    4'd5:  O_row_bits = 16'hE070;
                    4'd6:  O_row_bits = 16'h7870;
                    4'd7:  O_row_bits = 16'h3070;
                    4'd8:  O_row_bits = 16'h0070;
                    4'd9:  O_row_bits = 16'h3070;
                    4'd10: O_row_bits = 16'h3070;
                    4'd11: O_row_bits = 16'h3070;
                    4'd12: O_row_bits = 16'h7070;
                    4'd13: O_row_bits = 16'h77FF;
                    4'd14: O_row_bits = 16'h67FF;
                    4'd15: O_row_bits = 16'h6000;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            4'd2: begin  //涛
                case(I_row)
                    4'd0:  O_row_bits = 16'h6060;
                    4'd1:  O_row_bits = 16'h37FF;
                    4'd2:  O_row_bits = 16'h17FF;
                    4'd3:  O_row_bits = 16'h00E0;
                    4'd4:  O_row_bits = 16'h47FF;
                    4'd5:  O_row_bits = 16'h67FF;
                    4'd6:  O_row_bits = 16'h30C0;
                    4'd7:  O_row_bits = 16'h2FFF;
                    4'd8:  O_row_bits = 16'h0FFF;
                    4'd9:  O_row_bits = 16'h018E;
                    4'd10: O_row_bits = 16'h23FF;
                    4'd11: O_row_bits = 16'h33FF;
                    4'd12: O_row_bits = 16'h76CE;
                    4'd13: O_row_bits = 16'h6EEE;
                    4'd14: O_row_bits = 16'h6C7C;
                    4'd15: O_row_bits = 16'h603C;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            4'd3: begin  //陈
                case(I_row)
                    4'd0:  O_row_bits = 16'h0060;
                    4'd1:  O_row_bits = 16'h7C60;
                    4'd2:  O_row_bits = 16'h7DFF;
                    4'd3:  O_row_bits = 16'h6DFF;
                    4'd4:  O_row_bits = 16'h6CC0;
                    4'd5:  O_row_bits = 16'h69D8;
                    4'd6:  O_row_bits = 16'h7998;
                    4'd7:  O_row_bits = 16'h7998;
                    4'd8:  O_row_bits = 16'h7FFF;
                    4'd9:  O_row_bits = 16'h6FFF;
                    4'd10: O_row_bits = 16'h6C18;
                    4'd11: O_row_bits = 16'h6C9A;
                    4'd12: O_row_bits = 16'h7DDF;
                    4'd13: O_row_bits = 16'h799B;
                    4'd14: O_row_bits = 16'h631B;
                    4'd15: O_row_bits = 16'h61F9;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            4'd4: begin  //锐
                case(I_row)
                    4'd0:  O_row_bits = 16'h3084;
                    4'd1:  O_row_bits = 16'h31CE;
                    4'd2:  O_row_bits = 16'h7CCC;
                    4'd3:  O_row_bits = 16'h7CCC;
                    4'd4:  O_row_bits = 16'h61FF;
                    4'd5:  O_row_bits = 16'hFDFF;
                    4'd6:  O_row_bits = 16'h7D87;
                    4'd7:  O_row_bits = 16'h3187;
                    4'd8:  O_row_bits = 16'h3187;
                    4'd9:  O_row_bits = 16'hFDFF;
                    4'd10: O_row_bits = 16'hFDFF;
                    4'd11: O_row_bits = 16'h30DC;
                    4'd12: O_row_bits = 16'h30DC;
                    4'd13: O_row_bits = 16'h34DD;
                    4'd14: O_row_bits = 16'h3DDD;
                    4'd15: O_row_bits = 16'h379F;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            4'd5: begin  //张
                case(I_row)
                    4'd0:  O_row_bits = 16'h00C0;
                    4'd1:  O_row_bits = 16'h7CC2;
                    4'd2:  O_row_bits = 16'h7CC7;
                    4'd3:  O_row_bits = 16'h0CCE;
                    4'd4:  O_row_bits = 16'h0CDC;
                    4'd5:  O_row_bits = 16'h7CD0;
                    4'd6:  O_row_bits = 16'h7CC0;
                    4'd7:  O_row_bits = 16'h61FF;
                    4'd8:  O_row_bits = 16'h61FF;
                    4'd9:  O_row_bits = 16'h7CD8;
                    4'd10: O_row_bits = 16'h7CD8;
                    4'd11: O_row_bits = 16'h0CCC;
                    4'd12: O_row_bits = 16'h0CCC;
                    4'd13: O_row_bits = 16'h0CCE;
                    4'd14: O_row_bits = 16'h1DF7;
                    4'd15: O_row_bits = 16'h7DF3;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            4'd6: begin  //展
                case(I_row)
                    4'd0:  O_row_bits = 16'h0000;
                    4'd1:  O_row_bits = 16'h3FFF;
                    4'd2:  O_row_bits = 16'h3FFF;
                    4'd3:  O_row_bits = 16'h3007;
                    4'd4:  O_row_bits = 16'h3007;
                    4'd5:  O_row_bits = 16'h3FFF;
                    4'd6:  O_row_bits = 16'h3318;
                    4'd7:  O_row_bits = 16'h3318;
                    4'd8:  O_row_bits = 16'h3FFF;
                    4'd9:  O_row_bits = 16'h3318;
                    4'd10: O_row_bits = 16'h7318;
                    4'd11: O_row_bits = 16'h7FFF;
                    4'd12: O_row_bits = 16'h7666;
                    4'd13: O_row_bits = 16'h667F;
                    4'd14: O_row_bits = 16'h667C;
                    4'd15: O_row_bits = 16'h67DF;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            4'd7: begin  //鸣
                case(I_row)
                    4'd0:  O_row_bits = 16'h0030;
                    4'd1:  O_row_bits = 16'h7DFF;
                    4'd2:  O_row_bits = 16'h7DFF;
                    4'd3:  O_row_bits = 16'h6DB3;
                    4'd4:  O_row_bits = 16'h6DB2;
                    4'd5:  O_row_bits = 16'h6D96;
                    4'd6:  O_row_bits = 16'h6D9E;
                    4'd7:  O_row_bits = 16'h6D9C;
                    4'd8:  O_row_bits = 16'h6DFF;
                    4'd9:  O_row_bits = 16'h6DFF;
                    4'd10: O_row_bits = 16'h6C03;
                    4'd11: O_row_bits = 16'h7FFB;
                    4'd12: O_row_bits = 16'h7FFB;
                    4'd13: O_row_bits = 16'h6C03;
                    4'd14: O_row_bits = 16'h003F;
                    4'd15: O_row_bits = 16'h003E;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            4'd8: begin  //年
                case(I_row)
                    4'd0:  O_row_bits = 16'h0E00;
                    4'd1:  O_row_bits = 16'h0C00;
                    4'd2:  O_row_bits = 16'h1FFF;
                    4'd3:  O_row_bits = 16'h3FFF;
                    4'd4:  O_row_bits = 16'h78E0;
                    4'd5:  O_row_bits = 16'h70E0;
                    4'd6:  O_row_bits = 16'h7FFE;
                    4'd7:  O_row_bits = 16'h1FFE;
                    4'd8:  O_row_bits = 16'h18E0;
                    4'd9:  O_row_bits = 16'h18E0;
                    4'd10: O_row_bits = 16'h18E0;
                    4'd11: O_row_bits = 16'hFFFF;
                    4'd12: O_row_bits = 16'hFFFF;
                    4'd13: O_row_bits = 16'h00E0;
                    4'd14: O_row_bits = 16'h00E0;
                    4'd15: O_row_bits = 16'h00E0;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            4'd9: begin  //月
                case(I_row)
                    4'd0:  O_row_bits = 16'h0000;
                    4'd1:  O_row_bits = 16'h1FFE;
                    4'd2:  O_row_bits = 16'h1FFE;
                    4'd3:  O_row_bits = 16'h1806;
                    4'd4:  O_row_bits = 16'h1806;
                    4'd5:  O_row_bits = 16'h1FFE;
                    4'd6:  O_row_bits = 16'h1FFE;
                    4'd7:  O_row_bits = 16'h1806;
                    4'd8:  O_row_bits = 16'h1806;
                    4'd9:  O_row_bits = 16'h1FFE;
                    4'd10: O_row_bits = 16'h1FFE;
                    4'd11: O_row_bits = 16'h1806;
                    4'd12: O_row_bits = 16'h3806;
                    4'd13: O_row_bits = 16'h3806;
                    4'd14: O_row_bits = 16'h700E;
                    4'd15: O_row_bits = 16'h707E;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            4'd10: begin  //日
                case(I_row)
                    4'd0:  O_row_bits = 16'h0000;
                    4'd1:  O_row_bits = 16'h3FFE;
                    4'd2:  O_row_bits = 16'h3FFE;
                    4'd3:  O_row_bits = 16'h3806;
                    4'd4:  O_row_bits = 16'h3806;
                    4'd5:  O_row_bits = 16'h3806;
                    4'd6:  O_row_bits = 16'h3806;
                    4'd7:  O_row_bits = 16'h3FFE;
                    4'd8:  O_row_bits = 16'h3FFE;
                    4'd9:  O_row_bits = 16'h3806;
                    4'd10: O_row_bits = 16'h3806;
                    4'd11: O_row_bits = 16'h3806;
                    4'd12: O_row_bits = 16'h3806;
                    4'd13: O_row_bits = 16'h3806;
                    4'd14: O_row_bits = 16'h3FFE;
                    4'd15: O_row_bits = 16'h3FFE;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            4'd11: begin  //、
                case(I_row)
                    4'd0:  O_row_bits = 16'h0000;
                    4'd1:  O_row_bits = 16'h0000;
                    4'd2:  O_row_bits = 16'h0000;
                    4'd3:  O_row_bits = 16'h0000;
                    4'd4:  O_row_bits = 16'h0000;
                    4'd5:  O_row_bits = 16'h0000;
                    4'd6:  O_row_bits = 16'h0000;
                    4'd7:  O_row_bits = 16'h0000;
                    4'd8:  O_row_bits = 16'h0000;
                    4'd9:  O_row_bits = 16'h0000;
                    4'd10: O_row_bits = 16'h0000;
                    4'd11: O_row_bits = 16'h0000;
                    4'd12: O_row_bits = 16'h6000;
                    4'd13: O_row_bits = 16'h7800;
                    4'd14: O_row_bits = 16'h3C00;
                    4'd15: O_row_bits = 16'h1800;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            4'd12: begin  //小
                case(I_row)
                    4'd0:  O_row_bits = 16'h01C0;
                    4'd1:  O_row_bits = 16'h01C0;
                    4'd2:  O_row_bits = 16'h01C0;
                    4'd3:  O_row_bits = 16'h01C0;
                    4'd4:  O_row_bits = 16'h19CC;
                    4'd5:  O_row_bits = 16'h39CC;
                    4'd6:  O_row_bits = 16'h39CE;
                    4'd7:  O_row_bits = 16'h39CE;
                    4'd8:  O_row_bits = 16'h31C7;
                    4'd9:  O_row_bits = 16'h71C7;
                    4'd10: O_row_bits = 16'h71C7;
                    4'd11: O_row_bits = 16'h61C3;
                    4'd12: O_row_bits = 16'h61C3;
                    4'd13: O_row_bits = 16'h01C0;
                    4'd14: O_row_bits = 16'h01C0;
                    4'd15: O_row_bits = 16'h0FC0;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            4'd13: begin  //组
                case(I_row)
                    4'd0:  O_row_bits = 16'h1800;
                    4'd1:  O_row_bits = 16'h19FF;
                    4'd2:  O_row_bits = 16'h31FF;
                    4'd3:  O_row_bits = 16'h7787;
                    4'd4:  O_row_bits = 16'h6F87;
                    4'd5:  O_row_bits = 16'hFDFF;
                    4'd6:  O_row_bits = 16'h7DFF;
                    4'd7:  O_row_bits = 16'h1987;
                    4'd8:  O_row_bits = 16'h3187;
                    4'd9:  O_row_bits = 16'h75FF;
                    4'd10: O_row_bits = 16'h7DFF;
                    4'd11: O_row_bits = 16'h7187;
                    4'd12: O_row_bits = 16'h0187;
                    4'd13: O_row_bits = 16'h1D87;
                    4'd14: O_row_bits = 16'hFFFF;
                    4'd15: O_row_bits = 16'h63FF;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            4'd14: begin  //成
                case(I_row)
                    4'd0:  O_row_bits = 16'h0076;
                    4'd1:  O_row_bits = 16'h0076;
                    4'd2:  O_row_bits = 16'h0073;
                    4'd3:  O_row_bits = 16'h3FFF;
                    4'd4:  O_row_bits = 16'h3FFF;
                    4'd5:  O_row_bits = 16'h3030;
                    4'd6:  O_row_bits = 16'h3032;
                    4'd7:  O_row_bits = 16'h3FB7;
                    4'd8:  O_row_bits = 16'h3F36;
                    4'd9:  O_row_bits = 16'h333E;
                    4'd10: O_row_bits = 16'h333C;
                    4'd11: O_row_bits = 16'h733D;
                    4'd12: O_row_bits = 16'h7F39;
                    4'd13: O_row_bits = 16'h6E7B;
                    4'd14: O_row_bits = 16'h60FB;
                    4'd15: O_row_bits = 16'hE1CF;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            4'd15: begin  //员
                case(I_row)
                    4'd0:  O_row_bits = 16'h0000;
                    4'd1:  O_row_bits = 16'h3FFE;
                    4'd2:  O_row_bits = 16'h3FFE;
                    4'd3:  O_row_bits = 16'h380E;
                    4'd4:  O_row_bits = 16'h3FFE;
                    4'd5:  O_row_bits = 16'h3FFE;
                    4'd6:  O_row_bits = 16'h0000;
                    4'd7:  O_row_bits = 16'h3FFE;
                    4'd8:  O_row_bits = 16'h3FFE;
                    4'd9:  O_row_bits = 16'h3006;
                    4'd10: O_row_bits = 16'h30C6;
                    4'd11: O_row_bits = 16'h31C6;
                    4'd12: O_row_bits = 16'h31E6;
                    4'd13: O_row_bits = 16'h03F8;
                    4'd14: O_row_bits = 16'h1F3E;
                    4'd15: O_row_bits = 16'h7C0F;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            5'd16: begin  //曝
                case(I_row)
                    4'd0:  O_row_bits = 16'h0000;
                    4'd1:  O_row_bits = 16'h7BFF;
                    4'd2:  O_row_bits = 16'h7B03;
                    4'd3:  O_row_bits = 16'h7BFF;
                    4'd4:  O_row_bits = 16'h7B03;
                    4'd5:  O_row_bits = 16'h7BFF;
                    4'd6:  O_row_bits = 16'h78CC;
                    4'd7:  O_row_bits = 16'h7BFF;
                    4'd8:  O_row_bits = 16'h78CC;
                    4'd9:  O_row_bits = 16'h7FFF;
                    4'd10:  O_row_bits = 16'h798E;
                    4'd11:  O_row_bits = 16'h7BB7;
                    4'd12:  O_row_bits = 16'h7EFD;
                    4'd13:  O_row_bits = 16'h79BE;
                    4'd14:  O_row_bits = 16'h67B7;
                    4'd15:  O_row_bits = 16'h02E1;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            5'd17: begin  //光
                case(I_row)
                    4'd0:  O_row_bits = 16'h01C0;
                    4'd1:  O_row_bits = 16'h31C4;
                    4'd2:  O_row_bits = 16'h79CF;
                    4'd3:  O_row_bits = 16'h39CE;
                    4'd4:  O_row_bits = 16'h1DDC;
                    4'd5:  O_row_bits = 16'h09C8;
                    4'd6:  O_row_bits = 16'h01C0;
                    4'd7:  O_row_bits = 16'hFFFF;
                    4'd8:  O_row_bits = 16'hFFFF;
                    4'd9:  O_row_bits = 16'h0670;
                    4'd10:  O_row_bits = 16'h0E70;
                    4'd11:  O_row_bits = 16'h0E70;
                    4'd12:  O_row_bits = 16'h0E73;
                    4'd13:  O_row_bits = 16'h1C73;
                    4'd14:  O_row_bits = 16'h3C73;
                    4'd15:  O_row_bits = 16'h787F;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            5'd18: begin  //值
                case(I_row)
                    4'd0:  O_row_bits = 16'h1870;
                    4'd1:  O_row_bits = 16'h1FFF;
                    4'd2:  O_row_bits = 16'h3FFF;
                    4'd3:  O_row_bits = 16'h3070;
                    4'd4:  O_row_bits = 16'h73FF;
                    4'd5:  O_row_bits = 16'h7303;
                    4'd6:  O_row_bits = 16'hF303;
                    4'd7:  O_row_bits = 16'hF3FF;
                    4'd8:  O_row_bits = 16'hB303;
                    4'd9:  O_row_bits = 16'h33FF;
                    4'd10:  O_row_bits = 16'h3303;
                    4'd11:  O_row_bits = 16'h33FF;
                    4'd12:  O_row_bits = 16'h3303;
                    4'd13:  O_row_bits = 16'h3303;
                    4'd14:  O_row_bits = 16'h3FFF;
                    4'd15:  O_row_bits = 16'h3FFF;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            5'd19: begin  //增
                case(I_row)
                    4'd0:  O_row_bits = 16'h318C;
                    4'd1:  O_row_bits = 16'h31CC;
                    4'd2:  O_row_bits = 16'h37FF;
                    4'd3:  O_row_bits = 16'h37FF;
                    4'd4:  O_row_bits = 16'h3633;
                    4'd5:  O_row_bits = 16'h7EB7;
                    4'd6:  O_row_bits = 16'h7EBB;
                    4'd7:  O_row_bits = 16'h3633;
                    4'd8:  O_row_bits = 16'h37FF;
                    4'd9:  O_row_bits = 16'h37FF;
                    4'd10:  O_row_bits = 16'h3000;
                    4'd11:  O_row_bits = 16'h33FE;
                    4'd12:  O_row_bits = 16'h3B06;
                    4'd13:  O_row_bits = 16'hFBFE;
                    4'd14:  O_row_bits = 16'h4306;
                    4'd15:  O_row_bits = 16'h03FE;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            5'd20: begin  //益
                case(I_row)
                    4'd0:  O_row_bits = 16'h0808;
                    4'd1:  O_row_bits = 16'h1C1C;
                    4'd2:  O_row_bits = 16'h0E38;
                    4'd3:  O_row_bits = 16'h7FFF;
                    4'd4:  O_row_bits = 16'h7FFF;
                    4'd5:  O_row_bits = 16'h0630;
                    4'd6:  O_row_bits = 16'h0F3C;
                    4'd7:  O_row_bits = 16'h3C1E;
                    4'd8:  O_row_bits = 16'h7807;
                    4'd9:  O_row_bits = 16'h7FFF;
                    4'd10:  O_row_bits = 16'h3FFE;
                    4'd11:  O_row_bits = 16'h3366;
                    4'd12:  O_row_bits = 16'h3366;
                    4'd13:  O_row_bits = 16'h3366;
                    4'd14:  O_row_bits = 16'hFFFF;
                    4'd15:  O_row_bits = 16'hFFFF;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            5'd21: begin  //（左括号
                case(I_row)
                    4'd0:  O_row_bits = 16'h0000;
                    4'd1:  O_row_bits = 16'h0003;
                    4'd2:  O_row_bits = 16'h0006;
                    4'd3:  O_row_bits = 16'h000C;
                    4'd4:  O_row_bits = 16'h000C;
                    4'd5:  O_row_bits = 16'h000C;
                    4'd6:  O_row_bits = 16'h0018;
                    4'd7:  O_row_bits = 16'h0018;
                    4'd8:  O_row_bits = 16'h0018;
                    4'd9:  O_row_bits = 16'h0018;
                    4'd10:  O_row_bits = 16'h0018;
                    4'd11:  O_row_bits = 16'h0018;
                    4'd12:  O_row_bits = 16'h000C;
                    4'd13:  O_row_bits = 16'h000C;
                    4'd14:  O_row_bits = 16'h000C;
                    4'd15:  O_row_bits = 16'h0006;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            5'd22: begin  //）右括号
                case(I_row)
                    4'd0:  O_row_bits = 16'h0000;
                    4'd1:  O_row_bits = 16'h6000;
                    4'd2:  O_row_bits = 16'h3000;
                    4'd3:  O_row_bits = 16'h1800;
                    4'd4:  O_row_bits = 16'h1800;
                    4'd5:  O_row_bits = 16'h1800;
                    4'd6:  O_row_bits = 16'h0C00;
                    4'd7:  O_row_bits = 16'h0C00;
                    4'd8:  O_row_bits = 16'h0C00;
                    4'd9:  O_row_bits = 16'h0C00;
                    4'd10:  O_row_bits = 16'h0C00;
                    4'd11:  O_row_bits = 16'h0C00;
                    4'd12:  O_row_bits = 16'h1800;
                    4'd13:  O_row_bits = 16'h1800;
                    4'd14:  O_row_bits = 16'h1800;
                    4'd15:  O_row_bits = 16'h3000;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            5'd23: begin  //A
                case(I_row)
                    4'd0:  O_row_bits = 16'h0000;
                    4'd1:  O_row_bits = 16'h0780;
                    4'd2:  O_row_bits = 16'h0780;
                    4'd3:  O_row_bits = 16'h0FC0;
                    4'd4:  O_row_bits = 16'h0FC0;
                    4'd5:  O_row_bits = 16'h0FC0;
                    4'd6:  O_row_bits = 16'h1CE0;
                    4'd7:  O_row_bits = 16'h1CE0;
                    4'd8:  O_row_bits = 16'h1CE0;
                    4'd9:  O_row_bits = 16'h3FF0;
                    4'd10:  O_row_bits = 16'h3FF0;
                    4'd11:  O_row_bits = 16'h3FF0;
                    4'd12:  O_row_bits = 16'h7878;
                    4'd13:  O_row_bits = 16'h7038;
                    4'd14:  O_row_bits = 16'h0000;
                    4'd15:  O_row_bits = 16'h0000;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            5'd24: begin  //E
                case(I_row)
                    4'd0:  O_row_bits = 16'h0000;
                    4'd1:  O_row_bits = 16'h7F80;
                    4'd2:  O_row_bits = 16'h7F80;
                    4'd3:  O_row_bits = 16'h7F80;
                    4'd4:  O_row_bits = 16'h7000;
                    4'd5:  O_row_bits = 16'h7000;
                    4'd6:  O_row_bits = 16'h7F00;
                    4'd7:  O_row_bits = 16'h7F00;
                    4'd8:  O_row_bits = 16'h7F00;
                    4'd9:  O_row_bits = 16'h7000;
                    4'd10:  O_row_bits = 16'h7000;
                    4'd11:  O_row_bits = 16'h7F80;
                    4'd12:  O_row_bits = 16'h7F80;
                    4'd13:  O_row_bits = 16'h7F80;
                    4'd14:  O_row_bits = 16'h0000;
                    4'd15:  O_row_bits = 16'h0000;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            5'd25: begin  //G
                case(I_row)
                    4'd0:  O_row_bits = 16'h0000;
                    4'd1:  O_row_bits = 16'h07C0;
                    4'd2:  O_row_bits = 16'h1FE0;
                    4'd3:  O_row_bits = 16'h3FE0;
                    4'd4:  O_row_bits = 16'h3C20;
                    4'd5:  O_row_bits = 16'h7800;
                    4'd6:  O_row_bits = 16'h7000;
                    4'd7:  O_row_bits = 16'h71F0;
                    4'd8:  O_row_bits = 16'h71F0;
                    4'd9:  O_row_bits = 16'h7070;
                    4'd10:  O_row_bits = 16'h3870;
                    4'd11:  O_row_bits = 16'h3FF0;
                    4'd12:  O_row_bits = 16'h1FF0;
                    4'd13:  O_row_bits = 16'h07E0;
                    4'd14:  O_row_bits = 16'h0000;
                    4'd15:  O_row_bits = 16'h0000;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            5'd26: begin  //原
                case(I_row)
                    4'd0:  O_row_bits = 16'h0000;
                    4'd1:  O_row_bits = 16'h3FFF;
                    4'd2:  O_row_bits = 16'h3FFF;
                    4'd3:  O_row_bits = 16'h30E0;
                    4'd4:  O_row_bits = 16'h37FF;
                    4'd5:  O_row_bits = 16'h37FF;
                    4'd6:  O_row_bits = 16'h3607;
                    4'd7:  O_row_bits = 16'h37FF;
                    4'd8:  O_row_bits = 16'h3607;
                    4'd9:  O_row_bits = 16'h37FF;
                    4'd10:  O_row_bits = 16'h37FF;
                    4'd11:  O_row_bits = 16'h3070;
                    4'd12:  O_row_bits = 16'h7274;
                    4'd13:  O_row_bits = 16'h777E;
                    4'd14:  O_row_bits = 16'h6E77;
                    4'd15:  O_row_bits = 16'hFDF3;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            5'd27: begin  //样
                case(I_row)
                    4'd0:  O_row_bits = 16'h30C6;
                    4'd1:  O_row_bits = 16'h30C6;
                    4'd2:  O_row_bits = 16'h30EE;
                    4'd3:  O_row_bits = 16'hFDFF;
                    4'd4:  O_row_bits = 16'hFDFF;
                    4'd5:  O_row_bits = 16'h3030;
                    4'd6:  O_row_bits = 16'h3030;
                    4'd7:  O_row_bits = 16'h7DFF;
                    4'd8:  O_row_bits = 16'h7FFF;
                    4'd9:  O_row_bits = 16'hF430;
                    4'd10:  O_row_bits = 16'hF030;
                    4'd11:  O_row_bits = 16'hF3FF;
                    4'd12:  O_row_bits = 16'h33FF;
                    4'd13:  O_row_bits = 16'h3030;
                    4'd14:  O_row_bits = 16'h3030;
                    4'd15:  O_row_bits = 16'h3030;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            5'd28: begin  //灰
                case(I_row)
                    4'd0:  O_row_bits = 16'h1C00;
                    4'd1:  O_row_bits = 16'h1C00;
                    4'd2:  O_row_bits = 16'h7FFF;
                    4'd3:  O_row_bits = 16'h7FFF;
                    4'd4:  O_row_bits = 16'h1800;
                    4'd5:  O_row_bits = 16'h1870;
                    4'd6:  O_row_bits = 16'h1C72;
                    4'd7:  O_row_bits = 16'h1E67;
                    4'd8:  O_row_bits = 16'h3F67;
                    4'd9:  O_row_bits = 16'h3BEE;
                    4'd10:  O_row_bits = 16'h3264;
                    4'd11:  O_row_bits = 16'h70F0;
                    4'd12:  O_row_bits = 16'h70F8;
                    4'd13:  O_row_bits = 16'h61DC;
                    4'd14:  O_row_bits = 16'hE78E;
                    4'd15:  O_row_bits = 16'h4F07;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            5'd29: begin  //度
                case(I_row)
                    4'd0:  O_row_bits = 16'h00C0;
                    4'd1:  O_row_bits = 16'h00E0;
                    4'd2:  O_row_bits = 16'h7FFF;
                    4'd3:  O_row_bits = 16'h7FFF;
                    4'd4:  O_row_bits = 16'h730C;
                    4'd5:  O_row_bits = 16'h7FFF;
                    4'd6:  O_row_bits = 16'h7FFF;
                    4'd7:  O_row_bits = 16'h730C;
                    4'd8:  O_row_bits = 16'h73FC;
                    4'd9:  O_row_bits = 16'h73FC;
                    4'd10:  O_row_bits = 16'h6000;
                    4'd11:  O_row_bits = 16'h6FFE;
                    4'd12:  O_row_bits = 16'h6FFE;
                    4'd13:  O_row_bits = 16'h630E;
                    4'd14:  O_row_bits = 16'hE1F8;
                    4'd15:  O_row_bits = 16'hFFFF;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            5'd30: begin  //二
                case(I_row)
                    4'd0:  O_row_bits = 16'h0000;
                    4'd1:  O_row_bits = 16'h0000;
                    4'd2:  O_row_bits = 16'h3FFE;
                    4'd3:  O_row_bits = 16'h3FFE;
                    4'd4:  O_row_bits = 16'h0000;
                    4'd5:  O_row_bits = 16'h0000;
                    4'd6:  O_row_bits = 16'h0000;
                    4'd7:  O_row_bits = 16'h0000;
                    4'd8:  O_row_bits = 16'h0000;
                    4'd9:  O_row_bits = 16'h0000;
                    4'd10:  O_row_bits = 16'h0000;
                    4'd11:  O_row_bits = 16'h0000;
                    4'd12:  O_row_bits = 16'h7FFF;
                    4'd13:  O_row_bits = 16'h7FFF;
                    4'd14:  O_row_bits = 16'h0000;
                    4'd15:  O_row_bits = 16'h0000;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            5'd31: begin  //阈
                case(I_row)
                    4'd0:  O_row_bits = 16'h0800;
                    4'd1:  O_row_bits = 16'h1DFF;
                    4'd2:  O_row_bits = 16'h6DFF;
                    4'd3:  O_row_bits = 16'h607B;
                    4'd4:  O_row_bits = 16'h6FFF;
                    4'd5:  O_row_bits = 16'h6FFF;
                    4'd6:  O_row_bits = 16'h6063;
                    4'd7:  O_row_bits = 16'h6F7B;
                    4'd8:  O_row_bits = 16'h697B;
                    4'd9:  O_row_bits = 16'h6F73;
                    4'd10:  O_row_bits = 16'h6F7F;
                    4'd11:  O_row_bits = 16'h607F;
                    4'd12:  O_row_bits = 16'h7FFB;
                    4'd13: O_row_bits = 16'h6E9B;
                    4'd14: O_row_bits = 16'h601F;
                    4'd15: O_row_bits = 16'h601E;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            6'd32: begin  //帧
                case(I_row)
                    4'd0:  O_row_bits = 16'h1838;
                    4'd1:  O_row_bits = 16'h183F;
                    4'd2:  O_row_bits = 16'h7E3F;
                    4'd3:  O_row_bits = 16'h7E38;
                    4'd4:  O_row_bits = 16'h5AFF;
                    4'd5:  O_row_bits = 16'h5AFF;
                    4'd6:  O_row_bits = 16'h5AC3;
                    4'd7:  O_row_bits = 16'h5ADB;
                    4'd8:  O_row_bits = 16'h5ADB;
                    4'd9:  O_row_bits = 16'h5ADB;
                    4'd10: O_row_bits = 16'h5ADB;
                    4'd11: O_row_bits = 16'h5EFF;
                    4'd12: O_row_bits = 16'h5EFE;
                    4'd13: O_row_bits = 16'h1877;
                    4'd14: O_row_bits = 16'h19E3;
                    4'd15: O_row_bits = 16'h1881;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            6'd33: begin  //号
                case(I_row)
                    4'd0:  O_row_bits = 16'h0000;
                    4'd1:  O_row_bits = 16'h3FFE;
                    4'd2:  O_row_bits = 16'h3FFE;
                    4'd3:  O_row_bits = 16'h380E;
                    4'd4:  O_row_bits = 16'h3FFE;
                    4'd5:  O_row_bits = 16'h3FFE;
                    4'd6:  O_row_bits = 16'h0000;
                    4'd7:  O_row_bits = 16'hFFFF;
                    4'd8:  O_row_bits = 16'hFFFF;
                    4'd9:  O_row_bits = 16'h1800;
                    4'd10: O_row_bits = 16'h1FFE;
                    4'd11: O_row_bits = 16'h1FFE;
                    4'd12: O_row_bits = 16'h000E;
                    4'd13: O_row_bits = 16'h000C;
                    4'd14: O_row_bits = 16'h03FC;
                    4'd15: O_row_bits = 16'h01F8;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            6'd34: begin  //边
                case(I_row)
                    4'd0:  O_row_bits = 16'h20C0;
                    4'd1:  O_row_bits = 16'h70C0;
                    4'd2:  O_row_bits = 16'h30C0;
                    4'd3:  O_row_bits = 16'h3FFF;
                    4'd4:  O_row_bits = 16'h17FF;
                    4'd5:  O_row_bits = 16'h00C7;
                    4'd6:  O_row_bits = 16'hF8C7;
                    4'd7:  O_row_bits = 16'hF8C7;
                    4'd8:  O_row_bits = 16'h39C7;
                    4'd9:  O_row_bits = 16'h3987;
                    4'd10: O_row_bits = 16'h3B86;
                    4'd11: O_row_bits = 16'h3F3E;
                    4'd12: O_row_bits = 16'h3A1E;
                    4'd13: O_row_bits = 16'h7C00;
                    4'd14: O_row_bits = 16'hEFFF;
                    4'd15: O_row_bits = 16'h47FF;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            6'd35: begin  //缘
                case(I_row)
                    4'd0:  O_row_bits = 16'h1180;
                    4'd1:  O_row_bits = 16'h39FE;
                    4'd2:  O_row_bits = 16'h3186;
                    4'd3:  O_row_bits = 16'h6D86;
                    4'd4:  O_row_bits = 16'h6DFE;
                    4'd5:  O_row_bits = 16'hF80C;
                    4'd6:  O_row_bits = 16'h7BFF;
                    4'd7:  O_row_bits = 16'h30E0;
                    4'd8:  O_row_bits = 16'h29F3;
                    4'd9:  O_row_bits = 16'h7E7E;
                    4'd10: O_row_bits = 16'h78DE;
                    4'd11: O_row_bits = 16'h63BE;
                    4'd12: O_row_bits = 16'h027B;
                    4'd13: O_row_bits = 16'h19DB;
                    4'd14: O_row_bits = 16'hFF99;
                    4'd15: O_row_bits = 16'h6379;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            6'd36: begin  //自
                case(I_row)
                    4'd0:  O_row_bits = 16'h01C0;
                    4'd1:  O_row_bits = 16'h0180;
                    4'd2:  O_row_bits = 16'h3FFE;
                    4'd3:  O_row_bits = 16'h3FFE;
                    4'd4:  O_row_bits = 16'h3006;
                    4'd5:  O_row_bits = 16'h3006;
                    4'd6:  O_row_bits = 16'h3FFE;
                    4'd7:  O_row_bits = 16'h3FFE;
                    4'd8:  O_row_bits = 16'h3006;
                    4'd9:  O_row_bits = 16'h3006;
                    4'd10: O_row_bits = 16'h3FFE;
                    4'd11: O_row_bits = 16'h3FFE;
                    4'd12: O_row_bits = 16'h3006;
                    4'd13: O_row_bits = 16'h3006;
                    4'd14: O_row_bits = 16'h3FFE;
                    4'd15: O_row_bits = 16'h3FFE;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            6'd37: begin  //动
                case(I_row)
                    4'd0:  O_row_bits = 16'h0030;
                    4'd1:  O_row_bits = 16'h7E70;
                    4'd2:  O_row_bits = 16'h7E70;
                    4'd3:  O_row_bits = 16'h00FF;
                    4'd4:  O_row_bits = 16'h00FF;
                    4'd5:  O_row_bits = 16'hFF73;
                    4'd6:  O_row_bits = 16'hFF73;
                    4'd7:  O_row_bits = 16'h3873;
                    4'd8:  O_row_bits = 16'h3073;
                    4'd9:  O_row_bits = 16'h3663;
                    4'd10: O_row_bits = 16'h7663;
                    4'd11: O_row_bits = 16'h7763;
                    4'd12: O_row_bits = 16'h6363;
                    4'd13: O_row_bits = 16'hFFE3;
                    4'd14: O_row_bits = 16'h7FC3;
                    4'd15: O_row_bits = 16'h01DF;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            6'd38: begin  //手
                case(I_row)
                    4'd0:  O_row_bits = 16'h001E;
                    4'd1:  O_row_bits = 16'h7FFF;
                    4'd2:  O_row_bits = 16'h3FC0;
                    4'd3:  O_row_bits = 16'h00C0;
                    4'd4:  O_row_bits = 16'h00C0;
                    4'd5:  O_row_bits = 16'h7FFF;
                    4'd6:  O_row_bits = 16'h7FFF;
                    4'd7:  O_row_bits = 16'h00C0;
                    4'd8:  O_row_bits = 16'h00C0;
                    4'd9:  O_row_bits = 16'h00C0;
                    4'd10: O_row_bits = 16'hFFFF;
                    4'd11: O_row_bits = 16'hFFFF;
                    4'd12: O_row_bits = 16'h00C0;
                    4'd13: O_row_bits = 16'h00C0;
                    4'd14: O_row_bits = 16'h01C0;
                    4'd15: O_row_bits = 16'h0FC0;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            6'd39: begin  //目
                case(I_row)
                    4'd0:  O_row_bits = 16'h0000;
                    4'd1:  O_row_bits = 16'h3FFE;
                    4'd2:  O_row_bits = 16'h3FFE;
                    4'd3:  O_row_bits = 16'h3006;
                    4'd4:  O_row_bits = 16'h3006;
                    4'd5:  O_row_bits = 16'h3FFE;
                    4'd6:  O_row_bits = 16'h3FFE;
                    4'd7:  O_row_bits = 16'h3006;
                    4'd8:  O_row_bits = 16'h3006;
                    4'd9:  O_row_bits = 16'h3FFE;
                    4'd10: O_row_bits = 16'h3FFE;
                    4'd11: O_row_bits = 16'h3006;
                    4'd12: O_row_bits = 16'h3006;
                    4'd13: O_row_bits = 16'h3006;
                    4'd14: O_row_bits = 16'h3FFE;
                    4'd15: O_row_bits = 16'h3FFE;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            6'd40: begin  //标
                case(I_row)
                    4'd0:  O_row_bits = 16'h3000;
                    4'd1:  O_row_bits = 16'h31FF;
                    4'd2:  O_row_bits = 16'h31FF;
                    4'd3:  O_row_bits = 16'hFC00;
                    4'd4:  O_row_bits = 16'hFC00;
                    4'd5:  O_row_bits = 16'h33FF;
                    4'd6:  O_row_bits = 16'h33FF;
                    4'd7:  O_row_bits = 16'h7030;
                    4'd8:  O_row_bits = 16'h7830;
                    4'd9:  O_row_bits = 16'hFDB6;
                    4'd10: O_row_bits = 16'hF5B6;
                    4'd11: O_row_bits = 16'hF3B3;
                    4'd12: O_row_bits = 16'h3333;
                    4'd13: O_row_bits = 16'h3733;
                    4'd14: O_row_bits = 16'h3231;
                    4'd15: O_row_bits = 16'h30F0;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            6'd41: begin  //运
                case(I_row)
                    4'd0:  O_row_bits = 16'h2000;
                    4'd1:  O_row_bits = 16'h73FF;
                    4'd2:  O_row_bits = 16'h33FF;
                    4'd3:  O_row_bits = 16'h3800;
                    4'd4:  O_row_bits = 16'h1000;
                    4'd5:  O_row_bits = 16'h07FF;
                    4'd6:  O_row_bits = 16'hF7FF;
                    4'd7:  O_row_bits = 16'hF0CC;
                    4'd8:  O_row_bits = 16'h31CC;
                    4'd9:  O_row_bits = 16'h3386;
                    4'd10: O_row_bits = 16'h37FF;
                    4'd11: O_row_bits = 16'h33F3;
                    4'd12: O_row_bits = 16'h7802;
                    4'd13: O_row_bits = 16'h7C00;
                    4'd14: O_row_bits = 16'hEFFF;
                    4'd15: O_row_bits = 16'hC7FF;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            6'd42: begin  //动
                case(I_row)
                    4'd0:  O_row_bits = 16'h0030;
                    4'd1:  O_row_bits = 16'h7E70;
                    4'd2:  O_row_bits = 16'h7E70;
                    4'd3:  O_row_bits = 16'h00FF;
                    4'd4:  O_row_bits = 16'h00FF;
                    4'd5:  O_row_bits = 16'hFF73;
                    4'd6:  O_row_bits = 16'hFF73;
                    4'd7:  O_row_bits = 16'h3873;
                    4'd8:  O_row_bits = 16'h3073;
                    4'd9:  O_row_bits = 16'h3663;
                    4'd10: O_row_bits = 16'h7663;
                    4'd11: O_row_bits = 16'h7763;
                    4'd12: O_row_bits = 16'h6363;
                    4'd13: O_row_bits = 16'hFFE3;
                    4'd14: O_row_bits = 16'h7FC3;
                    4'd15: O_row_bits = 16'h01DF;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            6'd43: begin  //已
                case(I_row)
                    4'd0:  O_row_bits = 16'h0000;
                    4'd1:  O_row_bits = 16'h7FFE;
                    4'd2:  O_row_bits = 16'h7FFE;
                    4'd3:  O_row_bits = 16'h000E;
                    4'd4:  O_row_bits = 16'h000E;
                    4'd5:  O_row_bits = 16'h300E;
                    4'd6:  O_row_bits = 16'h300E;
                    4'd7:  O_row_bits = 16'h3FFE;
                    4'd8:  O_row_bits = 16'h3FFE;
                    4'd9:  O_row_bits = 16'h3000;
                    4'd10: O_row_bits = 16'h3002;
                    4'd11: O_row_bits = 16'h3003;
                    4'd12: O_row_bits = 16'h3003;
                    4'd13: O_row_bits = 16'h3803;
                    4'd14: O_row_bits = 16'h3FFF;
                    4'd15: O_row_bits = 16'h1FFE;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            6'd44: begin  //未
                case(I_row)
                    4'd0:  O_row_bits = 16'h01C0;
                    4'd1:  O_row_bits = 16'h01C0;
                    4'd2:  O_row_bits = 16'h7FFF;
                    4'd3:  O_row_bits = 16'h7FFF;
                    4'd4:  O_row_bits = 16'h01C0;
                    4'd5:  O_row_bits = 16'h01C0;
                    4'd6:  O_row_bits = 16'h01C0;
                    4'd7:  O_row_bits = 16'h7FFF;
                    4'd8:  O_row_bits = 16'h7FFF;
                    4'd9:  O_row_bits = 16'h03E0;
                    4'd10: O_row_bits = 16'h07F0;
                    4'd11: O_row_bits = 16'h0FF8;
                    4'd12: O_row_bits = 16'h1DDC;
                    4'd13: O_row_bits = 16'h39CE;
                    4'd14: O_row_bits = 16'h71C7;
                    4'd15: O_row_bits = 16'h61C3;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            6'd45: begin  //采
                case(I_row)
                    4'd0:  O_row_bits = 16'h001E;
                    4'd1:  O_row_bits = 16'h7FFF;
                    4'd2:  O_row_bits = 16'h7FE0;
                    4'd3:  O_row_bits = 16'h3384;
                    4'd4:  O_row_bits = 16'h31CE;
                    4'd5:  O_row_bits = 16'h389C;
                    4'd6:  O_row_bits = 16'h11C8;
                    4'd7:  O_row_bits = 16'h01C0;
                    4'd8:  O_row_bits = 16'h7FFF;
                    4'd9:  O_row_bits = 16'h7FFF;
                    4'd10: O_row_bits = 16'h07E0;
                    4'd11: O_row_bits = 16'h0FF8;
                    4'd12: O_row_bits = 16'h1DDC;
                    4'd13: O_row_bits = 16'h39CE;
                    4'd14: O_row_bits = 16'hF1C7;
                    4'd15: O_row_bits = 16'h41C1;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            6'd46: begin  //叠
                case(I_row)
                    4'd0:  O_row_bits = 16'h0000;
                    4'd1:  O_row_bits = 16'h3FFC;
                    4'd2:  O_row_bits = 16'h1C1C;
                    4'd3:  O_row_bits = 16'h03F0;
                    4'd4:  O_row_bits = 16'h3E1E;
                    4'd5:  O_row_bits = 16'h7F7F;
                    4'd6:  O_row_bits = 16'h7666;
                    4'd7:  O_row_bits = 16'h1E3E;
                    4'd8:  O_row_bits = 16'h73E3;
                    4'd9:  O_row_bits = 16'h7FFF;
                    4'd10: O_row_bits = 16'h780F;
                    4'd11: O_row_bits = 16'h1FFC;
                    4'd12: O_row_bits = 16'h180C;
                    4'd13: O_row_bits = 16'h1FFC;
                    4'd14: O_row_bits = 16'h180C;
                    4'd15: O_row_bits = 16'hFFFF;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            6'd47: begin  //加
                case(I_row)
                    4'd0:  O_row_bits = 16'h3800;
                    4'd1:  O_row_bits = 16'h387F;
                    4'd2:  O_row_bits = 16'h387F;
                    4'd3:  O_row_bits = 16'hFF73;
                    4'd4:  O_row_bits = 16'hFF73;
                    4'd5:  O_row_bits = 16'h3B73;
                    4'd6:  O_row_bits = 16'h3373;
                    4'd7:  O_row_bits = 16'h3373;
                    4'd8:  O_row_bits = 16'h3373;
                    4'd9:  O_row_bits = 16'h3373;
                    4'd10: O_row_bits = 16'h3373;
                    4'd11: O_row_bits = 16'h3373;
                    4'd12: O_row_bits = 16'h7373;
                    4'd13: O_row_bits = 16'h637F;
                    4'd14: O_row_bits = 16'h637F;
                    4'd15: O_row_bits = 16'hCF73;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            6'd48: begin  //逻
                case(I_row)
                    4'd0:  O_row_bits = 16'h2000;
                    4'd1:  O_row_bits = 16'h67FF;
                    4'd2:  O_row_bits = 16'h77FF;
                    4'd3:  O_row_bits = 16'h3EDB;
                    4'd4:  O_row_bits = 16'h16DB;
                    4'd5:  O_row_bits = 16'h07FF;
                    4'd6:  O_row_bits = 16'h07FF;
                    4'd7:  O_row_bits = 16'hF1C0;
                    4'd8:  O_row_bits = 16'hF1FE;
                    4'd9:  O_row_bits = 16'h33FE;
                    4'd10:  O_row_bits = 16'h378E;
                    4'd11:  O_row_bits = 16'h35FC;
                    4'd12:  O_row_bits = 16'h3078;
                    4'd13:  O_row_bits = 16'h79E0;
                    4'd14:  O_row_bits = 16'h7FFF;
                    4'd15:  O_row_bits = 16'h4FFF;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            6'd49: begin  //启
                case(I_row)
                    4'd0:  O_row_bits = 16'h01C0;
                    4'd1:  O_row_bits = 16'h01C0;
                    4'd2:  O_row_bits = 16'h3FFF;
                    4'd3:  O_row_bits = 16'h3FFF;
                    4'd4:  O_row_bits = 16'h3007;
                    4'd5:  O_row_bits = 16'h3007;
                    4'd6:  O_row_bits = 16'h3FFF;
                    4'd7:  O_row_bits = 16'h3FFF;
                    4'd8:  O_row_bits = 16'h3000;
                    4'd9:  O_row_bits = 16'h3000;
                    4'd10:  O_row_bits = 16'h37FF;
                    4'd11:  O_row_bits = 16'h37FF;
                    4'd12:  O_row_bits = 16'h7607;
                    4'd13:  O_row_bits = 16'h6607;
                    4'd14:  O_row_bits = 16'h67FF;
                    4'd15:  O_row_bits = 16'hE7FF;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            6'd50: begin  //工
                case(I_row)
                    4'd0:  O_row_bits = 16'h0000;
                    4'd1:  O_row_bits = 16'h7FFF;
                    4'd2:  O_row_bits = 16'h7FFF;
                    4'd3:  O_row_bits = 16'h01C0;
                    4'd4:  O_row_bits = 16'h01C0;
                    4'd5:  O_row_bits = 16'h01C0;
                    4'd6:  O_row_bits = 16'h01C0;
                    4'd7:  O_row_bits = 16'h01C0;
                    4'd8:  O_row_bits = 16'h01C0;
                    4'd9:  O_row_bits = 16'h01C0;
                    4'd10:  O_row_bits = 16'h01C0;
                    4'd11:  O_row_bits = 16'h01C0;
                    4'd12:  O_row_bits = 16'h01C0;
                    4'd13:  O_row_bits = 16'h01C0;
                    4'd14:  O_row_bits = 16'hFFFF;
                    4'd15:  O_row_bits = 16'hFFFF;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            6'd51: begin  //坊
                case(I_row)
                    4'd0:  O_row_bits = 16'h3030;
                    4'd1:  O_row_bits = 16'h3030;
                    4'd2:  O_row_bits = 16'h3030;
                    4'd3:  O_row_bits = 16'h33FF;
                    4'd4:  O_row_bits = 16'hFFFF;
                    4'd5:  O_row_bits = 16'hFCC0;
                    4'd6:  O_row_bits = 16'h30FF;
                    4'd7:  O_row_bits = 16'h30FF;
                    4'd8:  O_row_bits = 16'h30C7;
                    4'd9:  O_row_bits = 16'h31C7;
                    4'd10:  O_row_bits = 16'h35C7;
                    4'd11:  O_row_bits = 16'h3DC7;
                    4'd12:  O_row_bits = 16'hFF87;
                    4'd13:  O_row_bits = 16'h6387;
                    4'd14:  O_row_bits = 16'h073E;
                    4'd15:  O_row_bits = 16'h011E;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            6'd52: begin  //名
                case(I_row)
                    4'd0:  O_row_bits = 16'h0700;
                    4'd1:  O_row_bits = 16'h0600;
                    4'd2:  O_row_bits = 16'h0FFE;
                    4'd3:  O_row_bits = 16'h1FFE;
                    4'd4:  O_row_bits = 16'h380E;
                    4'd5:  O_row_bits = 16'h761C;
                    4'd6:  O_row_bits = 16'h6F70;
                    4'd7:  O_row_bits = 16'h03E0;
                    4'd8:  O_row_bits = 16'h0780;
                    4'd9:  O_row_bits = 16'h1FFE;
                    4'd10:  O_row_bits = 16'hFFFE;
                    4'd11:  O_row_bits = 16'h5806;
                    4'd12:  O_row_bits = 16'h1806;
                    4'd13:  O_row_bits = 16'h1806;
                    4'd14:  O_row_bits = 16'h1FFE;
                    4'd15:  O_row_bits = 16'h1FFE;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            6'd53: begin  //背
                case(I_row)
                    4'd0:  O_row_bits = 16'h0663;
                    4'd1:  O_row_bits = 16'h7E7F;
                    4'd2:  O_row_bits = 16'h7E7E;
                    4'd3:  O_row_bits = 16'h0661;
                    4'd4:  O_row_bits = 16'hFE7F;
                    4'd5:  O_row_bits = 16'hFE3F;
                    4'd6:  O_row_bits = 16'h0000;
                    4'd7:  O_row_bits = 16'h3FFE;
                    4'd8:  O_row_bits = 16'h3FFE;
                    4'd9:  O_row_bits = 16'h3006;
                    4'd10:  O_row_bits = 16'h3FFE;
                    4'd11:  O_row_bits = 16'h3006;
                    4'd12:  O_row_bits = 16'h3FFE;
                    4'd13:  O_row_bits = 16'h3006;
                    4'd14:  O_row_bits = 16'h300E;
                    4'd15:  O_row_bits = 16'h307E;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            6'd54: begin  //景
                case(I_row)
                    4'd0:  O_row_bits = 16'h0000;
                    4'd1:  O_row_bits = 16'h3FFE;
                    4'd2:  O_row_bits = 16'h3006;
                    4'd3:  O_row_bits = 16'h3FFE;
                    4'd4:  O_row_bits = 16'h3006;
                    4'd5:  O_row_bits = 16'h3FFE;
                    4'd6:  O_row_bits = 16'h01C0;
                    4'd7:  O_row_bits = 16'hFFFF;
                    4'd8:  O_row_bits = 16'h0000;
                    4'd9:  O_row_bits = 16'h3FFE;
                    4'd10:  O_row_bits = 16'h380E;
                    4'd11:  O_row_bits = 16'h380E;
                    4'd12:  O_row_bits = 16'h3FFE;
                    4'd13:  O_row_bits = 16'h0CD8;
                    4'd14:  O_row_bits = 16'h38CE;
                    4'd15:  O_row_bits = 16'hF3C3;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            6'd55: begin  //检
                case(I_row)
                    4'd0:  O_row_bits = 16'h3030;
                    4'd1:  O_row_bits = 16'h3078;
                    4'd2:  O_row_bits = 16'h307C;
                    4'd3:  O_row_bits = 16'hFCCE;
                    4'd4:  O_row_bits = 16'hFD87;
                    4'd5:  O_row_bits = 16'h33FF;
                    4'd6:  O_row_bits = 16'h3AFF;
                    4'd7:  O_row_bits = 16'h7C00;
                    4'd8:  O_row_bits = 16'h7423;
                    4'd9:  O_row_bits = 16'hF737;
                    4'd10:  O_row_bits = 16'hF136;
                    4'd11:  O_row_bits = 16'h31B6;
                    4'd12:  O_row_bits = 16'h31B6;
                    4'd13:  O_row_bits = 16'h318C;
                    4'd14:  O_row_bits = 16'h33FF;
                    4'd15:  O_row_bits = 16'h33FF;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            6'd56: begin  //测
                case(I_row)
                    4'd0:  O_row_bits = 16'h6003;
                    4'd1:  O_row_bits = 16'h77E3;
                    4'd2:  O_row_bits = 16'h3FEB;
                    4'd3:  O_row_bits = 16'h146B;
                    4'd4:  O_row_bits = 16'h056B;
                    4'd5:  O_row_bits = 16'h456B;
                    4'd6:  O_row_bits = 16'h656B;
                    4'd7:  O_row_bits = 16'h356B;
                    4'd8:  O_row_bits = 16'h256B;
                    4'd9:  O_row_bits = 16'h056B;
                    4'd10:  O_row_bits = 16'h256B;
                    4'd11:  O_row_bits = 16'h356B;
                    4'd12:  O_row_bits = 16'h338B;
                    4'd13:  O_row_bits = 16'h77C3;
                    4'd14:  O_row_bits = 16'h66E3;
                    4'd15:  O_row_bits = 16'h6E6F;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            6'd57: begin  //外
                case(I_row)
                    4'd0:  O_row_bits = 16'h1C30;
                    4'd1:  O_row_bits = 16'h1830;
                    4'd2:  O_row_bits = 16'h1830;
                    4'd3:  O_row_bits = 16'h3FB0;
                    4'd4:  O_row_bits = 16'h3FB0;
                    4'd5:  O_row_bits = 16'h31BC;
                    4'd6:  O_row_bits = 16'h71BC;
                    4'd7:  O_row_bits = 16'hE3B6;
                    4'd8:  O_row_bits = 16'hDB37;
                    4'd9:  O_row_bits = 16'h5F33;
                    4'd10:  O_row_bits = 16'h0F31;
                    4'd11:  O_row_bits = 16'h0E30;
                    4'd12:  O_row_bits = 16'h1C30;
                    4'd13:  O_row_bits = 16'h1C30;
                    4'd14:  O_row_bits = 16'h7830;
                    4'd15:  O_row_bits = 16'h7030;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            6'd58: begin  //接
                case(I_row)
                    4'd0:  O_row_bits = 16'h3070;
                    4'd1:  O_row_bits = 16'h3030;
                    4'd2:  O_row_bits = 16'h33FF;
                    4'd3:  O_row_bits = 16'h33FF;
                    4'd4:  O_row_bits = 16'h7DC6;
                    4'd5:  O_row_bits = 16'h7CCE;
                    4'd6:  O_row_bits = 16'h33FF;
                    4'd7:  O_row_bits = 16'h33FF;
                    4'd8:  O_row_bits = 16'h3CE0;
                    4'd9:  O_row_bits = 16'hFFFF;
                    4'd10:  O_row_bits = 16'hF3FF;
                    4'd11:  O_row_bits = 16'h318E;
                    4'd12:  O_row_bits = 16'h33CC;
                    4'd13:  O_row_bits = 16'h30FC;
                    4'd14:  O_row_bits = 16'h30FE;
                    4'd15:  O_row_bits = 16'hF7EF;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            6'd59: begin  //显
                case(I_row)
                    4'd0:  O_row_bits = 16'h0000;
                    4'd1:  O_row_bits = 16'h3FFE;
                    4'd2:  O_row_bits = 16'h3FFE;
                    4'd3:  O_row_bits = 16'h3006;
                    4'd4:  O_row_bits = 16'h3FFE;
                    4'd5:  O_row_bits = 16'h3006;
                    4'd6:  O_row_bits = 16'h3FFE;
                    4'd7:  O_row_bits = 16'h3FFE;
                    4'd8:  O_row_bits = 16'h0000;
                    4'd9:  O_row_bits = 16'h2772;
                    4'd10:  O_row_bits = 16'h7777;
                    4'd11:  O_row_bits = 16'h3F7E;
                    4'd12:  O_row_bits = 16'h1774;
                    4'd13:  O_row_bits = 16'h0770;
                    4'd14:  O_row_bits = 16'hFFFF;
                    4'd15:  O_row_bits = 16'hFFFF;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            6'd60: begin  //示
                case(I_row)
                    4'd0:  O_row_bits = 16'h0000;
                    4'd1:  O_row_bits = 16'h3FFE;
                    4'd2:  O_row_bits = 16'h3FFE;
                    4'd3:  O_row_bits = 16'h0000;
                    4'd4:  O_row_bits = 16'h0000;
                    4'd5:  O_row_bits = 16'h0000;
                    4'd6:  O_row_bits = 16'h7FFF;
                    4'd7:  O_row_bits = 16'h7FFF;
                    4'd8:  O_row_bits = 16'h00C0;
                    4'd9:  O_row_bits = 16'h08C8;
                    4'd10:  O_row_bits = 16'h1CDC;
                    4'd11:  O_row_bits = 16'h38CE;
                    4'd12:  O_row_bits = 16'h38C6;
                    4'd13:  O_row_bits = 16'h70C7;
                    4'd14:  O_row_bits = 16'hE1C3;
                    4'd15:  O_row_bits = 16'h27C2;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            6'd61: begin  //框
                case(I_row)
                    4'd0:  O_row_bits = 16'h3000;
                    4'd1:  O_row_bits = 16'h33FF;
                    4'd2:  O_row_bits = 16'h33FF;
                    4'd3:  O_row_bits = 16'hFF00;
                    4'd4:  O_row_bits = 16'hFF7F;
                    4'd5:  O_row_bits = 16'h337F;
                    4'd6:  O_row_bits = 16'h3318;
                    4'd7:  O_row_bits = 16'h7F7F;
                    4'd8:  O_row_bits = 16'h7B7F;
                    4'd9:  O_row_bits = 16'hF318;
                    4'd10:  O_row_bits = 16'hF318;
                    4'd11:  O_row_bits = 16'hB37F;
                    4'd12:  O_row_bits = 16'h337F;
                    4'd13:  O_row_bits = 16'h3300;
                    4'd14:  O_row_bits = 16'h33FF;
                    4'd15:  O_row_bits = 16'h33FF;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            6'd62: begin  //区
                case(I_row)
                    4'd0:  O_row_bits = 16'h0000;
                    4'd1:  O_row_bits = 16'h7FFF;
                    4'd2:  O_row_bits = 16'h7FFF;
                    4'd3:  O_row_bits = 16'h7000;
                    4'd4:  O_row_bits = 16'h7608;
                    4'd5:  O_row_bits = 16'h7F1C;
                    4'd6:  O_row_bits = 16'h77B8;
                    4'd7:  O_row_bits = 16'h71F0;
                    4'd8:  O_row_bits = 16'h70F0;
                    4'd9:  O_row_bits = 16'h71F8;
                    4'd10:  O_row_bits = 16'h77BC;
                    4'd11:  O_row_bits = 16'h7F1E;
                    4'd12:  O_row_bits = 16'h740C;
                    4'd13:  O_row_bits = 16'h7000;
                    4'd14:  O_row_bits = 16'h7FFF;
                    4'd15:  O_row_bits = 16'h7FFF;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            6'd63: begin  //域
                case(I_row)
                    4'd0:  O_row_bits = 16'h301A;
                    4'd1:  O_row_bits = 16'h301B;
                    4'd2:  O_row_bits = 16'h301B;
                    4'd3:  O_row_bits = 16'h37FF;
                    4'd4:  O_row_bits = 16'h37FF;
                    4'd5:  O_row_bits = 16'hF818;
                    4'd6:  O_row_bits = 16'hF81B;
                    4'd7:  O_row_bits = 16'h37DB;
                    4'd8:  O_row_bits = 16'h36DB;
                    4'd9:  O_row_bits = 16'h36DE;
                    4'd10:  O_row_bits = 16'h36DE;
                    4'd11:  O_row_bits = 16'h37DC;
                    4'd12:  O_row_bits = 16'h301D;
                    4'd13:  O_row_bits = 16'h38DD;
                    4'd14:  O_row_bits = 16'hFFFD;
                    4'd15:  O_row_bits = 16'hF7FF;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            7'd64: begin  //填
                case(I_row)
                    4'd0:  O_row_bits = 16'h3030;
                    4'd1:  O_row_bits = 16'h33FF;
                    4'd2:  O_row_bits = 16'h3030;
                    4'd3:  O_row_bits = 16'hFFFF;
                    4'd4:  O_row_bits = 16'hFF03;
                    4'd5:  O_row_bits = 16'h33FF;
                    4'd6:  O_row_bits = 16'h3303;
                    4'd7:  O_row_bits = 16'h33FF;
                    4'd8:  O_row_bits = 16'h3303;
                    4'd9:  O_row_bits = 16'h33FF;
                    4'd10:  O_row_bits = 16'h3F03;
                    4'd11:  O_row_bits = 16'hFFFF;
                    4'd12:  O_row_bits = 16'h40CC;
                    4'd13:  O_row_bits = 16'h03CF;
                    4'd14:  O_row_bits = 16'h0787;
                    4'd15:  O_row_bits = 16'h0601;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            7'd65: begin  //充
                case(I_row)
                    4'd0:  O_row_bits = 16'h0180;
                    4'd1:  O_row_bits = 16'h01C0;
                    4'd2:  O_row_bits = 16'h7FFF;
                    4'd3:  O_row_bits = 16'h7FFF;
                    4'd4:  O_row_bits = 16'h0710;
                    4'd5:  O_row_bits = 16'h0E38;
                    4'd6:  O_row_bits = 16'h1C1C;
                    4'd7:  O_row_bits = 16'h3FFE;
                    4'd8:  O_row_bits = 16'h3FFF;
                    4'd9:  O_row_bits = 16'h0672;
                    4'd10:  O_row_bits = 16'h0670;
                    4'd11:  O_row_bits = 16'h0E70;
                    4'd12:  O_row_bits = 16'h0E73;
                    4'd13:  O_row_bits = 16'h1C73;
                    4'd14:  O_row_bits = 16'h3C73;
                    4'd15:  O_row_bits = 16'h787F;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            7'd66: begin  //当
                case(I_row)
                    4'd0:  O_row_bits = 16'h01C2;
                    4'd1:  O_row_bits = 16'h30C7;
                    4'd2:  O_row_bits = 16'h38C7;
                    4'd3:  O_row_bits = 16'h1CCE;
                    4'd4:  O_row_bits = 16'h1CDC;
                    4'd5:  O_row_bits = 16'h00C8;
                    4'd6:  O_row_bits = 16'h7FFF;
                    4'd7:  O_row_bits = 16'h7FFF;
                    4'd8:  O_row_bits = 16'h001E;
                    4'd9:  O_row_bits = 16'h001E;
                    4'd10: O_row_bits = 16'h7FFF;
                    4'd11: O_row_bits = 16'h7FFF;
                    4'd12: O_row_bits = 16'h001E;
                    4'd13: O_row_bits = 16'h001E;
                    4'd14: O_row_bits = 16'h7FFF;
                    4'd15: O_row_bits = 16'h7FFF;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            7'd67: begin  //前
                case(I_row)
                    4'd0:  O_row_bits = 16'h0C0C;
                    4'd1:  O_row_bits = 16'h060C;
                    4'd2:  O_row_bits = 16'h7FFF;
                    4'd3:  O_row_bits = 16'h7FFF;
                    4'd4:  O_row_bits = 16'h0000;
                    4'd5:  O_row_bits = 16'h7F07;
                    4'd6:  O_row_bits = 16'h7F8F;
                    4'd7:  O_row_bits = 16'h18CF;
                    4'd8:  O_row_bits = 16'h7FCF;
                    4'd9:  O_row_bits = 16'h7FCF;
                    4'd10: O_row_bits = 16'h18CF;
                    4'd11: O_row_bits = 16'h7FCF;
                    4'd12: O_row_bits = 16'h7FCF;
                    4'd13: O_row_bits = 16'h18CF;
                    4'd14: O_row_bits = 16'h187F;
                    4'd15: O_row_bits = 16'h1CFC;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            7'd68: begin  //模
                case(I_row)
                    4'd0:  O_row_bits = 16'h0C18;
                    4'd1:  O_row_bits = 16'h0FFF;
                    4'd2:  O_row_bits = 16'h0FFF;
                    4'd3:  O_row_bits = 16'hFC18;
                    4'd4:  O_row_bits = 16'hFF3F;
                    4'd5:  O_row_bits = 16'h0C07;
                    4'd6:  O_row_bits = 16'h0FFF;
                    4'd7:  O_row_bits = 16'h3FFF;
                    4'd8:  O_row_bits = 16'h3FFF;
                    4'd9:  O_row_bits = 16'hF3FF;
                    4'd10: O_row_bits = 16'hF018;
                    4'd11: O_row_bits = 16'h4FFF;
                    4'd12: O_row_bits = 16'h0FFF;
                    4'd13: O_row_bits = 16'h0C18;
                    4'd14: O_row_bits = 16'h0C3C;
                    4'd15: O_row_bits = 16'h0F87;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            7'd69: begin  //式
                case(I_row)
                    4'd0:  O_row_bits = 16'h0338;
                    4'd1:  O_row_bits = 16'h033C;
                    4'd2:  O_row_bits = 16'h0318;
                    4'd3:  O_row_bits = 16'h7FFF;
                    4'd4:  O_row_bits = 16'h7FFF;
                    4'd5:  O_row_bits = 16'h00E0;
                    4'd6:  O_row_bits = 16'h00E0;
                    4'd7:  O_row_bits = 16'h3FE0;
                    4'd8:  O_row_bits = 16'h3FF0;
                    4'd9:  O_row_bits = 16'h0618;
                    4'd10: O_row_bits = 16'h0618;
                    4'd11: O_row_bits = 16'h061C;
                    4'd12: O_row_bits = 16'h06C6;
                    4'd13: O_row_bits = 16'h7FC6;
                    4'd14: O_row_bits = 16'hFE7E;
                    4'd15: O_row_bits = 16'hFC3C;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            default: O_row_bits = 16'h0000;
        endcase
    end

endmodule
