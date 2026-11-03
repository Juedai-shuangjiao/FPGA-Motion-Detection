//========================================================
// 模块：morph_filter —— 前景标记形态学滤波（可分离 3×3 开运算）
// 功能：对 1bit 前景标记（4 像素/拍）做「先腐蚀后膨胀」开运算：
//       腐蚀去掉孤立噪点（背景白斑），膨胀恢复目标尺寸。
//       可分离实现：3×1 水平腐蚀 → 1×3 垂直腐蚀 → 3×1 水平膨胀 → 1×3 垂直膨胀。
//       行缓冲 320 有效拍（每行 320 个比较对拍：240 个 128bit 解包出 320 个 96bit；
//       bg 每帧读半帧 360 行 = 115200 对，cmp 仿真实锤——⚠️ 不是 720 行×160，那是
//       把「半帧对数」误除 720 行的错判），垂直级用两级 320 深环形缓冲（DRAM 实现）：
//       mem_v1 读 = 320 拍前（中心行）、mem_v2 读 = 640 拍前（上行）。
//       总延迟 644 有效拍（级 1 水平腐蚀 2 拍：d1_h 拍 n = 输入拍 n-2；垂直 320；级 3
//       水平膨胀 2 拍：e1_h 拍 n = ero_v 拍 n-2；垂直 320），
//       valid 用 18bit 有效拍计数（帧清清零）等价原 644 深 valid 链（省 626 FF）。
// ⚠️ 2026-10-28 位序对齐修复（上板手边缘列状错位根因）：valid 链原 642 深 = 延迟 643 拍，
//       数据实际延迟 644 拍 → O_valid 比数据早 1 拍 → 下游攒字器把第 n 个数据放进第 n+1 组
//       → 标记整体水平错位 1 组（4 像素）。修复：valid 链扩到 644 位（延迟 644 拍），
//       与数据延迟严格同拍（仿真 tb_fg_map 首字图案坐实）。
// 接口：4bit 并行（bit0=行内最左像素），valid 与数据同步；帧开始清全部延迟链防跨帧污染。
// 边缘提取（2026-11-01 区域填充功能一）：形态学梯度 = 开运算 XOR 腐蚀（dil_v ^ ero_v 对齐）。
//   dil_v = 膨胀(腐蚀(原图)) = 开运算，ero_v = 腐蚀(原图)。XOR = 目标外轮廓线（2 像素宽环），
//   单点噪点被腐蚀吃掉后两图皆 0 → 完全消失（比膨胀^原图更干净且省 5000+ FF）。
//   ero_v 中心 = 输入 322 拍前、dil_v 中心 = 输入 644 拍前 → ero_v 打 322 拍对齐（DRAM 环形 320 + 2 拍寄存器）。
// ⚠️ 2026-11-01 资源修复（第二版，slice 超限 2683 后）：行缓冲 + 对齐链全部 DRAM 化
//   （ram_style=dram 环形缓冲）：写 mem[wp]、读 mem[wp+1]（读写地址恒错开，无冲突语义），
//   写数据打 1 拍补偿（ero_h_d1 / rv1_d1）使读值 = 恰 320 拍前（与移位链尾严格同拍）；
//   帧清 = 清指针（数据不清，旧数据靠 valid 门控不输出）。valid 链改 18bit 计数法。
//   开运算数据路径与第一版严格等价（tb_morph_edge/tb_row_fill 同一黄金模型全绿 = 行为不变）。
// ⚠️ 2026-10-27 三项修复（旧版白影错位+白线根因，勿回退）：
//   ① 全链统一「I_valid 拍才推进」——水平级/垂直级/valid 链同策略。旧版水平链每拍 shift、
//      垂直链 valid 门控，空洞拍（3/4 节流相位空洞+行尾 gap，空洞率约 25%）时两者相对漂移
//      → 垂直窗口跨行错位 → 输出错位标记 + 背景噪声被腐蚀/膨胀成伪前景飘线。
//   ② O_valid = valid 链尾 && I_valid——valid 门控链在空洞拍/输入停止期保持，若不加
//      && I_valid 门控，O_valid 会持续为 1，下游攒字器重复消费保持的旧数据（错位）。
//   ③ 行缓冲 320 拍 = 1 行（旧版 320 深本身正确，白影根因在门控不在行深）。
// 帧尾语义：帧间断层（vsync 后无有效拍）链不推进 → 帧尾 643 有效拍数据由下游延迟帧开始
//   脉冲清链丢弃（每半帧底部 2 行标记不更新，fg_init 判据已相应放宽，见 bg_read）。
// 边界说明：首尾行、行首尾 1 像素窗口退化（形态学边界本来退化），对显示效果无感。
//========================================================
module morph_filter (
    input  wire        I_clk,           //DDR 域时钟
    input  wire        I_rst_n,         //复位，低有效
    input  wire        I_frame_start,   //帧开始脉冲：清全部延迟链（防跨帧残留）
    input  wire        I_valid,         //输入有效
    input  wire [3:0]  I_data,          //输入前景标记（4 像素/拍）
    output wire        O_valid,         //输出有效（延迟 645 有效拍，只在数据拍为 1）
    output wire [3:0]  O_data,          //滤波后前景标记（开运算）
    output wire [3:0]  O_edge           //边缘标记（形态学梯度：开运算 XOR 腐蚀，与 O_data 同拍）
);

    //------------ 级 1：3×1 水平腐蚀（左邻 & 中心 & 右邻）------------
    // 处理中心 = d1_h（延迟 1 有效拍）；左邻：p0 用 d2_h[3]，其余 d1_h[i-1]；右邻：p3 用 d0_h[0]，其余 d1_h[i+1]
    // ⚠️ valid 门控推进（与垂直级同策略，空洞拍不 shift）
    reg [3:0] d0_h, d1_h, d2_h;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            d0_h <= 4'd0; d1_h <= 4'd0; d2_h <= 4'd0;
        end else if(I_frame_start) begin
            d0_h <= 4'd0; d1_h <= 4'd0; d2_h <= 4'd0;
        end else if(I_valid) begin
            d0_h <= I_data;
            d1_h <= d0_h;
            d2_h <= d1_h;
        end
    end
    wire [3:0] ero_h = {
        d1_h[2] & d1_h[3] & d0_h[0],   //p3
        d1_h[1] & d1_h[2] & d1_h[3],   //p2
        d1_h[0] & d1_h[1] & d1_h[2],   //p1
        d2_h[3] & d1_h[0] & d1_h[1]    //p0
    };

    //------------ 级 2：1×3 垂直腐蚀（上行 & 中心 & 下行）------------
    // 两级 320 深环形缓冲（DRAM，2026-11-01 资源修复）：mem_v1 读 = 320 拍前 ero_h（中心行）、
    // mem_v2 读 = 640 拍前 ero_h（上行）。与移位链等价（row_v1 尾 = 320 拍前、row_v2 尾 = 640 拍前）。
    // ⚠️ 写读拍账：读地址 = wp+1（最旧位置，最后写入拍 = t-319）；要使读值 = 恰 t-320 拍的数据，
    //    写入打 1 拍（mem_v1 写 ero_h_d1、mem_v2 写 rv1_d1）。读写地址恒错开 → 无同地址冲突语义。
    // ⚠️ 帧清 = 清指针（数据不清，旧数据靠 valid 门控不输出）。
    reg [3:0] ero_h_d1;   //ero_h 打 1 拍（mem_v1 写补偿）
    reg [3:0] rv1_d1;     //rv1 打 1 拍（mem_v2 写补偿）
    reg [3:0] mem_v1 [0:511] /* synthesis ram_style = dram */;
    reg [3:0] mem_v2 [0:511] /* synthesis ram_style = dram */;
    reg [8:0] wp_v1, wp_v2;   //写指针（模 320 回绕，有效拍推进）
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            wp_v1 <= 9'd0; wp_v2 <= 9'd0;
        end else if(I_frame_start) begin
            wp_v1 <= 9'd0; wp_v2 <= 9'd0;
        end else if(I_valid) begin
            mem_v1[wp_v1] <= ero_h_d1;   //= 上一拍 ero_h
            wp_v1 <= (wp_v1 == 9'd319) ? 9'd0 : wp_v1 + 1'b1;
            mem_v2[wp_v2] <= rv1_d1;     //= 上一拍 rv1（320 拍前 ero_h）
            wp_v2 <= (wp_v2 == 9'd319) ? 9'd0 : wp_v2 + 1'b1;
        end
    end
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            ero_h_d1 <= 4'd0; rv1_d1 <= 4'd0;
        end else if(I_frame_start) begin
            ero_h_d1 <= 4'd0; rv1_d1 <= 4'd0;
        end else if(I_valid) begin
            ero_h_d1 <= ero_h;
            rv1_d1   <= mem_v1[(wp_v1 == 9'd319) ? 9'd0 : wp_v1 + 1'b1];
        end
    end
    wire [8:0] rp_v1 = (wp_v1 == 9'd319) ? 9'd0 : wp_v1 + 1'b1;   //读指针 = 最旧位置
    wire [8:0] rp_v2 = (wp_v2 == 9'd319) ? 9'd0 : wp_v2 + 1'b1;
    wire [3:0] rv1 = mem_v1[rp_v1];   //320 拍前 ero_h（中心行）
    wire [3:0] rv2 = mem_v2[rp_v2];   //640 拍前 ero_h（上行）
    wire [3:0] ero_v = rv2 & rv1 & ero_h;   //上行(640有效拍前) & 中心(320) & 下行(当前)

    //------------ 级 3：3×1 水平膨胀（左邻 | 中心 | 右邻）------------
    // ⚠️ valid 门控推进（与级 1 同策略）
    reg [3:0] e0_h, e1_h, e2_h;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            e0_h <= 4'd0; e1_h <= 4'd0; e2_h <= 4'd0;
        end else if(I_frame_start) begin
            e0_h <= 4'd0; e1_h <= 4'd0; e2_h <= 4'd0;
        end else if(I_valid) begin
            e0_h <= ero_v;
            e1_h <= e0_h;
            e2_h <= e1_h;
        end
    end
    wire [3:0] dil_h = {
        e1_h[2] | e1_h[3] | e0_h[0],
        e1_h[1] | e1_h[2] | e1_h[3],
        e1_h[0] | e1_h[1] | e1_h[2],
        e2_h[3] | e1_h[0] | e1_h[1]
    };

    //------------ 级 4：1×3 垂直膨胀（上行 | 中心 | 下行）------------
    // 与级 2 同结构（DRAM 环形缓冲 + 1 拍写补偿）：mem_d1 读 = 320 拍前 dil_h（中心）、
    // mem_d2 读 = 640 拍前 dil_h（上行）。
    reg [3:0] dil_h_d1;   //dil_h 打 1 拍（mem_d1 写补偿）
    reg [3:0] rd1_d1;     //rd1 打 1 拍（mem_d2 写补偿）
    reg [3:0] mem_d1 [0:511] /* synthesis ram_style = dram */;
    reg [3:0] mem_d2 [0:511] /* synthesis ram_style = dram */;
    reg [8:0] wp_d1, wp_d2;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            wp_d1 <= 9'd0; wp_d2 <= 9'd0;
        end else if(I_frame_start) begin
            wp_d1 <= 9'd0; wp_d2 <= 9'd0;
        end else if(I_valid) begin
            mem_d1[wp_d1] <= dil_h_d1;
            wp_d1 <= (wp_d1 == 9'd319) ? 9'd0 : wp_d1 + 1'b1;
            mem_d2[wp_d2] <= rd1_d1;
            wp_d2 <= (wp_d2 == 9'd319) ? 9'd0 : wp_d2 + 1'b1;
        end
    end
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            dil_h_d1 <= 4'd0; rd1_d1 <= 4'd0;
        end else if(I_frame_start) begin
            dil_h_d1 <= 4'd0; rd1_d1 <= 4'd0;
        end else if(I_valid) begin
            dil_h_d1 <= dil_h;
            rd1_d1   <= mem_d1[(wp_d1 == 9'd319) ? 9'd0 : wp_d1 + 1'b1];
        end
    end
    wire [8:0] rp_d1 = (wp_d1 == 9'd319) ? 9'd0 : wp_d1 + 1'b1;
    wire [8:0] rp_d2 = (wp_d2 == 9'd319) ? 9'd0 : wp_d2 + 1'b1;
    wire [3:0] rd1 = mem_d1[rp_d1];
    wire [3:0] rd2 = mem_d2[rp_d2];
    wire [3:0] dil_v = rd2 | rd1 | dil_h;

    //------------ 边缘提取（2026-11-01 第二版）：形态学梯度 = 开运算 XOR 腐蚀 ------------
    // dil_v 中心 = 输入 644 拍前（2+320+2+320）；ero_v 中心 = 输入 322 拍前（2+320）。
    // ero_v 打 322 拍（DRAM 环形 320 + 2 拍寄存器）→ 中心 644 拍前，与 dil_v 同拍 XOR。
    // 语义：开运算 ^ 腐蚀 = 目标外轮廓线（2 像素宽环）；单点噪点被腐蚀吃掉 → 两图皆 0 → 消失。
    reg [3:0] ero_v_d1;   //ero_v 打 1 拍（mem_ea 写补偿）
    reg [3:0] mem_ea [0:511] /* synthesis ram_style = dram */;
    reg [8:0] wp_ea;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            wp_ea <= 9'd0;
        end else if(I_frame_start) begin
            wp_ea <= 9'd0;
        end else if(I_valid) begin
            mem_ea[wp_ea] <= ero_v_d1;
            wp_ea <= (wp_ea == 9'd319) ? 9'd0 : wp_ea + 1'b1;
        end
    end
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            ero_v_d1 <= 4'd0;
        end else if(I_frame_start) begin
            ero_v_d1 <= 4'd0;
        end else if(I_valid) begin
            ero_v_d1 <= ero_v;
        end
    end
    wire [8:0] rp_ea = (wp_ea == 9'd319) ? 9'd0 : wp_ea + 1'b1;
    wire [3:0] ero_v_320 = mem_ea[rp_ea];   //320 拍前 ero_v
    reg  [3:0] ero_v_321, ero_v_322;        //再打 2 拍 → 322 拍前 ero_v（中心 = 644 拍前）
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            ero_v_321 <= 4'd0; ero_v_322 <= 4'd0;
        end else if(I_frame_start) begin
            ero_v_321 <= 4'd0; ero_v_322 <= 4'd0;
        end else if(I_valid) begin
            ero_v_321 <= ero_v_320;
            ero_v_322 <= ero_v_321;
        end
    end
    wire [3:0] edge_comb = dil_v ^ ero_v_322;   //开运算 XOR 腐蚀 = 轮廓线

    //------------ 输出 + valid（644 有效拍数据延迟；valid 计数法 2026-11-01）------------
    // ⚠️ valid 链改 18bit 有效拍计数（帧清清零、I_valid 拍 +1）：out_valid = 计数 >= 644 && I_valid，
    //    与原 644 深 valid 链严格等价（帧清后 644 拍内计数 < 644 → 输出 valid 0；连续输入时
    //    计数 = 拍数 - 帧清偏移）。帧内最大有效拍 174724 < 2^18，无回绕。
    // ⚠️ O_valid = 链尾 && I_valid：链在空洞拍保持 1 会导致下游重复消费旧数据，
    //    必须只在「新数据拍」（I_valid 拍）输出 valid。
    // ⚠️ 2026-10-28：valid 链深 644 位（[643:0]，尾延迟 644 拍）与数据延迟 644 严格同拍——
    //    原 642 深比数据早 1 拍，攒字器错位 1 组（上板手边缘列状错位）。
    reg [17:0] S_vcnt;   //帧清后有效拍计数（I_valid 拍 +1）
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            S_vcnt <= 18'd0;
        else if(I_frame_start)
            S_vcnt <= 18'd0;
        else if(I_valid)
            S_vcnt <= S_vcnt + 1'b1;
    end

    //------------ 输出寄存（2026-10-29 dia 延迟根因修复）------------
    // ⚠️ O_data 原为组合输出（dil_v = 行缓冲 OR 组合）→ bg_read 攒字器写数据路径
    //   = 本组合 + 选择逻辑 → 路径长 → TD 综合在 dia 链插寄存器 → dia 比 addra 晚 1 拍采样
    //   → 字 k-1 写进 addr k → 标记整体左移 1 字（40 像素，实机「修复后左偏移 1-2cm」根因）。
    //   修复：O_data/O_valid 寄存 1 拍 → 写数据纯寄存器输出短路径 → TD 不再插拍 → 三信号同拍。
    //   打拍账：valid 链 643 拍 + 输出寄存 1 拍 = 总延迟 644 拍不变（数据链仍 644：2+320+2+320）。
    // 帧尾语义：输出寄存器帧开始清（配合清链，防跨帧残留）。
    reg [3:0] out_data_q;
    reg [3:0] out_edge_q;
    reg       out_valid_q;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            out_data_q  <= 4'd0;
            out_edge_q  <= 4'd0;
            out_valid_q <= 1'b0;
        end else if(I_frame_start) begin
            out_data_q  <= 4'd0;
            out_edge_q  <= 4'd0;
            out_valid_q <= 1'b0;
        end else begin
            out_data_q  <= dil_v;
            out_edge_q  <= edge_comb;
            // 计数法：链尾 644 拍前有数据 ⟺ 已收有效拍 >= 644（S_vcnt 采样拍前值）
            out_valid_q <= (S_vcnt >= 18'd644) && I_valid;
        end
    end

    assign O_data  = out_data_q;
    assign O_edge  = out_edge_q;
    assign O_valid = out_valid_q;

endmodule
