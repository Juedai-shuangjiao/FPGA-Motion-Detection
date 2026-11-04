# 字节流 UART 发送器设计模式（含全部时序坑）

适用：FPGA 造低速外发链路（UART/SPI 类串行协议）把大数据量流式送出——如把 DDR 背景缓冲原始数据发 PC 离线分析。

## 正确架构（三个要素）
1. **UART 移位器**：sr = {stop, data, start}，装载拍 line 立即发 start，bit_cnt 从 10 计数；每个 baud 周期（baud_cnt 数满分频值）发 sr[1] 并右移 {1'b1, sr[9:1]}。bit_cnt 数满 10 个周期才回空闲——保证 start 8 data stop 每段都是完整 1 bit。
2. **装载确认握手（ld_ack）**：UART 在装载拍（bit_cnt==0 且 tx_load）输出 1 拍 ld_ack 脉冲。发送状态机等 ld_ack 才推进字节计数——每字节流程 = idle 拍发起 tx_load → 下拍 UART 装载并 ld_ack → 状态机推进 → 发完 1 字节后重新发起。
3. **发送状态机三段（头/数据/尾）**：每段推进条件只有 ld_ack；发起条件 = uart_idle && !tx_load（tx_load 沿前值——上拍已发起未确认时本拍不得再发）。

## 时序坑（每个都让字节流错位/丢字，逐个对照检查）
- **start 位重复**：装载拍 line<=0 发了 start，若第 1 个 baud 周期又发 sr[0]（=start）→ 前导 0 双倍宽，接收端全乱。正确：装载拍发 start 后，每个 baud 周期发 sr[1]（sr[0] 是 start，不发）。
- **stop 位被压成 2 拍**：第 9 周期发完 stop 置 bit_cnt<=0，状态机在下一拍就发起下一字节装载 → stop 只剩 2 拍（接收端容不下）。正确：bit_cnt 装载 10，第 9、10 周期都发 1（双 stop）——接收端按 start 下降沿同步，双 stop 完全兼容，代价仅每字节多 1 bit 时间。
- **组合 ready 与装载差 1 拍**：状态机用组合 uart_idle（bit_cnt==0）发 tx_load，而 UART 在下一拍才采样 tx_load——组合 ready 在装载拍仍为 1，状态机连发 tx_load → 后续字节被 bit_cnt≠0 吞掉（字节打飞、头字节只发 1 个）。正确：握手信号必须是 UART 输出的 ld_ack 脉冲，不是组合 ready。
- **「提前发」丢字（shifter 右移竞态）**：装载确认拍（ld_ack 沿后 1 拍）状态机还满足 uart_idle（bit_cnt 沿前仍是 0）→ 又发一字节、shifter 右移、sh_cnt 减 1，但 UART 已在移位不会收它 → 该字节永远丢失（数据流里周期性地少 1 字节，表现为每 N 字节错位）。正确：发起条件加 !tx_load（沿前值），装载确认拍 tx_load 沿前 =1 → 抑制。
- **FIFO re 双拍脉冲（弹两字）**：re 置 1 拍后，re_d1 尚未置位且状态机条件仍真 → 下一拍又 re → 队首字被弹掉没人读。正确：re 条件加 !re（沿前值，单拍脉冲），或干脆不用自造 re_d1，直接用 FIFO IP 的 valid 信号装载（valid 与 dout 同拍对齐）。
- **仿真 FIFO 与 TD 硬 IP 语义相反**：软逻辑 FIFO（soft_fifo_al 类）dout/valid 是组合读（valid=!empty 恒 1、re 拍立即出数）；TD 综合的 BRAM 硬 IP 是 NOREG（re 后 1 拍 dout+valid）。RTL 按硬件语义写（valid 拍装载），tb 里用 10 行 NOREG stub 替代软 IP——stub：`valid_q <= re && !empty; dout_q <= mem[rptr]; if(re) rptr++`。用软 IP 仿真硬件语义的 RTL，表现 = 装载永远取到队首后一个字（数据整体错 1 字）。
- **FIFO 装载与发送同拍竞态**：装载 shifter<=dout 与发字节 shifter<=右移若同拍发生，非阻塞后者覆盖前者 → shifter 回跳但 sh_cnt 已减。装载拍用 !valid 门控发送，或装载优先于发送。

## 协议与系统层
- 帧格式：头 magic 4B（如 AA 55 53 4E）+ 数据 + 尾 magic，整周期循环重发——PC 端随时开串口监听，按头 magic 对齐切片即可，不需要握手/重传。
- 使能上升沿重置整机（帧序号、字节计数、FIFO 清空、状态机回头发状态）——否则残留数据/半周期错位；未使能时发送机完全静止（防复位后预发帧头）。
- 慢链路发送大缓冲：每帧只 tap 一个窗口（如 4KB/帧）写小 FIFO，N 帧发完全量——FIFO 深度 ≥ 单帧窗口 + 1 帧发送余量即可，不需要整帧缓存。

## 验证方法（tb 调试优先级）
- **先打印 DUT 内部字节序列**（ld_ack 拍打 tx_byte），一眼看出丢字/错位——比 tb 监测器解析位流、VCD 波形数边沿快一个数量级。tb 监测器（@(negedge tx)+#750 采样）会因 2 拍毛刺/采样漂移自己丢字节，别先怀疑 DUT。
- $time 单位 = timescale 时间单位（1ns），比较窗口按 ns 写（14000000 是 14ms 不是 14us）。
- tb 驱动循环里 valid 类信号必须每拍显式清 0（@(negedge clk) v=1; @(negedge clk) v=0），否则恒 1 → 每个数据被采多次，表现像数据重复/间隔错位。

## 编译管线配合
TD 在编译启动的 import 阶段读 .v/.al/.prj——**编译启动后再改源文件/工程文件不进当前 bit**。新功能在编译进行中开发时，明确标记进下一轮编译；bit 出来后验三连立即接下一轮，不要等。
