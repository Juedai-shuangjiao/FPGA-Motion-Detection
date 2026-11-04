# TD 命令行编译（WSL 自动化，省掉盯 GUI 等半小时）

安路 TD 编译（综合+布局布线+位流）可完全脱离 GUI，用命令行跑。在 WSL 里通过 `cmd.exe /c` 调 TD 的 `td_commands_prompt.exe` 即可，编译放后台跑、完成自动通知，用户只需最后去 TD 点「下载」。

## 核心命令

```bash
cd <工程>/prj/<工程名>_Runs/phy_1 && \
cmd.exe /c "E:/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe E:/TD_6.2.1_Engineer_6.2.168.116/doc/scripts/DefaultFlow.tcl"
```

- **路径必须用正斜杠**（`E:/TD_.../DefaultFlow.tcl`）。反斜杠会被 bash 和 cmd.exe 双重转义吃掉，报 `couldn't read file "E:TD_...docscriptsDefaultFlow.tcl"`。
- 后台跑：terminal `background=true` + `notify_on_complete=true`，编译完自动通知（大工程 30 分钟，小工程如流水灯 20 秒）。
- 编译完成后 `td_commands_prompt.exe` 停在 `td >` 交互模式，但 stdin 是管道、读不到输入就自动退出，无需手动 kill。
- 也可用 `cmd.exe /c "E:/TD_.../bin/td_commands_prompt.exe -help"` 探活（会进交互模式打印版本头，`-help` 被当文件名忽略，属正常）。
- **自定义 tcl 脚本必须放 Windows 可见路径传 Windows 路径**：`td_commands_prompt.exe E:/FPGA_Code/xx.tcl` 可以，传 `/tmp/xx.tcl` 会报 `couldn't read file`（cmd.exe 下 /tmp 解析成 UNC \\wsl.localhost 路径，CMD 不支持 UNC 且 TD 读不到）。脚本里写 `help` 可列出全量 tcl 命令（约百条），help 输出是确认「某功能有没有命令行入口」的最快途径。
- 命令清单事实：help 列出 `download`（-bit/-spd/-cable/-host_name，命令行下 bit 的入口）、`eram_operate`（-bit/-bin 操作 bit 文件里的 ERAM 初始化数据，**不是读板上 RAM**）、`debug_mode`、`read_phy_data/write_phy_data`、`JTAG_REG_ACCESS` 等硬件命令；**没有 ChipWatcher 触发/抓波形/导出的任何命令**——片上波形抓取 GUI-only，别在命令行里找。
- **编译等待用 notify_on_complete 等通知，别 sleep 轮询日志（用户质疑过「你一直 sleep 570 是在干什么」）**：后台编译启动时就挂 notify_on_complete=true，完成自动进通知；sleep 轮询既浪费后台进程又被 420s 工具上限截断，进度被用户问到时即查即报即可。

## 编译流程与 settings.cfg

`DefaultFlow.tcl` 步骤链：`read_design → opt_rtl → opt_gate → opt_place → opt_route → bitgen`。

`prj/<工程>_Runs/<run>/settings.cfg` 关键字段：
- `set start_step opt_place` —— 从布局布线开始（跳过综合）
- `set end_step bitgen` —— 到位流生成
- `set parent ../syn_1` —— 综合结果在 syn_1 目录
- `set top_model_name {<顶层模块>}` / `set device_name` / `set package_name`

**提速要点**：
- 改 **RTL（.v）** 必须从 `read_design`/综合重跑（慢，30 分钟）。
- 只改 **约束（.adc/.sdc）** 理论上有 `start_step opt_place` 只重跑布局布线的快捷路径——⚠️ **但 2026-10-23 实测：单独重跑 phy 会被静默跳过**（见下「约束修改的大坑」），改 sdc 老老实实删 syn_1 缓存全量重跑。
- 半小时耗时主要是「布局布线」（PH1P35 资源 74% LUT / 83% slice，工具要满足 800Mbps 时序），不可省。

## 产物位置

- 最终 .bit：`prj/<工程>_Runs/best_result/<工程>.bit`（下载器烧这个）
- 当次运行 .bit：`prj/<工程>_Runs/phy_1/<工程>.bit`

⚠️ **命令行编译不自动同步 best_result**：命令行跑完，.bit 只在 `phy_1/` 目录刷新，`best_result/` 里还是旧的（TD GUI 编译才会自动 copy）。下载时认准 `phy_1/` 目录里时间戳最新的 .bit（用 `find <工程> -name "*.bit" -newermt "今天" -exec ls -la {} \;` 定位），别下载到 best_result 的旧文件。

## 两个 run 目录

- `syn_1/run.bat` → 综合（`run_type syn`）
- `phy_1/run.bat` → 布局布线 + 位流（`run_type phy`，`parent ../syn_1`）

完整编译 = 先 syn_1 后 phy_1；只重跑布局布线 = 只跑 phy_1（综合结果已在 syn_1）。

## IP 参数修改的大坑（2026-10-23 实测，DDR REF_CLK 排查）

**TD 增量编译不监视 IP 参数文件**：`.params_ddr2.txt` / `.m_params_ddr2.txt` / `Design.xml` 都不在 .al 文件列表里，改这些文件后编译会静默复用旧综合结果（.bit 时间戳不变），参数修改根本不进编译。

**删缓存强制全量重编的做法**：`rm -f syn_1/*.db syn_1/*.area syn_1/*.timing syn_1/*.ts phy_1/*.db phy_1/*.bit phy_1/final_timing.rpt`，再从 syn_1 跑 DefaultFlow。注意：全量 syn 跑完**不会自动衔接 phy**（phy_1 的 db 被删后流程停住），需再单独 `cd phy_1` 跑一次 DefaultFlow——它会检测 syn db 已新、跳过 syn 直接 place/route（但 place 会变慢，全量布局 ~15 分钟）。

**PLL 的 M 倍频系数固化在 TD GUI 生成 IP 时写入的实例缓存里**：命令行改参数文本 + 删 db 全量重编**都刷新不了 M**（实测全量重编后 clk1 仍 133.333）。刷新 M 唯一途径是 GUI 走 IpTool 重新生成 IP。工程里 wrapper/src/rtl 下的 PLL .v 只是参数壳（REFCLK_DIV/FBKCLK_DIV/CLK0_DIV），M 不写在这些文件里。

**DDR REF_CLK 有三层参数文件，一层都不能漏**：`.params_ddr2.txt`（PH1P_REF_CLK）、`.m_params_ddr2.txt`（PLL0_REFCLK_FREQ）、`Design.xml`（PLL0_REFCLK_FREQ，**最常漏**）。REF_CLK 配 50 而板子实际 100M 差分 → PLL M=64 → usr_clk 133.33M = 2 倍超频（DDR 实跑 2133Mbps vs 标称 1066）；REF_CLK=100 → M=32 → usr_clk 66.67M（官方）。usr_clk 查 `phy_1/final_timing.rpt` 的 `clk1:` 行。

**IpTool 重新生成的坑**：TD 6.2 双击已生成 IP 报「无法识别文件 depot//Component.xml」（启动参数传丢，bug）；`bin/IpTool.exe` 是命令行工具直接退出；IpTool 向导的 IO 规划类参数（ADC File Path、PLL Location、RefClk Location）**不存 Design.xml**，重新打开向导全是默认值，与工程对不上会一路校验报错（adc 不存在、DQS 引脚无效）。

**验证「文件一致但 clk 不同」的实验设计**：增量编译（旧缓存）的 clk1 是缓存回显、不可信；必须删缓存全量重编对照。文件级用 `find . -type f | xargs md5sum | diff` 对比，比 diff -rq 更严（能看出参数文件改后的格式微差）。

## 约束修改的大坑：改 sdc 后只重跑 phy 会被静默跳过（2026-10-23 实测）

- **现象**：改 `timing.sdc` 后只删 `phy_1/*.db` 重跑 phy 的 DefaultFlow——进程跑满 14 分钟正常退出，但**没有新 td_*.log、bit 时间戳不变、SWNS 不变**（还是改动前的值）。
- **机制**：phy 阶段从 syn 产物的**约束快照**继承 sdc，不重新读源文件；且 TD 增量判定「syn 产物没变 → phy 已最新」直接复用旧 phy 结果，静默跳过。
- **判别（下板/看结果前先查，避免拿旧 bit 白下板）**：重跑后 `ls -la phy_1/td_*.log` 看有没有新 log 文件、`stat phy_1/*.bit` 看时间戳有没有更新——两样都没变 = 被跳过。
- **正确做法**：改 sdc 必须删 `syn_1` + `phy_1` 全部缓存全量重跑（syn 阶段把新 sdc 读进约束快照）。全量重跑后还要在 log 里确认新 sdc 命令文本出现了（`grep set_clock_groups phy_1/td_*.log` 显示的是新版文本才算数）。

## 新增源文件的三重登记坑（2026-10-24 实测，black box 根因）

**命令行编译读 run 目录里的 `.prj` 工程快照，不读 `.al`**：DefaultFlow.tcl 里是 `open_project FPGACompetition.prj -noanalyze`——`.prj`（在 `syn_1/`、`phy_1/` 各一份，TD GUI 编译时从 `.al` 同步生成）里有一份完整的 `<Source_Files>` 列表。**只把新文件 Add Source 进 `.al` 不够，命令行编译看不到 → 综合报 `HDL-8007 ERROR: xxx is a black box`**（新文件没进编译列表），syn 不产出 gate.db，phy 连锁报 `Cannot open file ../syn_1/FPGACompetition_gate.db`。

正确做法：新 .v 文件要**同时登记三处**——① `.al` 的 `<Verilog>` 段；② `syn_1/FPGACompetition.prj`；③ `phy_1/FPGACompetition.prj`（注意 .prj 里路径是 `../../../src/...`，比 .al 的 `../src/...` 多两层）。

另外两点：
- **CompileOrder 编号 .al 和 .prj 体系不一致**（同一文件两边号不同、且有重复号先例——重复不致命），新文件在各自文件里取「当前最大号+1」即可，别跨文件对号。
- **DefaultFlow 的 ERROR 不中断流程**：elaborate 报 ERROR 后流程继续跑完、exit code 还是 0（假成功）——后台跑完不能只看退出码，必须 grep 日志确认无 ERROR、gate.db/bit 已生成。**判别新增 ERROR 是否真失败**：先 grep 同一工程上一版编译日志，同一条 ERROR 旧编译也有且当时下板正常则可能是老毛病；black box、`Cannot open file *.db` 类 ERROR 才是真失败。
- **SYN-8411（VCO out of range）不是无害噪音，是「参数没生效」的红旗**：`SYN-8411 VCO '2400MHz' out of range [800, 2000]` = 参数文本要求 PLL VCO 超出 FPGA 上限 → PLL 回退 → 实际内存速率/时钟与声明错配 → 时序约束约束到错误时钟（SWNS 假绿）+ 校准赌运气。看到它意味着「文本参数（如 1600 超频组）从未生效，实际跑 IP 固化值（如 800Mbps）」，正确动作 = 回归官方验证参数组 + GUI Regenerate IP，而不是当背景噪音忽略；若决定保持现状继续开发，必须按「实际频率口径」重算所有带宽/时序预算。

**启用「备用文件」必须清 AutoExcluded 标记（2026-10-24 实测）**：项目里「备用不编译」的文件（如 uics500reg_1080p30.v）在 .al/.prj 里的 FileInfo 段带 `<Attr Name="AutoExcluded" Val="true"/>`，TD 会把条目保留但**排除在编译之外**。一旦 RTL 开始例化它，elaborate 就报 black box（文件明明在列表里却报 black box 的最常见原因）。修复：把 AutoExcluded 改成 false（.al + 两个 run 目录的 .prj 三处都要改），删缓存重跑。**判定方法：black box 报错的文件若在 .prj 列表里，先查它的 AutoExcluded**。

## RTL 修改被静默跳过 = 假编译（2026-10-25 实测，最隐蔽的坑）

- **现象**：改 .v 源码后跑 DefaultFlow，流程正常退出、**bit 时间戳更新、时序报告正常**，但下板现象毫无变化——因为 SYN 三个步骤（read_design/opt_rtl/opt_gate）被增量判定跳过，只跑了 place/route/bitgen，bit 内容是旧网表。一晚 5 次编译全是假编译（用户直觉「编译怎么都很快」——假编译只要 ~18 分钟，全量 ~50 分钟）。
- **判定（编译后必查，别只看 bit 时间戳）**：`ls -la syn_1/.*.end.f`——`.read_design.end.f`、`.opt_rtl.end.f`、`.opt_gate.end.f` 三个标记文件时间戳没更新 = 综合没跑 = 假编译。另有 `gate.db` mtime 佐证。真编译时三个 .end.f 都会刷新。
- **验证既有工程/副本是否假编译（不重跑编译的离线判定）**：①三个 .end.f 时间戳**依次递进**（read_design 最早、opt_gate 最晚，且相互间隔几分钟 = 三步都真跑过）；②`gate.db` mtime 与 `.opt_gate.end.f` 一致；③源码最后改动时间（`ls -lt src/hdl_source_clean/*.v`）**早于** `.read_design.end.f`——若源码改动晚于标记时间，说明当前 bit 不含最新源码。三点全过 = 真编译且包含最新改动。
- **机制**：step_begin/step_end 用 `.$step.begin.f/.end.f` 标记文件做跳过判定；TD 检测不到 WSL 侧修改的 RTL mtime（或判定有缺陷），RTL 改了仍复用旧综合。
- **强制全量**：`rm -f syn_1/*.db syn_1/.*.end.f syn_1/.*.begin.f phy_1/*.db`（.end.f/.begin.f 标记文件一并删，防残留标记触发跳过判定），再跑 syn_1 的 DefaultFlow。
- **编译前删缓存是固定纪律（历史会话实践）**：每次命令行编译前统一清理 `syn_1/*.db syn_1/.*.end.f syn_1/.*.begin.f phy_1/*.db`（可连带删 phy_1/*.bit——.bit 会被 bitgen 重写，删它本身非必需，但「编译前把连带的缓存产物一起清掉」这个习惯能保证每次都是真全量、不会拿到假新 bit）。宁可每次多花 50 分钟全量，也不要 18 分钟出一个假 bit 再下板白测。
- **删 phy_1/*.bit 会与用户下载撞车（协调坑）**：清缓存后到 phy 阶段 bitgen 完成前（40~50 分钟窗口）phy_1 里没有 .bit 文件——若用户正拿着上一个 bit 准备下板，下载工具会报文件不存在，用户会当成「下载故障」来回澄清。启动重编译前先告知用户「编译期间 bit 不可用、预计 HH:MM 出新的」；若用户急着下板验证旧 bit，先等他下载完再删缓存。

## 编译前零成本自检（改完代码、启动 50 分钟编译前，几分钟做完）

用户要求「验证一下准备编译」时的标准动作，四连：
1. **grep 改动点无残留**：改动值全局唯一（如阈值 `<= 'd240` 全文只此一处、无旧值 30 残留）；位宽改动连端口/内部 reg/复位初值三处一起 grep。
2. **iverilog 语法桩检查**：`iverilog -g2005 -o /tmp/chk 桩文件.v 改动文件.v`，桩只定义被例化的 IP（FIFO 等）空壳即可；依赖的子模块（解包器等）直接编进命令行。语法错误 1 分钟就报，不用等 TD 半小时。
3. **diff 基线确认改动范围**：与同源工程（如主线 vs nogrant）diff 改动文件，确认差异只落在预期行（阈值/位宽/地址），没有顺手改到别处。
4. **查上版编译日志的拆网点/黑盒警告**：`grep -E "HDL-5373|HDL-7225|SYN-5013|SYN-5025|HDL-8007" syn_1/run.log`——上版日志若有「identifier used before declaration」类警告，先修再编译（改后必重扫全工程，见 sim-passes-board-fails.md 第 0 号根因）。
- **全量重跑的连带代价**：elaborate 真跑时会暴露 .prj 缺文件 → black box ERROR（见上节三重登记）——所以强制全量前先确认新文件已登记进两个 run 目录的 .prj。
- **GUI 对照**：TD GUI 同样有增量机制，但流程视图每步状态可见、可手动 Run All，且有 .prj 自动同步，比命令行可靠；命令行编译后核对 .end.f 时间戳是硬纪律。

## 下载（命令行入口存在但未实测）

td_commands_prompt 的 help 命令清单里有 `download` 命令（`-bit <string> -spd -cable -host_name` 等参数），是命令行下载的入口，但本环境从未实测过其可用性——默认仍走 TD GUI 的 Download 界面选 .bit + AL-LINK 下载器：SRAM（掉电丢，调试用）/ Flash（固化，比赛演示用）。

## 停后台编译的坑：只杀 td 进程不够，bash 外壳会继续跑下一阶段（2026-10-24 实测）

- **现象**：想停掉一个后台编译，`taskkill /F /IM td.exe` + `td_commands_prompt.exe` 杀掉了工具进程，但 background terminal 的 **bash 外壳还活着**——它继续执行命令串的下一段（syn 完 → `cd ../phy_1` → 又拉起一个新 td），结果「旧编译的 phy」和「新启动的编译」在**同一个工程目录并发跑**，互相污染产物/缓存。
- **正确做法**：停编译要连 bash 会话一起杀——kill 该 background terminal 会话的 bash PID（`kill -9 <pid>`，PID 可从 `ps aux | grep DefaultFlow` 或进程列表里识别），再 `tasklist` 确认 Windows 侧 td 进程清空。
- **误杀警示**：清理时若同时有两条编译在跑，taskkill /IM td.exe 会把**新编译的 td 也一起杀了**（按映像名杀不分会话）——先确认要留哪条、精确 kill 目标 bash，别用按映像名的全局 taskkill。
- **杀 bash 后 Windows 侧 td 常残留并锁文件**：kill WSL 侧外壳后 td_commands_prompt.exe 在 Windows 侧还活着（可能要十几秒才退出），且**锁住 syn_1/*.db 等产物文件**——此时删缓存会报 Permission denied。删缓存失败先 `tasklist | grep -i td` 查残留，按 PID 逐个 taskkill，锁释放后再删缓存重跑。
- **多会话并行时先认领进程再杀**：td_commands_prompt.exe 多实例中可能有其他会话的编译——用 `powershell.exe -Command "Get-CimInstance Win32_Process -Filter \"Name='td_commands_prompt.exe'\" | Select-Object ProcessId,CreationDate,CommandLine | Format-List"` 看每个实例的**创建时间 + 命令行**，与「自己启动后台编译的时刻」比对认领，只杀自己的 PID。杀完用 tasklist 确认只剩对方的实例。
- 杀完后 `ps aux | grep -E "td_commands|DefaultFlow"` 和 `tasklist /FI "IMAGENAME eq td.exe"` 双确认归零，再启动新编译。

## 并行多工程编译（内存评估先行）

用户赶进度时会要求多个工程并行编译。TD 单实例峰值内存 ~2.2GB（place/route 阶段），启动前 `free -h` 评估：机器可用内存 ≥ 并行数 × 2.5GB 才安全（8GB 机器双开可行、三开会触底）。两个后台 terminal 会话各跑各工程的 DefaultFlow（各自目录/各自缓存，互不干扰），每个工程仍各自遵守「编译前删缓存 + 编译后验 .end.f」纪律，不能因为并行就省掉。
