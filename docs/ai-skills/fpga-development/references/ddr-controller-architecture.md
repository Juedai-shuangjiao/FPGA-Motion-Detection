# DDR 控制器架构（PH1P35 视频流工程的片内 DDR 访问）

> 调研时间 2026-10-17。用途：在「摄像头→DDR→HDMI」这条视频流上**加一路 DDR 访问**（如背景减除的背景读写、动态跟踪的帧缓存）时的施工参考。

## 数据流
```
摄像头 MIPI → demosaic → RGB(96位/4像素) → video_in(写DDR) → DDR → video_out(读DDR) → HDMI
```

## DDR 控制器（ph1p35_324_ddr_wrapper.v）
- **单路 AXI 用户接口**（`I_mc_app_*`）：25 位地址 `I_mc_app_addr` + 3 位命令 `I_mc_app_cmd`（cmd[0]=1 读 / 0 写）+ `I_mc_app_en` + 128 位数据 `I_mc_app_wdf_data` / `O_mc_app_rd_data`。
- 就绪/有效：`O_mc_app_rdy`（= arready||awready）、`O_mc_app_rd_data_valid`。
- 例化 IP 名 `ddr2`（米联客命名，实际是 **DDR3**，别被名字误导）。
- DDR3 物理信号：`ddr_dq[15:0]`（16bit）、`ddr_dqs_p/n`（差分选通）、`ddr_ck_p/n`（差分时钟）、`ddr_ba[1:0]`、`ddr_addr[12:0]`。

## video_in（写 DDR）
- 跨时钟域 FIFO（摄像头时钟 → DDR 时钟，w128_d512_fifo）+ 写突发（**FIFO 攒够 240 个 128 位才写**，写 240 个停）。
- **4 块乒乓缓冲区**：`IMAGE_BASE_ADDR_0~3 = 0 / 7000000 / 14000000 / 21000000`（25 位地址，地址每次写 +8）。
- 写指针 S_video_in_wp 每帧 +1；读指针 O_video_out_rp 跟写指针**错开 2**（乒乓，避免读写同一块）。
- 写使能条件：`FIFO攒够240 && !video_out_rd_busy && !跳帧`。

## video_out（读 DDR）
- 读突发（240 个 128 位/次）+ 跨时钟域 FIFO（DDR 时钟 → HDMI 时钟）+ 128→24 解包（128 和 24 最小公倍数 384，每 3 个 128 位 beat = 16 个 24 位像素）。
- 读使能条件：`FIFO剩余>=300 && !video_in_wr_busy`。

## 仲裁（现状 = 2 路 busy 互斥，无优先级调度器）
- video_in 写：`!I_video_out_rd_busy` 才写。
- video_out 读：`!I_video_in_wr_busy` 才读。
- 一个时刻只有一路访问 DDR，靠互相避让。

## 加第三路访问（如背景读）的套路
1. **加第 5 块缓冲区**：`IMAGE_BASE_ADDR_4 = 28000000`（背景/额外数据专用）。
2. **新建 bg_read 模块**：读突发（照抄 video_out）+ 跨时钟域 FIFO（DDR 时钟 → 摄像头时钟）+ 128→96 转回（给减背景用）。
3. **3 路互斥**：优先级 `video_out 读（显示不能断）> video_in 写（采集不能丢）> 背景读写（可等待）`。
   - 背景读写用**低优先级**：只在 `!video_in_wr_busy && !video_out_rd_busy` 时做，利用显示读写之间的空闲时段，不引入复杂调度器。

## 带宽账（16-bit DDR3 = 17Gbit/s，够用）
| 用途 | 带宽 | 占比 |
|---|---|---|
| video_in 写（显示） | 2.6 Gbit/s | 15% |
| video_out 读（显示） | 2.6 Gbit/s | 15% |
| 背景读（RGB 8bit 全分辨率 22Mbit×60fps） | 1.3 Gbit/s | 8% |
| **合计** | ~6.5 Gbit/s | **~38%** |

## 关键文件位置
- `src/hdl_source_clean/video_in.v` —— 写 DDR + 跨时钟域 FIFO + 乒乓（背景写照抄它）
- `src/hdl_source_clean/video_out.v` —— 读 DDR + 跨时钟域 FIFO + 128→24（背景读照抄它）
- `src/hdl_source_clean/ph1p35_ddr/ph1p35_324_ddr_wrapper.v` —— DDR 控制器 AXI 接口（单路）
- `src/hdl_source_clean/design_top_wrapper.v` —— 顶层（加仲裁 + 连接）
