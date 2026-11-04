# DDR 满速改造（ref_clk 100M）与降速 800Mbps —— PH1P35 合封 DDR 实战

> 适用：PH1P35MDG324 合封 DDR3（512Mb/16bit/1066Mbps），运动检测 DDR 存背景遇带宽/花屏问题时。
> 结论日期：2026-10-19。核心发现：**米联客官方例程把 DDR ref_clk 接成 50M 晶振，导致整个 DDR 半速跑**。

---

## 一、DDR 半速根因（最关键发现）

- 米联客官方例程（lab_ex1 和主工程 FPGACompetition 都是）把 DDR 的 `ref_clk` 接成 **50M 晶振（I_sys_clk，引脚 C4）**。
- 板上另有 **100M 差分晶振（SIT9121，LVDS3.3V）**，原理图网络名 `FPGA_DDR_100MHZ_LVDS_P/N`，引脚 **K5=P、L5=N**，被闲置（引脚约束里根本没有 K5/L5）。
- **判据**：`src/hdl_source_ip/ddr2/.params_ddr2.txt` 里 `PH1P_REF_CLK : 100.0000`（DDR IP 期望参考时钟 100M，范围 25~400），但顶层 `ph1p35_324_ddr_wrapper .I_sys_clk(I_sys_clk)` 接的是 50M。
- **结果**：VCO = ref_clk×FBKCLK_DIV/REFCLK_DIV = 50×32/3 = 533.33MHz（期望 100×32/3 = 1066.67）。于是**整个 DDR 半速**：
  - 内存数据率 533Mbps（标称 1066，DS1300 写 MDG324=1066Mbps）
  - ddr_clk（内存 CK）= 266.667MHz（标称 533）
  - usr_clk = 66.667MHz（标称 133.3）
- 之前只看到 usr_clk=66.667 就误判「usr_clk 半速」，实际是「内存和 usr_clk 都半速」。
- 半速带宽 = 8.53 Gbit/s，三个整帧访问（video_in 写 1.33 + video_out 读 1.33 + bg_read 读 1.33 ≈ 4G）+ 开销 ≈ 6~8G，顶到边界，背景读抢不过 → 读空 → 白线。

## 二、IPUG035 官方关键事实（本地挖到的权威文档）

本地 `板子资料/HX1P35A_Contest_202606/6_PH1P35数据手册/参考IP设计资料文档.zip` 里有：
- `IPUG035_安路PH1A系列FPGA DDR IP用户手册.pdf`（PH1A 和 PH1P 同代，DDR IP 结构一致，可直接参考）
- `IPUG012_Soft_FIFO用户手册_v3.0.pdf`、`APUG011_基于ERAM接口实现的高性能SDRAM读写v1.2.pdf`、`UG921 MIPI DPHY-RX`、`APUG092 HDMI1.4b`、`APUG013 UDP`。

IPUG035 关键结论：
- **「PHY to Controller Clock Ratio 只支持 4:1」**，即 usr_clk = 存储器时钟/4。内存 533MHz → usr_clk = **133.25MHz 是官方标准**。
- 参考时钟支持 Diff/Single/None 三种，`create_clock -period 10`（=100MHz），推荐从 DDR AC Bank 的 HPIO 输入。
- 注释 `REFCLK : DDR_SPEED/8 = 1066/8 = 133.3` 印证 PLL1 设计目标 refclk=133.3M。

## 三、满速方案（ref_clk 100M，5 处改动）

1. 顶层加差分对端口 `I_ddr_ref_clk_p / I_ddr_ref_clk_n`。
2. 顶层例化 **`PH1P_LOGIC_IBUF_DIFF`**（差分转单端，对应 Xilinx IBUFDS）：
   ```verilog
   PH1P_LOGIC_IBUF_DIFF #(.DIFF_TERM("TRUE")) u_ddr_ref_clk_ibuf(
       .i_p(I_ddr_ref_clk_p), .i_n(I_ddr_ref_clk_n),
       .interm_disable(1'b0), .o(S_ddr_ref_clk), .o_p(), .o_n());
   ```
   端口：i_p/i_n/interm_disable/o/o_p/o_n。DIFF_TERM=TRUE 用片内 100Ω 端接（片外 R262 未焊时）。
3. DDR wrapper 的 `.I_sys_clk` 从 `I_sys_clk`(50M) 改成 `S_ddr_ref_clk`(100M)。主 PLL 仍用 50M 晶振，不动。
4. 引脚约束：K5/L5 → **`IOSTANDARD = LVDS18`**（不是 LVDS33！）。
5. SDC：`create_clock -name ddr_ref_clk_100m -period 10.000 [get_ports {I_ddr_ref_clk_p}]`，并加入 DDR 时钟组（跟 usr_clk/ddr_clk 同组）。

**原语位置**：TD 安装目录 `template/verilog/Device-Primitive/PH1P/I,O/ph1p_i_o.v`，差分输入原语叫 `PH1P_LOGIC_IBUF_DIFF`（不是 IBUFDS）。差分输出是 `PH1P_LOGIC_OBUF_DIFF`。

**LVDS33 vs LVDS18 坑**：K5/L5 在 DDR I/O BANK（VCCIO=1.8V），只支持 LVDS18 等 1.8V 及以下的差分标准（报错列出可选值 DIFF_HSTL18_I / DIFF_SSTL18_I / LVDS18……，没有 LVDS33）。差分晶振虽然 3.3V 供电，但 LVDS 是电流驱动标准（共模 1.2V、摆幅 ±350mV，跟供电无关），电气上兼容 LVDS18 输入。

## 四、满速 1066 花屏 → 降速 800Mbps

- **满速 1066Mbps 花屏根因**：SWNS 只有 +0.007ns（贴边），usr_clk 域最坏路径 7.493ns（在加密的 MC IP 内部 `alc_mc_top/page_ctrl`，R-Period 7.493ns vs 周期 7.5ns）。温度/电压波动 → 偶发违例 → DDR 读写错位 → 全屏花屏 + 长方形黑屏从上往下滚动。**加密 IP 无法打拍拆路径，满速贴边治不了**。
- **降速 800Mbps**：usr_clk 100M（10ns 周期），那条 7.493ns 路径裕量变成 2.5ns，稳定。
- **降速参数（4 个文件同步改，漏一个都不行）**：

| 参数 | 1066Mbps 旧值 | 800Mbps 新值 |
|---|---|---|
| tCK | 1876 ps | 2500 ps |
| CL | 7 | 6 |
| CWL | 6 | 5 |
| PLL0_FBKCLK_DIV | 32 | 24 |
| PLL1_REFCLK_FREQ | 133.3 | 100.0 |

  文件：`ddr2.v`、`.params_ddr2.txt`、`.m_params_ddr2.txt`、`Design.xml`。`.params` 里还有派生值 `PH1P_DDR_CL`（7→6）、`PH1P_ACTUAL_FREQ`（533.3→400）同步改。
- 带宽账：800Mbps = 12.8 Gbit/s，三个整帧访问占 ~31%，够用。VCO = 100×24/3 = 800MHz，ddr_clk=400MHz（内存 CK），usr_clk=100MHz（4:1）。

## 五、帧同步对齐（跨时钟域漂移，背景减除花屏）

- **现象**：背景减除（运动检测）花屏闪烁，DELAY 固定拍（motion_detect 的 localparam DELAY）怎么调都治标——因为背景数据从 DDR usr_clk（100M 域）跨到摄像头 60M 域，FIFO 相位持续漂移，固定拍跟不住。
- **根治**（动态对齐，替代固定 DELAY 拍）：
  1. `bg_read.v` 检测「背景帧开始」：FIFO 连续读空（valid 连续 0 > 8 拍，远大于 3:4 节流的 1 拍空洞）后重新 valid=1 的上升沿，输出 `O_bg_frame_start`，喂进解包的 `I_128b_frame_start`（原来接 1'b0）。
  2. `motion_detect.v` 用「当前帧 FIFO（深度 128）+ 背景帧开始动态对齐」：当前帧每拍写 FIFO（数据+tlast+tuser），`I_tuser` 时记录 `frame_start_wptr`，背景帧开始时 `cur_rptr <= frame_start_wptr` 把读指针拨到当前帧帧开始位置，之后每拍读，读出的当前帧就跟背景严格同帧对齐。
- 关键信号链：bg_read `O_bg_frame_start` → 顶层 `S_bg_frame_start` → isp_top `I_bg_frame_start` → motion_detect `I_bg_frame_start`。

## 六、其他坑（本次踩过）

- **读侧 re=1'b1 直读导致解包 D 丢失**：bg_read 的 FIFO 读侧 re 要接「当前帧 128 位 valid」（S_ISP_O_tvalid，3/4 拍节奏），不能直读——否则 data_128bit_to_96bit 收到 4/4 拍连续、S_cnt 每拍+1、第 4 个 96 位（D）永远丢不出来，背景缩水 1/4 必然错位（横白线 18 根均匀分布）。
- **背景缓冲区地址**：原 28000000 跨 bank 切换开销大，改到紧挨乒乓第 3 块之后 22382400（=21000000+1382400），独立不重叠 + bank 切换最少。
- **减小防抖 IDLE_N 180→40**：让写侧读速率（占空比 25%→60%）跟上读侧 45M 峰值，FIFO 不读空，水位稳定，减小漂移。
