# 运动检测 DDR 改造（PH1P35 合封 DDR3 存背景）

> 目标：背景减除从「片内 ERAM 320×180 降采样」升级到「合封 DDR 全分辨率 1280×720」。
> 阶段 1（2026-10-18）已完成：背景写 + bg_read + 3 路仲裁，编译通过（ERAM 95/108、SWNS 0.105ns）。

## 现有 DDR 架构（改造前的调研结论）

- DDR 控制器 `ph1p35_324_ddr_wrapper` 是**单路 AXI 用户接口**（`I_mc_app_*`：25 位地址 + 3 位 cmd + 128 位数据），例化的 IP 叫 `ddr2`（米联客命名，实际是 DDR3 16bit）。
- `video_in`（写）+ `video_out`（读）通过 **busy 互斥**共享这单路接口：video_in 写触发条件 `!video_out_rd_busy`，video_out 读触发 `!video_in_wr_busy`。
- 4 块乒乓缓冲区：`IMAGE_BASE_ADDR_0~3 = 0 / 7000000 / 14000000 / 21000000`（25 位地址，每块相隔 700 万）。
- 顶层合并（design_top_wrapper.v）：`S_ddr_user_addr = 写使能 ? 写地址 : (读使能 ? 读地址 : 0)`，写优先；`S_ddr_user_wr_en/rd_en` 直通。

## 阶段 1 改动清单（已完成）

1. **motion_detect.v**：加 `O_bg_capture` 输出（把 bg_capture 采集标志引出去，覆盖完整一帧）。
2. **isp_top.v**：加 `O_bg_capture` 透传 + motion_detect 例化连接。
3. **video_in.v**：加背景写——`I_bg_capture` 跨时钟域打 3 拍同步 → `bg_capture_ddr`；采背景帧写地址重定向 `IMAGE_BASE_ADDR_4=28000000`、写指针不动（`if(... || bg_capture_ddr)`）。
4. **bg_read.v（新建）**：自由循环读背景（读地址读完一帧 230400 个回起始）+ 跨时钟域 FIFO（w128_d512_fifo，soft FIFO 不占 ERAM）+ 输出 128 位背景。
5. **design_top_wrapper.v**：加 bg_read 例化 + 3 路合并（`S_ddr_user_rd_en = S_vo_ddr_rd_en || S_bg_rd_en`、地址复用 3 选）+ busy 互斥（video_in/video_out 的 busy 输入都加 `|| S_bg_rd_busy`）。
6. **.al**：bg_read.v 加进 `<Verilog>` 段，CompileOrder=76。

## 关键坑：仲裁竞态（已修复）

3 路互斥的 busy 信号是组合判断对方 busy，会「同时触发」竞态——video_in 写和 bg_read 读同时触发时，合并逻辑写优先、bg_read 读地址被写地址覆盖、读错整个突发。

修复：bg_read 读使能「当前拍避让」：
```verilog
assign O_ddr_user_rd_en = S_rd_valid & I_ddr_user_ready &
                          (!I_video_in_wr_busy) & (!I_video_out_rd_busy);
```
读在 video_in 写/video_out 读忙时暂停（S_rd_cnt 不递增）、空闲再继续。

## 阶段 2 待做（真正吃 DDR 红利的一步）

1. **128→96 转换**：bg_read 输出 128 位背景，当前帧是 96 位，需「跨 beat 拼接」转 96 位（4 像素 RGB），类似 video_out 的 128→24 解包但输出 96 位。
2. **延迟对齐**：背景读有 DDR 读延迟（~40 拍）+ FIFO，当前帧有 demosaic/AWB 延迟，需「当前帧打 N 拍」对齐背景（N 需下板调）。
3. **motion_detect 去降采样**：删 320×180 降采样 + 3 块 4bit 背景 BRAM，改全分辨率 RGB 减背景。
4. 保留：闭运算、SW4 采背景、时间滤波（可选）。

## 关键文件

- `src/hdl_source_clean/video_in.v` / `video_out.v` —— 写/读 DDR 框架（背景写/读照抄）
- `src/hdl_source_clean/ph1p35_ddr/ph1p35_324_ddr_wrapper.v` —— DDR 控制器单路 AXI 接口
- `src/hdl_source_clean/isp/motion_detect.v` —— 背景减除（阶段 2 去降采样改造对象）
- `src/hdl_source_clean/bg_read.v` —— 背景读（阶段 1 新建）
- `src/hdl_source_clean/design_top_wrapper.v` —— 顶层（3 路合并 + 仲裁）
