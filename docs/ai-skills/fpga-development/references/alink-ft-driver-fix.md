# AL-LINK-FT 下载器 / ChipWatcher 连接故障修复流程（实测验证）

## 症状链
ChipWatcher 报 `host cast error ... default: 5555`、`Connect server failed`、窗口标题 [read only]、Single Trigger 灰——全部指向 JTAG 服务层，与 bit 无关。

## 分层排查
1. 进程：`tasklist | grep hwserver`——hwserver 必须活着且只有一个实例（双实例=僵尸冲突）。
2. 端口：`netstat -ano | grep 5555`——hwserver 监听 0.0.0.0:5555；连接后 CLOSE_WAIT/FIN_WAIT_2 = 服务挂了。
3. USB：`Get-PnpDevice | ? InstanceId -match 'VID_0403'`——AL-LINK-FT 是 FTDI FT2232H（VID_0403&PID_6042）。Status Unknown/Error（ProblemCode 28）= 驱动掉。
4. binWriter 能下载但 ChipWatcher 不能 = 硬件链路 OK、软件服务层坏。

## 修复三件套（缺一不可，官方文档《（必看）PH1P35烧写程序的使用方法.pdf》原文）
驱动与工具路径：`D:\Users\user\Desktop\FPGA比赛\板子资料\HX1P35A_Contest_202606\1_安路工具和软件\新版TD驱动PH1P35使用方法\`
1. **装 WinUSB 驱动**：运行 `安路JTAG驱动安装_固件\UsbDriverTool\UsbDriverTool.exe`，对 ID 0403:6042 的设备右键「安装 WinUSB」（不要用 FTDI CDM，不要走 Windows 自动搜索——会把驱动装坏）。
2. **替换 hwserver**：把板子资料里的 `hwserver.exe` 复制到 TD bin 目录（E:/TD_6.2.1_Engineer_6.2.168.116/bin/）覆盖——TD 自带的版本连接即断。复制前先关 ChipWatcher 并结束 hwserver 进程，否则文件被锁。
3. **填端口**：ChipWatcher 里点 `AL-LINK-FT(Local Host)` 按钮 → Local port 字段显式填 5555（空字段是 cast error 来源）→ 刷新 → Apply and Close。

## 官方文档记录的坑
- 点一次刷新后左上角可能不显示器件型号：重新点开 AL-LINK-FT 界面再刷一次，显示 OCCUPPIED 后稍等几秒即出现型号。
- 每换一次 hwserver/驱动，必须完全重启 ChipWatcher 才生效；read only 消失 = 服务层就绪。
- 用户升级驱动时 Windows Update 会把 WinUSB 顶成标准复合设备驱动，binWriter 都会失效——用 UsbDriverTool 重装 WinUSB 恢复。

## SC500CS 手册关键事实（《SC500CS_数据手册_V1.8.pdf》）
- 像素阵列 2600×1952，Active Array 2592×1944，四边各有 4 列/行 Active Border。
- 720p60 例程 crop：窗口宽 0x0500=1280，列起始 0x3210=0x0200=512（有效区内居中截取，行数据无 padding/前瞻像素）。
- 每行 RAW10 = 100×128bit 整除、ISP 输出 240×128bit 整除——打包层无行首偏移。
- 结论：行数据 = 100% 有效像素；错位排查时传感器/打包层可排除。
