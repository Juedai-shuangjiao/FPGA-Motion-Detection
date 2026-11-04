#!/usr/bin/env python3
"""VCD 文本波形解析：一次 dump 后查询任意信号时间线，替代 $display 单拍快照循环。

用法（在 scratch 目录里）：
    python vcd_parse.py dump.vcd find 'S_rd_total'      # 按名字模糊找信号 code
然后 import 使用：
    v = VCD('dump.vcd')
    v.find('rd_total')                                  # -> [(name, code, width), ...]
    v.value_at(code, t_ps)                              # t 时刻的值（t 单位=ps，见 $timescale）
    v.events_in_window(code, t0, t1)                    # 窗口内全部变化 [(t, val), ...]
    v.timeline(code, t0, t1)                            # 时间线（可抽样）

坑（已处理）：VCD 时间戳单位=$timescale 精度（本工程 1ps）；多位信号变化行带 b 前缀
（b1010 %"），1 位信号无前缀无空格（0&\"）；$var 名字可带 [n:0] 后缀；iverilog 不 dump
组合 assign wire 的变化（改用驱动它的时序 reg 统计）。
"""
import sys, re
from collections import defaultdict

class VCD:
    def __init__(self, path):
        self.sigs = {}          # id_code -> (name, width)
        self.name_to_code = {}  # name -> id_code
        self.changes = defaultdict(list)  # id_code -> [(t, value), ...]
        self.t = 0
        cur_scope = []
        with open(path, 'r', errors='replace') as f:
            for raw in f:
                line = raw.rstrip('\n')
                if line.startswith('$var'):
                    m = re.match(r'\$var\s+(\w+)\s+(\d+)\s+(\S+)\s+(\S+?)(?:\s+\[\d+:\d+\])?\s+\$end', line)
                    if m:
                        typ, width, code, name = m.group(1), int(m.group(2)), m.group(3), m.group(4)
                        full = '.'.join(cur_scope + [name])
                        self.sigs[code] = (full, width)
                        self.name_to_code[full] = code
                elif line.startswith('$scope'):
                    m = re.match(r'\$scope\s+\S+\s+(\S+)', line)
                    if m: cur_scope.append(m.group(1))
                elif line.startswith('$upscope'):
                    if cur_scope: cur_scope.pop()
                elif line.startswith('#') and line[1:].isdigit():
                    self.t = int(line[1:])
                elif line and not line.startswith('$'):
                    m = re.match(r'[bBrR]?([01xXzZ]+)\s*(\S+)', line)
                    if m:
                        val, code = m.group(1), m.group(2)
                        if code in self.sigs:
                            self.changes[code].append((self.t, val))

    def find(self, pattern):
        """按名字正则模糊找信号 -> [(name, code, width)]"""
        out = []
        for name, code in self.name_to_code.items():
            if re.search(pattern, name):
                out.append((name, code, self.sigs[code][1]))
        return out

    def timeline(self, name_or_code, t0=None, t1=None, max_events=2000):
        code = name_or_code if name_or_code in self.sigs else self.name_to_code.get(name_or_code)
        if code is None:
            print(f"信号不存在: {name_or_code}")
            return []
        ev = [(t, v) for (t, v) in self.changes[code] if (t0 is None or t >= t0) and (t1 is None or t <= t1)]
        if len(ev) > max_events:
            step = len(ev) // max_events
            return ev[::max(1, step)]
        return ev

    def value_at(self, name_or_code, t):
        """t 时刻的值（ps 单位；无事件信号取初值 None，恒值信号 grep 文件确认）"""
        code = name_or_code if name_or_code in self.sigs else self.name_to_code.get(name_or_code)
        if code is None:
            return None
        val = None
        for (tt, v) in self.changes[code]:
            if tt > t: break
            val = v
        return val

    def events_in_window(self, name_or_code, t0, t1, condition_fn=None):
        code = name_or_code if name_or_code in self.sigs else self.name_to_code.get(name_or_code)
        if code is None:
            return []
        return [(t, v) for (t, v) in self.changes[code] if t0 <= t <= t1 and (condition_fn is None or condition_fn(v))]

    def count_events(self, name_or_code, t0=None, t1=None, predicate=None):
        return len(self.events_in_window(name_or_code, t0 or 0, t1 or 10**18, predicate))

if __name__ == '__main__':
    v = VCD(sys.argv[1])
    if len(sys.argv) > 2 and sys.argv[2] == 'find':
        for pat in sys.argv[3:]:
            print("### 匹配", pat)
            for name, code, w in v.find(pat):
                print(f"  {code}  w={w}  {name}")
    else:
        print("用法: python vcd_parse.py file.vcd find <pattern>")
