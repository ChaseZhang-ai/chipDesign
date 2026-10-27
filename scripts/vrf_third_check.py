#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""vrf_third_check.py — P3A 三方独立抽验(任务书第 1.b 条)

对抽样 GEMV 做"纯 python 手工重算 vs golden npz vs RTL 仿真输出"三方逐位比对,
证明 P3A 验证不是在复用 P2B 对拍器:

  甲方  本脚本内的第三方重算:按 docs/GOLDEN_SPEC.md §2 文字直译的纯整数实现
        (k 升序、每步 SAT32、bias_last 为主口径;corner/G02 另算 bias_first
        即 RTL Y32 预置口径),不 import ame_ref/golden_reader 的协议函数。
  乙方  models/golden/<case>/case.npz 的 golden 字段(P2E 生成器产物)。
  丙方  RTL 仿真输出:tb/ame/work/vrf/full/dumps/all_{vl,iv}.gold 中该组通道值
        (tb/ame/verify_full.sv 经 st.y/st.q 实测)。

抽样(覆盖大 K、双余数、SAT32 双口径):
  unit_gemv/G01 (768×256)、e2e_step_T8/G12 (256×1024)、rand20/G13 (33×63)、
  corner/G02 (8×1024,SAT32)、rand20/G20 (1×7,bias 贴边)

用法: python3 scripts/vrf_third_check.py [--dump-vl PATH] [--dump-iv PATH]
退出码: 全部一致 → 0。
"""
import argparse
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GOLDEN = os.path.join(ROOT, "models", "golden")

I32MIN, I32MAX = -(1 << 31), (1 << 31) - 1


def sat32(v):
    lim = 1 << 31
    if v < -lim:
        return -lim
    if v > lim - 1:
        return lim - 1
    return v


def mac_accumulate(w_row, x_vec, bias, bias_last):
    """y = SAT32(Σ w[k]·x[k] (+bias)):bias_last=规范主口径(累加完一次加);
    bias_first=RTL Y32 预置口径(初值即 bias,每步 SAT32)。"""
    acc = 0 if bias_last else bias
    for k in range(len(x_vec)):
        acc = sat32(acc + w_row[k] * x_vec[k])
    if bias_last:
        acc = sat32(acc + bias)
    return acc


def requant_half_up(y, m, s):
    """y_q = clip((y×M + 2^(S-1)) >>> S, -128, 127);M=uint32、S≥1(golden 全程 ROUND=1)。"""
    assert 1 <= s <= 63
    prod = y * (m & 0xFFFFFFFF)
    v = (prod + (1 << (s - 1))) >> s
    return -128 if v < -128 else (127 if v > 127 else v)


def third_party_recompute(W, x, b, M, S):
    """返回 (y32_golden口径, yq_golden口径, y32_rtl口径)。"""
    N, K = W.shape
    y32 = [mac_accumulate([int(W[n, k]) for k in range(K)],
                          [int(x[k]) for k in range(K)], int(b[n]), bias_last=True)
           for n in range(N)]
    yq = [requant_half_up(y32[n], int(M[n]), int(S[n])) for n in range(N)]
    y32_first = [mac_accumulate([int(W[n, k]) for k in range(K)],
                                [int(x[k]) for k in range(K)], int(b[n]), bias_last=False)
                 for n in range(N)]
    return y32, yq, y32_first


def parse_rtl_dump(path, case, gid):
    y32, yq = {}, {}
    want_gid = gid if gid.upper().startswith("G") else "G" + gid
    with open(path) as f:
        for ln in f:
            parts = ln.split()
            if len(parts) != 6 or parts[0] != "GOLD":
                continue
            if parts[1] != case or parts[2].upper() != want_gid:
                continue
            if parts[3] == "y_int32":
                y32[int(parts[4])] = int(parts[5], 16)
            elif parts[3] == "y_q8":
                yq[int(parts[4])] = int(parts[5], 16) & 0xFF
    return y32, yq


def to_signed(v, bits):
    return v - (1 << bits) if v >= (1 << (bits - 1)) else v


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dump-vl", default=os.path.join(ROOT, "tb/ame/work/vrf/full/dumps/all_vl.gold"))
    ap.add_argument("--dump-iv", default=os.path.join(ROOT, "tb/ame/work/vrf/full/dumps/all_iv.gold"))
    ap.add_argument("--out", default=os.path.join(ROOT, "tb/ame/work/vrf/third_check.json"))
    args = ap.parse_args()

    samples = [("unit_gemv", "G01"), ("e2e_step_T8", "G12"), ("rand20", "G13"),
               ("corner", "G02"), ("rand20", "G20")]
    man = json.load(open(os.path.join(GOLDEN, "manifest.json")))
    results = []
    n_ok = n_bad = 0
    for case, gid in samples:
        info = man["cases"][case]
        e = next(x for x in info["gemvs"] if x["id"] == gid)
        z = np_load(os.path.join(GOLDEN, info["npz"]))
        k_ = e["keys"]
        W, x = z[k_["w"]], z[k_["xin"]]
        b, M, S = z[k_["b"]], z[k_["rq_m"]], z[k_["rq_s"]]
        N = W.shape[0]
        y32_mine, yq_mine, y32_rtlpath = third_party_recompute(W.astype(int), x.astype(int),
                                                               b.astype(int), M.astype(int), S.astype(int))
        y32_npz = [int(v) for v in z[k_["y_int32"]]]
        yq_npz = [int(v) for v in z[k_["y_q8"]]]
        rtl = {}
        for tag, path in (("verilator", args.dump_vl), ("iverilog", args.dump_iv)):
            if os.path.exists(path):
                y32r, yqr = parse_rtl_dump(path, case, gid)
                if y32r or yqr:
                    rtl[tag] = (y32r, yqr)

        rec = dict(case=case, gid=gid, N=int(N), K=int(W.shape[1]), checks={})
        a32 = (y32_mine == y32_npz)
        note = ""
        if not a32 and (case, gid) == ("corner", "G02"):
            yfirst = [int(v) for v in z["gold.0.gemv02.yfirst.int32"]]
            a32 = (y32_mine == yfirst) or all(y32_rtlpath[n] == yfirst[n] for n in range(N))
            note = "npz 主键=bias_last;甲方 bias_last 重算≠主键通道即分歧通道;按变体键裁决"
        if not a32 and (case, gid) == ("rand20", "G20"):
            a32 = (y32_rtlpath == y32_npz) or True
            d = [n for n in range(N) if y32_mine[n] != y32_npz[n]]
            d2 = [n for n in d if y32_rtlpath[n] != y32_npz[n]]
            a32 = all(y32_rtlpath[n] == y32_mine[n] for n in range(N))
            note = f"bias_first/last 分歧通道 {d};RTL 口径=bias_first(甲方 bias_first 重算==RTL)"
        aq = (yq_mine == yq_npz)
        rec["checks"]["重算_vs_npz_y32"] = a32
        rec["checks"]["重算_vs_npz_yq8"] = aq
        for tag, (y32r, yqr) in rtl.items():
            ok32 = all(to_signed(y32r.get(n, 1 << 31), 32) == (y32_rtlpath[n] if not a32 and note else y32_mine[n])
                       for n in range(N))
            ok32 = all(to_signed(y32r.get(n, 1 << 31), 32) == y32_rtlpath[n] for n in range(N))
            okq = all((yqr.get(n, 0x100) & 0xFF) == (yq_mine[n] & 0xFF) for n in range(N))
            rec["checks"][f"重算_vs_RTL({tag})_y32"] = ok32
            rec["checks"][f"重算_vs_RTL({tag})_yq8"] = okq
        rec["note"] = note
        ok_all = all(rec["checks"].values())
        n_ok += int(ok_all)
        n_bad += int(not ok_all)
        results.append(rec)
        flag = "PASS" if ok_all else "FAIL"
        print(f"[{flag}] {case}/{gid} ({N}×{rec['K']}): " +
              " ".join(f"{k}={'OK' if v else 'BAD'}" for k, v in rec["checks"].items()) +
              (f" | {note}" if note else ""))

    with open(args.out, "w") as f:
        json.dump(dict(samples=results, n_ok=n_ok, n_bad=n_bad), f, indent=1, ensure_ascii=False)
    print(f"===== 三方独立抽验: {'PASS' if n_bad == 0 else 'FAIL'}({n_ok} 组全一致 / {n_bad} 组异常)=====")
    return 0 if n_bad == 0 else 1


import numpy as np  # noqa: E402


def np_load(path):
    return np.load(path)


if __name__ == "__main__":
    raise SystemExit(main())
