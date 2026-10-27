#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""vrfb_golden.py — P3B 联测 golden 生成器(CPU+AME 指令级联测)。

为每个微内核配置生成 TB 运行所需四件套(输出到 tb/integ/work/cfg/<name>/):
  xmem.hex     XMEM 行为模型预载镜像(word/行,8 hex,小端打包,@wordaddr 稀疏)
  kv.hex       KV 行为模型预载镜像(同格式,KV 字节空间内 word 索引)
  exp_uart.hex 期望 UART 字节流(1 字节/行,2 hex;TB $readmemh 逐字节比对)
  exp_scr.hex  期望 XMEM SCRATCH 区终态(同 xmem 格式;回归脚本与 dump 逐字节比对)
  exp_kv.hex   期望 KV 阵列 rows[0..16) 终态(同格式)
  meta.json    配置元数据(布局指针/期望值摘要/数据来源)

数据来源与口径(重要):
  - 权重/x/y/M/S 一律**直读** models/golden/ 的 case.npz(rq.*.m / rq.*.s 原值装表,
    不做任何重算)——thus 规避 manifest.gemvs[].ms_rule 两种量化口径(§2.3 默认口径
    与 e2e"输出标定"口径)的复算歧义:芯片侧 requant 语义固定为 GOLDEN_SPEC §2.2,
    两种口径只影响 M/S 的**来源**,不影响比对(期望 y_q8 同样取 npz 原值)。
  - 合成配置(余数/边界)与 decode d02(1 层 lm_head)期望值由本文件**独立实现**
    GOLDEN_SPEC §2 整数协议(python int,不 import gld_gen/gld_verify,§9 双实现)。
  - 已核验(见 P3B_REPORT):golden 全部 gemv 的 b_int32=0 → 无 bias 通路(Y32 总线
    窗口越界,契约坑 b 规避)不影响与 golden 的逐位可比性。

XMEM 布局(程序与本文件共享的固定契约):
  0x0000_0000  job 表区:word0=n_jobs,之后每 job 8 word:
               {w_ptr, x_ptr, ms_ptr, out_ptr, K, N, kt, tag}
               decode 配置复用为 53-word 指针/参数表(见 build_decode)
  0x0001_0000  数据 arena(生成器向上分配:权重/激活/ms 表)
  0x0020_0000  decode 权重区(ARCH_SPEC §4.10 顺序)
  0x0048_0000  SCRATCH(程序输出/暂存;exp_scr.hex 覆盖范围)

ms 块格式(每 N 切片 80B = 20 word):M[16](u32 LE) + RS2[16](u8 = S | ROUND_SEL<<6,
不足 16 通道补 0)。程序一次 DMA 拷入 OC SRAM 后 qcfg。

用法:
  python3 scripts/vrfb_golden.py --all [--outdir tb/integ/work]
  python3 scripts/vrfb_golden.py --config g01 [--outdir ...]
"""
import argparse
import json
import os
import struct

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GROOT = os.path.join(ROOT, "models", "golden")
I8MIN, I8MAX = -128, 127
I32MIN, I32MAX = -(1 << 31), (1 << 31) - 1

XMEM_JOBS = 0x0000_0000
XMEM_ARENA = 0x0001_0000
XMEM_WDEC = 0x0020_0000
XMEM_SCR = 0x0048_0000
SCR_SIZE = 0x0001_0000

BOOT_UART = b"AME-CHIP BOOT OK\n"

M32 = (1 << 32) - 1


def sat32(v):
    return I32MIN if v < I32MIN else (I32MAX if v > I32MAX else v)


def gemv_int32(w, x):
    """§2.1:k 升序逐步累加,每步 SAT32。w[N][K], x[K] → y[N](python int 独立实现)。"""
    n = len(w)
    k = len(x)
    y = [0] * n
    for kk in range(k):
        xk = int(x[kk])
        for i in range(n):
            y[i] = sat32(y[i] + int(w[i][kk]) * xk)
    return y


def requant(y, m, s, rnd=1):
    """§2.2 ROUND_SEL=1 标量。"""
    prod = (int(y) * int(m)) & ((1 << 64) - 1)
    if prod >> 63:
        prod -= 1 << 64
    if rnd:
        prod += 1 << (int(s) - 1)
    return max(I8MIN, min(I8MAX, prod >> int(s)))


def slice_ms_block(m, s):
    """单切片 80B ms 块:M[16](u32) + RS2[16](u8 = S|ROUND_SEL<<6)。
    未用通道补 M=0/S=1(合法:requant 恒 0,且不触发 S=0 非法 ERR)。"""
    blk = bytearray(80)
    for i in range(16):
        if i < len(m):
            blk[i * 4:i * 4 + 4] = struct.pack("<I", int(m[i]) & M32)
            blk[64 + i] = int(s[i]) & 0x3F | 0x40
        else:
            blk[64 + i] = 1 | 0x40        # S=1, M=0
    return bytes(blk)


def ms_table(m, s):
    """全 N 通道按切片主序展开的 ms 表。"""
    out = bytearray()
    n = len(m)
    for sl in range((n + 15) // 16):
        out += slice_ms_block(m[sl * 16:sl * 16 + 16], s[sl * 16:sl * 16 + 16])
    return bytes(out)


XMEM_BASE_ADDR = 0x4000_0000


class Arena:
    """XMEM arena 分配器(写入镜像偏移;返回**绝对总线地址**)。"""

    def __init__(self, img):
        self.img = img
        self.ptr = XMEM_ARENA

    def alloc(self, data, align=16):
        self.ptr = (self.ptr + align - 1) & ~(align - 1)
        off = self.ptr
        self.img.put(off, bytes(data))
        self.ptr += len(data)
        return off

    def u32(self, v):
        return struct.pack("<I", v & M32)


def emit_words(path, mem, base, nbytes):
    """bytearray → $readmemh(word 索引 @addr,8 hex/行,小端打包,稀疏非零段)。"""
    w0 = base // 4
    w1 = (base + nbytes + 3) // 4
    lines = []
    run_start = None
    for wi in range(w0, w1):
        word = int.from_bytes(mem[wi * 4:wi * 4 + 4], "little")
        if word != 0:
            if run_start is None:
                run_start = wi
                lines.append("@%08X" % wi)
            lines.append("%08X" % word)
        else:
            run_start = None
    with open(path, "w") as f:
        f.write("\n".join(lines) + ("\n" if lines else ""))


def emit_bytes(path, data):
    with open(path, "w") as f:
        for b in data:
            f.write("%02X\n" % (b & 0xFF))


class XmemImage:
    """8MB XMEM 镜像(含 job 区/arena/SCR)。

    输出按"写入跨度"稠密生成(含跨度内的零字):稀疏输出会漏掉整字为零的
    word,行为模型的未初始化存储会以 X 参与 DMA 拷贝(联测中实际踩到)。
    """

    def __init__(self):
        self.mem = bytearray(8 * 1024 * 1024)
        self.spans = []

    def put(self, addr, data):
        self.mem[addr:addr + len(data)] = bytes(data)
        if data:
            self.spans.append((addr, len(data)))

    def u32(self, v):
        return struct.pack("<I", v & M32)

    def emit(self, path):
        spans = sorted(self.spans)
        merged = []
        for off, ln in spans:
            if merged and off <= merged[-1][0] + merged[-1][1]:
                end = max(merged[-1][0] + merged[-1][1], off + ln)
                merged[-1] = (merged[-1][0], end - merged[-1][0])
            else:
                merged.append((off, ln))
        lines = []
        for off, ln in merged:
            w0 = off // 4
            w1 = (off + ln + 3) // 4
            lines.append("@%08X" % w0)
            for wi in range(w0, w1):
                lines.append("%08X" % int.from_bytes(self.mem[wi*4:wi*4+4], "little"))
        with open(path, "w") as f:
            f.write("\n".join(lines) + ("\n" if lines else ""))


def npz_get(z, *names):
    for n in names:
        if n in z:
            return z[n]
    raise KeyError(str(names))


class GemvCase:
    """一个 GEMV 用例(直读 npz 或合成)。"""

    def __init__(self, gid, W, x, m, s, y_q, rnd=1, source=""):
        self.gid = gid
        self.W = np.asarray(W, dtype=np.int64)
        self.x = np.asarray(x, dtype=np.int64)
        self.m = np.asarray(m, dtype=np.int64)
        self.s = np.asarray(s, dtype=np.int64)
        self.y_q = np.asarray(y_q, dtype=np.int64)
        self.rnd = rnd
        self.source = source
        self.N, self.K = self.W.shape
        y32 = gemv_int32(self.W.tolist(), self.x.tolist())
        for i in range(self.N):
            rq = requant(y32[i], self.m[i], self.s[i], self.rnd)
            assert rq == int(self.y_q[i]), \
                f"{gid}[{i}]: requant 链不符 y32={y32[i]} m={self.m[i]} s={self.s[i]} " \
                f"rq={rq} yq={int(self.y_q[i])}"

    def slice_ms_blocks(self):
        """逐 N 切片的 80B ms 块(切片主序;未用通道 M=0/S=1 合法填充)。"""
        return ms_table(self.m, self.s)


def load_gemv_cases(case):
    z = np.load(os.path.join(GROOT, case, "case.npz"))
    man = json.load(open(os.path.join(GROOT, "manifest.json")))["cases"][case]
    out = {}
    for g in man["gemvs"]:
        gid = g["id"]
        p = g["npz_prefix"]
        W = z[g["keys"]["w"]]
        x = npz_get(z, f"{p}.xin.q8", f"{p}_xin.q8")
        yq = npz_get(z, f"{p}.y.q8", f"{p}_y_q8")
        m = z[g["keys"]["rq_m"]]
        s = z[g["keys"]["rq_s"]]
        b = npz_get(z, f"{p}.b.int32", f"{p}_b_int32")
        assert not np.any(b != 0), f"{case}/{gid} bias 非零(无 Y32 通路,不可比)"
        out[gid] = GemvCase(gid, W, x, m, s, yq, source=f"{case}.npz")
    return out, man, z


def checksum_note():
    return "csum = rotl32(csum,1) + (y_q8 & 0xFF),逐通道按 n 升序,per job"


def job_checksum(yq_bytes):
    c = 0
    for b in yq_bytes:
        c = (((c << 1) & M32) | (c >> 31)) + (b & 0xFF)
        c &= M32
    return c


def hex8(v):
    return "%08x" % (v & M32)


# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------

def build_gemv_config(name, cases, slices, kt=16):
    """slices: [(gid, n0, n1)] — 跑各 gid 的 [n0,n1) 输出通道(全 N 则 (gid,0,N))。"""
    img = XmemImage()
    jobs = []
    arena = Arena(img)
    scr = XMEM_SCR
    exp_uart = bytearray(BOOT_UART)
    scr_expected = bytearray()
    meta_jobs = []
    for gid, n0, n1 in slices:
        c = cases[gid]
        assert 0 <= n0 < n1 <= c.N
        sub = GemvCase(gid, c.W[n0:n1], c.x, c.m[n0:n1], c.s[n0:n1],
                       c.y_q[n0:n1], c.rnd, c.source)
        w_off = arena.alloc(c.W[n0:n1].astype(np.int8).tobytes())
        x_off = arena.alloc(c.x.astype(np.int8).tobytes())
        ms_off = arena.alloc(sub.slice_ms_blocks())
        out_off = scr
        yb = c.y_q[n0:n1].astype(np.int8).tobytes()
        n = n1 - n0
        scr_expected += yb
        pad = (-len(scr_expected)) % 16
        scr_expected += b"\x00" * pad
        scr += n + ((16 - n % 16) % 16)
        img.put(out_off, yb)
        XB = XMEM_BASE_ADDR
        jobs += [XB + w_off, XB + x_off, XB + ms_off, XB + out_off, c.K, n, kt,
                 ord("A") + len(meta_jobs)]
        exp_uart += bytes([ord("A") + len(meta_jobs)]) + \
            hex8(job_checksum(yb)).encode() + b"\n"
        meta_jobs.append({"gid": gid, "n0": n0, "n1": n1, "out": out_off,
                          "csum": hex8(job_checksum(yb))})
    img.put(XMEM_JOBS, struct.pack("<I", len(meta_jobs)) +
            b"".join(img.u32(v) for v in jobs))
    cfgdir = os.path.join(OUTDIR, "cfg", name)
    os.makedirs(cfgdir, exist_ok=True)
    img.emit(os.path.join(cfgdir, "xmem.hex"))
    emit_bytes(os.path.join(cfgdir, "exp_uart.hex"), exp_uart)
    emit_words(os.path.join(cfgdir, "exp_scr.hex"), bytes(scr_expected), 0,
               len(scr_expected))
    emit_words(os.path.join(cfgdir, "kv.hex"), b"", 0, 0)
    json.dump({"kind": "gemv", "jobs": meta_jobs, "checksum": checksum_note(),
               "kt": kt, "prog": "verify_gemv",
               "scr_words": (len(scr_expected) + 3) // 4},
              open(os.path.join(cfgdir, "meta.json"), "w"), indent=1)
    return {"name": name, "prog": "verify_gemv", "n_jobs": len(meta_jobs)}


def build_gemv_synthetic(name, shapes):
    """合成 GEMV 用例(独立协议实现期望值)。shapes: [(N,K,kt,seed,variant)]"""
    img = XmemImage()
    arena = Arena(img)
    scr = XMEM_SCR
    exp_uart = bytearray(BOOT_UART)
    scr_expected = bytearray()
    meta_jobs = []
    for ji, (N, K, kt, seed, variant) in enumerate(shapes):
        rng = np.random.default_rng(seed)
        if variant == "zero":
            W = np.zeros((N, K), dtype=np.int64)
            x = np.zeros(K, dtype=np.int64)
        elif variant == "extreme":
            W = np.full((N, K), 127, dtype=np.int64)
            W[::2] = -128
            x = np.full(K, 127, dtype=np.int64)
            x[1::2] = -128
        else:
            W = rng.integers(-128, 128, size=(N, K), dtype=np.int64)
            x = rng.integers(-128, 128, size=K, dtype=np.int64)
        m = (np.arange(N, dtype=np.int64) * 37 + 101) % 40000 + 1
        s = np.full(N, 8, dtype=np.int64)
        y32 = gemv_int32(W.tolist(), x.tolist())
        yq = np.array([requant(y32[i], m[i], s[i]) for i in range(N)], dtype=np.int64)
        kpad = ((K + kt - 1) // kt) * kt
        if kpad != K:
            W = np.pad(W, ((0, 0), (0, kpad - K)))
            x = np.pad(x, (0, kpad - K))
        c = GemvCase(f"{name}#j{ji}", W, x, m, s, yq, source="synthetic")
        gid = c.gid
        w_off = arena.alloc(W.astype(np.int8).tobytes())
        x_off = arena.alloc(x.astype(np.int8).tobytes())
        ms_off = arena.alloc(c.slice_ms_blocks())
        out_off = scr
        yb = yq.astype(np.int8).tobytes()
        scr_expected += yb
        scr_expected += b"\x00" * ((-len(scr_expected)) % 16)
        scr += N + ((16 - N % 16) % 16)
        img.put(out_off, yb)
        XB = XMEM_BASE_ADDR
        jobs = [XB + w_off, XB + x_off, XB + ms_off, XB + out_off, int(c.K), N, kt,
                ord("A") + ji]
        img.put(XMEM_JOBS + 4 + 32 * ji, b"".join(img.u32(v) for v in jobs))
        exp_uart += bytes([ord("A") + ji]) + hex8(job_checksum(yb)).encode() + b"\n"
        meta_jobs.append({"gid": gid, "N": N, "K": K, "kt": kt, "out": out_off,
                          "csum": hex8(job_checksum(yb))})
    img.put(XMEM_JOBS, struct.pack("<I", len(meta_jobs)))
    cfgdir = os.path.join(OUTDIR, "cfg", name)
    os.makedirs(cfgdir, exist_ok=True)
    img.emit(os.path.join(cfgdir, "xmem.hex"))
    emit_bytes(os.path.join(cfgdir, "exp_uart.hex"), exp_uart)
    emit_words(os.path.join(cfgdir, "exp_scr.hex"), bytes(scr_expected), 0,
               len(scr_expected))
    emit_words(os.path.join(cfgdir, "kv.hex"), b"", 0, 0)
    json.dump({"kind": "gemv", "jobs": meta_jobs, "prog": "verify_gemv",
               "scr_words": (len(scr_expected) + 3) // 4},
              open(os.path.join(cfgdir, "meta.json"), "w"), indent=1)
    return {"name": name, "prog": "verify_gemv", "n_jobs": len(meta_jobs)}


# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------

def npz_e2e(z, gid, name):
    p = f"gold.0.gemv{gid}"
    for cand in (f"{p}.{name}", f"{p}_{name}"):
        if cand in z:
            return z[cand]
    raise KeyError(f"{p}.{name}")


def kvmodel_index(L, T, H, pos):
    """KV 模型平坦字节空间:[L][T][H][pos][64]。"""
    return (((L * 2 + T) * 4 + H) * 256 + pos) * 64


def build_decode_config(name, z, layers, tokens):
    img = XmemImage()
    arena = Arena(img)
    wbase = XMEM_WDEC
    scr = XMEM_SCR

    def scr_alloc(n):
        nonlocal scr
        off = scr
        scr += (n + 15) & ~15
        return off

    wptr, msptr = {}, {}
    mskey = {"qkv": "Wqkv", "o": "Wo", "fc1": "fc1", "fc2": "fc2"}
    for l in range(2):
        worder = [("qkv", f"blocks.{l}.Wqkv.weight"), ("o", f"blocks.{l}.Wo.weight"),
                  ("fc1", f"blocks.{l}.fc1.weight"), ("fc2", f"blocks.{l}.fc2.weight")]
        for key, wname in worder:
            W = z[f"w.{wname}.q8"]
            wptr[(l, key)] = wbase
            img.put(wbase, W.astype(np.int8).tobytes())
            wbase += W.shape[0] * W.shape[1]
            m = z[f"rq.blocks.{l}.{mskey[key]}.weight.m"]
            s = z[f"rq.blocks.{l}.{mskey[key]}.weight.s"]
            msptr[(l, key)] = arena.alloc(ms_table(m, s), align=4)
    W = z["w.lm_head.weight.q8"]
    wptr["lm"] = wbase
    img.put(wbase, W.astype(np.int8).tobytes())
    m = z["rq.lm_head.weight.m"]
    s = z["rq.lm_head.weight.s"]
    msptr["lm"] = arena.alloc(ms_table(m, s), align=4)

    act = {}
    for l in range(2):
        for key, nk in [("ln1", "ln1_out"), ("attn", "attn_out"),
                        ("ln2", "ln2_out"), ("gelu", "gelu_out")]:
            v = z[f"act.0.L{l}.{nk}.q8"]
            act[(l, key)] = arena.alloc(v.astype(np.int8).tobytes())
    act["x_emb"] = arena.alloc(z["act.0.x_emb.q8"].astype(np.int8).tobytes())
    act["lnf"] = arena.alloc(z["act.0.lnf_out.q8"].astype(np.int8).tobytes())
    ptab = {}
    for l in range(2):
        for h in range(4):
            p = z[f"act.0.L{l}.attn_prob.q8"][h][:16].astype(np.int8).tobytes()
            p = p + b"\x00" * (16 - len(p))
            ptab[(l, h)] = arena.alloc(p)

    scr_qkv = scr_alloc(768)
    scr_kvrow = scr_alloc(512)
    scr_emb = scr_alloc(256)
    out_score = scr_alloc(4 * 16 * 2)     # [l][h][16]
    out_attn = scr_alloc(256 * 2)
    out_o = scr_alloc(256 * 2)
    out_fc1 = scr_alloc(1024 * 2)
    out_fc2 = scr_alloc(256 * 2)
    img.put(scr_kvrow, bytes(512))

    msscore, pvblk = {}, {}
    for l in range(2):
        for h in range(4):
            msscore[(l, h)] = arena.alloc(
                slice_ms_block(z[f"rq.gemv{2 + h + 12*l:02d}.m"],
                               z[f"rq.gemv{2 + h + 12*l:02d}.s"]), align=4)
            p100 = (z[f"act.0.L{l}.attn_prob.q8"][h][:16].astype(np.int8).tobytes()
                    + b"\x00" * (16 - len(z[f"act.0.L{l}.attn_prob.q8"][h][:16])) + b"\x00" * 4)
            pvblk[(l, h)] = arena.alloc(
                p100 + slice_ms_block(z[f"rq.gemv{6 + h + 12*l:02d}.m"],
                                      z[f"rq.gemv{6 + h + 12*l:02d}.s"]), align=4)

    lm_in_ptr = act["lnf"] if layers == 2 else act[(0, "ln2")]
    exp_uart = bytearray(BOOT_UART)
    scr_expected = bytearray(scr - XMEM_SCR)

    def scrput(off, data):
        img.put(off, data)
        scr_expected[off - XMEM_SCR:off - XMEM_SCR + len(data)] = bytes(data)

    def wrd(idx, v):
        img.put(XMEM_JOBS + 4 * idx, img.u32(v))

    XB = XMEM_BASE_ADDR
    def wrdp(i, v):
        wrd(i, v if v == 0 else XB + v)
    wrd(0, 0xDEC0DE01)
    wrd(1, layers | (tokens << 8) | (9 << 16))
    for l in range(2):
        wrdp(2 + l * 8 + 0, wptr[(l, "qkv")]); wrdp(3 + l * 8, msptr[(l, "qkv")])
        wrdp(4 + l * 8, wptr[(l, "o")]); wrdp(5 + l * 8, msptr[(l, "o")])
        wrdp(6 + l * 8, wptr[(l, "fc1")]); wrdp(7 + l * 8, msptr[(l, "fc1")])
        wrdp(8 + l * 8 + 0, wptr[(l, "fc2")])
        wrdp(8 + l * 8 + 1, msptr[(l, "fc2")])
    wrdp(18, wptr["lm"]); wrdp(19, msptr["lm"])
    wrdp(20, act["x_emb"])
    for l in range(2):
        wrdp(21 + l * 4, act[(l, "ln1")]); wrdp(22 + l * 4, act[(l, "attn")])
        wrdp(23 + l * 4, act[(l, "ln2")]); wrdp(24 + l * 4, act[(l, "gelu")])
    wrdp(30, lm_in_ptr)
    for l in range(2):
        for h in range(4):
            wrdp(31 + l * 4 + h, ptab[(l, h)])
    wrdp(39, scr_qkv); wrdp(40, scr_kvrow); wrdp(41, out_score)
    wrdp(42, out_attn); wrdp(43, out_o); wrdp(44, out_fc1)
    wrdp(45, out_fc2)
    for l in range(2):
        for h in range(4):
            wrdp(46 + l * 4 + h, msscore[(l, h)])
            wrdp(54 + l * 4 + h, pvblk[(l, h)])
    wrdp(62, scr_emb)
    for l in range(2):
        for h in range(4):
            wrd(64 + l * 4 + h, XB + scr_qkv + h * 64)

    jobbase = 0x0000_0800
    desc = []

    def mk_desc(w, ms, x, out, K, N, tag):
        desc.extend([w, x, ms, out, K, N, 16, tag])

    for l in range(layers):
        mk_desc(wptr[(l, "qkv")], msptr[(l, "qkv")], act[(l, "ln1")],
                scr_qkv, 256, 768, 0)
        mk_desc(wptr[(l, "o")], msptr[(l, "o")], out_attn + l * 256,
                out_o + l * 256, 256, 256, 0)
        mk_desc(wptr[(l, "fc1")], msptr[(l, "fc1")], act[(l, "ln2")],
                out_fc1 + l * 1024, 256, 1024, 0)
        mk_desc(wptr[(l, "fc2")], msptr[(l, "fc2")], act[(l, "gelu")],
                out_fc2 + l * 256, 1024, 256, 0)
    mk_desc(wptr["lm"], msptr["lm"], lm_in_ptr, 0, 256, 1024, 0x100)
    desc = [v if (i % 8 not in (0, 1, 2, 3)) else (XB + v if v != 0 else 0)
            for i, v in enumerate(desc)]
    for i, v in enumerate(desc):
        img.put(jobbase + 4 * i, img.u32(v))
    wrd(63, XB + jobbase)

    kvimg = bytearray(2 * 2 * 4 * 256 * 64)
    ctx = 9
    for l in range(layers):
        yqkv = npz_e2e(z, f"{1+12*l:02d}", "y.q8")
        scrput(scr_qkv, yqkv.tobytes())
        # kvrow staging:[h][{K,V}] 8×64B
        kvrow = bytearray(512)
        knew = z[f"kv.0.L{l}.knew.q8"]
        vnew = z[f"kv.0.L{l}.vnew.q8"]
        for h in range(4):
            kvrow[h * 128:h * 128 + 64] = knew[h].tobytes()
            kvrow[h * 128 + 64:h * 128 + 128] = vnew[h].tobytes()
        scrput(scr_kvrow, kvrow)
        for h in range(4):
            g = f"{2 + h + 12*l:02d}"
            ysc = npz_e2e(z, g, "y.q8")[:ctx]
            scrput(out_score + (l * 4 + h) * 16, ysc.tobytes())
            pv = npz_e2e(z, f"{6 + h + 12*l:02d}", "y.q8")
            scrput(out_attn + l * 256 + h * 64, pv.tobytes())
        scrput(out_o + l * 256, npz_e2e(z, f"{10+12*l:02d}", "y.q8").tobytes())
        scrput(out_fc1 + l * 1024, npz_e2e(z, f"{11+12*l:02d}", "y.q8").tobytes())
        scrput(out_fc2 + l * 256, npz_e2e(z, f"{12+12*l:02d}", "y.q8").tobytes())
        for h in range(4):
            for pos in range(8):
                kb = z[f"kv.0.L{l}.k.q8"][h][pos].tobytes()
                vb = z[f"kv.0.L{l}.v.q8"][h][pos].tobytes()
                o = kvmodel_index(l, 0, h, pos)
                kvimg[o:o + 64] = kb
                kvimg[kvmodel_index(l, 1, h, pos):kvmodel_index(l, 1, h, pos) + 64] = vb
            o = kvmodel_index(l, 0, h, 8)
            kvimg[o:o + 64] = knew[h].tobytes()
            kvimg[kvmodel_index(l, 1, h, 8):kvmodel_index(l, 1, h, 8) + 64] = vnew[h].tobytes()
    Wlm = z["w.lm_head.weight.q8"].astype(np.int64)
    xlm = z[lm_in_key(z, layers)].astype(np.int64)
    y32lm = gemv_int32(Wlm.tolist(), xlm.tolist())
    token = int(np.argmax(np.array(y32lm, dtype=np.int64)))
    if layers == 2:
        assert token == int(z["meta.token_pred"]), \
            f"lm_head 链自检失败:argmax={token} token_pred={int(z['meta.token_pred'])}"
    for _ in range(tokens):
        exp_uart += b"T%03x\n" % token

    cfgdir = os.path.join(OUTDIR, "cfg", name)
    os.makedirs(cfgdir, exist_ok=True)
    img.emit(os.path.join(cfgdir, "xmem.hex"))
    emit_words(os.path.join(cfgdir, "kv.hex"), kvimg, 0, len(kvimg))
    emit_bytes(os.path.join(cfgdir, "exp_uart.hex"), exp_uart)
    emit_words(os.path.join(cfgdir, "exp_scr.hex"), bytes(scr_expected), 0,
               len(scr_expected))
    kvexp = bytearray(16 * 64 * 4 * 2 * 2)
    for l in range(layers):
        for h in range(4):
            for T, tname in ((0, "k"), (1, "v")):
                for pos in range(16):
                    o = (((l * 2 + T) * 4 + h) * 16 + pos) * 64
                    if pos < ctx:
                        kvexp[o:o + 64] = z[f"kv.0.L{l}.{tname}.q8"][h][pos].tobytes()
    emit_words(os.path.join(cfgdir, "exp_kv.hex"), bytes(kvexp), 0, len(kvexp))
    json.dump({"kind": "decode", "layers": layers, "tokens": tokens, "ctx": ctx,
               "token": token, "prog": "verify_decode", "lm_in": lm_in_ptr,
               "scr_words": (len(scr_expected) + 3) // 4},
              open(os.path.join(cfgdir, "meta.json"), "w"), indent=1)
    return {"name": name, "prog": "verify_decode", "layers": layers, "tokens": tokens}


def lm_in_key(z, layers):
    return "act.0.lnf_out.q8" if layers == 2 else "act.0.L0.ln2_out.q8"


# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------

def build_edge_config():
    exp = bytearray(BOOT_UART)
    # E1 cfg imm[11:10]=01 → ERR → INTC[5]        "E1:1\n"
    # E2 qcfg S=0 → ERR                            "E2:1\n"
    # E3 exe rs1[31:1]≠0 → ERR                     "E3:1\n"
    # E4 ld.x rs1[31:10]≠0 → ERR                   "E4:1\n"
    # E5 ld.w rs1[31:3]≠0 → ERR                    "E5:1\n"
    # E6 st.y i≥N_eff(cfg n=1)→ ERR + data 0       "E6:1\n"
    # E9 AME DONE → INTC[4]                        "E9:1\n"
    # E10 lw 0x0000_2000 RSV → BUSERR INTC[8]      "E10:1\n"
    # E11 sw BOOTROM → SLVERR INTC[8]              "E11:1\n"
    # E12 lw 0x6000_0000 RSV5 → DECERR INTC[8]     "E12:1\n"
    # E14 DMA SRC→RSV → ERRCODE=2                  "E14:2\n"
    W = [(3 * i + 2) % 7 - 3 for i in range(16)]
    x = [(5 * i) % 11 - 5 for i in range(16)]
    y = gemv_int32([W], x)[0]
    yh = "%08x" % (y & M32)
    y2h = "%08x" % ((2 * y) & M32)
    exp += ("E1:%s\nE2:%s\nE3:%s\nE4:%s\nE5:%s\n" % (yh, yh, yh, yh, yh)).encode()
    exp += b"E6:00000000\n"
    exp += ("E7:%s\nE8:%s\n" % (yh, y2h)).encode()
    exp += b"E9:00000000\nE10:1\nE11:1\nE12:1\nE13:1\nE14:2\nE15:1\n"
    cfgdir = os.path.join(OUTDIR, "cfg", "e01_edge")
    os.makedirs(cfgdir, exist_ok=True)
    emit_bytes(os.path.join(cfgdir, "exp_uart.hex"), exp)
    with open(os.path.join(cfgdir, "xmem.hex"), "w") as f:
        f.write("")
    with open(os.path.join(cfgdir, "kv.hex"), "w") as f:
        f.write("")
    with open(os.path.join(cfgdir, "exp_scr.hex"), "w") as f:
        f.write("")
    with open(os.path.join(cfgdir, "exp_kv.hex"), "w") as f:
        f.write("")
    json.dump({"kind": "edge", "y": y, "prog": "verify_edge"},
              open(os.path.join(cfgdir, "meta.json"), "w"), indent=1)
    return {"name": "e01_edge", "prog": "verify_edge", "y": y}


# ---------------------------------------------------------------------------

OUTDIR = os.path.join(ROOT, "tb", "integ", "work")


def main():
    global OUTDIR
    ap = argparse.ArgumentParser()
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--config", action="append", default=[])
    ap.add_argument("--outdir", default=OUTDIR)
    args = ap.parse_args()
    OUTDIR = args.outdir

    made = []
    unit, _, _ = load_gemv_cases("unit_gemv")
    e2e = np.load(os.path.join(GROOT, "e2e_step_T8", "case.npz"))
    shapes = {g["id"]: (g["N"], g["K"]) for g in
              json.load(open(os.path.join(GROOT, "manifest.json")))
              ["cases"]["unit_gemv"]["gemvs"]}

    for i in range(1, 26):
        gid = f"G{i:02d}"
        made.append(build_gemv_config(f"g{i:02d}", unit, [(gid, 0, shapes[gid][0])]))
    made.append(build_gemv_config("g26_kt8", unit, [("G02", 0, 128)], kt=8))
    made.append(build_gemv_synthetic("g27_n5k35", [(5, 35, 16, 101, "rand")]))
    made.append(build_gemv_synthetic("g28_k35", [(16, 35, 16, 102, "rand")]))
    made.append(build_gemv_synthetic("g29_n17k48", [(17, 48, 16, 103, "rand")]))
    made.append(build_gemv_synthetic("g30_n1ext", [(1, 16, 16, 104, "extreme")]))
    made.append(build_gemv_synthetic("g31_zero", [(16, 32, 16, 105, "zero")]))
    # decode
    made.append(build_decode_config("d01_e2e", e2e, 2, 1))
    made.append(build_decode_config("d02_1layer", e2e, 1, 1))
    made.append(build_decode_config("d03_2tok", e2e, 2, 2))
    # edge
    made.append(build_edge_config())

    print(f"vrfb_golden: {len(made)} configs → {OUTDIR}/cfg/")
    for m in made:
        print("  ", m["name"], m["prog"])


if __name__ == "__main__":
    main()
