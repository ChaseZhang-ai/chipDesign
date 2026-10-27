#!/usr/bin/env python3
# -----------------------------------------------------------------------------
#
# -----------------------------------------------------------------------------
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OLD_DIR = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    REPO, 'pnr/amechip/reports/sky130hd/amechip/p4a4')
OLD_PREFIX = sys.argv[2] if len(sys.argv) > 2 else 'p4a4_sdc7576'
NEW_DIR = sys.argv[3] if len(sys.argv) > 3 else os.path.join(
    REPO, 'pnr/amechip/reports/sky130hd/amechip/p4a3rtl03')
NEW_PREFIX = sys.argv[4] if len(sys.argv) > 4 else 'p4a3rtl03'
NEW_PERIOD = sys.argv[5] if len(sys.argv) > 5 else '7.576'


def parse_paths(rpt_path):
    """返回 [(arrival, slack, startpoint, endpoint)](每条路径一项)。"""
    out = []
    if not os.path.exists(rpt_path):
        return out
    txt = open(rpt_path, errors='ignore').read()
    for b in re.split(r'(?=Startpoint:)', txt):
        if 'Startpoint' not in b or 'slack' not in b:
            continue
        sp = re.search(r'Startpoint:\s*(\S+)', b)
        ep = re.search(r'Endpoint:\s*(\S+)', b)
        arr = re.findall(r'([\d.]+)\s+data arrival time', b)
        sl = re.search(r'(-?[\d.]+)\s+slack', b)
        if sp and ep and arr and sl:
            out.append((float(arr[-1]), float(sl.group(1)), sp.group(1), ep.group(1)))
    return out


def base(name):
    """去位索引/后缀,聚合同族路径。"""
    n = re.sub(r'\$_\w*$', '', name)
    n = re.sub(r'\[\d+\]$', '', n)
    n = re.sub(r'\$\d+$', '', n)
    return n


def family(rows, kf, ke):
    """取起点匹配 kf、终点匹配 ke 的最差(最大 arrival)路径。"""
    best = None
    for arr, sl, sp, ep in rows:
        if kf(sp) and ke(ep):
            if best is None or arr > best[0]:
                best = (arr, sl, sp, ep)
    return best


def top_paths(rows, n=5):
    seen = {}
    for arr, sl, sp, ep in rows:
        k = (base(sp), base(ep))
        if k not in seen or arr > seen[k][0]:
            seen[k] = (arr, sl, sp, ep)
    return sorted(seen.values(), key=lambda x: -x[0])[:n]


old = parse_paths(os.path.join(OLD_DIR, f'{OLD_PREFIX}_top20.rpt'))
new_files = [os.path.join(NEW_DIR, f) for f in os.listdir(NEW_DIR)
             if f.startswith(NEW_PREFIX) and f.endswith('.rpt')] \
    if os.path.isdir(NEW_DIR) else []
new = []
for f in new_files:
    new += parse_paths(f)

print(f'旧口径: {OLD_PREFIX} @7.576 ns(120 MHz 预算)  路径数 {len(old)}')
print(f'新口径: {NEW_PREFIX} @{NEW_PERIOD} ns  路径数 {len(new)}  ({len(new_files)} 个报告)')

chains = [
    ('链1 CPU→AME 请求装载(trace_rd_o → u_rq_stq.p_u_q)',
     lambda n: 'trace_rd_o' in n, lambda n: 'u_rq_stq' in n and 'p_u_q' in n),
    ('链2 requant 参数装载(s1_rel → g_yq*.u_rq.p_u_q)',
     lambda n: 's1_rel' in n, lambda n: ('g_yq' in n or 'u_rq.' in n) and 'p_u_q' in n),
]
print('\n| 链 | 旧 arrival / slack@7.576 | 新 arrival / slack | 判定(≤8.333 量级) |')
print('|---|---|---|---|')
for name, kf, ke in chains:
    o = family(old, kf, ke)
    nn = family(new, kf, ke)
    def fmt(t, with_slack=True):
        if t is None:
            return '—(未出现在 top 路径)'
        if with_slack:
            return f'{t[0]:.3f} / {t[1]:+.3f}'
        return f'{t[0]:.3f}'
    verdict = ''
    if nn is not None:
        verdict = '✓ 已达标' if nn[0] <= 8.4 else f'✗ 仍超 {nn[0]:.3f}'
    elif o is not None:
        verdict = '✓ 路径已消失(链被寄存切断)'
    print(f'| {name} | {fmt(o)} | {fmt(nn)} | {verdict} |')

print('\n新最差路径 top5(去重后,按 arrival 降序):')
print('| # | arrival ns | slack ns | startpoint | endpoint |')
print('|--:|---:|---:|---|---|')
for i, (arr, sl, sp, ep) in enumerate(top_paths(new, 5), 1):
    print(f'| {i} | {arr:.3f} | {sl:+.3f} | `{sp}` | `{ep}` |')
