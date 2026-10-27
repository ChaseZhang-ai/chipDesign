#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""cpu_iss.py — RV32IM + Zicsr + AME(custom-0) 指令级模拟器(P2A 差分测试 golden)

与 rtl/cpu/ame_cpu.sv 逐指令差分:TB 把每条提交指令的 (pc, instr, rd, wdata,
flags) 打到 trace 文件,本模拟器对同一镜像产生同格式 trace,cpu_diff.py 比对。

约定
----
- 复位 PC = 0x0001_0000(BOOTROM,amechip_pkg::RESET_VECTOR);镜像里在该
  地址放 `j 0x0` 跳到主程序。
- GPR/CSR 复位全 0(与 RTL 一致);mtvec 复位 0x0000_0100。
- ebreak = 停机(提交后停止);非法指令 = NOP 提交 + flags sticky(与 RTL 一致)。
- mcycle 按步数计数(RTL 按真实周期),读 mcycle/cycle 系列的 trace 行带
  skip 标志,cpu_diff 跳过其 wdata;minstret 两侧同源,可比对。
- 中断/dma 等平台行为不在 ISS 范围(中断为 TB 定向测试,不做差分)。
- AME 功能模型:AME_ISA §3 的语义(含 ERR 判定与 st.y/st.q 数据路径),
  时序反压不建模(不影响提交序列;mcycle 已 skip)。
- WBUF/XBUF 初始内容:byte[i] = (i*7+13) & 0xFF(与 tb/cpu/tb_ame_model.sv
  一致,见 CPU_NOTES.md)。

用法
----
python3 scripts/cpu_iss.py prog.hex -o trace_ref.txt [--max-steps 200000]
"""

import argparse
import sys

M32 = 0xFFFFFFFF
RESET_VECTOR = 0x0001_0000

# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------

def load_hex(path, mem_bytes):
    with open(path, encoding="utf-8") as f:
        addr = None
        for line in f:
            s = line.split("#")[0].split("//")[0].strip()
            if not s:
                continue
            if s.startswith("@"):
                addr = int(s[1:], 16) * 4
                continue
            w = int(s, 16) & M32
            assert addr is not None, "hex data before @addr"
            mem_bytes[addr:addr + 4] = w.to_bytes(4, "little")
            addr += 4


# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------

class AmeModel:
    N_MAX = 16
    M_MAX = 16

    def __init__(self, mem):
        self.mem = mem
        self.n_eff = 0
        self.kt = 0
        self.rq_m = [0] * 32
        self.rq_s = [0] * 32
        self.rq_r = [0] * 32
        self.wbuf = bytes(((i * 7 + 13) & 0xFF) for i in range(1024))
        self.xbuf = bytes(((i * 7 + 13) & 0xFF) for i in range(1024))
        self.tile = [[[0] * self.M_MAX for _ in range(self.N_MAX)] for _ in range(2)]
        self.xreg = [[0] * self.M_MAX for _ in range(2)]
        self.y = [0] * self.N_MAX
        self.tset = [0, 0]
        self.xset = [0, 0]

    def step(self, instr, rs1, rs2):
        """返回 (resp_data, resp_err)。"""
        f3 = (instr >> 12) & 0x7
        f7 = (instr >> 25) & 0x7F
        rd = (instr >> 7) & 0x1F
        err = 0
        data = 0
        if f3 == 0x0:  # cfg
            n_eff = instr & 0x1F
            kt = (instr >> 5) & 0x1F
            if ((instr >> 10) & 0x3) != 0 or n_eff == 0 or n_eff > self.N_MAX \
                    or kt == 0 or kt > self.M_MAX:
                err = 1
            else:
                self.n_eff, self.kt = n_eff, kt
        elif f3 == 0x1 and f7 == 0x01:  # qcfg
            n = rd
            s = rs2 & 0x3F
            rnd = (rs2 >> 6) & 0x1
            if (rs2 >> 7) != 0 or s == 0 or n >= self.N_MAX:
                err = 1
            else:
                self.rq_m[n], self.rq_s[n], self.rq_r[n] = rs1, s, rnd
        elif f3 == 0x2 and f7 == 0x02:  # ld.w
            region = rs1 & 0x3
            tsel = (rs1 >> 2) & 0x1
            if rs1 >> 3:
                err = 1
            else:
                base = region * 256
                for n in range(self.n_eff):
                    for k in range(self.kt):
                        self.tile[tsel][n][k] = self.wbuf[base + n * self.kt + k]
                self.tset[tsel] = 2
        elif f3 == 0x3 and f7 == 0x03:  # ld.x
            off = rs1 & 0x1FF
            xsel = (rs1 >> 9) & 0x1
            if rs1 >> 10:
                err = 1
            else:
                for k in range(self.kt):
                    self.xreg[xsel][k] = self.xbuf[(off + k) % 1024]
                self.xset[xsel] = 2
        elif f3 == 0x4 and f7 in (0x04, 0x05):  # exe / exef
            tsel = rs1 & 0x1
            if (rs1 >> 1) or self.n_eff == 0 or self.kt == 0:
                err = 1
            else:
                if f7 == 0x05:
                    self.y = [0] * self.N_MAX
                for k in range(self.kt):
                    xk = self.xreg[tsel][k]
                    for n in range(self.n_eff):
                        prod = self.tile[tsel][n][k] * xk
                        acc = self.y[n] + prod
                        if acc > 0x7FFFFFFF:
                            acc = 0x7FFFFFFF
                        elif acc < -0x80000000:
                            acc = -0x80000000
                        self.y[n] = acc
        elif f3 == 0x5 and f7 == 0x06:  # st.y
            i = rs1 & 0x1F
            if rs1 >> 5:
                err = 1
                data = 0
            else:
                if i >= self.n_eff:
                    err = 1
                    data = 0
                else:
                    data = self.y[i] & M32
        elif f3 == 0x6 and f7 == 0x07:  # st.q
            i = rs1 & 0x1F
            if rs1 >> 5:
                err = 1
                data = 0
            else:
                if i >= self.n_eff:
                    err = 1
                    data = 0
                else:
                    data = self.requant(i) & M32
        elif f3 == 0x7 and f7 == 0x08:  # sync
            pass
        else:
            err = 1
        return data, err

    def requant(self, n):
        """GOLDEN_SPEC §2.2:clip((y*M (+2^(S-1) if ROUND)) >>> S, -128, 127)"""
        y = self.y[n]
        m = self.rq_m[n]
        s = self.rq_s[n]
        prod = y * m
        if self.rq_r[n]:
            prod += (1 << (s - 1))
        v = prod >> s
        if v > 127:
            v = 127
        elif v < -128:
            v = -128
        return v


# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------

class Iss:
    def __init__(self, mem):
        self.mem = mem
        self.x = [0] * 32
        self.pc = RESET_VECTOR
        self.halted = False
        self.ame = AmeModel(mem)
        # CSR
        self.mstatus_mie = 0
        self.mstatus_mpie = 0
        self.mtvec = 0x0000_0100
        self.mscratch = 0
        self.mepc = 0
        self.mcause = 0
        self.flags = 0
        self.mcycle = 0
        self.minstret = 0

    def rd32(self, a):
        b = self.mem[a & ~3:(a & ~3) + 4]
        return int.from_bytes(b, "little")

    def wr_bytes(self, a, data, nbytes):
        for i in range(nbytes):
            self.mem[(a + i) & M32] = (data >> (8 * i)) & 0xFF

    def csr_read(self, addr):
        if addr == 0x300:
            return (self.mstatus_mpie << 7) | (self.mstatus_mie << 3)
        if addr == 0x305:
            return self.mtvec
        if addr == 0x340:
            return self.mscratch
        if addr == 0x341:
            return self.mepc
        if addr == 0x342:
            return self.mcause
        if addr == 0x7C2:
            return self.flags
        if addr in (0xB00, 0xC00):
            return self.mcycle & M32
        if addr in (0xB80, 0xC80):
            return (self.mcycle >> 32) & M32
        if addr in (0xB02, 0xC02):
            return self.minstret & M32
        if addr in (0xB82, 0xC82):
            return (self.minstret >> 32) & M32
        return 0

    def csr_legal(self, addr):
        return addr in (0x300, 0x305, 0x340, 0x341, 0x342, 0x7C2,
                        0xB00, 0xB80, 0xB02, 0xB82,
                        0xC00, 0xC80, 0xC02, 0xC82)

    def csr_ro(self, addr):
        return addr in (0xC00, 0xC80, 0xC02, 0xC82)

    def csr_write(self, addr, val, f3):
        if f3 in (1, 5):
            new = val
        elif f3 in (2, 6):
            new = self.csr_read(addr) | val
        else:
            new = self.csr_read(addr) & ~val & M32
        if addr == 0x300:
            self.mstatus_mpie = (new >> 7) & 1
            self.mstatus_mie = (new >> 3) & 1
        elif addr == 0x305:
            self.mtvec = new
        elif addr == 0x340:
            self.mscratch = new
        elif addr == 0x341:
            self.mepc = new
        elif addr == 0x342:
            self.mcause = new
        elif addr == 0x7C2:
            self.flags = new & M32
        elif addr == 0xB00:
            self.mcycle = (self.mcycle & 0xFFFFFFFF00000000) | val
        elif addr == 0xB80:
            self.mcycle = ((val << 32) & 0xFFFFFFFF00000000) | (self.mcycle & M32)
        elif addr == 0xB02:
            self.minstret = (self.minstret & 0xFFFFFFFF00000000) | val
        elif addr == 0xB82:
            self.minstret = ((val << 32) & 0xFFFFFFFF00000000) | (self.minstret & M32)

    def set_flag(self, bit):
        self.flags |= (1 << bit)

    def step(self, trace):
        if self.halted:
            return False
        pc = self.pc
        instr = self.rd32(pc)
        rd_we, rd_idx, wdata, skip = 0, 0, 0, 0
        npc = pc + 4

        opcode = instr & 0x7F
        rd = (instr >> 7) & 0x1F
        f3 = (instr >> 12) & 0x7
        rs1i = (instr >> 15) & 0x1F
        rs2i = (instr >> 20) & 0x1F
        f7 = (instr >> 25) & 0x7F
        rs1 = self.x[rs1i]
        rs2 = self.x[rs2i]
        imm_i = instr >> 20
        if imm_i & 0x800:
            imm_i -= 0x1000
        imm_s = ((instr >> 25) << 5) | ((instr >> 7) & 0x1F)
        if imm_s & 0x800:
            imm_s -= 0x1000
        imm_b = (((instr >> 31) & 1) << 12) | (((instr >> 7) & 1) << 11) \
            | (((instr >> 25) & 0x3F) << 5) | (((instr >> 8) & 0xF) << 1)
        if imm_b & 0x1000:
            imm_b -= 0x2000
        imm_u = instr & 0xFFFFF000
        imm_j = (((instr >> 31) & 1) << 20) | (((instr >> 12) & 0xFF) << 12) \
            | (((instr >> 20) & 1) << 11) | (((instr >> 21) & 0x3FF) << 1)
        if imm_j & 0x100000:
            imm_j -= 0x200000

        def wreg(val):
            nonlocal rd_we, wdata
            if rd != 0:
                rd_we, wdata = 1, val & M32
                self.x[rd] = val & M32

        illegal = 0
        if opcode == 0x37:      # LUI
            wreg(imm_u)
        elif opcode == 0x17:    # AUIPC
            wreg(pc + imm_u)
        elif opcode == 0x6F:    # JAL
            wreg(pc + 4)
            npc = pc + imm_j
        elif opcode == 0x67:    # JALR
            if f3 == 0:
                wreg(pc + 4)
                npc = (rs1 + imm_i) & ~1 & M32
            else:
                illegal = 1
        elif opcode == 0x63:    # branch
            if f3 in (0, 1, 4, 5, 6, 7):
                take = {0: rs1 == rs2, 1: rs1 != rs2,
                        4: s32(rs1) < s32(rs2), 5: s32(rs1) >= s32(rs2),
                        6: rs1 < rs2, 7: rs1 >= rs2}[f3]
                if take:
                    npc = pc + imm_b
            else:
                illegal = 1
        elif opcode == 0x03:    # load
            addr = (rs1 + imm_i) & M32
            if f3 == 0:
                v = sext8(self.mem[addr])
            elif f3 == 1:
                v = sext16(int.from_bytes(self.mem[addr:addr + 2], "little"))
            elif f3 == 2:
                v = self.rd32(addr)
            elif f3 == 4:
                v = self.mem[addr]
            elif f3 == 5:
                v = int.from_bytes(self.mem[addr:addr + 2], "little")
            else:
                illegal = 1
                v = 0
            if not illegal:
                if (f3 in (0, 4) and addr % 1) or (f3 in (1, 5) and addr % 2) \
                        or (f3 == 2 and addr % 4):
                    illegal, v = 1, 0
                else:
                    wreg(v)
        elif opcode == 0x23:    # store
            addr = (rs1 + imm_s) & M32
            if f3 in (0, 1, 2):
                mis = (f3 == 1 and addr % 2) or (f3 == 2 and addr % 4)
                if not mis:
                    self.wr_bytes(addr, rs2, 1 << f3)
                else:
                    illegal = 1
            else:
                illegal = 1
        elif opcode == 0x13:    # op-imm
            sh = rs2i
            if f3 == 0:
                wreg(rs1 + imm_i)
            elif f3 == 1 and f7 == 0x00:
                wreg(rs1 << sh)
            elif f3 == 2:
                wreg(1 if s32(rs1) < imm_i else 0)
            elif f3 == 3:
                wreg(1 if rs1 < (imm_i & M32) else 0)
            elif f3 == 4:
                wreg(rs1 ^ (imm_i & M32))
            elif f3 == 5 and f7 == 0x00:
                wreg(rs1 >> sh)
            elif f3 == 5 and f7 == 0x20:
                wreg(s32(rs1) >> sh)
            elif f3 == 6:
                wreg(rs1 | (imm_i & M32))
            elif f3 == 7:
                wreg(rs1 & (imm_i & M32))
            else:
                illegal = 1
        elif opcode == 0x33:    # op
            if f7 == 0x00:
                wreg({0: rs1 + rs2, 1: rs1 << (rs2 & 31),
                      2: 1 if s32(rs1) < s32(rs2) else 0,
                      3: 1 if rs1 < rs2 else 0, 4: rs1 ^ rs2,
                      5: rs1 >> (rs2 & 31), 6: rs1 | rs2, 7: rs1 & rs2}[f3])
            elif f7 == 0x20:
                if f3 == 0:
                    wreg(rs1 - rs2)
                elif f3 == 5:
                    wreg(s32(rs1) >> (rs2 & 31))
                else:
                    illegal = 1
            elif f7 == 0x01:
                a, b = s32(rs1), s32(rs2)
                if f3 == 0:
                    wreg(rs1 * rs2)
                elif f3 == 1:
                    wreg(((a * b) & 0xFFFFFFFFFFFFFFFF) >> 32)
                elif f3 == 2:
                    wreg(((a * rs2) & 0xFFFFFFFFFFFFFFFF) >> 32)
                elif f3 == 3:
                    wreg(((rs1 * rs2) & 0xFFFFFFFFFFFFFFFF) >> 32)
                elif f3 == 4:
                    wreg(-0x80000000 if (a == -0x80000000 and b == -1)
                         else (0xFFFFFFFF if b == 0 else trunc_div(a, b)))
                elif f3 == 5:
                    wreg(0xFFFFFFFF if rs2 == 0 else rs1 // rs2)
                elif f3 == 6:
                    wreg(0 if (a == -0x80000000 and b == -1)
                         else (a if b == 0 else a - b * trunc_div(a, b)))
                elif f3 == 7:
                    wreg(a if rs2 == 0 else rs1 % rs2)
            else:
                illegal = 1
        elif opcode == 0x0F:    # fence
            if f3 not in (0, 1):
                illegal = 1
        elif opcode == 0x73:    # system
            if f3 == 0:
                imm12 = instr >> 20
                if imm12 == 0x000:
                    self.set_flag(3)
                elif imm12 == 0x001:
                    rd_we, rd_idx, wdata = 0, rd, 0
                    self.halted = True
                    self.set_flag(4)
                elif imm12 == 0x302:       # mret
                    npc = self.mepc & ~1 & M32
                    self.mstatus_mie = self.mstatus_mpie
                    self.mstatus_mpie = 1
                elif imm12 == 0x105:
                    pass
                else:
                    illegal = 1
            elif f3 in (1, 2, 3, 5, 6, 7):
                addr12 = instr >> 20
                pure_rd = (f3 in (2, 6)) and rs1i == 0
                if not self.csr_legal(addr12) or (self.csr_ro(addr12) and not pure_rd):
                    illegal = 1
                else:
                    old = self.csr_read(addr12)
                    wreg(old)
                    if not pure_rd:
                        self.csr_write(addr12, rs1 if f3 < 5 else rs1i, f3)
                    if addr12 in (0xB00, 0xC00, 0xB80, 0xC80):
                        skip = 1
            else:
                illegal = 1
        elif opcode == 0x0B:    # AME custom-0
            if f3 == 0x0:
                data, err = self.ame.step(instr, rs1, rs2)
            else:
                f7c = f7
                valid = {(0x1, 0x1), (0x2, 0x02), (0x3, 0x03), (0x4, 0x04),
                         (0x4, 0x05), (0x5, 0x06), (0x6, 0x07), (0x7, 0x08)}
                if (f3, f7c) not in valid:
                    illegal = 1
                    data, err = 0, 0
                else:
                    data, err = self.ame.step(instr, rs1, rs2)
                    if err:
                        self.set_flag(1)
                    if f3 in (0x5, 0x6) and rd != 0:
                        wreg(data)
        else:
            illegal = 1

        if illegal:
            self.set_flag(0)

        flags = (skip << 1) | (rd_we and rd != 0)
        trace.append(f"{pc:08x} {instr:08x} {rd:02x} {wdata:08x} {flags:x}")

        self.pc = npc & M32
        self.mcycle += 1
        self.minstret += 1
        return not self.halted


def s32(v):
    v &= M32
    return v - 0x100000000 if v & 0x80000000 else v


def sext8(v):
    return v - 0x100 if v & 0x80 else v


def sext16(v):
    return v - 0x10000 if v & 0x8000 else v


def trunc_div(a, b):
    q = abs(a) // abs(b)
    return -q if (a < 0) != (b < 0) else q


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("hex")
    ap.add_argument("-o", "--out", required=True)
    ap.add_argument("--max-steps", type=int, default=500000)
    args = ap.parse_args()

    mem = bytearray(1 << 20)
    load_hex(args.hex, mem)
    iss = Iss(mem)
    trace = []
    for _ in range(args.max_steps):
        if not iss.step(trace):
            break
    else:
        print("cpu_iss: ERROR max-steps exceeded (no ebreak)", file=sys.stderr)
        return 1
    if not iss.halted:
        print("cpu_iss: ERROR program did not halt (ebreak)", file=sys.stderr)
        return 1
    with open(args.out, "w", encoding="utf-8") as f:
        f.write("\n".join(trace) + "\n")
    print(f"cpu_iss: {args.hex} -> {args.out} ({len(trace)} instructions)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
