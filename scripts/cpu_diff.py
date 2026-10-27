#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""cpu_diff.py — ISS 与 RTL 提交序列差分比对(P2A 核心验收工具)

trace 行格式(两侧一致):
    <pc:8hex> <instr:8hex> <rd:2hex> <wdata:8hex> <flags:hex>
flags bit0 = 本条写 rd;bit1 = wdata 依赖 mcycle(差分跳过 wdata)。

比对规则:
  - 行数必须一致,逐行比对 pc/instr/rd/flags;
  - wdata 仅在两侧 flags bit1 均为 0 时比对(rd 写值随 pc+instr 确定)。

用法: python3 scripts/cpu_diff.py <ref.trace> <rtl.trace> [-v]
"""

import argparse
import sys


def load(path):
    rows = []
    with open(path, encoding="utf-8") as f:
        for ln, line in enumerate(f, 1):
            s = line.strip()
            if not s:
                continue
            parts = s.split()
            if len(parts) != 5:
                raise SystemExit(f"{path}:{ln}: bad trace line '{s}'")
            pc, instr, rd, wd, fl = (int(p, 16) for p in parts)
            rows.append((pc, instr, rd, wd, fl))
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ref")
    ap.add_argument("rtl")
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args()

    a = load(args.ref)
    b = load(args.rtl)
    n_mismatch = 0
    shown = 0
    limit = 20
    for i in range(max(len(a), len(b))):
        if i >= len(a) or i >= len(b):
            n_mismatch += 1
            if shown < limit:
                which = "RTL 多出" if i >= len(a) else "REF 多出"
                print(f"MISMATCH[{i}] {which}: "
                      f"ref={a[i] if i < len(a) else None} "
                      f"rtl={b[i] if i < len(b) else None}")
                shown += 1
            continue
        ra, rb = a[i], b[i]
        skip = ((ra[4] & 2) or (rb[4] & 2))
        written = ((ra[4] & 1) and (rb[4] & 1))
        if ra[0] != rb[0] or ra[1] != rb[1] or ra[2] != rb[2] or ra[4] != rb[4] \
                or (written and not skip and ra[3] != rb[3]):
            n_mismatch += 1
            if shown < limit:
                print(f"MISMATCH[{i}]:")
                print(f"  ref: pc={ra[0]:08x} instr={ra[1]:08x} rd={ra[2]:2d} "
                      f"wdata={ra[3]:08x} flags={ra[4]:x}")
                print(f"  rtl: pc={rb[0]:08x} instr={rb[1]:08x} rd={rb[2]:2d} "
                      f"wdata={rb[3]:08x} flags={rb[4]:x}")
                shown += 1
    total = max(len(a), len(b))
    print(f"cpu_diff: {args.ref} vs {args.rtl}: compared {total} instructions, "
          f"{n_mismatch} mismatches")
    if n_mismatch:
        return 1
    print("cpu_diff: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
