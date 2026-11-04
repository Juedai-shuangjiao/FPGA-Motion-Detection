# TD 重新生成 DDR2 IP（REF_CLK 刷新）实战

## 背景：REF_CLK 配错 = 2 倍超频
PH1P_REF_CLK 声明 50（实际板子 ref_clk=100M 差分 K5/L5）→ PLL1 M=64 → usr_clk = 100/4×64/12 = 133.33M（2 倍超频，标称 1066 实跑 2133）。声明 100 → M=32 → 66.67M（官方）。PLL0 级联 PLL1 出 usr_clk（IPUG034）。

## 参数在三层文件，改文本全部不生效
1. `.params_ddr2.txt`：PH1P_REF_CLK / PLL0_REFCLK_FREQ
2. `.m_params_ddr2.txt`：PLL0_REFCLK_FREQ（格式 `PLL0_REFCLK_FREQ; 1; 100.0`）
3. `Design.xml`：`referenceId="PLL0_REFCLK_FREQ">50.0` ← 最容易漏的一层

**改这三层 + 删 syn_1/phy_1 的 *.db 强制全量重编，PLL 仍是旧配置**——M 系数固化在 TD GUI 生成 IP 时写入的实例缓存里，命令行/文本无解，必须 GUI 重新生成。

## TD 6.2 GUI 重新生成的入口（实测坑）
- 右键 IP 条目：只有 File Properties / Open File Folder / Add / Open / Remove——没有 Regenerate
- 双击 ddr2.xml：报「无法识别文件 E:/TD_.../ip/depot//Component.xml」（双斜杠空路径，组件上下文没传进去，TD bug）
- `bin/IpTool.exe`：双击弹终端一闪而过——是命令行工具，不是 GUI
- **正确入口：TD 主界面菜单 Tools → IP Catalog**（面板被关了就在这打开）——注意 IP Catalog 只能新建，不能编辑已有实例
- 新建前必须先在工程里 Remove 旧 ddr2.xml（同名组件不能生成）；生成后 Add Source → IP files 加回来

## IpTool 新建 MIS_DDRF6F1D0P0（DDR2）的参数（2026-10-23 实测）
- Component Name 必须保持 `ddr2`（顶层例化模块名，改了要对不上）；生成前先备份旧目录
- **RefClk Freq 默认就是 100.0000**（不用改）；DDR Type=DDR2、DQ Bytes=1、AC Bytes=10、x8/512Mb、ROW_COL_BANK/NORMAL、PLL Location=BANK32、RefClk Type=DIFF、Training 全 0 保持
- 要改的：DDR Speed 800→**1066**、Speed Bin→**DDR2-1066**、CL 4→**7**、CWL 3→**6**、**Single PLL 取消勾选**（官方双 PLL 级联）
- **ADC File Path 必须 Browse 填 `ddr2/src/adc/ddr2.adc`**（IP 目录自带），否则报「The adc constraint file does not exist!」

## 命令行编译坑（td_commands_prompt）
- 增量编译不监视 IP 参数文件（不在 .al 文件列表）→ 参数改动直接复用旧 db
- 从 syn_1 目录跑 DefaultFlow.tcl：syn 跑完后 phy 可能不自动衔接（删过 phy_1 的 db 后）→ 再单独从 phy_1 目录跑一次
- 验证标准：final_timing.rpt 搜 `clk1`——66.667 才算 REF_CLK 真生效；bit 时间戳没变 = 编译复用了旧结果

## 最右列 3 像素 bug 的假设链（2026-10-23）
REF_CLK=50 → 2 倍超频 → 读数据眼图边缘采样错误 → 行尾 3 像素伪影（位置固定=固定时序边界、内容随场景=数据相关）。已排除：grant 切碎写（撤销 grant 下板仍在）、打包器提前结束（仿真 172800 精确）、写打断读返回尾流（仿真证明窗口存在且官方同样撞进 ~32 次/帧却不产生 bug → 打断不是充分条件）。