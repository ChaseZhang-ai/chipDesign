#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""mem_kv_golden.py — KV 控制器 golden 模型与激励/期望文件生成(P2C)

严格按 docs/ARCH_SPEC.md §4.9 语义实现(逐字节):
  APPEND_K/V   : SRC 处 64 B → kv_off(LAYER,K/V,HEAD,POS)
  APPEND_KV8   : SRC 处 8×64 B 按 [h][{K,V}] → 4 head 的 K、V
  READ_K/V     : DST[(pos-POS)*PITCH + i] = row(pos)[DDOFF+i]        (非转置)
                 DST[(d-DDOFF)*16 + (pos-POS)] = row(pos)[d]         (转置)
                 PITCH=0 → 紧凑(行长=DLEN)
  CLEAR        : LAYER/HEAD 的 K 与 V 各 COUNT 行写 0
  kv_off(layer,t,h,pos,j) = layer*0x20000 + t*0x10000 + h*0x4000 + pos*64 + j

SLICE 编码(契约 [4:0]/[9:5] 编不下 DDOFF=48/DLEN=64;本实现)
  [5:0] DDOFF(字节),[11:6] DLEN(0 → 64 整行)。见 reports/issues/P2C.md。

两套场景(kv_sram_if 无 layer 字段 → 后端 B 只支持单层,见 MEM_NOTES):
  <outdir>/a/  后端 A(默认,XMEM):2 层 × 4 head × ctx=128 完整序列
  <outdir>/b/  后端 B(片上 bank):1 层 × 4 head × ctx=128

每套输出:
  kv_cmds.hex   命令流(每条 16 字,tb/mem/tb_kv.sv 解析;w0 位域:
                [2:0] mode,[4] transpose,[5] irq_en,[7] expect_err,
                [11:8] expect_errcode;w1 layer w2 head w3 pos w4 count
                w5 src w6 dst w7 pitch w8 slice w9 readback_words)
  kv_src.hex    APPEND 源数据(逐字,TB 预载到 XMEM)
  kv_exp.hex    READ 输出期望(按命令序串接,每个读 op 的 DST 字流)
  kv_exp_bank{0..3}.hex   后端 B bank 镜像(各 4096 字,{kvt,pos,w})
  kv_exp_xmem.hex         后端 A XMEM KV 区镜像(131072 半字)
  README.txt    场景摘要

用法: python3 scripts/mem_kv_golden.py [--outdir models/kv_golden]
"""
import argparse
import os
import sys

HEADS = 4
CTX = 128
ROW_B = 64
LAYERS_MAX = 2


def lcg_bytes(seed, n):
    s = seed & 0xFFFFFFFF
    out = bytearray()
    for _ in range(n):
        s = (s * 1103515245 + 12345) & 0xFFFFFFFF
        out.append((s >> 16) & 0xFF)
    return bytes(out)


class KVStore:
    def __init__(self, layers):
        self.layers = layers
        self.s = {}
        for la in range(layers):
            for t in range(2):
                for h in range(HEADS):
                    self.s[(la, t, h)] = [bytearray(ROW_B) for _ in range(256)]

    def row(self, la, t, h, pos):
        return self.s[(la, t, h)][pos]

    def append_kv8(self, la, pos, src512):
        for h in range(HEADS):
            self.s[(la, 0, h)][pos] = bytearray(src512[h * 128:h * 128 + 64])
            self.s[(la, 1, h)][pos] = bytearray(src512[h * 128 + 64:h * 128 + 128])

    def clear(self, la, h, pos, count):
        for r in range(pos, pos + count):
            self.s[(la, 0, h)][r] = bytearray(ROW_B)
            self.s[(la, 1, h)][r] = bytearray(ROW_B)


def read_op(store, la, t, h, pos, count, ddoff, dlen, pitch, transpose):
    """§4.9 READ 语义 → DST 字节图像。"""
    if transpose:
        span = dlen * 16
        img = bytearray(span)
        for r in range(count):
            row = store.row(la, t, h, pos + r)
            for d in range(ddoff, ddoff + dlen):
                img[(d - ddoff) * 16 + r] = row[d]
        return img
    pitch_e = pitch if pitch else dlen
    span = (count - 1) * pitch_e + dlen
    img = bytearray(span)
    for r in range(count):
        row = store.row(la, t, h, pos + r)
        base = r * pitch_e
        img[base:base + dlen] = bytes(row[ddoff:ddoff + dlen])
    return img


def pack_words(img, nwords):
    out = []
    for i in range(nwords):
        b = bytes(img[4 * i:4 * i + 4]) + b"\x00\x00\x00"
        out.append(b[0] | (b[1] << 8) | (b[2] << 16) | (b[3] << 24))
    return out


def build(outdir, layers):
    os.makedirs(outdir, exist_ok=True)
    SRC_BASE = 0x40480000
    dst = 0x0000_0800

    blob = {}
    src_words = []
    for la in range(layers):
        blob[la] = [lcg_bytes(0x1000 + 0x10000 * la + p, 512) for p in range(CTX)]
        for p in range(CTX):
            src_words += pack_words(blob[la][p], 128)

    store = KVStore(layers)
    cmds = []
    exp_words = []

    def SL(dd, dl):
        return (dd & 0x3F) | ((dl << 6) & 0xFC0 if dl != 64 else 0)

    def cmd(mode, tr=0, irq=1, exp_err=0, exp_code=0, layer=0, head=0, pos=0,
            count=1, src=0, dst_=0, pitch=0, slice=0, rb=0):
        cmds.append([mode | (tr << 4) | (irq << 5) | (exp_err << 7) |
                     ((exp_code & 0xF) << 8),
                     layer, head, pos, count, src, dst_, pitch, slice,
                     rb, 0, 0, 0, 0, 0, 0])

    clr_cnt = 256 if layers == 2 else CTX
    for la in range(layers):
        for h in range(HEADS):
            cmd(5, layer=la, head=h, pos=0, count=clr_cnt)
            store.clear(la, h, 0, clr_cnt)

    for la in range(layers):
        for p in range(CTX):
            cmd(2, layer=la, pos=p, src=SRC_BASE + la * 0x20000 + p * 512)
        for p in range(CTX):
            store.append_kv8(la, p, blob[la][p])

    NCH = CTX // 16
    for la in range(layers):
        for h in range(HEADS):
            for ch in range(NCH):
                for dt in range(4):
                    cmd(3, layer=la, head=h, pos=ch * 16, count=16,
                        dst_=dst, pitch=16, slice=SL(dt * 16, 16), rb=64)
                    exp_words += pack_words(
                        read_op(store, la, 0, h, ch * 16, 16, dt * 16, 16, 16, 0), 64)
            for ds in range(4):
                for ch in range(NCH):
                    cmd(4, tr=1, layer=la, head=h, pos=ch * 16, count=16,
                        dst_=dst, pitch=0, slice=SL(ds * 16, 16), rb=64)
                    exp_words += pack_words(
                        read_op(store, la, 1, h, ch * 16, 16, ds * 16, 16, 0, 1), 64)

    cmd(5, layer=0, head=1, pos=64, count=32)
    store.clear(0, 1, 64, 32)
    for t in (0, 1):
        for ch in range(2, 6):
            cmd(3 + t, layer=0, head=1, pos=ch * 16, count=16, dst_=dst,
                pitch=0, slice=0, rb=256)
            exp_words += pack_words(
                read_op(store, 0, t, 1, ch * 16, 16, 0, 64, 0, 0), 256)

    cmd(3, exp_err=1, exp_code=1, layer=0, head=0, pos=1000, count=1,
        dst_=dst, pitch=16, slice=SL(0, 16))
    cmd(4, tr=1, exp_err=1, exp_code=1, layer=0, head=0, pos=0, count=17,
        dst_=dst, slice=SL(0, 16))
    cmd(3, exp_err=1, exp_code=1, layer=0, head=0, pos=0, count=16,
        dst_=dst, pitch=16, slice=SL(48, 32))           # DDOFF+DLEN>64
    cmd(0, exp_err=1, exp_code=1, layer=0, head=0, pos=0,
        src=SRC_BASE + 2)

    with open(os.path.join(outdir, "kv_cmds.hex"), "w") as f:
        for c in cmds:
            for w in c:
                f.write("%08x\n" % (w & 0xFFFFFFFF))
    with open(os.path.join(outdir, "kv_src.hex"), "w") as f:
        for w in src_words:
            f.write("%08x\n" % w)
    with open(os.path.join(outdir, "kv_exp.hex"), "w") as f:
        for w in exp_words:
            f.write("%08x\n" % w)

    if layers == 1:
        half = CTX * 16
        for h in range(HEADS):
            with open(os.path.join(outdir, "kv_exp_bank%d.hex" % h), "w") as f:
                for a in range(half * 2):
                    kvt = a // half
                    rem = a % half
                    pos, w = rem // 16, rem % 16
                    row = store.s[(0, kvt, h)][pos]
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
                row = store.s[(la, t, h)][pos]
                f.write("%04x\n" % (row[j] | (row[j + 1] << 8)))

    with open(os.path.join(outdir, "README.txt"), "w") as f:
        f.write("KV golden scenario §4.9: layers=%d heads=%d ctx=%d\n"
                % (layers, HEADS, CTX))
        f.write("cmds=%d (16 words each); read expected words=%d\n"
                % (len(cmds), len(exp_words)))
        f.write("READ DST fixed at 0x%08x (OCSRAM); readback per op.\n" % dst)
    return len(cmds), len(exp_words)


def _load_hex(path):
    out = []
    for line in open(path):
        s = line.strip()
        if not s or s.startswith("//"):
            continue
        out.append(None if "x" in s.lower() else int(s, 16))
    return out


def compare_dir(d):
    """比对 TB 转储与期望镜像(忽略 dump 文件头/大小写;X 视为失配)。"""
    ok = True
    banks = [os.path.join(d, "kv_exp_bank%d.hex" % h) for h in range(HEADS)]
    if os.path.exists(banks[0]):
        for h in range(HEADS):
            dump = os.path.join(d, "kv_dump_bank%d.hex" % h)
            if not os.path.exists(dump):
                print("MISSING dump: %s" % dump); ok = False; continue
            a, b = _load_hex(dump), _load_hex(banks[h])
            n = min(len(a), len(b))
            bad = sum(1 for i in range(n) if a[i] != b[i])
            if len(a) != len(b) or bad:
                print("BANK%d: MISMATCH (%d/%d)" % (h, bad, n)); ok = False
            else:
                print("BANK%d: MATCH (%d words)" % (h, n))
        print("PER-OP expected stream words: %d" %
              len(_load_hex(os.path.join(d, "kv_exp.hex"))))
    else:
        dump = os.path.join(d, "kv_dump_xmem.hex")
        exp = os.path.join(d, "kv_exp_xmem.hex")
        if not os.path.exists(dump):
            print("MISSING dump: %s" % dump); return False
        a, b = _load_hex(dump), _load_hex(exp)
        n = min(len(a), len(b))
        bad = sum(1 for i in range(n) if a[i] != b[i])
        if len(a) != len(b) or bad:
            print("XMEM KV: MISMATCH (%d/%d)" % (bad, n)); ok = False
        else:
            print("XMEM KV: MATCH (%d halfwords)" % n)
    return ok


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--outdir", default="models/kv_golden")
    ap.add_argument("--compare-dir", default=None)
    args = ap.parse_args()
    if args.compare_dir:
        sys.exit(0 if compare_dir(args.compare_dir) else 1)
    na, wa = build(os.path.join(args.outdir, "a"), LAYERS_MAX)
    nb, wb = build(os.path.join(args.outdir, "b"), 1)
    print("backend A: cmds=%d exp_words=%d" % (na, wa))
    print("backend B: cmds=%d exp_words=%d" % (nb, wb))


if __name__ == "__main__":
    main()
