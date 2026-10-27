#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""ame_golden_tb.py — AME golden 用例生成器与 npz→ops 转换器(P2B)

两种模式:
  1) 默认:生成自造用例集(≥50 组,覆盖全零/全一/INT8 极值/SAT32/K·N·KT 余数/
     M·S 边界/背靠背 exe/cfg 切换/sync/错误字段/总线窗口非法访问),
     每组输出 <work>/<case>/ops.hex(六字段 hex 指令流,含逐条期望值)
     与 case.npz(GOLDEN_SPEC §6 键名约定,自造数据按格式落地)。
  2) --from-npz <path>:读取 GOLDEN_SPEC §6 约定键名的 npz(W2E 全量 golden
     或自造 npz),转成等价 ops 流;--verify-npz 时用 ame_ref 独立复核
     gold.y.int32。K>512 的 tile 用"x 重载到偏移 0"规避 ld.x 9 位偏移场
     限制(见 reports/issues/P2B.md)。

ops 流格式(供 tb/ame/tb_ame_golden.sv 逐条回放,全部大写 hex):
  0 <instr8> <rs1_8> <rs2_8> <expdata_8> <experr_d>   coproc 指令
  1 <addr8>  <data8> <wstrb_2> <experr_d> 0           总线写
  2 <addr8>  <expdata8> <experr_d> 0 0                总线读

期望值由 tb/ame/ame_ref.py(纯 python 整数,独立实现)计算;比对在 SV TB。
"""
import argparse
import os
import random
import sys

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                "..", "tb", "ame"))
import ame_ref  # noqa: E402

A_AME_BASE = 0x2000_1000
WBUF_WIN   = A_AME_BASE + 0x0000
XBUF_WIN   = A_AME_BASE + 0x0400
Y32_WIN    = A_AME_BASE + 0x0800
YQ_WIN     = A_AME_BASE + 0x0880

I32_MAX = 0x7FFF_FFFF
I32_MIN = -0x8000_0000


# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
def enc_cfg(n_eff: int, kt: int) -> int:
    imm = (n_eff & 0x1F) | ((kt & 0x3F) << 5)
    return (imm << 20) | 0x0B


def enc_qcfg(n: int, m: int, s: int, rnd: int) -> tuple:
    instr = (0x01 << 25) | (0x01 << 12) | ((n & 0x1F) << 7) | 0x0B
    return instr, (m & 0xFFFF_FFFF), ((s & 0x3F) | ((rnd & 1) << 6))


def enc_ldw(region: int, tsel: int) -> tuple:
    instr = (0x02 << 25) | (0x02 << 12) | 0x0B
    return instr, ((region & 3) | ((tsel & 1) << 2)), 0


def enc_ldx(off: int, xsel: int) -> tuple:
    instr = (0x03 << 25) | (0x03 << 12) | 0x0B
    return instr, ((off & 0x1FF) | ((xsel & 1) << 9)), 0


def enc_exe(tsel: int, is_exef: bool) -> tuple:
    f7 = 0x05 if is_exef else 0x04
    instr = (f7 << 25) | (0x04 << 12) | 0x0B
    return instr, (tsel & 1), 0


def enc_sty(i: int) -> tuple:
    instr = (0x06 << 25) | (0x05 << 12) | 0x0B
    return instr, (i & 0x1F), 0


def enc_stq(i: int) -> tuple:
    instr = (0x07 << 25) | (0x06 << 12) | 0x0B
    return instr, (i & 0x1F), 0


def enc_sync() -> int:
    return (0x08 << 25) | (0x07 << 12) | 0x0B


# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
class OpsWriter:
    def __init__(self):
        self.lines = []

    def cp(self, instr, rs1, rs2, exp_data=0, exp_err=0):
        self.lines.append(f"0 {instr:08X} {rs1:08X} {rs2:08X} "
                          f"{exp_data & 0xFFFF_FFFF:08X} {int(exp_err)}")

    def wr(self, addr, data, wstrb=0xF, exp_err=0):
        self.lines.append(f"1 {addr:08X} {data:08X} {wstrb:02X} {int(exp_err)} 0")

    def rd(self, addr, exp_data, exp_err=0):
        self.lines.append(f"2 {addr:08X} {exp_data & 0xFFFF_FFFF:08X} "
                          f"{int(exp_err)} 0 0")

    def text(self) -> str:
        return "\n".join(self.lines) + "\n"


def emit_bytes(ow: OpsWriter, byte_addr: int, data: bytes):
    """按 32-bit 字写一串字节(首尾字用 wstrb 覆盖,支持非对齐起点)。"""
    idx = 0
    while idx < len(data):
        cur = byte_addr + idx
        wa = cur & ~3
        lane = cur & 3
        n = min(4 - lane, len(data) - idx)
        word = int.from_bytes(data[idx:idx + n], "little")
        wstrb = ((1 << n) - 1) << lane
        ow.wr(wa, word, wstrb)
        idx += n


# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
class Geom:
    def __init__(self, m, n, wbuf_tiles=4):
        self.m = m
        self.n = n
        self.wbuf_tiles = wbuf_tiles
        self.tile_bytes = m * n
        self.wbuf_depth = wbuf_tiles * m * n
        self.xbuf_depth = 1024


def emit_section(ow, geom, W, x, M, S, rnd, bias,
                 kt=16, st_y_each_tile=True, tail_sync=True,
                 yq_read=True, y32_readback=False,
                 y32_exp=None, yq_exp=None):
    """生成一条 GEMV 的指令流并同步推进期望值。返回 (y_int32, y_q8)。

    y32_exp/yq_exp:外部 golden(npz 模式)覆盖最终期望值;None 用本模型自算。
    """
    n_eff = len(W)
    k_total = len(x)
    assert n_eff <= geom.n and k_total <= geom.xbuf_depth
    assert all(len(row) == k_total for row in W)
    ts = (k_total + kt - 1) // kt

    cur_cfg = None
    y_run = list(bias) if bias is not None else [0] * n_eff

    for ni in range(n_eff):
        ow.cp(*enc_qcfg(ni, M[ni], S[ni], rnd))

    if bias is not None:
        for i in range(n_eff):
            ow.wr(Y32_WIN + 4 * i, bias[i] & 0xFFFF_FFFF)

    for t in range(ts):
        k0, k1 = t * kt, min((t + 1) * kt, k_total)
        kt_t = k1 - k0
        if cur_cfg != (n_eff, kt_t):
            ow.cp(enc_cfg(n_eff, kt_t), 0, 0)
            cur_cfg = (n_eff, kt_t)

        region = t % geom.wbuf_tiles
        tsel = t % 2
        region_base = (region * geom.tile_bytes) % geom.wbuf_depth
        tile = b"".join(bytes(v & 0xFF for v in W[ni][k0:k1])
                        for ni in range(n_eff))
        emit_bytes(ow, WBUF_WIN + region_base, tile)

        if k0 <= 0x1FF:
            if t == 0:
                emit_bytes(ow, XBUF_WIN, bytes(v & 0xFF for v in x))
            ow.cp(*enc_ldx(k0, tsel))
        else:
            emit_bytes(ow, XBUF_WIN, bytes(v & 0xFF for v in x[k0:k1]))
            ow.cp(*enc_ldx(0, tsel))

        ow.cp(*enc_ldw(region, tsel))
        ow.cp(*enc_exe(tsel, is_exef=(t == 0 and bias is None)))

        for k in range(k0, k1):
            for ni in range(n_eff):
                y_run[ni] = ame_ref.sat32(y_run[ni] + int(W[ni][k]) * int(x[k]))
        if st_y_each_tile:
            for ni in range(n_eff):
                ow.cp(*enc_sty(ni), y_run[ni])

    if tail_sync:
        ow.cp(enc_sync(), 0, 0)

    if y32_exp is not None:
        y_run = [int(v) for v in y32_exp]
    yq = ([int(v) for v in yq_exp] if yq_exp is not None
          else ame_ref.requant_vec(y_run, M, S, rnd))
    for ni in range(n_eff):
        ow.cp(*enc_stq(ni), yq[ni])
    if yq_read:
        for w in range((n_eff + 3) // 4):
            q = [(yq[4 * w + j] & 0xFF) if 4 * w + j < n_eff else 0
                 for j in range(4)]
            ow.rd(YQ_WIN + 4 * w, q[0] | (q[1] << 8) | (q[2] << 16) | (q[3] << 24))
    if y32_readback:
        for ni in range(n_eff):
            ow.rd(Y32_WIN + 4 * ni, y_run[ni])
    return y_run, yq


def emit_error_case(ow, geom):
    """定向:非法字段/越界/总线窗口非法访问(期望值 = AME_ISA §1.2/§3 + 已上报解释)。"""
    err = 1
    ow.cp((0x220 << 20) | 0x0B | (0b11 << 30), 0, 0, 0, err)   # imm[11:10]≠00
    ow.cp(enc_cfg(0, 16), 0, 0, 0, err)                        # N_eff=0
    if geom.n < 32:
        ow.cp(enc_cfg(geom.n + 1, 16), 0, 0, 0, err)           # N_eff>AME_N
    ow.cp(enc_cfg(8, 0), 0, 0, 0, err)                         # KT=0
    if geom.m < 32:
        ow.cp(enc_cfg(8, geom.m + 1), 0, 0, 0, err)            # KT>AME_M
    ow.cp(enc_cfg(min(4, geom.n), min(8, geom.m)), 0, 0)
    instr, m, rs2 = enc_qcfg(0, 100, 0, 1)
    ow.cp(instr, m, rs2, 0, err)
    if geom.n < 32:
        instr, m, rs2 = enc_qcfg(geom.n, 100, 8, 1)
        ow.cp(instr, m, rs2, 0, err)
    instr, m, rs2 = enc_qcfg(0, 100, 8, 1)
    ow.cp(instr, m, rs2 | 0x180, 0, err)
    instr, m, rs2 = enc_qcfg(0, 0, 8, 1)
    ow.cp(instr, m, rs2)
    i, r1, r2 = enc_ldw(0, 0)
    ow.cp(i, r1 | (1 << 3), r2, 0, err)
    i, r1, r2 = enc_ldx(0, 0)
    ow.cp(i, r1 | (1 << 10), r2, 0, err)
    i, r1, r2 = enc_exe(0, True)
    ow.cp(i, r1 | (1 << 1), r2, 0, err)
    i, r1, r2 = enc_sty(0)
    ow.cp(i, r1 | (1 << 5), r2, 0, err)
    if geom.n < 32:
        i, r1, r2 = enc_sty(geom.n)
        ow.cp(i, r1, r2, 0, err)
        i, r1, r2 = enc_stq(geom.n)
        ow.cp(i, r1, r2, 0, err)
    kt = min(8, geom.m)
    ow.cp(enc_cfg(min(4, geom.n), kt), 0, 0)
    for ni in range(min(4, geom.n)):
        instr, m, rs2 = enc_qcfg(ni, 1, 8, 1)
        ow.cp(instr, m, rs2)
    tile = bytes(1 for _ in range(min(4, geom.n) * kt))
    emit_bytes(ow, WBUF_WIN, tile)
    emit_bytes(ow, XBUF_WIN, bytes(1 for _ in range(kt)))
    ow.cp(*enc_ldw(0, 0))
    ow.cp(*enc_ldx(0, 0))
    ow.cp(*enc_exe(0, True))
    ow.cp(enc_sync(), 0, 0)
    ow.wr(A_AME_BASE - 4, 0, 0xF, err)
    ow.rd(A_AME_BASE - 4, 0, err)
    ow.wr(WBUF_WIN + 1, 0xAABB_CCDD, 0xF, err)
    ow.rd(WBUF_WIN + 2, 0, err)
    ow.wr(YQ_WIN, 0, 0xF, err)
    ow.rd(Y32_WIN + 0x7C, 0)
    ow.wr(Y32_WIN + 0x7C, 0, 0xF, err)
    ow.rd(A_AME_BASE + 0x0A00, 0)
    ow.wr(A_AME_BASE + 0x0A00, 0, 0xF, err)
    ow.cp(enc_sync(), 0, 0)


def emit_y32_busy_case(ow, geom):
    """定向:BUSY 期间写 Y32 → SLVERR 且丢弃;IDLE 后写读一致。"""
    n_eff = min(4, geom.n)
    kt = min(8, geom.m)
    k_total = 3 * kt
    W = [[random.Random(900 + r).randrange(-128, 128) for _ in range(k_total)]
         for r in range(n_eff)]
    x = [random.Random(950).randrange(-128, 128) for _ in range(k_total)]

    ow.cp(enc_cfg(n_eff, kt), 0, 0)
    for ni in range(n_eff):
        ow.cp(*enc_qcfg(ni, 1, 8, 1))
    emit_bytes(ow, WBUF_WIN,
               b"".join(bytes(v & 0xFF for v in W[ni][0:kt])
                        for ni in range(n_eff)))
    emit_bytes(ow, XBUF_WIN, bytes(v & 0xFF for v in x[0:kt]))
    ow.cp(*enc_ldw(0, 0))
    ow.cp(*enc_ldx(0, 0))
    ow.cp(*enc_exe(0, True))
    ow.wr(Y32_WIN, 0xDEAD_BEEF, 0xF, 1)
    ow.wr(WBUF_WIN, 0x5A5A_A5A5, 0xF, 0)
    ow.cp(enc_sync(), 0, 0)
    bias = [ame_ref.sat32(0) for _ in range(n_eff)]
    for ni in range(n_eff):
        ow.wr(Y32_WIN + 4 * ni, (1000 + ni) & 0xFFFF_FFFF)
        bias[ni] = 1000 + ni
    ow.cp(*enc_ldw(0, 0))
    ow.cp(*enc_ldx(0, 0))
    ow.cp(*enc_exe(0, False))
    W[0][0], W[0][1], W[0][2], W[0][3] = -91, -91, 90, 90
    y_run = list(bias)
    for k in range(kt):
        for ni in range(n_eff):
            y_run[ni] = ame_ref.sat32(y_run[ni] + int(W[ni][k]) * int(x[k]))
    ow.cp(enc_sync(), 0, 0)
    for ni in range(n_eff):
        ow.cp(*enc_sty(ni), y_run[ni])


# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
class Case:
    def __init__(self, name, sections, kt=16, opts=None):
        self.name = name
        self.sections = sections   # list of dict(W, x, M, S, rnd, bias)
        self.kt = kt
        self.opts = opts or {}


def _rand_case(name, seed, geom, kt=16):
    rng = random.Random(seed)
    n_eff = rng.choice([1, 2, 3, 5, 7, min(8, geom.n), geom.n])
    k_total = rng.choice([1, 5, 15, 16, 17, 31, 33, 47, 50, 63, 64, 127, 250])
    k_total = min(k_total, geom.xbuf_depth)
    W = [[rng.randrange(-128, 128) for _ in range(k_total)] for _ in range(n_eff)]
    x = [rng.randrange(-128, 128) for _ in range(k_total)]
    M = [rng.choice([0, 1, 2, 0x7FFF_FFFF, 0xFFFF_FFFF,
                     rng.randrange(0, 1 << 31)]) for _ in range(n_eff)]
    S = [rng.choice([1, 2, 3, 8, 16, 31, 63]) for _ in range(n_eff)]
    rnd = rng.randrange(2)
    sec = dict(W=W, x=x, M=M, S=S, rnd=rnd, bias=None)
    return Case(name, [sec], kt=kt)


def _rand_sec(k_total, n_eff, seed):
    return dict(
        W=[[random.Random(seed * 100 + r).randrange(-128, 128)
            for _ in range(k_total)] for r in range(n_eff)],
        x=[random.Random(seed * 100 + 55).randrange(-128, 128)
           for _ in range(k_total)],
        M=[random.Random(seed * 100 + 66).randrange(0, 1 << 31)
           for _ in range(n_eff)],
        S=[random.Random(seed * 100 + 77).choice([1, 4, 8, 15, 31, 63])
           for _ in range(n_eff)],
        rnd=random.Random(seed * 100 + 88).randrange(2),
        bias=None)


def build_cases(geom):
    cases = []
    for i in range(30):
        cases.append(_rand_case(f"rand_{i:02d}", 1000 + i, geom))
    N = geom.n

    def full(v, n, k):
        return [[v] * k for _ in range(n)]

    cases.append(Case("zeros", [dict(W=full(0, N, 32), x=[0] * 32,
                                     M=[1] * N, S=[8] * N, rnd=1, bias=None)]))
    cases.append(Case("ones", [dict(W=full(1, N, 32), x=[1] * 32,
                                    M=[1] * N, S=[1] * N, rnd=0, bias=None)]))
    cases.append(Case("ones_kt4", [dict(W=full(1, N, 22), x=[1] * 22,
                                        M=[4] * N, S=[2] * N, rnd=1, bias=None)],
                             kt=4))
    cases.append(Case("ext_min", [dict(W=full(-128, N, 64), x=[-128] * 64,
                                       M=[1] * N, S=[14] * N, rnd=1, bias=None)]))
    cases.append(Case("ext_max", [dict(W=full(127, N, 512), x=[127] * 512,
                                       M=[1] * N, S=[23] * N, rnd=1, bias=None)]))
    bias = [I32_MAX, I32_MIN, 0, -1] + [0] * (N - 4)
    Wsat = [[1] * 32, [-1] * 32, [1] * 16 + [-1] * 16, [-1] * 16 + [1] * 16] \
        + [[0] * 32 for _ in range(N - 4)]
    cases.append(Case("sat32", [dict(W=Wsat, x=[1] * 32, M=[1] * N, S=[8] * N,
                                     rnd=0, bias=bias)],
                      opts=dict(y32_readback=True)))
    cases.append(Case("k_rem_250", [dict(
        W=[[random.Random(7 + r).randrange(-128, 128) for _ in range(250)]
           for r in range(4)],
        x=[random.Random(99).randrange(-128, 128) for _ in range(250)],
        M=[3] * 4, S=[4] * 4, rnd=1, bias=None)]))
    cases.append(Case("k_rem_63", [_rand_sec(63, N, seed=5)]))
    cases.append(Case("k_rem_17", [_rand_sec(17, N, seed=6)]))
    cases.append(Case("n_rem_5", [_rand_sec(64, 5, seed=7)]))
    cases.append(Case("n_rem_1", [_rand_sec(32, 1, seed=8)]))
    n_e = min(8, geom.n)
    cases.append(Case("kt4_rem", [dict(
        W=[[random.Random(20 + r).randrange(-128, 128) for _ in range(22)]
           for r in range(n_e)],
        x=[random.Random(21).randrange(-128, 128) for _ in range(22)],
        M=[0x4000_0000] * n_e, S=[34] * n_e, rnd=1, bias=None)], kt=4))
    M_edge = [0xFFFF_FFFF, 1, 0, 0x7FFF_FFFF, 2, 0xFFFF_FFFF, 1, 0][:n_e]
    S_edge = [1, 1, 63, 63, 2, 3, 8, 16][:n_e]
    cases.append(Case("ms_edge", [dict(
        W=[[random.Random(30 + r).randrange(-4, 5) for _ in range(16)]
           for r in range(n_e)],
        x=[random.Random(31).randrange(-4, 5) for _ in range(16)],
        M=M_edge, S=S_edge, rnd=1, bias=None)]))
    cases.append(Case("round_mix", [dict(
        W=[[random.Random(40 + r).randrange(-16, 17) for _ in range(32)]
           for r in range(n_e)],
        x=[random.Random(41).randrange(-16, 17) for _ in range(32)],
        M=[7] * n_e, S=[4] * n_e, rnd=1, bias=None),
        dict(W=[[random.Random(40 + r).randrange(-16, 17) for _ in range(32)]
                for r in range(n_e)],
             x=[random.Random(41).randrange(-16, 17) for _ in range(32)],
             M=[7] * n_e, S=[4] * n_e, rnd=0, bias=None)]))
    cases.append(Case("b2b_k128", [_rand_sec(128, N, seed=50)]))
    cases.append(Case("wrap_k256", [_rand_sec(256, N, seed=51)]))
    cases.append(Case("cfg_switch", [_rand_sec(40, N, seed=60)], kt=16))
    cases.append(Case("sync_mix", [_rand_sec(96, N, seed=61)]))
    cases.append(Case("y32_bias", [dict(
        W=[_rand_sec(64, 1, seed=70 + r)["W"][0] for r in range(N)],
        x=[random.Random(80 * 13 + i).randrange(-128, 128) for i in range(64)],
        M=[0x0AAA_AAAA] * N, S=[16] * N, rnd=1,
        bias=[random.Random(90 + r).randrange(-1 << 20, 1 << 20)
              for r in range(N)])],
        opts=dict(y32_readback=True)))
    cases.append(Case("errors", []))
    cases.append(Case("y32_busy", []))
    cases = [Case(c.name, c.sections, kt=min(c.kt, geom.m), opts=c.opts)
             for c in cases]
    return cases


# ---------------------------------------------------------------------------
# npz(GOLDEN_SPEC §6)→ ops
# ---------------------------------------------------------------------------
def emit_npz_case(ow, geom, z, max_sections, verify):
    items = ame_ref.npz_gemv_items(z)
    g_no = 0
    for step, g, path, xin, y32, yq8 in items:
        Wm = z[f"w.{path}.q8"].astype(int)
        n_total = int(Wm.shape[0])
        rqm = z[f"rq.{path}.m"].astype(int)
        rqs = z[f"rq.{path}.s"].astype(int)
        x = xin.astype(int).tolist()
        for s0 in range(0, n_total, geom.n):
            if g_no >= max_sections:
                print(f"NPZ-SECTIONS-CAP {max_sections}(余下省略)")
                return
            n_eff = min(geom.n, n_total - s0)
            W = Wm[s0:s0 + n_eff].tolist()
            M = rqm[s0:s0 + n_eff].tolist()
            S = rqs[s0:s0 + n_eff].tolist()
            y32_npz = y32[s0:s0 + n_eff].astype(int).tolist()
            yq_npz = (yq8[s0:s0 + n_eff].astype(int).tolist()
                      if yq8 is not None else None)
            if verify:
                exp = ame_ref.gemv(W, x, bias=None, bias_first=False)
                if exp != y32_npz:
                    print(f"VERIFY-NPZ-MISMATCH step={step} gemv{g:02d} "
                          f"slice={s0} 前4: npz={y32_npz[:4]} ref={exp[:4]}")
            emit_section(ow, geom, W, x, M, S, 1, None,
                         st_y_each_tile=False, tail_sync=True,
                         yq_read=True, y32_exp=y32_npz, yq_exp=yq_npz)
            g_no += 1


# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
def write_case_npz(path, case: Case):
    arrays = {
        "meta.protocol_version": np.array(ame_ref.PROTOCOL_VERSION),
        "meta.layout": np.array("rowmajor"),
        "meta.case": np.array(case.name),
    }
    for si, sec in enumerate(case.sections):
        p = f"sec{si}"
        arrays[f"w.{p}.q8"] = np.asarray(sec["W"], dtype=np.int8)
        arrays[f"rq.{p}.m"] = np.asarray(sec["M"], dtype=np.uint32)
        arrays[f"rq.{p}.s"] = np.asarray(sec["S"], dtype=np.uint8)
        arrays[f"act.0.{p}.xin.q8"] = np.asarray(sec["x"], dtype=np.int8)
        y = ame_ref.gemv(sec["W"], sec["x"], bias=sec["bias"], bias_first=False)
        arrays[f"gold.0.gemv{si + 1:02d}.xin.q8"] = np.asarray(sec["x"],
                                                               dtype=np.int8)
        arrays[f"gold.0.gemv{si + 1:02d}.y.int32"] = np.asarray(y, dtype=np.int32)
        yq = ame_ref.requant_vec(y, sec["M"], sec["S"], sec["rnd"])
        arrays[f"gold.0.gemv{si + 1:02d}.y.q8"] = np.asarray(yq, dtype=np.int8)
    np.savez(path, **arrays)


# ---------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--work", default="tb/ame/work")
    ap.add_argument("--m", type=int, default=16)
    ap.add_argument("--n", type=int, default=16)
    ap.add_argument("--wbuf-tiles", type=int, default=4)
    ap.add_argument("--max-sections", type=int, default=8)
    ap.add_argument("--from-npz", default=None,
                    help="读取 GOLDEN_SPEC §6 npz,生成单个 ops 流")
    ap.add_argument("--verify-npz", action="store_true",
                    help="--from-npz 时用 ame_ref 独立复核 gold.y.int32")
    ap.add_argument("--out", default=None, help="--from-npz 的 ops 输出路径")
    args = ap.parse_args()

    geom = Geom(args.m, args.n, args.wbuf_tiles)

    if args.from_npz:
        z = ame_ref.load_golden_npz(args.from_npz)
        ow = OpsWriter()
        emit_npz_case(ow, geom, z, args.max_sections, args.verify_npz)
        out = args.out or "npz_case.ops"
        os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
        with open(out, "w") as f:
            f.write(ow.text())
        print(f"NPZ-OPS {out} ops={len(ow.lines)}")
        return

    root = os.path.join(args.work, f"m{args.m}n{args.n}")
    os.makedirs(root, exist_ok=True)
    cases = build_cases(geom)
    total_ops = 0
    for case in cases:
        ow = OpsWriter()
        cdir = os.path.join(root, case.name)
        os.makedirs(cdir, exist_ok=True)
        if case.name == "errors":
            emit_error_case(ow, geom)
        elif case.name == "y32_busy":
            emit_y32_busy_case(ow, geom)
        else:
            for sec in case.sections:
                emit_section(ow, geom, sec["W"], sec["x"], sec["M"], sec["S"],
                             sec["rnd"], sec["bias"], kt=case.kt,
                             st_y_each_tile=case.opts.get("st_y_each_tile", True),
                             tail_sync=case.opts.get("tail_sync", True),
                             yq_read=case.opts.get("yq_read", True),
                             y32_readback=case.opts.get("y32_readback", False))
        with open(os.path.join(cdir, "ops.hex"), "w") as f:
            f.write(ow.text())
        if case.sections:
            write_case_npz(os.path.join(cdir, "case.npz"), case)
        total_ops += len(ow.lines)
        print(f"CASE {case.name:14s} ops={len(ow.lines)}")
    print(f"TOTAL cases={len(cases)} ops={total_ops}")


if __name__ == "__main__":
    main()
