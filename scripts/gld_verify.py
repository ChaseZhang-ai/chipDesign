#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""gld_verify.py — AME golden 独立复算器（任务书验收 a：全绿证明 npz 本身无错）。

读 models/golden/manifest.json，逐 case 逐 gemv：
  1) 按 GOLDEN_SPEC §2 用**本文件独立实现**的 numpy 整数协议重算 y_int32（k 逐步步进、
     每步 SAT32、bias 最后一次 SAT32 加入）并与 npz 存储值逐位比对；
  1b) 按 §9.1(P1BXB):存在 yfirst.int32 变体键时,另用独立的 bias_first 实现复算
     并与变体键逐位比对(RTL 规范口径);无变体键而两口径分歧时报 WARN;
  2) 按 manifest 条目的 ms_rule 复算 M/S 寄存器值并比对（§2.3 / 输出标定口径）；
  3) 用复算的 M/S 独立执行 §2.2 requant 并与 npz y_q8 逐位比对；
  4) 纯 python 整数双实现抽检（每 gemv 4 个通道全 k 循环，防 numpy 路径自身系统性错误）；
  5) 结构检查：protocol_version、键存在性、shape/dtype；e2e 另查 §6 正名键与链路一致性。

独立性声明（GOLDEN_SPEC §9）：本文件不 import gld_common/gld_gen，§2 协议独立实现；
M/S 复算用 python round()（banker's，与生成器声明的 float64 语义同口径、代码不同实现）。

用法：
  python scripts/gld_verify.py [--root models/golden] [-v]
退出码：0=全绿，1=存在 MISMATCH。
"""
import argparse
import json
import os
import sys

import numpy as np

I8MIN, I8MAX = -128, 127
I32MIN, I32MAX = -(1 << 31), (1 << 31) - 1
PROTOCOL_VERSION = "1.0"



def sat32(v):
    return I32MIN if v < I32MIN else (I32MAX if v > I32MAX else v)


def gemv_stepwise(w_q8, x_q8, b_int32):
    """§2.1：k 逐步步进累加，每步 SAT32；全部 k 完成后一次 SAT32 加 bias（bias_last）。"""
    w = np.asarray(w_q8, dtype=np.int64)
    x = np.asarray(x_q8, dtype=np.int64)
    b = np.asarray(b_int32, dtype=np.int64)
    n, k = w.shape
    y = np.zeros(n, dtype=np.int64)
    for kk in range(k):
        y = np.clip(y + w[:, kk] * x[kk], I32MIN, I32MAX)
    return np.clip(y + b, I32MIN, I32MAX)


def gemv_bias_first(w_q8, x_q8, b_int32):
    """§2.1 bias_first 规范口径(GOLDEN_SPEC §9.1):y=b 起步,每个 k 步 SAT32。
    与 gemv_stepwise(bias_last 兼容口径)相互独立实现。"""
    w = np.asarray(w_q8, dtype=np.int64)
    x = np.asarray(x_q8, dtype=np.int64)
    b = np.asarray(b_int32, dtype=np.int64)
    n, k = w.shape
    y = np.clip(b, I32MIN, I32MAX).copy()
    for kk in range(k):
        y = np.clip(y + w[:, kk] * x[kk], I32MIN, I32MAX)
    return y


def requant_one(y, m, s):
    """§2.2 ROUND_SEL=1，标量版（python int；P1BXB:入参强制标量化,
    numpy 2.x 下 np.uint8 参与 `1 << (s-1)` 会整数溢出）。"""
    y, m, s = int(y), int(m), int(s)
    prod = (y * m) & ((1 << 64) - 1)
    if prod >> 63:
        prod -= 1 << 64
    return max(I8MIN, min(I8MAX, (prod + (1 << (s - 1))) >> s))


def requant_vec(y32, m, s):
    return np.array([requant_one(y, mm, ss) for y, mm, ss in zip(y32, m, s)], dtype=np.int64)


def pick_ms_indep(scale_out):
    """§2.3 独立实现：python round()（banker's）+ 降序找首个 M<=2^31-1。"""
    so = float(scale_out)
    for s in range(63, 0, -1):
        m = int(round(so * float(1 << s)))
        if m <= I32MAX:
            return max(m, 1), s
    return I32MAX, 1


def cal_s_out(y32, per_ch_scale):
    est = np.asarray(y32, np.float64) * np.asarray(per_ch_scale, np.float64)
    return np.float32((float(np.max(np.abs(est))) if est.size else 0.0) / 127.0)



def recompute_ms(entry, z, y32, cache):
    """按 ms_rule 复算 (M[N], S[N])。cache 用于跨条目的组标定（PV 拼接）。"""
    rule = entry["ms_rule"]
    refs = entry.get("ms_refs", {})
    sx = float(z[entry["keys"]["sx_in"]])
    sw = (z[entry["keys"]["sw"]].astype(np.float64)
          if entry["keys"].get("sw") in z else None)

    if rule == "forced_1_1":
        return np.full(entry["N"], 1, np.uint32), np.full(entry["N"], 1, np.uint8)

    if rule == "perchannel":
        pairs = [pick_ms_indep(sx * s) for s in sw]
    elif rule == "perchannel_cal":
        s_out = cal_s_out(y32, sx * sw)
        s_out = s_out if float(s_out) > 0.0 else np.float32(1.0)
        pairs = [pick_ms_indep(sx * s / float(s_out)) for s in sw]
    elif rule == "wqkv_group_cal":
        est = y32 * (sx * sw)
        s_out_q = cal_s_out(est[:256], np.ones(256))
        pairs = [pick_ms_indep(sx * s / float(s_out_q)) for s in sw[:256]]
        for h in range(4):
            so = cal_s_out(est[256 + 64 * h:320 + 64 * h], np.ones(64))
            pairs += [pick_ms_indep(sx * s / float(so)) for s in sw[256 + 64 * h:320 + 64 * h]]
        for h in range(4):
            so = cal_s_out(est[512 + 64 * h:576 + 64 * h], np.ones(64))
            pairs += [pick_ms_indep(sx * s / float(so)) for s in sw[512 + 64 * h:576 + 64 * h]]
    elif rule == "qk_default":
        gid = int(entry["id"][1:])
        l = 0 if gid <= 12 else 1
        h = (gid - 2) % 4 if gid < 13 else (gid - 14) % 4
        s_kv = float(z[f"kv.0.L{l}.k.sx"][h])
        pairs = [pick_ms_indep(sx * s_kv)] * entry["N"]
    elif rule == "pv_cal":
        gid = int(entry["id"][1:])
        l = 0 if gid <= 12 else 1
        h = (gid - 6) % 4 if gid < 14 else (gid - 18) % 4
        s_p = float(z[f"act.0.L{l}.attn_prob.sx"])
        s_v = float(z[f"kv.0.L{l}.v.sx"][h])
        s_vs = z[f"kv.0.L{l}.v.sx"].astype(np.float64)
        est_all = [cache["pv_y32"][(l, hh)] * (s_p * s_vs[hh]) for hh in range(4)]
        s_attn = cal_s_out(np.concatenate(est_all), np.ones(256))
        pairs = [pick_ms_indep(s_p * s_v / float(s_attn))] * entry["N"]
    else:
        raise ValueError(f"未知 ms_rule {rule}")
    m = np.array([p[0] for p in pairs], np.uint32)
    s = np.array([p[1] for p in pairs], np.uint8)
    return m, s



FAILS = []


def check(cond, msg):
    if not cond:
        FAILS.append(msg)
    return cond


def verify_case(name, info, root, verbose=False):
    path = os.path.join(root, info["npz"])
    z = np.load(path)
    n_ok = 0
    cache = {"pv_y32": {}}

    for e in info["gemvs"]:
        if e["ms_rule"] == "pv_cal":
            gid = int(e["id"][1:])
            l = 0 if gid <= 12 else 1
            h = (gid - 6) % 4 if gid < 14 else (gid - 18) % 4
            cache["pv_y32"][(l, h)] = gemv_stepwise(
                z[e["keys"]["w"]], z[e["keys"]["xin"]], z[e["keys"]["b"]])

    for e in info["gemvs"]:
        gid = e["id"]
        keys = e["keys"]
        n, k = e["N"], e["K"]
        n_start_fails = len(FAILS)
        n_start_fails = len(FAILS)
        if not check(keys["w"] in z, f"{name}/{gid}: 缺 {keys['w']}"):
            continue
        w8 = z[keys["w"]]
        x8 = z[keys["xin"]]
        b32 = z[keys["b"]]
        y32_st = z[keys["y_int32"]].astype(np.int64)
        yq_st = z[keys["y_q8"]].astype(np.int64)
        m_st = z[keys["rq_m"]]
        s_st = z[keys["rq_s"]]

        check(w8.dtype == np.int8 and w8.shape == (n, k), f"{name}/{gid}: w 形状/类型 {w8.shape}{w8.dtype}")
        check(x8.dtype == np.int8 and x8.shape == (k,), f"{name}/{gid}: xin 形状/类型")
        check(b32.dtype == np.int32 and b32.shape == (n,), f"{name}/{gid}: b 形状/类型")
        check(y32_st.shape == (n,) and yq_st.shape == (n,), f"{name}/{gid}: y 形状")
        check(m_st.dtype == np.uint32 and s_st.dtype == np.uint8, f"{name}/{gid}: rq dtype")
        check(np.all(m_st >= 1) and np.all(m_st <= I32MAX), f"{name}/{gid}: M 越界")
        check(np.all(s_st >= 1) and np.all(s_st <= 63), f"{name}/{gid}: S 越界（协议禁止 S=0）")

        y32 = gemv_stepwise(w8, x8, b32)
        check(np.array_equal(y32, y32_st), f"{name}/{gid}: y_int32(bias_last) MISMATCH")
        yfirst_key = keys["y_int32"].replace(".y.int32", ".yfirst.int32")
        y32_bf = gemv_bias_first(w8, x8, b32)
        if yfirst_key in z:
            yfirst_st = z[yfirst_key].astype(np.int64)
            check(yfirst_st.shape == (n,), f"{name}/{gid}: yfirst 形状")
            check(np.array_equal(y32_bf, yfirst_st),
                  f"{name}/{gid}: yfirst.int32(bias_first 规范口径) MISMATCH")
            n_div = int(np.sum(y32_bf != y32))
            if verbose:
                print(f"    yfirst 变体键已验(bias_first;与主键差 {n_div} 通道,§9.1 第 1 条)")
        elif not np.array_equal(y32_bf, y32):
            print(f"  WARN {name}/{gid}: 无 yfirst 变体键且两口径差 "
                  f"{int(np.sum(y32_bf != y32))} 通道(§9.1 第 2 条,须补键)")

        m_re, s_re = recompute_ms(e, z, y32, cache)
        ms_ok = check(np.array_equal(m_re.astype(np.int64), m_st.astype(np.int64)),
                      f"{name}/{gid}: M MISMATCH") and \
            check(np.array_equal(s_re.astype(np.int64), s_st.astype(np.int64)),
                  f"{name}/{gid}: S MISMATCH")

        yq = np.array([requant_one(y, mm, ss) for y, mm, ss in zip(y32, m_st, s_st)], np.int64)
        check(np.array_equal(yq, yq_st), f"{name}/{gid}: y_q8 MISMATCH")

        wl = w8.tolist()
        xl = x8.tolist()
        bl = b32.tolist()
        for ci in {0, n // 3, (2 * n) // 3, n - 1}:
            acc = 0
            row = wl[ci]
            xv = xl
            for kk in range(k):
                acc = sat32(acc + row[kk] * xv[kk])
            acc = sat32(acc + bl[ci])
            if not check(acc == int(y32_st[ci]), f"{name}/{gid} ch{ci}: 纯python y_int32 不一致"):
                break
        if len(FAILS) == n_start_fails:
            n_ok += 1
        if verbose:
            print(f"  {name}/{gid}: N={n} K={k} ms_rule={e['ms_rule']} "
                  f"y32[{int(y32_st[0])}...] {'OK' if np.array_equal(y32, y32_st) else 'FAIL'}")
    return n_ok, len(info["gemvs"])


def structural_checks(manifest, root):
    """§6 正名键 + e2e 链路一致性。"""
    e2e = manifest["cases"].get("e2e_step_T8")
    if not e2e:
        return
    z = np.load(os.path.join(root, e2e["npz"]))
    check(str(z["meta.protocol_version"]) == PROTOCOL_VERSION, "e2e: protocol_version != 1.0")
    check(str(z["meta.case"]) == "e2e_step_T8", "e2e: meta.case 不符")
    for path, n, k in [("blocks.0.Wqkv.weight", 768, 256), ("blocks.0.Wo.weight", 256, 256),
                       ("blocks.0.fc1.weight", 1024, 256), ("blocks.0.fc2.weight", 256, 1024),
                       ("blocks.1.Wqkv.weight", 768, 256), ("blocks.1.Wo.weight", 256, 256),
                       ("blocks.1.fc1.weight", 1024, 256), ("blocks.1.fc2.weight", 256, 1024),
                       ("lm_head.weight", 1024, 256)]:
        check(f"w.{path}.q8" in z and tuple(z[f"w.{path}.q8"].shape) == (n, k),
              f"e2e: 缺 w.{path}.q8 或形状错")
        check(f"rq.{path}.m" in z and f"rq.{path}.s" in z, f"e2e: 缺 rq.{path}.m/s")
    check("logits.0.int32" in z and tuple(z["logits.0.int32"].shape) == (1024,), "e2e: logits.0.int32")
    check("logits.0.q8" in z and tuple(z["logits.0.q8"].shape) == (1024,), "e2e: logits.0.q8")
    for l in range(2):
        for nm in ("k", "v"):
            key = f"kv.0.L{l}.{nm}.q8"
            check(key in z and tuple(z[key].shape) == (4, 128, 64), f"e2e: {key}")
            check(f"kv.0.L{l}.{nm}new.q8" in z, f"e2e: kv.0.L{l}.{nm}new.q8")
    check(np.array_equal(z["gold.0.gemv01.xin.q8"], z["act.0.L0.ln1_out.q8"]),
          "e2e: G01.xin != L0.ln1_out")
    check(np.array_equal(z["gold.0.gemv13.xin.q8"], z["act.0.L1.ln1_out.q8"]),
          "e2e: G13.xin != L1.ln1_out")
    check(np.array_equal(z["gold.0.gemv02.xin.q8"], z["act.0.L0.q.q8"][:64]),
          "e2e: G02.xin != q.q8[0:64]")
    check(np.array_equal(z["gold.0.gemv25.xin.q8"], z["act.0.lnf_out.q8"]),
          "e2e: G25.xin != lnf_out")
    check(np.array_equal(z["logits.0.int32"], z["gold.0.gemv25.y.int32"]),
          "e2e: logits.0.int32 != G25.y.int32")
    for l in range(2):
        check(np.array_equal(z[f"kv.0.L{l}.k.q8"][:, 8, :], z[f"kv.0.L{l}.knew.q8"]),
              f"e2e: L{l} cache row8 != knew")
    mapping = {"blocks.0.Wqkv.weight": "gemv01", "blocks.0.Wo.weight": "gemv10",
               "blocks.0.fc1.weight": "gemv11", "blocks.0.fc2.weight": "gemv12",
               "blocks.1.Wqkv.weight": "gemv13", "blocks.1.Wo.weight": "gemv22",
               "blocks.1.fc1.weight": "gemv23", "blocks.1.fc2.weight": "gemv24",
               "lm_head.weight": "gemv25"}
    for path, g in mapping.items():
        check(np.array_equal(z[f"w.{path}.q8"], z[f"w.{g}.q8"]), f"e2e: w.{path}.q8 != w.{g}.q8")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "models", "golden"))
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args()

    with open(os.path.join(args.root, "manifest.json")) as f:
        manifest = json.load(f)
    check(manifest.get("protocol_version") == PROTOCOL_VERSION, "manifest protocol_version")
    check(manifest.get("quant_source") in ("numpy", "tpumlir"), "manifest quant_source 非法")

    total_ok = total = 0
    for name, info in manifest["cases"].items():
        n_ok, n = verify_case(name, info, args.root, args.verbose)
        total_ok += n_ok
        total += n
        print(f"[{name}] gemv={n} y32复算一致={n_ok}/{n}")
    structural_checks(manifest, args.root)

    n_fails = len(FAILS)
    for msg in FAILS[:20]:
        print("  FAIL:", msg)
    if n_fails:
        print(f"共 {n_fails} 项失败（显示前 20）")
        print("VERIFY RESULT: FAIL")
        return 1
    print(f"结构检查 + 链路一致性: OK；M/S 复算: OK；y_q requant 复算: OK；纯 python 抽检: OK")
    print(f"VERIFY RESULT: ALL GREEN ({total_ok}/{total} gemv 逐位一致)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
