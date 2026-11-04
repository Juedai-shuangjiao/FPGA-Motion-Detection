# 2026 安路赛题二（PH1P35）官方例程 lab_ex1/2/3 解析

用户参加的是**赛题二**（PH1P35 实时数字图像处理系统），不是赛题三。三个官方例程是比赛的地基，理解它们 = 理解整条「摄像头→显示」数据流。

## 例程位置与解压
- zip 在 `板子资料/HX1P35A_Contest_202606/7_lab_ex_2026_nosoft/`：`lab_ex1_mipi_hdmi_SC500_720P.zip`、`lab_ex2_edge_SC500_720P.zip`、`lab_ex3_osd_SC500_720P.zip`
- 解压到 `E:\FPGA_Code\`（各成一个顶层目录 `lab_exN_xxx/`）
- WSL 解压：python `zipfile`（Windows 中文 zip 文件名是 GBK，zipfile 按 cp437 误读，需 `name.encode('cp437').decode('gbk')` 恢复；若 name 已含中文字符则直接可用）。全盘 find 遍历 /mnt 会 60s 超时，先 `ls` 顶层目录再钻进去。

## 三例程关系（同一骨架，逐步「插模块」）
- **lab_ex1 采集直通（地基）**：SC500 → MIPI → ISP → DDR → HDMI，无算法
- **lab_ex2 边缘检测**：ISP 输出后插 `isp/edge_detect_96.v`（Sobel）+ `image_correction.v`（裁剪 256×600 窗口）
- **lab_ex3 OSD**：HDMI 前在 `hdmi_mixer.v` 里叠加（`osd_char_lib.v` 字符点阵 + `anlogic_logo_rom.v` Logo 像素 ROM）

## 数据流（lab_ex1，记牢这条主链路）
```
SC500 摄像头(MIPI 2Lane, RAW10, 1280x720@60)
→ mipi_dphy_rx（DPHY0 硬核，加密 IP，LANE_NUM=2）
→ csi_unpacket_2lane（CSI-2 协议解析：包头/长包/短包/帧起止）
→ raw10_unpacket_2lane（RAW10 位宽解包）
→ uial2axis（转 AXI-Stream：tvalid/tdata/tlast/tuser）
→ isp_top（demosaic 去马赛克 + AWB 白平衡 + BLC 黑电平）→ 输出 128bit 打包 RGB
→ video_in（写 DDR 帧缓存）
→ ph1p35_324_ddr_wrapper（片内 DDR 控制器）
→ video_out（读 DDR）
→ hdmi_mixer（时序对齐）→ hdmi_tx（TMDS 编码）→ HDMI
```
时钟域：50M 输入 → PLL 生成 100m/24m/hdmi_pixel_clk/hdmi_serial_clk；另有三路独立时钟 S_csi_rx_clk（MIPI 恢复）、S_ddr_clk、S_hdmi_pixel_clk。DDR 帧缓存的作用就是隔离摄像头侧和 HDMI 侧两个时钟域。

## 顶层与工程
- 工程文件 `td_project/camera_to_dsi_display.al`，顶层 `design_top_wrapper.v`（端口 + PLL + 十几个模块例化串联，全用 `S_xxx` wire 连接）
- 引脚约束 `user_source/constraints_source/pin.adc`：clk=C4、rst_n=R10、摄像头 I2C=K3/J3、cam_24m=L3、cam_rst=L2、按键=N2/J14、HDMI TMDS=G16/F17/H14/C17（MIPI/DDR 引脚由 IP 内部锁定，pin.adc 里看不到）
- ⚠️ 换路径打开会报找不到文件：.al 里记录原作者 C 盘绝对路径，需重新 Add Source / 重导 IP

## 关键模块速记
- `vtc/uivtc.v`：HDMI 时序控制器，参数化行/场计数器生成 hs/vs/de（顶层配 1280x720@60：H_FrameSize=1650, V_FrameSize=750）
- `uics500_cfg/uicfgcs500_720p.v`：SC500 初始化，4 状态 I2C 状态机 + uii2c；CAM_ID=0x6c，CLK_DIV=24000000/100000-1=239（100kHz I2C）
- `isp/edge_detect_96.v`（lab_ex2 核心，Sobel）：灰度化(R/4+G/2+B/4 全移位)→2 行 BRAM(line1_mem/line2_mem)形成 3×3 窗口→Gx/Gy(<<<1 实现 ×2)→|Gx|+|Gy|(不开方)→阈值比较(EDGE_TH=80)→边缘白 0xffffff/非边缘黑 0x000000
- `osd_char_lib.v` + `anlogic_logo_rom.v` + `hdmi_mixer.v`（lab_ex3）：字符 16×16 点阵 case 查找表 + Logo 像素 ROM + S_x/S_y 坐标跟踪做区域覆盖判断

## 编译时间预期
- 完整视频系统例程（MIPI+ISP+DDR+HDMI）综合+布线 **10~15 分钟，正常**（开了 6 个并行 job，峰值内存 1.3GB）；流水灯只要几秒。工程越大编译越慢。
- 判断编译是否成功：看 `log/td_*.log` 结尾 `PRJ-1410 : Run syn_1 success.` + `Run phy_1 success.` + `PRJ-1424 ... saved as best result`，以及 best_result 里 .bit 的时间戳。别只看截图。

## 赛题规则：加密 IP 可以用（比赛策略）
- 加密 IP（`.enc.v`：MIPI PHY / HDMI 编码 / DDR 控制器 / UDP 协议栈）是安路官方底层/硬核，**比赛可以用**，官方直接发 lab_ex 样例让你用。
- 依据（2026 选题指南 PDF，按物理页码=阅读器翻页）：
  - **第 8 页**：赛题二「提供参赛样例 lab_ex_1/2/3，并配有样例解析」（最硬证据）
  - **第 16 页**：赛题二正文「从 MIPI 视频流输入解码、视频数据缓存…到 HDMI 高清显示」
  - **第 35 页**：「参赛作品必须为原创」（管你的设计/算法，非禁用平台 IP）
- ⚠️ 坑：第 20 页「配套图像处理 IP 库、高速接口参考工程」是**赛题三**（RK3576）的，别误引到赛题二——用户纠正过一次。引用赛题依据前先核对章节归属/页码。
- 页脚页码和阅读器页码对不上（PH1P35 正文阅读器第 16 页、页脚印「7」），以阅读器页码为准。
- 用户原创分落在：图像处理算法、系统架构、OSD、多算法切换状态机——底层接口（MIPI/HDMI/DDR/UDP）放心用官方 IP。
