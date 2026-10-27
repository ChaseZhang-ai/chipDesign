#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""cpu_gen_random.py — 随机 RV32IM+AME 测试程序生成器(P2A 差分测试)

生成策略(保证 RTL 与 ISS 可逐指令差分、程序必终止):
- 寄存器 x1..x15 为数据寄存器,先随机播种(含边界值);x28=数据基址,x29..x31 备用。
- 主体为 B 个基本块,块间只允许前向跳转(保证有向无环、必达 ebreak):
    ALU-imm / ALU-reg / 乘除 / load / store / 分支(块内或前向) / AME 指令。
- load/store 地址 = x28 + 4 对齐偏移(0..1020),落在本测试镜像数据区。
- AME 指令偶发插入:cfg/qcfg/ld.w/ld.x/exe(exef)/sync/st.y/st.q,
  字段均合法(exe 忙时由握手反压,CPU 停等;语义两侧模型一致)。
- 尾部:ame.sync + 写自检魔数 + ebreak。

输出:prog.s / prog.hex / trace_ref.txt(ISS 运行结果) / manifest.json

用法: python3 scripts/cpu_gen_random.py --seed 1 --blocks 260 --out-dir tb/cpu/gen/s001
"""

import argparse
import json
import os
import random
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

BOUNDARY = [
    0, 1, -1, 2, -2, 0x7FFFFFFF, -0x80000000, 0x12345678, -0x54321,
    0x55555555, 0xAAAAAAAA, 0x0000FFFF, 0xFFFF0000, 31, 32, -31, 0xFF, 0x80,
]

WEIGHTS = [
    ("alu_imm", 22), ("alu_reg", 22), ("muldiv", 6),
    ("load", 10), ("store", 10),
    ("branch", 14), ("ame", 8), ("csr", 4),
]


class Gen:
    def __init__(self, rng, blocks):
        self.rng = rng
        self.blocks = blocks
        self.lines = []
        self.ame_setup_done = False
        self.lbl_n = 0

    def reg(self, lo=1, hi=15):
        return f"x{self.rng.randint(lo, hi)}"

    def imm(self):
        return str(self.rng.choice(BOUNDARY))

    def emit(self, s):
        self.lines.append("  " + s)

    def alu_imm(self):
        rd = self.reg()
        rs = self.reg()
        op, kind = self.rng.choice([
            ("addi", 0), ("xori", 0), ("ori", 0), ("andi", 0),
            ("slti", 0), ("sltiu", 0), ("slli", 1), ("srli", 1), ("srai", 1),
        ])
        if kind:
            self.emit(f"{op} {rd}, {rs}, {self.rng.randint(0, 31)}")
        else:
            self.emit(f"{op} {rd}, {rs}, {self.imm()}")

    def alu_reg(self):
        rd, r1, r2 = self.reg(), self.reg(), self.reg()
        op = self.rng.choice(["add", "sub", "and", "or", "xor", "sll",
                              "srl", "sra", "slt", "sltu"])
        self.emit(f"{op} {rd}, {r1}, {r2}")

    def muldiv(self):
        rd, r1, r2 = self.reg(), self.reg(), self.reg()
        op = self.rng.choice(["mul", "mulh", "mulhsu", "mulhu",
                              "div", "divu", "rem", "remu"])
        self.emit(f"{op} {rd}, {r1}, {r2}")

    def load(self):
        rd = self.reg()
        off = self.rng.randrange(0, 1021, 4)
        op = self.rng.choice(["lw", "lw", "lb", "lbu", "lh", "lhu"])
        self.emit(f"{op} {rd}, {off}(x28)")

    def store(self):
        rs = self.reg()
        off = self.rng.randrange(0, 1021, 4)
        op = self.rng.choice(["sw", "sw", "sb", "sh"])
        self.emit(f"{op} {rs}, {off}(x28)")

    def branch(self, bid):
        r1, r2 = self.reg(), self.reg()
        op = self.rng.choice(["beq", "bne", "blt", "bge", "bltu", "bgeu"])
        if self.rng.random() < 0.7:
            k = self.rng.randint(1, 3)
            self.lbl_n += 1
            lbl = f".fwd{self.lbl_n}"
            self.emit(f"{op} {r1}, {r2}, {lbl}")
            for _ in range(k - 1):
                self.alu_imm()
            self.emit(f"{lbl}:")
        else:
            tgt = f".blk{bid + 1}" if bid + 1 < self.blocks else ".blk_end"
            self.emit(f"{op} {r1}, {r2}, {tgt}")

    def ame(self):
        if not self.ame_setup_done:
            self.emit("ame.cfg 16, 16")
            self.emit("li x20, 3")
            self.emit("li x21, 65")     # rs2 = S=1 | ROUND=1<<6
            self.emit("ame.qcfg 0, x20, x21")
            self.emit("li x22, 0")      # region0|tsel0<<2
            self.emit("li x23, 5")      # region1|tsel1<<2
            self.emit("li x24, 0")
            self.emit("li x25, 528")    # off16|xsel1<<9
            self.emit("li x26, 1")      # tsel1
            self.ame_setup_done = True
            return
        k = self.rng.choice(["gemv0", "gemv1", "load", "read"])
        if k == "gemv0":
            self.emit("ame.ld.w x22")
            self.emit("ame.ld.x x24")
            self.emit(f"ame.{self.rng.choice(['exef', 'exe'])} x24")
            self.emit("ame.sync")
        elif k == "gemv1":
            self.emit("ame.ld.w x23")
            self.emit("ame.ld.x x25")
            self.emit(f"ame.{self.rng.choice(['exef', 'exe'])} x26")
            self.emit("ame.sync")
        elif k == "load":
            self.emit(f"ame.ld.w x{self.rng.choice([22, 23])}")
            self.emit(f"ame.ld.x x{self.rng.choice([24, 25])}")
        else:
            self.emit("ame.sync")
            self.emit(f"li x27, {self.rng.randint(0, 15)}")
            self.emit(f"ame.{self.rng.choice(['st.y', 'st.q'])} x27, x{self.rng.randint(1, 15)}")

    def csr(self):
        rd = self.reg()
        k = self.rng.choice(["minstret", "minstret", "flags_rw", "mscratch"])
        if k == "minstret":
            self.emit(f"csrr {rd}, minstret")
        elif k == "mscratch":
            op = self.rng.choice(["csrr", "csrs", "csrc"])
            self.emit(f"{op} mscratch, {rd}" if op != "csrr" else f"csrr {rd}, mscratch")
        elif k == "flags_rw":
            self.emit(f"csrr {rd}, flags")

    def generate(self):
        self.lines.append("# 随机生成(cpu_gen_random.py)")
        self.lines.append("  .org 0x10000")
        self.lines.append("boot:")
        self.lines.append("  j start")
        self.lines.append("  .org 0x0")
        self.lines.append("start:")
        for i in range(1, 16):
            self.emit(f"li x{i}, {self.rng.choice(BOUNDARY)}")
        self.emit("li x28, 0x4000")
        for b in range(self.blocks):
            self.lines.append(f".blk{b}:")
            for _ in range(self.rng.randint(3, 8)):
                tot = sum(w for _, w in WEIGHTS)
                pick = self.rng.randrange(tot)
                acc = 0
                for name, w in WEIGHTS:
                    acc += w
                    if pick < acc:
                        getattr(self, name)(b) if name == "branch" else getattr(self, name)()
                        break
        self.lines.append(".blk_end:")
        self.emit("ame.sync")
        self.emit("li x28, 0x1FFF0")
        self.emit("li x29, 0x600D")
        self.emit("sw x29, 0(x28)")
        self.emit("ebreak")
        return "\n".join(self.lines) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--blocks", type=int, default=260)
    ap.add_argument("--out-dir", required=True)
    args = ap.parse_args()

    rng = random.Random(args.seed)
    src = Gen(rng, args.blocks).generate()

    os.makedirs(args.out_dir, exist_ok=True)
    s_path = os.path.join(args.out_dir, "prog.s")
    h_path = os.path.join(args.out_dir, "prog.hex")
    t_path = os.path.join(args.out_dir, "trace_ref.txt")
    with open(s_path, "w", encoding="utf-8") as f:
        f.write(src)

    r = subprocess.run([sys.executable, os.path.join(HERE, "cpu_asm.py"),
                        s_path, "-o", h_path], capture_output=True, text=True)
    if r.returncode:
        print(r.stderr, file=sys.stderr)
        return 1
    r = subprocess.run([sys.executable, os.path.join(HERE, "cpu_iss.py"),
                        h_path, "-o", t_path, "--max-steps", "500000"],
                       capture_output=True, text=True)
    if r.returncode:
        print(r.stderr, file=sys.stderr)
        return 1
    n_instr = sum(1 for _ in open(t_path))
    with open(os.path.join(args.out_dir, "manifest.json"), "w") as f:
        json.dump({"seed": args.seed, "blocks": args.blocks,
                   "committed": n_instr}, f)
    print(f"cpu_gen_random: seed={args.seed} -> {args.out_dir} ({n_instr} committed instrs)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
