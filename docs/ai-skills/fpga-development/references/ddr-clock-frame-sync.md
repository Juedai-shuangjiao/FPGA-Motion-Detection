# DDR 时钟半速根因 + 帧同步对齐循环依赖（2026-10 运动检测 DDR 全分辨率收尾）

> 主题：PH1P35 合封 DDR 为什么半速跑、怎么调满速、以及背景减除「帧同步对齐」的两个死锁陷阱。
> 相关文件：bg_read.v / motion_detect.v / isp_top.v / design_top_wrapper.v / ph1p_ddrphy_pll0.v / ddr2.v + .params_ddr2.txt + .m_params_ddr2.txt + Design.xml

## 一、DDR 半速根因（重大发现，别再看错）

板子（HX1P35A）有 **100MHz 差分晶振（SIT9121，引脚 K5/L5，LVDS）**，原理图网络名 `FPGA_DDR_100MHZ_LVDS_P/N`，是 DDR 内核专用参考时钟源。但**米联客官方例程（含 lab_ex1）统一把它闲置了**——DDR ref_clk 接的是 50MHz 晶振（C4，即 `I_sys_clk`），引脚约束里根本没有 K5/L5。

判据链（本地资料可查，别重新猜）：
1. `src/hdl_source_ip/ddr2/.params_ddr2.txt` 里 `PH1P_REF_CLK = 100.0000`（DDR IP 期望 100M 参考时钟）
2. `ph1p_ddrphy_pll1.v` 头注释 `REFCLK : DDR_SPEED/8`，`PLL1_REFCLK_FREQ=133.3`
3. timing 报告实测 `usr_clk=66.667`（=133.3 一半）、`ddr_clk=266.667`（=533 一半）
4. `6_PH1P35数据手册/参考IP设计资料文档.zip` 解压出 `IPUG035_安路PH1A系列FPGA DDR IP用户手册.pdf`：「**PHY to Controller Clock Ratio 只支持 4:1**」+「工作时钟 = 存储器时钟的 1/4」

**结论**：ref_clk 接 50M → VCO 只有一半 → **整个 DDR 半速**（内存 533Mbps + usr_clk 66.667）。正确满速 = ref_clk 接 100M 差分晶振 → 内存 1066Mbps + usr_clk 133.3。注意「usr_clk 半速」只是表象，根子是「内存+usr_clk 一起半速」。

## 二、LVDS 差分输入原语

安路 PH1P 的差分转单端 buffer = **`PH1P_LOGIC_IBUF_DIFF`**（TD 模板库 `template/verilog/Device-Primitive/PH1P/I,O/ph1p_i_o.v`，本地 TD 安装目录里就有，比 GitHub 任何第三方都权威）：
- 端口：`i_p`（差分 P）、`i_n`（差分 N）、`o`（单端输出）、`o_p`/`o_n`（差分输出，不用）、`interm_disable`（接 1'b0）
- 参数：`DIFF_TERM`（片内 100Ω 端接，"TRUE"/"FALSE"）
- **K5/L5 在 DDR I/O BANK，只支持 LVDS18（1.8V），不支持 LVDS33**。SIT9121 虽 3.3V 供电，但 LVDS 是电流驱动标准（共模 1.2V、摆幅 ±350mV），电气兼容 LVDS18，IOSTANDARD 写 LVDS18 即可。

## 三、DDR 内存速率调整（1066 → 800Mbps）

满速 1066Mbps 下 usr_clk 域最坏路径 7.493ns vs 周期 7.5ns，SWNS 只 +0.007 贴边 → 温度/电压波动偶发违例 → 全屏花屏 + 长方形黑屏滚动（DDR 读写指针错位）。降到 **800Mbps**（usr_clk 100M，周期 10ns）裕量 2.5ns 才稳定。

改内存速率要**四文件联动**（漏一个都不生效/不一致）：`ddr2.v`、`.params_ddr2.txt`、`.m_params_ddr2.txt`、`Design.xml`。参数对照：
- `tCK` 1876→2500（内存 CK 周期，533M→400M）
- `CL` 7→6、`CWL` 6→5（DDR3-800E 档）
- `PLL0_FBKCLK_DIV` 32→24（VCO=ref_clk×FBKCLK_DIV/REFCLK_DIV，800Mbps 要 VCO=800=100×24/3）
- `PLL1_REFCLK_FREQ` 133.3→100.0（PLL1 参考 = PLL0 clk0 = VCO/8 = 100）

`.params` 里 `PH1P_DDR_CL`、`PH1P_ACTUAL_FREQ` 两个 Dis（派生）值也一起改。

## 四、帧同步对齐的循环依赖死锁（架构大坑，必读）

背景减除「帧同步对齐」（用背景帧开始动态对齐当前帧，替代固定 DELAY 拍）会引入**两个循环依赖死锁**，上电后 motion_tuser/motion_valid 恒 0 → 背景读不触发 → 画面卡死、video_in 写指针不动、上 3/4 黑屏下 1/4 花屏：

1. **帧开始环**：`motion_tuser → 背景读(需帧开始) → 背景帧开始 → 读指针对齐 → motion_tuser`
2. **读侧 re 环**：`读侧 re=motion_valid → 背景帧开始 → 背景读 → re`

打破方法：
- 帧开始（`data_96bit_to_128bit` 的 `I_96b_frame_start` / isp_top 的 `O_tuser`）**始终用 `awb_O_tuser`（摄像头帧开始，独立源头）**，不用 `motion_tuser`
- bg_read 读侧 re 用**独立自由跑的 3:4 节流计数器**（`S_fifo_rd_34_cnt != 0`），不用当前帧 valid（`S_ISP_O_tvalid`）
- 原样叠加的数据要用 motion 输出的「读出的当前帧」（`O_cur_data`），不能用固定打拍（帧同步对齐后延迟是动态的）

## 五、128→96 解包需要 3/4 节流（D 丢失 bug）

`data_128bit_to_96bit` 解包期望输入「3/4 拍有效」（打包的 cnt=0 是空洞）。读侧 `re=1'b1` 直读会把「3/4 拍」读成「4/4 拍连续」，解包 S_cnt 每拍 +1，第 4 个 96 位（D）永远丢不出来 → 背景缩水 1/4 错位。读侧 re 必须 3:4 节流（或当前帧 valid 的 3/4 拍节奏）。
