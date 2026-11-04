# 下载器驱动/hwserver/ChipWatcher 修复（2026-11-01 实战验证）

## 症状链（可单独或组合出现）
- ChipWatcher 窗口标题带 `[read only]`，Single Trigger 灰，下载后板子黑屏
- `ERROR: host cast error: bad lexical cast: ... using default: 5555` 反复
- `ERROR: Connect server failed. / transfer failed / Chip validation failed / Downloading failed!`
- 设备管理器里 FTDI 设备 Unknown 或「USB Composite Device」、两个 MI 接口黄叹号（ProblemCode 28）

## 根因三层（都要查）
1. **USB 驱动层**：FTDI FT2232H（VID_0403&PID_6042，FriendlyName "USB-JTAG Cable"）被 Windows Update 顶成标准 USB Composite Device 兜底驱动，接口驱动装不上（ProblemCode 28）。
2. **hwserver 版本**：TD bin 里的 hwserver.exe 可能不配套；hwserver 活着但不监听 5555 = 打开 FTDI 通道失败。
3. **端口配置**：AL-LINK-FT 设置框 Local port 字段为空/损坏 → cast error 5555。

## 修复流程（按序）
1. **装 WinUSB 驱动**：板子资料目录 `D:\Users\user\Desktop\FPGA比赛\板子资料\HX1P35A_Contest_202606\1_安路工具和软件\新版TD驱动PH1P35使用方法\安路JTAG驱动安装_固件\UsbDriverTool\UsbDriverTool.exe` → 右键 VID 0403:6042 设备 → 安装 WinUSB。装完 Get-PnpDevice 查 Status 应为 OK、Class USBDevice。
2. **替换 hwserver**：同目录（新版TD驱动PH1P35使用方法/）官方 hwserver.exe → 复制到 TD bin 目录。注意：hwserver.exe 运行中被占用会复制失败——先关 ChipWatcher，任务管理器结束 hwserver.exe，原文件先备份 .bak，替换后 ChipWatcher 必须完全重启才用新 hwserver。
3. **端口**：ChipWatcher 里点 AL-LINK-FT(Local Host) → Local port 显式填 5555 → 刷新（官方 PDF 坑：一次刷新后左上角可能不显示型号，需重开该界面再刷一次，显示 OCCUPPIED 后等几秒出现芯片型号）→ Apply and Close。

## 判别事实（省时间）
- **binWriter 下载同一 bit 画面正常、ChipWatcher 下载黑屏 → bit 电路无问题**，是 ChipWatcher 下载/调试激活路径或上电初始化竞争（用户实测「第二次下载不黑屏」= 第一次配置时摄像头 I2C/PLL 初始化竞争失败）。
- JTAG 下载黑屏、复位后正常 → 复位是从 Flash 加载旧程序，画面正常的是旧版，不代表新版 bit 正常（Flash 内容需另行确认）。
- 查进程：tasklist 找 hwserver.exe/td.exe/bw.exe；bw.exe(binWriter) 占 JTAG 时 ChipWatcher 下载不上（先关 binWriter）。netstat -ano | grep 5555 验证 hwserver 监听。
- Windows 侧查设备：`Get-PnpDevice | Where InstanceId -match 'VID_0403'` 看 Status/FriendlyName；ProblemCode 28=驱动未装。

## GUI 编译 ddr2 black box 坑
- 报错 `ERROR: ddr2 is a black box in .../ph1p35_324_ddr_wrapper.v(78)` = **GUI 保存工程时把 .prj 和 .al 里的 ddr2.xml 引用清掉了**（会反复发生，每次 GUI 保存都可能再清）。
- 修复：在 syn_1/FPGACompetition.prj 与 phy_1/FPGACompetition.prj 的 PLL 块前插入 `<File Path="../../../src/hdl_source_ip/ddr2/ddr2.xml">` 块（CompileOrder 45，PLL 改 46，与 A 工程对齐）；GUI 读的 .al 里同样插入（注意 .al 路径前缀是 `../src/` 不是 `../../../src/`）。
- 用 patch 工具插 XML 时 diff 显示会误导（模糊匹配到相邻块），插入后必须人工 sed 核对最终 XML 结构是否完整（File 块成对、CompileOrder 无重复）。
- 命令行编译读 .prj；GUI 编译读 .al。两处都要修。GUI 打开工程后不要点保存（一保存又清）。

## 错位补偿方法论（B2 盲修路线）
- shiyan3 波形实测：位图 mark 首现 x=26、手真实 x≈15-20 → 写侧坐标系比视频坐标系超前约 6-11px → 涂白右错 8-9px。补偿 = 视频 x 处应查位图列 x-9，实现走组合相位层：col 链初值/行首复位从 0 改 34（≡提前 6，mod 40）+ 涂白条件用 mark_comb（比 mark_2d 再提前 2 拍）= 净左移 8px。
- TD retiming 会吃掉显式打拍（B v2 教训），补偿必须走组合逻辑常量（col 初值、常量加法），retiming 动不了。
- 业界同款案例：NeTV2（netv2-fpga issue #20）overlay 错位 = DRAM 批取与 sync 的相位（「DRAM fetches a group of pixels all at once, if the sync falls before/after the fetch」），官方修法 = line_align 微调寄存器（常数补偿）；MiSTer Arcade-Deco16 治本写法 = 每行 HSync 重置分组指针（「resynced to the write pointer at every HSync, never drifts」）。我们错位固定（每帧 172800 字=720 批整除 → 批相位每帧回同一点），常数补偿一次到位；若错位逐行扭斜才需要 HSync 重对齐治本。
