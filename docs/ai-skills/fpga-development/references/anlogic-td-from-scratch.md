# 安路 TD 从零建工程 + 手动搬视频流进自建工程

用户想「不靠官方例程，自己一步步搭工程」时用这套。核心是 Add Source 分类型加文件、设顶层、以及把官方例程（lab_ex1）的视频流底座手动搬进自己的工程。

## 一、从零建工程（New Project）
1. File → New Project，工程名随便起（与模块名无关），路径建议统一放 `E:\FPGA_Code\<工程名>\`。
2. 器件：Family=PH1、Device=PH1P35MDG324（选错后面全白搭）。
3. 生成 doc/prj/sim/src 四文件夹；源码放 src\，testbench 放 sim\，.al/.adc 在 prj\。

## 二、Add Source 的四个分类（别选错）
| 选项 | 放什么 | 例子 |
|---|---|---|
| Design files | Verilog/VHDL/SystemVerilog 源码 | key_debounce.v、top.v、*.sv |
| Constraint files | 引脚/时序约束 | pin.adc、timing.sdc |
| IP files | IP 核 | PLL.xml、ddr2.xml、*.ipc |
| Package files | 打包模块 | 少用 |

- 加单个文件选 **Add files**；批量加整个目录选 **Add Directories**（递归加子目录，.v 和 .sv 会一起进来）。
- Add files 弹窗里两个勾选框（「头文件全局包含」「复制到项目」）**普通模块都不用勾**。

## 三、设顶层（Set as Top）
- 源文件在工程里**天生平级**（key_debounce、top、design_top_wrapper 都一样高），没有优先级之分。谁是顶层只靠「右键 → Set as Top」指定，不是靠文件顺序。
- 一个工程只能有一个顶层；多个「没被例化的模块」并存没问题，只有被 Set as Top 的那个会被综合。

## 四、手动搬 lab_ex1 视频流进自建工程（5 步）
目标：把官方例程的「摄像头→ISP→DDR→HDMI」视频流底座搬进自己的工程，再在上面加自己的算法。视频流底层（MIPI DPHY / DDR 控制器 / HDMI 编码）是官方加密 IP（.enc.v/.enc.sv，源码看不到），只能搬文件、不能自己写——理解接口和数据流即可，不是能力问题。

1. 复制 `lab_ex1_mipi_hdmi_SC500_720P\lab_ex1_mipi_hdmi\user_source\` 下的 hdl_source、ip_source、constraints_source 到自建工程的 src\ 下。
2. 加 .v/.sv：Add Source → Design files → Add Directories → 选 `src\hdl_source`（约 91 个 .v + 4 个 .sv 一起进）。
3. 加 IP 核：Add Source → IP files，逐个加这 9 个：
   - `ip_source\PLL\PLL.xml`（时钟）
   - `ip_source\w128_d512_fifo\w128_d512_fifo.xml`、`w155_d512_fifo\...`、`w40_d512_fifo\...`（缓存 FIFO）
   - `ip_source\blk_mem_gen_awb_delay_signal\...xml`（存储块）
   - `ip_source\divider\divider.ipc`（除法器）
   - `hdl_source\ph1p35_ddr\ddr2\ddr2.xml`（DDR 控制器，在 hdl_source 里！）
   - `hdl_source\isp\demosaic_4x_2_0\blk_mem_gen_zhenghe\...xml`、`blk_mem_gen_demosaic\...xml`（去马赛克存储块）
4. 加约束：Add Source → Constraint files → pin.adc + timing.sdc。
5. 设顶层：Set as Top → design_top_wrapper（自己的按键 LED top.v 先不设顶层，后面再合并进视频流）。

## 五、关键坑
- **刚加完 .v 就一堆「找不到模块」错误是正常的**：.v 例化了 PLL/FIFO/DDR/MIPI 这些，它们的定义文件（IP 核 / .sv）还没加进来。等文件加全（尤其 IP 核）错误自动消失，别慌。
- **搬视频流是个大工程**（148 个文件 + 9 个 IP 核 + 约束 + 顶层切换），容易在 IP 核这一步出错。若用户只想「跑通视频流 + 加自己的算法」，更省事的是直接复制整个 lab_ex1 工程改名、再往 isp_top 插算法——但用户明确要「手动搬、一步步理解」时，就按上面 5 步耐心带，别劝。
- 顶层模块名必须和 TOP_MODULE 一致；综合日志若报 `HDL-5007 could not find top-level module` 但后面又 elaborate 成功、syn_1 success，那这个警告是早期误导，真正问题看 phy_1 阶段（BIT-8123 = 引脚没约束，见 anlogic-td-toolchain.md）。
