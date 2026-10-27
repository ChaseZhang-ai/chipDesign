#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""vrf_full_gen.py — P3A 全量 74 组 golden 对拍 ops 生成器(第三方独立实现)

读 models/golden/manifest.json + 各 case.npz,按真实指令序列(AME_ISA §2/§3/
§4.1)为每条 GEMV 生成一段 tb/ame/verify_full.sv 可回放的 ops 流:

  qcfg×N_eff → cfg → Y32 bias 预置(b.int32,AME_ISA §4.1 bias 进入方式)
  → [写 WBUF region → ld.x → ld.w → exe]×TS → sync → st.y/st.q 读回 dump

终判不在流内:st.y/st.q 结果由 TB dump 成 GOLD 行,交 golden_reader.py
compare 对照 npz。K>512 时按 P2B 已上报的规避方式把该 tile 的 x 片重载到
XBUF 偏移 0(ld.x 偏移场仅 9 位,issues/P2B.md #5)。

本脚本只生成指令流,不产生数值期望——期望完全来自 npz golden,经
golden_reader.py 终判(第三方独立性:判据与生成器分离)。

用法:
  python3 scripts/vrf_full_gen.py [--out tb/ame/work/vrf/full] [--sample 15]
输出:
  <out>/<case>__<gid>.ops   每组一个文件
  <out>/manifest.tsv        组清单(case/gid/N/K/ms_rule/iverilog 抽样标记)
"""
import argparse
import json
import os

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GOLDEN = os.path.join(ROOT, "models", "golden")

A_AME_BASE = 0x2000_1000
WBUF_WIN = A_AME_BASE + 0x0000
XBUF_WIN = A_AME_BASE + 0x0400
Y32_WIN = A_AME_BASE + 0x0800
STATUS_WIN = A_AME_BASE + 0x08C0

LDX_OFF_MAX = 0x1FF
KT = 16


def enc_cfg(n_eff, kt):
    imm = (n_eff & 0x1F) | ((kt & 0x3F) << 5)
    return (imm << 20) | 0x0B


def enc_qcfg(n, m, s, rnd):
    instr = (0x01 << 25) | (0x01 << 12) | ((n & 0x1F) << 7) | 0x0B
    return instr, (m & 0xFFFF_FFFF), ((s & 0x3F) | ((rnd & 1) << 6))


def enc_ldw(region, tsel):
    instr = (0x02 << 25) | (0x02 << 12) | 0x0B
    return instr, ((region & 3) | ((tsel & 1) << 2)), 0


def enc_ldx(off, xsel):
    instr = (0x03 << 25) | (0x03 << 12) | 0x0B
    return instr, ((off & 0x1FF) | ((xsel & 1) << 9)), 0


def enc_exe(tsel):
    instr = (0x04 << 25) | (0x04 << 12) | 0x0B
    return instr, (tsel & 1), 0


def enc_sync():
    return (0x08 << 25) | (0x07 << 12) | 0x0B


class Ops:
    def __init__(self):
        self.lines = []

    def cp(self, instr, rs1, rs2):
        self.lines.append(f"0 {instr:08X} {rs1 & 0xFFFF_FFFF:08X} {rs2 & 0xFFFF_FFFF:08X}")

    def wr(self, addr, data, wstrb=0xF, exp_err=0):
        self.lines.append(f"1 {addr:08X} {data & 0xFFFF_FFFF:08X} {wstrb:02X} {int(exp_err)}")

    def rd(self, addr, exp_data, exp_err=0):
        self.lines.append(f"2 {addr:08X} {exp_data & 0xFFFF_FFFF:08X} {int(exp_err)}")

    def dump(self, f, li, gn, exp=None):
        if exp is None:
            self.lines.append(f"4 {int(f)} {li & 0xFFFF_FFFF:08X} {gn & 0xFFFF_FFFF:08X}")
        else:
            self.lines.append(f"4 {int(f)} {li & 0xFFFF_FFFF:08X} {gn & 0xFFFF_FFFF:08X} "
                              f"{int(exp) & 0xFFFF_FFFF:08X}")

    def sync(self):
        self.cp(enc_sync(), 0, 0)

    def text(self):
        return "\n".join(self.lines) + "\n"


def emit_bytes(ow: Ops, byte_addr: int, data: bytes):
    """字节流按 32-bit 小端字写(首尾字 wstrb 覆盖,支持任意起点/长度)。"""
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


def emit_gemv(ow: Ops, W, x, b, M, S, rnd=1, kt=KT):
    """一条完整 GEMV:N = W.shape[0](任意),K = len(x)(≤1024)。

    逐 N 片(16 路)展开;每片:qcfg 装本片通道 M/S → cfg → Y32 预置本片
    bias → 逐 K 片 [写 WBUF region → ld.x → ld.w → exe] → sync → st.y/st.q
    dump(行号 = 全局通道号)。
    """
    N, K = W.shape
    assert K <= 1024, "XBUF_DEPTH=1024"
    ns = (N + 15) // 16
    x_bytes = bytes(v & 0xFF for v in x)
    for s in range(ns):
        n0 = s * 16
        n_eff = min(16, N - n0)
        for i in range(n_eff):
            ow.cp(*enc_qcfg(i, int(M[n0 + i]), int(S[n0 + i]), rnd))
        ts = (K + kt - 1) // kt
        kts = [min(kt, K - t * kt) for t in range(ts)]
        ow.cp(enc_cfg(n_eff, kts[0]), 0, 0)
        for i in range(n_eff):
            ow.wr(Y32_WIN + 4 * i, int(b[n0 + i]) & 0xFFFF_FFFF)
        if s == 0 or K > 0x200:
            emit_bytes(ow, XBUF_WIN, x_bytes)
        for t in range(ts):
            k0 = t * kt
            kt_t = kts[t]
            if t > 0 and kt_t != kts[t - 1]:
                ow.cp(enc_cfg(n_eff, kt_t), 0, 0)
            region = t % 4
            tsel = t % 2
            region_base = (region * 256) % 1024
            tile = b"".join(W[n0 + ni, k0:k0 + kt_t].astype(np.uint8).tobytes()
                            for ni in range(n_eff))
            emit_bytes(ow, WBUF_WIN + region_base, tile)
            if k0 <= LDX_OFF_MAX:
                ow.cp(*enc_ldx(k0, tsel))
            else:
                emit_bytes(ow, XBUF_WIN, x_bytes[k0:k0 + kt_t])
                ow.cp(*enc_ldx(0, tsel))
            ow.cp(*enc_ldw(region, tsel))
            ow.cp(*enc_exe(tsel))
        ow.sync()
        for i in range(n_eff):
            ow.dump(0, i, n0 + i)
        for i in range(n_eff):
            ow.dump(1, i, n0 + i)


def pick_sample(entries, n):
    """iverilog 抽样:定向必抽(角组/极形状)+ 每 case 保底 + 大 MAC 补齐。"""
    sample = set()
    must = [("corner", "G01"), ("corner", "G02"), ("rand20", "G13"),
            ("rand20", "G19"), ("rand20", "G20"), ("unit_gemv", "G12"),
            ("e2e_step_T8", "G12")]
    for c, g in must:
        if any(e[0] == c and e[1] == g for e in entries):
            sample.add((c, g))
    for c in sorted({e[0] for e in entries}):
        first = min(e[1] for e in entries if e[0] == c)
        sample.add((c, first))
    rest = sorted((e for e in entries if (e[0], e[1]) not in sample),
                  key=lambda e: -(e[2] * e[3]))
    for e in rest:
        if len(sample) >= n:
            break
        sample.add((e[0], e[1]))
    return sample


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=GOLDEN)
    ap.add_argument("--out", default=os.path.join(ROOT, "tb", "ame", "work", "vrf", "full"))
    ap.add_argument("--sample", type=int, default=15, help="iverilog 抽样组数")
    args = ap.parse_args()

    with open(os.path.join(args.root, "manifest.json")) as f:
        man = json.load(f)

    os.makedirs(args.out, exist_ok=True)
    all_entries = []  # (case, gid, N, K, ms_rule)
    for case, info in man["cases"].items():
        z = np.load(os.path.join(args.root, info["npz"]))
        for e in info["gemvs"]:
            gid = e["id"]
            k_ = e["keys"]
            W = z[k_["w"]].astype(int)
            x = z[k_["xin"]].astype(int)
            b = z[k_["b"]].astype(int)
            M = z[k_["rq_m"]].astype(int)
            S = z[k_["rq_s"]].astype(int)
            N, K = W.shape
            assert len(x) == K, f"{case}/{gid}: x 长度 != K"
            assert len(b) == N and len(M) == N and len(S) == N
            ow = Ops()
            ow.rd(STATUS_WIN, 0, 0)
            emit_gemv(ow, W, x, b, M, S, rnd=1, kt=KT)
            with open(os.path.join(args.out, f"{case}__{gid}.ops"), "w") as f:
                f.write(ow.text())
            all_entries.append((case, gid, N, K, e.get("ms_rule", "")))

    sample = pick_sample(all_entries, args.sample)
    with open(os.path.join(args.out, "manifest.tsv"), "w") as f:
        f.write("case\tgid\tN\tK\tms_rule\tiverilog_sample\n")
        for (case, gid, N, K, rule) in all_entries:
            f.write(f"{case}\t{gid}\t{N}\t{K}\t{rule}\t{int((case, gid) in sample)}\n")
    print(f"vrf_full_gen: {len(all_entries)} 组 ops → {args.out}(iverilog 抽样 {len(sample)})")


if __name__ == "__main__":
    main()
