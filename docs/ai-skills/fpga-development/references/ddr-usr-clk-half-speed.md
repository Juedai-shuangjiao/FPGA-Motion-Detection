# DDR 用户接口时钟 usr_clk 半速问题 + 背景减除全分辨率闪烁根因（2026-10-19）

## 一、usr_clk 半速（核心发现）

**米联客 DDR IP 把 usr_clk 配成了 8:1 半速 66.667MHz，安路官方标准是 4:1 = 133.25MHz。**

### 证据链（全部交叉印证）
1. 官方 IPUG035 DDR IP 手册原文：「PHY to Controller Clock Ratio - 设置物理层（存储器）时钟频率与 PPC 和用户接口时钟频率的比例。**由于 FPGA 逻辑时序限制，只支持 4:1 的比例选项**」→ usr_clk = 内存时钟/4 = 533/4 = 133.25MHz。
2. `ph1p_ddrphy_pll0.v` 顶部注释：`C0 = DDR_SPEED/8`、`C1 = DDR_SPEED/8`、`C2 = DDR_SPEED/2`。DDR_SPEED=1066Mbps → C0=C1=1066/8=133.25MHz（= 内存时钟 533/4）。
3. `ddr2.v` 的 `PLL1_REFCLK_FREQ=133.3`，ph1p_ddrphy_pll1.v 注释 `REFCLK = DDR_SPEED/8`。
4. timing 报告实测：usr_clk=66.667MHz、ctl_clk=66.667MHz、ddr_clk=266.667MHz；tCK=1876ps=533MHz（内存时钟）。
5. `.params_ddr2.txt` 里 `PH1P_ACTUAL_FREQ=533.3`（内存 533.3MHz 不变）。

### 根因（一行写错的公式）
`ph1p_ddrphy_pll0.v` 第 30/31 行：
```verilog
localparam  CLK0_DIV  = CLK2_DIV*4;   // 错！应 CLK2_DIV*2
localparam  CLK1_DIV  = CLK2_DIV*4;   // 错！应 CLK2_DIV*2
```
- VCO = ref_clk/REFCLK_DIV × FBKCLK_DIV = 50/3×32 = 533.33MHz（= 内存时钟）
- CLK2_DIV=2（ddr2.v 传入）→ 内存 clk2 = VCO/2 = 266.67MHz（半速，IOCLK 双沿输出 533）
- CLK0_DIV = CLK2_DIV×4 = 8 → clk0 = VCO/8 = 66.667MHz（半速！）
- 注释「C0=DDR_SPEED/8=133.25=VCO/4」证明 CLK0_DIV 应该是 4 = CLK2_DIV×2

### 修复
```verilog
localparam  CLK0_DIV  = CLK2_DIV*2;   // clk0 66.667→133.25MHz，usr_clk 翻倍
localparam  CLK1_DIV  = CLK2_DIV*2;   // ctl_clk 同步翻倍，保持 usr_clk/ctl_clk 同频 1:1
```
- usr_clk 和 ctl_clk 都 66.667→133.25MHz（必须一起改，保持同频 1:1，否则 PHY/MC 接口频率失配）
- 内存速率 1066Mbps 完全不变（clk2 = VCO/CLK2_DIV 不动）
- DDR 用户接口带宽 8.53Gbit/s（66.667M×128bit）→ 17Gbit/s（内存带宽全用上）

### 为什么不会被 TD 覆盖（改 RTL 安全）
- `CLK0_DIV`/`CLK1_DIV` **不在** `.params_ddr2.txt` 配置文件里（只有 PLL0_CLK2_DIV/PLL0_CLK3_DIV/PLL1_*，没有 CLK0/CLK1）——它们是 RTL 内部 localparam 公式。
- `ddr2.xml` 只是**文件清单**（`<ipxact:name>src/rtl/clk/ph1p_ddrphy_pll0.v</ipxact:name>`），**没有 checksum/md5 校验**，TD 编译时不会「检测到 RTL 被改」而重新生成覆盖。
- ph1p_ddrphy_pll0.v 是 IP 核心 RTL（固定），只有 ddr2.v / ph1p_ddrmc_wrapper_xxx.v 是「按参数生成的 wrapper」。

### 关于「Fmax 90.868MHz」的误判
之前实测 usr_clk 域最坏路径 Fmax=90.868MHz（在加密 MC IP 内部 alc_mc_top/page_ctrl，net 延迟占 71%），一度以为「调 133.3M 会违例」。**这是假象**：当时约束是 8:1 半速（15ns 周期），工具「满足 15ns 就收手」，不会为 7.5ns 优化。官方「只支持 4:1」说明 MC IP 本来就是按 usr_clk=133.25MHz 设计的。改回 4:1 后约束变 7.5ns，工具会重新优化布局，大概率能过。

## 二、背景减除 DDR 全分辨率「解包 D 丢失」bug（白线根因之一）

### 现象
全分辨率背景减除画面有「横白线 ~18 根均匀分布、上下抖动」，切其他算法也闪。

### 根因
`bg_read.v` 读侧 FIFO `re=1'b1` 直读，把「3/4 拍有效」的 128 位流读成了「4/4 拍连续」。而 `data_128bit_to_96bit` 解包期望输入是「3/4 拍有效」（3 个 128 位 → 4 个 96 位，第 4 个 D 靠输入空洞拍输出）。输入变成 4/4 连续后，解包 `S_cnt` 每拍 +1（0→1→2→0 循环），`S_pending`（D）永远没机会输出 → 背景每 3 个 128 位只输出 3 个 96 位，缩水 1/4，减背景必然错位。

### 修复
读侧 re 接「当前帧 128 位 valid」（`S_ISP_O_tvalid`，即 data_96bit_to_128bit 的 O_128b_valid，本身 3/4 拍节奏），让背景读跟当前帧同节奏、解包相位自动对齐：
```verilog
// bg_read 加端口 I_cur_valid，顶层接 .I_cur_valid(S_ISP_O_tvalid)
.re ( I_cur_valid )   // 替代 1'b1
```

### 还没根治的另一半：FIFO 读空（半速带宽不足）
修完 D 丢失后白线性质从「均匀分布」变成「上下移动」= 背景/当前帧错位在周期性漂移。根因：读侧峰值 45M/s（有效期间 3.84ms 突发读 172800 个 128 位）> 写侧受仲裁 20~27M/s（半速 DDR 空闲间隙），FIFO 有效期间读空。**根治 = usr_clk 调满 133.25M（写侧翻倍）**，或降分辨率 640×360（读侧峰值降到 1/4）。motion_detect 减背景加 `I_bg_valid &&` 门控只是兜底（读空时不判前景，避免假白线）。

## 三、本地文档位置
板子资料 `D:\Users\user\Desktop\FPGA比赛\板子资料\HX1P35A_Contest_202606\6_PH1P35数据手册\参考IP设计资料文档.zip`，内含：
- `IPUG035_安路PH1A系列FPGA DDR IP用户手册.pdf`（PH1A/P 同代，DDR IP 结构一致，含「4:1 比例」「dfi_clk=内存时钟/4」等关键规格）
- `IPUG012_Soft_FIFO用户手册_v3.0.pdf`、`APUG011_基于ERAM接口实现的高性能SDRAM读写`、`APUG010_Local bus总线的SDRAM读写`
- 同目录还有 `DS1300_PH1P_Datasheet.pdf`、`DS1301_PH1P_FamilyOverview.pdf`

WSL 提取 PDF：`pdftotext -layout xxx.pdf out.txt`，再 grep 关键词（usr_clk/dhi_clk/时钟比例/频率）。
