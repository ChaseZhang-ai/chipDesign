#!/usr/bin/env python3
# -----------------------------------------------------------------------------
# -----------------------------------------------------------------------------
import glob, os, re, sys

RPT = sys.argv[1] if len(sys.argv) > 1 else 'pnr/amechip/reports/sky130hd/amechip/p4a0'
TARGET = 8.333   # 120 MHz
MARGIN = 7.576   # +10%

def parse(fn):
    txt = open(fn, errors='ignore').read()
    out = []
    for b in re.split(r'(?=Startpoint:)', txt):
        if 'Startpoint' not in b or 'slack (' not in b:
            continue
        sp = re.search(r'Startpoint:\s*(\S+)', b)
        ep = re.search(r'Endpoint:\s*(\S+)', b)
        arr = re.findall(r'([\d.]+)\s+data arrival time', b)
        sl = re.search(r'(-?[\d.]+)\s+slack', b)
        if sp and ep and arr and sl:
            out.append((float(arr[-1]), float(sl.group(1)), sp.group(1), ep.group(1), os.path.basename(fn)))
    return out

def base(n):
    n = re.sub(r'\$_DFF\w*_?$', '', n)
    n = re.sub(r'\[\d+\]$', '', n)
    n = re.sub(r'\[\d+\]', '', n)
    return n

def cat(sp, ep):
    s, e = sp, ep
    if 'u_ame' in e and 'bus_resp_rdata' in e:
        if 'y_rdata' in s: return 'AME requant (Y→resp)'
        if 'u_wbuf' in s:  return 'AME WBUF bus read'
        if 'u_xbuf' in s:  return 'AME XBUF bus read'
        return 'AME window read mux'
    if 'u_ame' in e and 'u_array' in e:
        if 'u_wbuf' in s: return 'AME WBUF row read'
        if 'u_xbuf' in s: return 'AME XBUF row read'
        if 'x_q' in s:    return 'AME MAC x→Y'
        if 'tile_q' in s: return 'AME MAC tile→Y'
        return 'AME array'
    if 'u_ame' in s or 'u_ame' in e:
        if 'u_win' in s:  return 'AME window addr→resp'
        return 'AME other'
    if 'u_cpu' in s or 'u_cpu' in e: return 'CPU'
    if 'u_ocram' in e or 'u_bootrom' in e: return 'MEM store/ROM (flop array)'
    if 'u_memc' in e: return 'MEMC (XMEM queue)'
    if 'u_dma' in e:  return 'DMA'
    if 'u_uart' in e: return 'UART'
    if 'u_kvc' in e:  return 'KV ctrl'
    if 'u_xbar' in e or 'u_xbar' in s: return 'XBAR'
    if 'u_intc' in e: return 'INTC'
    if 'u_sys' in e:  return 'SYS CSR'
    return 'other'

rows = []
for fn in glob.glob(os.path.join(RPT, 'p4a0_*.rpt')):
    rows += parse(fn)
# dedup by (base startpoint, base endpoint)
seen = {}
for a, s, sp, ep, src in rows:
    key = (base(sp), base(ep))
    if key not in seen or a > seen[key][0]:
        seen[key] = (a, s, sp, ep, src)
uniq = sorted(seen.values(), key=lambda x: -x[0])[:20]

print('| # | delay ns | slack vs 8.333 | slack vs 7.576 | startpoint | endpoint | category |')
print('|---:|---:|---:|---:|---|---|---|')
for i, (a, s, sp, ep, src) in enumerate(uniq, 1):
    flag = '**FAIL 120M**' if a > TARGET else ('over margin' if a > MARGIN else 'ok')
    print(f'| {i} | {a:.3f} | {TARGET-a:+.3f} | {s:.3f} | `{sp}` | `{ep}` | {cat(sp,ep)} {flag} |')

print(f'\n(total parsed {len(rows)} paths, {len(seen)} unique; target {TARGET} ns / margin {MARGIN} ns)')
