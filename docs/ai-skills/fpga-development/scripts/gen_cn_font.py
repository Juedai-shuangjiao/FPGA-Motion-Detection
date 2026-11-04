#!/usr/bin/env python3
"""
中文字模生成：把中文字符渲染成 16x16 点阵，输出 Verilog case 表（osd_cn_char 模块用）。

用法：
  1. 改下面 chars 字符串为要生成的字（中文 + 标点都可以）
  2. /usr/bin/python3 gen_cn_font.py    （输出到终端，重定向到文件也行）
  3. 把输出的 case 表贴进 osd_cn_char.v（把 `5'd??` 的 ?? 改成你的索引号）

依赖：
  - PIL（/usr/bin/python3 -m pip install pillow，通常已装）
  - 中文字体 simhei 黑体（/mnt/c/Windows/Fonts/simhei.ttf）
    ★ 重要：主工程 osd_cn_char.v 的现有字模是 simhei 黑体生成的，别用 Noto Sans CJK
    （实测反推「李」字模匹配度：simhei 86.7% > Noto Sans CJK 82.8%）。用错字体会导致
    新字和旧字风格/大小不一致，屏幕上新旧字混排时明显不协调。

输出格式说明（跟 osd_char_lib.v 一致）：
  - 16x16 点阵，每行 16 位十六进制，bit15 = 最左边像素
  - 先打印 ASCII 预览（## = 点亮），确认字能辨认再贴进代码
"""
from PIL import Image, ImageDraw, ImageFont
import os

FONT_PATH = "/mnt/c/Windows/Fonts/simhei.ttf"
if not os.path.exists(FONT_PATH):
    # 回退：WSL 里的 Noto Sans CJK（风格会和现有字模不一致，仅应急用）
    FONT_PATH = "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"

# 渲染参数（实测和现有字模一致）：字号 16 直接渲染（不缩放）、阈值 128、y 偏移 0
SIZE = 16
THRESHOLD = 128

chars = "原样灰度"  # ← 改成要生成的字

font = ImageFont.truetype(FONT_PATH, SIZE)

for ch in chars:
    img = Image.new('L', (16, 16), 0)
    draw = ImageDraw.Draw(img)
    draw.text((0, 0), ch, font=font, fill=255)

    # ASCII 预览
    print(f"\n// 字符：{ch}")
    for y in range(16):
        line = "".join("##" if img.getpixel((x, y)) > THRESHOLD else "  " for x in range(16))
        print(f"// {line}")

    # Verilog 点阵（bit15 = 最左）
    print(f"    5'd??: begin  // {ch}   ← 把 ?? 改成你的索引号")
    print(f"        case(I_row)")
    for y in range(16):
        row = 0
        for x in range(16):
            if img.getpixel((x, y)) > THRESHOLD:
                row |= (1 << (15 - x))
        print(f"            4'd{y}: O_row_bits = 16'h{row:04X};")
    print(f"            default: O_row_bits = 16'h0000;")
    print(f"        endcase")
    print(f"    end")
