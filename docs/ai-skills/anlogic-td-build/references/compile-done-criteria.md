# TD 编译完成判据（2026-11-02 实测修正）

## 判据优先级

1. **bit 文件时间戳**（最硬）：`ls -l --time-style=full-iso syn_1/*.bit` 时间戳是新的且文件存在
2. **BIT-1003**（可靠）：日志 grep `BIT-1003`，出现 `Generate bitstream completely, there are N bits set as '1'` 即 bitgen 完成
3. **日志尾部 Flow Statistics**：有 bitgen 一行（wall time 非 0）
4. ⚠️ **BV4_FULL_DONE 不稳定**：某轮全流程成功（exit 0 + bit 生成）但日志里 grep 不到该串（grep -c 返回 0）——不能只靠它判完成

## 验证三连（完整版）

- ① bitstream 完成：grep -cE "BIT-1003" 日志 > 0
- ② 无资源超限：grep -c "PHY-9053" == 0
- ③ bit 时间戳新
- ④ 时序：grep "WNS.*TNS" 日志尾部，Setup/Hold WNS > 0、NUM_FEPS 0
- ⑤ 资源：grep "#slice" syn_1/FPGACompetition_phy.area（对照基线/历史轮次）

## 日志格式坑

- TD 日志是 CRLF：grep 匹配词尾的串要用 `tr -d '\r'` 再 tail，或只 grep 词头
