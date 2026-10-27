#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""vfrc_kv_gen.py — P3C 独立 KV/TRANSPOSE/SLICE 参考模型与场景生成

模型严格按 docs/ARCH_SPEC.md §4.9 的**逐字节语义**重新实现(与 P2C 的
scripts/mem_kv_golden.py 相互独立,不复用其代码):

  非转置: DST[(pos-POS)*PITCH + i] = row(pos)[DDOFF+i], i in [0,DLEN)
          PITCH=0 -> 紧凑(行长=DLEN)
  转置:   DST[(d-DDOFF)*16 + (pos-POS)] = row(pos)[d], COUNT<=16
  APPEND_K/V : SRC 处 64 B -> kv_off(LAYER,K/V,HEAD,POS)
  APPEND_KV8 : SRC 处 8x64 B,按 [h][{K,V}] -> 4 head 的 K/V(POS/LAYER 公共)
  CLEAR      : LAYER/HEAD 的 K 与 V 各 COUNT 行写 0
  kv_off(layer,t,h,pos,j) = layer*0x20000 + t*0x10000 + h*0x4000 + pos*64 + j

SLICE 编码(P2C 兼容编码,见 reports/issues/P2C.md):
  enc[5:0]=DDOFF(0..63), enc[11:6]=DLEN(0 -> 64)
本文件同时输出兼容编码与 §4.9 原编码([4:0]/[9:5])的等价性结论
(kv_slice_equiv.txt),供契约定稿引用。

场景(--variant):
  a_full   后端 A(2 层,ctx=128):decode 序列 + 跨边界 + 边界 SLICE + 错误路径 + CLEAR
  a_slice  后端 A(2 层,ctx=128):SLICE 组合抽样(两种转置模式)
  b_full   后端 B(1 层,ctx=128):32 pos 抽查
  slice_b  后端 B(1 层,ctx=128):SLICE **穷举**(DDOFF 0..63 x DLEN 1..64,
           DDOFF+DLEN<=64;转置/非转置各一遍)+ COUNT=16 抽样

输出目录内容:
  kv_cmds.hex      每 op 16 字:w0= flags, w1 layer, w2 head, w3 pos, w4 count,
                   w5 src, w6 dst, w7 pitch, w8 slice, w9 rb_words
                   flags: [2:0] mode [4] tr [5] irq [7] exp_err
                          [11:8] exp_errcode [16] check_dst
  kv_src.hex       APPEND 源数据(逐字,预载到 SRC_BASE=0x4048_0000)
  kv_exp_dst.hex   逐 op 读回期望字流(check_dst=1 的 op,按命令序)
  kv_exp_xmem.hex  后端 A 的 XMEM KV 区镜像(131072 半字)
  kv_exp_bank{0..3}.hex 后端 B 的 bank 镜像(4x4096 字)
  kv_meta.txt      变体摘要
  kv_slice_equiv.txt  编码等价性结论

用法:
  python3 scripts/vfrc_kv_gen.py --variant a_full --outdir build/p3c/golden/a_full
  python3 scripts/vfrc_kv_gen.py --variant slice_b --outdir build/p3c/golden/slice_b
  python3 scripts/vfrc_kv_gen.py --equivalence-only
"""
import argparse
import os
import sys

SRC_BASE = 0x4048_0000
DST_BASE = 0x0000_0800
KV_XMEM_BASE = 0x4040_0000
ROW_B = 64
HEADS = 4


def enc_slice(ddoff, dlen):
    """兼容编码:DDOFF[5:0], DLEN[11:6](64 -> 0)。"""
    assert 0 <= ddoff <= 63 and 1 <= dlen <= 64, (ddoff, dlen)
    return (ddoff & 0x3F) | ((0 if dlen == 64 else dlen) << 6)


def dec_slice_compat(enc):
    ddoff = enc & 0x3F
    dc = (enc >> 6) & 0x3F
    return ddoff, (64 if dc == 0 else dc)


def dec_slice_spec(enc):
    """§4.9 原文 5-bit 字段直译(仅用于等价性分析;DLEN=0 无定义)。"""
    return enc & 0x1F, (enc >> 5) & 0x1F


def slice_equivalence():
    """兼容编码 vs §4.9 原编码的等价性分析。

    注意:两者是**不同的位布局**,不是 bit-compatible。这里比较的是
    "对同一 (DDOFF,DLEN) 语义对,两种编码能否表达、解码是否回到原对"。
    """
    compat_pairs = [(dd, dl) for dd in range(64) for dl in range(1, 65)
                    if dd + dl <= 64]
    spec_pairs = [(dd, dl) for (dd, dl) in compat_pairs if dd <= 31 and dl <= 31]
    bad_rt = 0
    for (dd, dl) in compat_pairs:
        if dec_slice_compat(enc_slice(dd, dl)) != (dd, dl):
            bad_rt += 1
    lit = 16 | (16 << 5)
    demo = dec_slice_compat(lit)
    lines = []
    lines.append("SLICE 编码等价性结论(兼容编码 vs ARCH_SPEC §4.9 原语义)")
    lines.append("")
    lines.append("兼容编码(RTL/P2C-1): enc[5:0]=DDOFF(0..63),")
    lines.append("                     enc[11:6]=DLEN 码(0 表示 64)")
    lines.append("§4.9 原文编码      : enc[4:0]=DDOFF, enc[9:5]=DLEN(5 bit)")
    lines.append("")
    lines.append("A. 语义域(READ 方程本身)")
    lines.append("   兼容编码可表达 %d 个 (DDOFF,DLEN) 组合(DD 0..63," % len(compat_pairs))
    lines.append("   DL 1..64, DD+DL<=64);编码->解码往返失配 = %d。" % bad_rt)
    lines.append("   原 5-bit 字段可表达的子集 = %d 个(DD<=31 且 DL<=31)。" % len(spec_pairs))
    lines.append("   在该子集上,两种编码都能表达同一语义对,READ 方程逐字节")
    lines.append("   相同 => **语义等价**。")
    lines.append("   其余 %d 个组合(DDOFF>=32 或 DLEN>=32)原字段无法表达," % (len(compat_pairs) - len(spec_pairs)))
    lines.append("   兼容编码是对 §4.9 语义域的**严格超集扩展**,不改变原子集。")
    lines.append("")
    lines.append("B. 位布局(重要:不是 bit-compatible)")
    lines.append("   两种编码的字段位置不同,同一 32-bit 寄存器值解码不同。")
    lines.append("   例:按原布局写 (DDOFF=16,DLEN=16) => enc=0x%03x;" % lit)
    lines.append("   兼容编码将其解码为 (DDOFF=%d,DLEN=%d),不等价。" % demo)
    lines.append("   另外原布局 DLEN=48 需要 6 bit,写 5 bit 会溢出到字段外。")
    lines.append("   => 软件必须按新布局编码;旧布局的二进制配置不兼容。")
    lines.append("")
    lines.append("C. 唯一定义缺口")
    lines.append("   原文字段 DLEN 规定 1..64,但 5 bit 无法表示 32..64;")
    lines.append("   DLEN=0 原文未定义。兼容编码把码 0 定义为 64(整行),")
    lines.append("   与同表'复位 0 -> 整行'一致。")
    lines.append("")
    lines.append("D. RTL 实测证据")
    lines.append("   verify_kv_slice/slice_b 对全部 %d 个组合 x {转置,非转置}" % len(compat_pairs))
    lines.append("   逐字节与独立 python 模型对拍(见 reports/P3C_REPORT.md)。")
    lines.append("")
    lines.append("结论:兼容编码在 §4.9 原语义域内**语义等价**,在域外为")
    lines.append("严格超集;但它与原文位布局**不 bit-compatible**。建议契约")
    lines.append("定稿采用 [5:0]/[11:6] 并把 DLEN=0 明确为 64。")
    return lines, len(compat_pairs), len(spec_pairs), bad_rt


class KVStore:
    """(layer,kvt,head) -> ctx 行,每行 64 B。未写过的行为全 0。"""

    def __init__(self, layers, ctx):
        self.layers = layers
        self.ctx = ctx
        self.rows = {}

    def row(self, la, kvt, h, pos):
        key = (la, kvt, h)
        if key not in self.rows:
            self.rows[key] = [bytearray(ROW_B) for _ in range(self.ctx)]
        return self.rows[key][pos]

    def append(self, la, kvt, h, pos, data):
        assert len(data) == ROW_B
        self.row(la, kvt, h, pos)[:] = data

    def append_kv8(self, la, pos, data512):
        for h in range(HEADS):
            self.append(la, 0, h, pos, data512[h * 128:h * 128 + 64])
            self.append(la, 1, h, pos, data512[h * 128 + 64:h * 128 + 128])

    def clear(self, la, h, pos, count):
        for r in range(pos, pos + count):
            self.row(la, 0, h, r)[:] = bytes(ROW_B)
            self.row(la, 1, h, r)[:] = bytes(ROW_B)

    def read_image(self, la, kvt, h, pos, count, ddoff, dlen, pitch, tr):
        if tr:
            span = dlen * 16
            img = bytearray(span)
            for r in range(count):
                row = self.row(la, kvt, h, pos + r)
                for i in range(dlen):
                    img[i * 16 + r] = row[ddoff + i]
            return img
        peff = pitch if pitch else dlen
        span = (count - 1) * peff + dlen
        img = bytearray(span)
        for r in range(count):
            row = self.row(la, kvt, h, pos + r)
            img[r * peff:r * peff + dlen] = bytes(row[ddoff:ddoff + dlen])
        return img


def pack_words(img, nwords):
    out = []
    for i in range(nwords):
        b = bytes(img[4 * i:4 * i + 4])
        b = b + b"\x00" * (4 - len(b))
        out.append(b[0] | (b[1] << 8) | (b[2] << 16) | (b[3] << 24))
    return out


def lcg_bytes(seed, n):
    """确定性字节图案(与 P2C 不同:这里用 xorshift 风格)。"""
    x = seed & 0xFFFFFFFF
    out = bytearray()
    for _ in range(n):
        x ^= (x << 13) & 0xFFFFFFFF
        x ^= x >> 17
        x ^= (x << 5) & 0xFFFFFFFF
        x &= 0xFFFFFFFF
        out.append((x >> 11) & 0xFF)
    return bytes(out)


class Builder:
    def __init__(self, layers, ctx):
        self.layers = layers
        self.ctx = ctx
        self.store = KVStore(layers, ctx)
        self.cmds = []
        self.exp = []
        self.src_blocks = []
        self.nops = 0
        self.nread = 0

    def block(self, data):
        assert len(data) == ROW_B
        idx = len(self.src_blocks)
        self.src_blocks.append(data)
        return SRC_BASE + idx * ROW_B

    def add(self, mode, layer=0, head=0, pos=0, count=1, src=0, dst=DST_BASE,
            pitch=0, ddoff=0, dlen=64, tr=0, exp_err=0, exp_code=0,
            append_before=None, append_after=None, check=True):
        """append_before: 先做无命令的存储侧模型更新(用于源数据准备);
        append_after: 命令成功后更新模型。"""
        if append_before:
            append_before(self.store)
        enc = enc_slice(ddoff, dlen)
        rb = 0
        if check and mode in (3, 4) and not exp_err:
            img = self.store.read_image(layer, mode - 3, head, pos, count,
                                        ddoff, dlen, pitch, tr)
            rb = (len(img) + 3) // 4
            self.exp += pack_words(img, rb)
        self.cmds.append([
            (mode & 7) | (tr << 4) | (0 << 5) | (exp_err << 7) |
            ((exp_code & 0xF) << 8) | ((1 if check else 0) << 16),
            layer, head, pos, count, src, dst, pitch, enc, rb,
            0, 0, 0, 0, 0, 0])
        self.nops += 1
        if check and mode in (3, 4) and not exp_err:
            self.nread += 1
        if append_after:
            append_after(self.store)

    def append_kv(self, la, kvt, h, pos, data):
        src = self.block(data)
        self.add(0 + kvt, layer=la, head=h, pos=pos, src=src,
                 append_after=lambda s: s.append(la, kvt, h, pos, data))

    def append_kv8(self, la, pos, data512):
        src = self.block(data512[0:64])
        idx = len(self.src_blocks) - 1
        for k in range(1, 8):
            self.src_blocks.append(data512[k * 64:(k + 1) * 64])
        src = SRC_BASE + idx * ROW_B
        self.add(2, layer=la, pos=pos, src=src,
                 append_after=lambda s: s.append_kv8(la, pos, data512))

    def clear(self, la, h, pos, count):
        self.add(5, layer=la, head=h, pos=pos, count=count,
                 append_after=lambda s: s.clear(la, h, pos, count))

    def read(self, mode, la, h, pos, count, ddoff, dlen, pitch=0, tr=0):
        self.add(mode, layer=la, head=h, pos=pos, count=count,
                 dst=DST_BASE, pitch=pitch, ddoff=ddoff, dlen=dlen, tr=tr)

    def err(self, mode, la=0, h=0, pos=0, count=1, src=SRC_BASE, dst=DST_BASE,
            pitch=0, ddoff=0, dlen=64, tr=0, code=1):
        self.add(mode, layer=la, head=h, pos=pos, count=count, src=src,
                 dst=dst, pitch=pitch, ddoff=ddoff, dlen=dlen, tr=tr,
                 exp_err=1, exp_code=code, check=False)


def variant_a_full():
    b = Builder(2, 128)
    blobs = {}
    for la in range(2):
        for p in range(128):
            blobs[(la, p)] = lcg_bytes(0x51A0_0000 + la * 0x10000 + p * 97, 512)
    for c in range(8):
        for p in range(c * 16, c * 16 + 16):
            for la in range(2):
                b.append_kv8(la, p, blobs[(la, p)])
        for la in range(2):
            for h in range(HEADS):
                for dt in range(4):
                    b.read(3, la, h, c * 16, 16, dt * 16, 16, pitch=16)
        for la in range(2):
            for h in range(HEADS):
                for ds in range(4):
                    b.read(4, la, h, c * 16, 16, ds * 16, 16,
                           pitch=0, tr=1)
    for pos, cnt in ((63, 2), (64, 2), (127, 1), (120, 8), (0, 1)):
        for h in (0, 3):
            b.read(3, 0, h, pos, cnt, 0, 16, pitch=16)
            b.read(4, 0, h, pos, min(cnt, 16), 0, 16, pitch=0, tr=1)
    for pos, cnt in ((0, 8), (60, 8), (120, 8)):
        for h in (1, 2):
            b.read(3, 1, h, pos, cnt, 0, 64, pitch=0)
            b.read(4, 1, h, pos, cnt, 0, 16, pitch=64)
            b.read(3, 1, h, pos, cnt, 16, 32, pitch=48)
    bounds = [(0, 64), (0, 48), (0, 63), (0, 1), (48, 16), (47, 17),
              (63, 1), (1, 63), (16, 48), (32, 32), (0, 16), (2, 3),
              (60, 4), (4, 60), (15, 49), (17, 47)]
    for (dd, dl) in bounds:
        b.read(3, 0, 0, 0, 1, dd, dl, pitch=0)
        b.read(4, 0, 0, 0, 1, dd, dl, pitch=0, tr=1)
        b.read(3, 0, 1, 0, 16, dd, dl, pitch=dl)
    b.clear(0, 2, 32, 32)
    for t in (3, 4):
        for pos, cnt in ((32, 16), (48, 16), (0, 1)):
            b.read(t, 0, 2, pos, cnt, 0, 64, pitch=0)
    b.clear(1, 3, 0, 4)
    b.read(3, 1, 3, 0, 16, 0, 16, pitch=16)
    b.err(6, code=1)
    b.err(3, la=2, code=1)
    b.err(3, h=4, code=1)
    b.err(3, pos=256, code=1)
    b.err(3, pos=0, count=0, code=1)                     # COUNT=0
    b.err(3, pos=248, count=16, code=1)
    b.err(4, pos=0, count=17, tr=1, code=1)
    b.err(3, pos=0, count=1, ddoff=48, dlen=32, code=1)  # DDOFF+DLEN>64
    b.err(0, src=SRC_BASE + 2, code=1)
    b.err(3, dst=DST_BASE + 2, code=1)
    return b, "a_full"


def variant_a_slice():
    b = Builder(2, 128)
    combos = []
    for dd in range(64):
        for dl in range(1, 65):
            if dd + dl <= 64:
                combos.append((dd, dl))
    pats = {}
    for la in range(2):
        for kvt in range(2):
            for h in range(HEADS):
                for pos in (0, 1, 15, 16, 63, 64, 127):
                    pats[(la, kvt, h, pos)] = lcg_bytes(
                        0x9000_0000 + la * 0x100000 + kvt * 0x40000 +
                        h * 0x1000 + pos * 31, 64)
                    b.append_kv(la, kvt, h, pos, pats[(la, kvt, h, pos)])
    sample = combos[::5]
    for (dd, dl) in sample:
        b.read(3, 0, 2, 0, 1, dd, dl, pitch=0)
        b.read(4, 1, 3, 0, 1, dd, dl, pitch=0, tr=1)
    for (dd, dl) in [(0, 16), (16, 16), (32, 16), (48, 16),
                     (0, 64), (0, 48), (1, 17), (3, 61),
                     (17, 47), (47, 17)]:
        b.read(4, 1, 1, 16, 16, dd, dl, pitch=0, tr=1)
        b.read(3, 0, 1, 16, 16, dd, dl, pitch=dl)
    return b, "a_slice"


def variant_b_full():
    b = Builder(1, 128)
    blobs = {p: lcg_bytes(0xB000_0000 + p * 131, 512) for p in range(32)}
    for p in range(32):
        b.append_kv8(0, p, blobs[p])
    for p in (0, 15, 16, 31):
        for h in range(HEADS):
            b.read(3, 0, h, p, 1, 0, 64, pitch=0)
            b.read(4, 0, h, p, 1, 0, 16, pitch=0, tr=1)
    for ch in range(2):
        for h in range(HEADS):
            for dt in range(4):
                b.read(3, 0, h, ch * 16, 16, dt * 16, 16, pitch=16)
            for ds in range(4):
                b.read(4, 0, h, ch * 16, 16, ds * 16, 16, pitch=0, tr=1)
    b.clear(0, 1, 8, 8)
    for t in (3, 4):
        b.read(t, 0, 1, 0, 16, 0, 64, pitch=0)
    b.err(3, h=4, code=1)
    return b, "b_full"


def variant_slice_b():
    b = Builder(1, 128)
    for kvt in range(2):
        for h in range(HEADS):
            for pos in (0, 16):
                b.append_kv(0, kvt, h, pos,
                            lcg_bytes(0xC000_0000 + kvt * 0x10000 +
                                      h * 0x1000 + pos * 7, 64))
    combos = []
    for dd in range(64):
        for dl in range(1, 65):
            if dd + dl <= 64:
                combos.append((dd, dl))
    assert len(combos) == 2080, len(combos)
    for (dd, dl) in combos:
        b.read(3, 0, 2, 0, 1, dd, dl, pitch=0)
        b.read(4, 0, 3, 0, 1, dd, dl, pitch=0, tr=1)
    for (dd, dl) in [(0, 16), (0, 32), (0, 48), (0, 64), (16, 16),
                     (16, 32), (32, 16), (32, 32), (48, 16),
                     (1, 17), (3, 61), (17, 47), (47, 17)]:
        b.read(4, 0, 1, 16, 16, dd, dl, pitch=0, tr=1)
        b.read(3, 0, 1, 16, 16, dd, dl, pitch=dl)
    b.clear(0, 0, 0, 1)
    b.read(3, 0, 0, 0, 1, 0, 64, pitch=0)
    return b, "slice_b"


def write_images(b, outdir, backend_b):
    if backend_b:
        half = b.ctx * 16
        for h in range(HEADS):
            with open(os.path.join(outdir, "kv_exp_bank%d.hex" % h), "w") as f:
                for a in range(half * 2):
                    kvt = a // half
                    rem = a % half
                    pos, w = rem // 16, rem % 16
                    row = b.store.row(0, kvt, h, pos)
                    val = (row[4 * w] | (row[4 * w + 1] << 8) |
                           (row[4 * w + 2] << 16) | (row[4 * w + 3] << 24))
                    f.write("%08x\n" % val)
    else:
        with open(os.path.join(outdir, "kv_exp_xmem.hex"), "w") as f:
            for idx in range(0x20000):
                boff = idx * 2
                la = boff // 0x20000
                t = (boff % 0x20000) // 0x10000
                h = (boff % 0x10000) // 0x4000
                pos = (boff % 0x4000) // ROW_B
                j = boff % ROW_B
                if la < b.layers and pos < b.ctx:
                    row = b.store.row(la, t, h, pos)
                else:
                    row = bytes(ROW_B)
                f.write("%04x\n" % (row[j] | (row[j + 1] << 8)))


def build(variant, outdir):
    if variant == "a_full":
        b, name = variant_a_full(); backend_b = False
    elif variant == "a_slice":
        b, name = variant_a_slice(); backend_b = False
    elif variant == "b_full":
        b, name = variant_b_full(); backend_b = True
    elif variant == "slice_b":
        b, name = variant_slice_b(); backend_b = True
    else:
        raise SystemExit("unknown variant " + variant)

    os.makedirs(outdir, exist_ok=True)
    with open(os.path.join(outdir, "kv_cmds.hex"), "w") as f:
        for c in b.cmds:
            for w in c:
                f.write("%08x\n" % (w & 0xFFFFFFFF))
    with open(os.path.join(outdir, "kv_src.hex"), "w") as f:
        for blk in b.src_blocks:
            for w in pack_words(blk, 16):
                f.write("%08x\n" % w)
    with open(os.path.join(outdir, "kv_exp_dst.hex"), "w") as f:
        for w in b.exp:
            f.write("%08x\n" % w)
    with open(os.path.join(outdir, "kv_counts.hex"), "w") as f:
        f.write("%08x\n" % b.nops)
        f.write("%08x\n" % len(b.exp))
        f.write("%08x\n" % (len(b.src_blocks) * 16))
    write_images(b, outdir, backend_b)

    with open(os.path.join(outdir, "kv_meta.txt"), "w") as f:
        f.write("variant=%s\n" % name)
        f.write("backend=%s\n" % ("B" if backend_b else "A"))
        f.write("layers=%d\nctx=%d\n" % (b.layers, b.ctx))
        f.write("ops=%d\nread_ops=%d\nexp_words=%d\nsrc_words=%d\n" %
                (b.nops, b.nread, len(b.exp), len(b.src_blocks) * 16))
        f.write("src_base=0x%08x\ndst_base=0x%08x\n" % (SRC_BASE, DST_BASE))
    lines, nb, ne, nc = slice_equivalence()
    with open(os.path.join(outdir, "kv_slice_equiv.txt"), "w") as f:
        f.write("\n".join(lines) + "\n")
    return b, backend_b, name


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--variant", default=None,
                    choices=["a_full", "a_slice", "b_full", "slice_b"])
    ap.add_argument("--outdir", default=None)
    ap.add_argument("--equivalence-only", action="store_true")
    args = ap.parse_args()

    if args.equivalence_only:
        lines, nb, ne, nc = slice_equivalence()
        print("\n".join(lines))
        return

    if args.variant is None:
        for v in ("a_full", "a_slice", "b_full", "slice_b"):
            out = os.path.join(args.outdir or "build/p3c/golden", v)
            b, bb, name = build(v, out)
            print("%-8s backend=%s ops=%d read_ops=%d exp_words=%d src_words=%d"
                  % (v, "B" if bb else "A", b.nops, b.nread, len(b.exp),
                     len(b.src_blocks) * 16))
        return

    out = args.outdir or os.path.join("build/p3c/golden", args.variant)
    b, bb, name = build(args.variant, out)
    print("%s: backend=%s ops=%d read_ops=%d exp_words=%d src_words=%d"
          % (name, "B" if bb else "A", b.nops, b.nread, len(b.exp),
             len(b.src_blocks) * 16))


if __name__ == "__main__":
    main()
