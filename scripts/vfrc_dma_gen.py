#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""vfrc_dma_gen.py — P3C DMA 随机压力场景 + §4.5 逐字参考模型

生成 320 笔随机 2D 拷贝(背靠背)+ 并发标记 + 错误路径 + ABORT + BUSY 忽略,
并按 §4.5 伪代码逐字生成期望读地址流/写地址数据流与最终存储镜像。

数据图案(与 TB 共享的纯函数):
    word(addr) = ((addr>>2) * 0x9E3779B9 + 0x7F4A7C15) mod 2^32

区域(互不重叠,XMEM 8MB 内):
    SRC0 = 0x4060_0000  SRC1 = 0x4068_0000
    DST0 = 0x4070_0000  DST1 = 0x4078_0000
    CPU  XMEM  scratch = 0x4010_0000 (64 字,并发 CPU 读用)
    CPU  OCSRAM scratch= 0x0000_0800 (DMA 不用;CPU 并发读写)
    OCSRAM DMA dst     = 0x0000_0000..0x0000_07FF
    AME WBUF dst       = 0x2000_1000..(<=1KB)

输出(目录):
  dma_ops.hex      每 op 16 字:
                   w0 flags: [0]irq [1]sfix [2]dfix [3]exp_err
                             [7:4]exp_code [8]check_stream [9]final_check
                             [10]busy_ignore [11]conc
                   w1 src w2 dst w3 xcnt w4 ycnt w5 sp w6 dp
                   w7 abort_after(周期,0=无)
  dma_rd_addr.hex / dma_rd_data.hex   期望读流
  dma_wr_addr.hex / dma_wr_data.hex   期望写流
  dma_pre_addr.hex / dma_pre_data.hex 预载(源地址 + CPU scratch)
  dma_final_addr.hex / dma_final_data.hex  最终镜像(去重后)
  dma_counts.hex   [nops, nrd, nwr, npre, nfinal]
  dma_meta.txt
"""
import argparse
import os
import random

M32 = 0xFFFFFFFF


def word_of(addr):
    return (((addr >> 2) * 0x9E3779B9 + 0x7F4A7C15) & M32)


SRC_REGIONS = [(0x4060_0000, 0x0008_0000), (0x4068_0000, 0x0008_0000)]
DST_REGIONS = [(0x4070_0000, 0x0008_0000), (0x4078_0000, 0x0008_0000)]
OC_LO, OC_HI = 0x0000_0000, 0x0000_0800
CPU_OC = 0x0000_0800
CPU_XM = 0x4010_0000
WBUF_BASE = 0x2000_1000
ERR_SCRATCH = 0x407C_0000
N_OPS = 320


def gen_ops(seed=0x5EED_2026):
    rng = random.Random(seed)
    ops = []
    for i in range(N_OPS):
        kind = rng.random()
        xcnt = rng.randint(1, 64)
        ycnt = rng.randint(1, 8)
        sfix = 1 if rng.random() < 0.08 else 0
        dfix = 1 if rng.random() < 0.08 else 0
        if kind < 0.70:
            dkind = "xm"
        elif kind < 0.85:
            dkind = "oc"
        else:
            dkind = "wbuf"

        sp = 0 if rng.random() < 0.5 else xcnt * 4 + 4 * rng.randint(0, 4)
        dp = 0 if rng.random() < 0.5 else xcnt * 4 + 4 * rng.randint(0, 4)
        spe = sp if sp else xcnt * 4
        dpe = dp if dp else xcnt * 4

        s_ext = xcnt * 4 if sfix else (ycnt - 1) * spe + xcnt * 4
        d_ext = xcnt * 4 if dfix else (ycnt - 1) * dpe + xcnt * 4

        sbase, ssize = SRC_REGIONS[rng.randint(0, 1)]
        off = rng.randint(0, (ssize - s_ext) // 4) * 4
        src = sbase + off

        if dkind == "xm":
            dbase, dsize = DST_REGIONS[rng.randint(0, 1)]
            if dsize - d_ext < 0:
                dkind = "oc"
            else:
                off = rng.randint(0, (dsize - d_ext) // 4) * 4
                dst = dbase + off
        if dkind == "oc":
            if OC_HI - OC_LO - d_ext < 0:
                ycnt = 1
                if dp and (xcnt * 4) > (OC_HI - OC_LO):
                    xcnt = (OC_HI - OC_LO) // 4
                d_ext = xcnt * 4
                dp = 0
            off = rng.randint(0, (OC_HI - OC_LO - d_ext) // 4) * 4
            dst = OC_LO + off
        if dkind == "wbuf":
            if d_ext > 1024:
                ycnt = 1
                if dp:
                    xcnt = 256
                d_ext = xcnt * 4
                dp = 0
            dst = WBUF_BASE
        ops.append(dict(src=src, dst=dst, xcnt=xcnt, ycnt=ycnt, sp=sp, dp=dp,
                        sfix=sfix, dfix=dfix,
                        irq=int(rng.random() < 0.5),
                        dkind=dkind, conc=int(rng.random() < 0.10),
                        busy_ignore=0, abort_after=0,
                        exp_err=0, exp_code=0, check_stream=1,
                        final_check=1))
    def clean(**kw):
        o = dict(src=SRC_REGIONS[0][0], dst=DST_REGIONS[0][0], xcnt=8, ycnt=1,
                 sp=0, dp=0, sfix=0, dfix=0, irq=0, dkind="xm", conc=0,
                 busy_ignore=0, abort_after=0, exp_err=0, exp_code=0,
                 check_stream=1, final_check=1)
        o.update(kw)
        return o

    def err(**kw):
        o = clean(exp_err=1, exp_code=1, check_stream=0, final_check=0,
                  dst=ERR_SCRATCH, conc=0, irq=1)
        o.update(kw)
        return o

    ops.append(clean(src=0x4060_0000, dst=0x4078_0000, xcnt=64, ycnt=16,
                     sp=0, dp=0, busy_ignore=1))
    ops.append(err(src=SRC_REGIONS[0][0] + 2, exp_code=1))
    ops.append(err(dst=DST_REGIONS[0][0] + 2, exp_code=1))
    ops.append(err(sp=6, exp_code=1))
    ops.append(err(xcnt=0, exp_code=1))                           # XCNT=0
    ops.append(err(ycnt=0, exp_code=1))                           # YCNT=0
    ops.append(err(dst=0x2000_4000, exp_code=2))
    ops.append(err(dst=0x0001_0000, xcnt=4, exp_code=2))
    ops.append(clean(src=0x4060_0000, dst=ERR_SCRATCH, xcnt=64, ycnt=64,
                     sp=0, dp=0, abort_after=500, exp_err=1, exp_code=3,
                     check_stream=0, final_check=0, irq=1))
    return ops


def build(outdir):
    ops = gen_ops()
    rd_addr, rd_data = [], []
    wr_addr, wr_data = [], []
    final = {}
    pre = {}

    for o in ops:
        if o["exp_err"] or not o["check_stream"]:
            continue
        xc, yc = o["xcnt"], o["ycnt"]
        spe = o["sp"] if o["sp"] else xc * 4
        dpe = o["dp"] if o["dp"] else xc * 4
        for y in range(yc):
            for x in range(xc):
                s = o["src"] + (0 if o["sfix"] else y * spe + x * 4)
                d = o["dst"] + (0 if o["dfix"] else y * dpe + x * 4)
                v = word_of(s)
                rd_addr.append(s)
                rd_data.append(v)
                wr_addr.append(d)
                wr_data.append(v)
                pre[s] = v
                if o["final_check"]:
                    final[d] = v
    for i in range(64):
        a = CPU_XM + 4 * i
        pre[a] = word_of(a)

    os.makedirs(outdir, exist_ok=True)

    def wr_hex(name, vals, fmt="%08x\n"):
        with open(os.path.join(outdir, name), "w") as f:
            for v in vals:
                f.write(fmt % (v & M32))

    op_words = []
    for o in ops:
        flags = (o["irq"] | (o["sfix"] << 1) | (o["dfix"] << 2) |
                 (o["exp_err"] << 3) | ((o["exp_code"] & 0xF) << 4) |
                 (o["check_stream"] << 8) | (o["final_check"] << 9) |
                 (o["busy_ignore"] << 10) | (o["conc"] << 11))
        op_words.append([flags, o["src"], o["dst"], o["xcnt"], o["ycnt"],
                         o["sp"], o["dp"], o["abort_after"],
                         0, 0, 0, 0, 0, 0, 0, 0])
    wr_hex("dma_ops.hex", [w for rec in op_words for w in rec])
    wr_hex("dma_rd_addr.hex", rd_addr)
    wr_hex("dma_rd_data.hex", rd_data)
    wr_hex("dma_wr_addr.hex", wr_addr)
    wr_hex("dma_wr_data.hex", wr_data)
    pre_a = sorted(pre.keys())
    wr_hex("dma_pre_addr.hex", pre_a)
    wr_hex("dma_pre_data.hex", [pre[a] for a in pre_a])
    fin_a = sorted(final.keys())
    wr_hex("dma_final_addr.hex", fin_a)
    wr_hex("dma_final_data.hex", [final[a] for a in fin_a])
    wr_hex("dma_counts.hex", [len(ops), len(rd_addr), len(wr_addr),
                              len(pre_a), len(fin_a)])

    with open(os.path.join(outdir, "dma_meta.txt"), "w") as f:
        f.write("ops=%d\n" % len(ops))
        f.write("words=%d\n" % len(rd_addr))
        f.write("clean_ops=%d\n" % sum(1 for o in ops
                                       if not o["exp_err"] and o["check_stream"]))
        f.write("err_ops=%d\n" % sum(1 for o in ops if o["exp_err"]))
        f.write("conc_ops=%d\n" % sum(1 for o in ops if o["conc"]))
        f.write("final_words=%d\npreload_words=%d\n" % (len(fin_a), len(pre_a)))
        f.write("pattern=word(addr)=((addr>>2)*0x9E3779B9+0x7F4A7C15)&0xFFFFFFFF\n")
    return len(ops), len(rd_addr), len(wr_addr), len(pre_a), len(fin_a)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--outdir", default="build/p3c/golden/dma")
    args = ap.parse_args()
    r = build(args.outdir)
    print("DMA 场景: ops=%d read_words=%d write_words=%d preload=%d final=%d"
          % r)


if __name__ == "__main__":
    main()
