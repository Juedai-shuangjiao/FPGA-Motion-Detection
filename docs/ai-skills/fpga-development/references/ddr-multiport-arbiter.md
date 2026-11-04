# 安路 PH1P35 合封 DDR：IP 配置 + 多路访问仲裁（2026-10 实战沉淀）

合封 DDR（512Mb/16bit/1066Mbps）是**单路 AXI 接口**，官方 IP 无「多路仲裁」参考（官方 lab_ex 只用一路写+一路读的显示帧缓存）。多路访问要自己写仲裁。

## 一、DDR IP 时钟配置（关键结论）

- **IPUG035 手册权威**：「PHY to Controller Clock Ratio 只支持 4:1」= `usr_clk = 内存时钟/4 = 133.3MHz`（内存 533MHz、数据率 1066Mbps）。`dfi_clk/ctrl_clk` 也是内存时钟/4。
- **米联客官方例程（lab_ex1）把 DDR 配成「半速」**：`ddr2.v` 的 `PLL0_FBKCLK_DIV=32`、`ph1p_ddrphy_pll0.v` 里 `CLK0_DIV = CLK2_DIV*4`，而板载 ref_clk 接的是 50M 晶振 C4（不是 100M 差分晶振），导致 VCO=533M、内存实际只跑 533Mbps、usr_clk 只 66.667M。注释里 `C0 = DDR_SPEED/8 = 133.25M` 暴露了「设计目标是 133.25M」，米联客是「故意半速」为了时序宽松。
- **判据**：`.params_ddr2.txt` 里 `PH1P_REF_CLK = 100.0000`（期望 ref_clk 100M）、`PH1P_ACTUAL_FREQ = 533.3`（期望内存频率）。`PLL1_REFCLK_FREQ=133.3` 注释 `REFCLK : DDR_SPEED/8`。

## 二、调满速的正确姿势：ref_clk 吃 100M 差分晶振（不是改 CLK0_DIV）

- **板载 SIT9121 100MHz LVDS 差分晶振**（引脚 K5=CLKp / L5=CLKn，网络名 `FPGA_DDR_100MHZ_LVDS_P/N`），是 DDR 专用时钟源，米联客闲置了它。
- 顶层加差分转单端原语 **`PH1P_LOGIC_IBUF_DIFF`**（对应 Xilinx IBUFDS）：
  ```verilog
  PH1P_LOGIC_IBUF_DIFF #(.DIFF_TERM("TRUE")) u_ibuf(
      .i_p(I_ddr_ref_clk_p), .i_n(I_ddr_ref_clk_n),
      .interm_disable(1'b0), .o(S_ddr_ref_clk), .o_p(), .o_n());
  ```
  - 引脚约束 `IOSTANDARD = LVDS18`（**不是 LVDS33**：K5/L5 在 DDR I/O BANK，VCCIO 1.8V，只支持 LVDS18；SIT9121 虽 3.3V 供电但 LVDS 是电流驱动标准，共模 1.2V 摆幅 ±350mV，电气兼容 LVDS18）。
  - `DIFF_TERM="TRUE"` 用片内 100Ω 端接（板载 R262 是 `100R/NC` 未焊接）。
  - 主 PLL 仍吃 50M C4，只有 DDR ref_clk 改吃 100M。SDC 加 `create_clock -period 10 -name ddr_ref_clk_100m [get_ports {I_ddr_ref_clk_p}]`，并加入 DDR 时钟组。

## 三、满速 1066 时序贴边 → 降 800Mbps 稳定

- 满速 1066（usr_clk 133.3M）下 SWNS 只有 **+0.007ns**（usr_clk 域 MC IP 内部 `alc_mc_top/page_ctrl` 路径 7.493ns vs 7.5ns 周期），下板全屏花屏+黑屏滚动=读写指针错位。**这个最坏路径在加密 MC IP 内部，无法打拍拆**。
- **降 800Mbps 是稳定解**：改 `ddr2.v` + `.params_ddr2.txt` + `.m_params_ddr2.txt` + `Design.xml` 四个文件的参数：
  - `PLL0_FBKCLK_DIV` 32→24（VCO=100×24/3=800M）、`tCK` 1876→2500ps、`CL` 7→6、`CWL` 6→5、`PLL1_REFCLK_FREQ` 133.3→100.0。
  - 结果：usr_clk 100M（10ns 周期），那条 7.493ns 路径有 2.5ns 裕量，稳定。带宽 12.8G 仍够三路访问。
- 教训：**不要只改 `ph1p_ddrphy_pll0.v` 的 `CLK0_DIV`**（×4→×2）——那会让 usr_clk 翻倍但内存还是半速，两者速率不匹配 MC 内部会饿死。满速要改 ref_clk 或 FBKCLK_DIV（内存和 usr_clk 一起翻倍）。

## 四、多路访问仲裁（闪烁的根治）

- **症状**：背景读（第三路整帧 DDR 访问）插进来后，显示帧缓存（写+读两路）闪烁/花屏/长方形错位带滚动。禁用背景读后四路算法全跑通不闪——坐实「背景读是唯一干扰源，显示两路本身稳」。
- **根因**：3 路 busy 互斥是「写优先的一行 assign + 组合逻辑互相避让」，**没有饿死超时**，低优先级路（背景读）会饿死，组合避让有竞态。
- **业界标准**（参考 ARM `CFG_STARVE_TIMEOUT_P`、Microchip DDR AXI4 Arbiter、BrianHG 16 端口控制器）：**优先级 + 饿死超时（starvation timeout）**。
- **自写仲裁器骨架**（替代 busy 互斥，各模块删避让改「请求+grant」）：
  ```verilog
  // 优先级：显示读 > 采集写 > 背景读
  // 每路等待计数器：请求且 !grant 时 +1，grant 时清零；超时强制提升到最高
  reg [7:0] rd_wait_cnt, wr_wait_cnt, bg_wait_cnt;
  // RD_TIMEOUT=50 / WR_TIMEOUT=100 / BG_TIMEOUT=200
  always @(*) begin
      grant_rd=0; grant_wr=0; grant_bg=0;
      if      (req_rd && rd_starved) grant_rd=1;
      else if (req_wr && wr_starved) grant_wr=1;
      else if (req_bg && bg_starved) grant_bg=1;
      else if (req_rd) grant_rd=1;
      else if (req_wr) grant_wr=1;
      else if (req_bg) grant_bg=1;
  end
  // 各模块：突发计数器/使能/地址递增都改成 grant 门控，删掉互相避让
  ```
- 各模块改动模板：video_out 读侧 `O_ddr_user_rd_en = S_rd_valid & ready & I_rd_grant`，`O_rd_req = S_rd_valid`；写侧同理 grant 门控写使能+写计数+写完条件。

## 五、跨时钟域背景减除的坑（帧同步对齐失败教训，已放弃）

- **解包 D 丢失 bug**：`data_128bit_to_96bit` 解包期望输入「3/4 拍有效」，但 `bg_read` FIFO 读侧 `re=1'b1` 直读把 3/4 拍读成 4/4 拍，S_cnt 每拍+1 导致第 4 个 96 位（D）永远丢不出来。修法：读侧 re 用独立 3/4 节流计数器（`re = rd_cnt!=0`，不依赖当前帧 valid，否则有循环依赖）。
- **解包 S_cnt 无帧复位**：`data_128bit_to_96bit` 的 S_cnt 上电相位随机、永不归 0，而打包模块 `data_96bit_to_128bit` 的 S_cnt 消隐期归 0，两者相位对不上→解包错乱。修法：`I_128b_frame_start` 时 S_cnt 归 0（帧开始标记喂进去）。
- **帧同步对齐（读指针动态对齐）失败教训**：用「背景帧开始」动态对齐当前帧（FIFO+读指针），引入两个循环依赖（读侧 re 依赖 motion_valid、打包帧开始依赖 motion_tuser）+ 打包相位错位（竖分割）。**用「背景帧开始」做锚点动态对齐是过度设计，最终回退到固定 DELAY 拍 + 仲裁器**。
- **降分辨率有节奏死结**：降采样后的稀疏流（每 4 拍 1 个）和 DDR 解包连续流（每拍 1 个）节奏差 4 倍，要对齐需 43200×96bit 大 FIFO，片内 ERAM 放不下。
