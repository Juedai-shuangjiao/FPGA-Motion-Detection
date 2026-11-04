# 安路 TD「下载成功但程序不跑」排查

## 触发场景
用户报「下载报成功（Downloading succeeded / Chip validation success），但板上现象不对（LED 全亮 / 不动 / 跑的不是自己的程序）」。FPGA 入门高频，别急着改代码，按下面顺序排查。

## 第一优先：验证下载的 bit 内容到底对不对
「下载成功」≠「bit 内容正确」。直接读编译产物：

- `*_Runs/best_result/*_phy.area`：最直接的引脚分配表，格式：
  ```
  Name     Direction    Location    IOStandard    IOType    DriveStrength    PullType
  clk        INPUT         C4        LVCMOS33      HDIO          N/A          PULLUP
  rst_n      INPUT         D5        LVCMOS33      HDIO          N/A          PULLUP
  led[3]     OUTPUT        D6        LVCMOS33      HDIO           8            NONE
  ```
  看 Location 一列，确认引脚约束真的编译进去了（TD 软件里随机/默认分配的引脚是假的，不可信）。
- `*_Runs/phy_1/*.prj`：工程配置（Family / Device / Speed / TOP_MODULE / 源文件引用），确认器件和顶层模块对。
- `*_Runs/phy_1/place.qor`：Setup WNS > 0 = 时序满足。

## 第二优先：分析编译日志时间线
看 `prj/log/td_*.log`：
- 只有 `import_db ..._pr.db` + `Import design success`，没有 `Run syn_1 success` / `Run phy_1 success` → 这次只是「导入旧数据库 + 下载」，**没重新编译，下的是旧 bit**。
- 用文件时间戳对照：源码 `.v` / 约束 `.adc` 的 mtime vs `.bit` 的 mtime，源码比 bit 新 = 改了代码没重编。
- 大量 `HDL-8007 ERROR`（模块名以数字开头、端口名前后不一致 rest_n/rst_n、变量未声明）= 编译阶段语法错误；反复改到 `Run syn_1 success + Run phy_1 success` 才算真编过。

## 关键认知：JTAG SRAM 下载 vs Flash 固化
- `-mode jtag` 下载到 SRAM：**掉电丢失**。下载成功应立即运行（米联客实测「下载成功流水灯立即运行」，不需要额外复位）。
- 断电重开必然跑 Flash 里的程序（出厂程序或之前固化的），这是正常现象，不是故障。
- 固化到 Flash：Mode 选 PROGRAM_FLASH，固化后**断电重启**才生效。
- **.bit 可直接下 Flash，不需要 .hex**：官方开发板手册（`板子资料/HX1P35A_Contest_202606/9_康芯开发板使用手册及实验平台/新HX1P35A开发板手册-HDL版2604.pdf` 第 10 页）原文「JTAG 接口可将编译好的 .bit 下载到 FPGA，或加载到掉电保护的 FLASH 中，上电后 FPGA 读 FLASH 中 bin 配置运行」。流程 = 下载工具切「Program Flash」模式 → 选 .bit → 选 Flash 型号（**开发板用 N25Q128，128Mb QSPI；用户自设计板须按板上 Flash 丝印选型**）→ 下载 → 断电重启。.hex 只在 BitWizard 的 Create Flash File 合并多文件时才用。
- **板子资料导航坑**：`1_安路工具和软件/新版TD驱动PH1P35使用方法/（必看）PH1P35烧写程序的使用方法.pdf` 名为「烧写程序使用方法」，内容只是 AL-LINK-FT JTAG 驱动安装（UsbDriverTool 刷 WinUSB + hwserver.exe 放 TD bin），**不含 Flash 固化**。
- 本项目用户（开发者）此前一直用 SRAM 模式下载看效果，从未固化过 Flash——「上电自启」不意味着 Flash 里有用户 bit。

## 现象判读
- **「现象与上一版一模一样」→ 先怀疑 bit 根本没换，再怀疑代码**：三个高频原因按序查——① 下载工具缓存了旧文件路径（工具开着时改 bit 文件，直接点下载下的是旧文件，必须重新 File→Open 选新文件）；② bit 文件在重新编译期间被清缓存删掉了（下载时报文件不存在/打开失败）；③ 下载本身失败而用户没注意到提示。验证 = 让用户报下载工具里文件的时间戳/md5（`md5sum` 新旧两次 bit 内容不同才可能现象不同）。
- LED 全亮 = FPGA 引脚默认高电平 = **配置没生效 / 没启动**（流水灯代码只输出单热码，不可能全亮）。
- LED14 是电源指示灯，一直亮，与程序无关，别被误导。
- 下载耗时异常长（如 274 秒）→ 下载速度档（`-spd`）太慢，慢速下载易「报成功但配置没起」，把 spd 调大重下。

## 排查动作（按序）
1. 调高下载速度（spd 往大调）重新下载，下载完**别断电**，盯现象。
2. 下载完按一下复位键（KEY1）看有无变化。
3. 对照实验：下载康芯官方验证过的 bit（`板子资料/HX1P35A_Contest_202606/2_Example/0_cnt1s/cnt1s_Runs/best_result/cnt1s.bit`，功能 1s 全亮全灭闪烁），区分「bit 问题」还是「下载链路问题」。

## WSL 下直接查 Windows 设备枚举（比让用户截图更可靠）
WSL 里可直接调 PowerShell 查设备管理器，确认 FTDI 等 USB 设备是否被识别：
```bash
powershell.exe -NoProfile -Command "Get-PnpDevice -PresentOnly | Where-Object { \$_.InstanceId -match 'VID_0403' } | Format-List Status, Class, FriendlyName, InstanceId"
```
- bash 里 `$_` 必须写成 `\$_` 防 bash 展开。
- 查所有 USB 类设备：`Get-PnpDevice -PresentOnly -Class USB | Format-List Status, FriendlyName, InstanceId`。
- InstanceId 里的 `VID_xxxx&PID_xxxx` 是 ASCII；中文 FriendlyName 可能乱码但不影响判断。
- 这招对「找不到 USB Serial Converter A」之类的问题，比让用户发设备管理器截图（还常遇到 vision 工具读不了图）快得多、准得多。
