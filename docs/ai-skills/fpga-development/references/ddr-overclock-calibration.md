# PH1P DDR 超频与校准失败排查（2026-10-23 实测血泪）

## 铁律
- MC IP 的 PHY-MC 接口按 **8:1 固化**：usr_clk = 内存速率/16。**比例不能改，超频只能整体等比缩放**。
- 时钟拓扑：PLL0 clk0→PLL1 参考→dhi_clk(usr_clk)；clk1→ctl_clk(PHY DFI 侧)；clk2→ddr_clk(内存)。MC 在 dhi_clk 域、PHY 在 ctl_clk 域，1:1 同步假设。
- 改 CLK0_DIV ×4→×2（4:1）→ 校准失败。CLK1_DIV 也翻 → 内存超频 2133 更黑。
- 用户历史经验：1660Mbps 整体超频工作过 → 证明「同比例超频可行」。

## 校准失败诊断特征（区别于其他黑屏）
- SW4 写计数 = 0（写状态机一拍没跑）
- 黑屏但有 Logo（OSD 不依赖 DDR）
- 自动曝光/增益可调（AEC 走 MIPI 域，不经 DDR）→ 采集链活、DDR 域死
- 机制：init_calib_complete 不拉高 → S_rst_n(=pll_lock&&calib) 挂起 → 读写全停
- 即：不是「数据读不出」，是「写侧没启动」（校准失败，DDR 域复位态）

## 1600Mbps 成功参数组（等比 ×1.5）
改：tCK 1876→1250、PLL0_FBKCLK_DIV 32→48、PLL0_CLK3_DIV 21→32（cfg_clk 保 50M）、PLL1_REFCLK_FREQ 133.3→200.0
**必须保持官方**：CL=7、CWL=6、CLK2_DIV=2、SPEED_BIN=DDR2-1066、PH1P_DDR_SPEED=1066.00
结果：ddr_clk 400M（内存 1600）、usr_clk 100M、SWNS 0.678ns、下板画面正常。

## 翻车记录（每个都是校准失败/时序违例）
1. CL 11/CWL 9（按绝对时间推）→ 校准失败黑屏。校准训练按 CL 期望找读回数据位置，参数与颗粒不符不收敛。
2. SPEED_BIN 改 DDR2-1600 → 校准失败。枚举只有 DDR2-1066/1333-8/1333-9，查表落空。
3. CLK2_DIV 2→3（误当等比分频）→ ddr_clk 半速 400→266（内存 533）+ SWNS -1.58。内存速率=VCO 直接，CLK2_DIV 是 ddr_clk 分频不是缩放。
4. PH1P_DDR_SPEED 改 1600.00（SPEED 范围合法 400~1600）——bin 表相关一起回退官方最稳。

## sdc 坑
- 1600 下 TD 把 usr_clk 报成 ref_clk（PLL1 rename 失败），set_clock_groups 里明确列 usr_clk 名 → 整条命令 fails → MIPI→DDR 跨域 hold 违例 -1.58ns。
- 解法：DDR 域组用通配符 `get_clocks {u_ph1p35_324_ddr_wrapper/u_ddr2/*}`。
- 改 sdc 后必须重跑 syn（phy 阶段从 syn 产物继承约束，不重读源 sdc）；且只重跑 phy 会被 TD 静默跳过（syn 产物没变就复用旧结果）。

## 带宽预算（1600 配置，Python tick 模型验证）
- 一帧 172800 个 128bit；两帧 345600。消隐期 4.212ms（720p）。
- 100M usr_clk：读两帧 357160 tick = 3.57ms ✓（含 40 拍延迟 + 1440 突发×8 拍间隙）；66.67M 时 5.18ms ✗。
- 写侧：需 1.79ms，可用 11.2ms，余量 527%。

## 网络检索经验
- web_search keyless 后端常超时；改用 playwright MCP + 必应英文关键词（`Anlogic PH1P DDR IP overclock calibration failed`）。
- cn.bing 中文关键词会被拆字；百度有图形验证码。
- 有用资源：embedtech.cn/anlogic/136/137/（PH1P35 合封 DDR2 已知坑：双 PLL 默认仿真 X、单 PLL 勾选消失）；权威手册 IPUG034（MIS DDR IP 用户手册）。
