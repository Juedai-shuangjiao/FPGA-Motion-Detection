# HX1P35B 竞赛板事实清单（原理图/资料调研结论）

板子 = HX1P35B（芯片 PH1P35MDG324 合封 DDR），资料目录 D:\Users\user\Desktop\FPGA比赛\板子资料\HX1P35A_Contest_202606。

## 串口（收数据到 PC 的关键链路）
- uart_tx = FPGA 引脚 H1（bank21 IO_BE2P_21，LVCMOS33）、uart_rx = J1（IO_BE2N_21）。与官方例程 2_Example/16_uart_rs232/uart_test.adc 引脚一致。
- 板载 USB 转串口芯片 = CH340（5_软件工具及驱动/CH340驱动(USB串口驱动)）；官方上位机 = 1_安路工具和软件/Uart_Plot上位机软件（pyserial_display 打包版，numpy 绘图）。
- Windows 侧查串口状态：Get-PnpDevice -Class Ports（COM3/4 是蓝牙串口 BTHENUM，别认错）；CP210x VID_10C4 是外接小板不是板载。WSL 无 /dev/ttyUSB* 时用 usbipd 挂载或 Windows 侧 pyserial 收。
- 板子 USB 口只有下载器一个；原理图页：3=芯片 bank21/42（SD/蜂鸣器/数码管/MIPI CSI）、6=J1/J2 IDC40 排针（GPIOA/B 各 33 脚带 ESD）、7=HDMI、8=DDR、9=以太网 PHY。pdftotext 抓不到网络标签时找连接器直接翻对应页文本。

## 官方例程索引（2_Example/）
0_cnt1s 呼吸灯、10_PLL_TEST、11_Di_TRemble、12_MUL_4B、13_music、14_ps2_piano、15_VGA、16_uart_rs232、17_DC_MOTO、18_sd_card_audio、19_ball_top。

## 工具链
TD 6.2.1（E:/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe 批处理编译）；编译命令 cd prj/FPGACompetition_Runs/syn_1 && cmd.exe /c "...td_commands_prompt.exe FPGACompetition.tcl"。
