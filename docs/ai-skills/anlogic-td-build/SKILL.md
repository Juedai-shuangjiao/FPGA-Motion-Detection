---
name: anlogic-td-build
version: 1.0.0
author: 开发者
license: MIT
description: Use when compiling TD projects or switching GUI/CLI builds.
metadata:
  hermes:
    tags: [fpga, anlogic, td, build, gui, cli, 编译]
    related_skills: [fpga-development]
---

# 安路 TD 编译：GUI vs 命令行（PH1P35 项目实战）

## When to Use
- 用户要编译安路 TD 工程、在 GUI/命令行之间切换
- 遇到 ddr2 black box、VCO out of range、Code verification failed 等编译错误
- 需要验证编译是否真实完成

## 两者本质
同一套编译器（TD 6.2 系），只是入口不同。GUI 读 **.al**（不读 .prj），命令行 tcl 读 **.prj**。命令行适合后台长编译+日志监控，GUI 适合可视化+ChipWatcher 集成。

## 编译耗时（PH1P35 720P 工程，按资源占比分档）
- <90% 资源：实测 48~55 分钟完成 12 步全流程（87% 资源时连续多轮 48m15s/52m6s/54m0s 含 bitgen）——低资源时可按 50~60 分钟承诺
- 91% 资源：≈1.5h；96%+ 资源：布线收敛明显变慢 ≈2h，phys_opt -effort high 再 +40~50 分钟。给用户报时间按当前资源占比查本表，别一律按最坏值 2h+ 吓退用户也别在 96%+ 时按 50 分钟承诺（用户多次嫌慢的教训）
- 增量（源码未动）：≈ 25 分钟
- 编译慢主因 = 工程规模 + 布线算法并行度有限，多核用不满
- **改动大小与编译时间无强相关**（TD 无增量综合，每次全流程重跑）：1 行改动与加模块同样跑完整 place/route，实际时长由「布局随机扰动决定的 route 收敛轮数」主导——同规模改动实测 55 分钟到 3.5 小时都有。用户问时长时给「按资源档的区间 + 说明 route 收敛不确定性」，别因为改动小就承诺短时间；编译中用户嫌慢时查 run.log 的 `PHY-1001 : Iter N ... over cnt = M`（M 在降 = 正常收敛中，报迭代进度比空安抚有效）

## 验证三连（任何编译后必做）
1. 完成标志：命令行流程没有 BV4_FULL_DONE（那是 GUI 标志）——等价判据 = bitgen 完成（日志 `BIT-1004 : Generate file FPGACompetition.bit` + `finish command "bitgen"`）+ 流程总结表（`RUN-1001 : total` 行，各 step 状态列全绿）；GUI 流程看流程全绿
2. 时序：**命令行流程的时序文件在 Runs/syn_1/ 下**——`syn_1/FPGACompetition_pr.timing`（route 收尾 report_timing_summary 生成）+ `syn_1/final_timing.rpt`（bitgen 前最终报告），两个文件 mtime 必须刷新到刚编译完、数字一致；`grep -E "SWNS|HWNS"` 取开头汇总行，SWNS 负 = 违例。⚠️ **phy_1/FPGACompetition_pr.timing 是 GUI 编译的遗留文件，命令行流程根本不写 phy_1**——它的时间戳会停在最后一次 GUI 编译，把它的 SWNS 当成命令行编译结果 = 误报（实锤两次：读旧文件的 +0.100ns 报全绿，真实 final_timing.rpt 是 -2.949ns 违例）。凡 phy_1 下文件与 syn_1 下同名文件数字冲突，以 syn_1 的为准；phy_1 的产物只在 GUI 编译后有效
3. bit 时间戳：⚠️ 命令行流程的 bit 生成在 **Runs/syn_1/FPGACompetition.bit**（GUI 流程才在 phy_1/）——按实际编译入口查对应目录，修改时间必须刷新到刚编译完

- 编译期间巡检（用户要求「把编译进度监控好」时的标准动作）
- **报编译时长/进度前先查真实数据**：process_manage poll 取 uptime_seconds、或看 log 首尾行时间差——别凭对话时间感估算（深夜多轮 kill/重启后时间感必错，用户会当场纠正）。报「已完成 X 分钟」一律以 poll 的 uptime 为准。
- 编译进程退出会有 notify；但中途要主动巡检：每 15 分钟一次后台 `sleep 900` + 三查——进度（`grep -oE 'Stage [0-9.]+ \| [A-Za-z _]+' log | tail -2`）、错误（`grep -c ERROR log`，SYN-8411 VCO 超范围是已知无害噪音，单独排除计数）、存活（`tasklist.exe /FI "PID eq <自己启动的PID>" | grep -c td_commands`）
- ⚠️ 巡检/杀进程只用自己启动的 PID 精确过滤，绝不按进程名 grep 全量——同机其他工程（bugfix/区域填充等）的编译是同名进程、合法共存，按名扫描再杀 = 误杀他人编译（实锤发生过：命令行参数相同但工作目录不同，只看参数判「同工程并行」是错的）
- **自己的一次 CLI 编译启动后正常出现两个 td_commands_prompt.exe**（主进程 + TD 综合子进程，启动时间同为本次编译时刻）——看到第二个先比启动时间（`powershell.exe Get-Process td_commands_prompt | Select Id,StartTime`）再判断，两个都是本次启动的别杀；冲突判定只看「启动时间对应别的已知编译会话」
- 判残留进程才杀：隔 8 秒两次采样 CPU 不变 = 编译完卡住的残留；杀掉后立刻 tasklist 确认只剩自己的进程。⚠️ **process_manage kill 只杀 WSL 侧的 cmd.exe 壳，Windows 侧 td_commands_prompt.exe 主进程存活**（kill 后 tasklist 仍见同名进程、StartTime 对应被杀编译）——必须 `taskkill.exe /F /PID <Windows侧PID>` 精确补杀（触发审批，用户在线时执行），杀完再 tasklist 确认只剩本次编译的进程
- **停后台巡检循环要 kill -9 循环的 bash 父 PID，并扫掉 sleep 子进程**：kill 外层壳后 `for ...; do sleep 300; ...` 的循环体可能继续 fork 新 sleep（父 PPid 还指向已杀的 bash），用户 UI 里命令卡片一直转——杀完用 `ps aux | grep 'sleep 300' | grep -v grep | wc -l` 验证 0 残留，别只杀一次就宣布已停

## 命令行编译（后台长跑）
```bash
cd /mnt/e/FPGA_Code/<工程>/prj/FPGACompetition_Runs/syn_1
cmd.exe /c "E:/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe E:/FPGA_Code/<工程>/prj/FPGACompetition_Runs/syn_1/FPGACompetition.tcl" > /tmp/td_xx.log 2>&1
```
- **用户已认可命令行编译验证**（2026-11-01「你用命令行直接编译验证吧」）：改代码后可直接 CLI 编译出 bit 做验证三连，不再默认走 GUI；GUI 编译的「不点保存」纪律仅在用户指定 GUI 时适用
- **入口脚本两种，先 ls 确认再跑**：`bv4_full.tcl` 是 B 工程从成功日志重建的专用脚本（相对路径写死，复制工程目录后直接复用），并非所有工程都有；通用入口 = `FPGACompetition.tcl`（TD 默认全流程脚本，头部 source ./settings.cfg，SYN+PHY+bitgen 全流程，每个工程 Runs/syn_1/ 下都有）
- 后台跑用 terminal(background=true, notify=true)，日志 grep 阶段：`grep -o -E 'Stage [0-9.]+ \| [A-Za-z ]+' log | tail`
- **长编译挂机期间（用户睡觉/离开），execute_code 会被审批系统阻塞**（无人批准 → 1 分钟超时 BLOCKED，且明确告知不得重试同一脚本）——文件编辑类操作一律改用 patch 工具（逐块 patch 不阻塞）；纯查询用 terminal 前台命令。用户离开前把「等你回来看到什么」的检查清单留进会话
- 进度阶段：SYN（Map Gate 等）→ PHY（DRC → Iter 布线拥塞收敛 → Rip-up → start_timer 时序 → bitgen）
- 编译前检查 .prj 与 .al 都有 ddr2.xml 引用（`grep -c ddr2` 应 ≥1；.prj 在 Runs/syn_1/ 下，.al 在 prj/ 下）
- 跨会话同步他人修复后编译前，grep 顶层例化确认所有模块端口都有连接（模块加了新端口而顶层例化未同步 = 悬空端口 TD 隐式接 0，语义错且难查）
- **新增 .v 文件必须加进工程文件清单**：.prj 和 .al 的 XML `<File Path=...>` 列表都要加（.prj 用 ../../../src/ 前缀、.al 用 ../src/ 前缀；FileInfo 条目照抄现有格式），否则 elaborate 报 `HDL-8007 ERROR: xxx is a black box`。GUI 添加文件要点保存（会清 ddr2 引用）→ 直接编辑两个 XML 更稳，加完 grep 验证文件名计数 + ddr2 引用未丢。**CompileOrder 取「当前最大值 +1/+2」**：先 `grep -o 'CompileOrder" Val="[0-9]*"' | grep -o '[0-9]*' | sort -n | tail -1` 拿最大值再递增——TD 按数值排序编译，编号唯一即可、物理位置无关，编号重复或空洞都比乱序安全
- 启动编译前查残留 TD 进程：`tasklist.exe | grep td_commands_prompt`，有则隔 8 秒两次采样 CPU（`powershell.exe -NoProfile -Command "Get-Process -Id N | Select CPU"`）——CPU 两次不变 = 编译完卡住的残留（console 未关），`taskkill.exe /F /PID N` 后再启动，否则两个实例抢同一 Runs 目录互相覆盖
- **启动 CLI 编译前一条 pre-flight grep**（每次都要，GUI 编译会重写 settings.cfg 把 arr_* 变量清掉、把 end_step 改回 opt_gate——即使你上次已补过）：`grep -E 'end_step|arr_filter' Runs/syn_1/settings.cfg`，必须看到 end_step bitgen + arr_filter 两行齐全；缺一先补再启动，否则要么只跑综合、要么 place 白烧 37 分钟后炸断
- **编译运行中 git restore/编辑源文件安全**：TD 只在 elaborate 阶段读 .v 源，之后全用内存网表——restore 回「编译启动时的磁盘版本」对在跑编译零影响（阶段已过源读取 + 内容与启动时一致，双保险）；用户问「不会影响编译吧」时用这两个依据回答，不必另跑编译验证

## CLI 编译早退诊断（EXIT=0 但没有 bit，验证三连全空）
编译进程 exit 0 不代表跑完了——判据永远是 bit 是否存在。三连全空时按这个梯子定位：
1. `grep 'RUN-1003.*finish command' log | tail` 看跑到哪一步；`tail -20 log` 看末尾是「finish command xxx」还是 `td >` 交互提示符
2. **停在 elaborate 后（日志极短、只几秒）**：grep 日志里的 `HDL-8007 ERROR`——除了 black box（新文件没登记 .al/.prj），**同一错误码还有「index N is out of range」变体**（新 RTL 的位宽越界 bug，如 26bit 信号按 [FULL_X_W-1:0]=27bit 索引、11bit 信号取 [11:8]）。修完 iverilog 联合复验（-y 挂全目录）再重跑。⚠️ **iverilog 全过 ≠ TD 能过**：位宽越界类错误 iverilog（g2012/g2001）不报，只有 TD elaborate 抓——融合/新写模块跨模块赋值时逐端口核对位宽（26bit 赋 27bit 高位补 0、hex 提取前查端口位宽），别拿 iverilog 绿灯当编译必胜
3. **停在 place 后（约 37 分钟）**：`can't read "arr_filter"`——settings.cfg 变量缺失（见 pre-flight）。注意此时 `FPGACompetition_phy.area` 已生成——**先读资源账（PHY-9053 超限与否、slice 占比）再决定重跑**，资源结论不用等全流程跑完
4. 重跑前必清缓存（rm -f *.db *.bit .*.begin.f .*.end.f），补好变量后从头跑

## 命令行全流程编译（settings.cfg 两个坑）

1. **end_step 被 GUI 写成 opt_gate**：settings.cfg 由 GUI 写入，GUI 只跑综合时 end_step=opt_gate；命令行全流程（要 bit）前必须改 end_step bitgen。⚠️ settings.cfg 是 CRLF 行尾：sed 用 `$` 锚点匹配不到（`\r` 在行尾），必须用不带锚点的子串替换（`sed -i 's/set end_step opt_gate/set end_step bitgen/'`），改完 `grep end_step` 复核（本会话第一次 sed 带 `$` 静默没改到）。
2. **GUI 运行时内部管理的变量命令行必须显式定义**：全流程跑 place/route 时 tcl 的 flow_continue_check 分支读 `arr_filter`（`if { [string equal $arr_filter true] }`）——settings.cfg 里没有 → `can't read "arr_filter": no such variable` 在 place 结束后炸断（place.db 都没 export，只能从头重跑，白烧 44 分钟）。补齐：`set arr_filter false` / `set drHoldFix off` / `set arr_pwns 0.0` / `set arr_cong 100` / `set arr_rwns 0.0`（false/off = 不启用检查与 fix_hold，安全）。
   **arr_* 变量语义（查 TD 安装目录 doc/scripts/DefaultFlow.tcl 源码确认）**：这些只控制「阶段性质量检查是否中断流程」，不改变优化强度——`arr_filter` 开/关 flow_continue_check（place 分支与 `true` 比较、route 分支与 `on` 比较，TD 脚本自身比较值不一致，route 侧检查基本永不激活）；`arr_pwns` = place 检查的 WNS 阈值、`arr_cong` = 拥塞阈值、`arr_rwns` = route 检查的 WNS 阈值。想调优化强度找 route/phys_opt 的 effort 参数，别去调 arr_* 白费劲

## 时序追绿三招（SWNS 为负时的处理顺序）
1. **先判违例路径模块**（`grep -E "Start Point|End Point" final_timing.rpt` 按模块计数；再用 Max Paths 头两条看 Begin/End 模块 + `Logic Level` + `net/cell 占比`）：新增功能模块违例 = 自己拆流水能修；DDR PHY/既有时钟域违例 = 资源挤压（见资源预算节），RTL 白费工夫。**Logic Level>12 且 End 在自己新模块 = 组合串拍**（popcount 树+乘法+加法链没被寄存器断开）——拆拍治法见 fpga-development 的 foreground-overlay-chain.md；net 占比 >50% = 布局扰动，RTL 无用。
2. **phys_opt 提档**：route 命令内部自带 `phys_opt -post_route -effort low`（默认值，日志可见）；在 FPGACompetition.tcl 的 `### Editable zone for opt_route ###` 里 route 之后插入 `phys_opt -post_route -effort high`（支持 low/middle/high/ultra，见 doc/cmd/help_comment_opt.json）。改 tcl 前先 cp 备份，改动只影响下一轮编译，已出 bit 不受影响。⚠️ 改过 tcl 后 GUI 打开工程会重写 tcl 覆盖改动。⚠️ **phys_opt high 可能反向恶化**（实测：PHY 内部 mcu_clk 训练路径 SWNS -3.489→-3.815，白烧 1 小时）——违例路径 net 占比 >50% 且集中在 DDR PHY 内部时，phys_opt 的布局扰动对固定 IP 内部路径帮不上忙还会挤乱周边，一轮恶化即撤（cp 备份还原 tcl），别加档重试。实测（96%+ 资源）：第一轮 Reroute 报 SWNS -3.146→+0.034，但那是单轮中间值——Reroute/Relocation 交替十几轮收敛后最终仍负（-2.505ns），且每轮改善趋平到 0ps 就推不动。effort high 的账：Reroute 多轮迭代耗时 +40~50 分钟（总编译 1.5h→2h20m+），只能收掉 ~0.6ns，96%+ 资源下别指望它单挑回绿——先降资源再谈物理优化
3. **SWNS 负几 ns 的 bit 不阻塞功能下板验证**：DDR PHY 域违例（-2.9ns 级别）历史上多次下板画面功能正常——用户「先下板看看」时照发 bit 并给出路径，时序追绿与功能验证并行，不卡用户；但必须在汇报里明说违例数值，不得隐瞒或美化
- **HWNS 负几十~百 ps 的小 hold 违例（-0.085ns 级，路径在 soft FIFO IP 内部跨域寄存器）是布局随机波动**：同版设计前几轮编译 HWNS +0.020、某轮随机变 -0.085——IP 内部路径 RTL 改不动、85ps 对 100MHz 时钟下板风险很低（历史负 hold 版本下板正常），处理 = 如实告知用户数值 + 后台重编译一轮看是否随布局随机回绿，别为它卡交付
3. **资源挤压类违例**：96%+ 资源下 DDR PHY 路径被挤长 1~4ns，effort 只能收一部分，治本是降资源。⚠️ 但低资源占比不保证 PHY 干净：2026-11-02 融合版 87.85% slice（低于基线 91%）时 SWNS -3.489ns，违例全在 u_ddrphy_init/fiu 的 mcu_clk/sys_clk_50m 训练寄存器路径（非 ref_clk 自环），net 占 53% = 布局噪声拉长——新增模块扰动全局布局即可触发，与资源占比无强相关。判据不变：先 grep Start/End Point 看模块分布再定应对，PHY 内部路径 RTL 改不动，只能 phys_opt/重布局碰运气，功能风险低（训练期逻辑，框会话同款现象下板正常）

## TD 综合属性（SWUG106 手册 4.2 节，pdftotext 提取后 grep）
- **dsp_style**（4.2.10）：控制 DSP 映射——`(* dsp_style = "no" *)`（属性形式）或 `/* synthesis dsp_style = no */`（注释形式），可挂模块级；值 auto/yes/no。**TD 不认 syn_dspstyle 等 Quartus/Xilinx 风格属性名**，写错静默无效、DSP 数不降
- **小乘法会被塞进 DSP**：6×11 之类的窄乘法 TD 也可能映射进 DSP 18×18（本工程质心统计两个 6×11 乘法 = DSP +2）。**「~30 LUT 一个」的估计被实测推翻**：给 bbox_stat/div31 全模块 dsp_style=no 后，映射阶段 #lut 19903→21055（+1152）、逻辑级数 13→14。**完整编译的最终账**：DSP 10→8、slice 20549→20432（打包后不升反降——LUT 计数涨 ≠ slice 涨，打包密度不同，别用 #lut 增量的 1:1 换算去吓用户）；**真正的代价是时序**：SWNS -1.227→-2.505（恶化 1.28ns），+1152 LUT 把 96% 资源下的 DDR PHY 路径挤得更长。**结论：slice 几乎白省、时序实打实恶化——资源 <97% 且 DSP 不紧张时不要 dsp_style=no；只有 DSP 也吃紧或时序由 DSP 级联主导时才用**
- **资源趋势早信号（不必等最终报告）**：Map Gate 阶段日志 `SYN-2581 : Mapping with K=6, #lut = N` 的 #lut 数字跨编译可比（同工程同 K 值）——编译 30 分钟处即可发现资源涨跌趋势（实例：dsp_style=no 一版 #lut 19903→21055 提前暴露「省 2 DSP 花 +1152 LUT」的亏本账，不用等 1 小时后的最终 slice 报告）。⚠️ 早信号用于**预警**，不用于**拍板回滚**——编译跑完拿最终 slice+时序+DSP 三件套再定结论，中途宣布回滚方案会被用户拦下（「先别着急回滚」）；回滚决策等数据齐了再说
- 查命令帮助/参数：TD 安装目录 `doc/cmd/help_comment_{syn,phy,opt,tool}.json`（json 结构 command/<命令>/opt_list + opt_describe），python json.load 遍历即得完整参数表；流程模板源码在 `doc/scripts/DefaultFlow.tcl`（arr_* 变量、各 step 函数、Editable zone 位置都在这查）
3. **含中文路径的工程：命令行参数里不要带绝对 tcl 路径**——WSL 调 cmd.exe 时中文目录名被转码损坏（`couldn't read file "...bug�޸�/..."`）。正解：WSL 先 cd 到 Runs/syn_1（cwd 经 Win32 API 设置，中文 OK），命令行只写 `td_commands_prompt.exe FPGACompetition.tcl`（tcl/工程文件引用全相对路径）。**根治 = 工程目录直接改全英文**（`mv FPGACompetition_bug修复 FPGACompetition_bugfix`）：TD 工程文件（.prj/.al/settings.cfg）全用相对路径，改目录名零影响；文档/脚本里的旧路径引用同步（⚠️ 改名后几分钟内 WSL 对新目录名的读访问会失效——drvfs 缓存，Windows 侧完全正常：批量替换旧路径引用改走 Windows git bash sed，git 验证走 `git -C E:\...`，稍后 WSL 自然恢复或重启 WSL），git commit。**下板下载 bit 必须全英文路径**——TD 下载器不支持中文目录（命令行编译可用 cd+相对路径绕开，下载绕不了），最终交付前务必先改目录名。

## GUI 编译 + 转回 GUI 方法
### 前提：.al 的 ddr2 引用（缺了报 black box）
```bash
grep -c ddr2 prj/FPGACompetition.al   # 应为 1
```
缺则补：在 `<File Path="../src/ip_source/PLL/PLL.xml">` 前插：
```xml
            <File Path="../src/hdl_source_ip/ddr2/ddr2.xml">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="45"/>
                </FileInfo>
            </File>
```
### 关键坑
- **GUI 打开 .al 后绝不点保存**——保存会重写 .al 并清掉 ddr2 引用（屡试不爽的老坑）
- VCO 超范围警告（如 2400MHz 超 [800,2000]，derive_clocks 报 SYN-8411/USR-8159 失败）：无害——成功编译的 log 里同样有 10 处，bit 照常生成，别为它中断；确认 bit 日志里各时钟频率正确即可
- **用户发 GUI Console 报错/警告树截图时：先 tesseract OCR 再 grep 日志交叉验证，别凭窗口红标就断错**。`tesseract 图.png out -l chi_sim+eng`（WSL 自带，TD 窗口中文识别够用）读树结构，同时 grep prj/log/td_*.log（GUI Console 内容落盘处）。已知无害项清单：SYN-8411 VCO（上述）、HDL-5007（/* inside comment 注释嵌套，ISP 基线老警告）、HDL-5373（identifier used before declaration 先使用后声明，基线老写法）——融合/改代码后编译只盯三类实质问题：HDL-8007 black box（新文件未登记 .al/.prj）、语法错误、悬空端口；三类都没有 = 改动过综合没问题，让编译继续跑并如实告知用户哪些是已知无害项
- **编译无报错 EXIT=1、log 停在综合优化 round 附近 = 进程被外部 kill**（别的会话 taskkill 或 OOM），不是代码错——先查 `tasklist.exe | grep td_commands_prompt` 和别的 Hermes 会话是否误杀，再清缓存重跑；别误判为 RTL 问题去改代码
- 多会话同机并发：单 TD 综合峰值内存 1.3~2.8GB，16GB 机器 2 个并发紧张、3 个危险；不同工程目录互不冲突，但 tcl 同名（都叫 FPGACompetition.tcl）会被别的会话误判为「同工程并行」而杀掉——编译前先与其他会话对表。确认已跑进程身份用 `powershell.exe -NoProfile -Command "(Get-CimInstance Win32_Process -Filter 'ProcessId=N').CommandLine"`（但命令行参数相同、都走相对路径时无法据此区分，唯一可靠区分 = 与其它会话对表/用户通报，宁可共存不可误杀）
- **误杀另一会话的编译后，别替它重启**：它用 GUI 编译（读 .al）就用 GUI 恢复——用 CLI（读 .prj）替它重启会编译可能过期的 .prj、且 CLI/GUI 中间文件在同一 Runs 目录混写互相污染。恢复权交还那会话/用户自己重开 GUI；自己只负责把自己起的 CLI 残留进程（bash 被杀后 Windows 侧 td_commands_prompt.exe 成孤儿继续写工作区）按 PID 清干净，并告知对方。
- Code verification failed：bit 与 ChipWatcher cwc 不配对——用 binWriter 下载不校验，或重新生成调试内核
- GUI 编译时序可能略差于命令行（历史 -11ps vs +102ps），删调试内核（MARK_DEBUG 清零）后消除
- 隐式网三连（HDL-7225/SYN-5013/SYN-5025）零新增 = 无新增隐式网

## ChipWatcher 调试信号保留（TD 优化机制，2026-11 实测）
- **MARK_DEBUG="TRUE" 属性本身不保信号**：TD 真正保留的是 GUI 工程 ChipWatcher 自动创建列表（auto_created cwc）里被引用的信号——老调试信号在列表里 → 保留；新加的信号不在列表 → 综合优化掉，.cwc 里标红、Add Signal 列表里搜不到。
- **保信号的可靠姿势 = 给信号接真实负载**，别用顶层悬空输出端口：顶层加 output 端口悬空 → bitgen 报 `BIT-8123 ERROR: Bitgen is prohibitted as there is(are) unconstrained io(s) in design.`（配套 CRITICAL-WARNING 报「N of M logical ports has no user assigned specific location constraint」），且 GUI 工程设置改 unconstr_io 放行很难找、单独重跑 bitgen 仍失败。正解：把调试信号编入现有诊断通道（如 uart_dbg_tx 的预留字节 I_b10），有负载必保留，零新端口零新引脚。
- TD GUI 界面导航（左下「FPGA Flow」面板，Process 标签）：Syn Opt（Read Design/Optimize RTL/Optimize Gate）→ Phy Opt（Optimize Placement/Optimize Routing/Generate Bitstream）→ BitWriter；右键步骤可单独 Run；命令行可 reset_run phy_1 -step bitgen 单跑 bitgen；Bitgen 参数设置入口 = 右键 phy_1 → Run Properties → Flow Options 栏 → Generate Bitstream（General/Control/Startup/Attribute 四组）。
- 位宽提醒：调试信号拼进诊断字节时数清拼接位宽（{1'd0, 3 个 1bit, 3bit} = 7 位接到 8 位端口会隐式补零、注释位序错位），凑整用 2'd0 并核对注释。
- **Trigger Position 是窗口内绝对位置（0~采样深度-1），不是百分比**：0=窗口全在触发之后、深度-1=全在触发之前。给用户抓取指令时直接说「填 0 / 填 1023」，别用「拖到最右」这类描述（用户对 Trigger Settings 面板不熟）。帧头类诊断四抓组合：目标沿触发 + Position 0（触发后全窗）/ Position 1023（触发前全窗）/ 中点（前后各半）。
- **编译前新增的调试信号，抓取时先验证 CSV 列存在**：新信号不在 auto_created cwc 列表，用户容易忘记手动 Add Signal → 抓回的 CSV 缺列（白抓一轮）。让用户抓前确认信号列表里能看到新信号名（如 S_cw_rp），导出后先读 CSV 表头核对再分析。

## 资源预算与 slice 超限诊断（PH1P35 实测 2026-11）

- **新功能编码前先查基线资源余量**：`grep -E "#slice|#lut6|#reg|Utilization" Runs/phy_1/FPGACompetition_phy.area`（上一轮成功编译的 PHY 资源报告）。PH1P35 主线基线 slice 达 91%（19328/21216，仅剩 ~1900 片）——深延迟链类新功能（行缓冲/对齐链）先按「1 FF ≈ 0.5 slice、1 LUT ≈ 1 slice」算账再动手，别写完编译才撞 PHY-9053。
- **PHY-9053（slice 超限）现象**：place 跑完就停（`finish command "place"` 后无 route/bitgen），日志一条 `PHY-9053 ERROR: Design's slice number = N, exceeds the limit M`。定位资源大头：`Runs/syn_1/FPGACompetition_gate.area` 按 Instance 列 logic lut / seq / shifter lut / dram lut，找 seq 突然暴增的模块。
- **带复位/帧清分支的移位链 TD 不推断 SRL**：TD 官方 SRL 推断模板（SWUG106 手册 5.5.1：`always @(posedge clk) if(enable) shift_reg <= {shift_reg[DEPTH-2:0], d};`）只有 enable 分支、无任何复位——链里写 `if(!rst_n) / else if(frame_start)` 分支后 shifter lut 列恒 0、整条链变 FF，深度数百的 4bit 链一块就是上千 FF。需要帧清语义时用「洗链」（帧清后强制 en=1 喂 0 洗 DEPTH 拍，输出由 valid 链门控挡住）而不是复位分支。
- **深移位链资源三形态（按省资源顺序选）**：①SRL——无复位 enable 门控链，TD 默认寄存器+SRL+寄存器（可用 `/*synthesis shifter_style = ...*/` attribute 改策略，可选值 register|shifter|shifter_reg|reg_shifter|reg_shifter_reg）；②DRAM——数组+读写指针环形缓冲，声明处 `/*synthesis ram_style = dram*/` 强制分布式 RAM（LUT 实现，比 FF 省数倍）；③FF——带复位语义时的默认形态。attribute 写法与 RAM 推断规则查 TD 安装目录 `doc/SWUG/SWUG106_HDL_Coding_Synthesis_User_Guide.pdf`（pdftotext 提取后 grep 4.2.6 ram_style / 4.2.9 shifter_style / 5.5 Shift register）。
- 时序约束不变时新增延迟链也要重跑时序（slice 逼近上限时布线拥塞会让 SWNS 恶化，资源省下来也是为时序留裕量）。
- **slice 利用率 >96% 时，新增逻辑即使自身时序干净（已流水化），违例也会出现在 DDR PHY 内部 ref_clk 路径**（实测：同设计 91% 资源 SWNS +0.100 全绿 → 96.86% 资源 SWNS -1.227ns、违例全在 u_ddrphy_* 的 100MHz ref_clk 自环路径）。资源占比不只是 slice 上限问题，更是全局时序预算——判违例先看路径模块分布：新增功能模块违例 = 自己拆流水能修；DDR PHY/既有时钟域违例 = 资源挤压，只能降资源或放宽时序策略，别在 RTL 上白费工夫。

## 工程文件修复记录（PH1P35 实战）
- B 工程曾 .prj 和 .al 双缺 ddr2.xml → 双双补回；.prj 的 PLL CompileOrder 45→46 对齐 A 工程
- 首次 patch .al 时匹配错位会破坏 XML 结构——补完 grep 验证 + sed 看上下文
- 编译缓存清理：改源后默认清 syn_1/*.db、syn_1/*.bit、.*.end.f、.*.begin.f、phy_1/*.db、phy_1/*.bit、final_timing.rpt（命令行流程的 bit 在 syn_1 下，不删旧 bit 会误看旧时间戳）。⚠️ **删 bit 前先确认它是否已被用户下板消费**——重编译前的 rm -f *.bit 会连用户尚未下载验证的新 bit 一起删掉，删了就只剩旧版本（TD 留的副本在 best_result/FPGACompetition.bit 和 phy_1/cw/compiled.bit，但时间戳滞后几轮，ls -l 看时间戳确认版本、别盲信目录名）。用户可能要「先下载看看」时，重编译先征得同意或先备份 bit

## 相关
- fpga-development（项目主线 skill）
- ChipWatcher 调试三件套：WinUSB 驱动 + 官方 hwserver.exe + AL-LINK-FT Local port 5555（详见 fpga-development）
