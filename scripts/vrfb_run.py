#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""vrfb_run.py — P3B CPU+AME 联测一键回归(verilator 主 / iverilog 抽样)。

流程:
  1) vrfb_golden.py --all    生成 35 组配置(XMEM 镜像 + 期望 UART + 快照期望)
  2) build_hex.py asm ×3     汇编 verify_gemv/verify_decode/verify_edge(≤2KB 硬约束)
  3) 构建 verilator(--binary)与 iverilog 仿真器
  4) 逐配置运行:UART 字节级比对(TB 内)+ XMEM SCRATCH 快照 + KV 快照(python 逐字节)
  5) 汇总:回归统计 + 性能基线表 → reports/P3B_PERF.md

退出码:0 = 全部 PASS;非 0 = 有失败。

用法:
  python3 scripts/vrfb_run.py                 # verilator 全量 + iverilog 抽样
  python3 scripts/vrfb_run.py --quick         # 只跑小配置(冒烟)
  python3 scripts/vrfb_run.py --only g06_none # 指定配置子串
  python3 scripts/vrfb_run.py --no-iverilog
"""
import argparse
import os
import shutil
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TB = os.path.join(ROOT, "tb", "integ")
WORK = os.path.join(TB, "work")
HEXDIR = os.path.join(WORK, "hex")
CFGDIR = os.path.join(WORK, "cfg")
BUILD = os.path.join(WORK, "build")

PROGS = ["verify_gemv", "verify_decode", "verify_edge"]
RTL_CPU = ["amecpu_pkg.sv", "cpu_regfile.sv", "cpu_alu.sv", "cpu_muldiv.sv",
           "cpu_csr.sv", "cpu_axi_bridge.sv", "ame_cpu.sv"]
RTL_AME = ["ame_core.sv", "ame_ctrl.sv", "ame_array.sv", "ame_buf_rf.sv",
           "ame_requant.sv", "ame_rqtab.sv"]
RTL_SOC = ["soc_pkg.sv", "soc_uart.sv", "soc_syscsr.sv", "soc_intc.sv"]
TB_SRC = ["tb_cpu_ame.sv", "vrfb_axi2b.sv", "vrfb_xbar.sv", "vrfb_mem_model.sv",
          "vrfb_xmem_model.sv", "vrfb_dma_model.sv", "vrfb_kv_model.sv"]

def all_configs():
    cfgs = []
    for i in range(1, 26):
        cfgs.append((f"g{i:02d}", "verify_gemv", 3_000_000))
    cfgs += [
        ("g26_kt8",    "verify_gemv", 3_000_000),
        ("g27_n5k35",  "verify_gemv", 1_000_000),
        ("g28_k35",    "verify_gemv", 1_000_000),
        ("g29_n17k48", "verify_gemv", 1_000_000),
        ("g30_n1ext",  "verify_gemv", 1_000_000),
        ("g31_zero",   "verify_gemv", 1_000_000),
        ("d01_e2e",    "verify_decode", 25_000_000),
        ("d02_1layer", "verify_decode", 15_000_000),
        ("d03_2tok",   "verify_decode", 40_000_000),
        ("e01_edge",   "verify_edge", 2_000_000),
    ]
    return cfgs


QUICK = ["g26_kt8", "g27_n5k35", "g31_zero", "e01_edge"]
IVERI_SAMPLE = ["g26_kt8", "g27_n5k35", "e01_edge"]


def sh(cmd, timeout=None, quiet=False):
    if not quiet:
        print("+", " ".join(cmd) if isinstance(cmd, list) else cmd)
    r = subprocess.run(cmd, shell=isinstance(cmd, str), capture_output=True,
                       text=True, timeout=timeout)
    if r.returncode != 0 and not quiet:
        print(r.stdout[-3000:])
        print(r.stderr[-3000:])
    return r


def gen_golden():
    r = sh([sys.executable, os.path.join(ROOT, "scripts", "vrfb_golden.py"), "--all"])
    if r.returncode != 0:
        sys.exit("golden 生成失败")


def assemble():
    os.makedirs(HEXDIR, exist_ok=True)
    for p in PROGS:
        src = os.path.join(ROOT, "tb", "soc", "program", p + ".s")
        out = os.path.join(HEXDIR, p + ".hex")
        mp = os.path.join(HEXDIR, p + ".map")
        r = sh([sys.executable, os.path.join(ROOT, "scripts", "build_hex.py"), "asm",
                src, "-o", out, "--map", mp,
                "--text-limit", "2048", "--data-limit", "2048"])
        if r.returncode != 0:
            sys.exit(f"汇编失败: {p}")
        for line in r.stdout.splitlines():
            if line.startswith("asm:"):
                print("  ", line)


def build_verilator():
    os.makedirs(BUILD, exist_ok=True)
    exe = os.path.join(BUILD, "vsim")
    srcs = [os.path.join(TB, f) for f in TB_SRC]
    srcs += [os.path.join(ROOT, "rtl", "cpu", f) for f in RTL_CPU]
    srcs += [os.path.join(ROOT, "rtl", "ame", f) for f in RTL_AME]
    srcs += [os.path.join(ROOT, "rtl", "soc", f) for f in RTL_SOC]
    srcs += [os.path.join(ROOT, "rtl", "amechip_pkg.sv")]
    cmd = ["verilator", "--binary", "--top-module", "tb_cpu_ame", "-j", "8",
           "--Mdir", os.path.join(BUILD, "obj_v"), "-o", exe,
           "-Wno-fatal", "-Wno-WIDTHEXPAND", "-Wno-WIDTHTRUNC",
           "-Wno-INITIALDLY", "-Wno-UNOPTFLAT", "-Wno-CASEINCOMPLETE",
           "-Wno-SYNCASYNCNET", "-Wno-LATCH",
           "-I" + os.path.join(ROOT, "rtl"),
           "-I" + os.path.join(ROOT, "rtl", "interfaces"),
           "-I" + os.path.join(ROOT, "rtl", "soc"),
           "-I" + os.path.join(ROOT, "rtl", "cpu"),
           "-I" + os.path.join(ROOT, "rtl", "ame")] + srcs
    t0 = time.time()
    r = sh(cmd, timeout=900, quiet=False)
    if r.returncode != 0:
        print(r.stdout[-4000:]); print(r.stderr[-4000:])
        sys.exit("verilator 构建失败")
    print(f"  verilator ok ({time.time()-t0:.1f}s)")
    return exe


def build_iverilog():
    os.makedirs(BUILD, exist_ok=True)
    exe = os.path.join(BUILD, "isim")
    srcs = [os.path.join(TB, f) for f in TB_SRC]
    srcs += [os.path.join(ROOT, "rtl", "cpu", f) for f in RTL_CPU]
    srcs += [os.path.join(ROOT, "rtl", "ame", f) for f in RTL_AME]
    srcs += [os.path.join(ROOT, "rtl", "soc", f) for f in RTL_SOC]
    srcs += [os.path.join(ROOT, "rtl", "amechip_pkg.sv")]
    cmd = ["iverilog", "-g2012",
           "-I" + os.path.join(ROOT, "rtl"),
           "-I" + os.path.join(ROOT, "rtl", "interfaces"),
           "-I" + os.path.join(ROOT, "rtl", "soc"),
           "-I" + os.path.join(ROOT, "rtl", "cpu"),
           "-I" + os.path.join(ROOT, "rtl", "ame"),
           "-s", "tb_cpu_ame", "-o", exe] + srcs
    t0 = time.time()
    r = sh(cmd, timeout=1200, quiet=False)
    if r.returncode != 0:
        print(r.stdout[-4000:]); print(r.stderr[-4000:])
        sys.exit("iverilog 构建失败")
    print(f"  iverilog ok ({time.time()-t0:.1f}s)")
    return exe


def parse_hex_sparse(path):
    """稀疏 word hex(@addr) → dict[word_idx] = value;空文件 → {}。"""
    d = {}
    cur = 0
    if not os.path.exists(path):
        return d
    for line in open(path):
        line = line.strip()
        if not line:
            continue
        if line.startswith("@"):
            cur = int(line[1:], 16)
        else:
            d[cur] = int(line, 16)
            cur += 1
    return d


def cmp_region(exp_path, got_path, nwords):
    """dump 文件(稠密,word/行)vs 期望(稀疏)。返回 (ok, first_mismatch)。"""
    exp = parse_hex_sparse(exp_path)
    got = parse_hex_sparse(got_path)
    for w in range(nwords):
        e = exp.get(w, 0)
        g = got.get(w, 0)
        if e != g:
            return False, f"word{w:06X} exp={e:08X} got={g:08X}"
    return True, ""


def count_lines(path):
    if not os.path.exists(path):
        return 0
    return sum(1 for l in open(path) if l.strip())


def run_one(exe, name, prog, maxcyc, extra=[]):
    cfg = os.path.join(CFGDIR, name)
    if not os.path.isdir(cfg):
        return {"name": name, "ok": False, "err": "cfg 缺失"}
    args = [exe,
            f"+SRAM_HEX={os.path.join(HEXDIR, prog + '.hex')}",
            f"+BOOT_HEX={os.path.join(ROOT, 'tb', 'soc', 'build', 'boot_jump.hex')}",
            f"+XMEM_HEX={os.path.join(cfg, 'xmem.hex')}",
            f"+KV_HEX={os.path.join(cfg, 'kv.hex')}",
            f"+EXP_UART={os.path.join(cfg, 'exp_uart.hex')}",
            f"+NEXP={count_lines(os.path.join(cfg, 'exp_uart.hex'))}",
            f"+SCR_DUMP={os.path.join(cfg, 'scr_dump.hex')}",
            f"+SCR_BASE_W={0x120000}",
            f"+SCR_WORDS={json_meta(cfg).get('scr_words', 0)}",
            f"+KV_DUMP={os.path.join(cfg, 'kv_dump.hex')}",
            f"+MAXCYC={maxcyc}"] + extra
    t0 = time.time()
    try:
        r = subprocess.run(args, capture_output=True, text=True, timeout=maxcyc / 2000 + 600)
    except subprocess.TimeoutExpired:
        return {"name": name, "ok": False, "err": "host timeout"}
    dt = time.time() - t0
    log = r.stdout + r.stderr
    with open(os.path.join(cfg, "run.log"), "w") as f:
        f.write(log)
    res = {"name": name, "ok": False, "log": log, "sec": dt}
    for line in log.splitlines():
        if line.startswith("PERF "):
            res["perf"] = dict(kv.split("=") for kv in line.split()[1:])
        if line.startswith("AME_MON "):
            res["mon"] = line
        if line.startswith("AME_STALL "):
            res["stall"] = line
    res["uart_ok"] = "P3B PASS" in log
    meta = json_meta(cfg)
    nw = meta.get("scr_words", 0)
    if nw:
        ok, first = cmp_region(os.path.join(cfg, "exp_scr.hex"),
                               os.path.join(cfg, "scr_dump.hex"), nw)
        res["scr_ok"] = ok
        if not ok:
            res["scr_err"] = first
    else:
        res["scr_ok"] = True
    kvw = 2 * 2 * 4 * 16 * 16
    if os.path.exists(os.path.join(cfg, "exp_kv.hex")):
        ok, first = cmp_region(os.path.join(cfg, "exp_kv.hex"),
                               os.path.join(cfg, "kv_dump.hex"), kvw)
        res["kv_ok"] = ok
        if not ok:
            res["kv_err"] = first
    else:
        res["kv_ok"] = True
    res["ok"] = bool(res["uart_ok"] and res["scr_ok"] and res["kv_ok"])
    return res


_meta_cache = {}


def json_meta(cfg):
    import json
    if cfg not in _meta_cache:
        p = os.path.join(cfg, "meta.json")
        _meta_cache[cfg] = json.load(open(p)) if os.path.exists(p) else {}
    return _meta_cache[cfg]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--quick", action="store_true")
    ap.add_argument("--only", default=None)
    ap.add_argument("--no-iverilog", action="store_true")
    ap.add_argument("--no-build", action="store_true", help="跳过 golden/汇编/仿真器构建")
    ap.add_argument("--wave", default=None, help="指定配置名跑 VCD 波形(iverilog)")
    args = ap.parse_args()

    os.makedirs(WORK, exist_ok=True)
    if not args.no_build:
        print("== [1/4] golden 生成")
        gen_golden()
        print("== [2/4] 汇编微内核")
        assemble()
        print("== [3/4] 构建仿真器")
        vexe = build_verilator()
        iexe = build_iverilog() if not args.no_iverilog else None
    else:
        vexe = os.path.join(BUILD, "vsim")
        iexe = os.path.join(BUILD, "isim") if os.path.exists(os.path.join(BUILD, "isim")) else None

    cfgs = all_configs()
    if args.quick:
        cfgs = [c for c in cfgs if c[0] in QUICK]
    if args.only:
        cfgs = [c for c in cfgs if args.only in c[0]]

    print(f"== [4/4] 回归: {len(cfgs)} 配置(verilator)")
    results = []
    for name, prog, maxcyc in cfgs:
        r = run_one(vexe, name, prog, maxcyc)
        results.append(r)
        st = "PASS" if r["ok"] else "FAIL"
        p = r.get("perf", {})
        print(f"  [{st}] {name:12s} {r.get('sec',0):6.1f}s cyc={p.get('cyc','?'):>9s} "
              f"macs={p.get('macs','?'):>9s} "
              + ("" if r["ok"] else
                 f"uart={r['uart_ok']} scr={r.get('scr_ok')}{r.get('scr_err','')} "
                 f"kv={r.get('kv_ok')}{r.get('kv_err','')}"),
              flush=True)
        if not r["ok"]:
            for line in r["log"].splitlines():
                if "MISMATCH" in line or "FAIL" in line or "TIMEOUT" in line:
                    print("      ", line)

    iresults = []
    if iexe:
        sample = [c for c in cfgs if c[0] in IVERI_SAMPLE] if not args.only else cfgs[:2]
        if sample:
            print(f"== iverilog 抽样: {len(sample)} 配置")
            for name, prog, maxcyc in sample:
                r = run_one(iexe, name, prog, maxcyc)
                iresults.append(r)
                print(f"  [{'PASS' if r['ok'] else 'FAIL'}] {name:12s} {r.get('sec',0):6.1f}s",
                      flush=True)

    if args.wave:
        cfg = [c for c in all_configs() if c[0] == args.wave][0]
        if iexe:
            print(f"== 波形: {args.wave}(iverilog +WAVE)")
            run_one(iexe, cfg[0], cfg[1], cfg[2], extra=["+WAVE"])

    npass = sum(1 for r in results if r["ok"])
    nfail = len(results) - npass
    print("\n================ P3B 回归汇总 ================")
    print(f"verilator: PASS={npass} FAIL={nfail} (共 {len(results)})")
    if iresults:
        print(f"iverilog : PASS={sum(1 for r in iresults if r['ok'])}/{len(iresults)}")
    if nfail == 0:
        print("P3B REGRESSION: ALL PASS")
    else:
        print("P3B REGRESSION: FAIL")
        for r in results:
            if not r["ok"]:
                print("  FAIL", r["name"], r.get("err", ""),
                      r.get("scr_err", ""), r.get("kv_err", ""))

    write_perf_table(results, iresults)
    sys.exit(0 if nfail == 0 else 1)


def write_perf_table(results, iresults):
    """性能基线表 → reports/P3B_PERF.md(报告 P3B_REPORT.md 引用)。"""
    rows = []
    for r in results:
        p = r.get("perf", {})
        if not p:
            continue
        cyc = int(p.get("cyc", 0))
        macs = int(p.get("macs", 0))
        ab = int(p.get("ame_busy", 0))
        mac = int(p.get("mac", 0))
        ret = int(p.get("retired", 0))
        rows.append({
            "name": r["name"], "cyc": cyc, "retired": ret,
            "ipc": (ret / cyc) if cyc else 0,
            "ame_busy": ab, "mac_cyc": mac,
            "ame_duty": (mac / cyc) if cyc else 0,
            "macs": macs, "mac_per_cyc": (macs / cyc) if cyc else 0,
            "dma_busy": int(p.get("dma_busy", 0)), "kv_busy": int(p.get("kv_busy", 0)),
            "cpu_bus": int(p.get("cpu_bus", 0)), "ok": r["ok"],
        })
    out = os.path.join(ROOT, "reports", "P3B_PERF.md")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w") as f:
        f.write("# P3B 性能基线(自动生成:scripts/vrfb_run.py)\n\n")
        f.write("口径:行为模型总线(per-slave RR,单笔在途);XMEM 2 拍/32-bit(≈§4.8);\n")
        f.write("AME duty = MAC 发射拍/总周期;周期含 UART 打印(130 拍/字节,DIV=13)。\n\n")
        f.write("| 配置 | 总周期 | 退役指令 | IPC | AME BUSY | MAC 拍 | AME duty | MACs | MAC/拍 | DMA BUSY | KV BUSY | CPU 总线在途 | 结果 |\n")
        f.write("|---|---|---|---|---|---|---|---|---|---|---|---|---|\n")
        for x in rows:
            f.write(f"| {x['name']} | {x['cyc']} | {x['retired']} | {x['ipc']:.3f} | "
                    f"{x['ame_busy']} | {x['mac_cyc']} | {x['ame_duty']*100:.1f}% | "
                    f"{x['macs']} | {x['mac_per_cyc']:.3f} | {x['dma_busy']} | "
                    f"{x['kv_busy']} | {x['cpu_bus']} | {'PASS' if x['ok'] else 'FAIL'} |\n")
    print(f"性能表 → {out}")


if __name__ == "__main__":
    main()
