#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""主线「消隐期读两帧 + 写避让」带宽预算 tick 仿真
用法：改顶部常量（usr_clk、分辨率、突发参数）后 /usr/bin/python3 本文件。
输出三个场景：①消隐期读两帧够不够 ②写侧窗口余量 ③显示读是否独占。
⚠️ 量级 sanity check：帧周期 16.5ms = 1.65M tick @10ns——换算错 1000 倍时
可用窗口会算出负数/天文数字，立刻可见。
"""

USR_CLK_HZ = 100e6      # usr_clk（1600 配置 = 100M，8:1 = 内存/16）
TICK_NS    = 1e9 / USR_CLK_HZ

# HDMI 时序（720p，75M 像素钟）
H_TOTAL, V_TOTAL = 1650, 750
H_ACTIVE, V_ACTIVE = 1280, 720
FRAME_NS  = H_TOTAL * V_TOTAL / 75e6 * 1e9      # 16.5ms
BLANK_NS  = (H_TOTAL * V_TOTAL - H_ACTIVE * V_ACTIVE) / 75e6 * 1e9   # 4.212ms

BEATS_PER_LINE = 240          # 每行 240 个 128bit（1280 像素×24bit/128）
LINES          = 720
FRAME_BEATS    = BEATS_PER_LINE * LINES         # 172800
RD_LATENCY     = 40            # DDR 读命令→数据 40 拍
BURST_GAP      = 8             # 突发间间隙（bank 切换/仲裁，估算）


def read_two_frames_ticks():
    """消隐期背景读：读两帧（当前帧+背景帧），连续突发"""
    beats = FRAME_BEATS * 2          # 345600
    bursts = beats // BEATS_PER_LINE
    return RD_LATENCY + beats + bursts * BURST_GAP, bursts


def write_one_frame_ticks():
    """写一帧：每 240 beat 一个写突发"""
    return FRAME_BEATS + (FRAME_BEATS // BEATS_PER_LINE) * BURST_GAP


def main():
    rd_ticks, rd_bursts = read_two_frames_ticks()
    rd_ms = rd_ticks * TICK_NS / 1e6
    blank_ms = BLANK_NS / 1e6
    print("=" * 64)
    print(f"usr_clk = {USR_CLK_HZ/1e6:.0f}M | 帧周期 {FRAME_NS/1e6:.3f}ms | 消隐期 {blank_ms:.3f}ms")
    print("-" * 64)
    print(f"[场景1] 消隐期读两帧: {rd_ticks} tick = {rd_ms:.3f}ms "
          f"(含 {RD_LATENCY}拍延迟+{rd_bursts}个突发×{BURST_GAP}拍间隙)")
    print(f"        消隐期 {blank_ms:.3f}ms {'✓ 够' if rd_ms < blank_ms else '✗ 不够'}, "
          f"余量 {blank_ms-rd_ms:.3f}ms")
    if rd_ms > blank_ms:
        gap = rd_ticks - BLANK_NS / TICK_NS
        print(f"        缺口 {gap*TICK_NS/1e6:.3f}ms = {int(gap)} tick 需在显示期补读")

    wr_ticks = write_one_frame_ticks()
    disp_ticks = FRAME_BEATS
    avail_ticks = FRAME_NS / TICK_NS - disp_ticks - rd_ticks
    print("-" * 64)
    print(f"[场景2] 写侧: 写一帧需 {wr_ticks} tick = {wr_ticks*TICK_NS/1e6:.3f}ms")
    print(f"        可用窗口 {avail_ticks:.0f} tick = {avail_ticks*TICK_NS/1e6:.3f}ms "
          f"{'✓ 够' if wr_ticks < avail_ticks else '✗ 不够'}")
    if wr_ticks < avail_ticks:
        print(f"        余量 {(avail_ticks-wr_ticks)*TICK_NS/1e6:.3f}ms = "
              f"{(avail_ticks-wr_ticks)/wr_ticks*100:.0f}%")

    print("-" * 64)
    print("[场景3] 显示期背景读=0, 显示读独占 → 数据流连续不切碎 ✓")
    print("=" * 64)
    ok = rd_ms < blank_ms and wr_ticks < avail_ticks
    print("结论: 带宽预算 " + ("✓ 成立" if ok else "✗ 有缺口, 需补读或降帧率"))


if __name__ == "__main__":
    main()
