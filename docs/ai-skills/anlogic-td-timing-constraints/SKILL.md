---
name: anlogic-td-timing-constraints
description: 安路 TD 工程补时序约束 + 跨时钟域(CDC)违例修复。当 TD 时序报告出现负 slack（SWNS 负值）、花屏/黑屏排查、或需要给 PH1P35 等安路工程补 timing.sdc 时加载。
---

# 安路 TD 时序约束与跨时钟域修复

## 触发条件
- TD 工程 timing.sdc 为空 / 覆盖率低（<30% = 只有 IP 自带约束）
- 时序报告 SWNS 为负（时序违例）
- 花屏/黑屏、OSD 乱码，想定位时序问题

## 先分清两类违例（决定修法）
1. **跨域伪违例**：慢速配置信号从慢时钟域裸跨到快时钟域（没打拍）。特征：Budget 极小（如 0.653ns，两个非整数倍频时钟边沿最坏只差这么点）、起点终点时钟不同、Data Path Delay 只有零点几 ns。
2. **同域真违例**：同一时钟域内组合逻辑太深（大 case 表、乘法器+多级 LUT）。特征：Budget = 完整周期（如 13.333ns）、Logic Level 高（15+）、Data Path Delay 接近周期。

## 步骤

### 1. 确认约束状态
- 读工程 `.al`：有没有 `<SDC_FILE>` 标签引用 sdc（没有 = 工程根本没加载约束）
- 读 `timing.sdc`：是否空
- 官方例程参考：lab_ex3 的 `td_project/camera_to_dsi_display.sdc`（17 行完整模板）

### 2. 补时钟约束（timing.sdc，PH1P35 + 50M 晶振）
```
create_clock -name {sys_clk_50m} -period 20.000 -waveform {0.000 10.000} [get_ports {I_sys_clk}]
create_clock -name {mipi_rx_ck_pad} -period 4.167 -waveform {0.000 2.083} [get_nets {IO_rx_clk_pad_p}]
derive_clocks
rename_clock -name {pll_clk_100m} [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[0]}]
rename_clock -name {pll_clk_24m} [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[1]}]
rename_clock -name {HDMI_PIXEL_CLK} [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[4]}]
rename_clock -name {HDMI_SERIAL_CLK} [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[5]}]
rename_clock -name {MIPI_RX_BYTE_CLK} [get_clocks {u_mipi_dphy_rx_ph1p_mipiio_wrapper/u_ph1p_mipiio_rx_wrapper/u_PH1P_LOGIC_DPHY_MIPI_RX.o_fabric_div4_8_clk}]
set_clock_groups -asynchronous \
    -group [get_clocks {mipi_rx_ck_pad MIPI_RX_BYTE_CLK}] \
    -group [get_clocks {sys_clk_50m pll_clk_100m pll_clk_24m}] \
    -group [get_clocks {HDMI_PIXEL_CLK HDMI_SERIAL_CLK}] \
    -group [get_clocks {u_ph1p35_324_ddr_wrapper/u_ddr2/ddr_clk u_ph1p35_324_ddr_wrapper/u_ddr2/usr_clk}]
```

### 3. 在 .al 加 SDC_FILE 引用（ADC_FILE 块后）
```xml
<SDC_FILE>
    <File Path="../src/constraints_source/timing.sdc">
        <FileInfo>
            <Attr Name="UsedInSyn" Val="true"/>
            <Attr Name="UsedInP&R" Val="true"/>
            <Attr Name="BelongTo" Val="constraint_1"/>
            <Attr Name="CompileOrder" Val="2"/>
        </FileInfo>
    </File>
</SDC_FILE>
```

### 4. 修跨域违例：打拍 + 声明异步（配套用）
- RTL 层：在快时钟域模块入口，对慢时钟域输入打两拍 `S_xx_1d <= I_xx; S_xx_2d <= S_xx_1d;`，后续逻辑一律用 `S_xx_2d`。
- 约束层：`set_clock_groups` 把两个时钟域放进不同异步组。理由：同步器第一级是「故意采样异步信号、允许亚稳态」，工具不该查它的 setup，否则报 -0.x ns 假违例。
- 关键：约束里的 set_clock_groups 分组，必须和 RTL 里的打拍同步器一一对应。

### 5. 修同域违例：打拍流水线
组合逻辑太深 → 结果寄存一拍。数据打几拍，de/vsync/hsync 也要打同样拍数对齐，否则同步信号和数据错位 → 黑屏。

## 坑
- **sdc/adc 禁中文注释**（TD 会报错，之前踩过）、禁 `//` 注释，注释用英文。
- **改 .al 前先关 TD**（TD 保存工程会覆盖手改）。
- PLL 内部层次路径带 hash（如 `25a56e5ce2f9`），从官方例程复制 sdc 时先确认本工程 PLL.xml 里的 hash 是否一致。
- `derive_clocks` 自动派生 PLL/MIPI/DDR 输出时钟，不用手写 PLL 输出频率。
- 补约束后第一次跑，会冒出之前隐藏的违例——这是正常的（工具终于能查了），逐个按「跨域 vs 同域」分类处理。
- 验证标准：覆盖率 >90%，SWNS 为正值（全绿）。
- **DDR 满速时序贴边（SWNS 正值但极小如 +0.007ns）也会下板花屏**：温度/电压波动会让它偶发变负，表现全屏花屏+黑屏滚动（DDR 读写指针错位）。若最坏路径在加密 MC IP 内部（`alc_mc_top/page_ctrl`，无法打拍拆），解法是**降内存速率**——改 DDR IP 的 `PLL0_FBKCLK_DIV`/`tCK`/`CL`/`CWL`（如 1066→800Mbps，usr_clk 133.3→100M），周期 7.5ns→10ns，同一条 7.493ns 路径裕量从 0.007 变 2.5ns。注意别只改 `ph1p_ddrphy_pll0.v` 的 `CLK0_DIV`（会让 usr_clk 与内存速率失配）。详见 `fpga-development` 的 `references/ddr-video-framebuffer-arbiter.md`。
