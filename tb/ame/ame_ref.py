#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""ame_ref.py — AME 行为模型(P2B 单元验证,严格按 docs/GOLDEN_SPEC.md §2)

纯 python 整数实现(与 RTL/生成器独立,满足 GOLDEN_SPEC §9 "各自独立实现"),
位精确语义:

  累加   y_int32[n] = SAT32(Σ_k W_int8[n][k] × x_int8[k] + b_int32[n])
         每次部分和累加后立刻 SAT32;k 升序(分块时块内 k 升序、块号升序,
         与全局 k 升序逐位一致)。
  requant y_q = clip(( s64(y) × u64(M)  (+ 2^(S-1) if ROUND_SEL) ) >>> S, -128, 127)
         M=uint32、S=1..63;>>> 为算术右移(向下取整);中间量不饱和。

关于 bias 的实现路径差异(见 docs/AME_NOTES.md §余数与位精确):
  * GOLDEN 定义:bias 在全部 k 累加完成之后一次加入(bias_last=True,生成
    npz golden 用此口径)。
  * RTL 路径:bias 经 Y32 窗口预置后用 EXE 累加,即 bias 先行、每步 SAT32。
    两者仅在累加中途触发 SAT32 时可能不同;ame_ref 同时提供两种口径,
    golden 对拍 RTL 时用 bias_first(与本 RTL 一致),npz golden 用 bias_last。
"""

PROTOCOL_VERSION = "1.0"

U32 = (1 << 32) - 1
M64 = (1 << 64) - 1
I32_MIN, I32_MAX = -(1 << 31), (1 << 31) - 1


def sat32(v: int) -> int:
    """GOLDEN_SPEC §2.1 SAT32。"""
    return max(I32_MIN, min(I32_MAX, int(v)))


def to_s64(v: int) -> int:
    """取 int64 低 64 位并按二补码解释。"""
    v &= M64
    return v - (1 << 64) if (v >> 63) & 1 else v


def requant(y: int, m: int, s: int, round_sel: bool) -> int:
    """GOLDEN_SPEC §2.2 定点 requant(m uint32,s 1..63)。

    s=0 为协议禁止(qcfg 拒绝);此处与 RTL 一致地钳为移 0、无舍入偏置,
    仅用于协议域外的非法使用。
    """
    prod = to_s64(int(y) * int(m))
    sh = int(s) if s >= 1 else 0
    if round_sel and s >= 1:
        prod = to_s64(prod + (1 << (s - 1)))
    v = prod >> sh
    return max(-128, min(127, v))


def requant_vec(y_list, m_list, s_list, round_sel) -> list:
    return [requant(y, m, s, round_sel)
            for y, m, s in zip(y_list, m_list, s_list)]


def gemv(W, x, bias=None, bias_first: bool = True):
    """单条 GEMV:W 为 [N][K] 嵌套列表(int8 值),x 为 [K]。

    bias_first=True: 预置路径(RTL Y32 + EXE)——初始累加器 = bias,每步 SAT32。
    bias_first=False: GOLDEN 定义 —— 全 k 累加完后一次 SAT32(y + bias)。
    bias=None 等价 [0]*N,两种口径逐位一致。
    返回 y_int32[N](int python 整数)。
    """
    n = len(W)
    k_total = len(x)
    for row in W:
        assert len(row) == k_total, "W 行宽不一致"
    y = list(bias) if (bias is not None and bias_first) else [0] * n
    for k in range(k_total):
        xk = int(x[k])
        for ni in range(n):
            y[ni] = sat32(y[ni] + int(W[ni][k]) * xk)
    if bias is not None and not bias_first:
        for ni in range(n):
            y[ni] = sat32(y[ni] + int(bias[ni]))
    return y


# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
def load_golden_npz(path):
    """读取 GOLDEN_SPEC §6 约定键名的 case.npz,返回原始字典。

    使用方按需取:
      meta.protocol_version / meta.layout / meta.case
      w.<path>.q8 [N,K], w.<path>.sw [N]
      rq.<path>.m uint32[N] / rq.<path>.s uint8[N]
      gold.<step>.gemv<G>.xin.q8 / .y.int32 / .y.q8
    """
    import numpy as np
    z = np.load(path, allow_pickle=False)
    out = {k: z[k] for k in z.files}
    pv = str(out.get("meta.protocol_version", ""))
    if pv and pv != PROTOCOL_VERSION:
        raise ValueError(f"protocol_version {pv} != {PROTOCOL_VERSION}")
    return out


def npz_gemv_items(z):
    """从 npz 字典枚举 (step, g, path, xin, y32, yq8) 五元组。

    path 匹配规则:w.<path>.q8 形状 [N,K] 且 K == len(xin) 的唯一项。
    """
    gold_keys = [k for k in z if k.startswith("gold.") and k.endswith(".y.int32")]
    items = []
    for yk in sorted(gold_keys):
        stem = yk[: -len(".y.int32")]           # gold.<step>.gemv<G>
        _, step, gemv_g = stem.split(".")
        g = int(gemv_g.replace("gemv", ""))
        xin = z[stem + ".xin.q8"]
        y32 = z[yk]
        yq8 = z.get(stem + ".y.q8")
        k_total = int(xin.shape[0])
        cands = [p[len("w."):-len(".q8")] for p in z
                 if p.startswith("w.") and p.endswith(".q8")
                 and tuple(z[p].shape)[1] == k_total]
        if len(cands) != 1:
            raise KeyError(f"{yk}: K={k_total} 匹配到 {len(cands)} 个权重矩阵")
        items.append((int(step), g, cands[0], xin, y32, yq8))
    return items


if __name__ == "__main__":
    assert sat32(2**31) == I32_MAX and sat32(-2**31 - 1) == I32_MIN
    assert requant(0, 1, 1, True) == 0
    assert requant(1 << 30, 1, 30, True) == 1        # (2^30+2^29)>>30 = 1
    assert requant(3, 2, 2, False) == 1              # 6>>2 = 1
    assert requant(3, 2, 2, True) == 2               # (6+2)>>2 = 2
    assert requant(-3, 2, 2, False) == -2
    assert requant(-3, 2, 2, True) == -1             # (-6+2)>>2 = -1
    assert requant(-1, 0xFFFFFFFF, 1, False) == -128
    assert requant(0x7FFFFFFF, 0xFFFFFFFF, 1, False) == 127
    assert requant(-1 << 20, 0xFFFFFFFF, 1, True) == -128
    assert requant(5, 3, 1, True) == 8
    assert gemv([[1, 2], [3, 4]], [5, -6]) == [1*5 + 2*(-6), 3*5 + 4*(-6)]
    print("ame_ref selftest OK")
