# 2026 安路赛道官方例程 lab_ex1/2/3 架构与数据流

用户安路赛道（选题二：实时数字图像处理系统）的核心开发原型是康芯给的三个官方例程。掌握 lab_ex1 的架构就能理解后续全部工作——lab_ex2/3 和比赛基础任务都是在同一条数据流上「加模块」。

## 官方例程位置与作用

| 例程 | zip | 对应赛题基础任务 |
|------|-----|-----------------|
| lab_ex1_mipi_hdmi_SC500_720P | 采集直通显示 | ① 视频采集与显示 |
| lab_ex2_edge_SC500_720P | 边缘检测 | ② 基础图像处理算法 |
| lab_ex3_osd_SC500_720P | OSD/Logo 叠加 | ④ OSD 叠加「安路」Logo |

都在 `板子资料/HX1P35A_Contest_202606/7_lab_ex_2026_nosoft/`。已解压 lab_ex1 到 `E:\FPGA_Code\lab_ex1_mipi_hdmi_SC500_720P\`。未压缩同款参考：`2_Example/32_cs500_mipi_hdmi`。

## lab_ex1 工程要点

- 工程入口：`lab_ex1_mipi_hdmi/td_project/camera_to_dsi_display.al`（顶层 `design_top_wrapper`，器件 PH1P35MDG324，官方自带编译好的 `.bit` 可直接下载验证）。
- 源码在 `user_source/hdl_source/`，引脚约束 `user_source/constraints_source/pin.adc`，IP 核 `user_source/ip_source/`。
- **.al 记录原作者绝对路径**（`C:/Users/Cczzzzzq/Desktop/anlogic_example_SC520CS/...`），换机器/换路径打开可能报找不到文件，需重新 Add Source / 重导 IP。

## 数据流（背下来，后续全围绕它加模块）

```
SC500CS 摄像头（MIPI 2Lane，RAW10，1280×720@60）
  → mipi_dphy_rx（官方加密 IP，DPHY0，2 lane，差分→字节流）
  → csi_unpacket_2lane（CSI-2 协议解包：包头/负载/帧起止）
  → raw10_unpacket_2lane（10bit RAW 从字节流抠出）
  → uial2axis（转 AXI-Stream：tvalid/tdata/tlast/tuser）
  → isp_top（ISP：demosaic 去马赛克 + AWB 白平衡 + BLC 黑电平）
  → video_in（写 DDR 帧缓存）
  → ph1p35_324_ddr_wrapper（片内 DDR 控制器）
  → video_out（读 DDR）
  → hdmi_mixer（时序对齐 + 生成读使能）
  → hdmi_tx（TMDS 编码）→ HDMI 显示器
```

## 时钟域

- `I_sys_clk`(C4, 50M) → PLL → `S_100m_clk`(MIPI/DDR 参考)、`S_24m_clk`(摄像头工作+I2C)、`S_hdmi_pixel_clk`、`S_hdmi_serial_clk`。
- 摄像头侧 `S_csi_rx_clk`(MIPI 恢复时钟)、`S_ddr_clk`、HDMI 侧 `S_hdmi_pixel_clk`。
- **跨时钟域靠 DDR 帧缓存隔离**（写端摄像头时钟、读端 HDMI 时钟），这是视频系统带 DDR 的根本原因。

## 为什么「先 ISP 后缓存」而不是「先缓存 RAW」（架构权衡）

用户问过「为什么不把 RAW 直接写 DDR、读取时再做 ISP」。两种架构都合法，本工程选前者：
- **先 ISP 后缓存**（本工程）：赢在简单、实时性好。demosaic 需要 3×3 邻域，在「实时流」上用行缓存（line_buffer 存前 2 行）就能流水线做；DDR 只存成品 RGB，读出来直接显示。
- **先缓存 RAW 后 ISP**：赢在省 DDR 带宽（RAW10 10位/像素 < RGB888 24位/像素，不到一半），但 demosaic 要在「从 DDR 读取」时做，得随机访问多行数据、地址计算复杂、实现麻烦。

本工程是实时显示场景，追求简单低延迟，所以选「先 ISP 后缓存」。这同时决定了算法插入点必须在 **ISP 之后（AWB 输出）、DDR 之前**——在「实时流」上做算法，别放到 DDR 之后（那要在读取时做，复杂）。教用户时遇到「为什么不换缓存顺序」这类问题，说明他在思考架构权衡而非背代码，值得顺着讲清 demosaic 邻域 + 行缓存 vs 随机访问的取舍。

## lab_ex1 关键引脚（pin.adc）

- I_sys_clk=C4、I_rst_n=R10（注意复位不是流水灯的 D5/KEY1，是 R10）。
- 摄像头 I2C：O_cam_scl=K3、IO_cam_sda=J3；O_cam_24m=L3、O_cam_rst=L2。
- 按键 I_button[1:0]=N2/J14；O_screen_pwm=R11。
- HDMI TMDS：O_tmds_ch0_p=G16、ch1_p=F17、ch2_p=H14、clk_p=C17。
- MIPI 差分和 DDR 引脚**不在 pin.adc 里**——由官方 IP 硬核锁定，无需手动约束。

## 两个值得精讲的模块（讲解文档的重点）

1. **uivtc.v**（HDMI 时序控制器）：行/场两个计数器 + 参数化时序。1280×720@60 参数：H_ActiveSize=1280、H_FrameSize=1650、H_SyncStart=1390、H_SyncEnd=1430；V=720/750/725/730。核心逻辑：`hcnt` 数像素、`vcnt` 数行、`de = hs_valid && vs_valid` 圈出有效像素区。
2. **uicfgcs500_720p.v**（摄像头 I2C 配置）：4 状态状态机（判断→发写→等busy→等完成）通过 `uii2c` 控制器把寄存器表 `uics500reg_720p60` 逐条写进 SC500。`CAM_ID=8'h6c`（I2C 地址 0x36<<1）、`CLK_DIV=239`（24MHz→100kHz SCL）。初始化完若 `I_ae_req` 再写 AE 自动曝光表。

## 如何扩展到 lab_ex2 / lab_ex3（比赛要做的）

- **lab_ex2 边缘检测**：在 ISP 输出和 video_in 之间**插入 Sobel 处理模块**（行缓存 line_buffer 生成 3×3 窗口 + Gx/Gy + |Gx|+|Gy| + 阈值）。
- **lab_ex3 OSD**：在 hdmi_mixer 附近**叠加字符点阵 ROM**（含「安路」Logo）。
- 后续进阶项（多算法切换、帧差法）也都在 ISP→video_in 或 hdmi_mixer 环节加模块。

## 三个精确插入点（用户后续动手的位置，代码级 ★）

1. **算法**（多算法切换加灰度/二值化/Sobel）：`isp_top.v` 的 AWB 之后。isp_top 数据流 = demosaic(RAW→128位RGB) → data128_96(128→96位) → awb(白平衡,96位) → data_96bit_to_128bit(96→128位) → 输出。算法 MUX 插在 awb 输出 `awb_O_tdata`（96 位 RGB）之后。
2. **OSD**（加 Logo/字符）：`hdmi_mixer.v` 的 `DEBUG_MODE==0` 那个 else 分支（`O_hdmi_data <= S_video_data_2d` 处），判断当前坐标 S_x/S_y 是否落在 Logo 区域，是则覆盖像素。
3. **按键**（调曝光/增益）：`ae_set.v` 的 `I_btn` 输入（顶层接 `{I_button, 2'b11}`），key_debounce 插在原始按键和 ae_set 之间。ae_set 按键映射 I_btn[0]=曝光减 [1]=曝光加 [2]=增益减 [3]=增益加。

## 易踩的坑（读/改 lab_ex1 源码时）

- `data_96bit_to_128bit` 模块**定义在 `data96_128.v` 文件里**（该文件有 data_96bit_to_128bit 和 data96_128 两个模块，前者 3~79 行、后者 88~100 行）。hdl_source 顶层那个单独的 `data_96bit_to_128bit.v` 是重复旧文件，lab_ex1 .al 没引用它——找模块定义别找错文件。
- lab_ex1 的 `hdmi_mixer.v` 是 148 行**简化版**（DEBUG_MODE 0=透传/1=彩条/2=调试状态/3=分块），lab_ex3 的才是 909 行含 OSD（osd_char_lib + anlogic_logo_rom）。加 Logo 以 lab_ex3 为参照。
- video_in/video_out 用 **4 个缓冲区乒乓**（IMAGE_BASE_ADDR_0~3 相隔 700 万地址），写指针 `S_video_in_wp` 和读指针 `O_video_out_rp` 错开 2 个，跨时钟域靠 `w128_d512_fifo`（写端/读端各自时钟）。video_out 里 128 位→24 位解包：128 与 24 最小公倍数 384，每 3 个 128 位 beat = 16 个 24 位像素，靠 case 切位 + 跨 beat 拼接。
- 顶层里有大量 `S_dbg_*` 调试信号（记录「某环节是否见过数据」，供 ChipWatcher 抓波形定位数据流断点），功能上可整体忽略，别被带偏。

## 加密 IP（.enc.v，源码不可见，官方提供直接用）

- MIPI：`mipi_dphy_rx/*.enc.v/.enc.sv`（byte_aligner、channel_aligner、hs_detect、ph1p_mipiio 等）。
- HDMI 编码：`hdmi_1_4b_transmitter_core_wrapper.enc.v`。
- DDR 控制器内部：`ph1p35_ddr/ddr2/src/rtl/mc/alc_mc_top_all.enc.sv`。
用户原创重点在顶层串联、图像处理算法、OSD 叠加这些有源码的部分。
