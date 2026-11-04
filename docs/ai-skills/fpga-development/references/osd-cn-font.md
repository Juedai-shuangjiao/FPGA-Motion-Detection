# OSD 中文字模工程（FPGA 视频叠加文字）

PH1P35 项目 OSD 文字体系实战（osd_cn_char.v 16×16 点阵 + hdmi_mixer 渲染链）。新增/修改 OSD 中文文字时按此流程。

## 字模生成（Python + PIL）

```python
from PIL import Image, ImageDraw, ImageFont
font = ImageFont.truetype('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc', 15)
for ch in ['逻', '启']:
    img = Image.new('1', (16, 16), 0)
    d = ImageDraw.Draw(img)
    d.text((0, 0), ch, font=font, fill=1)
    for y in range(16):
        val = sum((1 << (15 - x)) for x in range(16) if img.getpixel((x, y)))
        print(f"16'h{val:04X}")
```

**字体必须与现有字模一致**：osd_cn_char 的字模用 Noto Sans CJK Regular 渲染——用 Serif（NotoSerifCJK）渲染新字会与旧字视觉不统一（笔画风格/粗细不同，用户会看出「字体不统一」）。新增字前先 `fc-list | grep Noto` 确认可用字体，
选与注释里声明一致的字体。

## 编码与索引
- 字符码 8 位：bit7=1 表示中文，低 7 位 = osd_cn_char 索引；bit7=0 为 ASCII（8'h3A 冒号、8'h2D 减号）。中文码 = 8'h80 + 索引。
- **索引空间**：osd_cn_char 的 I_idx 是 [6:0] 7 位（0~127），hdmi_mixer 例化连线是 `.I_idx(S_txt_char[6:0])`。
- **溢出坑**：写 6'd64/6'd65 会溢出 6 位范围被截断成 0/1（iverilog 报 Numeric constant truncated）——索引用 7'd 格式且确认 I_idx 位宽 ≥ 7。
- 历史文件里索引格式混写（4'd/5'd/6'd）——**查占用索引时用 `grep -o -E "(4|5|6|7)'d[0-9]+"` 四种位宽都搜**，sort -V 排序。

## 新增文字三步
1. PIL 渲染新字 → osd_cn_char.v 末尾 default 前插入 case 块（16 行 4'd0~4'd15 + default）
2. hdmi_mixer.v 对应行的 case(S_txt_idx) 里引用 `8'h80 + 8'd索引`；行 x 范围 = 字符数 × CHAR_W（16）
3. 语法验证：`iverilog -g2012 -o /tmp/x -y . -y key -I . osd_cn_char.v hdmi_mixer.v`（-y 目录必须带，否则报 Unknown module type 假错误）

## OSD 行布局
- S_row_idx 每行一个显示区，坐标条件 `(S_y_2d >= Y) && (S_y_2d < Y+16)`；x 范围 `(S_x_2d >= X) && (S_x_2d < X + n*CHAR_W)`
- 行号不够用时把 S_row_idx 从 [2:0] 扩 [3:0]，case 加分支
- 状态追加不覆盖：行内容用「基础信息 + 条件追加」结构（如帧号 7 字符恒显 + 采过背景后追加已采 2 字符），x 范围表达式里用条件宽度 `(S_sw_2d ? 2*CHAR_W : 0)`
- 文字行区域外 S_txt_char = 0（空白），字符 idx 超范围 default 也是 0

## 术语选择
- 队伍名称用「组名：X」不是「组别」——组别指 A/B/C 分组类别，组名才指队伍名；官方不建议显示成员姓名时用组名替代
