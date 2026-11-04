# DDR 合封内存 ref_clk 半速 + 差分输入原语（2026-10-19 挖到根因）

## 一、根因：米联客例程把 DDR ref_clk 接成 50M，100M 差分晶振被闲置

PH1P35MDG324 板子原理图（`板子资料/HX1P35A_Contest_202606/3_原理图/开发板原理图/HX1P35B_FT_40P_8.pdf` 第9页）上有 **SIT9121 差分晶振（100MHz，LVDS3.3V）**，差分对网络名 `FPGA_DDR_100MHZ_LVDS_P/N`，接 FPGA 引脚 **K5（P）/ L5（N）**。这是 DDR ref_clk 的专用时钟源。

但米联客官方例程（lab_ex1/2/3）统一把 DDR ref_clk 接成 `.refclk(I_sys_clk)`（**50M 单端晶振 C4**），引脚约束里根本没有 K5/L5。DDR IP 配置文件 `.params_ddr2.txt` 里 `PH1P_REF_CLK=100.0000`（期望 100M）、`PH1P_REFCLK_TYPE=NONE`（单端从 GCLK 输入）。

## 二、半速判据（算清楚，别被「usr_clk 半速」误导成「内存满速」）

DDR PHY 的 PLL0：`VCO = ref_clk × FBKCLK_DIV / REFCLK_DIV`。

- ref_clk=50M 时：`VCO = 50×32/3 = 533.33MHz`，`clk2(ddr_clk) = VCO/CLK2_DIV = 533.33/2 = 266.67MHz` = **内存 CK 半速**，`clk0 = VCO/8 = 66.667MHz` = **usr_clk 半速**。
- ref_clk=100M 时：`VCO = 1066.67MHz`，`clk2 = 533.33MHz` = 内存 CK 满速（tCK=1876ps=533MHz），`clk0 = 133.3MHz` = usr_clk 满速。

结论：**内存实际 533Mbps（标称 1066）+ usr_clk 66.667（标称 133.3），两者都半速**，带宽 8.53G（标称 17G，DS1300 合封 DDR Speed=1066Mbps 是标称）。早期文档「内存 1066 满速、只 usr_clk 半速」是误判。

## 三、调满速的正确 / 错误方法

- ❌ **错误：改 `ph1p_ddrphy_pll0.v` 的 `CLK0_DIV = CLK2_DIV*4` → `*2`**。这只让 usr_clk 翻倍到 133.3，内存还是半速 533Mbps，usr_clk×128bit(17G) > 内存×16bit(8.53G)，速率不匹配，MC 内部「用户接口灌得比内存存得快」直接饿死。**铁律：usr_clk × 128bit 必须 = 内存数据率 × 16bit，即 usr_clk = 内存 CK / 4，两者必须同步满速或同步半速。**
- ✅ **正确：改 DDR wrapper 的 `I_sys_clk` 从 `I_sys_clk`(50M C4) 改成 100M 差分晶振转单端**。VCO 翻倍到 1066.67，内存 1066Mbps + usr_clk 133.3 同时满速。主 PLL 仍用 50M C4 不动（DDR wrapper 的 `.ref_clk` 和 `.apb_pclk` 独立改，主 PLL 的 `.refclk` 别动）。

## 四、IPUG035 DDR IP 手册关键结论

本地 `板子资料/HX1P35A_Contest_202606/6_PH1P35数据手册/参考IP设计资料文档.zip` 解压有 `IPUG035_安路PH1A系列FPGA DDR IP用户手册.pdf`（PH1A 系列，但 PH1P 同架构）：

1. **「PHY to Controller Clock Ratio 只支持 4:1」** = usr_clk = 存储器时钟 / 4 = 133.25MHz。这是官方标准，所以 DDR MC IP 本来就按 usr_clk=133.25 设计，改满速时序能过。之前实测 usr_clk 域 Fmax 90.868MHz 是「半速约束（15ns 周期）下工具懒得优化」的假象——那条最坏路径 net 延迟占 71%，收紧约束到 7.5ns 后工具会重新优化布局。
2. ref_clk 支持 **Diff / Single / None** 三种 Clock Type（参考时钟在 AC Bank 时选 Diff/Single，否则 None）。
3. PLL0 文件顶注释 `C0=C1=DDR_SPEED/8=133.25、C2=DDR_SPEED/2=533`，直接暴露设计意图就是 usr_clk=133.25。

## 五、安路 PH1P 差分输入原语 = PH1P_LOGIC_IBUF_DIFF

对应 Xilinx IBUFDS。模板（TD 原语库 `template/verilog/Device-Primitive/PH1P/I,O/ph1p_i_o.v`）：

```verilog
PH1P_LOGIC_IBUF_DIFF #(
  .DIFF_TERM    ( "TRUE"     )  // "FALSE"/"TRUE"，片内 100Ω 差分端接
) u_ddr_ref_clk_ibuf (
  .i_p          ( I_ddr_ref_clk_p ), // 差分 P 端（K5）
  .i_n          ( I_ddr_ref_clk_n ), // 差分 N 端（L5）
  .interm_disable ( 1'b0         ), // 中间级使能，1'b0=正常
  .o            ( S_ddr_ref_clk  ), // 单端输出（接 DDR wrapper I_sys_clk）
  .o_p          ( ),                 // 差分输出，不用悬空
  .o_n          ( )                  // 差分输出，不用悬空
);
```

- 引脚约束：K5/L5 → `IOSTANDARD = LVDS33`（DS1300：HR I/O 支持 True LVDS 输入 + 片内 100Ω 端接电阻；LVDS33 只支持输入）。
- SDC：`create_clock -period 10 -name ddr_ref_clk_100m [get_ports {I_ddr_ref_clk_p}]`。
- DIFF_TERM 取值看片外端接：原理图 N 端串 R262=100R/NC（NC 可能未焊），DS1300 明确支持片内 100Ω 端接，**默认 DIFF_TERM="TRUE" 最保险**（不管片外焊没焊）。

## 六、找安路原语/文档不用联网、不用登录官网

- **原语模板**：TD 安装目录 `/mnt/e/TD_6.2.1_Engineer_6.2.168.116/template/verilog/Device-Primitive/PH1P/` 下按功能分类：`I,O/ph1p_i_o.v`（全部 IO 原语：IBUF/OBUF/IBUF_DIFF/OBUF_DIFF/IOBUF_DIFF/IOTRIBUF 等）、`Clock/`、`RAM,ROM/`、`Logic,Register/`、`Arithmetic/`、`Advanced/`、`Config/`。grep 目录找原语名最快。
- **IP 手册**：本地 `板子资料/.../6_PH1P35数据手册/参考IP设计资料文档.zip` 里有 IPUG035(DDR)/IPUG012(Soft FIFO)/APUG011(ERAM SDRAM)/UG921(MIPI) 等；`DS1300_PH1P_Datasheet.pdf` 是器件数据手册（含 LVDS 电学特性、合封 DDR 规格）。
- **官网**（需登录，登不进就翻本地）：IP 页 `https://www.anlogic.com/support/ip`（「存储器」分类下有 DDR 手册），资料页 `https://www.anlogic.com/support/tools-downloads`（PH1P 数据手册）。开通权限发邮件 web@anlogic.com / 电话 0755-23907781。

## 七、解包 D 丢失 bug（bg_read 读侧 re=1'b1 直读）

运动检测 DDR 改造里，横白线「均匀分布、上下移动」的确定性根源之一：

- `data_128bit_to_96bit` 解包期望输入「**3/4 拍有效**」（128 位流有空洞，cnt=2 时缓存第 4 个 96 位 D、下一空洞拍输出）。
- 但 bg_read 读侧 FIFO `re=1'b1` 直读，把 128 位流读成「4/4 拍连续」，解包 `S_cnt` 每拍 +1，**D 永远丢不出来** → 背景每 3 个 128 位只输出 3 个 96 位（缩水 1/4）→ 背景和当前帧必然错位。
- **修法**：读侧 `re = 当前帧 128 位 valid`（顶层 `S_ISP_O_tvalid`，data_96bit_to_128bit 的输出本身就是 3/4 拍节奏），背景读跟当前帧同节奏、解包相位自动对齐。同时 motion_detect 减背景加 `I_bg_valid &&` 门控（背景无效不判前景）。
- 这个 bug 跟「地址跨 bank」「占空比/防抖」无关（那些只能降闪烁频率不能根治），是「读侧节奏」的确定性 bug。
