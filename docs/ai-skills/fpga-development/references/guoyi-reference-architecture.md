# 2025 安路国一开源作品完整剖析

仓库：`https://github.com/maojinxiang/FPGA-ANLU-National-First-Prize`
本地路径：`D:\Users\user\Desktop\FPGA比赛\开源例子\FPGA-ANLU-National-First-Prize`
（WSL: `/mnt/d/Users/user/Desktop/FPGA比赛/开源例子/FPGA-ANLU-National-First-Prize`）

## 一、整体
2025 嵌入式芯片与系统设计竞赛·安路赛道·国一。三设备通过千兆 UDP 互传图/指令：
- 主板 Main（EG4S20BG256，主战场）
- 副板 Secondary（同型号，遥控器+图片源）
- PC Python 上位机（Tkinter + OpenCV）

功能：TF 卡读图、OV5640 采集、16 种 FPGA 实时图像处理、千兆 UDP 传输、HDMI 显示。
工具链：Anlogic TD 6.2。工程入口 `Main/q3q4/q4.al`（顶层 top_dual_udp）、`Secondary/prj/UDP_EXAMPLE/UDP_EXAMPLE.al`。

## 二、网络拓扑
- 主板 IP 192.168.240.1（本地 UDP 端口 0x0001）
- 副板 / PC IP 192.168.240.2（调试时别同时插，会撞 IP）
- 图片端口 6003，LED/数码管端口 1/2
- 主板↔副板：网线直连或千兆交换机；主板↔PC：PC 网卡手动设 IP

## 三、主板顶层 top_dual_udp.v 架构（最值得抄）
把「项目 A（TF/摄像头→UDP 发送）」+「项目 B（UDP→HDMI/LED 显示）」合并到一颗 FPGA，2 位拨码 + 单 SDRAM + 单协议栈分时复用。

1. **模式选择**（mode_sw_1:mode_sw_0）
   - 00 = TF卡→SDRAM→UDP 发送
   - 01 = 摄像头→SDRAM→图像处理→UDP 发送
   - 10 = UDP 接收→SDRAM→HDMI/LED 显示
   - 11 = 保留
2. **时钟**：clk_gen_rst_gen(125M UDP/TEMAC) + video_pll(SDRAM+HDMI 25M/125M) + sys_pll(SD 卡) + rx_pll(RGMII 收，对 rx_clk 移相 90°)
3. **复位架构**（精华）：POR 上电复位 → master_reset_n = POR & key1；A/B 两域复位按模式门控；模式切换用 2048 周期计数器给 SDRAM/UDP 重配置复位。
4. **共享资源 Mux 仲裁**（第 8 节）：`mode_is_udp_hdmi ? B : A` 三选一。SDRAM 写/读、UDP TX（tf/cam/loopback）都走 Mux。

## 四、三种场景数据流
- 场景1（模式01）摄像头→PC：OV5640→ov5640_dri(RGB565转888)→ov5640_delay(跨时钟)→frame_read_write(写SDRAM)→SDRAM→frame_read_write(读)→udp_cam_ctrl(处理+打包)→udp_ip_protocol_stack→TEMAC→RGMII→PC
- 场景2（模式00）TF→PC：sd_card_bmp(SPI读BMP)→SDRAM→udp_cam_ctrl_tf→UDP→PC
- 场景3（模式10）副板→主板HDMI：副板读图→UDP→主板分类器(LED/HDMI帧)→写SDRAM→app(HDMI时序)→HDMI

## 五、UDP 图像分包协议（关键字段表）
一帧 640×480 RGB888 = 921600 字节，拆 1450 包。每包 = 32 字节包头 + 636 字节数据 = 668 字节。

包头 8 个 32 位字（小端），`udp_cam_ctrl.v` 第 70 行拼接：
`{ FRAMSIZE(636), FRAMSEQ, PICSEQ, OFFSET, TOTAL(921600), HEIGHT(480), WIDTH(640), MAGIC(0xAA0055FF) }`

上位机 `struct.unpack("<8I")` 后：
| header[i] | 含义 |
|---|---|
| [0] | 魔数 0xAA0055FF |
| [1] | 宽 640 |
| [2] | 高 480 |
| [3] | 总字节 921600 |
| [4] | 数据偏移 |
| [5] | 帧号（FPGA 变量名 IMG_PICSEQ，反了） |
| [6] | 包号（FPGA 变量名 IMG_FRAMSEQ，反了） |
| [7] | 636 |

上位机按帧号+包号拼回 1450 包，缺包/2 秒超时整帧丢弃。

## 六、图像处理流水线（udp_cam_ctrl.v）
16 种效果，key4 切模式、key3 调亮度/饱和度。两级流水线：
- S1：读 SDRAM 32 位拆 R/G/B，一次性算好灰度、YUV 等所有中间量
- S2：按 img_mode case 选结果，按 byte_select_cnt 顺序 G-R-B 塞 8 位发送 FIFO

逐像素类（纯组合省面积）：原始/灰度/二值化/反相/红通道/色彩量化(高位截断)/Sepia/热力图 + 亮度(±255步进32) + 饱和度(YUV 空间 U/V 缩放)
邻域类（单独例化 sobel_process/emboss_process/morphology_process，内部行缓存 line_buffer 建 3×3 窗口）：Sobel/反相/浮雕/腐蚀/膨胀/形态学边缘

## 七、副板
key2=发 LED/数码管指令、key3=TF 读图发主板、key4=发主板模式切换指令。内部 udp_tx_arbiter 做 led/img/mode 三路发送仲裁，思路与主板同款。

## 八、给选手的结论
1. 最值得抄 = A/B 双工程 + 单 SDRAM + 单协议栈 + Mux 分时复用顶层架构。
2. UDP 协议栈 udp_ip_protocol_stack_merge.enc.v 和 TEMAC 是 `.enc.v` 加密官方 IP，源码不可见——千兆网这层站在官方 UDP 例程肩膀上，原创在图像处理/分包协议/复用仲裁/联调。
3. 换电脑报 IP 找不到：PLL/FIFO/SDRAM/行缓存 IP 都要重生成/重导。
4. 上位机第 5 页「运动检测」没实现，复用第 4 页显示逻辑。
5. 仓库带 lab_ex_4 / lab_ex_6 基础工程（SD卡/SDRAM/HDMI 官方例程级），学基础从那儿入手。
