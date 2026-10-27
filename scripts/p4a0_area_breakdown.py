#!/usr/bin/env python3
# -----------------------------------------------------------------------------
#
#   python3 scripts/p4a0_area_breakdown.py \
#     <1_2_yosys.v> <sky130_fd_sc_hd__tt_025C_1v80.lib>
#
# -----------------------------------------------------------------------------
import re
import sys
from collections import defaultdict

NETLIST, LIBERTY = sys.argv[1], sys.argv[2]

# ---- liberty cell -> area ----
areas = {}
cur = None
with open(LIBERTY, errors="ignore") as f:
    for line in f:
        m = re.search(r'cell\s*\(\s*"?([^")\s]+)"?\s*\)\s*\{', line)
        if m:
            cur = m.group(1)
            continue
        m = re.search(r'\barea\s*:\s*([0-9.eE+-]+)\s*;', line)
        if m and cur:
            areas[cur] = float(m.group(1))
            cur = None

FLOPS = re.compile(r'^sky130_fd_sc_hd__(df|edf|sdf|dl)')
MUX = re.compile(r'^sky130_fd_sc_hd_(mux|mux2|mux4|a[0-9]+[io]|o[0-9]+[a-z]*i?)')
BUF = re.compile(r'^sky130_fd_sc_hd_(buf|clkbuf)_')
INV = re.compile(r'^sky130_fd_sc_hd_(inv|clkinv)_')

groups = defaultdict(lambda: {"n": 0, "area": 0.0, "ff": 0, "mux": 0, "buf": 0, "inv": 0})
cell_re = re.compile(r'^\s+(sky130_fd_sc_hd__\w+)\s+(\S+)\s+\(')

def group_of(name):
    n = name.lstrip('\\')
    if n.startswith('u_ame.'):
        if '.u_wbuf' in n:   return 'AME:WBUF (1KB flop RF)'
        if '.u_xbuf' in n:   return 'AME:XBUF (1KB flop RF)'
        if '.u_array' in n:  return 'AME:array (tile/x/Y/MAC)'
        if '.u_rqtab' in n:  return 'AME:rqtab'
        if '.u_ctrl' in n:   return 'AME:ctrl'
        return 'AME:requant+glue'
    if n.startswith('u_cpu.'):
        if '.u_rf' in n:      return 'CPU:regfile'
        if '.u_alu' in n:     return 'CPU:ALU'
        if '.u_muldiv' in n:  return 'CPU:MUL/DIV'
        if '.u_csr' in n:     return 'CPU:CSR'
        if '.u_bridge' in n:  return 'CPU:AXI bridge'
        return 'CPU:core+glue'
    if n.startswith('u_mem.'):
        if '.u_ocram' in n:   return 'MEM:OC SRAM (4KB flop)'
        if '.u_bootrom' in n: return 'MEM:BOOT ROM (2KB flop)'
        if '.u_xbar' in n:    return 'MEM:xbar'
        if '.u_dma' in n:     return 'MEM:DMA'
        if '.u_kvc' in n:     return 'MEM:KV ctrl'
        if '.u_kvbe' in n:    return 'MEM:KV backend'
        if '.u_memc' in n:    return 'MEM:MEMC(XMEM)'
        if any(f'.u_{x}' in n for x in ('m0','s2','s3','s4','win')):
            return 'MEM:bundle<->AXI shims'
        return 'MEM:mem_ss_top glue'
    if n.startswith('u_uart'):    return 'PERIPH:UART'
    if n.startswith('u_sys'):     return 'PERIPH:SYS CSR'
    if n.startswith('u_intc'):    return 'PERIPH:INTC'
    if n.startswith('u_cr'):      return 'PERIPH:clk/rst sync'
    if n.startswith('u_bootrom'): return 'PERIPH:BOOT ROM (top, dead)'
    return 'TOP:glue/other'

total = {"n": 0, "area": 0.0, "ff": 0, "mux": 0, "buf": 0, "inv": 0}
with open(NETLIST, errors="ignore") as f:
    for line in f:
        m = cell_re.match(line)
        if not m:
            continue
        ctype, iname = m.group(1), m.group(2)
        a = areas.get(ctype, 0.0)
        g = groups[group_of(iname)]
        for d in (g, total):
            d["n"] += 1
            d["area"] += a
            if FLOPS.match(ctype): d["ff"] += 1
            if MUX.match(ctype):   d["mux"] += 1
            if BUF.match(ctype):   d["buf"] += 1
            if INV.match(ctype):   d["inv"] += 1

print(f"# P4A0 area breakdown (post-synth, sky130hd tt)\n")
print(f"netlist: `{NETLIST}`\n")
print("| group | cells | area µm² | area mm² | share | flops | mux/aoi | buf | inv |")
print("|---|---:|---:|---:|---:|---:|---:|---:|---:|")
for k in sorted(groups, key=lambda x: -groups[x]["area"]):
    d = groups[k]
    share = 100.0 * d["area"] / total["area"] if total["area"] else 0
    print(f"| {k} | {d['n']} | {d['area']:.0f} | {d['area']/1e6:.3f} | {share:.1f}% | {d['ff']} | {d['mux']} | {d['buf']} | {d['inv']} |")
print(f"| **TOTAL** | **{total['n']}** | **{total['area']:.0f}** | **{total['area']/1e6:.3f}** | **100%** | **{total['ff']}** | **{total['mux']}** | **{total['buf']}** | **{total['inv']}** |")

print("\n## inferred memories (from canonicalized RTLIL dump)\n")
print("| instance | width | depth | bits |")
print("|---|---:|---:|---:|")
for inst, w, d in [
    ("u_mem.u_core.u_ocram.u_ram.mem", 32, 1024),
    ("u_mem.u_core.u_bootrom.u_ram.mem", 32, 512),
    ("u_ame.u_core.u_wbuf.mem", 8, 1024),
    ("u_ame.u_core.u_xbuf.mem", 8, 1024),
    ("u_ame.u_core.u_array.tile_q", 2048, 2),
    ("u_ame.u_core.u_array.x_q", 128, 2),
    ("u_mem.u_core.u_dma.fifo_mem", 32, 8),
    ("u_mem.u_core.u_memc (wq/rq addr/data)", 23, 8),
    ("u_uart tfifo/rfifo", 8, 32),
    ("u_cpu ROM (proc_rom)", 4, 8),
]:
    print(f"| {inst} | {w} | {d} | {w*d} |")
