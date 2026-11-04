# PH1P MIS DDR IP：时钟拓扑、比例铁律与超频参数（实测闭环）

## 时钟拓扑（ph1p_ddrphy_clk_top.v + 时序报告实测）

```
PLL0 clk0 → PLL1 参考 → PLL1 clk0 = dhi_clk = usr_clk（MC + 用户逻辑域）
PLL0 clk1 → MLCLK 树缓冲 → ctl_clk（PHY 控制/DFI 接口域）
PLL0 clk2 → MLCLK → ddr_clk（内存时钟）
PLL0 clk3 → cfg_clk（APB 配置时钟，保持 ~50M）
pll_lock = PLL1 的 lock
```

pll0.v 的 localparam：`CLK0_DIV = CLK2_DIV*4`、`CLK1_DIV = CLK2_DIV*4`（例化时 .m_params 传入 CLK2_DIV=2 时 CLK0/1=8）。

## 铁律：时钟比例锁死，提速只能同比例超频

- **dhi_clk(usr_clk) 与 ctl_clk 频率 1:1 锁死**：MC↔PHY 的 DFI 接口按同频同步设计。只翻 CLK0_DIV（usr_clk 66.67→133.35M，8:1→4:1）下板 = init_calib_complete 永不拉高 → 黑屏 + 写计数 0。比例破坏 = 校准失败，不是时序贴边问题。
- **CLK1_DIV 不是 usr_clk 的分频**：CLK1 经 MLCLK 树给 PHY，翻倍它 = 内存时钟翻倍（内存 1066→2133 超频，老 bug 重现）。usr_clk 提速只能动 CLK0_DIV 那条线——但会破坏 1:1 铁律，所以**改比例这条路线整体死路**。
- **正确提速 = 提高 VCO（FBKCLK_DIV），所有时钟同比例缩放**：用户历史 1660Mbps 下板正常（同比例超频、1:1 保持），是本结论的直接验证。
- 经验映射：usr_clk ≈ 内存速率/16（1066→66.67M、1600→100M、1660→103.75M）。

## 内存速率与 VCO 关系

- 时序报告里的 ref_clk/ddr_clk 频率按 **PLL 的 REFCLK_FREQ 参数声明**算，不按引脚实际输入（ref 实际 50M、声明 100M 时报告按 100 推）。
- ddr_clk = VCO/CLK2_DIV；DDR 数据率 = 4×ddr_clk（1066 配置报 ddr_clk 266.67M → 1066.67Mbps）。
- **CLK2_DIV 保持 2 不动**：它是 ddr_clk 分频，改成 3 会把内存半速（1600 翻车实测：报 ddr_clk 400→266.67，内存 533）。
- cfg_clk 保持 ~50M：VCO ×1.5 时 CLK3_DIV 同步 ×1.5（21→32）。

## 超频参数等比缩放（1066→1600 反推，已编译全绿）

| 参数 | 1066 官方 | 1600 反推 | 说明 |
|---|---|---|---|
| tCK | 1876 | 1250 | CK 533M→800M |
| CL | 7 | 11 | 绝对时间保持 13.1ns（取整偏宽松） |
| CWL | 6 | 9 | 绝对时间 11.26ns 精确保持 |
| PLL0_FBKCLK_DIV | 32 | 48 | VCO ×1.5 |
| PLL0_CLK3_DIV | 21 | 32 | cfg_clk 保持 50M |
| PLL1_REFCLK_FREQ | 133.3 | 200.0 | PLL1 参考跟着涨 |
| PLL0_CLK2_DIV | 2 | **2（不动）** | 改 3 = 内存半速 |
| PH1P_DDR_SPEED | 1066.00 | **1066.00（不动）** | 见下 |
| PH1P_SPEED_BIN | DDR2-1066 | **DDR2-1066（不动）** | 枚举只有 1066/1333-8/1333-9 |

- **SPEED_BIN/PH1P_DDR_SPEED 必须保持官方值**：bin 枚举表（.params 里 `DDR2-1066;;DDR2-1333-8;;DDR2-1333-9`）只到 1333，改成不存在的 DDR2-1600 会让 IP 校准初始参数查表落空 → 校准失败黑屏。实际速率由 tCK/PLL 参数决定，bin 表只给训练初始参数——超频套路 = bin 不碰、只改速率参数（用户 1660 历史同款）。
- 四文件同步改：ddr2.v、.params_ddr2.txt、.m_params_ddr2.txt、Design.xml（每文件格式不同：`.tCK(1876)` / `tCK : 1876 : G` / `tCK; 1; 1876` / `referenceId="tCK">1876<`）。
- ⚠️ 1600 版编译 SWNS 1.215ns 全绿，但「bin 回退」最终版的下板结果本会话未闭环——超频下板验证以实际画面为准，校准不过先查 bin 一致性再查 tCK/CL/CWL。

## 校准失败的症状诊断（金标准组合）

黑屏 + Logo/OSD 文字仍在 + SW4 写计数 00000000 + 自动曝光/增益仍会收敛 = **init_calib_complete=0，DDR 域全停**。

- Logo 在 = HDMI 域独立工作（OSD 不走 DDR）；曝光可调 = 采集链活（摄像头→MIPI→ISP→AEC 全在 MIPI_RX_BYTE_CLK 59.995M 域，完全不经过 DDR）。这两个信号只证明「外围活」，不能证明 DDR。
- S_rst_n 等 init_calib_complete 才释放 → 写计数 0（写侧从没启动）→ 读 FIFO 空 → 黑屏。
- 看到这个组合：先查时钟比例/参数（bin 一致性、CLK2_DIV、FBKCLK_DIV 是否生效），不要先怀疑 HDMI 时序。

## final_timing.rpt 违例定位

- `grep -E "From Clock|To Clock|Path Group" final_timing.rpt` 定位违例所在时钟域；`SWNS 负` + 1 个 Viol Endpoint 时看单条路径的 Begin/End Point。
- 跨域 hold 违例常见于同步链第一级（如帧开始跨域打 3 拍）——电平展宽 + 3 拍链下第一级亚稳态可接受，用 set_clock_groups -asynchronous 关跨域检查即可。
- **DDR 域时钟名随配置变化**：1600 下 usr_clk 名消失（ddr2.sdc 的 rename_clock 失败），时序报告改报 ref_clk——sdc 里组内引用失效名字会让整条 set_clock_groups 命令 fails。Group 匹配用通配符 `u_ph1p35_324_ddr_wrapper/u_ddr2/*` 覆盖整个 DDR 域，一劳永逸。

## TD 增量机制坑（改约束必须全量重跑）

- 只清 phy_1 db 重跑 phy 会被 **静默跳过**：syn 产物时间戳没变，TD 认为 phy 已最新，进程跑 14 分钟但无新 log、无新 bit、SWNS 不变（看似「重跑无效」）。
- 改 sdc/约束后：删 syn_1+phy_1 的 db 全量重跑；完成后在**本轮 log**（按时间戳取最新 td_*.log）验证 set_clock_groups 无 CRITICAL-WARNING——旧 log 会误导 grep 结果。
- 验证缩放是否生效：对比 final_timing.rpt 时钟表（如 ddr_clk 266.67→400 = 精确 1.5×），比值说话，不靠参数文件猜。
