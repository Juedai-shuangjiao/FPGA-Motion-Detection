# 清编译缓存纪律 + bit 版本识别（2026-11-02 事故记录）

## 纪律：清缓存前先备份 bit

- 事故：`rm -f syn_1/*.bit` 清缓存把「唯一可下板的多段版 bit」删了，且无副本，只能重编译 58 分钟
- 纪律：清缓存（rm *.db/*.bit/结束标记）前，先 `cp syn_1/FPGACompetition.bit <安全位置>` 备份
- 用户优先下板验证：bit 是交付物，删之前先想「用户还能不能下板」

## TD 的 bit 副本位置（可救急）

- `prj/FPGACompetition_Runs/best_result/FPGACompetition.bit` —— TD 保存的「最好结果」副本
- `prj/FPGACompetition_Runs/phy_1/cw/compiled.bit` —— phy 流的 cw 子目录副本
- 时间戳可判版本；不确定内容时用 `grep "#slice" <目录>/FPGACompetition_phy.area` 对照已知版本资源数

## 本工程各轮 slice 数（版本指纹）

- 基线（无填充）：19328 / 21216 = 91.10%
- v2 单段填充 DRAM 化：18776 = 88.50%
- 多段 64 组版：18822 = 88.72%
- 多段 40px 位级版（下板验收版）：18600 = 87.67%

## 多段行填充（row_fill）设计要点

- 段分割 = 行内 0 游程 > GAP_T 组断段（任务书主线参数：GAP_T=10 组=40px）
- 噪点兜底 = 段内 1 像素总数 < MIN_W（4px）整段不填，位级 popcount 累加，成本可忽略
- 每行最多 K=4 段：段表寄存器（工作 + 行末锁存两份），行末拍锁存供第二遍输出用
- 行级判定无垂直信息：物体间隙 ≤ GAP_T 仍误连是已知局限（彻底解 = 跨行连通域，比赛期不做）
- 边缘模式（O_edge）是填充**前** open^erode 直通：涂白填掉的小洞其轮廓环在边缘图仍可见（语义独立，非 bug）
