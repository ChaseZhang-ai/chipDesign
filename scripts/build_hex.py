#!/usr/bin/env python3
# -----------------------------------------------------------------------------
#
#
#
# reports/issues/P2D.md):
#
#   python3 scripts/build_hex.py asm <in.s> -o out.hex [--map out.map]
#          [--define N=V ...] [--base 0x0] [--rom-bytes N] [--text-limit N]
#          [--data-limit N]
#   python3 scripts/build_hex.py selftest
# -----------------------------------------------------------------------------

import argparse
import os
import re
import sys

XLEN = 32
MASK32 = 0xFFFFFFFF

# ---- opcodes -----------------------------------------------------------------
OP_LUI, OP_AUIPC, OP_JAL, OP_JALR = 0x37, 0x17, 0x6F, 0x67
OP_BRANCH, OP_LOAD, OP_STORE = 0x63, 0x03, 0x23
OP_IMMI, OP_IMM, OP_SYS, OP_MISC = 0x13, 0x33, 0x73, 0x0F
OP_AME = 0x0B

REG_ALIASES = {
    'zero': 0, 'ra': 1, 'sp': 2, 'gp': 3, 'tp': 4,
    't0': 5, 't1': 6, 't2': 7, 's0': 8, 'fp': 8, 's1': 9,
    'a0': 10, 'a1': 11, 'a2': 12, 'a3': 13, 'a4': 14, 'a5': 15,
    'a6': 16, 'a7': 17,
    's2': 18, 's3': 19, 's4': 20, 's5': 21, 's6': 22, 's7': 23,
    's8': 24, 's9': 25, 's10': 26, 's11': 27,
    't3': 28, 't4': 29, 't5': 30, 't6': 31,
}
AME_SCRATCH = 31


class AsmError(Exception):
    pass


def to_signed32(v):
    v &= MASK32
    return v - (1 << 32) if v & 0x80000000 else v


# =============================================================================
# =============================================================================

_TOKEN_RE = re.compile(r"""
    \s*(?:
      (?P<hex>0[xX][0-9a-fA-F]+)
    | (?P<bin>0[bB][01]+)
    | (?P<dec>-?\d+)
    | (?P<char>'(?:[^'\\]|\\.)')
    | (?P<hi>%hi\s*\(\s*[A-Za-z_.][\w.]*\s*\))
    | (?P<lo>%lo\s*\(\s*[A-Za-z_.][\w.]*\s*\))
    | (?P<sym>[A-Za-z_.][\w.]*)
    | (?P<op><<|>>|[()+\-*/%&|])
    )""", re.VERBOSE)


def tokenize_expr(s):
    toks, pos = [], 0
    while pos < len(s):
        m = _TOKEN_RE.match(s, pos)
        if not m:
            if s[pos:].strip() == '':
                break
            raise AsmError(f"表达式词法错误: {s!r} @ {s[pos:pos+8]!r}")
        pos = m.end()
        for k in ('hex', 'bin', 'dec', 'char', 'hi', 'lo', 'sym', 'op'):
            if m.group(k) is not None:
                toks.append((k, m.group(k)))
                break
    return toks


def _eval_expr(toks, symbols, pc):
    """递归下降求值。优先级: | < +-*% <<>> 混合处理为左结合双层。"""
    pos = [0]

    def peek():
        return toks[pos[0]] if pos[0] < len(toks) else (None, None)

    def take():
        t = peek()
        pos[0] += 1
        return t

    def prim():
        kind, val = take()
        if kind is None:
            raise AsmError("表达式意外结束")
        if kind == 'op' and val in '+-':
            v = prim()
            return v if val == '+' else -v
        if kind == 'op' and val == '(':
            v = expr()
            k2, _ = take()
            if k2 != 'op' or _ != ')':
                raise AsmError("缺少右括号")
            return v
        if kind == 'hex':
            return int(val, 16)
        if kind == 'bin':
            return int(val, 2)
        if kind == 'dec':
            return int(val, 10)
        if kind == 'char':
            body = val[1:-1]
            body = body.encode().decode('unicode_escape')
            return ord(body)
        if kind in ('hi', 'lo'):
            name = re.match(r'%(hi|lo)\s*\(\s*([\w.]+)\s*\)', val).group(2)
            v = resolve(name)
            lo = v & 0xFFF
            lo_s = lo - 0x1000 if lo & 0x800 else lo
            if kind == 'lo':
                return lo_s
            return ((v - lo_s) >> 12) & 0xFFFFF
        if kind == 'sym':
            return resolve(val)
        raise AsmError(f"意外记号 {val!r}")

    def resolve(name):
        if symbols is not None and name in symbols:
            return symbols[name]
        if name == '.':
            return pc
        raise AsmError(f"未定义符号 {name!r}")

    def mul_div():
        v = prim()
        while True:
            k, o = peek()
            if k == 'op' and o in ('*', '/', '%'):
                take()
                r = prim()
                if o == '*':
                    v = v * r
                elif o == '/':
                    v = int(v / r) if r else 0
                else:
                    v = v % r if r else 0
            else:
                return v

    def shift():
        v = mul_div()
        while True:
            k, o = peek()
            if k == 'op' and o in ('<<', '>>'):
                take()
                r = mul_div()
                v = (v << r) if o == '<<' else (v >> r)
            else:
                return v

    def addsub():
        v = shift()
        while True:
            k, o = peek()
            if k == 'op' and o in ('+', '-'):
                take()
                r = shift()
                v = v + r if o == '+' else v - r
            else:
                return v

    def expr():
        v = addsub()
        while True:
            k, o = peek()
            if k == 'op' and o in ('&', '|'):
                take()
                r = addsub()
                v = (v & r) if o == '&' else (v | r)
            else:
                return v

    v = expr()
    if pos[0] != len(toks):
        raise AsmError(f"表达式尾部多余记号: {toks[pos[0]:]}")
    return v


def eval_expr(s, symbols=None, pc=0):
    toks = tokenize_expr(s)
    if not toks:
        raise AsmError("空表达式")
    v = _eval_expr(toks, symbols, pc)
    return to_signed32(v)


# =============================================================================
# =============================================================================

def parse_reg(tok):
    t = tok.strip().lower()
    if re.fullmatch(r'x([0-9]|[12][0-9]|3[01])', t):
        return int(t[1:])
    if t in REG_ALIASES:
        return REG_ALIASES[t]
    raise AsmError(f"非法寄存器 {tok!r}")


_REG_TOK_RE = re.compile(r'x([0-9]|[12][0-9]|3[01])|t[0-6]|s([0-9]|1[01])|a[0-7]|zero|ra|sp|gp|tp|fp', re.I)


def looks_reg(tok):
    """纯寄存器名判定(不查表,供 collect 阶段静态判形)"""
    return bool(_REG_TOK_RE.fullmatch(tok.strip()))


_INT_TOK_RE = re.compile(r"[-+]?(0[xX][0-9a-fA-F]+|0[bB][01]+|\d+)$")


def instr_nwords(mnem, ops):
    """指令的静态字数(collect 与编码两阶段必须一致):
    li/la 固定 2 字(lui+addi,简化前向引用);AME 立即数选择子形式展开为 2 字。"""
    if mnem.startswith('ame.'):
        body = mnem[4:]
        if body in ('ld.w', 'ld.x', 'exe', 'exef', 'st.y', 'st.q'):
            if len(ops) >= 1 and looks_reg(ops[0]):
                return 1
            return 2
        return 1
    if mnem in ('li', 'la'):
        return 2
    return 1


# =============================================================================
# =============================================================================

def enc_r(f7, rs2, rs1, f3, rd, op):
    return ((f7 & 0x7F) << 25) | ((rs2 & 31) << 20) | ((rs1 & 31) << 15) \
         | ((f3 & 7) << 12) | ((rd & 31) << 7) | (op & 0x7F)


def enc_i(imm, rs1, f3, rd, op):
    imm &= 0xFFF
    return (imm << 20) | ((rs1 & 31) << 15) | ((f3 & 7) << 12) \
         | ((rd & 31) << 7) | (op & 0x7F)


def enc_s(imm, rs2, rs1, f3, op):
    imm &= 0xFFF
    return ((imm >> 5) << 25) | ((rs2 & 31) << 20) | ((rs1 & 31) << 15) \
         | ((f3 & 7) << 12) | ((imm & 0x1F) << 7) | (op & 0x7F)


def enc_b(imm, rs2, rs1, f3, op=OP_BRANCH):
    imm &= 0x1FFF
    return (((imm >> 12) & 1) << 31) | (((imm >> 5) & 0x3F) << 25) \
         | ((rs2 & 31) << 20) | ((rs1 & 31) << 15) | ((f3 & 7) << 12) \
         | (((imm >> 1) & 0xF) << 8) | (((imm >> 11) & 1) << 7) | op


def enc_u(imm20, rd, op):
    return ((imm20 & 0xFFFFF) << 12) | ((rd & 31) << 7) | op


def enc_j(imm, rd, op=OP_JAL):
    imm &= 0x1FFFFF
    return (((imm >> 20) & 1) << 31) | (((imm >> 1) & 0x3FF) << 21) \
         | (((imm >> 11) & 1) << 20) | (((imm >> 12) & 0xFF) << 12) \
         | ((rd & 31) << 7) | op



def enc_ame_cfg(n_eff, kt):
    """I-type: imm[4:0]=N_eff, imm[9:5]=KT, imm[11:10]=00"""
    imm = (kt & 0x1F) << 5 | (n_eff & 0x1F)
    if n_eff < 0 or n_eff > 31 or kt < 0 or kt > 31:
        raise AsmError(f"ame.cfg 字段超范围 n_eff={n_eff} kt={kt}")
    return enc_i(imm, 0, 0x0, 0, OP_AME)


def enc_ame_qcfg(n, rs_m, rs_s):
    """R-type: rd=通道号 n, rs1=M, rs2={S[5:0],ROUND_SEL<<6}"""
    return enc_r(0x01, rs_s, rs_m, 0x1, n, OP_AME)


def enc_ame_ldw(rs1):
    return enc_r(0x02, 0, rs1, 0x2, 0, OP_AME)


def enc_ame_ldx(rs1):
    return enc_r(0x03, 0, rs1, 0x3, 0, OP_AME)


def enc_ame_exe(rs1, exef=False):
    return enc_r(0x05 if exef else 0x04, 0, rs1, 0x4, 0, OP_AME)


def enc_ame_sty(rs1, rd):
    return enc_r(0x06, 0, rs1, 0x5, rd, OP_AME)


def enc_ame_stq(rs1, rd):
    return enc_r(0x07, 0, rs1, 0x6, rd, OP_AME)


def enc_ame_sync():
    return enc_r(0x08, 0, 0, 0x7, 0, OP_AME)


# =============================================================================
# =============================================================================

R_INSTR = {
    'add': (0, 0x00), 'sub': (0, 0x20), 'sll': (1, 0x00), 'slt': (2, 0x00),
    'sltu': (3, 0x00), 'xor': (4, 0x00), 'srl': (5, 0x00), 'sra': (5, 0x20),
    'or': (6, 0x00), 'and': (7, 0x00),
    'mul': (0, 0x01), 'mulh': (1, 0x01), 'mulhsu': (2, 0x01), 'mulhu': (3, 0x01),
    'div': (4, 0x01), 'divu': (5, 0x01), 'rem': (6, 0x01), 'remu': (7, 0x01),
}
I_INSTR = {
    'addi': 0, 'slti': 2, 'sltiu': 3, 'xori': 4, 'ori': 6, 'andi': 7,
    'lb': 0, 'lh': 1, 'lw': 2, 'lbu': 4, 'lhu': 5,
    'jalr': 0,
}
SHIFT_INSTR = {'slli': (1, 0x00), 'srli': (5, 0x00), 'srai': (5, 0x20)}
BR_INSTR = {'beq': 0, 'bne': 1, 'blt': 4, 'bge': 5, 'bltu': 6, 'bgeu': 7}
ST_INSTR = {'sb': 0, 'sh': 1, 'sw': 2}


def split_ops(s):
    """按逗号切操作数(括号内不切——load/store 的 off(reg) 无逗号,安全)"""
    out, cur, depth = [], '', 0
    for ch in s:
        if ch == '(':
            depth += 1
        elif ch == ')':
            depth -= 1
        if ch == ',' and depth == 0:
            out.append(cur.strip())
            cur = ''
        else:
            cur += ch
    if cur.strip():
        out.append(cur.strip())
    return out


class Assembler:
    def __init__(self, defines=None, base=0, text_limit=None, data_limit=None):
        self.symbols = dict(defines or {})
        self.base = base
        self.text_limit = text_limit
        self.data_limit = data_limit
        self.words = {}
        self.pc = base
        self.section = 'text'
        self.size = {'text': 0, 'data': 0}
        self.labels = {}
        self.line_no = 0
        self.src_name = '?'
        self.cond_stack = []
        self.pass_no = 1
        self._instr_pcs = []
        self._instr_idx = 0

    def err(self, msg):
        raise AsmError(f"{self.src_name}:{self.line_no}: {msg}")

    def _imm12(self, v, mnem):
        if not (-2048 <= v <= 2047):
            self.err(f"{mnem} 立即数越界: {v} (12 位有符号范围 -2048..2047);"
                     f"请改用 'li tmp, {v}' + 'add/ori' 展开")
        return v


    def assemble(self, source):
        self.line_no = 0
        self._instr_idx = 0
        for ln_raw in source.splitlines():
            self.line_no += 1
            self._line(ln_raw)
        return self


    def _strip_comment(self, ln):
        for cm in ('#', '//', ';'):
            i = ln.find(cm)
            if i >= 0:
                ln = ln[:i]
        return ln.strip()

    def _line(self, raw):
        ln = self._strip_comment(raw)
        if not ln:
            return
        while True:
            m = re.match(r'^([A-Za-z_.][\w.]*):\s*(.*)$', ln)
            if not m:
                break
            self._define_label(m.group(1))
            ln = m.group(2).strip()
        if not ln:
            return
        if ln.startswith('.'):
            self._directive(ln)
        else:
            if not self._active():
                return
            self._instruction(ln)

    def _active(self):
        return all(a for a, _ in self.cond_stack)

    def _define_label(self, name):
        if not self._active():
            return
        if self.pass_no >= 2:
            if name not in self.symbols or self.symbols[name] != self.pc:
                self.err(f"第二遍发现符号 {name} 与第一遍不一致")
            return
        if name in self.labels or name in self.symbols:
            self.err(f"重复符号 {name}")
        self.labels[name] = self.pc
        self.symbols[name] = self.pc


    def _directive(self, ln):
        m = re.match(r'^(\.(\w+))\s*(.*)$', ln)
        if not m:
            self.err(f"无法解析指示 {ln!r}")
        name, _, rest = m.group(1), m.group(2), m.group(3).strip()

        if name == '.if':
            v = eval_expr(rest, self.symbols, self.pc) if self._active() else 0
            self.cond_stack.append((bool(v), bool(v)))
            return
        if name == '.else':
            if not self.cond_stack:
                self.err(".else 无匹配 .if")
            a, t = self.cond_stack[-1]
            self.cond_stack[-1] = ((not t) and a, True)
            return
        if name == '.endif':
            if not self.cond_stack:
                self.err(".endif 无匹配 .if")
            self.cond_stack.pop()
            return
        if not self._active():
            return

        if name in ('.globl', '.global', '.type', '.size', '.option'):
            return
        if name == '.equ' or name == '.set':
            mm = re.match(r'^([A-Za-z_.][\w.]*)\s*,\s*(.+)$', rest)
            if not mm:
                self.err(f"{name} 语法: .equ NAME, expr")
            if self.pass_no >= 2:
                return
            if mm.group(1) in self.symbols:
                self.err(f"重复符号 {mm.group(1)}")
            self.symbols[mm.group(1)] = eval_expr(mm.group(2), self.symbols, self.pc)
            return
        if name == '.text':
            self.section = 'text'
            return
        if name == '.data' or name == '.rodata' or name == '.bss':
            self.section = 'data'
            return
        if name == '.align':
            n = eval_expr(rest, self.symbols, self.pc)
            step = 1 << n
            self._pad((-self.pc) % step, 0)
            return
        if name == '.space' or name == '.zero':
            n = eval_expr(rest, self.symbols, self.pc)
            self._pad(n, 0)
            return
        if name == '.word':
            for e in split_ops(rest):
                self._emit_word(eval_expr(e, self.symbols, self.pc) & MASK32)
            return
        if name == '.half':
            for i, e in enumerate(split_ops(rest)):
                v = eval_expr(e, self.symbols, self.pc) & 0xFFFF
                if i % 2 == 0:
                    self._cur_half = v
                else:
                    self._emit_word(self._cur_half | (v << 16))
            return
        if name in ('.byte',):
            for e in split_ops(rest):
                v = eval_expr(e, self.symbols, self.pc) & 0xFF
                self._emit_byte(v)
            return
        if name in ('.ascii', '.asciz', '.string'):
            mm = re.match(r'^"(.*)"$', rest, re.S)
            if not mm:
                self.err(f"{name} 需要带引号字符串")
            s = mm.group(1).encode().decode('unicode_escape')
            for ch in s:
                self._emit_byte(ord(ch) & 0xFF)
            if name in ('.asciz', '.string'):
                self._emit_byte(0)
            return
        self.err(f"未知指示 {name}")


    def _account(self, n):
        self.size[self.section] += n

    def _emit_word(self, w):
        self.words[self.pc] = w & MASK32
        self.pc += 4
        self._account(4)

    def _emit_byte(self, b):
        ai = self.pc % 4
        base_a = self.pc - ai
        w = self.words.get(base_a, 0)
        w = (w & ~(0xFF << (8 * ai))) | ((b & 0xFF) << (8 * ai))
        self.words[base_a] = w
        self.pc += 1
        self._account(1)

    def _pad(self, n, fill):
        for _ in range(n):
            self._emit_byte(fill)


    def _emit_instr(self, w, cont=False):
        if self.section != 'text':
            self.err("指令只能出现在 .text 段")
        if self._instr_pcs and not cont:
            if self._instr_idx >= len(self._instr_pcs):
                self.err("第二遍指令条数多于第一遍(collect/编码字数不一致)")
            if self._instr_pcs[self._instr_idx] != self.pc:
                self.err(f"第二遍 pc 0x{self.pc:08X} 与第一遍 "
                         f"0x{self._instr_pcs[self._instr_idx]:08X} 不一致(静态字数策略错误)")
            self._instr_idx += 1
        self.words[self.pc] = w & MASK32
        self.pc += 4
        self._account(4)

    def _instruction(self, ln):
        m = re.match(r'^([A-Za-z.][\w.]*)\s*(.*)$', ln)
        if not m:
            self.err(f"无法解析语句 {ln!r}")
        mnem, ops_s = m.group(1).lower(), m.group(2).strip()
        ops = split_ops(ops_s) if ops_s else []

        if mnem.startswith('ame.'):
            self._ame(mnem, ops)
            return

        if mnem == 'nop':
            self._emit_instr(enc_i(0, 0, 0, 0, OP_IMMI))
            return
        if mnem == 'mv':
            self._need(ops, 2)
            self._emit_instr(enc_i(0, parse_reg(ops[1]), 0, parse_reg(ops[0]), OP_IMMI))
            return
        if mnem == 'not':
            self._need(ops, 2)
            self._emit_instr(enc_i(0xFFF, parse_reg(ops[1]), 4, parse_reg(ops[0]), OP_IMMI))
            return
        if mnem == 'neg':
            self._need(ops, 2)
            self._emit_instr(enc_r(0x20, parse_reg(ops[1]), 0, 0, parse_reg(ops[0]), OP_IMM))
            return
        if mnem in ('li', 'la'):
            self._need(ops, 2)
            rd = parse_reg(ops[0])
            v = eval_expr(ops[1], self.symbols, self.pc)
            self._emit_li(rd, v)
            return
        if mnem == 'j':
            self._need(ops, 1)
            self._emit_j(0, ops[0])
            return
        if mnem == 'jr':
            self._need(ops, 1)
            self._emit_instr(enc_i(0, parse_reg(ops[0]), 0, 0, OP_JALR))
            return
        if mnem == 'jalr':
            if len(ops) == 1:
                self._emit_instr(enc_i(0, parse_reg(ops[0]), 0, 1, OP_JALR))
            else:
                self._need(ops, 2, 3)
                if len(ops) == 2:
                    self._emit_instr(enc_i(0, parse_reg(ops[1]), 0, parse_reg(ops[0]), OP_JALR))
                else:
                    imm = self._imm12(eval_expr(ops[2], self.symbols, self.pc), 'jalr')
                    self._emit_instr(enc_i(imm, parse_reg(ops[1]), 0, parse_reg(ops[0]), OP_JALR))
            return
        if mnem == 'ret':
            self._emit_instr(enc_i(0, 1, 0, 0, OP_JALR))
            return
        if mnem == 'call':
            self._need(ops, 1)
            ra = 1
            self._emit_j(ra, ops[0])
            return
        if mnem == 'tail':
            self._need(ops, 1)
            self._emit_j(0, ops[0])
            return
        if mnem in ('beqz', 'bnez', 'bgez', 'bltz', 'bgtz', 'blez'):
            self._need(ops, 2)
            rs = parse_reg(ops[0])
            f3 = {'beqz': 0, 'bnez': 1, 'bgez': 5, 'bltz': 4, 'bgtz': 4, 'blez': 5}[mnem]
            if mnem in ('bgtz', 'blez'):
                # bgtz rs,lbl = blt x0,rs ; blez rs,lbl = bge x0,rs
                self._emit_br(0, rs, f3, ops[1])
            else:
                self._emit_br(rs, 0, f3, ops[1])
            return
        if mnem in ('bgt', 'ble', 'bgtu', 'bleu'):
            self._need(ops, 3)
            a, b = parse_reg(ops[0]), parse_reg(ops[1])
            f3 = {'bgt': 4, 'ble': 5, 'bgtu': 6, 'bleu': 7}[mnem]
            self._emit_br(b, a, f3, ops[2])
            return
        if mnem == 'seqz':
            self._need(ops, 2)
            self._emit_instr(enc_i(1, parse_reg(ops[1]), 3, parse_reg(ops[0]), OP_IMMI))
            return
        if mnem == 'snez':
            self._need(ops, 2)
            self._emit_instr(enc_r(0, parse_reg(ops[1]), 0, 3, parse_reg(ops[0]), OP_IMM))
            return

        if mnem in ('lui', 'auipc'):
            self._need(ops, 2)
            rd = parse_reg(ops[0])
            v = eval_expr(ops[1], self.symbols, self.pc)
            self._emit_instr(enc_u(v, rd, OP_LUI if mnem == 'lui' else OP_AUIPC))
            return
        if mnem == 'jal':
            if len(ops) == 1:
                self._emit_j(1, ops[0])
            else:
                self._need(ops, 2)
                self._emit_j(parse_reg(ops[0]), ops[1])
            return
        if mnem in BR_INSTR:
            self._need(ops, 3)
            self._emit_br(parse_reg(ops[0]), parse_reg(ops[1]), BR_INSTR[mnem], ops[2])
            return
        if mnem in I_INSTR and mnem in ('lb', 'lh', 'lw', 'lbu', 'lhu'):
            self._need(ops, 2)
            mm = re.match(r'^(-?[\w%+*/&|<>.()\s\'-]+)\s*\(\s*([\w]+)\s*\)$', ops[1])
            if not mm:
                self.err(f"load 操作数需 off(reg) 形式: {ops[1]!r}")
            imm = self._imm12(eval_expr(mm.group(1), self.symbols, self.pc), mnem)
            self._emit_instr(enc_i(imm, parse_reg(mm.group(2)), I_INSTR[mnem],
                                   parse_reg(ops[0]), OP_LOAD))
            return
        if mnem in ST_INSTR:
            self._need(ops, 2)
            mm = re.match(r'^(-?[\w%+*/&|<>.()\s\'-]+)\s*\(\s*([\w]+)\s*\)$', ops[1])
            if not mm:
                self.err(f"store 操作数需 off(reg) 形式: {ops[1]!r}")
            imm = self._imm12(eval_expr(mm.group(1), self.symbols, self.pc), mnem)
            self._emit_instr(enc_s(imm, parse_reg(ops[0]), parse_reg(mm.group(2)),
                                   ST_INSTR[mnem], OP_STORE))
            return
        if mnem in SHIFT_INSTR:
            self._need(ops, 3)
            f3, f7 = SHIFT_INSTR[mnem]
            sh = eval_expr(ops[2], self.symbols, self.pc) & 0x1F
            self._emit_instr(enc_r(f7, sh, parse_reg(ops[1]), f3, parse_reg(ops[0]), OP_IMMI))
            return
        if mnem in I_INSTR:  # addi/slti/sltiu/xori/ori/andi
            self._need(ops, 3)
            imm = self._imm12(eval_expr(ops[2], self.symbols, self.pc), mnem)
            self._emit_instr(enc_i(imm, parse_reg(ops[1]), I_INSTR[mnem],
                                   parse_reg(ops[0]), OP_IMMI))
            return
        if mnem in R_INSTR:
            self._need(ops, 3)
            f3, f7 = R_INSTR[mnem]
            self._emit_instr(enc_r(f7, parse_reg(ops[2]), parse_reg(ops[1]), f3,
                                   parse_reg(ops[0]), OP_IMM))
            return
        if mnem == 'fence' or mnem == 'fence.i':
            self._emit_instr(enc_i(0, 0, 0, 0, OP_MISC) if mnem == 'fence'
                             else enc_i(1, 0, 1, 0, OP_MISC))
            return
        if mnem == 'ecall':
            self._emit_instr(enc_i(0, 0, 0, 0, OP_SYS))
            return
        if mnem == 'ebreak':
            self._emit_instr(enc_i(1, 0, 0, 0, OP_SYS))
            return
        if mnem == 'wfi':
            self._emit_instr(enc_i(0x105, 0, 0, 0, OP_SYS))
            return
        self.err(f"未知指令 {mnem!r}")

    def _emit_li(self, rd, v):
        v &= MASK32
        lo = v & 0xFFF
        lo_s = lo - 0x1000 if lo & 0x800 else lo
        hi = ((v - lo_s) >> 12) & 0xFFFFF
        self._emit_instr(enc_u(hi, rd, OP_LUI))
        self._emit_instr(enc_i(lo_s, rd, 0, rd, OP_IMMI), cont=True)

    def _emit_j(self, rd, target):
        v = eval_expr(target, self.symbols, self.pc)
        off = v - self.pc
        if not (-(1 << 20) <= off < (1 << 20)):
            self.err(f"jal 跳转距离超界: {off}")
        self._emit_instr(enc_j(off, rd, OP_JAL))

    def _emit_br(self, rs1, rs2, f3, target):
        v = eval_expr(target, self.symbols, self.pc)
        off = v - self.pc
        if not (-4096 <= off < 4096):
            self.err(f"branch 跳转距离超界: {off}")
        self._emit_instr(enc_b(off, rs2, rs1, f3, OP_BRANCH))


    def _ame(self, mnem, ops):
        body = mnem[4:]
        if body == 'cfg':
            self._need(ops, 2)
            n = eval_expr(ops[0], self.symbols, self.pc)
            kt = eval_expr(ops[1], self.symbols, self.pc)
            self._emit_instr(enc_ame_cfg(n, kt))
            return
        if body == 'qcfg':
            self._need(ops, 3)
            n = eval_expr(ops[0], self.symbols, self.pc)
            if not (0 <= n <= 31):
                self.err(f"qcfg 通道号越界: {n}")
            self._emit_instr(enc_ame_qcfg(n, parse_reg(ops[1]), parse_reg(ops[2])))
            return
        if body == 'ld.w':
            self._ame_sel(ops, enc_ame_ldw)
            return
        if body == 'ld.x':
            self._ame_sel(ops, enc_ame_ldx)
            return
        if body in ('exe', 'exef'):
            exef = body == 'exef'
            if len(ops) == 1 and looks_reg(ops[0]):
                self._emit_instr(enc_ame_exe(parse_reg(ops[0]), exef))
            elif len(ops) == 1:
                v = eval_expr(ops[0], self.symbols, self.pc)
                self._ame_expand(v & 0x1F, lambda r: enc_ame_exe(r, exef))
            else:
                self.err(f"{mnem} 需要 1 个选择子操作数")
            return
        if body in ('st.y', 'st.q'):
            enc = enc_ame_sty if body == 'st.y' else enc_ame_stq
            self._need(ops, 2)
            rd = parse_reg(ops[1])
            if looks_reg(ops[0]):
                self._emit_instr(enc(parse_reg(ops[0]), rd))
            else:
                v = eval_expr(ops[0], self.symbols, self.pc)
                self._ame_expand(v & 0x1F, lambda r: enc(r, rd))
            return
        if body == 'sync':
            self._need(ops, 0)
            self._emit_instr(enc_ame_sync())
            return
        self.err(f"未知 AME 指令 {mnem!r}")

    def _ame_sel(self, ops, enc):
        """ame.ld.w/ld.x: 寄存器形式 = 单寄存器操作数;立即数形式 = region[,tsel]/off[,xsel]"""
        if len(ops) == 1 and looks_reg(ops[0]):
            self._emit_instr(enc(parse_reg(ops[0])))
            return
        if len(ops) in (1, 2):
            a = eval_expr(ops[0], self.symbols, self.pc)
            b = eval_expr(ops[1], self.symbols, self.pc) if len(ops) == 2 else 0
            self._ame_expand((a & 0x1FF) | ((b & 1) << 9) if enc is enc_ame_ldx
                             else (a & 3) | ((b & 1) << 2),
                             enc)
            return
        self.err(f"ame.ld 需要寄存器或 1-2 个立即数")

    def _ame_expand(self, sel, encfn):
        """立即数选择子: addi x31,x0,sel + 原生指令(x31=t6 为汇编器保留)"""
        if not (-2048 <= sel <= 2047):
            self._emit_li(AME_SCRATCH, sel & MASK32)
            return
        self._emit_instr(enc_i(sel, 0, 0, AME_SCRATCH, OP_IMMI))
        self._emit_instr(encfn(AME_SCRATCH), cont=True)

    def _need(self, ops, lo, hi=None):
        hi = lo if hi is None else hi
        if not (lo <= len(ops) <= hi):
            self.err(f"操作数个数错误(得 {len(ops)},需 {lo}..{hi})")


    def collect_pass(self, source):
        """第一遍: 轻量扫描 —— 收集标签与 .equ,按**静态字数**推进 pc(支持前向引用)。
        不做表达式求值(数据指示中的字面量除外);第二遍(assemble)编码并校验 pc 一致。"""
        self._instr_pcs = []
        self.line_no = 0
        for ln_raw in source.splitlines():
            self.line_no += 1
            ln = self._strip_comment(ln_raw)
            if not ln:
                continue
            while True:
                m = re.match(r'^([A-Za-z_.][\w.]*):\s*(.*)$', ln)
                if not m:
                    break
                self._define_label(m.group(1))
                ln = m.group(2).strip()
            if not ln:
                continue
            if ln.startswith('.'):
                self._directive_collect(ln)
                continue
            m = re.match(r'^([A-Za-z.][\w.]*)\s*(.*)$', ln)
            if not m:
                self.err(f"无法解析语句 {ln!r}")
            mnem, ops_s = m.group(1).lower(), m.group(2).strip()
            ops = split_ops(ops_s) if ops_s else []
            if self.section != 'text':
                self.err("指令只能出现在 .text 段")
            if not self._active():
                continue
            self._instr_pcs.append(self.pc)
            self.pc += 4 * instr_nwords(mnem, ops)
        self.words = {}
        self.pc = self.base
        self.size = {'text': 0, 'data': 0}
        self.cond_stack = []
        self.line_no = 0
        self.pass_no = 2
        self._instr_idx = 0

    def _directive_collect(self, ln):
        """collect 阶段的指示处理: 只做符号/段落/字面量数据,忽略需要求值的编码"""
        m = re.match(r'^(\.(\w+))\s*(.*)$', ln)
        if not m:
            self.err(f"无法解析指示 {ln!r}")
        name, rest = m.group(1), m.group(3).strip()
        if name == '.if':
            v = eval_expr(rest, self.symbols, self.pc) if self._active() else 0
            self.cond_stack.append((bool(v), bool(v)))
            return
        if name == '.else':
            if not self.cond_stack:
                self.err(".else 无匹配 .if")
            a, t = self.cond_stack[-1]
            self.cond_stack[-1] = ((not t) and a, True)
            return
        if name == '.endif':
            if not self.cond_stack:
                self.err(".endif 无匹配 .if")
            self.cond_stack.pop()
            return
        if not self._active():
            return
        if name in ('.globl', '.global', '.type', '.size', '.option'):
            return
        if name in ('.equ', '.set'):
            mm = re.match(r'^([A-Za-z_.][\w.]*)\s*,\s*(.+)$', rest)
            if not mm:
                self.err(f"{name} 语法: .equ NAME, expr")
            if mm.group(1) in self.symbols:
                self.err(f"重复符号 {mm.group(1)}")
            self.symbols[mm.group(1)] = eval_expr(mm.group(2), self.symbols, self.pc)
            return
        if name == '.text':
            self.section = 'text'
            return
        if name in ('.data', '.rodata', '.bss'):
            self.section = 'data'
            return
        if name == '.align':
            n = eval_expr(rest, self.symbols, self.pc)
            self.pc += (-self.pc) % (1 << n)
            return
        if name in ('.space', '.zero'):
            self.pc += eval_expr(rest, self.symbols, self.pc)
            return
        if name == '.word':
            for _ in split_ops(rest):
                self.pc += 4
            return
        if name == '.half':
            self.pc += 2 * len(split_ops(rest))
            return
        if name == '.byte':
            self.pc += len(split_ops(rest))
            return
        if name in ('.ascii', '.asciz', '.string'):
            mm = re.match(r'^"(.*)"$', rest, re.S)
            if not mm:
                self.err(f"{name} 需要带引号字符串")
            s = mm.group(1).encode().decode('unicode_escape')
            self.pc += len(s) + (1 if name in ('.asciz', '.string') else 0)
            return
        self.err(f"未知指示 {name}")


    def emit_hex(self, rom_bytes, out_path, fill=0):
        n_words = rom_bytes // 4
        if rom_bytes % 4:
            raise AsmError("rom_bytes 必须 4 对齐")
        used = max(self.words) if self.words else 0
        last = max(self.pc, used + 4) if self.words else self.pc
        if last - self.base > rom_bytes:
            raise AsmError(f"镜像 {last - self.base}B 超出区域容量 {rom_bytes}B")
        with open(out_path, 'w') as f:
            f.write(f"// generated by scripts/build_hex.py ({os.path.basename(out_path)})\n")
            f.write(f"// base=0x{self.base:08X} bytes_used={last - self.base}\n")
            for i in range(n_words):
                a = self.base + i * 4
                f.write(f"{self.words.get(a, fill):08X}\n")

    def write_map(self, path, title):
        with open(path, 'w') as f:
            f.write(f"# {title} map (build_hex.py)\n")
            f.write(f"base       = 0x{self.base:08X}\n")
            f.write(f"text_bytes = {self.size['text']}\n")
            f.write(f"data_bytes = {self.size['data']}\n")
            f.write(f"total_end  = 0x{self.pc:08X} ({self.pc - self.base} bytes from base)\n\n")
            for name, a in sorted(self.labels.items(), key=lambda kv: kv[1]):
                f.write(f"0x{a:08X}  {name}\n")

    def check_limits(self):
        if self.text_limit is not None and self.size['text'] > self.text_limit:
            raise AsmError(f"程序段 {self.size['text']}B 超过硬约束 {self.text_limit}B")
        if self.data_limit is not None and self.size['data'] > self.data_limit:
            raise AsmError(f"数据段 {self.size['data']}B 超过硬约束 {self.data_limit}B")


def assemble_file(path, defines=None, base=0, text_limit=None, data_limit=None):
    with open(path) as f:
        src = f.read()
    asm = Assembler(defines=dict(defines or {}), base=base,
                    text_limit=text_limit, data_limit=data_limit)
    asm.collect_pass(src)
    asm.assemble(src)
    asm.check_limits()
    return asm


# =============================================================================
# =============================================================================

def selftest():
    cases = [
        ("ame.cfg 16,16 (§1.2 字段位)", enc_ame_cfg(16, 16), 0x2100000B),
        ("ame.qcfg 3,x6,x7     §7", enc_ame_qcfg(3, 6, 7), 0x0273118B),
        ("ame.exe rs1=x0       §7", enc_ame_exe(0), 0x0800400B),
        ("ame.exef rs1=x0      §7", enc_ame_exe(0, True), 0x0A00400B),
        ("ame.sync             §7", enc_ame_sync(), 0x1000700B),
        ("ame.st.q rs1=x3,rd=x10 §7", enc_ame_stq(3, 10), 0x0E01E50B),
        ("addi x1,x2,-1", enc_i(-1 & 0xFFF, 2, 0, 1, OP_IMMI), 0xFFF10093),
        ("lui x5,0x12345", enc_u(0x12345, 5, OP_LUI), 0x123452B7),
        ("sw x3,8(x4)", enc_s(8, 3, 4, 2, OP_STORE), 0x00322423),
        ("beq x1,x2,+8", enc_b(8, 2, 1, 0, OP_BRANCH), 0x00208463),
        ("jal x1,+16", enc_j(16, 1, OP_JAL), 0x010000EF),
        ("wfi", enc_i(0x105, 0, 0, 0, OP_SYS), 0x10500073),
        ("mul x5,x6,x7", enc_r(0x01, 7, 6, 0, 5, OP_IMM), 0x027302B3),
    ]
    fails = 0
    for name, got, want in cases:
        ok = (got & MASK32) == (want & MASK32)
        print(f"  {'PASS' if ok else 'FAIL'}  {name}: got=0x{got:08X} want=0x{want:08X}")
        fails += 0 if ok else 1
    try:
        a2 = Assembler()
        a2.collect_pass("addi x1, x2, 0x1000")
        a2.assemble("addi x1, x2, 0x1000")
        print("  FAIL  I-type 越界未报错(P3D-10)")
        fails += 1
    except AsmError as e:
        print(f"  PASS  I-type 越界报错(P3D-10): {e}")

    src = """
        ame.cfg 16, 16
        ame.sync
        li   x5, 5
        ame.ld.w x5
        ame.qcfg 3, x6, x7
"""
    asm = Assembler()
    asm.collect_pass(src)
    asm.assemble(src)
    w = [asm.words[asm.base + 4 * i] for i in range(len(asm.words))]
    # li x5,5 = lui x5,0 + addi x5,x5,5;ame.ld.w x5 = f7 0x02 | rs1 5 | f3 0x2 | 0x0B
    exp = [0x2100000B, 0x1000700B, 0x000002B7, 0x00528293, 0x0402A00B, 0x0273118B]
    ok = w == exp
    print(f"  {'PASS' if ok else 'FAIL'}  端到端小程序编码: {['%08X' % x for x in w]}")
    fails += 0 if ok else 1
    print(f"selftest: {'ALL PASS' if fails == 0 else f'{fails} FAIL'}")
    return fails


# =============================================================================
# =============================================================================

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

BOOT_LIMIT = 2 * 1024
TEXT_LIMIT = 2 * 1024
DATA_LIMIT = 2 * 1024


def build_boot(out_boot, out_jump):
    os.makedirs(os.path.dirname(out_jump), exist_ok=True)
    src = os.path.join(ROOT, 'rtl', 'soc', 'boot', 'boot.s')
    a = assemble_file(src, defines={'BOOT_JUMP': 0}, base=0x00010000,
                      text_limit=BOOT_LIMIT)
    a.emit_hex(BOOT_LIMIT, out_boot)
    print(f"boot.hex: {a.size['text']}B code, {a.size['data']}B data "
          f"(limit {BOOT_LIMIT}B) -> {out_boot}")
    b = assemble_file(src, defines={'BOOT_JUMP': 1}, base=0x00010000,
                      text_limit=BOOT_LIMIT)
    b.emit_hex(BOOT_LIMIT, out_jump)
    print(f"boot_jump.hex: {b.size['text']}B -> {out_jump}")


def build_demo(out_hex, out_map):
    src = os.path.join(ROOT, 'tb', 'soc', 'program', 'demo_decode.s')
    a = assemble_file(src, base=0x00000000, text_limit=TEXT_LIMIT,
                      data_limit=DATA_LIMIT)
    a.emit_hex(4 * 1024, out_hex)   # OC SRAM 4KB
    a.write_map(out_map, "demo_decode.s (OC SRAM image)")
    print(f"demo.hex: text={a.size['text']}B (limit {TEXT_LIMIT}B), "
          f"data={a.size['data']}B (limit {DATA_LIMIT}B) -> {out_hex}")


def main():
    ap = argparse.ArgumentParser(description="AME-Chip RV32IM+AME assembler")
    sub = ap.add_subparsers(dest='cmd', required=True)
    p_asm = sub.add_parser('asm', help='assemble one file')
    p_asm.add_argument('input')
    p_asm.add_argument('-o', '--output', required=True)
    p_asm.add_argument('--map')
    p_asm.add_argument('--define', action='append', default=[])
    p_asm.add_argument('--base', default='0x0')
    p_asm.add_argument('--rom-bytes', type=lambda x: int(x, 0), default=4 * 1024)
    p_asm.add_argument('--text-limit', type=lambda x: int(x, 0), default=None)
    p_asm.add_argument('--data-limit', type=lambda x: int(x, 0), default=None)
    sub.add_parser('boot', help='generate boot ROM images')
    sub.add_parser('demo', help='generate demo image')
    sub.add_parser('selftest', help='encoding selftest')
    args = ap.parse_args()

    if args.cmd == 'selftest':
        sys.exit(1 if selftest() else 0)
    if args.cmd == 'boot':
        build_boot(os.path.join(ROOT, 'rtl', 'soc', 'boot', 'boot.hex'),
                   os.path.join(ROOT, 'tb', 'soc', 'build', 'boot_jump.hex'))
        return
    if args.cmd == 'demo':
        os.makedirs(os.path.join(ROOT, 'tb', 'soc', 'build'), exist_ok=True)
        build_demo(os.path.join(ROOT, 'tb', 'soc', 'build', 'demo.hex'),
                   os.path.join(ROOT, 'tb', 'soc', 'build', 'demo.map'))
        return
    if args.cmd == 'asm':
        defines = {}
        for d in args.define:
            k, _, v = d.partition('=')
            defines[k] = eval_expr(v) if v else 1
        a = assemble_file(args.input, defines=defines,
                          base=int(args.base, 0), text_limit=args.text_limit,
                          data_limit=args.data_limit)
        a.emit_hex(args.rom_bytes, args.output)
        if args.map:
            a.write_map(args.map, args.input)
        print(f"asm: text={a.size['text']}B data={a.size['data']}B -> {args.output}")


if __name__ == '__main__':
    try:
        main()
    except AsmError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)
