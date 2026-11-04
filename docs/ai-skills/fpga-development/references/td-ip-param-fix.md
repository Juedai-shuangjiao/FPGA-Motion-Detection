# TD IP 参数修改与重新生成（PH1P35 DDR2 实战教训，2026-10 最右列伪影根因战）

## 触发场景
改 DDR IP 参数（PH1P_REF_CLK 50→100）修复 usr_clk 频率错误（133.33M = 2 倍超频 → 最右列 3 像素伪影）。

## 关键事实

1. IP 参数三层文件（同一目录 src/hdl_source_ip/ddr2/）：`.params_ddr2.txt`、`.m_params_ddr2.txt`、`Design.xml`。
2. TD 增量编译**不监视这三个文件**——改完必须删 `syn_1/*.db syn_1/*.area syn_1/*.timing syn_1/*.ts phy_1/*.db phy_1/*.bit phy_1/final_timing.rpt` 强制全量重编。
3. 删 db 后在 syn_1 目录跑 DefaultFlow **只完成 syn 不自动衔接 phy**——需在 phy_1 目录再跑一次 DefaultFlow.tcl（约 11 分钟）。全量 syn 约 23-26 分钟。
4. 验证：`phy_1/final_timing.rpt` 的 `clk1:` = usr_clk 实际频率（66.667 正确 / 133.333 = REF_CLK 按 50 配的 2 倍超频）。
5. 官方基线工程：`/mnt/e/FPGA_Code/lab_ex1_mipi_hdmi_SC500_720P/lab_ex1_mipi_hdmi/td_project/camera_to_dsi_display.al`——官方全量重编 clk1=66.667，是参数对齐的判据。
6. **对齐方式：整目录 md5sum 递归对比 + 原样拷贝官方三个参数文件，禁止单点 sed**——本次教训：单点 sed 改 PH1P_REF_CLK 后以为对齐，实则 .params/.m_params 还有大量差异（PH1P_IO_VOL 1.8 vs 官方 1.5 等），clk 依旧 133.33，直到整文件 md5 对齐才修复。
7. GUI 重新生成路线不可靠（TD 6.2）：双击 IP 报 `depot//Component.xml` 空路径 bug；右键 IP 无 Regenerate；IP Catalog 只能新建；IpTool.exe 命令行启动即闪退。文件级对齐优于 GUI 重新生成。
8. 工程 .al 是 XML：IP 引用在 `<IP_FILE>` 段落（带 FileInfo/CompileOrder 属性）；Remove 后手动插回 `<File Path="../src/hdl_source_ip/ddr2/ddr2.xml">` 块即可。.al 中 `UsedInP&R` 的 & 未转义，Python 严格解析报错但 TD 容忍。
9. DDR IP 时钟链：PLL0 级联 PLL1（PLL0 输出给 PLL1 供参考），PH1P_REF_CLK 声明错 → 整链翻倍 → usr_clk 2 倍超频 → DDR 读眼图边缘采样错误（位置固定、内容随机、少量像素）。
10. 官方 DDR2 关键参数：PH1P_REF_CLK=100、PH1P_DDR_SPEED=1066、PH1P_DQ_BYTE=2、PH1P_COMP_TYPE=x16、PH1P_SINGLE_PLL=0、PH1P_IO_VOL=1.5、CL=7、CWL=6。
11. 显示侧保底方案（hdmi_mixer）：最右列 bug 用「锁存 bug 区左侧正常列 + x≥1276 复制填充」可完全覆盖——覆盖边界须提前 1 拍（bug 实际起点比推算早 1 拍，首版 x≥1277 残留 1 像素，改 x≥1276 干净）。

## 参数文本与 IP 实例固化不一致 → PLL 计算失败 → 约束全缺失（2026-10-26 nogrant 冻结根因）

**现象链**：改 DDR 参数文本但不 Regenerate（IP 实例固化旧配置）→ phy 阶段按「新文本」算 PLL → 参数非法时 SYN-8411「VCO out of range [800,2000]」→ derive_clocks 失败 → DDR 时序约束全缺失 → 布局布线无时序引导赌运气（有的编译正常工作、有的校准失败）。诊断特征：**写计数 0 + 画面冻结（显示 DDR 残留旧数据）+ 复位无效 + OSD/曝光正常** = DDR 校准失败（init_calib_complete 恒 0 门控掉所有读写使能）。

**实锤过程**：nogrant 10-23 深夜把参数文本改成「1600 组」（tCK 1250/PLL0_FBKCLK_DIV 48/PLL0_CLK3_DIV 32/PLL1_REFCLK_FREQ 200）但 IP 实例一直固化 800 配置。IPUG034 官方手册：**DDR2 速率上限 1333Mbps**（1600 非法！1600 是 DDR3/DDR4 上限）、ref_clk 范围 25~400MHz。1600 组下 PLL1 参考 200M → VCO = 200×12 = 2400MHz 超硬件范围 → 每次 phy 都报 SYN-8411（从 10-23 21:51 起每次编译都报，没人看日志）。15:29 版侥幸收敛（有画面），18:30 版改动后布局变 → 校准失败。

**修复**：参数文本改回官方 1066 组（tCK 1876/PLL0_FBKCLK_DIV 32/PLL0_CLK3_DIV 21/PLL1_REFCLK_FREQ 133.3，其余 PH1P_REF_CLK=100/CL=7/CWL=6/CLK2=2/SPEED_BIN=DDR2-1066 本来就和官方一致）——官方 lab_ex1 的 .params_ddr2.txt 是权威参考；该组合 PLL VCO = 133.3×12 = 1600 ✓ 在范围内，10-23 15:15 编译（SYN-8411=0）验证过。

**真正的参数载体 = ddr2.v 的例化参数（2026-10-26 二次实锤，此条最重要）**：改 .params/.m_params/Design.xml 三个文本文件**完全无效**——综合/布局布线读的是 `src/hdl_source_ip/ddr2/ddr2.v` 里 `ph1p_ddrmc_wrapper` 例化的参数（.tCK/.PLL0_FBKCLK_DIV/.PLL1_REFCLK_FREQ 等）。10-23 21:30（同步 1600 组时）重新生成的 ddr2.v 固化了 1600 组（tCK 1250/PLL1REF 200），此后文本怎么改都不影响编译。**改 DDR 参数 = 改 ddr2.v（或 GUI Regenerate 重新生成 ddr2.v）**；验证 = ddr2.v 与官方 lab_ex1 的 ddr2.v 逐字节 diff（去 CRLF）为零。之前 19 节「参数文件改无效」的结论正确但解释不完整——真正原因是参数在 ddr2.v 里。

**「1600 超频」的完整真相（2026-10-26 定案）**：1600 组 ddr2.v 固化后，PLL 参数计算失败（VCO 2400 超范围）但网表仍按例化参数接线：ref 50M(C4) → PLL0 REFCLK_DIV 3/FBKCLK 48 → VCO0 800M → ddr_clk 400M（内存 800Mbps）、usr_clk 100M（PLL1 200/4×24/12）。**即 1600 组实际跑出 800 配置的频率**——「内存 1600Mbps」从未发生，但 usr_clk 100M 是真的（主线带宽预算结论不受影响）。tCK 1250 声明与实际 400M 时钟错配，PHY 内部时序参数与实际时钟矛盾 = 校准不稳定的根因。

**教训**：
- 改 IP 参数文本后必查 phy 日志的 SYN-8411 / derive_clocks fails 条数（0 = 正常）——这是「参数文本 vs 实例固化」矛盾的免费报警器
- 时序报告 SWNS 全绿不能证明 DDR 约束健康：SYN-8411 时约束全缺失，SWNS 只覆盖已约束路径，未约束路径不报
- 「超频成功」结论要拿时序报告的时钟频率核对：1600 组的 tCK 1250 从未真正生效（IP 实例一直 800），主线「内存 1600Mbps」的说法实为 800Mbps（usr_clk 100M 不变，带宽预算结论不受影响）
