# DDR 参考时钟半速根因 + LVDS 差分原语 + 解包 D 丢失 bug（2026-10-19，PH1P35 比赛板）

## 一、DDR 半速根因（重大发现）

**米联客官方例程（lab_ex1/2/3 和我们的 FPGACompetition 工程）把 DDR 控制器 ref_clk 接成了 50M 晶振（I_sys_clk=C4），而安路 DDR IP 期望 ref_clk=100MHz**。

证据链（全部在本地板子资料，不用登录官网）：
- `.params_ddr2.txt` 里 `PH1P_REF_CLK = 100.0000`（期望参考时钟 100MHz，范围 25~400）
- 顶层 `design_top_wrapper.v`：`ph1p35_324_ddr_wrapper.I_sys_clk(I_sys_clk)` 接的是 50M 晶振 C4
- `ph1p_ddrphy_pll0.v` 顶部注释 `C0 = DDR_SPEED/8 = 1066/8 = 133.25MHz`（usr_clk 设计目标）
- 原理图 `HX1P35B_FT_40P_8.pdf` 第 9 页：板上有 SIT9121 差分晶振（LVDS3.3V，100MHz），`CLKp→K5`、`CLKn→L5`，网络名 `FPGA_DDR_100MHZ_LVDS_P/N`，被米联客闲置（pin.adc 里没有 K5/L5）

### 时钟树与分频关系

```
ref_clk → PLL0(VCO = ref_clk × FBKCLK_DIV / REFCLK_DIV = ref_clk × 32/3)
           ├ clk2(ddr_clk) = VCO/CLK2_DIV = VCO/2 = 内存时钟
           └ clk0 = VCO/CLK0_DIV = VCO/(CLK2_DIV×4) = VCO/8 → PLL1 参考
                                                          → PLL1 输出 usr_clk = refclk(1:1)
```

- ref_clk=50M：VCO=533.33，ddr_clk=266.67（内存 CK，数据率 533Mbps），usr_clk=66.667
- ref_clk=100M：VCO=1066.67，ddr_clk=533（内存 CK，tCK=1876ps，数据率 1066Mbps），usr_clk=133.3 ← **正确满速**

安路 IPUG035 DDR 手册明确「PHY to Controller Clock Ratio 只支持 4:1」，即 usr_clk = 内存时钟/4 = 133.3MHz。米联客配的 66.667 是「8:1 半速」非标配置（为时序宽松）。

### ⚠️ 改 CLK0_DIV ×4→×2 是错的坑

`ph1p_ddrphy_pll0.v` 里 `localparam CLK0_DIV = CLK2_DIV*4` 改成 `*2`，只让 usr_clk 翻倍到 133.3，但内存还半速 533Mbps → usr_clk 带宽（133.3M×128bit=17G）> 内存带宽（533Mbps×16=8.53G），MC 内部数据率不匹配，会饿死。

**正确做法：改 ref_clk 50M→100M，让内存和 usr_clk 同步满速**。两者必须满足 `usr_clk×128 = 内存数据率×16`，否则速率不匹配。

### 改 ref_clk 100M 的 5 处改动

1. 顶层加差分对端口 `input wire I_ddr_ref_clk_p / I_ddr_ref_clk_n`（K5/L5）
2. 顶层例化 `PH1P_LOGIC_IBUF_DIFF` 转单端，`DIFF_TERM="TRUE"`（片外 R262 100R 未焊，用片内 100Ω 端接）
3. DDR wrapper 的 `.I_sys_clk` 从 `I_sys_clk`(50M) 改接 `S_ddr_ref_clk`(100M) —— **主 PLL 还是 50M C4 不动，只有 DDR 控制器换 100M**
4. pin.adc 加 `set_pin_assignment { I_ddr_ref_clk_p } { LOCATION = K5; IOSTANDARD = LVDS33; }`（N 端 L5 同理）
5. timing.sdc 加 `create_clock -name ddr_ref_clk_100m -period 10.000 [get_ports {I_ddr_ref_clk_p}]` 并加入 DDR 时钟组（`-group [get_clocks {ddr_ref_clk_100m .../ddr_clk .../usr_clk}]`）

改完预期：ddr_clk 266.667→533、usr_clk 66.667→133.3、带宽 8.53G→17G，三个整帧访问（写+显示读+背景读）占比 47%→23.5%。

## 二、安路 PH1P 原语（从 TD 本地模板库挖，不用登录官网）

TD 原语模板库：`<TD安装目录>/template/verilog/Device-Primitive/PH1P/`（分类 Clock / I,O / Advanced / Arithmetic / Logic,Register / RAM,ROM / Config）。本机路径 `/mnt/e/TD_6.2.1_Engineer_6.2.168.116/template/verilog/Device-Primitive/PH1P/`。**查原语写法先翻这里，官网 IP 手册要登录很麻烦**。

- **PH1P_LOGIC_IBUF_DIFF**（差分输入转单端，对应 Xilinx IBUFDS）：
  ```verilog
  PH1P_LOGIC_IBUF_DIFF #(
    .DIFF_TERM("TRUE")    // 片内 100Ω 差分端接，"TRUE"/"FALSE"
  ) u_ibuf_diff(
    .i_p(I_ddr_ref_clk_p),    // 差分 P
    .i_n(I_ddr_ref_clk_n),    // 差分 N
    .interm_disable(1'b0),    // 中间级使能，0=正常
    .o(S_ddr_ref_clk),        // 单端输出
    .o_p(),                   // 差分输出（不用，悬空）
    .o_n()                    // 差分输出（不用，悬空）
  );
  ```
- 其余原语（`PH1P_LOGIC_*` 前缀）：IBUF（单端输入）、OBUF_DIFF（差分输出）、IOBUF_DIFF（差分双向）、IOTRIBUF（三态）、ODDR、BUFG、ERAM、DPHY_MIPI_RX（MIPI 硬核）、DPHY_LVDS_TX/RX

## 三、128→96 解包 D 丢失 bug（bg_read 读侧直读）

data_96bit_to_128bit 打包是「3/4 拍有效」（4 个 96 位 = 3 个 128 位，cnt=0 空洞），data_128bit_to_96bit 解包期望「3/4 拍有效」输入。

**bg_read 读侧 FIFO 的 `re` 若接 `1'b1` 直读，把 DDR 读出的连续 128 位流当「4/4 拍有效」喂解包，S_cnt 每拍+1、第 4 个 96 位（D）永远丢不出来，背景缩水 1/4，减背景必然错位成横白线（18 根均匀分布、上下抖动）。**

修复：`re` 接当前帧的 128 位 valid（顶层 `S_ISP_O_tvalid`，本身是 data_96bit_to_128bit 的输出、3/4 拍节奏），解包相位自动对齐。配套：motion_detect 减背景用 `I_bg_valid` 门控（背景无效时不判前景）。

「闪烁」有两个独立根因：①解包 D 丢失（确定性错位，re 直读 bug）；②DDR 半速带宽不足（FIFO 读空 → 背景断续）。①靠 re=当前帧 valid 修，②靠 ref_clk 满速根治。

## 四、本地板子资料挖掘路径（HX1P35A_Contest_202606）

位置 `D:\Users\user\Desktop\FPGA比赛\板子资料\HX1P35A_Contest_202606\`（WSL `/mnt/d/...`）：
- `6_PH1P35数据手册/参考IP设计资料文档.zip`：解压有 IPUG035 DDR IP 手册（PH1A，与 PH1P 同代，含「4:1 比例」「ref_clk Diff/Single/None」）、IPUG012 Soft FIFO、APUG011 ERAM SDRAM、APUG010 Local bus SDRAM、UG921 MIPI、APUG092 HDMI、APUG013 UDP
- `6_PH1P35数据手册/DS1300_PH1P_Datasheet.pdf`：PH1P 数据手册（合封 DDR 1066Mbps、HR I/O 支持 True LVDS 输入+片内 100Ω 端接、ERAM 位宽配置 1/2/5/10/20/40）
- `6_PH1P35数据手册/DS1301_PH1P_FamilyOverview.pdf`：家族概览
- `6_PH1P35数据手册/UG1316_..._MIPI用户手册.pdf`：MIPI 手册
- `3_原理图/开发板原理图/HX1P35B_FT_40P_*.pdf`：10 页原理图（100M 差分晶振 SIT9121 在 P08 第 9 页）
- `9_康芯开发板使用手册及实验平台/新HX1P35A开发板手册-HDL版2604.pdf`：开发板手册（差分晶振说明、引脚汇总）
- `7_lab_ex_2026_nosoft/`：官方 lab_ex1/2/3 例程 zip（可解压对比 DDR 配置，确认米联客统一半速）

挖原语/寄存器/引脚时，本地 zip+PDF 用 pdftotext + unzip -l 提取文本 grep，比官网（要登录）快得多。
