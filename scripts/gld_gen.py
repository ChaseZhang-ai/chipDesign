#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""gld_gen.py — AME 全量位精确 golden 生成器（W2E，严格按 docs/GOLDEN_SPEC.md v1.0）。

生成 4 个 case 到 models/golden/<case>/case.npz + 全局 manifest.json：

  unit_gemv    G1..G25（WORKLOAD §5 全部 decode GEMV 实例）各 1 组随机 int8 x/W
               + 真实量化 scale → §2.3 M/S（§8 用例 1）
  e2e_step_T8  prefill 8 token（fp32 参考，逐位置与 minigpt_decode.onnx 交叉验证）
               + 1 步 decode 全 INT8 链（§5 全部量化点、KV 写回、logits argmax）
  corner       §8 用例 3：①K=1024 最长累加 ②极端 W/x+bias 触发 SAT32（bias_last 口径，
               另存 bias_first 变体键 gold.0.gemv02.yfirst.int32）③M=1,S=1 强制直通
               ④全零输入
  rand20       20 组随机 (N,K)：16 整除 / 非整除余数 / 极值权重 -128/+127 集中（任务书
               追加覆盖；GOLDEN_SPEC §2 只定义 GEMV，故全部 M=1）

用法：
  source ~/venvs/tpu-mlir/bin/activate && python scripts/gld_gen.py \
      [--root models/golden] [--seed 20261023] [--prefill-tokens 8] [--skip-onnx-check]

量化权威性（任务书第 2 条）：quant_source=numpy —— GOLDEN_SPEC §1/§2.3 本身就是规范级
量化定义（对称、zp=0、banker's rounding、absmax scale、M/S 浮点公式），逐位可复现；
tpu-mlir 校准/量化工具链的 scale 选择（如百分比截位）与该协议不一致，且芯片运行期只
消费本 golden 定义的字节流，故以 numpy 规范实现为唯一权威，manifest.quant_source 如实
标注（详见 reports/issues/P2E.md）。

关键口径（与 manifest.protocol_notes 同文）：
  * y_q 是 requant 单元输出：按 §2.3，M/2^S ≈ scale_out = s_x×s_w[n]，故 y_q ≈ y_f
    （浮点单位、幅度 O(1)，e2e 中多为小整数；unit_gemv 随机 int8 下 scale_out≈1 而
    饱和到 ±127）。这是规范公式的直接结果，RTL 比对主目标 y_q/y_int32 均逐位有效。
    层间数据链走 §5 边界张量（per-tensor absmax/127 重量化，幅度满 ±127）。
  * Wqkv 权重按 9 组量化（q / k×4头 / v×4头，组内共享 scale）——使 k/v 行 requant 的
    scale_out 组内一致，KV cache 得以满足 §5 的 per-(层,头) 16 组 scale；其余 Linear
    按 §1 标准 per-channel。
  * e2e 链上 dequant 一律 y_q×scale_out（芯片视角：向量单元只见 requant 输出）；
    每个 GEMV 的输入都是 §5 边界 q8（幅度满 ±127，测试数据丰富）。
  * prefill 为 fp32 参考（与 wl_minigpt 同构、onnxruntime 逐步交叉验证），其 k/v 行按
    decode 步的 s_kv[l][h] = s_x0×s_w_group 量化入 cache，与 decode 写回行共用同一
    per-(层,头) scale。
"""
import argparse
import datetime
import json
import math
import os
import subprocess
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gld_common as gc  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODELS = os.path.join(ROOT, "models")

LN_EPS = 1e-5
MASK_NEG = -1e9
ATTN_SCALE_SHIFT = 3


# (gid, weight_path, N, K, kind, stage) —— G01..G25 = WORKLOAD.md §5 G1..G25
def gemv_defs():
    d = [("G01", "blocks.0.Wqkv.weight", 768, 256, "weight", "L0.wqkv")]
    d += [(f"G{2 + h:02d}", None, 128, 64, "cache_qk", f"L0.qk.h{h}") for h in range(4)]
    d += [(f"G{6 + h:02d}", None, 64, 128, "cache_pv", f"L0.pv.h{h}") for h in range(4)]
    d += [("G10", "blocks.0.Wo.weight", 256, 256, "weight", "L0.wo"),
          ("G11", "blocks.0.fc1.weight", 1024, 256, "weight", "L0.fc1"),
          ("G12", "blocks.0.fc2.weight", 256, 1024, "weight", "L0.fc2"),
          ("G13", "blocks.1.Wqkv.weight", 768, 256, "weight", "L1.wqkv")]
    d += [(f"G{14 + h:02d}", None, 128, 64, "cache_qk", f"L1.qk.h{h}") for h in range(4)]
    d += [(f"G{18 + h:02d}", None, 64, 128, "cache_pv", f"L1.pv.h{h}") for h in range(4)]
    d += [("G22", "blocks.1.Wo.weight", 256, 256, "weight", "L1.wo"),
          ("G23", "blocks.1.fc1.weight", 1024, 256, "weight", "L1.fc1"),
          ("G24", "blocks.1.fc2.weight", 256, 1024, "weight", "L1.fc2"),
          ("G25", "lm_head.weight", 1024, 256, "weight", "lm_head")]
    return d


GEMV_DEFS = gemv_defs()



def ln_f32(x, gamma, beta, eps=LN_EPS):
    mu = x.mean(axis=-1, keepdims=True)
    var = ((x - mu) ** 2).mean(axis=-1, keepdims=True)
    return (x - mu) / np.sqrt(var + eps) * gamma + beta


def gelu_f32(x):
    from scipy.special import erf
    return 0.5 * x * (1.0 + erf(x / math.sqrt(2.0)))


def softmax_f32(x, axis=-1):
    m = x.max(axis=axis, keepdims=True)
    e = np.exp(x - m)
    return e / e.sum(axis=axis, keepdims=True)


def dequant(q8, scale):
    return np.asarray(q8, dtype=np.float64) * np.float64(scale)


def quant_boundary(x_f):
    """§5 边界张量：per-tensor absmax/127 量化。→(q8, sx_f32)"""
    return gc.q_per_tensor(np.asarray(x_f, dtype=np.float32))



def prefill_fp32(w, cfg, ids):
    """与 wl_minigpt.MiniGPT.forward_prefill 同构的 fp64 前向。"""
    H = cfg["n_head"]
    hd = cfg["d_model"] // H
    T = len(ids)
    x = w["wte.weight"][ids].astype(np.float64) + w["wpe.weight"][:T]
    k_cache = np.zeros((cfg["n_layer"], H, T, hd))
    v_cache = np.zeros_like(k_cache)
    for l in range(cfg["n_layer"]):
        p = f"blocks.{l}."
        h1 = ln_f32(x, w[p + "ln1.weight"], w[p + "ln1.bias"])
        qkv = h1 @ w[p + "Wqkv.weight"].T.astype(np.float64) + w[p + "Wqkv.bias"]
        q, k, v = (t.reshape(T, H, hd).transpose(1, 0, 2)
                   for t in (qkv[:, :256], qkv[:, 256:512], qkv[:, 512:]))
        k_cache[l], v_cache[l] = k, v
        att = q @ k.transpose(0, 2, 1) * (1.0 / math.sqrt(hd))
        att += np.triu(np.full((T, T), MASK_NEG), 1)
        prob = softmax_f32(att, axis=-1)
        y = (prob @ v).transpose(1, 0, 2).reshape(T, 256)
        x = x + y @ w[p + "Wo.weight"].T.astype(np.float64) + w[p + "Wo.bias"]
        h2 = ln_f32(x, w[p + "ln2.weight"], w[p + "ln2.bias"])
        x = x + gelu_f32(h2 @ w[p + "fc1.weight"].T.astype(np.float64) + w[p + "fc1.bias"]) \
                @ w[p + "fc2.weight"].T.astype(np.float64) + w[p + "fc2.bias"]
    x = ln_f32(x, w["ln_f.weight"], w["ln_f.bias"])
    logits = x @ w["lm_head.weight"].T.astype(np.float64) + w["lm_head.bias"]
    return logits, k_cache, v_cache



def bias_int32(w, path, sx, sw):
    """§1: b_int32 = round(b_f/(s_x*s_w[n]))。sw=0 的通道取 0。"""
    bpath = path.replace(".weight", ".bias")
    bf = np.asarray(w[bpath], dtype=np.float64)
    so = np.float64(sx) * np.asarray(sw, dtype=np.float64)
    b = np.where(so > 0, np.round(np.divide(bf, so, where=so > 0, out=np.zeros_like(bf))), 0.0)
    return np.clip(b, gc.I32_MIN, gc.I32_MAX).astype(np.int64)


def wqkv_group_quant(wf):
    """Wqkv 权重 9 组量化（组内共享 scale）：q[0:256], k头h[256+64h:320+64h], v头h 同理。"""
    wf = np.asarray(wf, dtype=np.float64)
    assert wf.shape == (768, 256)
    sw = np.zeros(768, np.float32)
    q8 = np.zeros((768, 256), np.int8)
    groups = [(0, 256)] + [(256 + 64 * h, 320 + 64 * h) for h in range(4)] \
           + [(512 + 64 * h, 576 + 64 * h) for h in range(4)]
    for a, b in groups:
        s = np.float32(float(np.max(np.abs(wf[a:b]))) / 127.0)
        sw[a:b] = s
        q8[a:b] = np.clip(np.round(wf[a:b] / np.float64(s)), -128, 127).astype(np.int8)
    return q8, sw


class GemvEmitter:
    """把一条 GEMV 的全部字段写入 npz + manifest 条目（所有 case 共用）。"""

    def __init__(self, z, man_gemvs, step):
        self.z, self.man, self.step = z, man_gemvs, step

    def emit(self, gid, kind, N, K, w_q8, x_q8, b32, y32, yq, m, s,
             path=None, sw=None, sx=None, sx_key=None, ms_rule="", ms_refs=None,
             yfirst=None, note=""):
        g = f"gemv{gid[1:]}"
        pre = f"gold.{self.step}.{g}"
        z = self.z
        z.put(f"{pre}.xin.q8", np.asarray(x_q8, np.int8))
        z.put(f"{pre}.b.int32", np.asarray(b32, np.int32))
        z.put(f"{pre}.y.int32", np.asarray(y32, np.int32))
        z.put(f"{pre}.y.q8", np.asarray(yq, np.int8))
        z.put(f"w.{g}.q8", np.asarray(w_q8, np.int8))
        if sw is not None:
            z.put(f"w.{g}.sw", np.asarray(sw, np.float32))
        z.put(f"rq.{g}.m", np.asarray(m, np.uint32))
        z.put(f"rq.{g}.s", np.asarray(s, np.uint8))
        if sx is not None:
            z.put(f"act.{self.step}.{g}.sx", np.float32(sx))
        if yfirst is not None:
            z.put(f"{pre}.yfirst.int32", np.asarray(yfirst, np.int32))
        self.man.append({
            "id": gid, "npz_prefix": pre, "kind": kind, "path": path,
            "M": 1, "N": int(N), "K": int(K), "macs": int(N * K),
            "keys": {"w": f"w.{g}.q8", "sw": (f"w.{g}.sw" if sw is not None else None),
                     "rq_m": f"rq.{g}.m", "rq_s": f"rq.{g}.s",
                     "b": f"{pre}.b.int32", "xin": f"{pre}.xin.q8",
                     "y_int32": f"{pre}.y.int32", "y_q8": f"{pre}.y.q8",
                     "sx_in": sx_key,
                     **({"yfirst_int32": f"{pre}.yfirst.int32"} if yfirst is not None else {})},
            "ms_rule": ms_rule, "ms_refs": ms_refs or {}, "note": note,
        })


# ---------------------------------------------------------------- case: unit_gemv

UNIT_PAT = {
    "G01": ("uniform", "uniform"), "G02": ("alt", "uniform"), "G03": ("uniform", "x_all127"),
    "G04": ("ext10", "uniform"), "G05": ("rows_ext", "uniform"), "G06": ("uniform", "uniform"),
    "G07": ("alt", "uniform"), "G08": ("ext10", "x_allm128"), "G09": ("rows_ext", "uniform"),
    "G10": ("uniform", "uniform"), "G11": ("ext10", "uniform"), "G12": ("uniform", "x_all127"),
    "G13": ("uniform", "uniform"), "G14": ("alt", "uniform"), "G15": ("ext10", "uniform"),
    "G16": ("uniform", "uniform"), "G17": ("rows_ext", "uniform"), "G18": ("uniform", "uniform"),
    "G19": ("ext10", "uniform"), "G20": ("alt", "x_all127"), "G21": ("uniform", "uniform"),
    "G22": ("rows_ext", "uniform"), "G23": ("uniform", "uniform"), "G24": ("ext10", "uniform"),
    "G25": ("uniform", "uniform"),
}


def draw_int8(rng, shape, pat):
    if pat == "uniform":
        return rng.integers(-128, 128, size=shape, dtype=np.int64)
    if pat == "x_all127":
        return np.full(shape, 127, np.int64)
    if pat == "x_allm128":
        return np.full(shape, -128, np.int64)
    a = rng.integers(-128, 128, size=shape, dtype=np.int64)
    if pat == "alt":
        ii = np.indices(shape).sum(axis=0)
        a = np.where(ii % 2 == 0, 127, -128)
    elif pat == "ext10":
        msk = rng.random(shape) < 0.10
        ext = rng.choice(np.array([127, -128]), size=shape)
        a = np.where(msk, ext, a)
    elif pat == "rows_ext":
        a = np.where(np.arange(shape[0]) % 2 == 0, 127, -128)[:, None] * np.ones(shape[1], np.int64)
    elif pat == "ext_sparse":
        msk = rng.random(shape) < 0.05
        ext = rng.choice(np.array([127, -128]), size=shape)
        a = np.where(msk, ext, a)
    elif pat == "ext_periodic":
        flat = np.arange(a.size)
        a = np.where(flat % 7 == 0, np.where(flat % 14 == 0, 127, -128), a.ravel()).reshape(shape)
    elif pat == "x_ext":
        msk = rng.random(shape) < 0.25
        ext = rng.choice(np.array([127, -128]), size=shape)
        a = np.where(msk, ext, a)
    elif pat == "all_m128":
        a = np.full(shape, -128, np.int64)
    else:
        raise ValueError(pat)
    return a


def gen_unit_gemv(w, cfg, rng, step=0):
    z = gc.NpzWriter()
    man = []
    em = GemvEmitter(z, man, step)
    z.meta("unit_gemv", CONFIG_JSON, note="随机 int8 x/W + 真实量化 M/S（GOLDEN_SPEC §8 用例1）")
    total_macs = 0
    for gid, path, N, K, kind, stage in GEMV_DEFS:
        wpat, xpat = UNIT_PAT[gid]
        w8 = draw_int8(rng, (N, K), wpat).astype(np.int8)
        x8 = draw_int8(rng, (K,), xpat).astype(np.int8)
        sx = np.float32(float(np.max(np.abs(x8.astype(np.float64)))) / 127.0)
        sw = (np.max(np.abs(w8.astype(np.float64)), axis=1) / 127.0).astype(np.float32)
        b32 = np.zeros(N, np.int64)
        y32 = gc.gemv_acc(w8, x8, b32)
        scale_out = np.float64(sx) * sw.astype(np.float64)
        m, s = gc.pick_ms_vec(scale_out)
        yq = gc.requant_np(y32, m, s)
        em.emit(gid, kind="random", N=N, K=K, w_q8=w8, x_q8=x8, b32=b32,
                y32=y32, yq=yq, m=m, s=s, path=path, sw=sw, sx=sx,
                sx_key=f"act.{step}.{f'gemv{gid[1:]}'}.sx",
                ms_rule="perchannel", note=f"pattern w={wpat} x={xpat} stage={stage}")
        total_macs += N * K
    return z, man, total_macs


# ---------------------------------------------------------------- case: e2e_step_T8

class E2E:
    """decode 单步 INT8 全链（step=0，pos=prefill_tokens）。

    requant 配置口径（ms_rule，与 manifest.protocol_notes 同文）：
      * 线性层（Wqkv/Wo/fc1/fc2/lm_head）：scale_out = s_x×s_w[n]/s_out，
        s_out = absmax(y_est)/127 为该输出张量的标定 scale（y_est = y_int32×s_x×s_w，
        生成器侧参考；芯片离线校准同源），y_q 满幅 ±127、dequant = y_q×s_out。
      * Wqkv 按 9 组（q / k×4头 / v×4头）各取组内 s_out → KV cache 行 = requant 输出，
        per-(层,头) scale = 组 s_out，满 8bit 精度。
      * QK：§2.3 默认 scale_out = s_q×s_kv（y_q 为信息视图；真实输出走 int32>>3 路径）。
      * PV：scale_out = s_p×s_v[h]/s_attn_out，s_attn_out = 4 头拼接 absmax/127，
        y_q 拼接即 per-tensor 边界，直接作 Wo 输入。
    """

    def __init__(self, w, cfg, prefill_tokens=8):
        self.w, self.cfg = w, cfg
        self.H = cfg["n_head"]
        self.hd = cfg["d_model"] // self.H
        self.ctx = cfg["max_ctx"]
        self.T = prefill_tokens
        self.pos = prefill_tokens
        self.z = gc.NpzWriter()
        self.man = []
        self.em = GemvEmitter(self.z, self.man, 0)
        self.wq = {}

    def quant_weights(self):
        for path in ["blocks.0.Wqkv.weight", "blocks.1.Wqkv.weight"]:
            q8, sw = wqkv_group_quant(self.w[path])
            self.wq[path] = {"q8": q8, "sw": sw}
        for path in ["blocks.0.Wo.weight", "blocks.0.fc1.weight", "blocks.0.fc2.weight",
                     "blocks.1.Wo.weight", "blocks.1.fc1.weight", "blocks.1.fc2.weight",
                     "lm_head.weight"]:
            q8, sw = gc.q_per_channel(self.w[path])
            self.wq[path] = {"q8": q8, "sw": sw}
        for path, d in self.wq.items():
            self.z.put(f"w.{path}.q8", d["q8"])
            self.z.put(f"w.{path}.sw", d["sw"].astype(np.float32))

    @staticmethod
    def _cal_s_out(y32, per_ch_scale):
        """s_out = absmax(y_est)/127；y_est = y_int32 × per-channel requant 等效 scale。"""
        est = np.asarray(y32, np.float64) * np.asarray(per_ch_scale, np.float64)
        am = float(np.max(np.abs(est))) if est.size else 0.0
        return np.float32(am / 127.0)

    def gemv_linear(self, gid, path, x_q8, sx, sx_key, out_act_key):
        d = self.wq[path]
        b32 = bias_int32(self.w, path, sx, d["sw"])
        y32 = gc.gemv_acc(d["q8"], x_q8, b32)
        so = np.float64(sx) * d["sw"].astype(np.float64)
        s_out = self._cal_s_out(y32, so)
        if float(s_out) == 0.0:
            s_out = np.float32(1.0)
        cfg_scale = so / np.float64(s_out)
        m, s = gc.pick_ms_vec(cfg_scale)
        yq = gc.requant_np(y32, m, s)
        self.em.emit(gid, kind="weight", N=d["q8"].shape[0], K=d["q8"].shape[1],
                     w_q8=d["q8"], x_q8=x_q8, b32=b32, y32=y32, yq=yq, m=m, s=s,
                     path=path, sw=d["sw"], sx=sx, sx_key=sx_key,
                     ms_rule="perchannel_cal",
                     ms_refs={"s_out_key": out_act_key + ".sx"})
        self.z.put(f"rq.{path}.m", m.astype(np.uint32))
        self.z.put(f"rq.{path}.s", s.astype(np.uint8))
        self.z.put(out_act_key + ".q8", yq.astype(np.int8))
        self.z.put(out_act_key + ".sx", np.float32(s_out))
        return y32, yq, s_out

    def block(self, l, xq_in, xsx_in, k_f, v_f):
        w, z, cfg = self.w, self.z, self.cfg
        H, hd, ctx, pos, T = self.H, self.hd, self.ctx, self.pos, self.T
        p = f"blocks.{l}."
        pre = f"act.0.L{l}."
        L = l

        z.put(pre + "ln1_in.q8", xq_in)
        z.put(pre + "ln1_in.sx", np.float32(xsx_in))

        ln1_f = ln_f32(dequant(xq_in, xsx_in), w[p + "ln1.weight"], w[p + "ln1.bias"])
        ln1_q, ln1_sx = quant_boundary(ln1_f)
        z.put(pre + "ln1_out.q8", ln1_q)
        z.put(pre + "ln1_out.sx", np.float32(ln1_sx))
        z.put(pre + "ln1_out.f32", ln1_f.astype(np.float32))

        path = f"blocks.{l}.Wqkv.weight"
        d = self.wq[path]
        b32 = bias_int32(w, path, ln1_sx, d["sw"])
        y32 = gc.gemv_acc(d["q8"], ln1_q, b32)
        sw64 = d["sw"].astype(np.float64)
        swq, swk, swv = sw64[:256], sw64[256:512:64], sw64[512:768:64]
        est_q = y32[:256] * (np.float64(ln1_sx) * swq)
        s_q_out = self._cal_s_out(est_q, np.ones(256))
        est_k = np.stack([y32[256 + 64 * h:320 + 64 * h] * (np.float64(ln1_sx) * swk[h])
                          for h in range(H)])
        est_v = np.stack([y32[512 + 64 * h:576 + 64 * h] * (np.float64(ln1_sx) * swv[h])
                          for h in range(H)])
        s_k_out = np.array([self._cal_s_out(est_k[h], np.ones(hd)) for h in range(H)], np.float32)
        s_v_out = np.array([self._cal_s_out(est_v[h], np.ones(hd)) for h in range(H)], np.float32)
        scale_out = np.concatenate([
            np.float64(ln1_sx) * swq / np.float64(s_q_out),
            np.concatenate([np.full(64, np.float64(ln1_sx) * swk[h] / np.float64(s_k_out[h]))
                            for h in range(H)]),
            np.concatenate([np.full(64, np.float64(ln1_sx) * swv[h] / np.float64(s_v_out[h]))
                            for h in range(H)])])
        m, s = gc.pick_ms_vec(scale_out)
        yq = gc.requant_np(y32, m, s)
        self.em.emit(f"G{1 + 12 * L:02d}", kind="weight", N=768, K=256,
                     w_q8=d["q8"], x_q8=ln1_q, b32=b32, y32=y32, yq=yq, m=m, s=s,
                     path=path, sw=d["sw"], sx=ln1_sx, sx_key=pre + "ln1_out.sx",
                     ms_rule="wqkv_group_cal",
                     ms_refs={"s_out_keys": [pre + "q.sx", pre + "k.sx", pre + "v.sx"]})
        z.put(f"rq.{path}.m", m.astype(np.uint32))
        z.put(f"rq.{path}.s", s.astype(np.uint8))

        z.put(pre + "q.q8", yq[:256].astype(np.int8))
        z.put(pre + "q.sx", np.float32(s_q_out))
        z.put(pre + "q.f32", dequant(yq[:256], s_q_out).astype(np.float32))
        qb_q, qb_sx = yq[:256].astype(np.int8), s_q_out
        self.k_sx[l] = s_k_out
        self.v_sx[l] = s_v_out
        for h in range(H):
            self.k_cache8[l][h][pos] = yq[256 + 64 * h:320 + 64 * h]
            self.v_cache8[l][h][pos] = yq[512 + 64 * h:576 + 64 * h]
            self.k_cache8[l][h][:pos] = np.clip(np.round(
                k_f[l][h][:pos].astype(np.float64) / np.float64(s_k_out[h])), -128, 127).astype(np.int8)
            self.v_cache8[l][h][:pos] = np.clip(np.round(
                v_f[l][h][:pos].astype(np.float64) / np.float64(s_v_out[h])), -128, 127).astype(np.int8)
        z.put(pre + "k.sx", s_k_out.astype(np.float32))
        z.put(pre + "v.sx", s_v_out.astype(np.float32))
        q_f = dequant(qb_q, qb_sx)

        qk_scaled = np.zeros((H, ctx), np.int64)
        for h in range(H):
            gid = f"G{2 + h + 12 * L:02d}"
            kw = self.k_cache8[l][h]                                # [ctx,hd]
            y32q = gc.gemv_acc(kw, qb_q[64 * h:64 * h + 64], np.zeros(ctx, np.int64))
            sc = np.float64(qb_sx) * np.float64(s_k_out[h])
            mq, sq = gc.pick_ms_vec(np.full(ctx, sc))
            yqq = gc.requant_np(y32q, mq, sq)
            self.em.emit(gid, kind="cache_qk", N=ctx, K=hd, w_q8=kw,
                         x_q8=qb_q[64 * h:64 * h + 64], b32=np.zeros(ctx, np.int64),
                         y32=y32q, yq=yqq, m=mq, s=sq, sx=qb_sx, sx_key=pre + "q.sx",
                         ms_rule="qk_default",
                         note="W=本步 KV cache k 行快照（运行期数据，非 ROM）")
            qk_scaled[h] = y32q >> ATTN_SCALE_SHIFT                 # §5 ×0.125
        z.put(pre + "qk_scaled.int32", qk_scaled.astype(np.int32))

        score_f = dequant(qk_scaled, np.float64(qb_sx) * s_k_out[:, None] / (1 << ATTN_SCALE_SHIFT))
        valid = np.zeros(ctx)
        valid[:pos + 1] = 1
        score_f = score_f + np.where(valid, 0.0, MASK_NEG)
        z.put(pre + "attn_logits.f32", score_f.astype(np.float32))
        prob_f = softmax_f32(score_f, axis=-1)
        prob_q, prob_sx = quant_boundary(prob_f)
        z.put(pre + "attn_prob.q8", prob_q)
        z.put(pre + "attn_prob.sx", np.float32(prob_sx))
        z.put(pre + "attn_prob.f32", prob_f.astype(np.float32))

        est_heads = []
        for h in range(H):
            vw = self.v_cache8[l][h].T                              # [hd,ctx]
            y32p = gc.gemv_acc(vw, prob_q[h], np.zeros(hd, np.int64))
            est_heads.append(y32p * (np.float64(prob_sx) * np.float64(s_v_out[h])))
        s_attn_out = self._cal_s_out(np.concatenate(est_heads), np.ones(256))
        head_yq = np.zeros((H, hd), np.int8)
        for h in range(H):
            gid = f"G{6 + h + 12 * L:02d}"
            vw = self.v_cache8[l][h].T
            y32p = gc.gemv_acc(vw, prob_q[h], np.zeros(hd, np.int64))
            cp = np.full(hd, np.float64(prob_sx) * np.float64(s_v_out[h]) / np.float64(s_attn_out))
            mp, sp = gc.pick_ms_vec(cp)
            yqp = gc.requant_np(y32p, mp, sp)
            self.em.emit(gid, kind="cache_pv", N=hd, K=ctx, w_q8=vw,
                         x_q8=prob_q[h], b32=np.zeros(hd, np.int64),
                         y32=y32p, yq=yqp, m=mp, s=sp, sx=prob_sx, sx_key=pre + "attn_prob.sx",
                         ms_rule="pv_cal",
                         ms_refs={"s_out_key": pre + "attn_out.sx"},
                         note="W=本步 KV cache v 行转置（运行期数据，非 ROM）")
            head_yq[h] = yqp
        z.put(pre + "attn_out.q8", head_yq.reshape(256))
        z.put(pre + "attn_out.sx", np.float32(s_attn_out))
        z.put(pre + "attn_out.f32", dequant(head_yq.reshape(256), s_attn_out).astype(np.float32))

        _, wo_yq, s_wo = self.gemv_linear(f"G{10 + 12 * L:02d}", f"blocks.{l}.Wo.weight",
                                          head_yq.reshape(256), s_attn_out,
                                          pre + "attn_out.sx", pre + "wo_out")
        wo_f = dequant(wo_yq, s_wo)

        res1_sum = dequant(xq_in, xsx_in) + wo_f
        res1_q, res1_sx = quant_boundary(res1_sum)
        z.put(pre + "res1.q8", res1_q)
        z.put(pre + "res1.sx", np.float32(res1_sx))
        z.put(pre + "res1.f32", res1_sum.astype(np.float32))
        res1_f = dequant(res1_q, res1_sx)

        ln2_f = ln_f32(res1_f, w[p + "ln2.weight"], w[p + "ln2.bias"])
        ln2_q, ln2_sx = quant_boundary(ln2_f)
        z.put(pre + "ln2_out.q8", ln2_q)
        z.put(pre + "ln2_out.sx", np.float32(ln2_sx))
        z.put(pre + "ln2_out.f32", ln2_f.astype(np.float32))

        _, fc1_yq, s_fc1 = self.gemv_linear(f"G{11 + 12 * L:02d}", f"blocks.{l}.fc1.weight",
                                            ln2_q, ln2_sx, pre + "ln2_out.sx", pre + "fc1_out")
        gelu_in_f = dequant(fc1_yq, s_fc1)
        z.put(pre + "fc1_out.f32", gelu_in_f.astype(np.float32))
        gelu_f = gelu_f32(gelu_in_f)
        gelu_q, gelu_sx = quant_boundary(gelu_f)
        z.put(pre + "gelu_out.q8", gelu_q)
        z.put(pre + "gelu_out.sx", np.float32(gelu_sx))
        z.put(pre + "gelu_out.f32", gelu_f.astype(np.float32))

        _, fc2_yq, s_fc2 = self.gemv_linear(f"G{12 + 12 * L:02d}", f"blocks.{l}.fc2.weight",
                                            gelu_q, gelu_sx, pre + "gelu_out.sx", pre + "fc2_out")
        fc2_f = dequant(fc2_yq, s_fc2)
        res2_sum = res1_f + fc2_f
        res2_q, res2_sx = quant_boundary(res2_sum)
        z.put(pre + "res2.q8", res2_q)
        z.put(pre + "res2.sx", np.float32(res2_sx))
        z.put(pre + "res2.f32", res2_sum.astype(np.float32))
        return res2_q, res2_sx, dequant(res2_q, res2_sx)

    def run(self):
        cfg, w, z = self.cfg, self.w, self.z
        self.quant_weights()
        ids = np.random.default_rng(20261023).integers(0, cfg["vocab"], self.T)
        logits_f, k_f, v_f = prefill_fp32(w, cfg, ids)
        self.token_in = int(np.argmax(logits_f[-1]))
        x_emb_f = w["wte.weight"][self.token_in] + w["wpe.weight"][self.pos]

        self.k_cache8 = np.zeros((cfg["n_layer"], self.H, self.ctx, self.hd), np.int8)
        self.v_cache8 = np.zeros_like(self.k_cache8)
        self.k_sx = np.zeros((cfg["n_layer"], self.H), np.float32)
        self.v_sx = np.zeros_like(self.k_sx)

        xq, xsx = quant_boundary(x_emb_f)
        z.put("act.0.x_emb.q8", xq)
        z.put("act.0.x_emb.sx", np.float32(xsx))
        z.put("act.0.x_emb.f32", x_emb_f.astype(np.float32))
        x_f = dequant(xq, xsx)
        for l in range(cfg["n_layer"]):
            xq, xsx, x_f = self.block(l, xq, xsx, k_f, v_f)

        lnf_f = ln_f32(x_f, w["ln_f.weight"], w["ln_f.bias"])
        lnf_q, lnf_sx = quant_boundary(lnf_f)
        z.put("act.0.lnf_out.q8", lnf_q)
        z.put("act.0.lnf_out.sx", np.float32(lnf_sx))
        z.put("act.0.lnf_out.f32", lnf_f.astype(np.float32))
        logits32, logitsq, _ = self.gemv_linear("G25", "lm_head.weight",
                                                lnf_q, lnf_sx, "act.0.lnf_out.sx",
                                                "act.0.logits")
        self.token_pred = int(np.argmax(logits32))
        z.put("logits.0.int32", logits32.astype(np.int32))
        z.put("logits.0.q8", logitsq.astype(np.int8))

        valid = np.zeros(self.ctx, np.int8)
        valid[:self.pos + 1] = 1
        z.put("mask.0.valid", valid)
        z.put("mask.0.add.f32", np.where(valid == 1, np.float32(0.0), np.float32(MASK_NEG)))
        for l in range(cfg["n_layer"]):
            for nm, cache8, sx in (("k", self.k_cache8, self.k_sx), ("v", self.v_cache8, self.v_sx)):
                z.put(f"kv.0.L{l}.{nm}.q8", cache8[l])
                z.put(f"kv.0.L{l}.{nm}.sx", sx[l].astype(np.float32))
                z.put(f"kv.0.L{l}.{nm}new.q8", cache8[l][:, self.pos, :])
        z.meta("e2e_step_T8", CONFIG_JSON,
               token_in=np.int64(self.token_in), token_pred=np.int64(self.token_pred),
               pos=np.int64(self.pos), prefill_tokens=np.int64(self.T),
               ln_eps=np.float32(LN_EPS), qk_shift=np.int64(ATTN_SCALE_SHIFT),
               bias_order=np.array("bias_last"),
               note="prefill 为 fp32 参考；decode 步全 INT8 链（输出标定 requant 口径），§5 全部量化点")
        self._kf, self._vf = k_f, v_f
        return ids, logits_f

    def prefill_cache(self):
        return self._kf, self._vf


# ---------------------------------------------------------------- case: corner / rand20

def bias_first_gemv(w8, x8, b32):
    """RTL 预置口径（ame_ref bias_first）：累加器预置 bias，每步 SAT32。纯 python。"""
    n, k = len(w8), len(x8)
    y = [int(v) for v in b32]
    for kk in range(k):
        xk = int(x8[kk])
        for ni in range(n):
            v = y[ni] + int(w8[ni][kk]) * xk
            y[ni] = gc.I32_MIN if v < gc.I32_MIN else (gc.I32_MAX if v > gc.I32_MAX else v)
    return np.array(y, np.int64)


def gen_corner(rng, step=0):
    z = gc.NpzWriter()
    man = []
    em = GemvEmitter(z, man, step)
    z.meta("corner", CONFIG_JSON, note="①K=1024 最长累加 ②SAT32 ③M=1,S=1 直通 ④全零（§8 用例3）")
    total = 0

    N, K = 64, 1024
    w8 = np.clip(np.round(rng.normal(0, 25, (N, K))), -128, 127).astype(np.int8)
    x8 = np.clip(np.round(rng.normal(0, 40, K)), -128, 127).astype(np.int8)
    sx = np.float32(np.max(np.abs(x8.astype(np.float64))) / 127.0)
    sw = (np.max(np.abs(w8.astype(np.float64)), axis=1) / 127.0).astype(np.float32)
    b32 = np.zeros(N, np.int64)
    y32 = gc.gemv_acc(w8, x8, b32)
    m, s = gc.pick_ms_vec(np.float64(sx) * sw.astype(np.float64))
    em.emit("G01", "corner_longacc", N, K, w8, x8, b32, y32, gc.requant_np(y32, m, s), m, s,
            sw=sw, sx=sx, sx_key=f"act.{step}.gemv01.sx", ms_rule="perchannel",
            note="K=1024 最长累加路径")
    total += N * K

    N, K = 8, 1024
    x8 = np.full(K, 127, np.int64)
    w8 = np.zeros((N, K), np.int64)
    w8[0] = 127
    w8[1] = -128
    w8[2:6] = draw_int8(rng, (4, K), "uniform")
    w8[6] = -128
    w8[7] = 127
    w8 = w8.astype(np.int8)
    b32 = np.array([gc.I32_MAX, gc.I32_MIN, gc.I32_MAX, gc.I32_MIN,
                    1 << 30, -(1 << 30), gc.I32_MAX, gc.I32_MIN], np.int64)
    sx = np.float32(1.0)
    sw = (np.max(np.abs(w8.astype(np.float64)), axis=1) / 127.0).astype(np.float32)
    y32 = gc.gemv_acc(w8, x8, b32)
    m, s = gc.pick_ms_vec(np.float64(sx) * sw.astype(np.float64))
    yfirst = bias_first_gemv(w8, x8, b32)
    diverged = int(np.sum(yfirst != y32))
    em.emit("G02", "corner_sat32", N, K, w8, x8, b32, y32, gc.requant_np(y32, m, s), m, s,
            sw=sw, sx=sx, sx_key=f"act.{step}.gemv02.sx",
            ms_rule="perchannel", yfirst=yfirst,
            note=f"bias_last 口径（GOLDEN 定义）；bias_first 变体存 yfirst.int32，"
                 f"两口径分歧通道数={diverged}（混合积+巨bias 通道）")
    total += N * K

    N, K = 32, 256
    w8 = draw_int8(rng, (N, K), "uniform").astype(np.int8)
    x8 = draw_int8(rng, (K,), "uniform").astype(np.int8)
    sx = np.float32(np.max(np.abs(x8.astype(np.float64))) / 127.0)
    sw = (np.max(np.abs(w8.astype(np.float64)), axis=1) / 127.0).astype(np.float32)
    b32 = np.zeros(N, np.int64)
    y32 = gc.gemv_acc(w8, x8, b32)
    m = np.full(N, 1, np.uint32)
    s = np.full(N, 1, np.uint8)
    em.emit("G03", "corner_passthrough", N, K, w8, x8, b32, y32, gc.requant_np(y32, m, s), m, s,
            sw=sw, sx=sx, sx_key=f"act.{step}.gemv03.sx", ms_rule="forced_1_1",
            note="强制寄存器直通：yq=clip((y32+1)>>1)，绕过 §2.3 生成规则")
    total += N * K

    N, K = 16, 64
    w8 = np.zeros((N, K), np.int8)
    x8 = np.zeros(K, np.int8)
    sx = np.float32(0.0)
    sw = np.zeros(N, np.float32)
    b32 = np.zeros(N, np.int64)
    y32 = gc.gemv_acc(w8, x8, b32)
    m, s = gc.pick_ms_vec(np.zeros(N))                # → (1,63)
    em.emit("G04", "corner_zero", N, K, w8, x8, b32, y32, gc.requant_np(y32, m, s), m, s,
            sw=sw, sx=sx, sx_key=f"act.{step}.gemv04.sx", ms_rule="perchannel",
            note="全零输入/权重/bias；sx=0 退化路径")
    total += N * K
    return z, man, total


RAND_SHAPES = [
    (16, 16, "alt", "uniform", 0),
    (32, 32, "uniform", "uniform", 0),
    (64, 64, "ext10", "uniform", 0),
    (128, 256, "uniform", "uniform", 0),
    (256, 1024, "rows_ext", "uniform", 0),
    (1024, 256, "uniform", "x_all127", 0),
    (48, 80, "uniform", "uniform", 0),
    (96, 112, "ext_sparse", "uniform", 0),
    (240, 272, "uniform", "uniform", 0),
    (512, 1024, "uniform", "uniform", 0),
    (17, 16, "uniform", "uniform", 0),
    (16, 17, "uniform", "uniform", 0),
    (33, 63, "ext_periodic", "uniform", 0),
    (100, 100, "uniform", "uniform", 0),
    (127, 129, "uniform", "uniform", 0),
    (250, 17, "uniform", "x_ext", 0),
    (63, 65, "uniform", "uniform", 0),
    (15, 31, "uniform", "uniform", 0),
    (1, 16, "all_m128", "uniform", 0),
    (1, 7, "uniform", "x_all127", gc.I32_MAX - 2048),
]


def gen_rand20(rng, step=0):
    z = gc.NpzWriter()
    man = []
    em = GemvEmitter(z, man, step)
    z.meta("rand20", CONFIG_JSON, note="20 组随机 (N,K)：整除/余数/极值集中/单行/bias 贴边；GEMV M=1")
    total = 0
    for i, (N, K, wpat, xpat, bval) in enumerate(RAND_SHAPES):
        gid = f"G{i + 1:02d}"
        w8 = draw_int8(rng, (N, K), wpat).astype(np.int8)
        x8 = draw_int8(rng, (K,), xpat).astype(np.int8)
        sx = np.float32(np.max(np.abs(x8.astype(np.float64))) / 127.0)
        sw = (np.max(np.abs(w8.astype(np.float64)), axis=1) / 127.0).astype(np.float32)
        b32 = np.full(N, bval, np.int64) if bval else np.zeros(N, np.int64)
        y32 = gc.gemv_acc(w8, x8, b32)
        m, s = gc.pick_ms_vec(np.float64(sx) * sw.astype(np.float64))
        em.emit(gid, "random", N, K, w8, x8, b32, y32, gc.requant_np(y32, m, s), m, s,
                sw=sw, sx=sx, sx_key=f"act.{step}.{f'gemv{i + 1:02d}'}.sx",
                ms_rule="perchannel",
                note=f"w={wpat} x={xpat} bias={'I32MAX-2048' if bval else 0}"
                     f"{' [16整除]' if N % 16 == 0 and K % 16 == 0 else ' [含余数]'}")
        total += N * K
    return z, man, total



def onnx_crosscheck(w, cfg, ids, logits_f, kf, vf):
    """prefill 逐位置 vs minigpt_decode.onnx（wl_minigpt 5c 同款约定）。

    pos=i 时喂 cache 行 0..i（含自身行——与硬件"控制器先写 k/v 新行再读 0..pos"
    及 prefill 因果注意力一致），mask 掩 i+1 以后；比对 logits[i]。
    """
    import onnxruntime as ort
    T = len(ids)
    so = ort.SessionOptions()
    sess = ort.InferenceSession(os.path.join(MODELS, "minigpt_decode.onnx"), so,
                                providers=["CPUExecutionProvider"])
    worst = 0.0
    for i in range(T):
        kc = np.zeros((cfg["n_layer"], cfg["n_head"], cfg["max_ctx"],
                       cfg["d_model"] // cfg["n_head"]), np.float32)
        vc = np.zeros_like(kc)
        kc[:, :, :i + 1, :] = kf[:, :, :i + 1, :]
        vc[:, :, :i + 1, :] = vf[:, :, :i + 1, :]
        mask = np.zeros((1, 1, 1, cfg["max_ctx"]), np.float32)
        mask[..., i + 1:] = MASK_NEG
        x_emb = (w["wte.weight"][ids[i]] + w["wpe.weight"][i]).astype(np.float32)[None]
        out = sess.run(None, {"x_emb": x_emb, "k_cache": kc, "v_cache": vc, "mask": mask})
        d = float(np.max(np.abs(out[0][0] - logits_f[i])))
        worst = max(worst, d)
    return worst


# ---------------------------------------------------------------- main

def sha256_file(p):
    import hashlib
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for c in iter(lambda: f.read(1 << 20), b""):
            h.update(c)
    return h.hexdigest()


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--root", default=os.path.join(MODELS, "golden"))
    ap.add_argument("--seed", type=int, default=20261023)
    ap.add_argument("--prefill-tokens", type=int, default=8)
    ap.add_argument("--skip-onnx-check", action="store_true")
    args = ap.parse_args()

    global CONFIG_JSON
    with open(os.path.join(MODELS, "minigpt_config.json")) as f:
        CONFIG_JSON = f.read()
    cfg = json.loads(CONFIG_JSON)
    w = {k: v for k, v in np.load(os.path.join(MODELS, "minigpt_weights.npz")).items()}
    rng = np.random.default_rng(args.seed)

    os.makedirs(args.root, exist_ok=True)
    manifest = {
        "protocol_version": gc.PROTOCOL_VERSION,
        "created_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
        "spec": "docs/GOLDEN_SPEC.md",
        "generator": {
            "script": "scripts/gld_gen.py",
            "command": (f"source ~/venvs/tpu-mlir/bin/activate && cd {ROOT} && "
                        f"python scripts/gld_gen.py --root models/golden --seed {args.seed} "
                        f"--prefill-tokens {args.prefill_tokens}"),
            "python": sys.version.split()[0],
            "numpy": np.__version__,
            "seed": args.seed, "prefill_tokens": args.prefill_tokens,
            "weights_npz": "models/minigpt_weights.npz",
            "weights_sha256": sha256_file(os.path.join(MODELS, "minigpt_weights.npz")),
            "decode_onnx": "models/minigpt_decode.onnx",
        },
        "quant_source": "numpy",
        "quant_note": ("GOLDEN_SPEC §1/§2.3 即规范级量化定义（对称 zp=0、banker's rounding、"
                       "absmax scale、M/S 浮点公式），numpy 逐字实现为唯一权威；"
                       "tpu-mlir 校准工具链的 scale 选择与该协议不一致，不作 scale 来源"
                       "（理由见 reports/issues/P2E.md §量化权威性）。"),
        "protocol_notes": {
            "quant_act": "per-tensor sx=absmax/127, q=clip(round_bankers(x/sx),-128,127)，float64 计算",
            "quant_weight": "per-channel sw=absmax_row/127；Wqkv 为 9 组组内共享 scale（q,k×4头,v×4头）",
            "pick_ms": "§2.3 逐字：S 从 63 降序，M=round_bankers(scale_out*2^S)，首个 M<=2^31-1 即选，"
                       "M=max(M,1)；全溢出→(2^31-1,1)。float64 语义，比对侧须同口径",
            "mac": "k 升序累加，每步 SAT32；bias_last：全 k 完成后一次 SAT32 加入。"
                   "K<=8192 时 |部分和|<=K*2^14<2^31，途中 SAT 永不触发（gld_common.gemv_acc 断言保护）",
            "requant": "ROUND_SEL=1：yq=clip((s64(y)*u64(M)+2^(S-1))>>>S,-128,127)，S>=1",
            "qk_shift": "scores×0.125 = y_int32 >> 3 截断算术右移（§5；ROUND_SEL 不适用）",
            "softmax_gelu_ln": "fp64 参考实现：LN eps=1e-5、GELU=erf 精确式、softmax 减 max",
            "bias_order": "npz golden=bias_last（GOLDEN 定义）；RTL 预置口径 bias_first 见 "
                          "tb/ame/ame_ref.py；corner/gemv02 另存 gold.0.gemv02.yfirst.int32",
            "requant_cfg": "e2e 线性层采用输出标定口径 scale_out=(s_x*s_w)/s_out（s_out=absmax"
                           "(y_est)/127，y_est=y_int32*s_x*s_w，等价于芯片离线校准），使 y_q 满幅 "
                           "±127；QK 用 §2.3 默认 scale_out=s_q*s_kv（y_q 为信息视图，真实输出走 "
                           "int32>>3）。unit/corner/rand 用 §2.3 默认口径（c≈1，y_q 大面积饱和 "
                           "±127 属规范公式直接结果，主比对目标为 y_int32 位精确）",
            "y_q_semantics": "y_q 的浮点含义由所选 scale_out 决定：§2.3 默认口径下 y_q≈y_f"
                             "（浮点单位）；输出标定口径下 y_q=y_f/s_out（int8 单位）。"
                             "比对一律按整数字节，dequant 需查 manifest.ms_rule",
            "l2_flow": "每 GEMV 输入=§5 边界 q8（per-tensor absmax/127 或 requant 输出，幅度满 "
                       "±127）；层间 dequant=y_q*s_out（输出标定口径）；Wqkv 9 组组内 s_out 一致"
                       "=KV per-(层,头) cache scale（cache 行满 8bit 精度）；prefill k/v 行按同组 "
                       "scale 量化入 cache；注意力含自身行（控制器先写 row[pos] 再 QK，"
                       "WORKLOAD §7 口径，mask.0.valid 前 pos+1 行有效）",
        },
        "mem_files": {
            "naming": "<case>/gemv{GG}_{w|x|b_int32|y_int32|y_q|regs_m|regs_s}.mem；"
                      "w 权重 ROM 镜像默认 tile16（N,K 均被 16 整除时，否则 rowmajor 打包），"
                      "并附 _w_rowmajor.mem / _w_tile16.mem / _w_tile32.mem（可整除时）",
            "formats": {"w": "4×int8 小端打包 32-bit 字，每行 8 hex 大写，首行 // layout= path= N= K= words=",
                        "x/y_q/regs_s": "每行 2 hex（int8 二补码 / uint8）",
                        "y_int32/b_int32/regs_m": "每行 8 hex（int32 二补码 / uint32，按通道升序）",
                        "通用": "ASCII 空白分隔、允许 // 注释、不用 @addr（§7）"},
        },
        "cases": {},
    }

    head, dirty = gc.git_info(ROOT)
    manifest["generator"]["git_head"] = head
    manifest["generator"]["git_dirty"] = dirty

    stats = []

    # ---- unit_gemv ----
    z, man, macs = gen_unit_gemv(w, cfg, rng)
    p = z.save(os.path.join(args.root, "unit_gemv", "case.npz"))
    manifest["cases"]["unit_gemv"] = {
        "npz": "unit_gemv/case.npz", "sha256": sha256_file(p), "step": 0,
        "description": "G1..G25 随机 int8 + 真实量化 M/S（§8 用例1）",
        "gemv_count": len(man), "total_macs": macs, "gemvs": man}
    stats.append(("unit_gemv", len(man), macs))

    # ---- e2e_step_T8 ----
    e = E2E(w, cfg, args.prefill_tokens)
    ids, logits_f = e.run()
    kf, vf = e.prefill_cache()
    onnx_note = {"skipped": True}
    if not args.skip_onnx_check:
        worst = onnx_crosscheck(w, cfg, ids, logits_f, kf, vf)
        ok = worst < 1e-3
        onnx_note = {"max_abs_diff_prefill_vs_decode_graph": worst, "threshold": 1e-3,
                     "passed": bool(ok), "positions": args.prefill_tokens}
        assert ok, f"prefill fp32 参考与 decode 图偏差 {worst:.3e} 超阈值"
    manifest["onnx_crosscheck"] = onnx_note
    p = z2path = e.z.save(os.path.join(args.root, "e2e_step_T8", "case.npz"))
    macs = sum(g["macs"] for g in e.man)
    manifest["cases"]["e2e_step_T8"] = {
        "npz": "e2e_step_T8/case.npz", "sha256": sha256_file(p), "step": 0,
        "description": f"prefill {args.prefill_tokens} token（fp32 参考）+ 1 步 decode 全 INT8 链",
        "token_in": e.token_in, "token_pred": e.token_pred, "pos": e.pos,
        "gemv_count": len(e.man), "total_macs": macs, "gemvs": e.man}
    stats.append(("e2e_step_T8", len(e.man), macs))

    # ---- corner ----
    z, man, macs = gen_corner(rng)
    p = z.save(os.path.join(args.root, "corner", "case.npz"))
    manifest["cases"]["corner"] = {
        "npz": "corner/case.npz", "sha256": sha256_file(p), "step": 0,
        "description": "K=1024 最长累加 / SAT32 / M=1,S=1 直通 / 全零（§8 用例3）",
        "gemv_count": len(man), "total_macs": macs, "gemvs": man}
    stats.append(("corner", len(man), macs))

    # ---- rand20 ----
    z, man, macs = gen_rand20(rng)
    p = z.save(os.path.join(args.root, "rand20", "case.npz"))
    manifest["cases"]["rand20"] = {
        "npz": "rand20/case.npz", "sha256": sha256_file(p), "step": 0,
        "description": "20 组随机形状：16 整除/余数/极值集中/单行/bias 贴边（GEMV M=1）",
        "gemv_count": len(man), "total_macs": macs, "gemvs": man}
    stats.append(("rand20", len(man), macs))

    gc.dump_manifest(os.path.join(args.root, "manifest.json"), manifest)

    print("== golden 生成完成 ==")
    for name, n, macs in stats:
        print(f"  {name:12s} gemv={n:3d} MACs={macs:,}")
    print(f"  总计         gemv={sum(n for _, n, _ in stats):3d} "
          f"MACs={sum(m for _, _, m in stats):,}")
    print(f"  quant_source = numpy ; onnx_crosscheck = {onnx_note}")
    print(f"  e2e token_in={e.token_in} token_pred={e.token_pred}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
