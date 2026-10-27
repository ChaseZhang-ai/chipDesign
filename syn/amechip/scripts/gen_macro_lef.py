#!/usr/bin/env python3
# -----------------------------------------------------------------------------
#
#
#
# -----------------------------------------------------------------------------
import argparse, re, sys
from collections import defaultdict

def snap5(v):
    """吸附到 0.005um 制造网格(DRT-0320 对宏引脚形状按 mfg grid 检查)。"""
    return round(v * 200.0) / 200.0

def parse_lef_pins(path):
    """返回 (preamble, [(pin_name, pin_block_text)], vdd_rects, gnd_rects, obs_text, footer)"""
    with open(path) as f:
        txt = f.read()
    m = re.search(r'PIN vdd\n(.*?)END vdd', txt, re.S)
    vdd_sec = m.group(1)
    m = re.search(r'PIN gnd\n(.*?)END gnd', txt, re.S)
    gnd_sec = m.group(1)
    rect_re = re.compile(r'RECT\s+(-?[\d.]+) (-?[\d.]+) (-?[\d.]+) (-?[\d.]+)\s*;')
    vdd = [tuple(map(float, mm)) for mm in rect_re.findall(vdd_sec)]
    gnd = [tuple(map(float, mm)) for mm in rect_re.findall(gnd_sec)]
    txt2 = re.sub(r'PIN vdd\n.*?END vdd\n', '', txt, count=1, flags=re.S)
    txt2 = re.sub(r'PIN gnd\n.*?END gnd\n', '', txt2, count=1, flags=re.S)
    return txt2, vdd, gnd

def parse_facts(path):
    macros = []   # (inst, x1, y1, x2, y2)
    straps = defaultdict(set)  # net -> set of (x1, x2) met4
    for line in open(path):
        p = line.split()
        if not p: continue
        if p[0] == 'MACRO':
            macros.append((p[1], float(p[2]), float(p[3]), float(p[6]), float(p[7])))
        elif p[0] == 'STRAP' and p[1] == 'met4':
            straps[p[2]].add((float(p[3]), float(p[5])))
    return macros, straps

def make_clusters(pads, width=1.27):
    """按 x 中心贪心聚成 <=width 宽的列, 列中心=窗口两端中点(保证列内所有
    焊盘中心落在 c±width/2 内, 即 1.6um 条覆盖 ±0.8 > ±0.635 需求)。"""
    xs = sorted(( ((r[0]+r[2])/2.0, r) for r in pads ), key=lambda t: t[0])
    clusters = []
    i = 0
    while i < len(xs):
        j = i
        while j+1 < len(xs) and xs[j+1][0] - xs[i][0] <= width:
            j += 1
        group = xs[i:j+1]
        lo, hi = group[0][0], group[-1][0]
        c = (lo + hi) / 2.0
        if hi - lo > width + 1e-9 and len(group) > 1:
            mid = len(group)//2
            for seg in (group[:mid], group[mid:]):
                if seg:
                    seg_lo, seg_hi = seg[0][0], seg[-1][0]
                    clusters.append(((seg_lo+seg_hi)/2.0, [g[1] for g in seg]))
        else:
            clusters.append((c, [g[1] for g in group]))
        i = j + 1
    return clusters

def pick_columns_joint(pads_vdd, pads_gnd, lat_vss, lat_vdd, macro_offsets,
                       width=1.27, min_same=2.0, min_opp=3.5,
                       min_core_clear=2.4, n_cols=12):
    """两网交替选列(按列内焊盘数降序), 逐步施加 同网/异网/核心栅格 约束。"""
    cand = {'vdd': sorted(make_clusters(pads_vdd, width), key=lambda t: -len(t[1])),
            'gnd': sorted(make_clusters(pads_gnd, width), key=lambda t: -len(t[1]))}
    latt = {'vdd': [lat_vss], 'gnd': [lat_vdd]}
    sel = {'vdd': [], 'gnd': []}
    ptr = {'vdd': 0, 'gnd': 0}
    turn = 'vdd' if len(cand['vdd'][0][1]) >= len(cand['gnd'][0][1]) else 'gnd'
    while len(sel['vdd']) < n_cols or len(sel['gnd']) < n_cols:
        progressed = False
        for _ in range(2):
            net = turn
            while ptr[net] < len(cand[net]):
                c, group = cand[net][ptr[net]]
                ptr[net] += 1
                if any(abs(c - c2) < min_same for c2, _ in sel[net]): continue
                if any(abs(c - c2) < min_opp for c2, _ in sel['gnd' if net=='vdd' else 'vdd']): continue
                ok = True
                for off in macro_offsets:
                    dx = off + c
                    for lat in latt[net]:
                        if min(abs(dx - s) for s in lat) < min_core_clear:
                            ok = False; break
                    if not ok: break
                if not ok: continue
                sel[net].append((c, group))
                progressed = True
                break
            turn = 'gnd' if turn == 'vdd' else 'vdd'
        if not progressed:
            break
    return sel['vdd'], sel['gnd']

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--lef', required=True)
    ap.add_argument('--facts', required=True)
    ap.add_argument('--out-lef', required=True)
    ap.add_argument('--out-tcl', required=True)
    ap.add_argument('--cols', type=int, default=12)
    args = ap.parse_args()

    txt2, vdd, gnd = parse_lef_pins(args.lef)
    macros, straps = parse_facts(args.facts)
    if not macros:
        sys.exit('facts 里没有 MACRO 行')
    offsets = [m[1] for m in macros]
    lat_vdd = sorted(set((a+b)/2.0 for a, b in straps['VDD']))
    lat_vss = sorted(set((a+b)/2.0 for a, b in straps['VSS']))
    print(f'met4 栅格: VDD {len(lat_vdd)} 条, VSS {len(lat_vss)} 条; 实例原点 {offsets}')

    sel_vdd, sel_gnd = pick_columns_joint(vdd, gnd, lat_vss, lat_vdd,
                                           offsets, n_cols=args.cols)
    nv = sum(len(g) for _, g in sel_vdd); ng = sum(len(g) for _, g in sel_gnd)
    print(f'选定电源条: VDD {len(sel_vdd)} 条/{nv} 焊盘, VSS {len(sel_gnd)} 条/{ng} 焊盘')
    if len(sel_vdd) < 6 or len(sel_gnd) < 6:
        sys.exit('电源条太少, 列选择约束过紧, 请检查')

    macro_end_re = re.compile(r'(END\s+sky130_sram_1rw1r_128x256_8)', re.S)
    def pin_section(name, use, cols, macro_h=632.475):
        s = f'   PIN {name}\n      DIRECTION INOUT ;\n      USE {use} ; \n      SHAPE ABUTMENT ; \n'
        for c, group in cols:
            c = snap5(c)
            s += '      PORT\n         LAYER met4 ;\n'
            s += f'         RECT  {snap5(c-0.8):.3f} 52.000 {snap5(c+0.8):.3f} {snap5(macro_h):.3f} ;\n'
            s += '      END\n'
        s += f'   END {name}\n'
        return s
    insert = ('   # ---- P4A 衍生注记 ----\n'
              '   # vdd/gnd 原为 3358/2992 个 0.49um met3 焊盘(两网交错散布),\n'
              '   # 此处改声明为 met4 电源条(与 ORFS microwatt RAM512 同形态)。\n'
              '   # 实际几何由 syn/amechip/scripts/pdn_macro_fix.tcl 在 POST_PDN\n'
              '   # 画出, 并经 via3(M3M4_PR) 下接到条下方的原 met3 焊盘。\n'
              '   # OBS 段中与焊盘矩形重合的 met3 阻碍已剔除(原 LEF 把每个焊盘\n'
              '   # 同时声明为引脚与阻碍, 自相矛盾; 引脚形状本身即对布线器成阻挡)。\n')
    insert += pin_section('vdd', 'POWER', sel_vdd)
    insert += pin_section('gnd', 'GROUND', sel_gnd)
    out_txt, nsub = macro_end_re.subn(insert + r'\1', txt2, count=1)
    if nsub != 1:
        sys.exit('未找到 MACRO END 行')

    all_pads = vdd + gnd
    pad_x = sorted(all_pads, key=lambda r: r[0])
    def obs_overlaps_pad(o):
        for p in pad_x:
            if p[0] > o[2]:
                break
            if p[2] > o[0] and p[1] < o[3] and p[3] > o[1]:
                return True
        return False
    lines = out_txt.splitlines(True)
    obs_start = None
    for n, l in enumerate(lines):
        if l.strip() == 'OBS':
            obs_start = n
            break
    if obs_start is None:
        sys.exit('未找到 OBS 段')
    new_lines = []
    cur_layer = None
    n_obs_removed = 0
    for l in lines:
        s = l.strip()
        if s.startswith('LAYER') and s.endswith(';'):
            cur_layer = s
            new_lines.append(l)
            continue
        if (cur_layer == 'LAYER  met3 ;' and 'RECT' in s):
            vals = [float(v) for v in re.findall(r'-?[\d.]+', s)]
            if len(vals) == 4:
                o = (min(vals[0],vals[2]), min(vals[1],vals[3]), max(vals[0],vals[2]), max(vals[1],vals[3]))
                if obs_overlaps_pad(o):
                    n_obs_removed += 1
                    continue
        new_lines.append(l)
    out_txt = ''.join(new_lines)
    print(f'OBS met3 修剪: 剔除与焊盘重叠的 {n_obs_removed} 条(原 23406)')
    with open(args.out_lef, 'w') as f:
        f.write(out_txt)

    with open(args.out_tcl, 'w') as f:
        f.write('# 自动生成(gen_macro_lef.py), 勿手改: 宏焊盘(met3, master 坐标) + 电源条列\n')
        f.write('set AME_PADS(vdd) [list\\\n')
        for r in vdd:
            f.write(f'  [list {r[0]:.3f} {r[1]:.3f} {r[2]:.3f} {r[3]:.3f}]\\\n')
        f.write(']\nset AME_PADS(gnd) [list\\\n')
        for r in gnd:
            f.write(f'  [list {r[0]:.3f} {r[1]:.3f} {r[2]:.3f} {r[3]:.3f}]\\\n')
        f.write(']\nset AME_COLS(vdd) [list')
        for c, _ in sel_vdd: f.write(f' {snap5(c):.3f}')
        f.write(']\nset AME_COLS(gnd) [list')
        for c, _ in sel_gnd: f.write(f' {snap5(c):.3f}')
        f.write(']\n')
    print(f'写出 {args.out_lef} 与 {args.out_tcl}')
    for nm, sel in (('vdd', sel_vdd), ('gnd', sel_gnd)):
        for c, group in sel:
            for r in group:
                cx = (r[0]+r[2])/2.0
                assert abs(cx - c) <= 0.635 + 1e-9, (nm, c, cx)
    print('列内焊盘覆盖校验通过(±0.635um)')

if __name__ == '__main__':
    main()
