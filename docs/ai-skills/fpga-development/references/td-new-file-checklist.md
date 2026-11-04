# TD 工程新增 .v 文件必做清单（2026-10-27 黑盒教训，两次踩坑修正）

## 现象
新模块例化后编译，SYN 9~21 秒「假成功」（rc=0）、gate.db 不产出、PHY 报 Cannot open gate.db。
日志特征：HDL-8007 ERROR: xxx is a black box + HDL-7144 unknown module。

## 根因与正确顺序
1. 改三处文件列表：
   - E:\FPGA_Code\FPGACompetition\prj\FPGACompetition.al（同步源）
   - prj/FPGACompetition_Runs/syn_1/FPGACompetition.prj（TD 实际读）
   - prj/FPGACompetition_Runs/phy_1/FPGACompetition.prj（TD 实际读）
   只改 .al 不够——TD 编译读 .prj。
2. 插入位置：某现有条目（如 bg_read.v）的 </File> 之后。条目模板：
   <File Path="../../../src/hdl_source_clean/xxx.v">
       <FileInfo>
           <Attr Name="UsedInSyn" Val="true"/>
           <Attr Name="UsedInP&R" Val="true"/>
           <Attr Name="BelongTo" Val="design_1"/>
           <Attr Name="CompileOrder" Val="N"/>
       </FileInfo>
   </File>
   坑：插入点计算错误会把条目插到文件第 1 行且首字符写成 <<File；误删 <?xml 头。插完必须验证：文件以 <?xml 开头、条目在目标条目之后、首行不是 <<。
   **坑 2：CompileOrder 撞号 = 条目被 TD 静默丢弃，照样 black box**（uart_dbg_tx 用 35 撞了 hdmi_phy_warpper、改 77 又与既有条目重复，两次都假跑；换完全唯一的 99 才编进去）。这个工程的 CompileOrder 本来就有大量重复值，别用「最大值+1」也别猜，插入前 grep 该值的出现次数，用确定唯一的号（如 99）。插完 grep 文件名确认条目真在列表里。
3. 全部改完再启动编译。TD 启动瞬间锁定文件列表——启动后才改 → black box 假成功一轮。
4. ⚠️ 多会话共用：另一会话（1080P 版本）共用同一 .al/.prj 会互相覆盖（时间戳可查）。改完立即启动编译，别让另一会话的写盘夹在中间。
5. 编译启动 3 分钟后 grep syn_run.log 查 black box 止损；看到「analyze verilog file xxx.v」即被认到。
