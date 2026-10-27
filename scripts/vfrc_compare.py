#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""vfrc_compare.py — P3C hex 镜像/字流比对(忽略 // 注释与空行)

用法:
  python3 scripts/vfrc_compare.py dump.hex exp.hex [--tag NAME]
退出码: 0=匹配, 1=失配
"""
import argparse
import sys


def load(path):
    vals = []
    with open(path) as f:
        for ln, line in enumerate(f, 1):
            s = line.strip()
            if not s or s.startswith("//"):
                continue
            try:
                vals.append(int(s, 16))
            except ValueError:
                vals.append(None)
    return vals


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dump")
    ap.add_argument("exp")
    ap.add_argument("--tag", default="")
    ap.add_argument("--max-report", type=int, default=10)
    args = ap.parse_args()

    a = load(args.dump)
    b = load(args.exp)
    tag = args.tag or args.dump
    n = min(len(a), len(b))
    bad = 0
    first = []
    for i in range(n):
        if a[i] != b[i]:
            bad += 1
            if len(first) < args.max_report:
                first.append((i, a[i], b[i]))
    if len(a) != len(b):
        print("%s: LENGTH MISMATCH dump=%d exp=%d" % (tag, len(a), len(b)))
    for i, x, y in first:
        print("%s: [%d] dump=%s exp=%s" %
              (tag, i, "X" if x is None else "%08x" % x,
               "X" if y is None else "%08x" % y))
    if bad == 0 and len(a) == len(b):
        print("%s: MATCH (%d words)" % (tag, n))
        return 0
    print("%s: MISMATCH (%d/%d)" % (tag, bad, n))
    return 1


if __name__ == "__main__":
    sys.exit(main())
