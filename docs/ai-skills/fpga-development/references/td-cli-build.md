## TD 命令行编译（td_commands_prompt.exe，无需 GUI）

适用：B 工程（只有 .al，走 .prj 的命令行流程）。GUI 编译与命令行编译互不兼容的坑多，命令行脚本一次固化后直接复用。

### 固化脚本
B 工程脚本：`Runs/syn_1/bv4_full.tcl`（66 行核心命令序列，从 B v3 成功日志 RUN-1002 行重建）。A 工程照同样方法重建。

### 从成功日志重建命令序列的方法（无现成脚本时）
python 正则 `RUN-1002 : start command "((?:[^"\\]|\\.)*)"` 提取全部命令 → 按原文去重保序 → 跳过 save_best_bits/start_timer/end_timer 和所有 set_pin_assignment/set_ippin_assignment/set_ipinst_assignment（这些是 read_adc/read_ip_adc 的日志展开输出，不是真实 tcl 命令，重建时混进去必报错）→ 其余命令末尾分号剥掉 → import_device/open_project 放最前，phy 段第一条 open_project -noanalyze 前插入 `cd ../phy_1` → 末尾 puts "BUILD_DONE" + exit。

### 编译命令（后台跑，约 38 分钟）
```
cd /mnt/e/FPGA_Code/FPGACompetition_B/prj/FPGACompetition_Runs/syn_1
cmd.exe /c "E:/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe E:/FPGA_Code/FPGACompetition_B/prj/FPGACompetition_Runs/syn_1/bv4_full.tcl"
```
注意：Windows 路径必须用正斜杠（反斜杠在 WSL bash → cmd 转义链里会被吞掉，报 couldn't read file）。tcl 参数直接传路径，不用 -f。

### 脚本核心命令（顺序勿改）
syn 段：import_device ph1_35p.db -package PH1P35MDG324 -speed 3 → open_project FPGACompetition.prj → commit_param -step design → elaborate -top design_top_wrapper → read_adc pin.adc → read_ip_adc -ip ddr2 → read_sdc ×3 → export_db elaborate → commit_param rtl → insert_debugger → optimize_rtl → commit_param gate → optimize_gate -packarea → update_pll_param → report_* → export_db gate
phy 段（先 `cd ../phy_1`）：open_project -noanalyze → import_db ../syn_1/FPGACompetition_gate.db → commit_param place → config_chipwatcher → compile_watcher → import_db -mode ooc ×2 → pack -eco → place → commit_param route → route → export_db pr → fix_hold → update_timing final → commit_param bitgen → bitgen -bit FPGACompetition.bit → export_bid

### 四个致命坑（都实踩过）
1. **GUI 打开/保存工程会清掉 ddr2 引用** → 编译报 `ddr2 is a black box in .../ph1p35_324_ddr_wrapper.v(78)`。GUI 读的是 prj/FPGACompetition.al（工程文件），命令行读 Runs/syn_1 与 Runs/phy_1 两份 .prj——**三处都要 grep 确认有 `hdl_source_ip/ddr2/ddr2.xml` 条目**（照 A 工程格式：UsedInSyn/P&R true、BelongTo design_1；.al 里路径是 `../src/` 相对 prj/，.prj 里是 `../../../src/` 相对 Runs 目录）。CompileOrder 对照 A 工程：ddr2=45、PLL=46（B 工程现状 PLL 撞号 45 时把 PLL 改 46）。补回后 GUI 打开直接跑编译、**不要点保存**（保存会再次清掉）。**GUI 打开工程还会在会话内重算 PLL**：报 `ERROR: VCO '2400.0000MHz' is out of range [800.0000MHz, 2000.0000MHz]` 而命令行编译同工程不报 = PLL 源文件没坏（Design.xml VCO=1500 合法），是 GUI 会话内存里算出的非法组合——PLL 向导重新生成/Apply 即可，别去改源文件
2. **tcl 命令含 `;` 会被解释器当命令分隔符截断** → invalid command / Invalid format 报错。核心命令序列本身不含分号；所有 set_pin_assignment/set_ippin_assignment/set_ipinst_assignment 是 read_adc/read_ip_adc 的自动展开输出，**不要**手写进 tcl（写了必报 USR-8053 或 invalid command，试过裸写/大括号/双引号全失败）。
3. **launch_runs/reset_runs 在 td_commands_prompt 里不生效**（reset_run 直接 invalid command；launch_runs 打印 launched 但 run.exe 不真正跑，还建出嵌套空目录 Runs/syn_1/FPGACompetition_Runs/）。必须手写命令序列。
4. 日志判定：完成标志是 tcl 里的 puts "BV4_FULL_DONE"（自定义）；真编译判据 = bit 文件时间戳刷新 + 日志尾部 Timing final SWNS/HWNS 数值 + Flow Statistics 总时长。

### 副本工程盲修编译（cp -r 双线并行时）
`cp -r FPGACompetition_B FPGACompetition_B2` 后直接在副本目录跑同一份 bv4_full.tcl 即可：tcl 内命令全用相对路径（open_project FPGACompetition.prj），无需 sed 改路径；但副本的 .prj/.al 是复制时刻的快照，若源工程刚补过 ddr2 引用要先确认副本里也有（实测 cp -r 在补丁前启动时副本缺 ddr2，把源工程 prj/.al cp 过去覆盖即可）。副本目录的 git 历史随复制带走（自带 .git），在副本里继续 commit 正常。**cp -r 大目录（含 prj 中间产物数百 MB）超时被杀后目标目录是半成品**：再次 `cp -r 源 目标` 时目标已存在，cp 会把源整体复制到 目标/源 下（嵌套、结构损坏，`目标/src/hdl_source_clean` 不存在）。修复 = `mv 目标 _trash_半成品` + 重新 cp（用后台任务 + notify，别用前台超时）；多份副本复制用循环串行 cp，每份都验证 `目标/src/hdl_source_clean` 存在。

### 重编译清缓存前必须备份当前 bit
重编译前清缓存（rm syn_1/*.bit *.db 结束标记）会删掉当前可下板的 bit——如果用户还想先下板看现有效果（或当前 bit 是刚验收过的版本），删了就无副本可恢复（best_result/phy_1 里残留的旧 bit 时间戳更早、可能是无新功能的基线版，下它没意义）。规则：清缓存前先 `cp syn_1/*.bit /tmp/或工程外备份` 并告诉用户已备份；用户说「先下载看看」时先查 bit 是否还在，不在就老实说明被删了，别让用户带着旧 bit 下板白折腾。

### 与 GUI 的冲突
GUI 打开着 .al 工程时命令行编译 .prj 可以并行跑（B v3 就这么干的）；但 GUI 随后「保存工程」会覆盖 .prj 丢 ddr2 引用。编译后 GUI 打开 ChipWatcher 会报「Current flow is out of date」→ 点 yes 变 read only → 解法：把 bit 复制成 cw/compiled.bit 与 .cwc/.data 同目录，离线打开 ChipWatcher 选 compiled.cwc。

### GUI 编译时序报告分阶段判读（别把中间报告当最终违例）
用户报「GUI 编译有时序违例」时先查阶段：综合阶段的 gate.timing 出现负 SWNS（如 -1.49ns）是**中间报告**，P&R 会收敛（实测综合后 -1.49ns → P&R 后 SWNS -11ps 近似绿）；最终时序看本流程自己写的报告——**GUI 流程 = phy_1/FPGACompetition_pr.timing，命令行流程 = syn_1/FPGACompetition_pr.timing（命令行不写 phy_1，那里只有 GUI 遗留的旧文件，时间戳滞后别误读）**。命令行编译同样有中间 SWNS 为负的阶段（-962ps → 最终 +115ps）。GUI 与命令行是同一编译器、结果等价，最终差异约 ±100ps 来自布线 seed/迭代策略，不是流程优劣。**删调试内核（MARK_DEBUG 信号）后布线压力减小，GUI 编译也转全绿**：同一工程带调试 hub 时 GUI -11ps、全删 MARK_DEBUG 后 GUI +100ps 零违例——收官版清理调试信号时顺带把时序缺口一起解决。用户视命令行编译为「邪修」、称「GUI 编译才是正道」时给此口径：邪的不是编译方式，是盲猜参数——参数来自实测插值时走哪条路都是正道。

### patch 工具改 .prj/.al 后必须 sed 验证实际结构
patch 对 .prj/.al 这类 XML 的模糊匹配会让返回的 diff 显示与实际插入位置不一致（显示像插进上一个 File 块的 FileInfo 中间、把结构拆坏了，sed -n 打印实际文件却是结构完好的）——被 diff 误导重做会二次改坏文件。规则：patch 工程 XML 后立刻 sed -n 打印插入点上下文验证真实结构，以实际文件为准，不按 diff 显示判断。

### 两工程目录对齐移植（A 工程改造成 B2 状态）
把一个工程的当前设计移植进另一个工程目录（文件集可能不完全同步）时：先 `comm -13 <(find 源 -name '*.v' | sed 替换前缀 | sort) <(find 目标 ... | sort)` 对比文件集——文件集完全相同（146 个 .v 无增删）时移植 = `cp -r 源/src/* 目标/src/` 内容覆盖 + 确认目标 .al/.prj 的 ddr2 引用 + git status 核对差异文件清单（实测差异集中在 3-4 个文件时覆盖即完成）。文件集有增删时才需要改 .prj 的文件列表。