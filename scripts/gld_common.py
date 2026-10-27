#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""gld_common.py — W2E golden 生成侧协议库（严格按 docs/GOLDEN_SPEC.md）。

本文件只被**生成器**（scripts/gld_gen.py）使用。比对侧（scripts/gld_verify.py、
tb/ame/golden_reader.py）按 GOLDEN_SPEC §9 要求各自独立实现 §2 协议，禁止 import 本文件。

数值口径（manifest.rounding 有同名记录）：
  * quant  : 对称、zp=0、banker's rounding（np.round）——GOLDEN_SPEC §1；
             一律先升 float64 再除（manifest.quant_compute_dtype="float64"）。
  * pick_ms: §2.3 伪代码逐字实现——S 从 63 降到 1，M=round_bankers(scale_out×2^S)，
             首个 M<=2^31-1 的 S 即选中，M=max(M,1)；永不溢出时返回 (2^31-1, 1)。
  * GEMV   : §2.1 —— 部分和 k 升序、每步 SAT32；本库用 cumsum 等价实现，等价性由
             断言 |partial| <= K×2^14 < 2^31 保证（K<=8192，见 gemv_acc 内断言）；
             bias 在全部 k 累加完后一次 SAT32 加入（bias_last，GOLDEN 定义口径，
             与 tb/ame/ame_ref.py 的 bias_first 口径区分，见该文件 docstring）。
  * requant: §2.2 ROUND_SEL=1 —— y_q = clip((s64(y)×u64(M) + 2^(S-1)) >>> S, -128, 127)，
             S>=1 强制；numpy 的 >> 对有符号整数即算术右移（向下取整）。
"""
import json
import os

import numpy as np

PROTOCOL_VERSION = "1.0"
I8_MIN, I8_MAX = -128, 127
I32_MIN, I32_MAX = -(1 << 31), (1 << 31) - 1


def q_per_tensor(x_f32):
    """GOLDEN_SPEC §1 激活量化：s_x = absmax/127，banker's rounding。→(q8, sx_f32标量)"""
    x = np.asarray(x_f32, dtype=np.float64)
    am = float(np.max(np.abs(x))) if x.size else 0.0
    sx = np.float32(am / 127.0)
    if float(sx) == 0.0:
        return np.zeros(x.shape, np.int8), sx
    q = np.clip(np.round(x / np.float64(sx)), I8_MIN, I8_MAX).astype(np.int8)
    return q, sx


def q_per_channel(w_f32):
    """GOLDEN_SPEC §1 权重量化：按输出行 n 的 per-channel scale。→(q8[N,K], sw_f32[N])"""
    w = np.asarray(w_f32, dtype=np.float64)
    am = np.max(np.abs(w), axis=1)
    sw = (am / 127.0).astype(np.float32)
    sw64 = sw.astype(np.float64)
    safe = np.where(sw64 == 0.0, 1.0, sw64)
    q = np.clip(np.round(w / safe[:, None]), I8_MIN, I8_MAX).astype(np.int8)
    q[sw64 == 0.0] = 0
    return q, sw


def pick_ms(scale_out):
    """GOLDEN_SPEC §2.3 M/S 生成（生成器侧唯一权威实现；float64 语义）。"""
    so = float(np.float64(scale_out))
    for s in range(63, 0, -1):
        m = int(np.round(so * float(1 << s)))        # banker's rounding
        if m <= I32_MAX:
            return max(m, 1), s
    return I32_MAX, 1


def pick_ms_vec(scale_out_arr):
    """向量化 pick_ms：输入 [N] float，返回 (M uint32[N], S uint8[N])。"""
    arr = np.asarray(scale_out_arr, dtype=np.float64)
    m = np.empty(arr.shape, np.uint32)
    s = np.empty(arr.shape, np.uint8)
    for i, so in enumerate(arr.ravel()):
        mm, ss = pick_ms(so)
        m.ravel()[i] = mm
        s.ravel()[i] = ss
    return m, s


# ---------------------------------------------------------------- MAC / requant

def gemv_acc(w_q8, x_q8, b_int32):
    """GOLDEN_SPEC §2.1（bias_last）：y_int32 = SAT32(Σ_k W×x + b)。

    cumsum 等价于"每步 SAT32"的条件：任意部分和绝对值 <= K×2^14 < 2^31，
    SAT 在累加途中永不触发（断言保护）。bias 在 k 累加完后一次加入并 SAT32。
    返回 int64 数组（值域已在 int32 内）。
    """
    w = np.asarray(w_q8, dtype=np.int64)
    x = np.asarray(x_q8, dtype=np.int64)
    b = np.asarray(b_int32, dtype=np.int64)
    n, k = w.shape
    assert x.shape == (k,), f"x shape {x.shape} != ({k},)"
    assert b.shape == (n,), f"bias shape {b.shape} != ({n},)"
    assert k * (1 << 14) < (1 << 31), "K 过大，部分和 SAT 等价性不成立"
    acc = np.cumsum(w * x[None, :], axis=1)[:, -1] if k else np.zeros(n, np.int64)
    return np.clip(acc + b, I32_MIN, I32_MAX)


def requant_np(y_int32, m_u32, s_u8):
    """GOLDEN_SPEC §2.2 ROUND_SEL=1。M/S 可为标量或 [N] 数组。→ int8[N]"""
    y = np.asarray(y_int32, dtype=np.int64)
    m = np.asarray(m_u32, dtype=np.int64)
    s = np.asarray(s_u8, dtype=np.int64)
    assert np.all(s >= 1) and np.all(s <= 63), "S 必须在 1..63（协议禁止 S=0）"
    assert np.all(m >= 0) and np.all(m <= I32_MAX), "M 必须在 0..2^31-1"
    prod = y * m + (np.int64(1) << (s - 1))
    return np.clip(prod >> s, I8_MIN, I8_MAX).astype(np.int8)


def requant_biasfirst(y_int32, m_u32, s_u8):
    """bias_first 口径的 y_int32（供 corner 用例双口径比对，见 ame_ref.py docstring）。"""
    y = np.asarray(y_int32, dtype=np.int64)
    m = np.asarray(m_u32, dtype=np.int64)
    s = np.asarray(s_u8, dtype=np.int64)
    prod = y * m + (np.int64(1) << (s - 1))
    return np.clip(prod >> s, I8_MIN, I8_MAX).astype(np.int8)


def gemv_full(w_q8, x_q8, b_int32, sx, sw, ms_override=None):
    """一条龙：acc → (M,S) → y_q。返回 dict（生成 npz 用）。

    ms_override: None=按 §2.3 由 scale_out=sx*sw 生成；(M[N], S[N]) 强制配置。
    """
    y32 = gemv_acc(w_q8, x_q8, b_int32)
    if ms_override is None:
        scale_out = np.float64(sx) * np.asarray(sw, dtype=np.float64)
        m, s = pick_ms_vec(scale_out)
    else:
        m, s = ms_override
    yq = requant_np(y32, m, s)
    return {"y32": y32, "yq": yq, "m": m, "s": s}



def _hex_u32(v):
    return f"{int(v) & 0xFFFFFFFF:08X}"


def _hex_i8(v):
    return f"{int(v) & 0xFF:02X}"


def pack_words_linear(bytes_seq, pad_to_word=True):
    """4×int8 小端打包成 32-bit 字（§7）：word = b0|b1<<8|b2<<16|b3<<24。

    返回 (words list, pad_bytes)。尾部长度不足 4 时零填充（pad_to_word=False 则
    要求长度恰为 4 的倍数）。
    """
    bs = list(bytes_seq)
    pad = (-len(bs)) % 4
    if pad:
        if not pad_to_word:
            raise ValueError(f"长度 {len(bs)} 不是 4 的倍数")
        bs += [0] * pad
    words = []
    for i in range(0, len(bs), 4):
        b0, b1, b2, b3 = bs[i:i + 4]
        words.append((b0 & 0xFF) | (b1 & 0xFF) << 8 | (b2 & 0xFF) << 16 | (b3 & 0xFF) << 24)
    return words, pad


def tile16_linear(w_q8):
    """AME-TILE<16> 线性字节流（§3.2）：addr=((g*(K/16)+c)*16+i)*16+j。要求 N,K 被 16 整除。"""
    w = np.asarray(w_q8, dtype=np.int8)
    n, k = w.shape
    assert n % 16 == 0 and k % 16 == 0, f"tile16 需 N,K 被 16 整除: {n}x{k}"
    t = w.reshape(n // 16, 16, k // 16, 16).transpose(0, 2, 1, 3)  # [g,c,i,j]
    return t.reshape(-1).tolist()


def tile32_linear(w_q8):
    w = np.asarray(w_q8, dtype=np.int8)
    n, k = w.shape
    assert n % 32 == 0 and k % 32 == 0, f"tile32 需 N,K 被 32 整除: {n}x{k}"
    t = w.reshape(n // 32, 32, k // 32, 32).transpose(0, 2, 1, 3)
    return t.reshape(-1).tolist()


def write_mem(path, lines, header=None):
    with open(path, "w") as f:
        if header:
            f.write(f"// {header}\n")
        f.write("\n".join(lines) + "\n")


def mem_weight(path, w_q8, layout, path_name):
    """权重 ROM 镜像。layout: tile16|tile32|rowmajor（§3/§7）。返回 (文件行数, pad_bytes)。"""
    w = np.asarray(w_q8, dtype=np.int8)
    n, k = w.shape
    if layout == "tile16":
        stream = tile16_linear(w)
    elif layout == "tile32":
        stream = tile32_linear(w)
    elif layout == "rowmajor":
        stream = w.reshape(-1).tolist()
    else:
        raise ValueError(layout)
    words, pad = pack_words_linear(stream)
    write_mem(path, [_hex_u32(v) for v in words],
              header=f"layout={layout} path={path_name} N={n} K={k} words={len(words)}"
                     + (f" pad_bytes={pad}" if pad else ""))
    return len(words), pad


def mem_i8(path, arr, header=None):
    a = np.asarray(arr, dtype=np.int8).reshape(-1)
    write_mem(path, [_hex_i8(v) for v in a], header=header)


def mem_i32(path, arr, header=None):
    a = np.asarray(arr, dtype=np.int64).reshape(-1)
    assert np.all((a >= I32_MIN) & (a <= I32_MAX))
    write_mem(path, [_hex_u32(v) for v in a], header=header)


def mem_u32(path, arr, header=None):
    a = np.asarray(arr, dtype=np.int64).reshape(-1)
    assert np.all((a >= 0) & (a <= 0xFFFFFFFF))
    write_mem(path, [_hex_u32(v) for v in a], header=header)


def mem_u8(path, arr, header=None):
    a = np.asarray(arr, dtype=np.int64).reshape(-1)
    assert np.all((a >= 0) & (a <= 0xFF))
    write_mem(path, [f"{int(v):02X}" for v in a], header=header)


# ---------------------------------------------------------------- npz / manifest

class NpzWriter:
    """GOLDEN_SPEC §6 键值收集器 + 写盘。"""

    def __init__(self):
        self.d = {}

    def put(self, key, arr):
        assert key not in self.d, f"重复键 {key}"
        self.d[key] = arr

    def meta(self, case, config_json, **extra):
        self.put("meta.protocol_version", np.array(PROTOCOL_VERSION))
        self.put("meta.layout", np.array("rowmajor"))
        self.put("meta.case", np.array(case))
        self.put("meta.config_json", np.array(config_json))
        for k, v in extra.items():
            self.put(f"meta.{k}", np.array(v))

    def save(self, path):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        np.savez(path, **self.d)
        return path


def sha256_file(path):
    import hashlib
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def git_info(root):
    import subprocess
    try:
        head = subprocess.run(["git", "-C", root, "rev-parse", "HEAD"],
                              capture_output=True, text=True, check=True).stdout.strip()
        dirty = subprocess.run(["git", "-C", root, "status", "--porcelain"],
                               capture_output=True, text=True, check=True).stdout != ""
    except Exception as e:                                   # pragma: no cover
        head, dirty = f"<git unavailable: {e}>", True
    return head, dirty


def dump_manifest(path, manifest):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(manifest, f, indent=2, ensure_ascii=False, sort_keys=False)
