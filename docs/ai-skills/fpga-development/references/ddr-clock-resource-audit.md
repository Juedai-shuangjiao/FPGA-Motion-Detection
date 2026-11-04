# DDR 时钟树 + 资源账审计（2026-10-19 运动检测 DDR 改造时追出来的）

## 一、DDR 用户接口 usr_clk 是「半速」66.667MHz（设计目标 133.3MHz）

timing 报告 Clock Summary 权威实测值（别信文档里「1066Mbps 满速 17Gbit/s」的假设）：

| 时钟 | 实测频率 |
|---|---|
| MIPI_RX_BYTE_CLK（=S_csi_rx_clk，摄像头域） | 60 MHz |
| usr_clk（DDR 用户接口 = S_ddr_clk = dhi_clk） | 66.667 MHz |
| ddr_clk（DDR 内存时钟） | 266.667 MHz |
| HDMI_PIXEL_CLK | 75 MHz |
| HDMI_SERIAL_CLK | 375 MHz |
| 低速：sys_clk_50m / pll_clk_100m / pll_clk_24m | 50 / 100 / 24 MHz |

### 根因（时钟树追到底）

DDR 硬核 PLL 链：`50M晶振 → PLL0 → clk0(VCO/8=66.667M) → PLL1参考 → usr_clk`

- `ph1p_ddrphy_pll1.v` 顶部注释写死：`REFCLK : DDR_SPEED/8`，且 `PLL1_REFCLK_FREQ=133.3`（=1066/8）。
- 但 `ph1p_ddrphy_pll0.v` 里 `localparam CLK0_DIV = CLK2_DIV*4 = 8`，导致 `clk0 = VCO/8 = 66.667MHz`（本应 `VCO/4 = 133.3MHz`）。
- 所以 usr_clk 带宽 = 66.667M × 128bit = **8.53 Gbit/s，只有内存带宽的一半**（tCK=1876ps=533MHz → 1066Mbps×16bit = 17.06 Gbit/s）。

### 影响

三个整帧访问（video_in 写 1.33 + video_out 显示读 1.33 + bg_read 背景读 1.33 ≈ 4 Gbit/s）在当前 8.53G 下占 ~47%，调满后只占 23.5%，仲裁余量翻倍。背景读「低优先级抢边角料」读得慢 → FIFO 读空 → 背景断续错位，根子就是这半速带宽。

### 改法（时钟调高）

1. `ph1p_ddrphy_pll0.v` 第 30 行 `localparam CLK0_DIV = CLK2_DIV*4` 改成 `*2`（clk0 翻倍 → 133.3M）。
2. 或把 `ph1p35_324_ddr_wrapper` 的 `I_sys_clk` 从 50M 晶振换成主 PLL 的 `S_100m_clk`（100M）。

⚠️ 两者都动 DDR PHY 硬核 IP 内部参数，DDR 校准/时序可能重新变紧，**单独验证，别和功能改动混一起下板**。

## 二、算法串行化不划算（资源账实测）

RTL area 模块级（`prj/FPGACompetition_Runs/syn_1/FPGACompetition_rtl.area`）：

| 模块 | gates | FF | ERAM |
|---|---|---|---|
| motion_detect（DDR 版） | 20 | 126 | 0 |
| canny_top（边缘） | 260 | 811 | 6 |
| binary/gray（灰度二值） | 12 | 0 | 0 |
| brightness_stat（曝光） | 3 | 42 | 0 |
| **算法合计** | ~300 | ~1000 | ~6 |

算法并行总开销 ~1000 FF ≈ 总 FF(24197) 的 **4%**。真正吃资源的是别处：

- `anlogic_logo_rom` 38666 gates（Logo 6400 行 case，LUT 大头，基础任务强制保留，可 BRAM 化）
- `awb` 两个 32 位除法器 8114 FF（白平衡必需）
- DDR PHY + MC ~5800 FF（硬核）

结论：**保持并行，串行化是负收益**（省不下 4%，却要状态机 + 时钟倍频 + 数据缓存）。

## 三、soft_fifo 读侧时序（改 bg_read 读侧 re 前必读）

`w128_d512_fifo` 是 soft_fifo（`SHOW_AHEAD_EN=0`、`OUTREG_EN="NOREG"`）。读 `soft_fifo_al_*.v` 第 187~197 行的 valid 生成分支：

```
if (SHOW_AHEAD_EN && NOREG)        valid = !empty_flag;
else if (!SHOW_AHEAD_EN && OUTREG) valid = re_r2 & !empty_flag_r2;
else                               valid = re_r1 & !empty_flag_r1;  // ← 本工程走这
```

即 `valid = re 打 1 拍 & 非空打 1 拍`，dout 是同步读（re 后一拍 dout + valid 同时有效）。

后果：`re=1'b1` 直读 → valid 连续=1（FIFO 非空时）=「4/4 拍有效」；`re` 接 3/4 节奏信号 → valid 跟着变「3/4 拍有效」。这正是「data_128bit_to_96bit 解包 D 丢失」的底层机制（读侧不能直读，见 SKILL.md 的 96↔128 打包/解包条）。

## 四、背景减除「固定背景」的简化

背景是 SW4 采一次后不变的固定背景，所以「帧同步对齐」的实质是「节奏对齐」（读出的背景流跟当前帧同 3/4 节奏、同数量 172800 个 128 位），而不是「内容对齐」——读侧 re=当前帧 valid 时，读出的背景是「帧 N」还是「帧 N-1」无所谓（内容一样）。这让「读错帧」不再是要担心的问题，只需担心「节奏/数量对齐」。
