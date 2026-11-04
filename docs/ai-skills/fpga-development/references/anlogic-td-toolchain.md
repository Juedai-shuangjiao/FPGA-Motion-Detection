# 安路 Anlogic TD 工具链速查

安路 FPGA 开发工具叫 **TD**（Tang Dynasty），国一作品用 TD 6.2。工程概念与 Vivado/Quartus 不同，别套错。

## 文件后缀对照
| 后缀 | 含义 |
|---|---|
| `.al` | 工程文件（TD 主入口，双击打开） |
| `.qws` | 工作区文件 |
| `.qdf` | assignment 默认值 |
| `.v` / `.vhd` | 源码（Verilog / VHDL） |
| `.enc.v` / `.enc.vhd` | **加密 IP 核，源码不可见**（官方提供，如 UDP 协议栈、TEMAC、HDMI TMDS 编码器） |
| `.qip` | IP 核引用清单（一个 IP 生成会带 .qip + .v 壳 + 若干中间文件） |
| `.sdc` | 时序约束 |
| `.adc` | 反标文件 |
| `.bit` | 下载位流（在 Runs/best_result 或 phy_1/cw 下） |
| `.prj` / `.tcl` | 综合/布局布线脚本（Runs/syn_1、Runs/phy_1） |

## 典型工程目录结构
```
工程/
├─ xxx.al            # 入口
├─ src/              # 手写源码
├─ import/           # 导入的 .v + IP 核
├─ al_ip/            # IP 核（TEMAC_CORE 等）
├─ Runs/
│  ├─ syn_1/         # 综合结果
│  └─ phy_1/         # 布局布线 + 位流（best_result/xxx.bit）
├─ log/              # TD 运行日志（.log 正常 / .logw 警告）
└─ out/              # 输出（back_annotation.adc 等）
```

## TD 向导「New Project」新建的工程（目录布局和开源项目不同）
TD 菜单 Project → New Project 新建的工程，布局是教程要求的 4 文件夹，和上面开源项目的 `Runs/` 在根目录不同：
```
工程/
├─ doc/                  # 文档（空）
├─ prj/                  # ★ 项目主体全在这
│  ├─ xxx.al             # 工程文件（双击打开 TD 工程）
│  ├─ xxx.adc            # 引脚约束（Tools→IO Constraint 保存生成）
│  ├─ xxx_Runs/          # 编译运行结果（目录名带工程名前缀 xxx_Runs）
│  │  ├─ syn_1/          # 综合中间文件
│  │  ├─ phy_1/          # 布局布线中间文件
│  │  └─ best_result/    # ★ 最终 .bit 在这
│  ├─ log/               # 编译日志 td_YYYY-MM-DD_*.log
│  └─ work/              # ModelSim 工作库
├─ sim/                  # 仿真 testbench（run_led_tb.v）
└─ src/                  # 手写源码（xxx.v）
```
- 下板选位流：`prj/xxx_Runs/best_result/xxx.bit`（Tools→Download 里 Add 这个）。
- 打开工程：双击 `prj/xxx.al`。
- 搜用户工程时注意：`.al`/`.bit` 都在 `prj/` 里，别只在工程根目录找；Windows 挂载 /mnt 全盘 find 遍历会 60s 超时，直接 `ls -dt /mnt/d/.../Desktop/*/` 看顶层目录，或先猜 E 盘 `FPGA_Code` 这类自建目录再钻进去。

## 康芯教程文档的坑（用户「照文档做」时）
康芯《安路软件使用完整流程》等 PDF 教程（在 `板子资料/HX1P35A_Contest_202606/8_FPGA学习资料/`）：
- **截图芯片对不上**：教程下板界面截图显示 `eagle s20 BG256`（易灵思 EG4S20 板），不是 PH1P35MDG324。所以教程「分配引脚」图29 里填的具体引脚号是 eagle_s20 板子的，**PH1P35 用户不能照抄**，要查 `9_康芯开发板使用手册及实验平台/HX1P35B开发板引脚分配汇总.docx`（或 references/hx1p35a-board-pins.md）。
- **教程确实有「分配引脚」这一节**（在「仿真验证」之后，Tools→IO Constraint），用户常做到仿真波形对了就停、漏掉这节，然后 Bitgen 报 BIT-8123。用户说「教程里没写引脚约束」时，提醒他往下翻到这一节，别以为真没有。

## 换电脑打开的坑
打开 `.al` 常报「找不到 IP 核 / .v 文件」，原因：
1. 工程里记的是原作者机器的绝对路径。
2. PLL / FIFO / SDRAM / 行缓存等 IP 是本地生成的，换环境要重生成。

处理：优先在 `import/`、`src/`、`al_ip/`、README 指明的目录找；用 TD 的 `Add Source` / `Add Existing File` 重导；IP 重新生成（PLL/FIFO/SDRAM/line buffer）。

## 手动重建 lab_ex 视频流工程（Add Directories 的坑）
lab_ex1（摄像头→HDMI）视频流底座，源文件**不是整个 hdl_source 目录**，而是精选的 42 个 .v/.sv + 8 个 IP 核 + pin.adc。手动重建时最大的坑：

1. **Add Directories 会递归添加整个目录**，把不该加的文件也加进来，导致一堆语法错误：
   - **IP 内部实现文件**（ddr2/src/rtl/ 那几十个 .v/.vh、demosaic 的 blk_mem_gen、awb 的 ram/divider，含 .vhd）——它们由 IP 核 .xml 自动引用，**不能当独立源文件**，加进来会被当 Verilog 编译报错（尤其 .vhd/.vh）。
   - **旧版备用文件**（auto_white_balance.v、csi_unpacket.v、raw10_unpacket.v、uicfgcs500.v、pll_hdmi.v、ps_wrapper.v、video_cuttting.v、raw8_to_rgb888.v、mipi_rx_error_detect.v、data_96bit_to_128bit.v、isp/BLC/BLC.v、isp/awb/awb.v、uial2axis/uial2axis.v、uiisp_beta 下的旧版）——废弃不用，不能加。

2. **正确做法**：准备一个「干净文件夹」只放那 42 个源文件（保持目录结构），Add Directories 这个干净目录；IP 核单独用 Add Source → IP files 加；约束单独加。这样 Add Directories 才不会混进 IP 内部实现和旧版文件。

3. **文件清单**（42 源文件 + 8 IP 核 + pin.adc + 添加顺序）已存档在用户目录 `E:\FPGA_Code\视频流工程文件清单.md`。8 个 IP 核 = PLL、w128_d512_fifo、w155_d512_fifo、blk_mem_gen_awb_delay_signal、divider、ddr2、blk_mem_gen_zhenghe、blk_mem_gen_demosaic。

4. **别用 cp -r 移动/移回目录**：手动整理目录时，`cp -r src dst` 当 dst 已存在会嵌套错位（变成 dst/src/...），导致 IP 核引用断裂、报一堆「xxx.v is missing!」。要重建干净，直接从 lab_ex1 重新 `cp -r` 覆盖，别来回挪。

5. **IP 核不适合手动搬**：DDR/PLL/FIFO 是通过 TD 的 IpTool 生成的，内部实现文件靠 .xml 相对路径引用。用户坚持「手动搬理解结构」时，正确姿势是「源文件用干净文件夹 Add Directories + IP 核单独 Add IP files」，而不是把 IP 内部文件也当源文件搬。

## 常见器件
- EG4S20BG256：安路 HX4S20C 板主控（国一那套），20K 逻辑单元，256 引脚。
- 安路 Eagle 系列：EG4（低端）、PH1（中端，用户 PH1P35 图像处理用）。
- **PH1P35MDG324**：用户 HX1P35A 板主控（图像处理赛道）。PH1 系列，160 用户 IO，21216 LUT（TD 器件库口径；选型手册写 38189 是等效逻辑单元口径），6 PLL，40 DSP，硬核 **MCU(RISC-V) + MIPI DPHY×2**，片内 512Mb 内存。PH1P35 家族还有 MBG484(291 IO 无内存)、MEG324(197 IO 无内存)、MHG324(1Gb 内存) 等尾缀，选器件时要对板子手册核对尾缀（尾缀决定 IO 数/是否带片内内存）。

## 建工程芯片选择
- Device Family 选 **PH1**（TD 器件库里 family 名就是 ph1，对应 arch/ph1_35p.db 等）。
- Device Name 选 **PH1P35MDG324**（板子手册 `新HX1P35A开发板手册-HDL版2604.pdf` 原文「安路 PH1P 系列 PH1P35MDG324」）。
- TD 自带的 board_designs 里只有米联客 AP102/104/106（都是 PH1A 系列），没有 HX1P35A 板卡模板，手动建工程选器件即可，别指望一键选到 HX1P35A。

## 烧录 / 下载
TD 生成 `.bit` 后用 TD 自带 downloader（或 JTAG）下载。注意位流在 `Runs/phy_1/cw/compiled.bit` 或 `Runs/best_result/xxx.bit`。PH1P35 用 TD 自带 **hwserver.exe**（bin/ 下）烧录。

### 核对 bit 的引脚是否真编译进去（排查「下载成功但功能不对」的第一步）
编译产物里 `Runs/phy_1/xxx_phy.area`（或 best_result 同名）有真实引脚分配表，列：`Name Direction Location IOStandard IOType DriveStrength PullType`。直接看 Location 列和 .adc 是否一致。用户报「下载成功但灯不流水/功能不对」时，**先看这个文件确认引脚对不对**，别急着怀疑代码——本例流水灯就是引脚全对（clk=C4 rst_n=D5 led[3:0]=D6/C6/E10/D10）、代码也对、时序也满足，问题根本不在 bit。

### 下载报 success 但程序不跑（偶发，重新下载即可）
JTAG 下载报 `Downloading succeeded!` 只代表「数据发完 + 校验过」，不保证 FPGA 配置「干净落地并启动」。慢速下载（如 `-spd 7` 花 274 秒）时传输时间长，USB 抖动/供电波动易让配置在最后启动环节掉链子 → FPGA 没跑程序，引脚停默认高电平，高电平点亮的 LED 就「全亮」。**现象特征：灯全亮 + 复位键无反应 + 重新下载一次就正常**。处理：再下载一次；频繁偶发就把下载速度档调高（缩短传输时间）。这是 FPGA JTAG 下载的常见一次性偶发失败，不是代码/引脚/驱动问题。

### 「程序在跑 vs 没跑」一句话验证：按住复位键看灯
复位值通常写单热码（如流水灯 `led<=4'b1000`）。按住复位键（rst_n 低有效）时：
- 灯变成「只有 1 个亮」→ 程序在跑，之前「全亮」是流水太快（视觉暂留）。
- 灯还是「全亮不动」→ 复位没起作用，程序没跑（FPGA 未配置，引脚默认高电平）。
辅助判断：手机摄像头拍灯，屏幕里在闪=太快全亮（代码在跑）；稳定不闪=真全亮（没跑）。

### JTAG 下载是临时的（掉电丢失）
`-mode jtag` 下载到 SRAM，掉电就丢，重新上电 FPGA 会读 Flash 里的出厂程序（用户看到「断电重开跑别的程序」是正常的，不是故障）。想永久留存要选 `PROGRAM_FLASH` 模式固化到 Flash，固化后需断电重启才生效。

## 引脚约束（关键坑：不分配引脚 Bitgen 直接失败）
**⚠️ IO Constraint 界面在第一次综合前是灰色的、点不了**——这是 TD 的正常设计：它必须先「综合」（Syn Opt 的 Read Design）把代码读进去、识别出顶层端口，IO Constraint 才能列出端口让你分配引脚。所以新手建工程的正确顺序是：① 加源文件 → ② 先综合一次（会报 SYN-6021「端口没约束」但综合能过，忽略）→ ③ 综合完 IO Constraint 变亮 → ④ 分配引脚保存 .adc → ⑤ 重新 Compile All。**别指望「先约束后编译」，第一次编译前约束界面必然是灰的。** 流程：
1. 菜单 **Tools → IO Constraint**，给每个顶层端口填 Location（引脚号，查板子引脚分配表/原理图）。
2. 保存，起名（如 run_led），路径默认，弹窗选 Yes → 生成 `.adc` 约束文件（Constraints 栏可见）。
3. **分配完引脚后要重新编译一次**，再走 Bitgen → 生成 `.bit` → Tools → Download。

常见报错（Console 里看到它们 = 没做引脚约束）：
- `BIT-8123: Bitgen is prohibitted as there is(are) unconstrained io(s)` ← 致命，拒绝生成位流。
- `SYN-6021: N out of N logical ports has no user assigned specific location` ← 所有端口都没约束，软件只好随机塞引脚（随机值不是板子真实引脚，下板必错）。
- `PHY-5060: Clock net candidate xxx has mixed fanouts` ← 计数器分频时钟被当时钟用的固有警告，低速流水灯可忽略。

**「.adc 加入了但综合没读到」的排查**：现象是 .adc 文件内容对、也进了工程（.al 里有 ADC_FILE、UsedInSyn=true），但综合日志仍报 SYN-6021（端口无用户约束）+ 最后 BIT-8123。确认方法：看 `Runs/phy_1/xxx_phy.area` 的 **Detailed IO Report** 表，对比 Location 列是否等于 .adc 里设的引脚——若被随机塞成别的（实测：clk 设 C4 实际 K5、rst_n 设 D5 实际 G16、key_in 设 A9 实际 U9、led 设 D10 实际 D11），就是综合阶段没读到 .adc。处理：重新 Tools→IO Constraint 分配引脚 → 保存（弹窗选 Yes）→ 关掉分配界面 → 重新 Compile All。

## TD 软件安装目录结构（帮用户"看看都装了啥"时用）
TD 6.2 安装根目录下关键子目录：
- `bin/`：`td.exe` 主程序、`hwserver.exe`(PH1P35 烧录)、`td_commands_prompt.exe`(TCL 命令行)、`IpTool.exe`(IP 生成)、`bw.exe`(BitWizard)、`design_integrator.exe`、`mpack.exe`(模块打包)、`hpfTool.exe`、`alps.exe`、`svf2aje.exe`。
- `arch/`：器件库 `.db` 文件（`ph1_35p.db`、`eagle_*.db`、`ef2/ef3/ef4_*.db`、`dr1/sf1/sf2_*.db`）+ `device_resource/device_resource.csv`（全器件资源表，列：Family,Device,User IOs,LUTs,DFFs,DSPs,PLLs,ERAMs,DRAMs,Serdes Lanes,PCIE,Hard Cores...）。判断某芯片是否支持、查资源参数就 grep 这个 csv。
- `ip/`：IP 核库（`mipi_io`、`serdes`、`ddr`、`pcie`、`xgmac`(千兆网)、`uart`、`cordic`、`fft`、`fir`、`soft_fifo`、`psram_controller`、`cm3_cpu`、`risc_v_32`、`high_speed_io`、`hxt` 等）。PH1P35 图像采集靠 `mipi_io`（MIPI DPHY 硬核）。
- `doc/`：官方一手文档——`TD_User_Guide_V6.2.pdf` 总手册、`IPUG*`(IP 核指南)、`SWUG*`(软件指南)、`UG1310_PH1P_Libraries_Guide`(PH1P 器件原语)。用户偏好官方一手文档，优先指这里的。
- `board_designs/`：预置板卡模板（仅米联客 AP102/104/106，PH1A 系列）。
- `driver/`：下载器驱动 al-link / dl-cable（win7/win10 x64/x86）。
- `license/Anlogic.lic`：许可文件，NODELOCKED 但 `HOST_ID = ANY`（任意机器可用），看有效期字段。

## 从 PDF/docx 提取文档和代码（WSL 无 vision 工具时的替代）
用户常发 PDF 教程/截图让读。没有 vision_analyze 时用命令行 OCR：
- **PDF 里的代码截图**（位图，pdftotext 提不出文字）：`pdfimages -png x.pdf /tmp/out/img` 提取全部图片，再 `tesseract img-NNN.png stdout` OCR。代码是英文，tesseract 默认 eng 即可；中文注释识别差但代码主体（module/always/posedge/引脚号）够用。用 `grep -iE "module|always|posedge"` 批量定位含代码的图。
- **PDF 正文文字**：`pdftotext x.pdf -` 直接出文本（矢量文字能提，图片里的字提不出）。
- **docx 表格**（WSL 无 pandoc/unzip，python 无 python-docx）：用标准库 `zipfile` 读 `word/document.xml`，`re.findall(r'<w:t[^>]*>([^<]*)</w:t>', xml)` 按顺序提取单元格文本，再去重/配对。别用 `w:tr`/`w:tc` 正则（会匹配到嵌套的 `w:tcPr` 里的 `<w:t>`，输出爆炸）。

详见 `references/verilog-common-errors.md`（Verilog 入门/仿真常见错误清单）和 `references/hx1p35a-board-pins.md`（HX1P35A 板完整引脚表）。
