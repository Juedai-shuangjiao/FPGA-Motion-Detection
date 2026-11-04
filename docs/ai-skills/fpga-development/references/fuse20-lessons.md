# 2026-11-03 fuse20 迭代教训（编译中）

## iverilog 12 function 内 ~x[11:0] 位宽上下文 bug（仿真全白）
`a = g_s[12] ? (~g_s[11:0] + 12'd1) : g_s[11:0];`（g_s/a 均 13bit）在 function 内赋值上下文：
iverilog 把 ~ 操作数先零扩展到 13bit 再取反（4092→4099→+1→4100，超幅值物理上限 4080）→ 仿真全白/伪边缘。
TD 综合行为正确（fuse19 上板正常可证）；module 级（initial 里）同表达式正常——bug 只在 function 上下文。
最小复现：tb_expr_min——无括号 4100、加括号仍 4100、XOR 版 4 ✓。
规避写法：`(g_s[11:0] ^ 12'hFFF) + 12'd1`（XOR 掩码代替 ~，两工具语义一致）。
仿真出现超数学上限的值，先怀疑工具位宽 bug 再做最小表达式复现。

## KEY4 一 key 两用（短按+长按）判定模式
短按 = 「释放沿 && 本次按住未产生长按 tick」（long_tick 置位锁存、松开清零，key_short_press.v）。
长按成立后本次按键不再发短按脉冲——根治「长按开头是一次按下沿必误触发短按」。
代价：短按响应移到释放瞬间（点按 50~100ms 无感）。
auto_manual_sel：held_flag 保证一次长按周期只切一次（key_hold 的 tick 是连续的，不锁存会反复横跳）。
en=0（非目标模式）时 mode 复位默认态 + held_flag 清零。

## 阴影判据 v3（相对色度容忍）在白墙/低色度背景必然误滤手内部
v3 = |ds| ≤ 4 + s_bg/4。实验室白墙 s_bg≈0~4 → 容忍仅 4~5；手内部暗区（dy<-48 亮度低于墙面、
AWB 后色度几乎不升 ds≤0、|ds|≤4）完全满足阴影特征 → 被滤 → 涂白稀疏均匀、row_fill 填不满。
数学上「白墙前手内部暗区」与「白墙上的真阴影」通道特征不可分。
务实取舍 = v2 的 s_bg>=12 前置门控（场景开关）：灰白背景关阴影抑制保涂白完整（演示核心），
彩色背景启用滤真影子；代价 = 灰水管挡光阴影不滤（可接受）。
选型先想「演示主场景的背景色度」——低色度场景别用相对容忍类判据。

## osd_cn_char 现有字模真实渲染参数（反推锁定）
simhei 19px、x=-1、y=-2、阈值 32（外框 16×16 满格、笔画数与旧模一致：自 16×13×133 全同）。
gen_cn_font.py 里写的「simhei 16px 阈值 128」是过时参数。
反推法：渲染 6 个旧字 × 各参数组合，比「外框高/宽/笔画数」三个度量（比像素匹配度靠谱——
FreeType 版本差异像素级最高 ~78%，但度量一致视觉就一致）。新字和旧字同行时度量必须一致。

## canny 等含 BRAM lb 的流水线仿真必须用真实 RTL 相位链
tb 用「真实 line_buffer_demosaic.v + blk_mem_gen_demosaic.v + stub ram_c36c2ca3b3a7」才能与硬件相位一致。
ram stub 要点：doa/dob 用组合 mem[addr]（NOREG 异步读）、mem 初始清零、write 在 posedge。
手写简化 stub（同址读旧写新延迟 1 行）与实际「行内 320 循环 + 首行锁 tlast_lock + addrb 相位」不符 → 假全白。
真实 line_buffer_demosaic 语义：addra 行内 0~319 循环（I_tuser 帧首复位）、首行 tlast_lock 置位后 rd_en 才读、
O_valid = valid_d0 && tlast_lock（首行无输出）。

## wrapper 新增联动信号先 grep 重名
S_thr_auto 与既有 bg_read 差分档位线撞名（iverilog already declared）→ 二值化联动线改名 S_binary_auto。
wrapper 是 1100+ 行大文件，新信号名先 grep 全文件确认唯一。

## tb 注入噪声别用 {N{noise[2:0]}} 复制填充
3bit 复制 N 次填满字节 = 每字节 0x92/0xB6 这种大幅值（146~255），不是 ±3 噪声——
「±3 噪声过 mag8 阈值 64」的假象就是这么来的。每像素小噪声写 {12{{5'd0, noise[2:0]}}}（字节级复制）。

## 阈值联动查表（wrapper 24M 域）实现要点
S_brightness_avg（像素域）在 24M 域打 2 拍再查表；带 initializer 的 wire 必须先声明后使用（TD 坑）；
4 档查表档位值 localparam 化，下板后只调表不调结构；Sobel 联动档位按现场实测锚点内插（3990/121 窗口
mag8 128~144 → 暗场 1088；目标 100 甜点 → 亮场 128）。threshold_set/sobel_threshold_set 加 I_auto_en/
I_auto_val：auto_en=1 时 r_threshold 直接跟随（按键忽略）、auto_en=0 按键调——手动值从联动值连续变化不跳变。

## canny 两级高斯（3×3 级联≈5×5）延迟连锁账
每级 lb 净 +2 拍：tvalid 链 +2、h/v_cnt 打拍 +2、强边缘 lb 地址 d4→d6、mtuser/valid 打拍 +2。
边界屏蔽组数随高斯层数扩散：左邻居缓存逐层扩散 1 组（高斯+高斯+Sobel 三层 → 屏蔽 5 组）。
isp_top 的算法 MUX 是自洽的（Sobel 取 canny 全套 data+valid+tuser）——canny 延迟改 8→10 拍不用改 isp_top。
验证先查下游是「固定拍对齐」还是「自洽 MUX」再决定连锁范围。
