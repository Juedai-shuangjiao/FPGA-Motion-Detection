# 安路 ChipWatcher / Eram Editor 片上调试实操（TD 6.2）

> 实机错位/相位问题在 RTL 仿真对不出来时（跨时钟域、TD 插拍/retiming 不可见），片上抓波形是唯一「看见真身」的手段。文档出处：TD doc/SWUG/SWUG111_Debug_Tools_User_Guide.pdf（pdftotext 后可 grep）。

## 工程速查（本工程实测）
- **ChipWatcher 用 GUI 编译（用户经验，明确要求过）**：Mark Debug 属性的调试核插入在 GUI 编译链路完整（后端生成 phy_1/cw/compiled.cwc + debug hub）；命令行编译产物 GUI 打开报「Current flow is out of date」。分工 = agent 改 RTL（Mark Debug 属性 + 引出打拍），用户 GUI 编译 + 抓波形。
- TD ChipWatcher IP 源码：E:/TD_6.2.1_Engineer_6.2.168.116/ip/depot/ChipWatcher_1.1/ChipWatcher/RTL/ChipWatcher.sv（端口 probe0~probe255 + clk，用法 = Mark Debug 属性而非直接例化）。
- .cwc 配置是 XML：watcher_nodes 下 net（单信号，含 clock/inst/type=MARK_DEBUG_PROBE）与 bus（多 bit，net 逐位列出）。参考样例已抢救到本工程 sim/chipwatcher_ref/compiled_b3.cwc（B v3 抓写读侧坐标系的配置，连同 chip_debugger/ 核目录）——新抓取改信号名前先照它抄格式。
- 串口诊断帧（uart_dbg_tx，替代 ChipWatcher 的零成本观测）：115200 8N1，每帧 12 字节 = AA 55 | b2(半帧标志) b3(fg_init) b4(首字地址低8) b5(标志+高7) b6/b7/b8(bg 读总数低8/中8/高3) b9(SW4) b10(预留) | EE；读总数 ÷480 = 该段读到行数。串口接不了时改用「线位置反推窗口」：停止线行号 = 段起点 + 窗口拍数/480。

## 何时用
- 确定性 bug（每次烧板稳定复现）最好抓——一次波形就锁定相位差；随机 bug 才难抓
- 抓之前先看时序报告，但**违例评估按「被抓信号的时钟域」判**：调试核布线会把本来贴边（~+0.1ns）的 DDR 域拉到 -90ps 级违例，只要被抓信号所在域（如视频域 75M）SWNS/HWNS 全绿，波形采样就可信，照抓；交付版拆掉调试核后违例自然回绿（hub 消失即 -11ps~-90ps 级违例转绿）。**另一种无害形态 = 域内（intra-clock）全绿但全局 SWNS 负**：违例全落在 inter-clock 路径（跨域打拍采样/CDC 被当同步路径计时）——TD 把调试块 clk0→clk2 的 2 拍同步器也计时，这类伪违例不影响采样正确性（同步器本来就是跨域吸收亚稳态的），判据 = 报告里 Intra clock domain timing 段 0 Viol 即可照抓，别被全局 -971ps/12 点吓停
- 设计抓什么：同链信号「打拍前/中/后」多版本（可看出综合器吃没吃打拍）+ 数据/地址 + 坐标系（x/y/word/col）——波形里「内容首次非零拍」与「输出首次生效拍」的坐标差 × 时钟频率关系 = 错位拍数

## 触发信号选择三档（读/写窗口类 bug，实测定式）

抓「间歇性活动链」（如 bg 读：每帧读满后停）时，触发选错 = 整窗口零信息，三档按目标选：
1. **抓帧头读启动** = 触发清场/帧开始信号上升沿（如 abort 清场 300 拍信号）——窗口覆盖清场 + 首批读命令，看读被谁挡、启动延迟多少。
2. **抓停读原因** = 触发读使能下降沿——窗口落在停读瞬间，看 grant/门控/水位哪个先变；窗口内读计数（帧头清 0、逐命令 +1 的 rdcnt）可用，但**计数类信号要抓高位段**：读满量 8.8 万~13 万远超 8 位，8 位绕圈数不出读满没读满——抓 [18:11] 高位（每 2048 命令 +1，读满值 = 段读量>>11，如 88320>>11=43、130560>>11=63，一眼判读；旧文 ÷256 口径的 345/510/525 是另一段位，别混用）。
3. **抓「上一帧读总数」的定式（实测有效，不用 Pre-Trigger）**：触发 = 帧头清场信号（如 abort）上升沿，**窗口首拍（触发点前 ~127 拍）就是上一帧尾**——rdcnt 在触发拍才清 0，首拍的 rdcnt 高位值 = 上一帧读命令总数，直接判读上一帧读满没读满（实测抓 4 次得 43/63/63/43 = A 读满/B1 读满/B2 贴边）。Trigger Position 不用动（默认位置即可，用户不会设也不用设）。**逐帧轮转判读法**：连续抓 N 次（每次间隔仅导出时间），每次首拍值 = 各段读满值的轮转序列——某段的值恒不出现 = 该段读不满（读满才翻转段、读不满卡同段重读，所以读不满段会「隐身」，只看到它前面一段的值反复出现）；读出「实机窗口」= 最大读满段的读量 < 窗口 < 读不满段的读量（如 B1=130560 读满、B2=134400 读不满 → 窗口 ∈ [130560,134400)）。**高位分辨率局限**：读不满停读量与相邻段读满量在高位段同值（B2 停 ~130600 与 B1 读满 130560 同为 63）——贴边段判定结合「段读量 vs 实测窗口」推算，别只看高位值；需要精确停读量就加抓中位段或读使能下降沿窗口。
4. **避免用行消隐电平边沿（disp/de 下降沿）当触发**——它落在任意行，大概率命中「读满停读期」（读使能全程 0、仲裁正确地不给片——bg 无需求时 BG 片 1 拍跳过，grant 几乎全程 0 是正常行为不是损耗），整窗口只有「水位锯齿/门控基线」可用，看不出读的行为。
5. **抓特定时刻（显示开始/帧尾/某行首）必须用该时刻独有的信号触发**：每行都满足的触发条件（disp/de 边沿）抓到的只是点 Run 后撞上的随机行，顶部行这类低概率行（1/750）靠多抓几次撞不中；显示开始瞬间 = 场同步 vsync 下降沿触发（场消隐结束 = 第 0 行显示开始），帧尾 = 帧头清场信号上升沿 + 窗口首拍定式（见 3）。配套抓「残余丢弃期/写使能」这类慢电平信号（discard_cnt>0 展宽电平、FIFO we），单拍脉冲类（帧开始脉冲）在 75M 采样下漏采，别选。
6. **Trigger Position in window = 触发点在窗口中的绝对位置（0~1023）**：默认 127 = 触发前 127 拍 + 后 896 拍；0 = 全 Post（窗口全在触发后，看「事件之后发生了什么」）；1023 = 全 Pre（看「事件之前」）。Window data depth 最大 1024 拍不可调——跨长消隐期（667µs）看两件事只能**多窗口拼接**：同一帧头分别用 vsync 下降沿（显示开始）、discard 下降沿（残余丢完）、we 上升沿（首笔写）、disp 上升沿（首行显示）各抓一次，每窗口当拼图碎片分析，别指望单窗口覆盖全程。判读利器 = **速率自洽**：把信号变化速率与理论速率对比（如水位降速 0.18/拍 ≈ 显示消耗 320 字/1650 拍 = 0.19/拍 → 显示链健康、供给正常，问题在数据内容而非流量）——水位满 ≠ 数据对。
7. **多读源交织 bug 先做开关二分实验**（几秒钟收敛方向）：关掉副读源（如背景检测）看现象是否消失——消失 = 多读源交织相关（仲裁/标签/丢弃计数），不消失 = 单链路自身（帧头/复位/读指针）。比抓波形快一个量级，先二分再决定抓什么。

判读口径：跨域打 2 拍采样的计数信号（DDR 域计数 → 视频域 75M 采样）每采样拍 +1 或 +2（4/3 比率）是正常的，按「变化总数 ≈ 实际命令数（含 8 位截断回绕）」换算，别当丢拍；读段内 grant 持续 1 且读命令占空比 ~50% = 链路健康。

**跨域采样选信号的口径**：Mark Debug 信号全标在视频域（安全域）时，源信号要选「慢电平/宽脉冲」——单拍脉冲（帧开始/写命令拍类）在 75M 采样（13.3ns 周期）下会漏采或采成断续毛刺；帧头判据改用「帧头清 0 的计数信号变化」（rdcnt 从 0 起跳）或展宽信号，别抓源域单拍脉冲。8 位计数信号在长窗口内绕圈多次（读满 8.8 万拍 = 345 圈），要读总量就抓高位段 [18:11]；绕圈时「回跳 >100 算 +256」在分析脚本里做回绕展开。

## 插入信号（Mark Debug，最省事）
- 源码信号定义处加属性：`(*MARK_DEBUG = "TRUE"*) reg xxx;`（wire 定义处也可标，保守用 reg）
- **⚠️ 属性本身不保信号：TD 只保留 ChipWatcher 工程自动创建列表（auto_created_cwc）里引用的信号**——新加的 MARK_DEBUG 信号不在上次工程的列表里时，综合器把它当无负载信号优化掉（网表里不存在）→ .cwc 里标红、Signal Selector 搜索不到（旧信号不标红因为它们在列表里）。**修法首选 = 给信号接真实负载**（如编入 uart_dbg_tx 诊断帧的预留字节——bit 拼接进现有字节，有负载必保留、零新端口零新引脚；拼接位宽数清，{1'd0,3个1bit,3bit}=7位接 8 位端口会隐式补零、注释位序错位，用 2'd0 凑整并核对注释）。判别「编译没跑到 vs 被优化」：其他老信号正常而新信号标红 = 被优化。
- **⚠️ 顶层悬空输出端口保信号会挡 bitgen（实测，已弃用）**：无引脚约束的输出端口在 bitgen 报 `BIT-8123 ERROR: Bitgen is prohibitted as there is(are) unconstrained io(s) in design.`（syn_1 成功、phy 全流程跑完、只差 bitgen 时失败）。两个表面解法都不靠谱：改 `phy_1/.bitgen_param.f` 的 `unconstr_io on` 后单独重跑 bitgen 仍报错（参数走 commit_param 存 flow db，改文件无效）；GUI 整流程 Rerun 会重新导出参数写回 off，且 Bitgen 设置对话框入口难找（右键 phy_1 → Run Properties → Flow Options → Generate Bitstream）。**结论：保信号别走悬空端口，直接接真实负载**。
- 不能标芯片 IO port（与 IO Logic Model 相接的 port 导致 Mapping 报错）——port 数据要抓就加内部 debug 寄存器打 1 拍再标（`S_dbg_xx <= port[..:0];`）
- 标注后正常跑完整 Flow，软件按驱动时钟自动分组实例；默认采样深度 1024，可改
- 多时钟域 = 多个实例、时间轴不共享；跨域对比有难度，先抓单域内部账

## 收官清理（交付版删除全部调试信息）
调试收敛后把 MARK_DEBUG 全部拆掉出交付版：①功能信号（de 链/x_2d/word/col/mark 链）只删属性保留信号；纯调试 reg/端口（如写侧三件套 I_dbg_wr_*/S_dbg_wr_*/读侧 S_dbg_rd_*）连声明+打拍赋值+顶层连线整块删。②删属性用正则 `\(\*MARK_DEBUG = "TRUE"\*\)\s+reg\s+`——按精确空格字符串 replace 会漏（声明行 reg 后为对齐有多个空格，正则 \s+ 才全命中）；删完 grep -c MARK_DEBUG 必须归零。③源模块为调试引出的输出端口（bg_read 的 S_fg_wr_*）留着空挂即可，综合自动 trim，不必回改源模块。④收益双重：调试 hub 消失 → 时序改善（-11ps 级微小违例可直接转绿）+ ChipWatcher 下载黑屏问题自然消失（无 hub 可激活）——交付版天然规避调试核插域黑屏。

## 编译
- 带采样核编译时间变长——尤其 bit 生成阶段（start_timer 之后）可能静默几十分钟，别误判卡死去杀进程（进程活着就等）；phy 单阶段 40~50 分钟属正常。进度判读看三处日志：prj/log/td_*.log（launch_runs/import_db 里程碑，含 Import ChipWatcher 成功行）、phy_1/run.log（布线 Iter N 拥塞计数在走 = 活着）、phy_1/cw/auto_created_cwc1/*_ooc.log 与 phy_1/cw/debug_hub/top_debug_hub_ooc.log（调试核 OOC 综合进度，到 Exported models = 核完成）
- **多会话/多工程并行编译的互相误杀**：另一会话的编译巡检按「tcl 文件名相同」误判同工程并行（不同工程目录的 tcl 都叫 FPGACompetition.tcl），会把本会话的编译进程 kill（症状 = 编译在优化迭代某轮无报错 EXIT=1）——并行编译前先告知对方会话「不同目录、勿杀」，或错开时间。机器内存 16GB、单 TD 综合峰值 1.3~2.8GB：2 个 TD 并发可行、3 个危险（无报错崩溃 = 内存竞争头号嫌疑）。
- 命令行编译后 GUI 打开该工程会报「Current flow is out of date」，点 Yes 仍是 read only——用离线调试模式绕过

## 下载校验错「bit file does not match with chipwatcher design」
- = 下载的 bit 与打开的 .cwc 不是同一版编译产物（典型：下到了 syn_1 的旧 bit——工程默认 run 的 bit 可能还是上一版无调试核的）。GUI 编译后配对三件套自动生成在 phy_1/cw/（compiled.bit + compiled.cwc 同秒生成）——下载前确认 bit 路径指向 phy_1/cw/compiled.bit，不是 syn_1 下的；离线模式打开 phy_1/cw/compiled.cwc 即可自然配对

## 离线调试（推荐，不依赖 GUI 工程状态）
1. 不打开工程，Tools → Debug Tools → ChipWatcher → 弹窗选 compiled.cwc
2. .cwc 与 .bit 必须同一目录：编译产物在 phy_1/cw/compiled.cwc，把 phy_1 的 bit 复制进来命名 compiled.bit
3. 导入后（标题 read only，离线模式正常现象）点 Watch 按钮（顶部工具栏左起第一个，UIA label 含「Watch」）→ 上半下载窗口、下半波形区；用户卡在「找不到 watch」时直接指向工具栏左起第一个。**注意区分**：read only 本身正常，但 read only + Connect server failed 同时出现 = 离线只读且抓取全灰，此时 read only 是「hwserver 断线」而非离线模式，按下方 hwserver 排障分层修，别在 UI 上找只读开关
4. 只读只锁编译期属性（信号列表/深度）；触发条件是运行时设置，Watch 里可改
5. 波形导出：File → Export Wave Data 存 CSV（文本可回传脚本分析）；或抄 Value 列关键拍
6. **CSV 解析列序坑**：导出 CSV 前两列是 Sample、Trigger（占位列），信号列从第 3 列（索引 2）开始——分析脚本按 header 名取列或从 r[2] 起，从 r[1] 起会全体错位（把 Trigger 当第一个信号、所有信号串一位，算出的分段/计数全废，且一眼看不出错）

## TD 命令行能力边界（td_commands_prompt tcl）
- `help` 列全部命令；脚本路径必须用 Windows 风格（WSL 的 /tmp 是 UNC 路径 cmd 不认，写 /mnt/e/... 并传 E:/... 形式）
- 命令行有：`download -bit <file>`（下载 bit）、`eram_operate`（操作 bit 文件里的 ERAM 初始化数据，**不是**读板上 RAM）、`read_phy_data -addr`、`debug_mode`
- 命令行**没有** ChipWatcher 的设触发/抓波形/导出命令——波形只能 GUI；「命令行读数据」的正解 = 用户 GUI 导出 CSV/txt 存文件 → agent read_file 读
- Eram Editor 读板上 RAM 的通道 = hwserver.exe（见下），无 tcl 接口

## 下载与硬件识别（最大的坑在 JTAG 占用）
- 调试工具（ChipWatcher/Eram Editor）走 hwserver.exe；烧录工具（binWriter = bw.exe）另走一路——**烧录窗口开着就占住 JTAG，调试工具全部 No hardware**。先关掉 TD 的 Download 窗口再连
- 下载速度档位与 binWriter 的不一致没关系（binWriter 5Mbps vs ChipWatcher 6Mbps），选最近档位即可，不是必须匹配
- Download 窗口 Device 栏空白 = 硬件没连好（查上电/JTAG/烧录窗口占用）

### 连通性报错的排障分层（5555 cast error 类，往 hwserver/端口/USB 层查）
- 报错分级：`Connect server failed` / `Chip validation failed` / `Downloading failed` / `host cast error ... using default: 5555` 都是 **hwserver 通信层**问题——5555 是 hwserver.exe 的本地监听端口，cast error ≠ 端口被外部程序占用，而是 td.exe 连上 5555 后协议层读到垃圾数据。binWriter 能下载而 ChipWatcher 报这些错时，JTAG 硬件链路多半是通的，别先拔线。
- 排障命令（WSL 里全用 Windows 原生命令，WSL 自带 shell 无 netstat）：进程 `tasklist.exe | grep -iE 'bw|td|hwserver'`；端口归属 `/mnt/c/Windows/System32/netstat.exe -ano | grep 5555`；USB 枚举 PowerShell `Get-PnpDevice -Class USB`（含 Status=Unknown 的异常设备）。
- **hwserver.exe 僵尸实例冲突**：tasklist 出现两个 hwserver.exe = 旧的占住 5555，td.exe 连上后立即断开（netstat 见 CLOSE_WAIT/FIN_WAIT_2 堆积）→ cast error 刷屏。清法：退出 ChipWatcher → 任务管理器结束全部 hwserver.exe → 重开 ChipWatcher 自动拉起新实例；整机重启一并重置 USB 枚举，是清僵尸最彻底的手段，用户主动重启时不要拦。
- **下载器 = FTDI FT2232H（VID_0403&PID_6042，设备名 USB-JTAG Cable，双接口 MI_00/MI_01）**：设备在但接口 Status=Unknown/Error = 驱动掉了。**TD 自带 `driver/al-link/win10/x64/anlocyusb.inf` 只认安路自定义 VID_336C&PID_1001~1004，与 FTDI 0403:6042 不匹配——别拿它重装**。PowerShell `Disable-PnpDevice` → 等 3 秒 → `Enable-PnpDevice` 循环只算临时缓解（实测仅让主设备 OK，hwserver 仍打不开通道），**最终解法 = 官方驱动包三步（板子资料 `HX1P35A_Contest_202606/1_安路工具和软件/新版TD驱动PH1P35使用方法/`，先 pdftotext 同目录（必看）PDF 看官方流程）**：①`安路JTAG驱动安装_固件/UsbDriverTool/UsbDriverTool.exe` 对 VID_0403&PID_6042 设备右键选「安装 WinUSB」；②把该目录配套 **hwserver.exe 复制替换 TD bin 下的 hwserver.exe**（原文件备份 .bak；替换前必须先关 ChipWatcher 并结束残留 hwserver 进程——文件被占用时 cp 报 Permission denied）；③完全重启 ChipWatcher（替换 hwserver 后不重启不生效）→ 点 AL-LINK-FT 弹窗里 **Local port 显式填 5555**（空着就刷 cast error）→ 刷新（官方写明要刷两次才显示型号，第一次显示 OCCUPPIED 属正常）→ Apply and Close → 芯片型号直接出现、标题 [read only] 消失。
- **Windows「自动搜索驱动」会把好驱动换坏**：更新驱动走 Windows Update 时 FTDI 被装成兜底「USB Composite Device」（binWriter 也开始识别不到板子），接口残渣呈 ProblemCode 28 = 驱动安装失败无 inf 绑定（PowerShell `Get-PnpDeviceProperty -KeyName DEVPKEY_Device_ProblemCode` 查）。恢复 = 设备管理器卸载黄叹号设备（勾选删除驱动程序）→ 拔插 USB → 用 UsbDriverTool 重装 WinUSB。settings.ini 里 `Cable Select=0:123456789` 就是该 FTDI 的串号（占位串号不是配置错误）。**拉起 ≠ 就绪，两种失败形态分开判**：①进程消失 = hwserver 启动即崩；②进程活着但 netstat 5555 无 LISTENING = 拉起成功但 FTDI 通道打不开（WinUSB 独占合并后接口模式丢失时是这种）——tasklist 看进程、netstat 看 5555 LISTENING，两层都查才下结论。形态②的下一步在驱动层继续修（设备管理器更新驱动走 Windows Update 恢复 FTDI 接口模式），别在 UI 找只读开关。TD 用户配置在 `C:/Users/<user>/.anlogic/Tang Dynasty/settings.ini`（Cable Mode/下载器串号/JTAG CLK Freq）；hwserver.exe 手动启动无 console 输出，判断死活靠 tasklist 有没有进程，不靠输出。
- **「能下载程序（binWriter/ChipWatcher 下载都成功）但 Single Trigger 灰」= 硬件链路通，问题在触发配置层**（四件套检查），不要在 USB/端口层浪费时间。
- UIA 点击 download_button 后按钮消失 ≠ 下载开始：以进度百分比走动为准——0% 不动 = 通信没建立，先查 hwserver/端口/USB 三层；下载完成后 download_button 会重新出现在元素树里。

## 抓波形操作顺序
1. 打开界面：TD 打开工程 .al → Hierarchy 树里双击「ChipWatcher」节点（**合成双击/自动化双击无效，需真人双击**；自动化接管时这一步让用户手动点，其余步骤驱动）
2. 下载 bit → 板子断电重启 → 照常初始化（SW4 采背景等）
3. 手/物体放画面左 1/4 处不动（深度 1024 拍只覆盖约一行 80%，放左边才在窗口内）
4. 触发设行首：de_2d 上升沿——**触发信号列表默认是空的，Operators 列不出现**（用户会卡在「找不到 Operators」）：先在触发条件设置区右侧列表空白处**右键 → Add Triggers**（菜单第一项，Down+Enter 键盘导航可选）→ 弹出 Signal Selector 列表库，**双击信号 = 勾选添加**，再点 OK。列表库只含勾选过 Trigger Enable 的信号。添加后行才出现 Operators/Trigger Condition 列。
5. **单 bit 信号点 Trigger Condition 列**（最宽列，不是 Operators 列）弹下拉：don't care/high/low/rising edge/falling edge/edge，选 rising edge；Bus 信号才用 Operators 列。
6. 波形数据信号也要加：数据区（上半）工具栏第一个按钮（Add Signals）或 data_tree 右键菜单同样弹 Signal Selector，双击逐个添加；只加触发信号的话波形窗口只有一条线。
7. 设 Single Trigger 进等待状态（工具栏第一个图标按钮），条件满足自动抓；「de_2d 一直高」是正常现象——1024 拍窗口 < 一行 1280 拍，行有效期内持续高
8. 判读时用「内容首次非零拍 vs 输出首次生效拍」的坐标差

## 多实例（时钟域分组）与 Single Trigger 变灰（实测排障清单）
- **MARK_DEBUG 信号按驱动时钟自动分组**：新增标在另一时钟域的信号（如 bg_read 写侧三件套 @ I_ddr_clk）会新建 auto_created_cwc2 实例而非并入已有实例——界面左上实例下拉切换，各实例有独立数据树/触发树（实测：cwc1=写侧/DDR 域，时钟 u_rd_tag_fifo/clkw；cwc2=读侧/视频域，时钟 u_hdmi_mixer/I_clk）。验证某 .cwc 里有哪些信号：python 正则 `name="([^"]*S_[^"]*)"` 抓全部再按实例段归属。
- **调试核插敏感时钟域会黑屏：ChipWatcher 下载黑屏但 binWriter 下载正常 = 调试核激活问题，不是 bit 问题**。MARK_DEBUG 标在 DDR 域信号（如 bg_read 内部 @ clkw）时 TD 会给 DDR 域插一个 debug hub 实例；ChipWatcher 下载后激活该 hub 会把 DDR 域拖死（bg_read 读不出帧数据 → 画面全黑，按复位键从 Flash 载入旧 bit 才恢复）。判别：同一 bit 用 binWriter 下载画面正常、ChipWatcher 下载黑屏；时序报告全绿也黑 = 不是时序问题而是 hub 插域问题。修法：把调试信号挪到安全时钟域——被标模块把该信号引出为输出端口 → 目标模块（视频域）加输入端口打 2 拍跨域同步 → MARK_DEBUG 只标在打拍后的信号上（相位分析扣掉打拍数即可）；同时删掉原时钟域的 MARK_DEBUG 属性、保留打拍前的内部信号（功能逻辑不动）。重新编译后 cwc 里敏感域的实例消失，只剩安全域实例。
- **Single Trigger 变灰四件套检查**：bit 已下载（Status=Idle）→ 数据信号已加（Data Enable）→ 触发信号已加且 Trigger Condition 已设（rising edge）→ **当前停在对的实例页**（trigger_tree 元素名 = auto_created_cwcX_trigger_tree 可判断；在 cwc2 页设了触发却停在 cwc1 页 = 灰，点实例 tab 页签切回去）。前三点都满足仍灰时，第 4 点（实例页签）是头号嫌疑；用户报「该添加的都添加了」时优先查 Trigger Condition 列和实例页签。
- **下载 bit 后复位键行为以实测为准**：老经验「复位键→从 Flash 载入旧 bit、调试电路消失」在部分板态不成立——实测（shiyan6-8 抓取成功路径）「ChipWatcher 下载后黑屏（DDR 训练/初始化在下载后偶发失败）→ 按复位键 → 画面恢复且调试电路仍在、Single Trigger 可抓」。判别法：复位后画面正常时看 Single Trigger 是否仍可点（可点 = 调试内核还在 = 复位未重载 Flash；灰 = 被旧 bit 替换）。若复位后能抓，则「下载黑屏→复位→画面正常态抓取」反而是黑屏态抓不到数据（上游全死、写侧三件套全程 0）时的正确补救路径。仍不放心时优先 binWriter 下载同一 bit（不激活调试核）判画面，再走 ChipWatcher 下载+复位路径。**黑屏态抓的数据不可信**：视频域时序链（x_2d/de/col）可能照常跳但显示链/上游死——写侧信号全程 0 时先怀疑「黑屏状态下 bg_read 没跑」，别当「写侧无活动」下结论；画面正常态（复位后）抓的数据才是有效证据。
- **Signal Selector 信号比预期少**：先清搜索框（Name 输入框有过滤字符时只显示匹配项），再看模块分组树（u_bg_read / u_hdmi_mixer 两个分支）；实例下拉选错实例也只列出该实例信号。
- **打开的 .cwc 是旧版**（信号列表没新增信号）= prj/compiled.cwc 是上次编译残留——把 phy_1/cw/ 的 compiled.cwc/compiled.bit/compiled.data 三件套复制到 prj/ 覆盖后重新打开。
- 触发信号用 de 链任一版都行（de_1d/de_2d/de_3d 都是行首上升沿，差固定打拍关系可换算）。

## ChipWatcher 彻底修不好时的保底：盲调补偿（拨码选 k）
- 抓波形的目的是「把错位 k 变成实测数字」；若 GUI/hwserver 当晚修不好，改走盲调：把补偿做成参数化加法（读地址/坐标加 k），SW 拨码组合编码 k∈[0,15]（4 个拨码 16 档，临时占用功能拨码），一次编译装全部候选，下板拨码试错、按涂白位置二分收敛。错位是固定常数时此法可靠且省编译次数；帧间漂移时不适用（仍需波形追根因）。

## Eram Editor（读芯片 RAM 内容——写/读侧一把判定）
- Tools → Debug Tools → Eram Editor；点 ram list 加载 .bid 文件（phy_1/FPGACompetition_inst.bid 记录 Instance Name，Logic RAM 被拆块会列多个 syn_xxx 实例）
- 点 Logic 切 Logic RAM；选 Status 为 READABLE 的实例读数据；可存 .mif/.dat/.txt 回传分析
- 判读：RAM 内容本身偏移 = 写侧锅；内容位置正确但屏幕显示偏移 = 读侧锅——一次读 RAM 直接切分写/读两侧
- 与 ChipWatcher 受同一个 JTAG 占用坑影响

## 远程指导用户抓板（用户小白、界面不熟）
- 用户 GUI 截图用 tesseract OCR 读界面文字（-l chi_sim+eng），比口述准确
- 每个操作给「一图一步」傻瓜步骤；让用户卡哪步截图发哪步，OCR 后继续指
- **优先 cua-driver 接管 Windows 桌面自动化 TD**（Hermes 配 HERMES_CUA_DRIVER_CMD 指向 Windows 版 cua-driver，/reload 后 list_apps 可见 Windows 应用，见 computer-use 技能）：能可靠驱动 Qt 的 UIA Invoke 按钮（download_button、工具栏按钮）、读元素树；但 Qt 树双击打开、OK 按钮、单元格下拉是盲区——**混合模式**：盲区让用户手动点一下，其余全自动化，一次成功率最高
- 启动 TD 带工程：cmd.exe /c start "" "E:\TD_...\bin\td.exe" "E:\...\FPGACompetition.al"（start 会阻塞到 GUI 加载完，用大 timeout 或后台）；list_windows 里 TD 的 app_name 是 td.exe（不是显示名），capture 时 app="td.exe"
