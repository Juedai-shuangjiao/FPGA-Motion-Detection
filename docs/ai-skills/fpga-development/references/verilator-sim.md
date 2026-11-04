# verilator 仿真环境（WSL，比 iverilog 快约 10 倍）

## 环境（免 sudo 解压安装，非正常 apt 安装）

- 安装位置：~/verilator_local（历次会话用 apt-get download + dpkg -x 解压）。
- 三件套（缺一即「找不到 verilator」）：
  1. 不在 PATH：直调 ~/verilator_local/usr/bin/verilator_bin（外层 Perl 包装器 verilator 按 Debian 布局找 bin 会报 not found，别用）。
  2. export VERILATOR_ROOT=$HOME/verilator_local/usr/share/verilator（否则找不到 include 头）。
  3. ~/.bashrc 已加别名 alias verilator='$HOME/verilator_local/usr/bin/verilator_bin' + export VERILATOR_ROOT——新会话 source 后可直接用。
- 版本：Verilator 5.020（Debian 包）。

## 编译与运行

```bash
verilator --binary --timing --top-module tb_xxx -Wno-fatal --Mdir sim/obj_xxx \
  -y src/hdl_source_clean -y src/hdl_source_clean/key <dut>.v <tb>.v
./sim/obj_xxx/Vtb_xxx
```

- **必须显式 --top-module**：默认可能把第一个输入文件的模块当顶层（曾把 div31 当顶层生成 Vdiv31，可执行文件名字不对找不到）。
- --timing 支持 #delay、@(posedge) 等时序仿真；--binary 自动写 main 并链接。
- -Wno-fatal 让部分警告降级；verilator 报错比 iverilog 严格（重复声明、类型错误直接 %Error）。
- ⚠️ **改 RTL 后必须 `rm -rf <Mdir>` 再重新编译**：--binary 会复用 obj_dir 里的旧 C++ 产物，RTL 改了不删目录直接跑 = 执行旧 DUT，输出 err=0 假阳性（真阳性：旧版仿真结果与新版代码无关）。每次改 .v 后重编译前先删 Mdir。
- ⚠️ **RTL 用 patch 工具改完必须立即重编译 tb 抓语法**：patch 的 context_aware 模糊匹配可能把 Verilog 关键字改坏（实锤：`end else if` 被替换成 `} else if`），语法错误只能靠编译器抓，不能「看着对」就过。

## 与 iverilog 的差异（tb 迁移注意）

- Verilator 5.020 **支持** $dumpfile/$dumpvars（VCD 导出）——但全层次 dump + 帧级场景会拖慢百倍（bbox tb 满帧场景 0.3s → 170s）。tb 里默认注释掉 VCD，调试才开；要看波形回 iverilog 也不迟。
- 匿名模块例化（`key_pulse (...)` 无实例名）报语法错——iverilog 和 TD 接受，verilator 拒绝；tb 顶层避免匿名例化。
- 层次引用 u_dut.S_xxx 在 tb 的 $display 中可用（内部信号可观测）——锁存链故障优先插 $display 打内部状态，别干读波形。
- 内存/reg 默认 2 态 0（无 X 传播），未初始化数组为 0。

## 速度陷阱（仿真突然慢 10 倍+ 时逐条排查）

- **--Mdir 必须在 WSL 本地磁盘**（如 ~/.hermes/cache/scratch/vobj_xxx），别放 /mnt/e 下：drvfs 上 g++ 编译读写在 Windows 磁盘，Windows 侧 TD 编译吃满 IO 时 verilator 编译从秒级退化为超时（300s 都完不了）。源文件在 /mnt/e 只读一次没问题，只有 Mdir 挪本地。
- **localparam 位宽截断是静默陷阱**：`localparam SAT_CNT = 15'd32768` 截断为 0（15 位存不下 32768），verilator 不报错——比较 `S_cnt >= SAT_CNT` 恒真，逻辑静默失效且现象诡异（min/max 正常、cnt 恒 0）。给带位宽标注的字面量先算所需位宽：32768 需要 16'd。

## 结论

iverilog 解释执行，tb_hdmi_mixer 类仿真（数帧 1280×720 扫描）跑数分钟；verilator 编译成 C++ 秒级跑完（20 秒 vs 数分钟）。功能断言调试优先 verilator，需要 X 传播语义/波形时用 iverilog。
