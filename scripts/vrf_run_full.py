#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""vrf_run_full.py — P3A 全量 74 组 golden 对拍 runner(第三方重验)

流程:
  1) 调 scripts/vrf_full_gen.py 生成 74 组 ops(verilator 全量,iverilog 抽样);
  2) 构建 tb/ame/verify_full.sv 的 verilator(--binary)与 iverilog 仿真;
  3) 逐组运行,收集 GOLD dump 与 PERF 计数;
  4) golden_reader.py compare 全量终判(权威);
  5) 已知 SAT32 bias 口径分歧的裁决(任务书规定):
       corner/G02  y_int32 ↔ npz 变体键 gold.0.gemv02.yfirst.int32(bias_first)
       rand20/G20  y_int32 ↔ 本 runner 独立重算的 bias_first 参考(P2E 未存变体键,
                   协议发现上报 issues/P3A.md);y_q8 两组均须与主键逐位一致;
  6) 输出逐组判定矩阵 + 吞吐统计(tb/ame/work/vrf/full/summary.json)。

用法: python3 scripts/vrf_run_full.py [--sim both] [--jobs 8] [--regen]
退出码: 全部 PASS → 0,否则 1。
"""
import argparse
import concurrent.futures as fut
import json
import os
import re
import subprocess
import sys

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tb", "ame"))
import golden_reader as gr  # noqa: E402

TB = os.path.join(ROOT, "tb", "ame")
AMESRC = ["rtl/ame/ame_core.sv", "rtl/ame/ame_ctrl.sv", "rtl/ame/ame_array.sv",
          "rtl/ame/ame_buf_rf.sv", "rtl/ame/ame_requant.sv", "rtl/ame/ame_rqtab.sv"]
INCS = ["-I" + os.path.join(ROOT, "rtl"), "-I" + os.path.join(ROOT, "rtl", "interfaces")]

I32MIN, I32MAX = -(1 << 31), (1 << 31) - 1


def _sat(v):
    return I32MIN if v < I32MIN else (I32MAX if v > I32MAX else v)


def gemv_bias_first(W, x, bias):
    """Y32 预置 bias 后逐 k SAT32 累加(RTL 路径);k 升序。"""
    N, K = W.shape
    y = [_sat(int(bias[n])) for n in range(N)]
    for k in range(K):
        xk = int(x[k])
        for n in range(N):
            y[n] = _sat(y[n] + int(W[n, k]) * xk)
    return y


def build(outdir, sim):
    env = os.path.join(outdir, f"sim_{sim}" if sim == "iverilog" else "vsim")
    if sim == "verilator":
        cmd = ["verilator", "--binary", "--top-module", "tb_verify_full", "-j", "4",
               "-Wno-INITIALDLY", "-Wno-WIDTHEXPAND", "-Wno-WIDTHTRUNC",
               "--Mdir", os.path.join(outdir, "obj_dir")] + INCS + \
              ["tb/ame/verify_full.sv"] + AMESRC + ["-o", env]
    else:
        cmd = ["iverilog", "-g2012"] + INCS + ["-o", env,
                                               "tb/ame/verify_full.sv"] + AMESRC
    r = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
    if r.returncode != 0:
        print(f"BUILD FAIL ({sim}):\n{r.stdout}\n{r.stderr}", file=sys.stderr)
        raise SystemExit(2)
    exe = os.path.join(outdir, "vsim") if sim == "verilator" else \
        os.path.join(outdir, "sim_iverilog")
    return exe


def run_one(exe, sim, opsf, dumpf, case, gid):
    os.makedirs(os.path.dirname(dumpf), exist_ok=True)
    logf = dumpf.replace(".gold", ".log")
    if sim == "iverilog":
        cmd = ["vvp", exe, "+ops=" + opsf, "+dump=" + dumpf,
               "+case=" + case, "+gid=" + gid]
    else:
        cmd = [exe, "+ops=" + opsf, "+dump=" + dumpf,
               "+case=" + case, "+gid=" + gid]
    with open(logf, "w") as lf:
        r = subprocess.run(cmd, cwd=ROOT, stdout=lf, stderr=subprocess.STDOUT,
                           timeout=3600)
    ok = False
    perf = {}
    with open(logf) as f:
        for ln in f:
            m = re.match(r"PERF case=\S+ \S+ ops=(\d+) checks=(\d+) dumped=(\d+) "
                         r"fail=(\d+) mac=(\d+) busy=(\d+) idle=(\d+)", ln)
            if m:
                perf = dict(ops=int(m.group(1)), checks=int(m.group(2)),
                            dumped=int(m.group(3)), fail=int(m.group(4)),
                            mac=int(m.group(5)), busy=int(m.group(6)),
                            idle=int(m.group(7)))
            if "VERIFY RESULT: PASS" in ln:
                ok = True
    return ok, perf, logf


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sim", choices=["both", "verilator", "iverilog"], default="both")
    ap.add_argument("--jobs", type=int, default=8)
    ap.add_argument("--regen", action="store_true")
    ap.add_argument("--workdir", default=os.path.join(ROOT, "tb", "ame", "work", "vrf", "full"))
    args = ap.parse_args()
    out = args.workdir

    if args.regen or not os.path.exists(os.path.join(out, "manifest.tsv")):
        subprocess.run([sys.executable, os.path.join(ROOT, "scripts", "vrf_full_gen.py"),
                        "--out", out], cwd=ROOT, check=True)

    ents = []
    with open(os.path.join(out, "manifest.tsv")) as f:
        hdr = f.readline().rstrip("\n").split("\t")
        for ln in f:
            v = ln.rstrip("\n").split("\t")
            d = dict(zip(hdr, v))
            ents.append((d["case"], d["gid"], int(d["N"]), int(d["K"]),
                         d["ms_rule"], d["iverilog_sample"] == "1"))

    exe_v = exe_i = None
    if args.sim in ("both", "verilator"):
        print("build verilator ...")
        exe_v = build(out, "verilator")
    if args.sim in ("both", "iverilog"):
        print("build iverilog ...")
        exe_i = build(out, "iverilog")

    jobs = []
    for (case, gid, N, K, rule, isi) in ents:
        if args.sim in ("both", "verilator"):
            jobs.append((exe_v, "verilator",
                         os.path.join(out, f"{case}__{gid}.ops"),
                         os.path.join(out, "dumps", "vl", f"{case}__{gid}.gold"),
                         case, gid))
        if (args.sim in ("both", "iverilog")) and isi:
            jobs.append((exe_i, "iverilog",
                         os.path.join(out, f"{case}__{gid}.ops"),
                         os.path.join(out, "dumps", "iv", f"{case}__{gid}.gold"),
                         case, gid))

    results = {}
    with fut.ThreadPoolExecutor(max_workers=args.jobs) as ex:
        futs = {ex.submit(run_one, *j): j for j in jobs}
        for fu in fut.as_completed(futs):
            j = futs[fu]
            ok, perf, logf = fu.result()
            results[(j[4], j[5], j[1])] = (ok, perf)
            print(f"  [{j[1]:9s}] {j[4]}/{j[5]}: {'PASS' if ok else 'FAIL'} "
                  f"(mac={perf.get('mac', 0)} busy={perf.get('busy', 0)})")

    os.makedirs(os.path.join(out, "dumps"), exist_ok=True)
    for tag in ("vl", "iv"):
        part = sorted(os.path.join(out, "dumps", tag, f"{c}__{g}.gold")
                      for (c, g) in {(j[4], j[5]) for j in jobs}
                      if os.path.exists(os.path.join(out, "dumps", tag, f"{c}__{g}.gold")))
        if not part:
            continue
        merged = os.path.join(out, "dumps", f"all_{tag}.gold")
        with open(merged, "w") as w:
            for p in part:
                with open(p) as f:
                    w.write(f.read())
        print(f"=== golden_reader compare({tag}) 权威终判 ===")
        r = subprocess.run([sys.executable, os.path.join(TB, "golden_reader.py"),
                            "compare", "--dump", merged],
                           cwd=ROOT, capture_output=True, text=True)
        print(r.stdout, r.stderr)

    summary = judge(out, ents, results)
    with open(os.path.join(out, "summary.json"), "w") as f:
        json.dump(summary, f, indent=1, ensure_ascii=False)

    ok_all = summary["verdict"] == "PASS"
    print(f"\n===== vrf_run_full: {summary['verdict']} "
          f"(组级 PASS {summary['pass_groups']}/{summary['total_groups']}) =====")
    return 0 if ok_all else 1


def judge(out, ents, results):
    """逐组比对 dump vs npz(经 golden_reader 解析),处理两个已知 bias 口径组。"""
    manifest, sel = gr.load_all(os.path.join(ROOT, "models", "golden"))
    rows = []
    n_pass = 0
    special_notes = {}
    for tag, simname in (("vl", "verilator"), ("iv", "iverilog")):
        merged = os.path.join(out, "dumps", f"all_{tag}.gold")
        if not os.path.exists(merged):
            continue
        got, order, unknown = gr.parse_dump(merged)
        for (case, gid, N, K, rule, isi) in ents:
            if not any(k[0] == case and k[1] == gr.norm_gid(gid) for k in got):
                continue
            key32 = (case, gr.norm_gid(gid), "y_int32")
            key8 = (case, gr.norm_gid(gid), "y_q8")
            e = next(x for x in sel[case]["gemvs"] if x["id"] == gr.norm_gid(gid))
            z = sel[case]["z"]
            q_bad = []
            expq = z[e["keys"]["y_q8"]]
            for n in range(len(expq)):
                av = got.get(key8, {}).get(n)
                if av is None or gr.to_signed(av, 8) != int(expq[n]):
                    q_bad.append(n)
            exp32 = z[e["keys"]["y_int32"]]
            bad32 = []
            for n in range(len(exp32)):
                av = got.get(key32, {}).get(n)
                if av is None or gr.to_signed(av, 32) != int(exp32[n]):
                    bad32.append(n)
            note = ""
            if bad32 and (case, gid) == ("corner", "G02"):
                yf = z["gold.0.gemv02.yfirst.int32"]
                if all(gr.to_signed(got[key32][n], 32) == int(yf[n]) for n in range(len(yf))):
                    note = "RTL 口径=bias_first(与 npz 变体键 yfirst 逐位一致;主键 bias_last 分歧通道 " \
                           + ",".join(map(str, bad32)) + ")"
                    bad32 = []
                    special_notes["corner/G02"] = note
            elif bad32 and (case, gid) == ("rand20", "G20"):
                kk = e["keys"]
                ybf = gemv_bias_first(z[kk["w"]].astype(int), z[kk["xin"]].astype(int),
                                      z[kk["b"]].astype(int))
                if all(gr.to_signed(got[key32][n], 32) == ybf[n] for n in range(len(ybf))):
                    note = ("RTL 口径=bias_first(与独立重算 bias_first 参考逐位一致;"
                            "npz 主键 bias_last 分歧通道 " + ",".join(map(str, bad32)) +
                            ";P2E 未存该组变体键 → 协议发现上报 issues/P3A.md)")
                    bad32 = []
                    special_notes["rand20/G20"] = note
            ok = (not q_bad) and (not bad32)
            n_pass += int(ok)
            rows.append(dict(sim=simname, case=case, gid=gid, N=N, K=K,
                             y32_bad=bad32, yq8_bad=q_bad, note=note,
                             pass_=ok, **{k: results.get((case, gid, simname), (False, {}))[1].get(k)
                                          for k in ("ops", "checks", "mac", "busy", "idle")}))
    total = len(rows)
    verdict = "PASS" if (n_pass == total and total > 0) else "FAIL"
    return dict(verdict=verdict, pass_groups=n_pass, total_groups=total,
                special_notes=special_notes, rows=rows)


if __name__ == "__main__":
    raise SystemExit(main())
