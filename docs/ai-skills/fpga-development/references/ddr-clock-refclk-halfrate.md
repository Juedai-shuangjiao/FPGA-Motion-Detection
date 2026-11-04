# PH1P35 DDR 时钟配置与 ref_clk 半速根因（2026-10-19 实测）

> 适用：HX1P35A 板（PH1P35MDG324），排查 DDR 带宽不足 / 闪烁 / 花屏 / 想调 DDR 时钟时必读。

## 一、核心硬件事实（权威来源）

| 事实 | 来源 |
|---|---|
| 合封 DDR3 = 512Mb / 16bit / **1066Mbps**（速度上限） | DS1300 数据手册 Integrated Memory Interface |
| DDR IP 的「PHY to Controller Clock Ratio」**只支持 4:1**，即 usr_clk = 内存时钟/4 = 133.25MHz | IPUG035 DDR IP 用户手册 |
| 板上有 **100MHz 差分晶振（SIT9121，LVDS3.3V），K5=P / L5=N**，网络名 `FPGA_DDR_100MHZ_LVDS_P/N`，是 DDR ref_clk 专用时钟源 | 开发板原理图 P08 + 开发板手册 |
| DDR IP 期望 ref_clk = **100MHz**（`.params_ddr2.txt` 里 `PH1P_REF_CLK = 100.0000`） | DDR IP 配置文件 |

## 二、米联客的「半速」根因（重大，反复用）

**米联客官方例程（lab_ex1/2/3 和用户工程都这样）统一把 DDR ref_clk 接成了 50MHz 晶振（C4），没用板上的 100MHz 差分晶振（K5/L5）。**

- 顶层 `ph1p35_324_ddr_wrapper` 的 `.I_sys_clk` 接的是 `I_sys_clk`（50M C4），引脚约束里**根本没有 K5/L5**。
- DDR IP 的 PLL0 按 `FIN=100` 配置（期望 ref_clk=100M），但实际吃 50M → VCO 只有一半。
- 结果：**整个 DDR 半速跑**：

| 项目 | 半速（米联客，ref_clk=50M） | 满速（正确，ref_clk=100M） |
|---|---|---|
| 内存数据率 | 533 Mbps | 1066 Mbps |
| ddr_clk（内存 CK） | 266.667 MHz | 533.333 MHz |
| usr_clk | 66.667 MHz | 133.333 MHz |
| ctl_clk | 66.667 MHz | 133.333 MHz |
| 带宽 | 8.53 Gbit/s | 17 Gbit/s |

**判别铁律**：timing 报告 Clock Summary 里 `ddr_clk` 是 266.667MHz（半速）还是 533.333MHz（满速）、`usr_clk` 是 66.667 还是 133.333，一眼就能判断 DDR 是否半速。

**注意**：`PH1P_ACTUAL_FREQ=533.3` 是「期望内存频率」，不是「实际跑的」。实际跑多少看 timing 报告的 ddr_clk。

## 三、满速改造（ref_clk 接 100M 差分晶振）

改动 5 处（都不碰 DDR IP 内部 RTL）：

1. **顶层加差分对端口**：`input wire I_ddr_ref_clk_p/n`（K5/L5）
2. **顶层例化差分转单端原语** `PH1P_LOGIC_IBUF_DIFF`（见下），输出 `S_ddr_ref_clk`（100M 单端）
3. **DDR wrapper 的 `.I_sys_clk` 从 `I_sys_clk`(50M) 改成 `S_ddr_ref_clk`(100M)**——主 PLL 还是吃 50M C4，只有 DDR 换 100M
4. **引脚约束**：K5/L5 → `LVDS18`（⚠️ 不是 LVDS33，见下）
5. **SDC**：`create_clock -name {ddr_ref_clk_100m} -period 10.000 [get_ports {I_ddr_ref_clk_p}]` + 加入 DDR 时钟组

## 四、LVDS 差分输入原语 PH1P_LOGIC_IBUF_DIFF（对应 Xilinx 的 IBUFDS）

- **原语模板位置**：`<TD安装目录>/template/verilog/Device-Primitive/PH1P/I,O/ph1p_i_o.v`（TD 自带，官方权威，不用上网搜）
- 例化：

```verilog
PH1P_LOGIC_IBUF_DIFF #(
    .DIFF_TERM("TRUE")   // 片内 100Ω 差分端接
) u_ibuf(
    .i_p          ( I_ddr_ref_clk_p ),   // 差分 P（K5）
    .i_n          ( I_ddr_ref_clk_n ),   // 差分 N（L5）
    .interm_disable ( 1'b0            ), // 中间级使能（0=正常）
    .o            ( S_ddr_ref_clk    ),   // 单端输出（接 DDR ref_clk）
    .o_p          (                  ),   // 差分输出（不用，悬空）
    .o_n          (                  )    // 差分输出（不用，悬空）
);
```

- **⚠️ DDR I/O BANK 只支持 LVDS18，不支持 LVDS33**：报错 `Invalid attribute/value IOSTANDARD/LVDS33 ... valid values are ...LVDS18`。K5/L5 在 DDR I/O BANK，VCCIO=1.8V，只能配 LVDS18。但 SIT9121 晶振（3.3V 供电）的 LVDS 输出是电流驱动标准电平（共模 1.2V、摆幅 ±350mV），电气上完全兼容 LVDS18 输入，直接配 LVDS18 即可。
- `DIFF_TERM="TRUE"`（片内端接）用于片外端接电阻 R262（100R）未焊接的情况；焊了就 "FALSE"。

## 五、满速 1066Mbps 不稳定 → 降速 800Mbps

**1066Mbps 是合封 DDR 规格上限，跑满速 SWNS 只有 +0.007ns（贴边）→ 温度/电压一波动就偶发违例 → 全屏花屏 + 长方形黑屏从上到下滚动（DDR 读写指针错位的典型表现）。**

解法：降内存速率到 **800Mbps**（usr_clk 100M，周期 10ns，SWNS 裕量约 2.5ns），带宽 12.8G 仍够三个整帧访问（占 ~31%）。

参数改法（**4 个文件必须同步改**，否则 TD 检测不一致会重新生成覆盖）：

| 参数 | 1066Mbps | 800Mbps |
|---|---|---|
| `tCK`（ps） | 1876 | 2500 |
| `CL` | 7 | 6 |
| `CWL` | 6 | 5 |
| `PLL0_FBKCLK_DIV` | 32 | 24 |
| `PLL1_REFCLK_FREQ` | 133.3 | 100.0 |

文件：`src/hdl_source_ip/ddr2/ddr2.v`、`.params_ddr2.txt`、`.m_params_ddr2.txt`、`Design.xml`（`.params` 里还有 `PH1P_DDR_CL`、`PH1P_ACTUAL_FREQ` 两个派生值，一并改 6 / 400）。

原理：VCO = ref_clk × FBKCLK_DIV / REFCLK_DIV = 100 × 24/3 = 800MHz；内存数据率 = VCO = 800Mbps；usr_clk = VCO/8 = 100MHz。改 FBKCLK_DIV 控制 VCO，从而控制内存速率。PLL1_REFCLK_FREQ 要跟着改成 100（= DDR_SPEED/8 = 800/8）。

## 六、解包 D 丢失 bug（运动检测闪烁根因之一）

`bg_read` 的 FIFO 读侧 `re=1'b1` 直读，把「3/4 拍有效」的 128 位流读成了「4/4 拍连续」，导致 `data_128bit_to_96bit` 解包的 `S_cnt` 每拍都 +1、第 4 个 96 位（D）永远丢不出来——解包每 3 个 128 位只输出 3 个 96 位（缩水 1/4），背景和当前帧必然错位。

**修复**：读侧 re 改成「当前帧的 128 位 valid」（`S_ISP_O_tvalid`，它本身就是 3/4 拍节奏），让背景读跟当前帧同节奏、同帧，解包相位自动对齐。配套：motion_detect 减背景用 `I_bg_valid` 门控兜底。

## 七、背景读带宽账（判断会不会读空）

- 读侧（摄像头 60M，re=当前帧 valid）峰值 ≈ 45M 个 128 位/s（视频有效期间突发）
- 写侧（DDR 读，受仲裁）半速 ≈ 16.7M/s → **读空 → 白线（18 根均匀分布、上下移动）**
- 满速后写侧 ≈ 40~54M/s > 读侧 45M/s → 不读空 → 白线消
- 判据：写侧速率（受仲裁的空闲间隙）必须 > 读侧峰值 45M，否则 FIFO 读空、背景断续、白线漂移。
