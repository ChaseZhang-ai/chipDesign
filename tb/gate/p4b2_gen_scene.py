#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""p4b2_gen_scene.py — P4B2 裁剪 decode 场景生成(门仿 vs RTL v0.3 一致性)

单一来源:本脚本调用 scripts/build_hex.py 汇编 tb/gate/p4b2_decode.s,
并生成 XMEM 稀疏镜像 p4b2_scene.hex(格式与 vfrd_golden.py emit_scene 相同:
半字索引 @addr 行,pmem[xmem_a[22:1]] 直接 $readmemh)。

场景布局(器件偏移 = 系统地址 - 0x4000_0000):
  0x0000_0000  主程序(p4b2_decode.hex,补零到 1024 word = loader 拷贝量)
  0x0002_0000  权重:16 行 × 256B,行内前 KT=16B 有效:w[r][k]=((5r+3k)&3)+1
  0x0004_0000  x 向量 256B:x[k]=((13k+5)&7)+1
  0x0004_1000  M:16 word 全 1(qcfg 由程序读取;S=4/ROUND=1 在程序内硬编码)

用法:python3 tb/gate/p4b2_gen_scene.py   # 产物落 tb/gate/build/
"""
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BUILD = os.path.join(ROOT, "tb", "gate", "build")
PROG_S = os.path.join(ROOT, "tb", "gate", "p4b2_decode.s")

KT = 16
ROWS = 16
ROW_STRIDE = 256

OFF_PROG = 0x0000_0000
OFF_W = 0x0002_0000
OFF_X = 0x0004_0000
OFF_M = 0x0004_1000


def put_words(sp, addr, words):
    for i, w in enumerate(words):
        w = int(w) & 0xFFFFFFFF
        sp[(addr + 4 * i) >> 1] = w & 0xFFFF
        sp[((addr + 4 * i) >> 1) + 1] = (w >> 16) & 0xFFFF


def put_bytes(sp, addr, data):
    for i, b in enumerate(bytes(data)):
        a = addr + i
        idx = a >> 1
        cur = sp.get(idx, 0)
        sp[idx] = (cur & 0x00FF) | (b << 8) if (a & 1) else (cur & 0xFF00) | b


def emit_sparse(path, sp):
    with open(path, "w") as f:
        prev = None
        for a in sorted(sp):
            if prev is None or a != prev + 1:
                f.write(f"@{a:06X}\n")
            f.write(f"{sp[a]:04X}\n")
            prev = a


def main():
    os.makedirs(BUILD, exist_ok=True)
    prog_hex = os.path.join(BUILD, "p4b2_prog.hex")
    cmd = [sys.executable, os.path.join(ROOT, "scripts", "build_hex.py"), "asm",
           "-o", prog_hex, "--base", "0x0",
           "--text-limit", "4096", "--data-limit", "512", PROG_S]
    print("[p4b2]", " ".join(cmd))
    subprocess.run(cmd, check=True)

    words = []
    with open(prog_hex) as f:
        for ln in f:
            ln = ln.split("//")[0].strip()
            if ln:
                words.append(int(ln, 16))
    assert len(words) <= 1024, f"program too large: {len(words)} words"
    words += [0] * (1024 - len(words))
    print(f"[p4b2] prog = {len(words) - (1024 - len(words))} words (+pad to 1024)")

    sp = {}
    put_words(sp, OFF_PROG, words)

    wbytes = bytearray(ROWS * ROW_STRIDE)
    for r in range(ROWS):
        for k in range(KT):
            wbytes[r * ROW_STRIDE + k] = ((5 * r + 3 * k) & 3) + 1
    put_bytes(sp, OFF_W, wbytes)

    xbytes = bytearray(256)
    for k in range(256):
        xbytes[k] = ((13 * k + 5) & 7) + 1
    put_bytes(sp, OFF_X, xbytes)

    put_words(sp, OFF_M, [1] * 16)

    out = os.path.join(BUILD, "p4b2_scene.hex")
    emit_sparse(out, sp)
    print(f"[p4b2] scene -> {out} ({len(sp)} halfwords)")


if __name__ == "__main__":
    main()
