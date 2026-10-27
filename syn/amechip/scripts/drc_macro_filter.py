#!/usr/bin/env python3
# -----------------------------------------------------------------------------
#
#
# -----------------------------------------------------------------------------
import re, sys
from collections import Counter

MACROS = [
    (8.12, 100.13, 1149.84, 732.605),
    (1165.94, 100.13, 2307.66, 732.605),
    (2323.76, 100.13, 3465.48, 732.605),
]

def main():
    rpt = sys.argv[1]
    top = 'amechip_top'
    if '--top' in sys.argv:
        top = sys.argv[sys.argv.index('--top') + 1]
    txt = open(rpt).read()
    items = re.findall(
        r'<item>\s*<tags/>\s*<category>([^<]+)</category>\s*<cell>([^<]*)</cell>.*?<value>([^<]*)</value>',
        txt, re.S)
    sub = Counter(); top_in = Counter(); top_out = Counter()
    samples = []
    for cat, cell, val in items:
        if cell == top:
            cs = [float(v) for v in re.findall(r'-?\d+\.?\d*', val)][:2]
            if len(cs) >= 2 and any(m[0]-2 <= cs[0] <= m[2]+2 and m[1]-2 <= cs[1] <= m[3]+2 for m in MACROS):
                top_in[cat] += 1
            else:
                top_out[cat] += 1
                if len(samples) < 8: samples.append((cat, val[:90]))
        else:
            sub[cat] += 1
    print(f"total items: {len(items)}")
    print(f"宏GDS子单元层次(豁免): {sum(sub.values())}")
    for c, n in sub.most_common(6): print(f"   {n:8d}  {c}")
    print(f"顶层坐标在宏bbox内(豁免): {sum(top_in.values())}")
    for c, n in top_in.most_common(6): print(f"   {n:8d}  {c}")
    print(f"宏外(必须0): {sum(top_out.values())}")
    for c, n in top_out.most_common(8): print(f"   {n:8d}  {c}")
    for s in samples: print("  sample:", s)
    sys.exit(1 if sum(top_out.values()) else 0)

if __name__ == '__main__':
    main()
