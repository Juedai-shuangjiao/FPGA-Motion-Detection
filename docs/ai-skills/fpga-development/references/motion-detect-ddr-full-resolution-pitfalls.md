# 运动检测全分辨率 DDR 背景读：踩坑全集 + 最终回退结论（2026-10-19）

目标：背景减除从「片内 ERAM 320×180」升级到「合封 DDR 全分辨率 1280×720」。
结果：折腾一整天后**回退**——全分辨率 DDR 背景读（第三个整帧访问）在这个板子上问题太多，结论是「显示帧缓存继续用 DDR，运动检测背景回退片内 ERAM」。以下是完整踩坑链，逐条都是「别再重走」的教训。

## 1. DDR ref_clk 半速（最重大的发现，板子资源审计类）

- 安路 DDR IP 期望 `ref_clk = 100MHz`（`.params_ddr2.txt` 里 `PH1P_REF_CLK = 100.0000`，范围 25~400）。
- 米联客官方例程（lab_ex1 和我们工程）顶层 `.ref_clk(I_sys_clk)` 接的是 **50M 晶振（C4）**，导致整个 DDR 半速：内存 533Mbps（标称 1066）+ usr_clk 66.667M（标称 133.3）。
- **板子上有 100MHz 差分晶振（SIT9121，引脚 K5=LVDS_P / L5=LVDS_N，网络名 FPGA_DDR_100MHZ_LVDS_P/N），是 DDR 专用时钟源，米联客没用它**（引脚约束里根本没有 K5/L5）。
- 正确满速 = DDR ref_clk 接 100M 差分晶振（经 IBUF_DIFF 转单端），内存 1066Mbps + usr_clk 133.3M，带宽 8.53G → 17G。
- 判据来源：开发板手册「内核DDR差分时钟源 100MHz」+ 原理图 SIT9121 + `.params` PH1P_REF_CLK=100 + `IPUG035 DDR IP 手册`（「PHY to Controller = 4:1」「参考时钟 create_clock -period 10」）。PH1A 与 PH1P 同代，DDR IP 结构一致。
- **改 ref_clk 的正确姿势**：`CLK0_DIV/CLK1_DIV` 别动（那是 ×4 半速的「结果」）；改「ref_clk 引脚从 50M 晶振 → 100M 差分晶振」。改 `CLK0_DIV ×4→×2` 是错的——只翻 usr_clk 不翻内存，两者速率不匹配 MC 会饿死。

## 2. 满速不稳，降 800Mbps 稳定

- ref_clk 接 100M 后 DDR 满速 1066Mbps，但 usr_clk 域 SWNS 只有 +0.007ns（贴边），全屏花屏 + 黑屏段滚动（DDR 读写偶发违例）。
- 降到 800Mbps（`PLL0_FBKCLK_DIV` 32→24、`tCK` 1876→2500、`CL` 7→6、`CWL` 6→5、`PLL1_REFCLK_FREQ` 133.3→100，四文件同步：ddr2.v / .params / .m_params / Design.xml）后 usr_clk=100M，SWNS 裕量 ~2.5ns，稳定。
- 结论：**这块合封 DDR 的稳定甜点是 800Mbps（usr_clk 100M），1066 是规格上限但贴边不稳**。带宽 12.8G 够三个整帧访问。

## 3. LVDS 差分转单端原语（PH1P_LOGIC_IBUF_DIFF）

- 安路 PH1P 差分输入原语是 `PH1P_LOGIC_IBUF_DIFF`（对应 Xilinx IBUFDS）。
- 官方模板在 TD 安装目录 `template/verilog/Device-Primitive/PH1P/I,O/ph1p_i_o.v`（这是挖原语的权威来源，比官网/CSDN 都可靠，官网 IP 手册要登录）。
- 端口：`i_p`(差分P) `i_n`(差分N) `interm_disable`(接1'b0) `o`(单端输出) `o_p/o_n`(差分输出，不用悬空)。参数 `DIFF_TERM("TRUE"/"FALSE")` 片内 100Ω 端接。
- **电平标准坑**：K5/L5 在 DDR I/O BANK（VCCIO=1.8V），只支持 `LVDS18`，不支持 `LVDS33`（报错 `Invalid attribute/value IOSTANDARD/LVDS33`，valid 值里只有 LVDS18）。SIT9121 虽 3.3V 供电，但 LVDS 是电流驱动（共模 1.2V 摆幅 ±350mV 与供电无关），电气兼容 LVDS18。
- 片外 R262（100R）未焊接 → `DIFF_TERM="TRUE"` 用片内端接。

## 4. 128↔96 打包/解包的两个 bug（花屏/白线根因）

- **D 丢失**：bg_read 读侧 FIFO `re=1'b1` 直读 → 解包收到「4/4 拍有效」而非「3/4 拍」→ 第 4 个 96 位（D）永远丢，每 3 个 128 位只输出 3 个 96 位（缩水 1/4）→ 横白线。修复：读侧 re 改 **3/4 节流**（每 4 拍读 3 拍）。
- **S_cnt 无帧复位**：打包 `data_96bit_to_128bit` 的 S_cnt 在消隐期归 0（每帧对齐），但解包 `data_128bit_to_96bit` 的 S_cnt 只在 valid 时 +1、永不归 0，上电相位随机 → 解包背景整个错乱 → 花屏。修复：解包 `if(I_128b_frame_start) S_cnt <= 0`（背景帧开始处复位，跟打包消隐归 0 对应）。
- 这两条是「真 bug」，跟帧同步对齐无关，回退时也保留。

## 5. 帧同步对齐的循环依赖死锁（两个）

用「背景帧开始」动态对齐读指针（替代固定 DELAY 拍）时，出现两个循环依赖，都表现为**上电卡死/无画面**：
1. **帧开始环**：`motion_tuser → 背景读帧开始 → 背景读 → 读出的当前帧 → motion_tuser`。
2. **读侧 re 环**：`读侧 re=motion_valid → 背景读 → 背景帧开始 → 读指针 → motion_valid`。

修复（两个都要断）：
- 背景读帧开始改用独立的 `awb_tuser` 跨时钟域（展宽 8 拍 + 打 3 拍 + 下降沿），不用 motion_tuser。
- 读侧 re 改用独立自由跑的 3/4 节流计数器，不用 motion_valid。

## 6. 三个整帧访问的仲裁竞争（闪烁 + 长方形花屏滚动）

- video_in 写 + video_out 读 + bg_read 读三个整帧访问抢单口 DDR，bg_read 见缝插针读，打乱写读节奏 → 乒乓指针周期性错位 → 「长方形花屏从上往下滚 + 闪烁」。
- 这不是带宽问题（带宽够），是「仲裁时序竞争」。「帧同步读」「空闲防抖 IDLE_N」「占空比」都无效（读的总量没变）。
- Microchip 官方「DDR AXI4 Arbiter」文档印证：多路视频帧读写必须有仲裁器（先到先服务 + 优先级），我们的「3 路 busy 互斥」是简化版、没调度器。
- 开源参考 `BrianHGinc/BrianHG-DDR3-Controller`（16 端口 + PORT_PRIORITY 优先级仲裁），但它是独立控制器，不能替换安路硬核 IP。

## 7. 降分辨率 640×360 的节奏死结

- 想降背景到 640×360（数据量 1/4 减干扰），但：解包背景是「连续流」（每拍 1 个 96 位），而 2:1 降采样后的当前帧是「稀疏流」（每 4 拍 1 个），节奏差 4 倍。
- 对齐需要 43200×96bit 的大 FIFO，片内 BRAM（2.16Mbit）放不下。降分辨率在这个「DDR 连续流 + 降采样稀疏流」的组合下是死结（旧版 ERAM 之所以没这问题，是因为 BRAM 是「按需读」，节奏天然跟降采样同步）。

## 8. 最终结论（架构决策）

- **显示帧缓存必须用 DDR**（摄像头 60M 突发 ↔ HDMI 75M 均匀，整帧缓冲跑不掉）。
- **运动检测背景读 DDR 全分辨率**：问题太多（仲裁竞争 + 节奏死结 + 帧同步复杂度），回退。
- **原样（直通模式）不该用「读出的当前帧」**——直通就该直接 `awb_O_tdata`，跟灰度/二值/边缘一样。只有「运动叠加」才需要打拍对齐 motion 标记。把「读出的当前帧」当原样数据、把 motion_tuser 当原样帧开始，都是过度设计，背景读一失败整个原样花屏（而其他算法有画面）。
- 回退稳定方案 = 运动检测用「片内 ERAM 320×180 背景减除」（下板验证过、前景 4×4 块）+ 原样直通 awb + 禁用 bg_read（I_bg_en=0）。
