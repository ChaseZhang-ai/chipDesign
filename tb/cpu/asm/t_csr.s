# CSR 最小集:mstatus/mtvec/mscratch/mepc/mcause/flags/计数器 + 非法 CSR
  .org 0x10000
boot:
  j start

  .org 0x0
start:
  # mscratch:RW 三种操作
  li x1, 0x12345678
  csrw mscratch, x1        # csrrw x0, mscratch, x1
  csrr x2, mscratch        # = 0x12345678
  li x3, 0x0000FFFF
  csrs mscratch, x3        # |= → 0x1235FFFF
  csrr x4, mscratch
  csrc mscratch, x3        # &= ~ → 0x12345678
  csrr x5, mscratch
  csrrci x6, mscratch, 0xF # 清低 4 位 → 0x12345670
  csrrsi x7, mscratch, 1   # |=1 → 0x12345671

  # mstatus:MIE/MPIE
  li x8, 0x88              # MIE=1, MPIE=1
  csrw mstatus, x8
  csrr x9, mstatus         # = 0x88
  li x10, 0x8
  csrc mstatus, x10        # MIE=0
  csrr x11, mstatus        # = 0x80
  csrsi mstatus, 0x8       # MIE=1
  csrr x12, mstatus

  # mtvec 写读
  li x13, 0x00000200
  csrw mtvec, x13
  csrr x14, mtvec

  # mepc/mcause 写读 + mret 跳转
  li x15, 0x00000500
  csrw mepc, x15
  li x16, 0x2
  csrw mcause, x16
  csrr x17, mepc
  mret                     # 跳 0x500
  addi x18, x18, 1         # 跳过后不执行

  .org 0x500
mret_target:
  addi x18, x18, 2         # 执行
  csrw mepc, x16           # mepc = 2?? 会跳 0x2 → 未初始化区域... 改回主路径
  li x19, next_mret
  csrw mepc, x19
  mret
  j bad

  .org 0x1000              # 与上面代码避开:主流程继续段
next_mret:
  # flags:置位/清除
  csrr x20, flags
  li x21, 0x3
  csrs flags, x21          # 置 bit0/bit1(软件写)
  csrr x22, flags
  csrc flags, x21
  csrr x23, flags

  # 非法 CSR 地址 → 非法 NOP + flags[0](两侧一致)
  csrr x24, 0x7FF
  csrrw x25, 0x401, x0

  # RO 别名:纯读合法(csrrs x0 形式)
  csrr x26, instret        # 与 ISS 可比
  csrr x27, cycle          # skip 标志
  csrrw x28, cycle, x0     # 写 RO(非纯读)→ 非法
  csrr x29, flags          # bit0 已再置位

  # mcycle/minstret
  csrr x30, minstret
  csrr x31, mcycle

  j end
bad:
  li x1, 999
end:
  ebreak
