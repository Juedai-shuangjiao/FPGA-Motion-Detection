# DDR ref_clk 半速根因 + 满速花屏 + 降 800Mbps 稳定（2026-10-19 实测，换板/重调 DDR 必读）

## 一、半速根因（米联客例程的隐藏坑）

- 板上有 100MHz 差分晶振（SIT9121，引脚 K5/L5，差分对 `FPGA_DDR_100MHZ_LVDS_P/N`），是 DDR 专用 ref_clk。
- 但米联客官方例程（lab_ex1 也是）把 DDR ref_clk 接成 50M 晶振（C4，I_sys_clk），导致 DDR **整体半速**：
  - 内存 533Mbps（标称 1066Mbps）
  - usr_clk 66.667M（标称 133.3M）
- 判据：DDR IP 配置 `.params_ddr2.txt` 里 `PH1P_REF_CLK=100.0`（期望 100M），`PH1P_ACTUAL_FREQ=533.3`（期望内存频率）。
- ⚠️ 不是「usr_clk 单独半速」，是「内存 + usr_clk 都半速」（VCO 只有一半，因为 ref_clk=50M 而非 100M）。

## 二、满速 1066Mbps 会花屏

- ref_clk 改接 100M 差分晶振后，内存满速 1066Mbps + usr_clk 133.3M。
- 但花屏（所有模式都花 + 长方形黑屏从上到下滚动 = DDR 读写指针错位）。
- 根因：usr_clk 133.3M（7.5ns 周期）下，MC IP 内部 page_ctrl 路径 7.493ns，SWNS 仅 +0.007 贴边，温度/电压一波动就偶发违例。加密 IP（`alc_mc_top_all.enc.sv`）无法打拍拆路径。
- 结论：满速 1066Mbps 在这个板子上跑不稳，无法根治（除非降 usr_clk = 降内存速率）。帧同步对齐救不了它（那是数据流对齐问题，不是 DDR 时序问题）。

## 三、降 800Mbps（稳定 + 够带宽的平衡点）

- 800Mbps = 内存 CK 400MHz + usr_clk 100M（10ns 周期），带宽 12.8G。
- usr_clk 域最坏路径 7.493ns vs 10ns，裕量 2.5ns（比 0.007ns 高 350 倍），稳定。
- 带宽 12.8G 够三个整帧访问（写 1.33 + 显示读 1.33 + 背景读 1.33 ≈ 4G 有效 + 开销 ≈ 6~8G）。
- 改法（4 个文件同步改，缺一个 TD 会检测不一致）：
  - `ddr2.v`：`.tCK(1876→2500)` `.CWL(6→5)` `.CL(7→6)` `.PLL0_FBKCLK_DIV(32→24)` `.PLL1_REFCLK_FREQ(133.3→100.0)`
  - `.m_params_ddr2.txt`：tCK/CWL/CL/PLL0_FBKCLK_DIV/PLL1_REFCLK_FREQ 同上
  - `.params_ddr2.txt`：tCK/CL/CWL/PLL0_FBKCLK_DIV/PLL1_REFCLK_FREQ/PH1P_DDR_CL(6)/PH1P_ACTUAL_FREQ(400)
  - `Design.xml`：tCK/CL/CWL/PLL0_FBKCLK_DIV/PLL1_REFCLK_FREQ

## 四、接 100M 差分晶振的 RTL

- 顶层加差分对端口 `I_ddr_ref_clk_p/n`（K5/L5）。
- 例化 `PH1P_LOGIC_IBUF_DIFF` 原语（TD 模板在 `template/verilog/Device-Primitive/PH1P/I,O/ph1p_i_o.v`）：
  - `.DIFF_TERM("TRUE")` 片内 100Ω 端接（R262 未焊，用片内端接）
  - `.i_p/.i_n` 接差分对，`.o` 接单端 100M，`.interm_disable` 接 1'b0，`.o_p/.o_n` 悬空
- 引脚约束 K5/L5 配 **LVDS18**（该 DDR I/O BANK VCCIO=1.8V，报错 `Invalid IOSTANDARD/LVDS33`，只支持 LVDS18）。
- SIT9121 是 3.3V 供电的 LVDS 差分晶振，但 LVDS 是电流驱动标准（共模 1.2V、摆幅 ±350mV），电气上兼容 LVDS18 输入。
- 时序约束：`create_clock ddr_ref_clk_100m -period 10`，并加入 DDR 时钟组 `set_clock_groups`。

## 五、背景读跨时钟域漂移 → 帧同步对齐（治本）

- 背景读：DDR usr_clk 100M 域 → 跨时钟域 FIFO → 摄像头 60M 域，FIFO 相位漂移导致背景延迟周期性漂移。
- DELAY 固定拍（55/40）治标不治本（漂移导致减背景周期性错位 → 花屏闪烁，且「减小防抖 IDLE_N」也救不了漂移）。
- 根治 = 帧同步对齐：
  1. `bg_read` 检 FIFO 连续读空（空计数 >8 拍，远大于 3:4 节流的 1 拍空洞）后重新有数据 = 背景帧开始，输出 `O_bg_frame_start`，喂进解包 `I_128b_frame_start`（解包打 1 拍输出 `O_96b_frame_start` 对齐 96 位背景）。
  2. `motion_detect`：当前帧存 128 深 FIFO（数据 96bit + tlast + tuser），`I_tuser` 时记录 `frame_start_wptr`；背景帧开始时读指针重置到 `frame_start_wptr`，之后每拍 +1；减背景用读出的当前帧 vs 背景，valid 用 `cur_fifo_valid && I_bg_valid`。
  3. 读指针每帧在背景帧开始动态对齐，漂移被吸收，替代 DELAY 固定拍。
