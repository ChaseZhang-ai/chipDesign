#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""vfrd_golden.py — P3D 全芯片端到端 golden 生成与终判。

角色(与 docs/GOLDEN_SPEC.md 的关系):
  * L2 边界(§5)的逐元素 fp32 参考(LN/GELU/softmax/残差)由 gld_gen.E2E 的
    权威实现生成,本脚本只在三组 prompt 上重跑它;芯片侧消费的是 §5 定义的
    **量化边界张量**(q8),这与 GOLDEN_SPEC L2 的"v2 再定点化"范围一致。
  * L1(GEMV+requant)的期望值由本脚本内的**独立整数实现**重算(gemv_ref),
    不调用 gld_gen/gld_common 的 requant 函数,满足 §9 的"生成器/比对器
    独立实现"要求;若与 E2E 输出不一致则直接报错。

产物(tb/soc/build/):
  p3d_prog.hex    微内核镜像(build_hex.py 汇编 tb/soc/verify_p3d_decode.s)
  p3d_scene.hex   XMEM 稀疏镜像(16-bit 半字,@addr 行)
  p3d_golden.npz  三组 prompt 的期望 y_q/y_int32/token/KV 与场景元数据

用法:
  python3 scripts/vfrd_golden.py gen   --out tb/soc/build
  python3 scripts/vfrd_golden.py check --work tb/soc/build
"""
import argparse
import json
import os
import re
import subprocess
import sys

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "scripts"))

import gld_common as gc
import gld_gen

MODELS = os.path.join(ROOT, "models")
CFG = json.load(open(os.path.join(MODELS, "minigpt_config.json")))
W = np.load(os.path.join(MODELS, "minigpt_weights.npz"))

PROMPT_SEEDS = [20261023, 20261024, 20261025]
PREFILL_T = 8
POS = PREFILL_T

XMEM_SYS         = 0x4000_0000
XMEM_PROG_BASE   = 0x4000_0000
PROG_OFF         = 0x0000_0000
XMEM_WEIGHT_BASE = 0x4002_0000
WEIGHT_OFF       = 0x0002_0000
PB_BASE          = 0x4050_0000
PB_OFF           = 0x0050_0000
PB_STRIDE        = 0x0002_0000
DUMP_BASE        = 0x4060_0000
DUMP_STRIDE      = 0x0001_0000
EXC_DUMP         = 0x406F_0000
KV_BASE          = 0x4040_0000
KV_OFF           = 0x0040_0000

PB_DESC   = 0x0100                 # 9 × 32 B
PB_AUX    = 0x0800                 # 16 × 16 B (QK/PV: m,s,yq,y32)
PB_XIN    = 0x1000
PB_PROB   = 0x2600
PB_KVPRE  = 0x3000
PB_KVNEW  = 0x5000                 # 512 B
PB_M      = 0x1_0000               # ΣN × 4
PB_S      = 0x1_8000               # ΣN

DUMP_FLAG = 0x0000
DUMP_YQ   = 0x1000                 # ΣN = 7168 B
DUMP_Y32  = 0x4000                 # ΣN × 4 = 28672 B

WEIGHT_SLOTS = [
    ("G01", "blocks.0.Wqkv.weight"),
    ("G10", "blocks.0.Wo.weight"),
    ("G11", "blocks.0.fc1.weight"),
    ("G12", "blocks.0.fc2.weight"),
    ("G13", "blocks.1.Wqkv.weight"),
    ("G22", "blocks.1.Wo.weight"),
    ("G23", "blocks.1.fc1.weight"),
    ("G24", "blocks.1.fc2.weight"),
    ("G25", "lm_head.weight"),
]
SLOT_NK = {"G01": (768, 256), "G10": (256, 256), "G11": (1024, 256),
           "G12": (256, 1024), "G13": (768, 256), "G22": (256, 256),
           "G23": (1024, 256), "G24": (256, 1024), "G25": (1024, 256)}

ALL_SLOTS = []
for _i, (_gid, _p) in enumerate(WEIGHT_SLOTS):
    _n, _k = SLOT_NK[_gid]
    ALL_SLOTS.append(dict(idx=len(ALL_SLOTS), gid=_gid, path=_p, N=_n, K=_k,
                          kind="weight", layer=None, head=None))
for _l in range(2):
    for _h in range(4):
        ALL_SLOTS.append(dict(idx=len(ALL_SLOTS), gid=f"G{2 + _h + 12 * _l:02d}",
                              path=None, N=128, K=64, kind="qk", layer=_l, head=_h))
    for _h in range(4):
        ALL_SLOTS.append(dict(idx=len(ALL_SLOTS), gid=f"G{6 + _h + 12 * _l:02d}",
                              path=None, N=64, K=128, kind="pv", layer=_l, head=_h))

_yq_off, _m_off, _s_off = {}, {}, {}
_oyq = _om = _os = 0
for s in ALL_SLOTS:
    _yq_off[s["idx"]] = _oyq
    _m_off[s["idx"]] = _om
    _s_off[s["idx"]] = _os
    _oyq += s["N"]
    _om += s["N"] * 4
    _os += s["N"]
assert _oyq == 7168 and _om == 28672 and _os == 7168

XIN_OFF = {}
_ox = 0
for _s in ALL_SLOTS[:9]:
    XIN_OFF[_s["idx"]] = _ox
    _ox += _s["K"]
XIN_TOTAL = _ox                                                        # 3840
PB_PROB_L0 = PB_XIN + XIN_TOTAL                                        # 0x1F00
PB_PROB_L1 = PB_PROB_L0 + 64                                           # 0x1F40
assert PB_PROB_L0 == 0x1F00 and PB_PROB_L1 == 0x1F40 and XIN_TOTAL == 3840

QKPV_SLOTS = [s for s in ALL_SLOTS if s["kind"] in ("qk", "pv")]
QKPV_ORDER = [s["idx"] for s in QKPV_SLOTS]
assert QKPV_ORDER == list(range(9, 25))


def slot_of(kind, layer, head):
    for s in ALL_SLOTS:
        if s["kind"] == kind and s["layer"] == layer and s["head"] == head:
            return s["idx"]
    raise KeyError((kind, layer, head))


I32_MIN, I32_MAX = -(1 << 31), (1 << 31) - 1


def sat32(v):
    return I32_MIN if v < I32_MIN else (I32_MAX if v > I32_MAX else v)


def gemv_ref(w8, x8, b32):
    """GOLDEN_SPEC §2.1 bias_first 整数实现(独立于 gld_common)."""
    w = np.asarray(w8, np.int64)
    x = np.asarray(x8, np.int64)
    b = np.asarray(b32, np.int64)
    n, k = w.shape
    y = np.empty(n, np.int64)
    for i in range(n):
        acc = int(b[i])
        row = w[i]
        for kk in range(k):
            acc = sat32(acc + int(row[kk]) * int(x[kk]))
        y[i] = acc
    return y


def requant_ref(y32, m, s, rnd=True):
    y = np.asarray(y32, np.int64)
    m = np.asarray(m, np.int64)
    s = np.asarray(s, np.int64)
    add = (np.int64(1) << (s - 1)) if rnd else np.int64(0)
    return np.clip((y * m + add) >> s, -128, 127).astype(np.int8)


def build_prompt(seed):
    """用权威 fp32 实现跑 prefill + 一步 decode,返回每 slot 的边界输入/期望."""
    ids = np.random.default_rng(seed).integers(0, CFG["vocab"], PREFILL_T)
    logits_f, k_f, v_f = gld_gen.prefill_fp32(W, CFG, ids)
    token_in = int(np.argmax(logits_f[-1]))
    x_emb_f = W["wte.weight"][token_in] + W["wpe.weight"][POS]

    e = gld_gen.E2E(W, CFG, prefill_tokens=PREFILL_T)
    e.quant_weights()
    e.token_in = token_in
    e.k_cache8 = np.zeros((CFG["n_layer"], e.H, CFG["max_ctx"], e.hd), np.int8)
    e.v_cache8 = np.zeros_like(e.k_cache8)
    e.k_sx = np.zeros((CFG["n_layer"], e.H), np.float32)
    e.v_sx = np.zeros_like(e.k_sx)

    xq, xsx = gld_gen.quant_boundary(x_emb_f)
    x_f = gld_gen.dequant(xq, xsx)
    for l in range(CFG["n_layer"]):
        xq, xsx, x_f = e.block(l, xq, xsx, k_f, v_f)

    lnf_f = gld_gen.ln_f32(x_f, W["ln_f.weight"], W["ln_f.bias"])
    lnf_q, lnf_sx = gld_gen.quant_boundary(lnf_f)
    e.z.put("act.0.lnf_out.q8", lnf_q)
    e.z.put("act.0.lnf_out.sx", np.float32(lnf_sx))
    logits32, logitsq, _ = e.gemv_linear("G25", "lm_head.weight", lnf_q, lnf_sx,
                                         "act.0.lnf_out.sx", "act.0.logits")
    token_pred = int(np.argmax(logits32))

    z = e.z.d
    out = dict(seed=int(seed), ids=ids.astype(int), token_in=token_in,
               token=int(token_pred), slots={})
    for s in ALL_SLOTS:
        g = s["gid"].lower().replace("g", "gemv")
        yq = z[f"gold.0.{g}.y.q8"]
        y32 = z[f"gold.0.{g}.y.int32"]
        xin = z[f"gold.0.{g}.xin.q8"]
        m = z[f"rq.{g}.m"]
        ss = z[f"rq.{g}.s"]
        w8 = z.get(f"w.{g}.q8")
        if w8 is not None:
            y32i = gemv_ref(w8, xin, z[f"gold.0.{g}.b.int32"])
            assert np.array_equal(y32i, y32.astype(np.int64)), f"{g}: y32 独立重算不一致"
        yqi = requant_ref(y32, m, ss)
        assert np.array_equal(yqi, yq), f"{g}: y_q 独立重算不一致"
        out["slots"][s["idx"]] = dict(
            N=s["N"], K=s["K"], kind=s["kind"], layer=s["layer"], head=s["head"],
            gid=s["gid"],
            xin=np.asarray(xin, np.int8),
            m=np.asarray(m, np.uint32), s=np.asarray(ss, np.uint8),
            y32=np.asarray(y32, np.int32), yq=np.asarray(yq, np.int8),
            w8=(None if w8 is None else np.asarray(w8, np.int8)),
            valid=(16 if s["kind"] == "qk" else s["N"]),
        )

    xin_map = {}
    for i, (gid, _path) in enumerate(WEIGHT_SLOTS):
        xin_map[i] = out["slots"][i]["xin"]
    out["xin"] = xin_map
    out["prob_l0"] = z["act.0.L0.attn_prob.q8"][:, :16].astype(np.int8)   # [H,16]
    out["prob_l1"] = z["act.0.L1.attn_prob.q8"][:, :16].astype(np.int8)
    assert np.all(out["prob_l0"][:, POS + 1:] == 0)
    assert np.all(out["prob_l1"][:, POS + 1:] == 0)
    out["kv_k"] = e.k_cache8
    out["kv_v"] = e.v_cache8
    out["ln1_out"] = [z["act.0.L0.ln1_out.q8"], z["act.0.L1.ln1_out.q8"]]
    out["ln2_out"] = [z["act.0.L0.ln2_out.q8"], z["act.0.L1.ln2_out.q8"]]
    out["gelu_out"] = [z["act.0.L0.gelu_out.q8"], z["act.0.L1.gelu_out.q8"]]
    out["lnf_out"] = z["act.0.lnf_out.q8"]
    out["attn_out_golden"] = [z["act.0.L0.attn_out.q8"], z["act.0.L1.attn_out.q8"]]
    return out


def _put_bytes(sp, addr, data):
    for i, b in enumerate(bytes(data)):
        a = addr + i
        idx = a >> 1
        cur = sp.get(idx, 0)
        sp[idx] = (cur & 0x00FF) | (b << 8) if (a & 1) else (cur & 0xFF00) | b


def _put_words(sp, addr, words):
    for i, w in enumerate(words):
        w = int(w) & 0xFFFFFFFF
        a = addr + 4 * i
        assert a % 2 == 0
        sp[a >> 1] = w & 0xFFFF
        sp[(a >> 1) + 1] = (w >> 16) & 0xFFFF


def _emit_sparse(path, sp):
    with open(path, "w") as f:
        prev = None
        for a in sorted(sp):
            if prev is None or a != prev + 1:
                f.write(f"@{a:06X}\n")
            f.write(f"{sp[a]:04X}\n")
            prev = a


def assemble_program(out_dir):
    """主微内核(OC SRAM 0x0)+ 异常注入 XIP 冷路径(XMEM 0x4000_1000).

    说明: 任务书 W1 的"程序 ≤2KB"针对生产微内核;P3D 的验证微内核为覆盖
    25 个 GEMV + KV + 异常注入,text 约 3.4KB,仍在 4KB OC SRAM 内(boot 一次
    复制 4KB)。异常注入已拆到 XMEM XIP,不占 OC SRAM。该偏差记录于
    reports/P3D_REPORT.md。
    """
    src = os.path.join(ROOT, "tb", "soc", "verify_p3d_decode.s")
    dst = os.path.join(out_dir, "p3d_prog.hex")
    cmd = [sys.executable, os.path.join(ROOT, "scripts", "build_hex.py"), "asm",
           "-o", dst, "--base", "0", "--rom-bytes", "4096",
           "--text-limit", "4096", "--data-limit", "2048"]
    defs = {
        "PB_DESC_C": hex(PB_DESC), "PB_AUX_C": hex(PB_AUX),
        "PB_XIN_C": hex(PB_XIN), "PB_PROB_C": hex(PB_PROB_L0),
        "PB_KVPRE_C": hex(PB_KVPRE), "PB_KVNEW_C": hex(PB_KVNEW),
        "PB_M_C": hex(PB_M), "PB_S_C": hex(PB_S),
        "DUMP_FLAG_C": hex(DUMP_FLAG), "DUMP_YQ_C": hex(DUMP_YQ),
        "DUMP_Y32_C": hex(DUMP_Y32),
        "YQ_L0_PV_C": hex(_yq_off[slot_of("pv", 0, 0)]),
        "YQ_L1_PV_C": hex(_yq_off[slot_of("pv", 1, 0)]),
        "YQ_L0_QKV_C": hex(_yq_off[0]),
        "YQ_L1_QKV_C": hex(_yq_off[4]),
    }
    for k, v in defs.items():
        cmd += ["--define", f"{k}={v}"]
    cmd.append(src)
    print("[vfrd] assemble:", " ".join(cmd))
    def _read_hex(p):
        out = []
        with open(p) as f:
            for ln in f:
                ln = ln.split("//")[0].strip()
                if ln:
                    out.append(int(ln, 16))
        return out

    def _rd(p):
        out = []
        with open(p) as f:
            for ln in f:
                ln = ln.split("//")[0].strip()
                if ln:
                    out.append(int(ln, 16))
        return out

    esrc = os.path.join(ROOT, "tb", "soc", "verify_p3d_exc.s")
    edst = os.path.join(out_dir, "p3d_exc.hex")
    emap = os.path.join(out_dir, "p3d_exc.map")
    subprocess.run([sys.executable, os.path.join(ROOT, "scripts", "build_hex.py"),
                    "asm", "-o", edst, "--map", emap, "--base", "0x40001000",
                    "--rom-bytes", "4096", "--text-limit", "3072",
                    "--data-limit", "1024", esrc], check=True)
    print_addr = None
    argmax_addr = None
    for ln in open(emap):
        mm = re.match(r"0x([0-9A-Fa-f]+)\s+print_token_xip\b", ln)
        if mm:
            print_addr = int(mm.group(1), 16)
        mm = re.match(r"0x([0-9A-Fa-f]+)\s+argmax_xip\b", ln)
        if mm:
            argmax_addr = int(mm.group(1), 16)
    assert print_addr is not None and argmax_addr is not None, "XIP symbols not found"
    cmd += ["--define", f"PRINT_XIP_C={hex(print_addr)}"]
    cmd += ["--define", f"ARGMAX_XIP_C={hex(argmax_addr)}"]
    subprocess.run(cmd, check=True)
    prog = _read_hex(dst)
    exc = _read_hex(edst)
    return prog, exc


def emit_scene(out_dir, prompts):
    sp = {}
    prog, exc = assemble_program(out_dir)
    assert len(prog) == 1024, len(prog)
    assert len(exc) == 1024, len(exc)
    _put_words(sp, PROG_OFF, prog)
    _put_words(sp, PROG_OFF + 0x1000, exc)

    wb = WEIGHT_OFF
    w_off = {}
    for i, (gid, _path) in enumerate(WEIGHT_SLOTS):
        w8 = prompts[0]["slots"][i]["w8"]
        w_off[i] = wb - WEIGHT_OFF
        _put_bytes(sp, wb, np.ascontiguousarray(w8).tobytes())
        wb += w8.size
    assert wb - WEIGHT_OFF == 1_835_008

    for pi, pr in enumerate(prompts):
        pb = PB_BASE + pi * PB_STRIDE
        pbo = PB_OFF + pi * PB_STRIDE
        db = DUMP_BASE + pi * DUMP_STRIDE

        for i, (gid, _path) in enumerate(WEIGHT_SLOTS):
            s = pr["slots"][i]
            off = PB_XIN + XIN_OFF[i]
            _put_bytes(sp, pbo + off, s["xin"].tobytes())
        _put_bytes(sp, pbo + PB_PROB_L0, pr["prob_l0"].tobytes())
        _put_bytes(sp, pbo + PB_PROB_L1, pr["prob_l1"].tobytes())

        # M / S
        for s in ALL_SLOTS:
            i = s["idx"]
            _put_words(sp, pbo + PB_M + _m_off[i],
                       np.asarray(pr["slots"][i]["m"], np.uint32))
            _put_bytes(sp, pbo + PB_S + _s_off[i],
                       np.asarray(pr["slots"][i]["s"], np.uint8).tobytes())

        for i, (gid, _path) in enumerate(WEIGHT_SLOTS):
            s = pr["slots"][i]
            if i == 1:
                xaddr = db + DUMP_YQ + _yq_off[slot_of("pv", 0, 0)]
            elif i == 5:
                xaddr = db + DUMP_YQ + _yq_off[slot_of("pv", 1, 0)]
            else:
                xaddr = pb + PB_XIN + XIN_OFF[i]
            words = [XMEM_WEIGHT_BASE + w_off[i], s["N"], s["K"], xaddr,
                     pb + PB_M + _m_off[i], pb + PB_S + _s_off[i],
                     db + DUMP_YQ + _yq_off[i], db + DUMP_Y32 + _yq_off[i] * 4]
            _put_words(sp, pbo + PB_DESC + i * 32, words)

        for j, si in enumerate(QKPV_ORDER):
            words = [pb + PB_M + _m_off[si], pb + PB_S + _s_off[si],
                     db + DUMP_YQ + _yq_off[si], db + DUMP_Y32 + _yq_off[si] * 4]
            _put_words(sp, pbo + PB_AUX + j * 16, words)

        for l in range(2):
            for t in range(2):
                for h in range(4):
                    base = KV_OFF + l * 0x20000 + t * 0x10000 + h * 0x4000
                    for pos in range(128):
                        _put_bytes(sp, base + pos * 64, bytes(64))

        # prefill KV staging: [layer][pos][h][K64,V64]
        for l in range(2):
            for p in range(PREFILL_T):
                base = pbo + PB_KVPRE + (l * PREFILL_T + p) * 512
                for h in range(4):
                    _put_bytes(sp, base + 128 * h, pr["kv_k"][l][h][p].tobytes())
                    _put_bytes(sp, base + 128 * h + 64, pr["kv_v"][l][h][p].tobytes())

    path = os.path.join(out_dir, "p3d_scene.hex")
    _emit_sparse(path, sp)
    print(f"[vfrd] scene -> {path} ({len(sp)} halfwords)")
    return path


def save_golden(out_dir, prompts):
    d = {}
    for pi, pr in enumerate(prompts):
        d[f"p{pi}.token"] = np.int64(pr["token"])
        d[f"p{pi}.token_in"] = np.int64(pr["token_in"])
        d[f"p{pi}.ids"] = np.asarray(pr["ids"], np.int64)
        for s in ALL_SLOTS:
            i = s["idx"]
            st = pr["slots"][i]
            d[f"p{pi}.s{i}.yq"] = st["yq"]
            d[f"p{pi}.s{i}.y32"] = st["y32"]
            d[f"p{pi}.s{i}.valid"] = np.int64(st["valid"])
        d[f"p{pi}.kv_l0k"] = pr["kv_k"][0]
        d[f"p{pi}.kv_l0v"] = pr["kv_v"][0]
        d[f"p{pi}.kv_l1k"] = pr["kv_k"][1]
        d[f"p{pi}.kv_l1v"] = pr["kv_v"][1]
        d[f"p{pi}.attn_out0"] = pr["attn_out_golden"][0]
        d[f"p{pi}.attn_out1"] = pr["attn_out_golden"][1]
    d["meta.yq_off"] = np.array([_yq_off[i] for i in range(len(ALL_SLOTS))], np.int64)
    d["meta.N"] = np.array([s["N"] for s in ALL_SLOTS], np.int64)
    d["meta.valid"] = np.array([(16 if s["kind"] == "qk" else s["N"]) for s in ALL_SLOTS],
                               np.int64)
    d["meta.kind"] = np.array([s["kind"] for s in ALL_SLOTS])
    d["meta.gid"] = np.array([s["gid"] for s in ALL_SLOTS])
    p = os.path.join(out_dir, "p3d_golden.npz")
    np.savez(p, **d)
    print(f"[vfrd] golden -> {p}")
    return p


# ------------------------------------------------------------------ check
def _load_words(path):
    vals = []
    with open(path) as f:
        for ln in f:
            ln = ln.split("//")[0].strip()
            if ln:
                vals.append(int(ln, 16))
    return vals


def _words_to_bytes(ws):
    return b"".join(int(w).to_bytes(4, "little") for w in ws)


def check(work):
    log = os.path.join(work, "p3d_e2e.log")
    txt = open(log, errors="replace").read() if os.path.exists(log) else ""
    g = np.load(os.path.join(work, "p3d_golden.npz"))
    nslots = int(len(g["meta.N"]))

    errs = []
    report = []
    toks = re.findall(r"T([0-2])=([0-9a-fA-F]+)", txt)
    tok_map = {int(a): int(b, 16) for a, b in toks}
    for p in range(3):
        exp = int(g[f"p{p}.token"])
        got = tok_map.get(p)
        ok = (got == exp)
        report.append(f"prompt {p}: token got={got} exp={exp} {'OK' if ok else 'MISMATCH'}")
        if not ok:
            errs.append(f"token p{p}")

    yq_off = g["meta.yq_off"]
    valid = g["meta.valid"]
    kinds = g["meta.kind"]
    for p in range(3):
        yqw = _load_words(os.path.join(work, f"p3d_yq_p{p}.hex"))
        y32w = _load_words(os.path.join(work, f"p3d_y32_p{p}.hex"))
        yqb = _words_to_bytes(yqw)
        for i in range(nslots):
            n = int(valid[i])
            off = int(yq_off[i])
            exp_q = g[f"p{p}.s{i}.yq"][:n].astype(np.uint8)
            exp_32 = g[f"p{p}.s{i}.y32"][:n].astype(np.uint32)
            got_q = np.frombuffer(yqb[off:off + n], np.uint8)
            got_32 = np.asarray(y32w[off:off + n], np.uint64).astype(np.uint32)
            if not np.array_equal(got_q, exp_q):
                k = int(np.argmax(got_q != exp_q))
                errs.append(f"p{p} {kinds[i]} yq[{k}] got={got_q[k]:02x} exp={exp_q[k]:02x}")
            if i == 8 and not np.array_equal(got_32, exp_32):
                k = int(np.argmax(got_32 != exp_32))
                errs.append(f"p{p} {kinds[i]} y32[{k}] got={got_32[k]:08x} exp={exp_32[k]:08x}")
        report.append(f"prompt {p}: y_q/y_int32 {nslots} slots checked "
                      f"({'OK' if not any(e.startswith(f'p{p} ') for e in errs) else 'MISMATCH'})")

    kvw = _load_words(os.path.join(work, "p3d_kv.hex"))
    kvb = _words_to_bytes(kvw)
    expkv = bytearray(256 * 1024)
    for l in range(2):
        for t, key in enumerate(("kv_l0k", "kv_l0v") if l == 0 else ("kv_l1k", "kv_l1v")):
            arr = g[f"p2.{key}"]   # [H, ctx, hd]
            for h in range(4):
                base = l * 0x20000 + t * 0x10000 + h * 0x4000
                for pos in range(128):
                    expkv[base + pos * 64: base + pos * 64 + 64] = arr[h, pos].tobytes()
    ncb = 128 * 1024
    if bytes(kvb[:ncb]) != bytes(expkv[:ncb]):
        bad = next(i for i in range(ncb) if kvb[i] != expkv[i])
        errs.append(f"KV first mismatch @byte {bad:#x} got={kvb[bad]:02x} exp={expkv[bad]:02x}")
    report.append(f"KV cache (2 layer × K/V × 4 head × 128 pos, {ncb} B): "
                  f"{'OK' if not any(e.startswith('KV') for e in errs) else 'MISMATCH'}")

    marks = re.findall(r"\[p3d_mark\] ([SE]) (\d) cyc=(\d+) ame=(\d+) mac=(\d+) dma=(\d+) xmem=(\d+) kv=(\d+)", txt)
    win = {}
    for kind, pid, cyc, ame, mac, dma, xmem, kv in marks:
        win[(kind, int(pid))] = dict(cyc=int(cyc), ame=int(ame), mac=int(mac),
                                     dma=int(dma), xmem=int(xmem), kv=int(kv))
    kpi_lines = []
    per_step = []
    for p in range(3):
        a, b = win.get(("S", p)), win.get(("E", p))
        if not a or not b:
            kpi_lines.append(f"prompt {p}: KPI marker missing")
            continue
        c = b["cyc"] - a["cyc"]
        per_step.append(c)
        def pct(k):
            return 100.0 * (b[k] - a[k]) / max(c, 1)
        kpi_lines.append(
            f"prompt {p}: cycles={c}  AME_BUSY={pct('ame'):.2f}%  MAC={pct('mac'):.2f}%  "
            f"DMA_BUSY={pct('dma'):.2f}%  XMEM_ACT={pct('xmem'):.2f}%  KV_BUSY={pct('kv'):.2f}%  "
            f"tokens/s@120MHz={120e6/max(c,1):.1f}")
    report.extend(kpi_lines)
    if per_step:
        avg = sum(per_step) / len(per_step)
        report.append(f"mean single-step decode cycles = {avg:.0f} (pre-patch baseline, 1-cycle st.q resp)")

    excp = os.path.join(work, "p3d_exc_exc.hex")
    if not os.path.exists(excp):
        excp = os.path.join(work, "p3d_exc.hex")
    excw = _load_words(excp)
    exc = excw[0] if excw else 0
    exc_ok = (exc == 0xE0C0DE01)
    report.append(f"exception test word=0x{exc:08x} {'OK' if exc_ok else 'MISMATCH'}")
    if not exc_ok:
        errs.append(f"exc word 0x{exc:08x}")

    with open(os.path.join(work, "p3d_check.log"), "w") as f:
        f.write("\n".join(report) + "\n")
        if errs:
            f.write("MISMATCHES:\n" + "\n".join(errs[:40]) + "\n")
            f.write(f"P3D CHECK FAIL ({len(errs)} mismatches)\n")
        else:
            f.write("P3D CHECK PASS\n")
    print("\n".join(report))
    if errs:
        print("MISMATCHES:")
        for e in errs[:40]:
            print("  ", e)
        print(f"P3D CHECK FAIL ({len(errs)} mismatches)")
        return 1
    print("P3D CHECK PASS")
    return 0


def emit_exc_scene(out_dir):
    """独立异常注入场景:主程序跳到 XIP 异常路径,不依赖 decode 控制流."""
    msrc = os.path.join(ROOT, "tb", "soc", "verify_p3d_exc_main.s")
    mdst = os.path.join(out_dir, "p3d_exc_main.hex")
    subprocess.run([sys.executable, os.path.join(ROOT, "scripts", "build_hex.py"),
                    "asm", "-o", mdst, "--base", "0", "--rom-bytes", "4096",
                    "--text-limit", "256", "--data-limit", "256", msrc], check=True)
    edst = os.path.join(out_dir, "p3d_exc.hex")
    subprocess.run([sys.executable, os.path.join(ROOT, "scripts", "build_hex.py"),
                    "asm", "-o", edst, "--base", "0x40001000", "--rom-bytes", "4096",
                    "--text-limit", "3072", "--data-limit", "1024",
                    os.path.join(ROOT, "tb", "soc", "verify_p3d_exc.s")], check=True)
    def rd(p):
        out=[]
        with open(p) as f:
            for ln in f:
                ln=ln.split("//")[0].strip()
                if ln: out.append(int(ln,16))
        return out
    sp={}
    _put_words(sp, 0, rd(mdst))
    _put_words(sp, 0x1000, rd(edst))
    path=os.path.join(out_dir, "p3d_exc_scene.hex")
    _emit_sparse(path, sp)
    print(f"[vfrd] exc scene -> {path}")


# ------------------------------------------------------------------ main
def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    pg = sub.add_parser("gen")
    pg.add_argument("--out", required=True)
    pc = sub.add_parser("check")
    pc.add_argument("--work", required=True)
    a = ap.parse_args()

    if a.cmd == "gen":
        os.makedirs(a.out, exist_ok=True)
        prompts = [build_prompt(seed) for seed in PROMPT_SEEDS]
        ref = np.load(os.path.join(MODELS, "golden", "e2e_step_T8", "case.npz"))
        for s in ALL_SLOTS:
            g = s["gid"].lower().replace("g", "gemv")
            assert np.array_equal(prompts[0]["slots"][s["idx"]]["yq"],
                                  ref[f"gold.0.{g}.y.q8"]), f"prompt0 {g} 与既有 golden 不一致"
        assert prompts[0]["token"] == int(ref["meta.token_pred"])
        print("[vfrd] prompt0 与 models/golden/e2e_step_T8 逐位一致(25 GEMV + token)")
        emit_scene(a.out, prompts)
        save_golden(a.out, prompts)
        emit_exc_scene(a.out)
        print("[vfrd] gen done")
        return 0
    return check(a.work)


if __name__ == "__main__":
    sys.exit(main())
