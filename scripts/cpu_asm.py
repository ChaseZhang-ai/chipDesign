#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""cpu_asm.py — 小型 RV32IM+Zicsr+AME(custom-0) 汇编器子集(P2A 自用)

项目内无 riscv-gcc(任务书约定),本汇编器把 tb/cpu/asm/*.s 汇编成
$readmemh 兼容 hex(字编址 @addr 指令 + 每行一个 32-bit 字)。

支持语法
--------
- 注释: `#` 或 `//` 到行尾;标签 `name:`;常量 `.equ name, expr`
- 段定位: `.org addr`(字节地址,自动 4 对齐)
- 数据: `.word v1, v2, ...`(可引 .equ/标签立即数)
- 立即数: 十进制 / 0x 十六进制 / 负数 / .equ 名 / 标签(仅 branch/jal/la)
- 指令: RV32I 全集 + M 扩展 + Zicsr(csrrw/s/c + 立数形式 + csrr 伪指令)
        + system(ecall/ebreak/mret/wfi/fence/fence.i)
- 伪指令: li / la / mv / nop / j / call / ret / beqz / bnez
- AME(字段语义见 docs/AME_ISA.md §1.1/§7;本工具约定:
    - ame.cfg  <n_eff>, <kt>              I 型, imm=n_eff|kt<<5
    - ame.qcfg <idx>, <rsM>, <rsS>        rd 字段 = idx(通道号,立即数)
    - ame.ld.w <rs> / ame.ld.x <rs> / ame.exe <rs> / ame.exef <rs>
        rs = 预先装好打包字段(region|tsel<<2 / off|xsel<<9 / tsel)的寄存器
    - ame.st.y <rs_idx>, <rd> / ame.st.q <rs_idx>, <rd>
        rs_idx = 预装了 Y 索引的寄存器(AME 按 req_rs1 值[4:0] 取索引)
    - ame.sync
  与 §7 立即数形式的差别仅在汇编语法(寄存器显式化),机器码逐字段一致。

输出
----
- hex: 字编址 $readmemh 镜像(空洞用 @addr 跳过);BOOTROM 复位向量程序
  由测试源内 `.org 0x10000` 段提供。
- listing(-l): 地址、机器码、源行,便于人工核对。

用法
----
python3 scripts/cpu_asm.py prog.s -o prog.hex [-l prog.lst]
python3 scripts/cpu_asm.py --selftest        # 编码单元自测(含 AME_ISA §7 样例)
"""

import re
import sys

REG_NAMES = {f"x{i}": i for i in range(32)}
ABI_NAMES = {
    "zero": 0, "ra": 1, "sp": 2, "gp": 3, "tp": 4,
    "t0": 5, "t1": 6, "t2": 7, "s0": 8, "fp": 8, "s1": 9,
    "a0": 10, "a1": 11, "a2": 12, "a3": 13, "a4": 14, "a5": 15,
    "a6": 16, "a7": 17, "s2": 18, "s3": 19, "s4": 20, "s5": 21,
    "s6": 22, "s7": 23, "s8": 24, "s9": 25, "s10": 26, "s11": 27,
    "t3": 28, "t4": 29, "t5": 30, "t6": 31,
}
REG = {**REG_NAMES, **ABI_NAMES}

CSR_NAMES = {
    "mstatus": 0x300, "mtvec": 0x305, "mscratch": 0x340,
    "mepc": 0x341, "mcause": 0x342, "flags": 0x7C2,
    "mcycle": 0xB00, "mcycleh": 0xB80, "minstret": 0xB02, "minstreth": 0xB82,
    "cycle": 0xC00, "cycleh": 0xC80, "instret": 0xC02, "instreth": 0xC82,
}

OPCODE = {
    "lui": 0x37, "auipc": 0x17, "jal": 0x6F, "jalr": 0x67,
    "branch": 0x63, "load": 0x03, "store": 0x23,
    "op_imm": 0x13, "op": 0x33, "fence": 0x0F, "system": 0x73,
    "ame": 0x0B,
}

F3_BRANCH = {"beq": 0, "bne": 1, "blt": 4, "bge": 5, "bltu": 6, "bgeu": 7}
F3_LOAD   = {"lb": 0, "lh": 1, "lw": 2, "lbu": 4, "lhu": 5}
F3_STORE  = {"sb": 0, "sh": 1, "sw": 2}
F3_OP_IMM = {"addi": 0, "slli": 1, "slti": 2, "sltiu": 3,
             "xori": 4, "srli": 5, "srai": 5, "ori": 6, "andi": 7}
F3_OP     = {"add": 0, "sll": 1, "slt": 2, "sltu": 3, "xor": 4,
             "srl": 5, "sub": 0, "sra": 5, "or": 6, "and": 7}
F3_OP_F7  = {("add", 0): 0x00, ("sub", 0): 0x20, ("sll", 1): 0x00,
             ("slt", 2): 0x00, ("sltu", 3): 0x00, ("xor", 4): 0x00,
             ("srl", 5): 0x00, ("sra", 5): 0x20, ("or", 6): 0x00, ("and", 7): 0x00}
F3_MULDIV = {"mul": 0, "mulh": 1, "mulhsu": 2, "mulhu": 3,
             "div": 4, "divu": 5, "rem": 6, "remu": 7}

AME_F7 = {"qcfg": 0x01, "ld.w": 0x02, "ld.x": 0x03,
          "exe": 0x04, "exef": 0x05, "st.y": 0x06, "st.q": 0x07, "sync": 0x08}


class AsmError(Exception):
    pass


def parse_int(tok):
    tok = tok.strip()
    neg = tok.startswith("-")
    if neg:
        tok = tok[1:]
    if tok.lower().startswith("0x"):
        v = int(tok, 16)
    else:
        v = int(tok, 10)
    return -v if neg else v


def reg(tok):
    tok = tok.strip().lower()
    if tok not in REG:
        raise AsmError(f"bad register '{tok}'")
    return REG[tok]


def enc_r(f7, rs2, rs1, f3, rd, op):
    return ((f7 & 0x7F) << 25) | ((rs2 & 0x1F) << 20) | ((rs1 & 0x1F) << 15) \
         | ((f3 & 0x7) << 12) | ((rd & 0x1F) << 7) | (op & 0x7F)


def enc_i(imm, rs1, f3, rd, op):
    return ((imm & 0xFFF) << 20) | ((rs1 & 0x1F) << 15) | ((f3 & 0x7) << 12) \
         | ((rd & 0x1F) << 7) | (op & 0x7F)


def enc_s(imm, rs2, rs1, f3, op):
    imm &= 0xFFF
    return (((imm >> 5) & 0x7F) << 25) | ((rs2 & 0x1F) << 20) | ((rs1 & 0x1F) << 15) \
         | ((f3 & 0x7) << 12) | ((imm & 0x1F) << 7) | (op & 0x7F)


def enc_b(imm, rs2, rs1, f3, op):
    imm &= 0x1FFF
    return (((imm >> 12) & 0x1) << 31) | (((imm >> 5) & 0x3F) << 25) \
         | ((rs2 & 0x1F) << 20) | ((rs1 & 0x1F) << 15) | ((f3 & 0x7) << 12) \
         | (((imm >> 1) & 0xF) << 8) | (((imm >> 11) & 0x1) << 7) | (op & 0x7F)


def enc_u(imm, rd, op):
    return ((imm & 0xFFFFF) << 12) | ((rd & 0x1F) << 7) | (op & 0x7F)


def enc_j(imm, rd, op):
    imm &= 0x1FFFFF
    return (((imm >> 20) & 0x1) << 31) | (((imm >> 1) & 0x3FF) << 21) \
         | (((imm >> 11) & 0x1) << 20) | (((imm >> 12) & 0xFF) << 12) \
         | ((rd & 0x1F) << 7) | (op & 0x7F)


class Assembler:
    def __init__(self):
        self.labels = {}
        self.equ = {}
        self.items = []       # (addr, kind, payload, lineno, srcline)
        self.pc = 0

    def strip_comment(self, line):
        for c in ("#", "//"):
            i = line.find(c)
            if i >= 0:
                line = line[:i]
        return line.strip()

    def tokens(self, s):
        return [t for t in re.split(r"[,\s]+", s) if t]

    def value(self, tok):
        """立即数求值(.equ / 数字);标签不行(需在第二遍按 pc 相对处理)。"""
        tok = tok.strip()
        if tok in self.equ:
            return self.equ[tok]
        try:
            return parse_int(tok)
        except ValueError:
            raise AsmError(f"unknown symbol '{tok}'")

    def pass1(self, path):
        with open(path, encoding="utf-8") as f:
            lines = f.readlines()
        for ln, raw in enumerate(lines, 1):
            line = self.strip_comment(raw)
            while True:
                m = re.match(r"^([A-Za-z_.$][\w.$]*)\s*:\s*(.*)$", line)
                if not m:
                    break
                label = m.group(1)
                if label in self.labels:
                    raise AsmError(f"line {ln}: duplicate label '{label}'")
                self.labels[label] = self.pc
                line = m.group(2).strip()
            if not line:
                continue
            parts = self.tokens(line)
            op = parts[0].lower()
            args = parts[1:]
            if op == ".equ":
                name, val = args[0], self.value(args[1])
                self.equ[name] = val
                continue
            if op == ".org":
                self.pc = self.value(args[0])
                continue
            if op == ".word":
                for a in args:
                    self.items.append((self.pc, "word", a, ln, raw.rstrip()))
                    self.pc += 4
                continue
            n = self.instr_size(op, args)
            self.items.append((self.pc, "instr", (op, args), ln, raw.rstrip()))
            self.pc += 4 * n

    def instr_size(self, op, args):
        if op == "li" or op == "la":
            return 2
        return 1

    def resolve_label(self, tok):
        tok = tok.strip()
        if tok in self.labels:
            return self.labels[tok]
        if tok in self.equ:
            return self.equ[tok]
        try:
            return parse_int(tok)
        except ValueError:
            raise AsmError(f"undefined label '{tok}'")

    def csr_num(self, tok):
        tok = tok.strip().lower()
        if tok in CSR_NAMES:
            return CSR_NAMES[tok]
        return parse_int(tok)

    def asm_instr(self, op, args, pc, ln):
        """返回 1 或 2 条机器码(list[int])。"""
        def need(n):
            if len(args) != n:
                raise AsmError(f"line {ln}: '{op}' expects {n} args, got {len(args)}")

        if op == "nop":
            need(0)
            return [enc_i(0, 0, 0, 0, OPCODE["op_imm"])]
        if op == "mv":
            need(2)
            return [enc_i(0, reg(args[1]), 0, reg(args[0]), OPCODE["op_imm"])]
        if op in ("li", "la"):
            need(2)
            rd = reg(args[0])
            val = self.resolve_label(args[1]) if op == "la" else self.value_or_sym(args[1])
            val &= 0xFFFFFFFF
            lo = val & 0xFFF
            lo_s = lo - 0x1000 if lo & 0x800 else lo
            hi = ((val - lo_s) & 0xFFFFFFFF) >> 12
            hi &= 0xFFFFF
            return [enc_u(hi, rd, OPCODE["lui"]),
                    enc_i(lo, rd, 0, rd, OPCODE["op_imm"])]
        if op == "j":
            need(1)
            off = self.resolve_label(args[0]) - pc
            return [enc_j(off, 0, OPCODE["jal"])]
        if op == "call":
            need(1)
            off = self.resolve_label(args[0]) - pc
            return [enc_j(off, 1, OPCODE["jal"])]
        if op == "ret":
            need(0)
            return [enc_i(0, 1, 0, 0, OPCODE["jalr"])]
        if op in ("beqz", "bnez"):
            need(2)
            off = self.resolve_label(args[1]) - pc
            f3 = 0 if op == "beqz" else 1
            return [enc_b(off, 0, reg(args[0]), f3, OPCODE["branch"])]
        if op == "csrr":
            need(2)
            return [enc_i(0, 0, 2, reg(args[0]), OPCODE["system"])
                    | (self.csr_num(args[1]) << 20)]

        # ---- RV32I ----
        if op in ("lui", "auipc"):
            need(2)
            imm = self.value(args[1])
            return [enc_u(imm, reg(args[0]), OPCODE["lui" if op == "lui" else "auipc"])]
        if op == "jal":
            if len(args) == 1:
                off = self.resolve_label(args[0]) - pc
                return [enc_j(off, 1, OPCODE["jal"])]
            need(2)
            off = self.resolve_label(args[1]) - pc
            return [enc_j(off, reg(args[0]), OPCODE["jal"])]
        if op == "jalr":
            if len(args) == 1:
                return [enc_i(0, reg(args[0]), 0, 1, OPCODE["jalr"])]
            need(3)
            return [enc_i(self.value(args[2]), reg(args[1]), 0,
                          reg(args[0]), OPCODE["jalr"])]
        if op in F3_BRANCH:
            need(3)
            off = self.resolve_label(args[2]) - pc
            return [enc_b(off, reg(args[1]), reg(args[0]),
                          F3_BRANCH[op], OPCODE["branch"])]
        if op in F3_LOAD:
            rd, rs1, imm = self.mem_args(args, ln)
            return [enc_i(imm, rs1, F3_LOAD[op], rd, OPCODE["load"])]
        if op in F3_STORE:
            rs2, rs1, imm = self.mem_args_store(args, ln)
            return [enc_s(imm, rs2, rs1, F3_STORE[op], OPCODE["store"])]
        if op in F3_OP_IMM:
            need(3)
            imm = self.value(args[2])
            f3 = F3_OP_IMM[op]
            if op == "slli":
                if imm & ~0x1F:
                    raise AsmError(f"line {ln}: shamt out of range")
            if op in ("srli", "srai"):
                if imm & ~0x1F:
                    raise AsmError(f"line {ln}: shamt out of range")
                f7 = 0x00 if op == "srli" else 0x20
                return [enc_i((f7 << 5) | imm, reg(args[1]), f3,
                              reg(args[0]), OPCODE["op_imm"])]
            return [enc_i(imm, reg(args[1]), f3, reg(args[0]), OPCODE["op_imm"])]
        if op in F3_OP:
            need(3)
            f3 = F3_OP[op]
            if op in ("add", "sll", "slt", "sltu", "xor", "srl", "or", "and"):
                f7 = 0x00
            else:
                f7 = 0x20  # sub / sra
            return [enc_r(f7, reg(args[2]), reg(args[1]), f3,
                          reg(args[0]), OPCODE["op"])]
        if op in F3_MULDIV:
            need(3)
            return [enc_r(0x01, reg(args[2]), reg(args[1]), F3_MULDIV[op],
                          reg(args[0]), OPCODE["op"])]
        if op in ("fence", "fence.i"):
            if op == "fence":
                return [enc_i(0, 0, 0, 0, OPCODE["fence"])]
            return [enc_i(1, 0, 1, 0, OPCODE["fence"])]
        if op in ("ecall", "ebreak", "mret", "wfi"):
            need(0)
            imm = {"ecall": 0x000, "ebreak": 0x001, "mret": 0x302, "wfi": 0x105}[op]
            return [enc_i(imm, 0, 0, 0, OPCODE["system"])]

        # ---- Zicsr ----
        if op in ("csrw", "csrs", "csrc", "csrwi", "csrsi", "csrci"):
            f3 = {"csrw": 1, "csrs": 2, "csrc": 3,
                  "csrwi": 5, "csrsi": 6, "csrci": 7}[op]
            need(2)
            src = self.value(args[1]) if f3 >= 5 else reg(args[1])
            return [enc_i(0, src & 0x1F, f3, 0, OPCODE["system"])
                    | (self.csr_num(args[0]) << 20)]
        if op in ("csrrw", "csrrs", "csrrc", "csrrwi", "csrrsi", "csrrci"):
            need(3)
            f3 = {"csrrw": 1, "csrrs": 2, "csrrc": 3,
                  "csrrwi": 5, "csrrsi": 6, "csrrci": 7}[op]
            src = self.value(args[2]) if f3 >= 5 else reg(args[2])
            return [enc_i(0, src & 0x1F, f3, reg(args[0]), OPCODE["system"])
                    | (self.csr_num(args[1]) << 20)]

        # ---- AME custom-0 ----
        if op == "ame.cfg":
            need(2)
            n_eff, kt = self.value(args[0]), self.value(args[1])
            imm = (n_eff & 0x1F) | ((kt & 0x1F) << 5)
            return [enc_i(imm, 0, 0x0, 0, OPCODE["ame"])]
        if op == "ame.qcfg":
            need(3)
            idx = self.value(args[0])
            return [enc_r(AME_F7["qcfg"], reg(args[2]), reg(args[1]), 0x1,
                          idx & 0x1F, OPCODE["ame"])]
        if op in ("ame.ld.w", "ame.ld.x", "ame.exe", "ame.exef"):
            need(1)
            f3map = {"ame.ld.w": 0x2, "ame.ld.x": 0x3, "ame.exe": 0x4, "ame.exef": 0x4}
            f7map = {"ame.ld.w": 0x02, "ame.ld.x": 0x03, "ame.exe": 0x04, "ame.exef": 0x05}
            return [enc_r(f7map[op], 0, reg(args[0]), f3map[op], 0, OPCODE["ame"])]
        if op in ("ame.st.y", "ame.st.q"):
            need(2)
            f3 = 0x5 if op == "ame.st.y" else 0x6
            f7 = 0x06 if op == "ame.st.y" else 0x07
            return [enc_r(f7, 0, reg(args[0]), f3, reg(args[1]), OPCODE["ame"])]
        if op == "ame.sync":
            need(0)
            return [enc_r(AME_F7["sync"], 0, 0, 0x7, 0, OPCODE["ame"])]

        raise AsmError(f"line {ln}: unknown instruction '{op}'")

    def value_or_sym(self, tok):
        tok = tok.strip()
        if tok in self.equ:
            return self.equ[tok]
        if tok in self.labels:
            return self.labels[tok]
        return parse_int(tok)

    def mem_args(self, args, ln):
        """lw rd, imm(rs) 或 lw rd, sym(绝对地址→li 由测试自己处理,这里只支持 off(reg))"""
        if len(args) != 2:
            raise AsmError(f"line {ln}: mem op expects 'rd, off(rs)'")
        rd = reg(args[0])
        m = re.match(r"^(.*)\(\s*([xa-z0-9]+)\s*\)$", args[1].strip())
        if not m:
            raise AsmError(f"line {ln}: mem operand '{args[1]}' not off(reg)")
        off = self.value(m.group(1)) if m.group(1).strip() else 0
        return rd, reg(m.group(2)), off

    def mem_args_store(self, args, ln):
        if len(args) != 2:
            raise AsmError(f"line {ln}: store expects 'rs2, off(rs1)'")
        rs2 = reg(args[0])
        m = re.match(r"^(.*)\(\s*([xa-z0-9]+)\s*\)$", args[1].strip())
        if not m:
            raise AsmError(f"line {ln}: mem operand '{args[1]}' not off(reg)")
        off = self.value(m.group(1)) if m.group(1).strip() else 0
        return rs2, reg(m.group(2)), off

    def assemble(self, path):
        self.pass1(path)
        words = {}
        listing = []
        for addr, kind, payload, ln, src in self.items:
            if kind == "word":
                val = self.value_or_sym(payload)
                words[addr >> 2] = val & 0xFFFFFFFF
                listing.append(f"{addr:08x}  {val & 0xFFFFFFFF:08x}  {src.strip()}")
            else:
                op, args = payload
                for k, w in enumerate(self.asm_instr(op, args, addr, ln)):
                    words[(addr >> 2) + k] = w & 0xFFFFFFFF
                    listing.append(f"{addr + 4 * k:08x}  {w:08x}  {src.strip()}")
        return words, listing


def write_hex(words, path):
    with open(path, "w", encoding="utf-8") as f:
        keys = sorted(words)
        prev = None
        for k in keys:
            if prev is None or k != prev + 1:
                f.write(f"@{k:08x}\n")
            f.write(f"{words[k]:08x}\n")
            prev = k


def selftest():
    """编码自测:AME_ISA.md §7 六个机器码样例 + RV32I 若干代表编码。"""
    a = Assembler()
    a.equ = {}
    cases = [
        # (op, args, pc, expect)
        ("ame.cfg", ["16", "16"], 0x0, 0x2100000B),
        ("ame.qcfg", ["3", "x6", "x7"], 0x0, 0x0273118B),
        ("ame.exe", ["x0"], 0x0, 0x0800400B),
        ("ame.exef", ["x0"], 0x0, 0x0A00400B),
        ("ame.sync", [], 0x0, 0x1000700B),
        ("ame.st.q", ["x3", "x10"], 0x0, 0x0E01E50B),
    ]
    for op, args, pc, want in cases:
        got = a.asm_instr(op, args, pc, 0)[0]
        assert got == want, f"{op} {args}: got {got:08x}, want {want:08x}"
    assert a.asm_instr("add", ["x1", "x2", "x3"], 0, 0)[0] == 0x003100B3
    assert a.asm_instr("addi", ["x1", "x2", "-1"], 0, 0)[0] == 0xFFF10093
    assert a.asm_instr("mul", ["x1", "x2", "x3"], 0, 0)[0] == 0x023100B3
    assert a.asm_instr("lw", ["x1", "4(x2)"], 0, 0)[0] == 0x00412083
    assert a.asm_instr("sw", ["x1", "8(x2)"], 0, 0)[0] == 0x00112423
    assert a.asm_instr("beq", ["x1", "x2", "8"], 0, 0)[0] == 0x00208463
    assert a.asm_instr("jal", ["x1", "16"], 0, 0)[0] == 0x010000EF
    assert a.asm_instr("csrrw", ["x1", "mstatus", "x2"], 0, 0)[0] == 0x300110F3
    print("cpu_asm selftest: ALL PASS")
    return 0


def main():
    if "--selftest" in sys.argv:
        return selftest()
    args = sys.argv[1:]
    src = None
    out = None
    lst = None
    i = 0
    while i < len(args):
        if args[i] == "-o":
            out = args[i + 1]; i += 2
        elif args[i] == "-l":
            lst = args[i + 1]; i += 2
        else:
            src = args[i]; i += 1
    if not src or not out:
        print(__doc__)
        return 1
    asm = Assembler()
    try:
        words, listing = asm.assemble(src)
    except AsmError as e:
        print(f"cpu_asm: ERROR: {e}", file=sys.stderr)
        return 1
    write_hex(words, out)
    if lst:
        with open(lst, "w", encoding="utf-8") as f:
            f.write("\n".join(listing) + "\n")
    print(f"cpu_asm: {src} -> {out} ({len(words)} words)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
