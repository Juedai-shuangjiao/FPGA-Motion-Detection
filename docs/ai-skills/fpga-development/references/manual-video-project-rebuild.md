# 从 lab_ex1 手动重建视频流工程（Add Source 的正确姿势）

用户想把官方 lab_ex1（摄像头→ISP→DDR→HDMI）的视频流「手动搬」进自己的工程，理解每个文件。这里最容易翻车的不是代码，而是**文件的添加方式**。

## 视频流底座需要哪些文件

lab_ex1 的 user_source 里有约 120 个文件，但真正需要「手动添加为源文件」的只有：

- **42 个源文件**（.v/.sv）：design_top_wrapper（顶层）、video_in/out、hdmi_*、isp_top、demosaic 系列、mipi_dphy_rx 系列（含 .enc 加密）、uics500_cfg、vtc/uivtc 等。完整清单见 `E:\FPGA_Code\视频流工程文件清单.md`（或从 lab_ex1 的 camera_to_dsi_display.al 里 grep `<File Path="hdl_source/...">` 提取）。
- **8 个 IP 核**（.xml/.ipc）：PLL、w128_d512_fifo、w155_d512_fifo、blk_mem_gen_awb_delay_signal、divider、ddr2、blk_mem_gen_zhenghe、blk_mem_gen_demosaic。
- **约束**：pin.adc（引脚约束，必加）；timing.sdc（时序约束，可选，报时钟错再加）。

## 关键坑（手动搬必踩）

1. **Add Directories 递归添加整个 hdl_source 会翻车**：它会把 IP 内部实现文件（ddr2/src/rtl/ 下几十个 .v/.vh）和旧版备用文件（auto_white_balance.v、csi_unpacket.v、raw10_unpacket.v、uicfgcs500.v、pll_hdmi.v、ps_wrapper.v、video_cuttting.v 等）也加进来，TD 把它们当独立源码编译 → 报一堆语法错误（尤其 .vhd/.vh 文件）。

2. **IP 核内部实现文件不能当独立源文件，但必须留在原位**：ddr2/src/rtl/、blk_mem_gen 的 RTL/、awb/ram、awb/divider 这些是通过 IP 核 .xml 自动引用的。既不能 Add 为源文件，也不能移走（移走 .xml 引用就断，报 `xxx.v is missing!`）。

3. **正确姿势**：准备一个「干净源文件目录」（只放 42 个源文件），Add Directories 它；IP 核单独 Add Source → IP files；约束单独加。用 `comm -23` 对比「目录里所有文件」和「.al 里记录的文件」就能精确得出「多余文件」清单。

4. **移动文件别用 cp -r 到已存在的同名目录**：`cp -r a/b c/b` 当 c/b 已存在时会嵌套成 c/b/b/，导致 IP 核找不到实现文件。要么先 rm 目标，要么用 rsync 或逐个文件 mv。

5. **data_96bit_to_128bit 模块定义在 data96_128.v 文件里**（一个文件里有两个 module：data_96bit_to_128bit 和 data96_128）。isp_top 例化的是 data_96bit_to_128bit，它的定义就在 data96_128.v，所以只要添加 data96_128.v 即可。hdl_source 顶层那个单独的 data_96bit_to_128bit.v 是重复旧文件，lab_ex1 的 .al 里没有它——别误以为缺文件。

6. **加注释不破坏代码的验证法**：给官方 .v 加中文注释后，用「去掉注释 + 去掉所有空白」的纯代码 diff 跟原文件对比，只有注释/空白差异才是安全的。删调试逻辑（S_dbg_* 等 ChipWatcher 信号）前先 grep 确认哪些「悬空」（声明了但没连子模块端口，可删）、哪些连了子模块端口（如 S_hdmi_debug_status→hdmi_mixer 的 .I_debug_status，删后要接 4'd0）；删完 grep 确认残留为 0、module/endmodule 配对。diff 命令骨架：`diff <(sed -e 's/[[:space:]]*\/\/.*$//' -e 's/[[:space:]]//g' -e '/^$/d' 原文件) <(同样处理 注释版)`。

## 添加顺序（照这个走，别乱）

1. 新建工程：Family=PH1、Device=PH1P35MDG324。
2. Design files → Add Directories → 干净源文件目录（42 个）。
3. IP files → 8 个 IP 核（.xml/.ipc，Add files 逐个加）。
4. Constraint files → pin.adc。
5. 设顶层 = design_top_wrapper（Set as Top）。
6. Compile All。

## IO Constraint 为什么第一次是灰的

安路 TD 的 Tools → IO Constraint **必须完成综合的 Read Design 才能打开**（否则置灰）。所以流程被迫是：先综合一次（会报 SYN-6021「端口没约束」，但综合能过）→ IO Constraint 变亮 → 分配引脚保存 .adc → 重新 Compile All。引脚约束是编译时生效的，必须「先约束、后编译」（第一次编译报错是预期的）。

## 编译日志诊断

- 日志位置：`prj/log/td_*.log`（.log 正常、.logw 只有 warning）；布局布线细节在 `prj/xxx_Runs/phy_1/run.log`。
- `SYN-6021 CRITICAL-WARNING: N out of N logical ports has no user assigned specific location` = 引脚约束没被综合读到，端口被随机分配（对应区域报告里 Location 是 K5/U9/G16 这类随机值）。
- `BIT-8123 ERROR: Bitgen is prohibitted ... unconstrained io(s)` = 存在未约束 IO，Bitgen 拒绝生成位流。
- 验证引脚是否生效：看 `xxx_Runs/phy_1/xxx_phy.area` 的 Detailed IO Report，Location 列跟 .adc 对得上才对。

## 底线建议

IP 核（DDR/PLL/FIFO）是通过 TD 的 IpTool 生成的，不适合手动搬。真要快速得到一个能跑的工程，**直接复制整个 lab_ex1 工程改名**比手动搬 120 个文件可靠得多；「理解结构」的诉求通过读 design_top_wrapper.v / isp_top.v 的数据流照样能满足。
