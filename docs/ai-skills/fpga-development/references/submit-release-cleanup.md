# 提交版工程整理工作流（release cleanup）

适用：把开发主线整理成「比赛提交版/交付版」——复制工程、回滚/修复指定改动、清理工程文件、保证 GUI 可编译。

## 流程（顺序执行）
1. **复制到新目录，不动开发主线**：rsync 排除 .git 和 prj/*_Runs（编译产物大且会重建）。开发主线若正在后台编译，复制是读操作安全，但副本里改、原目录一行都不动。
2. **副本里做改动**：回滚/修复全部在副本做。改完先 iverilog 全工程语法检查（`find src -name '*.v' ! -name '*.enc.v' | xargs iverilog -g2012 -tnull`），只有「Possible nested comment」报错是中文注释嵌套提示，TD 无关可忽略。
3. **清理 .al**：踢未使用模块（见下节）后，验证 .al 结构（ET 解析会因 TD 自带的 `UsedInP&R` 未转义 & 报错——历史格式无碍，别修）。CompileOrder 有少量重复是历史现状，TD 能编译，别「顺手修」。
4. **GUI 编译准备**：副本无 Runs 目录 → GUI 打开 .al 后直接跑全流程，TD 自动重建。交付说明里写清楚 bit 路径和「下载后先复位再观察」。

## 判「未使用模块」的正确方法（纯 grep 例化正则必漏）
- 从顶层递归收集例化树，再与 .al 注册列表做差集。正则漏匹配/误判的真实情况（逐条对过再下结论）：
  1. 例化跨行：`模块名 #(
 ... ) u_inst (` —— 用 `\b模块名\s+#?\(|\b模块名\s+u_` 双模式 grep
  2. 例化名带后缀：`模块名 模块名_r0(` —— 按模块名裸 grep 所有出现处再人工判例化
  3. **.enc 加密模块在 .sv wrapper 里例化**（MIPI/HDMI 官方 IP）：grep 必须同时搜 .v 和 .sv，文件名带 .enc 后缀但模块名不带
  4. **文件名与模块名拼写不一致**（如文件 hdmi_phy_warpper.v 但模块 hdmi_phy_wrapper）：判死前先 head 文件看 module 声明名
  5. **实例名保留但模块已换**：`canny_top u_sobel_top (` —— 升级后实例名没改、模块换成新的，旧模块名仍出现在实例名里，裸 grep 会误判「在用」。看到实例名与模块名不一致时必须按实例名前的模块名判定
  6. **例化被注释掉**：`//bad_pixel_correct u_bad_pixel_correct (` —— grep 命中但整行注释。grep 结果必须过滤 `//` 行，可疑的看整行上下文
  7. **端口连接 ≠ 例化**：`.key_pulse(S_key_pulse)` 只是上层端口接线。判模块孤儿时还要追该信号的真正驱动（可能是另一个模块如 key_short_press 的输出）
- 官方注释是硬证据：源文件头注释写着「默认不加入工程源文件列表」的（如 1080p30 寄存器表在 720p60 工程里）直接踢。
- .al 条目删除：`<File Path="...">...</File>` 正则整块删；注意 al_ip/ 下的条目 Path 无 `../` 前缀（`al_ip/xxx.xml`），与 src/ 条目（`../src/xxx.v`）两种格式都要处理。
- **删除条目后 CompileOrder 必重排**：删条目会留编号空洞（如 52/63/67/74），TD 对空洞容忍度未知——按条目在 .al 中的出现顺序整体重编号为 1~N 连续（保序 = 依赖顺序不变，最稳）。与「历史重复号别顺手修」不冲突：重复是 TD 自生现状，空洞是自己删出来的必须补。
- 用户发 TD GUI 截图报错/列模块时：tesseract 装好后 `tesseract 截图.png out -l chi_sim+eng` OCR 提取窗口文本（TD GUI 的模块浏览/错误列表都能读出来），别干瞪眼。

## GUI 编译 vs 命令行编译的数值差异（都属正常，别误判回退出错）
- 资源口径：GUI 默认综合选项优化少于命令行 tcl，slice 占用会高 ~3%（实测 95.56% vs 92.73%）；SYN-8411 条数也会不同（6 vs 10，内容同为 DDR PLL VCO 2400 告警）。判据只看：时序全绿 + bit 生成 + 下板验证。
- bit 位置：GUI 全流程后 bit 在 Runs/phy_1/（布局布线目录），命令行在 Runs/syn_1/，两处都查。

## 交付打包（RAR / PDF / U 盘）
- RAR：`apt install rar`；`rar a -r -ep1 -x'FPGACompetition/prj/*_Runs/*' -x'FPGACompetition/sim/**/obj_dir/*' -x'FPGACompetition/sim/*.vvp' 包名.rar FPGACompetition`。源码+文档压缩后 ~2MB（大头全在 Runs/obj_dir，必须排除）。
- 技术报告 PDF：裸 python3 = ARM 工具链（无 weasyprint）；`/usr/bin/python3 -m venv` 建 venv 再 pip 装 markdown+weasyprint（清华源，系统 python 受 PEP668 管控）。@font-face 指向 /mnt/c/Windows/Fonts/：simsun.ttc 正文宋体 + simhei.ttf 标题黑体。md→HTML（markdown 库 tables+fenced_code 扩展）→HTML(string).write_pdf。
- WSL 只自动挂 C/D/E：U 盘 F: 要 `sudo mkdir /mnt/f && sudo mount -t drvfs F: /mnt/f`，用前先 powershell.exe Get-PSDrive 确认盘符存在。

## 交付物清单（比赛提交）
- 提交版工程目录 + 说明文档（与开发版的差异逐条列：修了什么、删了什么、验证状态、GUI 编译注意事项、下板验证清单）
- 技术报告（模板结构见 competition-technical-report）
- 演示视频脚本（见 competition-demo-script）
- 上传 GitHub 时排除 Runs/编译产物（工程 400M+ 大头是产物）
