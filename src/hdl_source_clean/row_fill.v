//========================================================
// 模块：row_fill —— 前景标记行填充单元（区域填充功能，2026-11-01）
// 功能：对 1bit 前景标记流（4 像素/拍）做水平扫描线填充：每行统计多个前景段
//       （按 0 游程长度分段），段内 [L,R] 全 1、段外原值——手掌心空洞变实心，
//       而「离得太远的物体/噪声」与手之间的宽间隙（≥ GAP_T）不会误连成一片。
// 多段语义（2026-11-02 改进，替代单段 [L,R] 全行填充；参数按任务书「零、用户新增需求」）：
//   ① 段分割 = 0 游程 > GAP_T 组（默认 10 组 = 40px）→ 断段；gap ≤ 40px → 段内空洞照填
//   ② 段宽过滤 = 段内 1 像素数 < MIN_W（默认 4px）→ 整段不填（孤立噪点段兜底；morph 已滤单点）
//   ③ 每行最多 K=4 段（段表寄存器，行末锁存），段内位粒度掩码与单段版相同
// ⚠️ 局限（行级判定无垂直信息）：物体间隙 ≤ GAP_T 仍会误连（手洞 vs 物体间隙本质都是
//   0 游程，只按宽度区分）；参数可现场调。彻底解法 = 跨行连通域标签，代价大暂不做。
// 结构：320 拍 × 8bit 行缓冲（DRAM 环形：{边缘直通, 数据} 合并，2026-11-01 第二版资源修复）：
//       第一遍（拍 0~319）数据进缓冲 + 段统计状态机（开段/关段/0 游程计数）；
//       第二遍（拍 320~639）读出 320 拍前的数据，用行末锁存的段表生成填充掩码。
//       输出组号与输入组号同余（缓冲深 320 拍回绕），掩码直接与当前组号比较，无需相位偏移。
// ⚠️ DRAM 环形与移位链等价拍账：读地址 = wp+1（最旧位置，最后写入拍 = t-319），
//    写数据打 1 拍补偿（row_in_d1）→ 读值 = 恰 320 拍前。读写地址恒错开无冲突。
//    帧清 = 清指针（数据不清，旧数据靠 valid 门控不输出）。
// ⚠️ valid 链改 18bit 有效拍计数（省 320 FF）：O_valid = 计数 >= 320 && I_valid，
//    与 320 深 valid 链严格等价（帧清后 320 拍内计数 < 320 → 无输出）。
// 延迟：321 有效拍（缓冲 320 深 + 输出寄存 1 拍），valid 门控推进（空洞拍不 shift）。
//       输出寄存与 morph 输出寄存同款原因：短路径防 TD 插拍，data/valid 三信号同拍。
// 直通通道：O_ori（开运算标记延迟 321 拍，非填充模式涂白用）、O_edge（边缘标记延迟 321 拍）。
// DRAIN 直通：I_drain 经 320 深延迟链 + 输出寄存 1 拍（总 321，与数据同拍对齐）——DRAIN 期
//       morph 排空 644 拍跨行边界，段统计错乱，直通输出原值保证帧尾行为与改造前一致（零回归）。
// 帧尾语义：帧开始脉冲清指针/统计丢弃滞留 321 拍（旧帧尾约 1 行数据），与 morph 清链同拍
//       （S_fs_d512）；新帧头数据到达前 valid 计数已过 320（清后 ~600 拍空窗），帧头不丢拍。
//========================================================
module row_fill #(
    parameter [8:0] GAP_T = 9'd10,   //段间隙阈值（组数）：0 游程 > GAP_T → 断段（10 组 = 40px，任务书初定值）
    parameter [8:0] MIN_W = 9'd4     //最小段前景像素数：段内 1 像素总数 < MIN_W → 整段不填（4px，任务书噪点兜底）
)(
    input  wire        I_clk,           //DDR 域时钟
    input  wire        I_rst_n,         //复位，低有效
    input  wire        I_frame_start,   //帧开始脉冲：清全部延迟链 + 清统计（与 morph 同拍 S_fs_d512）
    input  wire        I_valid,         //输入有效（morph 输出 valid，每行 320 有效拍 + 行尾空洞）
    input  wire [3:0]  I_data,          //输入前景标记（morph 开运算输出，bit0=行内最左像素）
    input  wire [3:0]  I_edge,          //输入边缘标记（morph 边缘输出，与 I_data 同拍）
    input  wire        I_drain,         //DRAIN 排空期（与 I_valid 同拍）：填充直通输出原值
    output wire        O_valid,         //输出有效（延迟 321 有效拍，与 O_ori/O_fill/O_edge 同拍）
    output wire [3:0]  O_ori,           //开运算标记直通（延迟 321 有效拍，非填充模式写 ERAM 用）
    output wire [3:0]  O_fill,          //填充后标记（每段 [L,R] 全 1，段外原值）
    output wire [3:0]  O_edge           //边缘标记直通（延迟 321 有效拍，与 O_fill 同拍供 mux）
);

    // 每行最多段数
    localparam K = 4;

    //------------ 数据缓冲：320 拍 × 8bit DRAM 环形（{edge, data} 合并）------------
    // 写 mem[wp] = 上一拍 {I_edge, I_data}（写补偿 1 拍），读 rp = wp+1 = 320 拍前。
    reg [7:0] row_in_d1;   //写补偿：{I_edge, I_data} 打 1 拍
    reg [7:0] mem_row [0:511] /* synthesis ram_style = dram */;
    reg [8:0] wp_row;      //写指针（模 320 回绕，有效拍推进）
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            wp_row <= 9'd0;
        end else if(I_frame_start) begin
            wp_row <= 9'd0;
        end else if(I_valid) begin
            mem_row[wp_row] <= row_in_d1;
            wp_row <= (wp_row == 9'd319) ? 9'd0 : wp_row + 1'b1;
        end
    end
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            row_in_d1 <= 8'd0;
        end else if(I_frame_start) begin
            row_in_d1 <= 8'd0;
        end else if(I_valid) begin
            row_in_d1 <= {I_edge, I_data};
        end
    end
    wire [8:0] rp_row = (wp_row == 9'd319) ? 9'd0 : wp_row + 1'b1;   //读指针 = 最旧位置
    wire [7:0] rv_row = mem_row[rp_row];
    wire [3:0] S_tail      = rv_row[3:0];    //当拍输出原值（320 拍前输入组）
    wire [3:0] S_edge_tail = rv_row[7:4];    //当拍输出边缘（320 拍前输入组）

    //------------ DRAIN 直通链 320 深（1bit，保留向量 FF）------------
    // 尾 [319] = 320 拍前 I_drain，+ 输出寄存 1 拍 = 321 与数据同拍。
    reg [319:0] S_drain_sr;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_drain_sr <= 320'd0;
        end else if(I_frame_start) begin
            S_drain_sr <= 320'd0;
        end else if(I_valid) begin
            S_drain_sr <= {S_drain_sr[318:0], I_drain};
        end
    end

    //------------ valid 计数（18bit，替代 320 深 valid 链，2026-11-01 资源修复）------------
    // 帧清清零、I_valid 拍 +1；O_valid = 计数 >= 320 && I_valid（帧清后 320 拍内无输出）。
    reg [17:0] S_vcnt;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            S_vcnt <= 18'd0;
        else if(I_frame_start)
            S_vcnt <= 18'd0;
        else if(I_valid)
            S_vcnt <= S_vcnt + 1'b1;
    end

    //------------ 组内最左 1 位号（优先编码，bit0=行内最左像素）------------
    function [1:0] f_left_one;
        input [3:0] d;
        begin
            if(d[0])      f_left_one = 2'd0;
            else if(d[1]) f_left_one = 2'd1;
            else if(d[2]) f_left_one = 2'd2;
            else          f_left_one = 2'd3;
        end
    endfunction
    //------------ 组内最右 1 位号（优先编码）------------
    function [1:0] f_right_one;
        input [3:0] d;
        begin
            if(d[3])      f_right_one = 2'd3;
            else if(d[2]) f_right_one = 2'd2;
            else if(d[1]) f_right_one = 2'd1;
            else          f_right_one = 2'd0;
        end
    endfunction
    //------------ 组内 1 的个数（popcount，噪点段兜底用）------------
    function [2:0] f_popcnt;
        input [3:0] d;
        begin
            f_popcnt = d[0] + d[1] + d[2] + d[3];
        end
    endfunction

    //------------ 段统计状态机（第一遍扫描，2026-11-02 多段版）------------
    // 行内组号 S_grp 0~319 循环（有效拍推进）。段语义（任务书「零、用户新增需求」）：
    //   有 1 的拍：开段（若未开）记 L、更新 R，0 游程清零，段内 1 像素数累加；
    //   0 拍且段开：0 游程计数，> GAP_T（第 GAP_T+1 个 0 拍）→ 关段（段内 1 像素数 >= MIN_W 才压表）；
    //   行末拍：关当前段（含当拍组 319 贡献）+ 段表锁存到 S_out_* + 全部复位。
    reg [8:0] S_grp;        //行内组号 0~319
    reg       S_seg_open;   //当前段已开
    reg [8:0] S_cur_L_grp;  //当前段左边界组号
    reg [1:0] S_cur_L_bit;  //当前段左边界组内最左 1 位号
    reg [8:0] S_cur_R_grp;  //当前段右边界组号
    reg [1:0] S_cur_R_bit;  //当前段右边界组内最右 1 位号
    reg [8:0] S_zero_len;   //当前 0 游程长度（组数）
    reg [8:0] S_cnt1;       //当前段内 1 像素总数（噪点兜底：< MIN_W 整段不填）
    reg [1:0] S_seg_cnt;    //已关段数 0~K（超出丢弃）
    // 段表（工作寄存器，行末锁存到 S_out_*）
    reg [8:0] S_seg_L [0:K-1];
    reg [8:0] S_seg_R [0:K-1];
    reg [1:0] S_seg_Lb [0:K-1];
    reg [1:0] S_seg_Rb [0:K-1];
    // 行末锁存（输出掩码用：上一行段表）
    reg [8:0] S_out_L [0:K-1];
    reg [8:0] S_out_R [0:K-1];
    reg [1:0] S_out_Lb [0:K-1];
    reg [1:0] S_out_Rb [0:K-1];
    reg [1:0] S_out_cnt;    //上一行有效段数（0 = 无前景行，输出全 0）

    integer si;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_grp       <= 9'd0;
            S_seg_open  <= 1'b0;
            S_cur_L_grp <= 9'd0; S_cur_L_bit <= 2'd0;
            S_cur_R_grp <= 9'd0; S_cur_R_bit <= 2'd0;
            S_zero_len  <= 9'd0;
            S_cnt1      <= 9'd0;
            S_seg_cnt   <= 2'd0;
            for(si = 0; si < K; si = si + 1) begin
                S_seg_L[si] <= 9'd0; S_seg_R[si] <= 9'd0;
                S_seg_Lb[si] <= 2'd0; S_seg_Rb[si] <= 2'd0;
            end
            S_out_cnt <= 2'd0;
            for(si = 0; si < K; si = si + 1) begin
                S_out_L[si] <= 9'd0; S_out_R[si] <= 9'd0;
                S_out_Lb[si] <= 2'd0; S_out_Rb[si] <= 2'd0;
            end
        end else if(I_frame_start) begin
            S_grp       <= 9'd0;
            S_seg_open  <= 1'b0;
            S_cur_L_grp <= 9'd0; S_cur_L_bit <= 2'd0;
            S_cur_R_grp <= 9'd0; S_cur_R_bit <= 2'd0;
            S_zero_len  <= 9'd0;
            S_cnt1      <= 9'd0;
            S_seg_cnt   <= 2'd0;
            for(si = 0; si < K; si = si + 1) begin
                S_seg_L[si] <= 9'd0; S_seg_R[si] <= 9'd0;
                S_seg_Lb[si] <= 2'd0; S_seg_Rb[si] <= 2'd0;
            end
            S_out_cnt <= 2'd0;
            for(si = 0; si < K; si = si + 1) begin
                S_out_L[si] <= 9'd0; S_out_R[si] <= 9'd0;
                S_out_Lb[si] <= 2'd0; S_out_Rb[si] <= 2'd0;
            end
        end else if(I_valid) begin
            if(S_grp == 9'd319) begin
                // 行末拍：关当前段（1 像素数含当拍组 319 贡献，>= MIN_W 才压表）+ 锁存 + 复位
                if(S_seg_open) begin
                    if((S_cnt1 + f_popcnt(I_data)) >= MIN_W) begin
                        if(S_seg_cnt < K) begin
                            S_seg_L[S_seg_cnt]  <= S_cur_L_grp;
                            S_seg_Lb[S_seg_cnt] <= S_cur_L_bit;
                            S_seg_R[S_seg_cnt]  <= (I_data != 4'd0) ? 9'd319 : S_cur_R_grp;
                            S_seg_Rb[S_seg_cnt] <= (I_data != 4'd0) ? f_right_one(I_data) : S_cur_R_bit;
                        end
                        S_seg_cnt <= (S_seg_cnt < K) ? S_seg_cnt + 1'b1 : S_seg_cnt;
                    end
                end else if(I_data != 4'd0) begin
                    // 未开段且行末拍有 1：单组段，1 像素数 = 组内 popcount，同样受 MIN_W 过滤
                    if(f_popcnt(I_data) >= MIN_W) begin
                        if(S_seg_cnt < K) begin
                            S_seg_L[S_seg_cnt]  <= 9'd319;
                            S_seg_Lb[S_seg_cnt] <= f_left_one(I_data);
                            S_seg_R[S_seg_cnt]  <= 9'd319;
                            S_seg_Rb[S_seg_cnt] <= f_right_one(I_data);
                        end
                        S_seg_cnt <= (S_seg_cnt < K) ? S_seg_cnt + 1'b1 : S_seg_cnt;
                    end
                end
                // 行末锁存（下一拍起供第二遍输出用）
                for(si = 0; si < K; si = si + 1) begin
                    S_out_L[si]  <= S_seg_L[si];
                    S_out_R[si]  <= S_seg_R[si];
                    S_out_Lb[si] <= S_seg_Lb[si];
                    S_out_Rb[si] <= S_seg_Rb[si];
                end
                S_out_cnt <= S_seg_cnt;
                // 复位（下一拍 = 新行组 0）
                S_seg_open  <= 1'b0;
                S_cur_L_grp <= 9'd0; S_cur_L_bit <= 2'd0;
                S_cur_R_grp <= 9'd0; S_cur_R_bit <= 2'd0;
                S_zero_len  <= 9'd0;
                S_cnt1      <= 9'd0;
                S_seg_cnt   <= 2'd0;
                for(si = 0; si < K; si = si + 1) begin
                    S_seg_L[si] <= 9'd0; S_seg_R[si] <= 9'd0;
                    S_seg_Lb[si] <= 2'd0; S_seg_Rb[si] <= 2'd0;
                end
                S_grp <= 9'd0;
            end else if(I_data != 4'd0) begin
                // 有 1 的拍：开段（若未开）/更新 R，0 游程清零，1 像素数累加
                if(!S_seg_open) begin
                    S_seg_open  <= 1'b1;
                    S_cur_L_grp <= S_grp;
                    S_cur_L_bit <= f_left_one(I_data);
                end
                S_cur_R_grp <= S_grp;
                S_cur_R_bit <= f_right_one(I_data);
                S_zero_len  <= 9'd0;
                S_cnt1      <= S_cnt1 + f_popcnt(I_data);
                S_grp       <= S_grp + 1'b1;
            end else begin
                // 0 拍：段开时 0 游程计数，> GAP_T（第 GAP_T+1 个 0 拍）→ 关段（1 像素数 >= MIN_W 才压表）
                if(S_seg_open) begin
                    if(S_zero_len >= GAP_T) begin
                        if(S_cnt1 >= MIN_W) begin
                            if(S_seg_cnt < K) begin
                                S_seg_L[S_seg_cnt]  <= S_cur_L_grp;
                                S_seg_Lb[S_seg_cnt] <= S_cur_L_bit;
                                S_seg_R[S_seg_cnt]  <= S_cur_R_grp;
                                S_seg_Rb[S_seg_cnt] <= S_cur_R_bit;
                            end
                            S_seg_cnt <= (S_seg_cnt < K) ? S_seg_cnt + 1'b1 : S_seg_cnt;
                        end
                        S_seg_open <= 1'b0;
                        S_cnt1     <= 9'd0;
                        S_zero_len <= 9'd0;
                    end else begin
                        S_zero_len <= S_zero_len + 1'b1;
                    end
                end
                S_grp <= S_grp + 1'b1;
            end
        end
    end

    //------------ 填充掩码生成（组合：上一行锁存段表 + 当前组号）------------
    // 多段：组号落在任一段 [L,R] 内 → 段内掩码（边界组位粒度，规则与单段版相同）。
    // 段内 1 像素数 < MIN_W 的噪点段已在统计时过滤（不压表）。
    reg [3:0] S_mask;
    integer sm;
    always @(*) begin
        S_mask = 4'd0;
        for(sm = 0; sm < K; sm = sm + 1) begin
            if(sm < S_out_cnt) begin
                if(S_grp < S_out_L[sm]) begin
                    S_mask = S_mask;                    //段左外：不动
                end else if(S_grp == S_out_L[sm]) begin
                    if(S_out_L[sm] == S_out_R[sm]) begin
                        // 单组段：掩码 = [L_bit, R_bit] 区间全 1
                        case({S_out_Lb[sm], S_out_Rb[sm]})
                            4'b0000 : S_mask = S_mask | 4'b0001;
                            4'b0001 : S_mask = S_mask | 4'b0011;
                            4'b0010 : S_mask = S_mask | 4'b0111;
                            4'b0011 : S_mask = S_mask | 4'b1111;
                            4'b0101 : S_mask = S_mask | 4'b0010;
                            4'b0110 : S_mask = S_mask | 4'b0110;
                            4'b0111 : S_mask = S_mask | 4'b1110;
                            4'b1010 : S_mask = S_mask | 4'b0100;
                            4'b1011 : S_mask = S_mask | 4'b1100;
                            4'b1111 : S_mask = S_mask | 4'b1000;
                            default : S_mask = S_mask;
                        endcase
                    end else begin
                        // 左边界组：bit >= L_bit 全 1
                        case(S_out_Lb[sm])
                            2'd0    : S_mask = S_mask | 4'b1111;
                            2'd1    : S_mask = S_mask | 4'b1110;
                            2'd2    : S_mask = S_mask | 4'b1100;
                            default : S_mask = S_mask | 4'b1000;
                        endcase
                    end
                end else if(S_grp < S_out_R[sm]) begin
                    S_mask = 4'b1111;                   //段内：全 1（空洞填充）
                end else if(S_grp == S_out_R[sm]) begin
                    // 右边界组：bit <= R_bit 全 1
                    case(S_out_Rb[sm])
                        2'd0    : S_mask = S_mask | 4'b0001;
                        2'd1    : S_mask = S_mask | 4'b0011;
                        2'd2    : S_mask = S_mask | 4'b0111;
                        default : S_mask = S_mask | 4'b1111;
                    endcase
                end
                // 段右外：不动
            end
        end
    end

    //------------ 输出寄存（1 拍，与 morph 输出寄存同款：短路径防 TD 插拍）------------
    // 填充 = 掩码 | 原值（任务书「否则原值」：掩码外保持原值，掩码内全 1）。
    // DRAIN 直通：S_drain_sr[319] 与寄存后的数据同拍，直通期输出原值不填充。
    reg [3:0] S_ori_q, S_fill_q, S_edge_q;
    reg       S_valid_q;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_ori_q   <= 4'd0;
            S_fill_q  <= 4'd0;
            S_edge_q  <= 4'd0;
            S_valid_q <= 1'b0;
        end else if(I_frame_start) begin
            S_ori_q   <= 4'd0;
            S_fill_q  <= 4'd0;
            S_edge_q  <= 4'd0;
            S_valid_q <= 1'b0;
        end else begin
            S_ori_q   <= S_tail;
            S_fill_q  <= S_drain_sr[319] ? S_tail : (S_mask | S_tail);
            S_edge_q  <= S_edge_tail;
            // 输出 valid = 缓冲尾有数据（已收有效拍 >= 320）&& 当拍新数据（防空洞拍重复输出）
            S_valid_q <= (S_vcnt >= 18'd320) && I_valid;
        end
    end

    assign O_ori   = S_ori_q;
    assign O_fill  = S_fill_q;
    assign O_edge  = S_edge_q;
    assign O_valid = S_valid_q;

endmodule
