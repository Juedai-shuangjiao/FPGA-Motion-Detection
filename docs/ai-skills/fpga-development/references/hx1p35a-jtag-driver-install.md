# HX1P35A 板载 JTAG 驱动安装（FTDI FT2232H → 安路 AL-Link FT）

## 背景
PH1P35 开发板（主控 PH1P35MDG324）板载 JTAG 下载器用的是 FTDI FT2232H 芯片 + 一片 EEPROM。
装驱动要做三件事：装 FTDI CDM 驱动 → 用 FT_Prog 刷 PID → 装 WinUSB 驱动。中间要插拔 USB 多次。

资料目录（Windows）：
`D:\Users\user\Desktop\FPGA比赛\板子资料\HX1P35A_Contest_202606\1_安路工具和软件\新版TD驱动PH1P35使用方法\`

关键文件：
- `（必看）PH1P35烧写程序的使用方法.pdf`
- `安路JTAG驱动安装_固件\操作流程.txt`
- `安路JTAG驱动安装_固件\安路刷下载驱动教程.pdf`
- `安路JTAG驱动安装_固件\al_link_ft_new.xml`（UTF-16 LE 编码，idProduct=6042，产品名 "USB-JTAG Cable"，SN前缀 ALFT）
- `安路JTAG驱动安装_固件\FT_PROG\CDM212364_Setup.exe`（FTDI 官方 CDM 驱动）
- `安路JTAG驱动安装_固件\FT_PROG\FT_Prog.exe`（FTDI 配置工具）
- `安路JTAG驱动安装_固件\UsbDriverTool\UsbDriverTool.exe`（驱动切换工具）
- `hwserver.exe`（复制到 TD bin 目录）

## 关键标识
- FTDI VID = 0403
- PID 6010 = FT2232H 原始默认（未刷，需要刷）
- PID 6042 = 安路专用（已刷好；装 FTDI CDM 驱动时 Windows 显示名是 "USB Composite Device (FTDI CDM)"，序列号 123456789，而不是 "USB-JTAG Cable"）
- 装好 FTDI CDM 驱动后设备名 = "USB Serial Converter A/B"（通用串行总线控制器下）+ "USB Serial Port (COMx)"（端口下）
- **关键坑**：PID 已刷成 6042 时，设备显示成 "USB Composite Device (FTDI CDM)"（Class=USB，在「通用串行总线控制器」下），不是 "USB Serial Converter A"。用户按「端口/其他设备」找会找不到，其实已经识别。此时跳过 FT_Prog，直接用 UsbDriverTool 换 WinUSB。

## 「找不到 USB Serial Converter A」排查
这个名字是 FTDI 驱动装好后才有的。找不到时先看设备管理器插拔后冒出来什么：

1. 完全无新设备 → 硬件问题：换数据线（非充电线）、换 USB 口、确认板子上电。
2. 「其他设备」黄色感叹号（FT2232H / USB Serial / 未知设备）→ FTDI 驱动没装，先装 CDM212364_Setup.exe。
3. 「通用串行总线控制器」已有 USB Serial Converter A/B → 驱动已装好，直接刷 PID。
4. 名字是 "USB-JTAG Cable" → 已刷好 PID，直接装 WinUSB。

查硬件 ID：右键设备 → 属性 → 详细信息 → 硬件 ID → 看 VID_xxxx&PID_xxxx。

## 完整流程
1. 装 FTDI CDM 驱动：运行 `FT_PROG\CDM212364_Setup.exe`，插拔 USB。
   （有残留错误设备先右键卸载 + 勾选删除驱动软件再重插。）
2. 刷 PID：
   a. 管理员运行 `UsbDriverTool\UsbDriverTool.exe`，选中 USB Serial Converter A，改成 FTDI CDM 驱动。
   b. 打开 `FT_PROG\FT_Prog.exe`，点放大镜扫描（扫不到就重新插拔 USB-JTAG 再扫）。
   c. 右键 Device:0 → Apply Template → From File → 选 `al_link_ft_new.xml`。
   d. 点闪电 ProgramDevice → Program 烧写。
   e. 拔插 USB。
3. 装 WinUSB：再用 UsbDriverTool，此时设备显示 "USB-JTAG Cable"(0403:6042)，右键装 WinUSB。
4. TD 识别：
   a. 复制 `hwserver.exe` 到 TD bin 目录（如 D:\Anlogic\TD_6.2.1_Engineer_6.2.168.116\bin）。
   b. TD 里点 AL-LINK-FT(Local Host)，Local port=5555，点刷新 → Apply and Close。
   c. 第一次刷新左上角可能不显示型号，重开界面再刷一次，显示 OCCUPIED 后等几秒即出 PH1P35。

## 支持器件与软件版本（2025年3月）
- PH1P35：TD_6.1.2_PH1P35_Release_150640
- PH1A-2A：TD_6.0.3_PHX_Release_152183
- DR1：TD_5.9.1_DR1_2025.1
- 双核 A35/RISCV 裸机：FD_2025.1
