# RV32I ALU 边界值:加/减溢出、移位 0/1/31、逻辑、SLT/SLTU、LUI/AUIPC
  .org 0x10000
boot:
  j start

  .org 0x0
start:
  li x1, 0x7FFFFFFF
  addi x2, x1, 1          # 溢出 → 0x80000000
  addi x3, x2, -1         # → 0x7FFFFFFF
  li x4, 0x80000000
  addi x5, x4, -1         # → 0x7FFFFFFF
  sub x6, x4, x1          # 0x80000000-0x7FFFFFFF = 1
  sub x7, x1, x4          # → 0xFFFFFFFF
  add x8, x4, x4          # 0x00000000(回卷)

  li x9, 1
  sll x10, x9, x0         # 移 0
  li x11, 31
  sll x12, x9, x11        # 0x80000000
  srl x13, x12, x11       # 1
  sra x14, x12, x11       # 0xFFFFFFFF
  li x15, 0xF0F0F0F0
  srai x16, x15, 4        # 0xFF0F0F0F
  srli x17, x15, 4        # 0x0F0F0F0F
  slli x18, x15, 8        # 0xF0F0F000
  sll x19, x15, x11       # 移位量只取低 5 位:31 → 0xF0000000
  sra x20, x12, x0        # 移 0:符号不变

  xori x21, x15, -1       # 0x0F0F0F0F
  ori  x22, x0, -16       # 0xFFFFFFF0
  andi x23, x15, 0xFF     # 0xF0
  xor x24, x15, x15       # 0
  or  x25, x15, x0
  and x26, x15, x12

  slt x27, x4, x9         # 有符号:0x80000000 < 1 → 1
  slt x28, x9, x4         # → 0
  sltu x29, x4, x9        # 无符号:0x80000000 < 1 → 0
  sltu x30, x9, x4        # → 1
  slti x31, x4, 0         # 1
  sltiu x5, x4, -1        # 0x80000000 < 0xFFFFFFFF → 1

  auipc x6, 0             # x6 = 当前 pc
  auipc x7, 1             # pc+0x1000
  lui x8, 0x12345
  lui x9, -1              # 0xFFFFF000

  # 写几个结果到内存防优化(顺序提交本身即被差分覆盖)
  li x28, 0x1FFF0
  sw x2, 0(x28)
  sw x12, 4(x28)
  sw x16, 8(x28)
  sw x27, 12(x28)
  ebreak
