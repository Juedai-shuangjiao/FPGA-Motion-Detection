# 消隐期读 + 前景标记片内（全分辨率 1×1 运动检测）

PH1P35 竞赛项目「运动检测背景减除」的最终方案：不再跟显示读三路抢 DDR，改成「消隐期读当前帧+背景、算前景标记存片内 ERAM，有效期间显示叠加」。本文是 2026-10-21 会话的踩坑沉淀。

## 方案核心

- 前景标记 = 1bit/像素，1280×720×1 = 921600 bit，片内 ERAM 2.16Mbit **放得下**。
- 存储：40bit 宽 × 23040 深 = **45 块 ERAM**（512×40 配置）。⚠️ 深度直接填 `23040`，勿取 2 的幂 32768（会浪费到 64 块）。原理同「RGB 4bit 从 65535 砍 57600 省 3 块」：信息量 921600bit = 45 块×20480bit 完全匹配，零浪费。
- 数据流：消隐期 bg_read 一路读（交替读当前帧块 + 背景块）→ 分块相减 → 前景标记写 ERAM；有效期间显示读 + 读 ERAM 叠加涂白。DDR 在消隐期/有效期间天然错峰，不三路竞争。

## ERAM 资源验证：TD 压缩恒 0 位（debug 图案的 EMB 偏乐观）

40bit×23040 理论 45 块（23040=45×512 精确整除），但用 debug 自检图案（写数据 {addr,5'd0,addr,5'd0}，两个 5'd0 段恒 0）编译后 EMB 实测只增 **34 块**——TD 把写入数据中恒为 0 的位段优化掉不占存储（syn 日志 `SYN-2593 optimized to a new one with A-width N due to unused data out` + `SYN-1001 Optimize constant input of erams`，40bit 压缩成 30bit），读回自动补 0、功能完整，不是 bug。⚠️ **用测试图案评估 ERAM 资源会偏乐观**：正式前景标记（40 位全动态）才实占 45 块，资源预算要以正式数据口径验证。

## 时间预算（⚠️ 纠正文档「消隐期 12.83ms」错误）

- 720p60 消隐期 = H_FrameSize×V_FrameSize − 1280×720 = 1650×750 − 921600 = **315900 像素 @75M = 4.2ms**。文档写的「12.83ms」是**有效显示时间**，不是消隐期。
- 读两帧（当前+背景）= 345600 个 128bit（一帧 172800 = 1280×720×96/128）：
  - 满速 1066（usr_clk 133.3M）2.59ms ✅ 余量 1.6ms
  - 800Mbps（usr_clk 100M）3.46ms ✅ 余量 0.75ms
  - 半速 533（usr_clk 66.67M）5.18ms ❌ 读不完
- usr_clk = DDR_SPEED/8（PLL0 顶部注释 C0）；内存时钟 C2 = DDR_SPEED/2。

## 满速 1066 配置（半速 → 满速的最小改动）

- `ddr2.v`：`PLL0_REFCLK_FREQ` 50.0 → 100.0（其他参数 tCK=1876 / CL=7 / CWL=6 / PLL0_FBKCLK_DIV=32 已经是满速值，不用改）。
- 顶层加 `PH1P_LOGIC_IBUF_DIFF`（`DIFF_TERM="TRUE"`，实例名 `u_ddr_ref_clk_ibuf`，顶层端口 `I_ddr_ref_clk_p/n`），DDR ref_clk 接 SIT9121 差分晶振（K5/L5）。
- `pin.adc`：K5/L5 用 **IOSTANDARD = LVDS18**（不是 LVDS、不是 DIFF_SSTL15 —— 从之前满速综合日志 `RUN-1002 start command "set_pin_assignment ... LVDS18"` 反查得到）。
- `timing.sdc`：`create_clock -name ddr_ref_clk_100m -period 10.000 [get_ports I_ddr_ref_clk_p]`。
- IBUF_DIFF 对 ddrio 引脚会报 `can't config diff term` CRITICAL-WARNING（DIFF_TERM 不生效），但 ref_clk 裸跑能锁住，不影响。

## 加裕量优化（hdmi_mixer Logo 路径）

满速下最差 setup 路径 SWNS 104ps 在 hdmi_mixer 的 Logo 地址计算 `S_logo_addr = (S_y_2d-LOGO_Y)*160 + (S_x_2d-LOGO_X)`（DSP 乘法 mult0 + 6400 行 case 查表 + fanout 367，路径 12.8ns，net 占 52%）。

优化两招（保持「比坐标晚 3 拍」对齐不变）：
1. `*160` 改移位加法 `(y<<7)+(y<<5)`（160=128+32），甩掉 DSP 乘法器。
2. Logo 地址打 1 拍（`S_logo_addr_d1 <= S_logo_addr`），并把地址计算从 `S_x_2d/S_y_2d` 改用 `S_x_1d/S_y_1d`（提前 1 拍，抵消打拍延迟，对齐不变）。

效果：HDMI 域 104ps → **383ps**（3.7 倍），全局最差变成 DDR MC IP 内部（`u_alc_mc_top/page_ctrl`，加密 IP）的 259ps（改不了，但比之前记录的满速 7ps 好）。

## 位序真相（128↔24bit 打包解包，花屏定位关键）

- `data128_96`（demosaic 128→96）：`O_tdata = {I_tdata[23:0], I_tdata[55:32], I_tdata[87:64], I_tdata[119:96]}` → **96bit [23:0]=像素0(最左)，[95:72]=像素3(最右)**。
- 打包 `data_96bit_to_128bit`：128bit[0] = {96bit[0], 96bit[1][95:64]}，即 [127:32]=96bit[0]，[31:0]=96bit[1][95:64]。
- video_out 的 128→24 解包**从 [127:104] 高位拆**（cnt0→data[127:104]）→ 输出「每 4 像素反序」，靠后面坐标打拍抵消（所以画面正常，不是 bug）。
- 最右列 x=1279 = 一行的**最后一个 128bit（第 240 个）的 [23:0] 段**（行末尾边界，花屏嫌疑点，尚未 100% 坐实）。

## w128_d512_fifo 读时序

`OUTREG_EN="NOREG"` 但 ram_infer 里 `assign dob = (REGMODE_B=="OUTREG") ? dob_tmp2 : dob_tmp`，而 dob_tmp 是 `posedge clkb` 读寄存器 → **NOREG 实际有 1 拍延迟（re 后 1 拍 dout 有效）**；OUTREG 才是 2 拍（dob_tmp2 再打 1 拍）。仿 FIFO 读时序别想当然当「纯组合」或「2 拍」。

## 验证方法（用户明确偏好，重要）

- 验证 Verilog 逻辑用 **iverilog 仿真真实 RTL**（例化工程里的模块，如 data_96bit_to_128bit + data_128bit_to_96bit），**不要用 Python 复现逻辑** —— Python 复现是「重新实现一遍 RTL」，会引入复现错误，结果不可信（本次 Python 复现出「全反序」，跟画面正常矛盾，被用户纠正）。
- 验证打包/解包往返：输入「递增像素值」（96bit[k] 的 4 像素 = 4k+0..4k+3），例化真实打包+解包，对比输出个数和值，验证「无损」。实测「96→128→96」往返 320 进 320 出、错误 0，带行消隐也无损。
- 复刻「内联」逻辑（如 video_out 的 128→24 解包）做 testbench 时，时序对齐极易错（FIFO 读延迟 + 打拍 + 反序抵消），输出会「全错/全 0」跟真实画面矛盾 —— 这是复刻不对的信号，优先改成直接例化真实模块验证。
