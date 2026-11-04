# DDR 时钟树 + 半速根因 + 调时钟方向（2026-10-19 挖板子资料坐实）

## 结论一句话

PH1P35 的合封 DDR 标称 1066Mbps（17Gbit/s），但米联客例程把 DDR 的 ref_clk 接成 **50M 晶振（C4）** 而非板上的 **100MHz 差分晶振（SIT9121，引脚 K5/L5）**，导致**整个 DDR 半速跑**：内存 533Mbps + usr_clk 66.667MHz，带宽只有 8.53Gbit/s。这是「运动检测背景读写侧速率不足、FIFO 读空、白线上下漂移」的真根因。

## 证据链

1. **板子原理图**（`3_原理图/开发板原理图/HX1P35B_FT_40P_8.pdf` 第 9 页）：SIT9121AI-2B1 差分晶振，`CLKp → FPGA_DDR_100MHZ_LVDS_P → K5`，`CLKn → FPGA_DDR_100MHZ_LVDS_N → L5`。
2. **开发板手册**（`9_康芯开发板使用手册及实验平台/新HX1P35A开发板手册-HDL版2604.pdf`）：「内核 DDR 差分时钟源，100MHz，SIT9121，LVDS3.3V」。
3. **DDR IP 配置**（`src/hdl_source_ip/ddr2/.params_ddr2.txt`）：`PH1P_REF_CLK : 100.0000`（期望 ref_clk=100M），`PH1P_ACTUAL_FREQ : 533.3`（期望内存 533.3M）。
4. **米联客顶层**：`design_top_wrapper.v` 里 `ph1p35_324_ddr_wrapper` 的 `.I_sys_clk(I_sys_clk)`，而 `I_sys_clk` = C4（50M 晶振）。引脚约束 `pin.adc` 里**没有 K5/L5**（100M 差分晶振被闲置）。
5. **官方 lab_ex1 例程同样半速**：`lab_ex1_mipi_hdmi_SC500_720P.zip` 里的 `ph1p_ddrphy_pll0.v` 也是 `CLK0_DIV = CLK2_DIV*4`，坐实「半速是米联客统一做法，非本工程特有」。

## DDR 时钟树（PLL0 级联 PLL1）

```
ref_clk(50M) → PLL0(REFCLK_DIV=3, FBKCLK_DIV=32)
  VCO = 50 × 32/3 = 533.33 MHz
  clk0 = VCO/8 = 66.667 MHz   → PLL1 参考时钟
  clk1 = VCO/8 = 66.667 MHz   → ctl_clk（PHY 控制）
  clk2 = VCO/2 = 266.67 MHz   → ddr_clk（内存 CK 半速）
  clk3 = VCO/21               → cfg_clk
  → PLL1(EXTERNAL FEEDBACK, FBCLK_DIV=REFCLK_DIV=4, CLK0_DIV=12)
    usr_clk = clk0 = 66.667 MHz（反馈锁定后输出=输入）
```

`ph1p_ddrphy_pll0.v` 顶部注释暴露设计意图：
```
// C0 | DDR_SPEED/8   (= 1066/8 = 133.25 MHz)
// C1 | DDR_SPEED/8
// C2 | DDR_SPEED/2   (= 533 MHz 内存时钟)
```

注释说 C0=133.25，但 `localparam CLK0_DIV = CLK2_DIV*4`（=8）让 clk0=VCO/8=66.667（DDR_SPEED/16），正好半速。

## 调时钟的正确方向 = 改 ref_clk，不是改 CLK0_DIV

- **正确**：DDR ref_clk 从 50M（C4）改接板上的 100M 差分晶振（K5/L5）→ VCO=1066.67 → 内存 CK=clk2=533（1066Mbps 满速）+ clk0=133.3（usr_clk 满速），内存和 usr_clk 同时满速，带宽翻倍到 17G。
- **错误（踩过坑，别重走）**：改 `ph1p_ddrphy_pll0.v` 的 `CLK0_DIV ×4→×2`，只让 usr_clk 翻倍到 133.3，但内存还半速 533Mbps，usr_clk(133.3M×128bit=17G) 和内存(533Mbps×16=8.53G) **速率不匹配，MC 内部饿死**。要满速必须 ref_clk 换 100M。

## IPUG035 DDR IP 手册要点（权威）

文件在板子资料 `6_PH1P35数据手册/参考IP设计资料文档.zip` 内 `IPUG035_安路PH1A系列FPGA DDR IP用户手册.pdf`（PH1A/PH1P 同代，DDR IP 结构一致）。

- 「PHY to Controller Clock Ratio：由于 FPGA 逻辑时序限制，**只支持 4:1 的比例选项**」→ usr_clk = 内存时钟/4 = 133.25MHz。
- 「PPC 工作时钟与 dfi_clk 相同，是存储器时钟频率的 1/4」。
- 参考时钟（PLL Reference Clock）：推荐从 DDR AC Bank HPIO 输入，**100MHz**（`create_clock -period 10 -name sys_clk -waveform {0 5}`）。
- Clock Pin Selection：Clock Type 有 **Diff / Single / None** 三种；参考时钟为差分信号时选 Diff，单端选 Single。
- 改 ref_clk 100M 的落地：① 引脚约束加 K5/L5（LVDS 差分）② 顶层 LVDS 差分转单端 ③ DDR wrapper ref_clk 接 100M 单端 ④ SDC 加 100M 时钟约束（DDR IP 是 ddr2.xml 引用的，`ph1p_ddrphy_pll0.v` 在 IP 深层目录 src/hdl_source_ip/ddr2/src/rtl/clk/，TD 的 Design 源文件列表不直接显示，用记事本按路径打开确认）。

## 时序假象（重要，别被 Fmax 误导）

usr_clk 域最坏路径（DDR MC 加密 IP 内部 alc_mc_top/page_ctrl）实测 Fmax 90.868MHz、Data Path 10.761ns（**net 延迟占 71%**）。这不是「IP 焊死 90MHz」，而是「被配成 8:1 半速、约束 15ns 周期、工具没按 133M 去优化」的假象——net 延迟占比高说明布局还有大量优化空间，改回官方 4:1=133.25 后工具会重新优化，MC IP 按 133.25 设计应能过。

## bg_read 解包 D 丢失 bug（白线根因之一）

bg_read 的 FIFO 读侧 `re=1'b1` 直读，把「3/4 拍有效」的 128 位流读成「4/4 拍连续」，导致 `data_128bit_to_96bit` 解包的 S_cnt 每拍 +1、第 4 个 96 位（D）永远丢不出来，背景每 3 个 128 位只输出 3 个 96 位（缩水 1/4），跟当前帧错位出白线。修法：读侧 re 改接「当前帧 128 位 valid」（S_ISP_O_tvalid，本身就是 3/4 拍节奏），解包相位自动对齐；motion_detect 减背景加 `I_bg_valid &&` 门控兜底 FIFO 读空。

## 白线「上下移动」的诊断本质

白线固定分布 = 确定性错位（如解包 D 丢失）；白线上下移动/闪烁 = **周期性相位漂移** = 两个异步时钟域（DDR 66.667M vs 摄像头 60M）频率差 11% 导致 FIFO 水位漂移。根治方向不是「调对齐拍数」（漂移是连续的），而是「让写侧速率 ≥ 读侧消费」：降背景分辨率（读侧消费降 1/4）或调 DDR 满速（写侧速率翻倍）。
