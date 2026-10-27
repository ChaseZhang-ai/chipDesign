#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""vrf_bound_gen.py — P3A 边界专项定向用例(任务书第 4 条)

覆盖:
  B1  K=1024 最长累加链 + 全 -128×全 -128(逐位期望由模型给)
  B2  requant 饱和边界:Y32 直写 y 值 × M/S/ROUND 网格,含恰在 ±127/±128
      溢出点的定向构造、M=0/M=2^32-1/S=1/S=63(st.q + YQ 总线读双路核对)
  B4  N/K 双余数(N=35×K=42 → 16+16+3 / 16+16+10)
  B5  单行 N=1、K<16 不满 tile(K=5,K=1)
  B6  非法字段全集(每条指令的非法字段,期望 resp_err=1/data=0)+ STATUS.ERR
      sticky + EVCLEAR 清除 + 非法风暴后合法指令仍工作
  B7  忙时写 Y32 → SLVERR 且丢弃(IDLE 后读回核对)
  B9  STATUS BUSY/DONE/READY 位 + EVCLEAR(W1C)行为
  B11 cfg 中途切换(KT 16→8)同一 Y 续累

模型复用 scripts/vrf_rand.py 的独立整数实现(第三方口径)。
期望内联在 ops 流(op 3/4/7),verify_full.sv 仿真内逐位判罚。

用法:
  python3 scripts/vrf_bound_gen.py [--out tb/ame/work/vrf/bound]
输出:
  <out>/bound_main.ops        全部边界用例(判罚门)
  <out>/repro_ldw_precfg.ops  ld.w 先于 cfg 的 ISA 偏差复现(预期 FAIL,仅取证)
"""
import argparse
import os
import random
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "scripts"))
from vrf_rand import (Model, Ops, sat32, requant, emit_bytes,      # noqa: E402
                      enc_cfg, enc_qcfg, enc_ldw, enc_ldx, enc_exe, enc_sync, enc_st,
                      WBUF_WIN, XBUF_WIN, Y32_WIN, YQ_WIN, STATUS_WIN)

I32MAX, I32MIN = (1 << 31) - 1, -(1 << 31)


def b1_long_acc(ow: Ops, mdl: Model, rng):
    n_eff, K, kt = 16, 1024, 16
    x = [-128] * K
    ow.cp(enc_qcfg(0), 1, (14 << 0) | (1 << 6))
    ow.cp(enc_qcfg(1), 1, (14 << 0) | (1 << 6))
    for ch in range(2, 16):
        m, s, r = rng.choice([(1, 14, 1), (2, 15, 0), (0x7FFF_FFFF, 31, 1)])
        ow.cp(enc_qcfg(ch), m, (s & 0x3F) | (r << 6))
        mdl.do_qcfg(ch, m, s, r)
    mdl.do_qcfg(0, 1, 14, 1)
    mdl.do_qcfg(1, 1, 14, 1)
    rows = [[-128] * K for _ in range(n_eff)]
    rows[1] = [127] * K
    for n in range(2, n_eff):
        rows[n] = [rng.randrange(-128, 127) for _ in range(K)]
    ow.cp(enc_cfg(n_eff, kt), 0, 0)
    mdl.do_cfg(n_eff, kt)
    for i in range(n_eff):
        ow.wr(Y32_WIN + 4 * i, 0)
        mdl.Y[i] = 0
    xfull = False
    for t in range(K // kt):
        k0 = t * kt
        region, tsel = t % 4, t % 2
        blob = b"".join(bytes(v & 0xFF for v in rows[ni][k0:k0 + kt])
                        for ni in range(n_eff))
        emit_bytes(ow, WBUF_WIN + (region * 256) % 1024, blob)
        for i, b in enumerate(blob):
            mdl.wbuf[((region * 256) + i) % 1024] = b
        if k0 <= 0x1FF:
            if not xfull:
                verb = bytes(v & 0xFF for v in x)
                emit_bytes(ow, XBUF_WIN, verb)
                for i, bb in enumerate(verb):
                    mdl.xbuf[i % 1024] = bb
                xfull = True
            ow.cp(*enc_ldx(k0, tsel))
            mdl.do_ldx(k0, tsel)
        else:
            sl = bytes(v & 0xFF for v in x[k0:k0 + kt])
            emit_bytes(ow, XBUF_WIN, sl)
            for i, bb in enumerate(sl):
                mdl.xbuf[i] = bb
            ow.cp(*enc_ldx(0, tsel))
            mdl.do_ldx(0, tsel)
        ow.cp(*enc_ldw(region, tsel))
        mdl.do_ldw(region, tsel)
        ow.cp(*enc_exe(tsel, is_f=(t == 0)))
        mdl.do_exe(tsel, is_f=(t == 0))
    ow.cp(enc_sync(), 0, 0)
    for i in range(n_eff):
        ow.dump_chk(0, i, i, mdl.Y[i])
        ow.dump_chk(1, i, i, mdl.st_q(i))


def b2_requant_grid(ow: Ops, mdl: Model, rng):
    ys = [I32MAX, I32MAX - 1, I32MIN, I32MIN + 1, 1 << 30, -(1 << 30),
          255, 254, 253, -255, -256, -257, -259, 127, -128, 1, -1, 0,
          0x12345678 - (1 << 31), 0x9ABCDEF0 - (1 << 31)]
    mss = [(0, 1, 0), (1, 1, 0), (1, 1, 1), (1, 63, 1), (2, 2, 1), (2, 2, 0),
           (0x7FFF_FFFF, 31, 1), (0xFFFF_FFFF, 1, 0), (0xFFFF_FFFF, 63, 1),
           (0x8000_0000, 32, 1), (3, 4, 1), (1, 2, 0), (0xFFFF_FFFF, 34, 1)]
    n = 0
    yq_words = {}
    for yi, (y, ms) in enumerate((y, ms) for y in ys for ms in mss):
        ch = n % 16
        y_val, (m, s, r) = y, ms
        ow.wr(Y32_WIN + 4 * ch, y_val & 0xFFFFFFFF)
        mdl.Y[ch] = sat32(y_val)
        ow.cp(enc_qcfg(ch), m, (s & 0x3F) | (r << 6))
        mdl.do_qcfg(ch, m, s, r)
        ow.cp_chk(*enc_st(1, ch), mdl.st_q(ch), 0)
        yq_words[ch] = mdl.st_q(ch)
        n += 1
        if n % 16 == 0:
            for w in range(4):
                q = [yq_words[4 * w + j] for j in range(4)]
                word = ((q[0] & 0xFF) | (q[1] & 0xFF) << 8 |
                        (q[2] & 0xFF) << 16 | (q[3] & 0xFF) << 24)
                ow.rd(YQ_WIN + 4 * w, word)
            yq_words = {}
            for ch2 in range(16):
                ow.wr(Y32_WIN + 4 * ch2, 0)
                mdl.Y[ch2] = 0
    for (y, m, s, r) in [(253, 1, 1, 1), (254, 1, 1, 1), (255, 1, 1, 1),
                         (509, 2, 2, 1), (510, 2, 2, 1), (511, 2, 2, 1),
                         (-255, 1, 1, 1), (-256, 1, 1, 1), (-257, 1, 1, 1),
                         (-255, 1, 1, 0), (-256, 1, 1, 0), (-257, 1, 1, 0)]:
        ch = 0
        ow.wr(Y32_WIN + 4 * ch, y & 0xFFFFFFFF)
        mdl.Y[ch] = sat32(y)
        ow.cp(enc_qcfg(ch), m, (s & 0x3F) | (r << 6))
        mdl.do_qcfg(ch, m, s, r)
        ow.cp_chk(*enc_st(1, ch), mdl.st_q(ch), 0)
        ow.rd(YQ_WIN, ((mdl.st_q(0) & 0xFF) | (mdl.st_q(1) & 0xFF) << 8 |
                       (mdl.st_q(2) & 0xFF) << 16 | (mdl.st_q(3) & 0xFF) << 24))


def gemv_directed(ow: Ops, mdl: Model, rng, n_total, K, bias_mode, tag_seed):
    x = [rng.randrange(-128, 128) for _ in range(K)]
    W = [[rng.randrange(-128, 128) for _ in range(K)] for _ in range(n_total)]
    bias = ([rng.randrange(-1 << 30, 1 << 30) for _ in range(n_total)]
            if bias_mode else [0] * n_total)
    xfull = False
    for s in range((n_total + 15) // 16):
        n0 = s * 16
        n_eff = min(16, n_total - n0)
        for i in range(n_eff):
            m = rng.choice([1, 2, 0x7FFF_FFFF, rng.randrange(0, 1 << 31)])
            sc = rng.choice([1, 3, 8, 31, 63])
            r = rng.randrange(2)
            ow.cp(enc_qcfg(i), m, (sc & 0x3F) | (r << 6))
            mdl.do_qcfg(i, m, sc, r)
        ts = (K + 15) // 16
        kts = [min(16, K - t * 16) for t in range(ts)]
        ow.cp(enc_cfg(n_eff, kts[0]), 0, 0)
        mdl.do_cfg(n_eff, kts[0])
        for i in range(n_eff):
            ow.wr(Y32_WIN + 4 * i, bias[n0 + i] & 0xFFFFFFFF)
            mdl.Y[i] = sat32(bias[n0 + i])
        for t in range(ts):
            k0 = t * 16
            kt_t = kts[t]
            if t > 0 and kt_t != kts[t - 1]:
                ow.cp(enc_cfg(n_eff, kt_t), 0, 0)
                mdl.do_cfg(n_eff, kt_t)
            region, tsel = t % 4, t % 2
            blob = b"".join(bytes(v & 0xFF for v in W[n0 + ni][k0:k0 + kt_t])
                            for ni in range(n_eff))
            emit_bytes(ow, WBUF_WIN + (region * 256) % 1024, blob)
            for i, b in enumerate(blob):
                mdl.wbuf[((region * 256) + i) % 1024] = b
            if k0 <= 0x1FF:
                if not xfull:
                    verb = bytes(v & 0xFF for v in x)
                    emit_bytes(ow, XBUF_WIN, verb)
                    for i, bb in enumerate(verb):
                        mdl.xbuf[i % 1024] = bb
                    xfull = True
                ow.cp(*enc_ldx(k0, tsel))
                mdl.do_ldx(k0, tsel)
            else:
                sl = bytes(v & 0xFF for v in x[k0:k0 + kt_t])
                emit_bytes(ow, XBUF_WIN, sl)
                for i, bb in enumerate(sl):
                    mdl.xbuf[i] = bb
                ow.cp(*enc_ldx(0, tsel))
                mdl.do_ldx(0, tsel)
            ow.cp(*enc_ldw(region, tsel))
            mdl.do_ldw(region, tsel)
            ow.cp(*enc_exe(tsel, is_f=False))
            mdl.do_exe(tsel, is_f=False)
        ow.cp(enc_sync(), 0, 0)
        for i in range(n_eff):
            ow.dump_chk(0, i, n0 + i, mdl.Y[i])
            ow.dump_chk(1, i, n0 + i, mdl.st_q(i))


def b6_illegal(ow: Ops, mdl: Model, rng):
    E = 1

    def bad(instr, rs1=0, rs2=0):
        ow.cp_chk(instr, rs1, rs2, 0, E)

    bad((((0b11 << 10) | (1 << 5) | 16) << 20) | 0x0B)
    bad(enc_cfg(0, 16))
    bad(enc_cfg(17, 16))
    bad(enc_cfg(16, 0))
    bad(enc_cfg(16, 17))
    bad(enc_qcfg(0), 100, 0)
    bad(enc_qcfg(16), 100, 8)
    bad(enc_qcfg(0), 100, 8 | (1 << 7))
    bad((0x02 << 25) | (0x01 << 12) | 0x0B, 100, 8)
    bad(enc_ldw(0, 0)[0], 1 << 3, 0)
    bad(enc_ldx(0, 0)[0], 1 << 10, 0)
    bad(enc_exe(0, True)[0], 1 << 1, 0)
    bad(enc_exe(0, False)[0], 1 << 5, 0)
    bad(enc_st(0, 0)[0], 1 << 5, 0)
    bad(enc_st(1, 0)[0], 1 << 5, 0)
    bad(enc_st(0, 16)[0], 16, 0)
    bad(enc_st(1, 16)[0], 16, 0)
    bad((0x01 << 25) | (0x07 << 12) | 0x0B)
    ow.cp(enc_sync(), 0, 0)
    ow.lines.append("7 00000080 00000080")
    ow.wr(STATUS_WIN + 8, 2)                   # EVCLEAR.ERR(W1C)
    ow.lines.append("7 00000080 00000000")
    ow.cp(enc_cfg(4, 8), 0, 0)
    mdl.do_cfg(4, 8)
    for ch in range(4):
        ow.cp(enc_qcfg(ch), 1, (8 & 0x3F) | (1 << 6))
        mdl.do_qcfg(ch, 1, 8, 1)
    blob = bytes([rng.randrange(-128, 128) & 0xFF for _ in range(4 * 8)])
    emit_bytes(ow, WBUF_WIN, blob)
    for i, b in enumerate(blob):
        mdl.wbuf[i] = b
    xb = bytes([rng.randrange(-128, 128) & 0xFF for _ in range(8)])
    emit_bytes(ow, XBUF_WIN, xb)
    for i, b in enumerate(xb):
        mdl.xbuf[i] = b
    ow.cp(*enc_ldx(0, 0))
    mdl.do_ldx(0, 0)
    ow.cp(*enc_ldw(0, 0))
    mdl.do_ldw(0, 0)
    ow.cp(*enc_exe(0, True))
    mdl.do_exe(0, True)
    ow.cp(enc_sync(), 0, 0)
    for i in range(4):
        ow.dump_chk(0, i, i, mdl.Y[i])
        ow.dump_chk(1, i, i, mdl.st_q(i))


def b7_busy_y32(ow: Ops, mdl: Model, rng):
    n_eff, kt = 16, 16
    W = [[rng.randrange(-128, 128) for _ in range(kt)] for _ in range(n_eff)]
    x = [rng.randrange(-128, 128) for _ in range(kt)]
    ow.cp(enc_cfg(n_eff, kt), 0, 0)
    mdl.do_cfg(n_eff, kt)
    for ch in range(n_eff):
        ow.cp(enc_qcfg(ch), 1, (8 & 0x3F) | (1 << 6))
        mdl.do_qcfg(ch, 1, 8, 1)
    blob = b"".join(bytes(v & 0xFF for v in W[ni]) for ni in range(n_eff))
    emit_bytes(ow, WBUF_WIN + 512, blob)
    for i, b in enumerate(blob):
        mdl.wbuf[512 + i] = b
    xb = bytes(v & 0xFF for v in x)
    emit_bytes(ow, XBUF_WIN + 32, xb)
    for i, b in enumerate(xb):
        mdl.xbuf[32 + i] = b
    ow.cp(*enc_ldx(32, 1))
    mdl.do_ldx(32, 1)
    ow.cp(*enc_ldw(2, 1))
    mdl.do_ldw(2, 1)
    ow.lines.append("7 00000008 00000000")
    ow.lines.append("6 00000003 00000014")
    ow.cp(enc_sync(), 0, 0)
    ow.cp(*enc_ldw(2, 1))
    mdl.do_ldw(2, 1)
    ow.cp(*enc_ldx(32, 1))
    mdl.do_ldx(32, 1)
    ow.cp(*enc_exe(1, True))
    mdl.do_exe(1, True)
    ow.lines.append("7 00000001 00000001")
    ow.wr(Y32_WIN + 4 * 3, 0xDEAD_BEEF, 0xF, 1)
    ow.lines.append("8 2000300C")
    ow.wr(WBUF_WIN + 768, 0xA5A5_5A5A, 0xF, 0)
    ow.cp(enc_sync(), 0, 0)
    for i in range(n_eff):
        ow.dump_chk(0, i, i, mdl.Y[i])
    ow.lines.append("7 00000003 00000002")
    ow.wr(STATUS_WIN + 8, 1)                      # EVCLEAR.DONE
    ow.lines.append("7 00000002 00000000")


def b11_cfg_switch(ow: Ops, mdl: Model, rng):
    n_eff, K = 8, 40                            # 16 + 16 + 8,KT 16→16→8
    W = [[rng.randrange(-128, 128) for _ in range(K)] for _ in range(n_eff)]
    x = [rng.randrange(-128, 128) for _ in range(K)]
    for ch in range(n_eff):
        ow.cp(enc_qcfg(ch), 3, (5 & 0x3F) | (1 << 6))
        mdl.do_qcfg(ch, 3, 5, 1)
    ow.cp(enc_cfg(n_eff, 16), 0, 0)
    mdl.do_cfg(n_eff, 16)
    emit_bytes(ow, XBUF_WIN, bytes(v & 0xFF for v in x))
    for i, b in enumerate(x):
        mdl.xbuf[i] = b & 0xFF
    for t in range(3):
        k0, kt_t = t * 16, min(16, K - t * 16)
        if t == 2:
            ow.cp(enc_cfg(n_eff, kt_t), 0, 0)
            mdl.do_cfg(n_eff, kt_t)
        region, tsel = t % 4, t % 2
        blob = b"".join(bytes(v & 0xFF for v in W[ni][k0:k0 + kt_t]) for ni in range(n_eff))
        emit_bytes(ow, WBUF_WIN + (region * 256) % 1024, blob)
        for i, b in enumerate(blob):
            mdl.wbuf[((region * 256) + i) % 1024] = b
        ow.cp(*enc_ldx(k0 if k0 <= 0x1FF else 0, tsel))
        mdl.do_ldx(k0 if k0 <= 0x1FF else 0, tsel)
        ow.cp(*enc_ldw(region, tsel))
        mdl.do_ldw(region, tsel)
        ow.cp(*enc_exe(tsel, is_f=(t == 0)))
        mdl.do_exe(tsel, is_f=(t == 0))
    ow.cp(enc_sync(), 0, 0)
    for i in range(n_eff):
        ow.dump_chk(0, i, i, mdl.Y[i])
        ow.dump_chk(1, i, i, mdl.st_q(i))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(ROOT, "tb", "ame", "work", "vrf", "bound"))
    ap.add_argument("--seed", type=int, default=42)
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    rng = random.Random(args.seed)
    mdl = Model()
    ow = Ops()
    ow.rd(STATUS_WIN, 0, 0)
    b1_long_acc(ow, mdl, rng)
    b2_requant_grid(ow, mdl, rng)
    gemv_directed(ow, mdl, rng, 35, 42, bias_mode=True, tag_seed="nk")
    gemv_directed(ow, mdl, rng, 1, 5, bias_mode=False, tag_seed="n1k5")
    gemv_directed(ow, mdl, rng, 1, 1, bias_mode=True, tag_seed="n1k1")   # B5 K=1
    b6_illegal(ow, mdl, rng)
    b7_busy_y32(ow, mdl, rng)
    b11_cfg_switch(ow, mdl, rng)
    with open(os.path.join(args.out, "bound_main.ops"), "w") as f:
        f.write(ow.text())

    ow2 = Ops()
    ow2.cp(*enc_ldw(0, 0))
    ow2.cp_chk(0x6 << 25 | 0x5 << 12 | 0x0B, 0, 0, 0, 0)
    with open(os.path.join(args.out, "repro_ldw_precfg.ops"), "w") as f:
        f.write(ow2.text())
    print(f"vrf_bound_gen: bound_main.ops({len(ow.lines)} 行)+ repro_ldw_precfg.ops → {args.out}")


if __name__ == "__main__":
    main()
