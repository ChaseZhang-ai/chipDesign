#!/usr/bin/env python3
# -----------------------------------------------------------------------------
#
# -----------------------------------------------------------------------------
import re
import sys

ROOT = '/home/zcz/verda/autoDecodeChip'
REF = f'{ROOT}/rtl/interfaces/amechip_top_ports.sv'
TOP = f'{ROOT}/rtl/soc/amechip_top.sv'

PORT_RE = re.compile(
    r'\b(input|output|inout)\s+(?:wire|logic|reg)?\s*'
    r'(?:\[\s*(\d+)\s*:\s*(\d+)\s*\])?\s*([A-Za-z_]\w*)\s*(?=\s*[,)]|\s*$)', re.M | re.X)


def parse_ports(path):
    src = open(path).read()
    m = re.search(r'\bmodule\s+\w+\s*(?:#\([^)]*\))?\s*\((.*?)\)\s*;', src, re.S)
    if not m:
        print(f'ERROR: {path} 中未找到模块端口头')
        sys.exit(1)
    body = m.group(1)
    ports = []
    for pm in PORT_RE.finditer(body):
        direction = pm.group(1)
        hi = int(pm.group(2)) if pm.group(2) is not None else 0
        lo = int(pm.group(3)) if pm.group(3) is not None else 0
        width = hi - lo + 1
        ports.append((pm.group(4), direction, width))
    return ports


def main():
    ref = parse_ports(REF)
    top = parse_ports(TOP)

    ref_map = {n: (d, w) for n, d, w in ref}
    top_map = {n: (d, w) for n, d, w in top}
    ok = True

    print(f'契约文件: {REF}')
    print(f'顶层文件: {TOP}')
    print(f'契约端口 {len(ref)} 个 / 顶层端口 {len(top)} 个\n')

    if len(ref) != len(top):
        print(f'FAIL: 端口数量不一致')
        ok = False
    for i, ((rn, rd, rw), (tn, td, tw)) in enumerate(zip(ref, top)):
        if rn != tn or rd != td or rw != tw:
            print(f'FAIL [{i}]: 契约 ({rn},{rd},{rw}) vs 顶层 ({tn},{td},{tw})')
            ok = False

    for n in ref_map:
        if n not in top_map:
            print(f'FAIL: 顶层缺少端口 {n}')
            ok = False
    for n in top_map:
        if n not in ref_map:
            print(f'FAIL: 顶层多出端口 {n}')
            ok = False
    for n, (d, w) in ref_map.items():
        if n in top_map and top_map[n] != (d, w):
            print(f'FAIL: {n} 方向/宽度不一致: 契约 {d}{w}bit vs 顶层 {top_map[n][0]}{top_map[n][1]}bit')
            ok = False

    if ok:
        print('端口逐项一致(名字/方向/位宽/顺序): PASS')
        for i, (n, d, w) in enumerate(ref, 1):
            print(f'  #{i:2d} {n:14s} {d:6s} [{w} bit]')
        return 0
    print('\n端口核对: FAIL')
    return 1


if __name__ == '__main__':
    sys.exit(main())
