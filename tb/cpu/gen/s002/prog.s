# 随机生成(cpu_gen_random.py)
  .org 0x10000
boot:
  j start
  .org 0x0
start:
  li x1, 1
  li x2, -1
  li x3, -1
  li x4, 65535
  li x5, 2147483647
  li x6, 1431655765
  li x7, -344865
  li x8, -2147483648
  li x9, 1
  li x10, 2147483647
  li x11, 31
  li x12, 4294901760
  li x13, 255
  li x14, 65535
  li x15, 128
  li x28, 0x4000
.blk0:
  sw x5, 72(x28)
  rem x8, x15, x6
  lh x15, 336(x28)
  and x4, x4, x1
  slt x3, x3, x9
  mulhsu x9, x11, x9
.blk1:
  lh x12, 744(x28)
  mulhsu x6, x14, x8
  lhu x12, 944(x28)
  sb x4, 1000(x28)
  sh x9, 724(x28)
  lbu x6, 932(x28)
.blk2:
  and x6, x14, x12
  bge x5, x13, .fwd1
  srai x14, x9, 26
  andi x5, x12, -31
  .fwd1:
  sb x6, 152(x28)
  csrr x1, minstret
  csrr x2, minstret
  blt x11, x1, .fwd2
  xori x15, x15, 255
  slti x3, x14, 305419896
  .fwd2:
  add x15, x1, x7
  ori x6, x6, 305419896
.blk3:
  xori x2, x2, 0
  addi x12, x15, 65535
  and x3, x14, x15
  csrr x3, minstret
  mulhu x10, x1, x13
  sltiu x1, x1, 2
  xor x6, x8, x1
  lb x9, 92(x28)
.blk4:
  bge x12, x3, .blk5
  sltiu x11, x11, 2
  ori x8, x13, 255
  bge x13, x7, .fwd3
  .fwd3:
  srl x5, x5, x10
  bltu x1, x12, .blk5
.blk5:
  ori x5, x1, 2147483647
  andi x2, x8, 255
  ame.cfg 16, 16
  li x20, 3
  li x21, 65
  ame.qcfg 0, x20, x21
  li x22, 0
  li x23, 5
  li x24, 0
  li x25, 528
  li x26, 1
  srli x4, x4, 4
  sltu x2, x10, x4
  blt x12, x6, .fwd4
  addi x9, x13, -2
  .fwd4:
  ori x7, x7, 2
  sw x12, 176(x28)
.blk6:
  andi x1, x3, 2
  sra x1, x9, x11
  lw x5, 776(x28)
.blk7:
  srl x12, x13, x7
  sh x1, 104(x28)
  sw x10, 368(x28)
  ame.sync
  li x27, 11
  ame.st.y x27, x9
  slti x10, x6, 65535
  srl x1, x14, x11
  andi x2, x5, 0
  lhu x1, 840(x28)
.blk8:
  lw x4, 148(x28)
  sub x1, x6, x5
  sub x13, x8, x4
  bgeu x6, x7, .fwd5
  xori x7, x15, -344865
  .fwd5:
  sltiu x2, x2, 4294901760
  sltu x12, x2, x1
.blk9:
  sh x13, 88(x28)
  sll x6, x8, x3
  sra x8, x9, x14
  csrs mscratch, x12
  ame.ld.w x23
  ame.ld.x x24
  slti x8, x10, 128
  lh x12, 172(x28)
  csrr x14, minstret
.blk10:
  rem x3, x9, x3
  addi x13, x2, -2
  sll x7, x4, x12
.blk11:
  and x9, x5, x2
  sw x13, 864(x28)
  slt x9, x4, x12
  sra x3, x15, x3
  ame.ld.w x23
  ame.ld.x x25
  ame.exe x26
  ame.sync
  mulhsu x13, x13, x10
.blk12:
  lh x12, 60(x28)
  rem x15, x12, x3
  sb x1, 988(x28)
  lhu x5, 844(x28)
  bltu x8, x6, .fwd6
  xori x15, x11, 305419896
  andi x9, x10, 4294901760
  .fwd6:
  ame.sync
  li x27, 0
  ame.st.q x27, x8
.blk13:
  ame.sync
  li x27, 5
  ame.st.y x27, x1
  lw x4, 788(x28)
  srai x7, x14, 12
  sltu x12, x15, x10
  and x8, x13, x10
  slli x10, x11, 30
  sra x9, x10, x3
.blk14:
  add x13, x2, x6
  sh x9, 132(x28)
  ame.ld.w x23
  ame.ld.x x25
  sw x8, 56(x28)
  bne x13, x6, .blk15
  lw x5, 276(x28)
  srli x8, x7, 18
  srai x1, x5, 29
.blk15:
  rem x1, x9, x14
  bgeu x8, x4, .fwd7
  srai x3, x8, 19
  sltiu x2, x5, 1431655765
  .fwd7:
  srl x11, x13, x5
.blk16:
  andi x9, x11, 4294901760
  bne x9, x14, .blk17
  beq x2, x5, .fwd8
  srai x9, x4, 17
  .fwd8:
  slli x2, x2, 23
  sll x6, x6, x2
  lbu x6, 340(x28)
  lbu x14, 596(x28)
.blk17:
  ame.sync
  li x27, 6
  ame.st.q x27, x6
  andi x2, x15, -31
  sll x13, x11, x14
  and x6, x3, x13
.blk18:
  srl x13, x9, x11
  lb x13, 700(x28)
  csrr x15, flags
  csrr x7, flags
.blk19:
  beq x11, x11, .fwd9
  slti x8, x3, 65535
  .fwd9:
  lw x8, 176(x28)
  sub x7, x3, x1
  rem x3, x6, x2
  andi x9, x6, 4294901760
  sw x5, 960(x28)
  remu x6, x4, x15
.blk20:
  sltiu x13, x4, -344865
  slti x7, x6, -1
  or x4, x4, x12
.blk21:
  blt x1, x6, .fwd10
  ori x1, x14, 2147483647
  slli x14, x2, 28
  .fwd10:
  sltu x3, x6, x9
  slli x6, x11, 14
  srli x7, x13, 31
  bltu x14, x6, .blk22
  bltu x2, x10, .fwd11
  srli x7, x14, 10
  .fwd11:
  lw x7, 924(x28)
  ori x8, x10, 2
.blk22:
  sw x15, 356(x28)
  lhu x5, 936(x28)
  sltiu x5, x2, 305419896
  sub x1, x3, x7
  add x14, x11, x8
  sh x4, 132(x28)
  ori x9, x1, 255
  sw x1, 96(x28)
.blk23:
  srai x14, x14, 21
  ame.ld.w x23
  ame.ld.x x25
  ame.exef x26
  ame.sync
  mulh x8, x1, x3
  add x2, x8, x4
  bge x4, x11, .fwd12
  srai x14, x7, 10
  ori x9, x2, -2147483648
  .fwd12:
  sll x7, x4, x5
  lw x3, 872(x28)
.blk24:
  sub x13, x5, x13
  blt x2, x8, .fwd13
  slli x5, x4, 8
  .fwd13:
  ame.ld.w x22
  ame.ld.x x24
  ame.exef x24
  ame.sync
  bne x9, x13, .fwd14
  ori x10, x1, 0
  .fwd14:
  csrc mscratch, x5
  andi x12, x13, -2
.blk25:
  sub x1, x12, x4
  srai x11, x12, 11
  srli x11, x15, 18
  xor x3, x14, x6
  sh x10, 136(x28)
  lbu x11, 68(x28)
  xor x11, x14, x2
.blk26:
  slt x7, x6, x5
  csrr x7, minstret
  lhu x13, 260(x28)
.blk27:
  lb x14, 928(x28)
  mulhu x8, x10, x5
  bne x8, x8, .blk28
  beq x6, x5, .fwd15
  srli x11, x14, 14
  ori x13, x10, 1431655765
  .fwd15:
.blk28:
  sw x14, 612(x28)
  addi x13, x14, -2147483648
  xor x1, x6, x9
  csrr x11, flags
.blk29:
  addi x7, x8, 1431655765
  bne x10, x3, .fwd16
  xori x13, x7, 32
  xori x15, x5, -31
  .fwd16:
  sw x13, 484(x28)
  bne x5, x14, .fwd17
  sltiu x15, x14, 4294901760
  andi x9, x7, -2147483648
  .fwd17:
  bgeu x1, x5, .fwd18
  slli x12, x7, 7
  slli x8, x7, 30
  .fwd18:
  mulhu x5, x4, x4
.blk30:
  sw x9, 184(x28)
  slli x7, x12, 25
  sll x9, x5, x2
.blk31:
  mulh x9, x13, x8
  ame.sync
  li x27, 7
  ame.st.q x27, x1
  ori x8, x1, -2
  add x6, x4, x9
  blt x3, x11, .blk32
  srai x11, x9, 5
  ame.ld.w x23
  ame.ld.x x25
  ame.exe x26
  ame.sync
.blk32:
  srai x1, x5, 17
  sb x1, 724(x28)
  ame.ld.w x22
  ame.ld.x x24
  ame.exe x24
  ame.sync
  sltiu x10, x13, 65535
  bge x5, x13, .blk33
  sw x10, 304(x28)
  addi x6, x7, 65535
  ame.ld.w x22
  ame.ld.x x24
  ame.exef x24
  ame.sync
.blk33:
  sh x9, 888(x28)
  lw x4, 372(x28)
  bltu x1, x1, .blk34
  csrr x14, flags
  ame.ld.w x23
  ame.ld.x x25
  ame.exe x26
  ame.sync
  addi x15, x14, 305419896
  bne x13, x15, .fwd19
  xori x2, x15, 305419896
  .fwd19:
  add x9, x4, x2
.blk34:
  lh x2, 572(x28)
  bltu x4, x1, .fwd20
  slli x15, x7, 8
  ori x3, x7, 32
  .fwd20:
  csrr x6, minstret
  bge x3, x9, .blk35
  bgeu x14, x13, .fwd21
  sltiu x10, x3, -2
  .fwd21:
  ori x5, x12, -2
  bgeu x7, x10, .fwd22
  andi x8, x8, 31
  .fwd22:
  lb x5, 448(x28)
.blk35:
  addi x14, x7, 31
  slt x15, x14, x1
  sb x10, 532(x28)
  sll x8, x12, x8
  sw x14, 944(x28)
  bne x14, x9, .fwd23
  srai x7, x2, 15
  .fwd23:
  csrr x11, mscratch
  lh x10, 944(x28)
.blk36:
  lbu x2, 796(x28)
  bgeu x13, x12, .blk37
  bne x6, x3, .fwd24
  srli x3, x7, 31
  ori x12, x12, 31
  .fwd24:
  srl x15, x6, x10
  xor x11, x12, x13
  ame.ld.w x22
  ame.ld.x x25
  bge x1, x4, .fwd25
  .fwd25:
.blk37:
  srl x10, x6, x12
  sll x12, x14, x15
  srli x9, x10, 25
  bge x15, x4, .blk38
  beq x1, x6, .fwd26
  .fwd26:
.blk38:
  ame.ld.w x22
  ame.ld.x x24
  ame.exef x24
  ame.sync
  sltu x7, x8, x11
  andi x15, x8, 305419896
  csrr x10, flags
  slli x6, x5, 31
  lw x13, 572(x28)
  sw x4, 748(x28)
  mulhsu x14, x6, x13
.blk39:
  sw x13, 460(x28)
  bge x8, x4, .blk40
  bne x4, x9, .fwd27
  ori x12, x6, -2147483648
  .fwd27:
  csrr x12, minstret
.blk40:
  bgeu x1, x13, .fwd28
  .fwd28:
  ame.ld.w x23
  ame.ld.x x25
  ame.exef x26
  ame.sync
  bgeu x2, x8, .fwd29
  .fwd29:
  add x7, x10, x14
  xori x6, x15, 1431655765
  srli x10, x6, 24
.blk41:
  ori x8, x3, 32
  bne x2, x5, .blk42
  sb x2, 596(x28)
.blk42:
  bne x15, x9, .fwd30
  .fwd30:
  or x10, x5, x8
  srli x12, x6, 3
.blk43:
  xor x14, x10, x6
  ame.ld.w x22
  ame.ld.x x24
  ame.exef x24
  ame.sync
  andi x14, x15, 0
  sll x2, x5, x2
.blk44:
  sb x13, 276(x28)
  andi x7, x12, 1431655765
  beq x13, x1, .fwd31
  .fwd31:
.blk45:
  addi x14, x9, -2
  csrc mscratch, x8
  div x8, x11, x5
  ori x15, x11, 2
  ori x14, x2, 65535
  ame.ld.w x23
  ame.ld.x x25
  ame.exe x26
  ame.sync
  bltu x11, x15, .fwd32
  .fwd32:
  bgeu x12, x13, .fwd33
  ori x2, x15, 31
  .fwd33:
.blk46:
  lb x11, 76(x28)
  lhu x15, 1016(x28)
  bne x6, x15, .fwd34
  .fwd34:
  ame.ld.w x22
  ame.ld.x x24
  ame.exef x24
  ame.sync
.blk47:
  mulhu x3, x7, x13
  bltu x5, x10, .blk48
  ori x2, x9, -2147483648
  ame.ld.w x22
  ame.ld.x x24
  ame.exe x24
  ame.sync
  andi x9, x4, 32
  ame.sync
  li x27, 14
  ame.st.y x27, x6
  srl x1, x6, x2
  slti x10, x2, 65535
.blk48:
  add x6, x7, x4
  ori x3, x3, 4294901760
  slti x2, x11, 31
  lbu x1, 224(x28)
  addi x12, x2, -2147483648
  lbu x1, 392(x28)
  xor x14, x3, x3
.blk49:
  xor x10, x4, x9
  sra x10, x7, x8
  mulhsu x13, x5, x7
  blt x13, x7, .blk50
  lh x9, 868(x28)
.blk50:
  add x9, x2, x10
  sltu x15, x7, x15
  lh x12, 180(x28)
  sw x8, 568(x28)
  or x6, x14, x2
  or x7, x3, x9
  sw x7, 332(x28)
  slt x14, x8, x3
.blk51:
  csrr x6, minstret
  add x15, x13, x9
  lbu x9, 64(x28)
.blk52:
  srl x4, x3, x12
  or x15, x14, x15
  bltu x14, x4, .blk53
  blt x5, x10, .fwd35
  srai x10, x7, 3
  srli x1, x13, 12
  .fwd35:
  bgeu x6, x5, .blk53
  blt x1, x8, .fwd36
  .fwd36:
  sra x6, x5, x12
.blk53:
  ame.ld.w x22
  ame.ld.x x25
  andi x7, x11, 2147483647
  mulhsu x12, x11, x8
  lw x12, 604(x28)
  ame.ld.w x23
  ame.ld.x x25
  ame.exef x26
  ame.sync
.blk54:
  ori x9, x10, 0
  srai x6, x4, 30
  lw x11, 672(x28)
  addi x2, x4, 255
  sw x1, 316(x28)
  sltu x5, x2, x1
.blk55:
  rem x15, x5, x2
  ame.ld.w x23
  ame.ld.x x25
  ame.exe x26
  ame.sync
  ori x4, x4, 31
.blk56:
  xori x10, x5, 305419896
  bne x4, x1, .blk57
  sltu x11, x14, x3
  andi x3, x2, 305419896
  or x6, x12, x2
  bne x3, x10, .blk57
  mulhu x8, x12, x3
.blk57:
  mulhu x5, x1, x2
  blt x5, x11, .fwd37
  slti x11, x1, -1
  .fwd37:
  sb x9, 284(x28)
  sltu x15, x10, x7
.blk58:
  bltu x14, x2, .fwd38
  ori x4, x15, -1
  ori x8, x2, -31
  .fwd38:
  andi x3, x7, -31
  rem x9, x11, x3
  xor x2, x6, x6
  lh x3, 504(x28)
  add x8, x13, x6
.blk59:
  andi x1, x2, 1431655765
  srai x13, x8, 14
  add x4, x14, x2
  xori x2, x7, 31
  bge x15, x10, .fwd39
  .fwd39:
  csrr x1, minstret
  andi x15, x14, 305419896
  slti x15, x12, 255
.blk60:
  and x2, x13, x13
  bgeu x5, x4, .fwd40
  .fwd40:
  ame.ld.w x22
  ame.ld.x x24
  ame.exef x24
  ame.sync
  ame.ld.w x22
  ame.ld.x x24
  ame.exe x24
  ame.sync
  lw x1, 4(x28)
  ame.ld.w x22
  ame.ld.x x24
  ame.ld.w x22
  ame.ld.x x24
.blk61:
  slti x7, x14, -31
  ori x5, x10, 2863311530
  mulhu x4, x10, x4
  sh x8, 228(x28)
.blk62:
  bgeu x14, x6, .blk63
  lbu x1, 876(x28)
  csrr x11, minstret
  bgeu x7, x9, .blk63
  srai x13, x11, 25
  xor x2, x8, x5
.blk63:
  lhu x4, 336(x28)
  add x14, x2, x13
  srl x9, x12, x3
  lhu x10, 64(x28)
  ame.ld.w x23
  ame.ld.x x25
  ame.exef x26
  ame.sync
  addi x15, x4, -344865
  sw x13, 372(x28)
  sh x6, 172(x28)
.blk64:
  beq x14, x3, .fwd41
  .fwd41:
  slti x11, x4, 1
  sra x14, x4, x11
  sh x12, 1004(x28)
  slli x1, x5, 13
  lbu x2, 928(x28)
  sw x14, 348(x28)
.blk65:
  bltu x3, x12, .blk66
  sb x3, 56(x28)
  csrr x13, minstret
  blt x12, x10, .fwd42
  ori x6, x10, -1
  .fwd42:
  bltu x4, x3, .blk66
.blk66:
  ame.ld.w x22
  ame.ld.x x24
  blt x1, x4, .fwd43
  ori x8, x7, 1
  slli x10, x11, 4
  .fwd43:
  or x3, x9, x9
  slti x5, x14, 2863311530
  sh x12, 564(x28)
.blk67:
  sltu x6, x9, x1
  xori x12, x10, 31
  lh x7, 936(x28)
  add x7, x13, x15
  sltu x1, x1, x3
  bne x6, x4, .blk68
  srai x15, x15, 22
  add x15, x15, x6
.blk68:
  and x11, x12, x5
  ame.ld.w x23
  ame.ld.x x25
  ame.exe x26
  ame.sync
  slt x8, x9, x9
.blk69:
  sltu x10, x6, x9
  bge x8, x7, .fwd44
  .fwd44:
  sb x3, 216(x28)
  lhu x8, 164(x28)
  lh x7, 924(x28)
.blk70:
  sb x1, 1016(x28)
  bgeu x7, x15, .fwd45
  .fwd45:
  slti x3, x14, 0
  srl x14, x1, x11
  srl x7, x12, x4
.blk71:
  xor x10, x7, x7
  slti x5, x3, 0
  sll x1, x4, x3
  sll x10, x4, x13
  mul x10, x3, x1
  xori x4, x7, 4294901760
  srl x3, x5, x4
.blk72:
  ame.sync
  li x27, 13
  ame.st.q x27, x2
  slt x8, x3, x12
  bge x14, x8, .fwd46
  andi x14, x10, 31
  .fwd46:
.blk73:
  sra x11, x15, x14
  bgeu x5, x4, .fwd47
  srai x1, x5, 16
  .fwd47:
  srl x6, x4, x10
  ori x2, x2, 2147483647
  or x5, x13, x9
  bgeu x4, x13, .fwd48
  srli x5, x9, 21
  ori x9, x13, -2147483648
  .fwd48:
.blk74:
  srli x5, x9, 30
  lb x11, 692(x28)
  addi x8, x8, 31
  sw x7, 372(x28)
.blk75:
  sra x9, x7, x5
  sltiu x15, x5, 31
  ame.ld.w x22
  ame.ld.x x24
  ame.exef x24
  ame.sync
  mulhu x12, x14, x11
  blt x10, x7, .fwd49
  slti x11, x3, 305419896
  .fwd49:
  beq x10, x2, .fwd50
  srli x12, x14, 0
  andi x14, x9, 0
  .fwd50:
  sltiu x9, x11, 2147483647
.blk76:
  xor x10, x10, x13
  lh x6, 316(x28)
  bltu x1, x11, .fwd51
  addi x15, x13, 4294901760
  .fwd51:
  csrr x3, minstret
  or x11, x2, x8
  add x4, x2, x5
.blk77:
  sub x7, x2, x12
  srl x12, x7, x4
  bge x12, x4, .fwd52
  .fwd52:
.blk78:
  xori x14, x9, 65535
  csrr x4, minstret
  div x12, x8, x6
.blk79:
  lh x13, 564(x28)
  beq x14, x2, .fwd53
  .fwd53:
  or x9, x4, x4
  srl x13, x7, x12
.blk80:
  addi x11, x5, 31
  sw x11, 940(x28)
  sub x6, x9, x10
  slli x9, x12, 23
  srli x12, x7, 24
.blk81:
  srli x2, x8, 30
  ame.ld.w x22
  ame.ld.x x24
  ame.exef x24
  ame.sync
  sll x12, x6, x7
  ame.ld.w x23
  ame.ld.x x25
  bge x13, x7, .blk82
  srai x15, x13, 9
  or x15, x12, x4
  slli x1, x1, 4
.blk82:
  sw x14, 944(x28)
  add x7, x3, x13
  ori x7, x7, 2147483647
  bne x5, x13, .fwd54
  .fwd54:
  sub x4, x12, x4
  sll x1, x13, x4
.blk83:
  sb x12, 304(x28)
  slti x9, x12, 305419896
  andi x9, x4, 32
.blk84:
  sb x9, 828(x28)
  ame.sync
  li x27, 1
  ame.st.y x27, x14
  blt x4, x2, .fwd55
  slli x1, x13, 7
  sltiu x4, x7, -31
  .fwd55:
.blk85:
  sltu x8, x13, x2
  bne x9, x9, .fwd56
  sltiu x8, x13, 32
  .fwd56:
  sw x8, 632(x28)
.blk86:
  bge x5, x10, .fwd57
  .fwd57:
  slli x1, x14, 7
  add x1, x5, x13
  sll x10, x15, x3
  blt x11, x14, .blk87
  xori x2, x5, -1
  andi x10, x13, 0
.blk87:
  beq x3, x12, .fwd58
  .fwd58:
  and x8, x11, x8
  bne x1, x13, .fwd59
  sltiu x12, x13, 2147483647
  .fwd59:
  blt x10, x8, .fwd60
  andi x15, x15, -1
  .fwd60:
  srli x6, x9, 0
.blk88:
  sltiu x11, x6, 1431655765
  sw x9, 16(x28)
  ame.ld.w x22
  ame.ld.x x25
  add x15, x5, x3
  lbu x3, 820(x28)
  csrr x2, flags
  lb x6, 520(x28)
  sh x1, 624(x28)
.blk89:
  srli x2, x13, 8
  srl x14, x11, x2
  bltu x14, x5, .blk90
  remu x14, x1, x11
  csrr x13, minstret
.blk90:
  sra x1, x3, x8
  srai x4, x14, 15
  bgeu x15, x9, .blk91
  ame.ld.w x22
  ame.ld.x x24
.blk91:
  lbu x4, 588(x28)
  csrr x2, minstret
  sb x1, 508(x28)
  add x10, x1, x15
  blt x6, x9, .fwd61
  addi x13, x12, 65535
  sltiu x10, x11, 305419896
  .fwd61:
  srl x1, x1, x6
  andi x10, x9, 32
.blk92:
  bgeu x8, x1, .blk93
  lbu x6, 320(x28)
  sltu x13, x10, x5
.blk93:
  slt x3, x12, x9
  lb x5, 104(x28)
  bgeu x6, x9, .fwd62
  ori x13, x5, -1
  ori x14, x15, 1431655765
  .fwd62:
  bltu x7, x6, .fwd63
  srli x5, x11, 18
  srai x2, x11, 17
  .fwd63:
  slt x2, x14, x10
.blk94:
  bltu x2, x15, .fwd64
  addi x11, x1, 31
  sltiu x11, x4, -2147483648
  .fwd64:
  lhu x14, 584(x28)
  lbu x6, 760(x28)
  sra x1, x9, x9
  or x8, x12, x14
  bge x15, x9, .fwd65
  andi x10, x12, 2
  srai x15, x7, 9
  .fwd65:
  lw x10, 768(x28)
  bge x15, x11, .blk95
.blk95:
  mul x7, x11, x5
  xor x2, x4, x9
  add x13, x1, x12
.blk96:
  slti x6, x14, 4294901760
  ame.sync
  li x27, 7
  ame.st.y x27, x13
  bltu x1, x11, .fwd66
  ori x14, x14, -2147483648
  .fwd66:
  lh x14, 960(x28)
  beq x1, x15, .blk97
.blk97:
  slt x7, x6, x5
  srl x11, x9, x12
  andi x11, x2, 0
  ame.sync
  li x27, 2
  ame.st.q x27, x10
  sub x11, x10, x10
  ame.ld.w x23
  ame.ld.x x25
.blk98:
  beq x7, x5, .blk99
  slt x15, x1, x8
  srai x3, x10, 25
  sb x11, 864(x28)
  andi x12, x14, 1431655765
  lbu x7, 124(x28)
  lh x4, 804(x28)
.blk99:
  bge x14, x3, .fwd67
  .fwd67:
  ame.ld.w x22
  ame.ld.x x25
  beq x14, x1, .fwd68
  slti x3, x8, 32
  xori x13, x2, 2863311530
  .fwd68:
  slti x8, x10, -344865
  sb x4, 396(x28)
.blk100:
  srl x15, x14, x4
  csrr x13, flags
  sb x12, 112(x28)
  slli x6, x5, 19
  bgeu x8, x14, .fwd69
  andi x14, x5, 4294901760
  srli x3, x5, 23
  .fwd69:
  srli x14, x15, 25
.blk101:
  csrr x6, mscratch
  sltu x14, x12, x5
  addi x15, x11, -1
  beq x3, x2, .fwd70
  addi x3, x9, 65535
  xori x9, x6, -1
  .fwd70:
.blk102:
  ame.ld.w x23
  ame.ld.x x25
  ame.exe x26
  ame.sync
  csrr x15, flags
  and x10, x7, x1
  ame.ld.w x22
  ame.ld.x x25
  lw x7, 888(x28)
  sra x13, x13, x7
.blk103:
  or x7, x12, x7
  sub x13, x13, x14
  sw x7, 992(x28)
  srli x2, x4, 11
  blt x4, x3, .fwd71
  addi x14, x15, 128
  .fwd71:
.blk104:
  and x4, x14, x5
  srai x5, x8, 30
  ame.ld.w x23
  ame.ld.x x25
  ame.exe x26
  ame.sync
  csrr x3, minstret
  srli x4, x7, 5
.blk105:
  xori x14, x13, 1431655765
  lw x13, 556(x28)
  sh x9, 224(x28)
  slt x14, x6, x3
  and x7, x10, x2
.blk106:
  ame.ld.w x23
  ame.ld.x x24
  or x7, x5, x3
  divu x11, x9, x15
.blk107:
  xor x12, x8, x11
  slti x7, x5, -344865
  ame.ld.w x22
  ame.ld.x x24
  ame.exe x24
  ame.sync
.blk108:
  bltu x8, x1, .fwd72
  xori x4, x12, 31
  .fwd72:
  sll x2, x5, x9
  sb x15, 248(x28)
  sltu x4, x3, x2
  csrr x9, minstret
.blk109:
  ori x3, x13, 31
  sw x10, 764(x28)
  ame.sync
  li x27, 10
  ame.st.y x27, x10
  slli x8, x3, 15
  ame.ld.w x23
  ame.ld.x x25
  bgeu x13, x13, .fwd73
  srli x13, x11, 0
  .fwd73:
.blk110:
  sw x15, 428(x28)
  slt x12, x10, x5
  xor x6, x1, x8
  ori x6, x7, -2
  andi x9, x4, 255
.blk111:
  blt x4, x8, .fwd74
  sltiu x14, x9, -2147483648
  addi x13, x10, 2147483647
  .fwd74:
  csrr x6, flags
  sltu x11, x7, x6
  sb x3, 392(x28)
  lw x14, 704(x28)
  csrr x15, flags
  bltu x4, x13, .blk112
  bne x8, x11, .blk112
.blk112:
  blt x6, x10, .blk113
  sw x10, 740(x28)
  lb x13, 872(x28)
  andi x13, x5, 4294901760
  addi x9, x4, -31
  ame.ld.w x23
  ame.ld.x x25
  ame.exe x26
  ame.sync
  lhu x7, 980(x28)
  bne x1, x4, .fwd75
  .fwd75:
.blk113:
  xor x12, x4, x13
  ame.ld.w x22
  ame.ld.x x24
  ame.exef x24
  ame.sync
  bne x10, x1, .blk114
  addi x12, x8, 305419896
.blk114:
  mul x10, x10, x15
  ame.ld.w x22
  ame.ld.x x25
  slt x3, x6, x7
  and x12, x11, x15
  ame.ld.w x23
  ame.ld.x x25
  ame.exe x26
  ame.sync
.blk115:
  lb x13, 540(x28)
  srl x7, x6, x4
  csrr x2, minstret
  sltiu x3, x15, 4294901760
.blk116:
  lbu x3, 8(x28)
  slli x8, x15, 5
  lb x14, 364(x28)
  sub x12, x12, x2
  sh x13, 492(x28)
  sra x4, x14, x14
.blk117:
  mulhu x6, x7, x7
  sra x14, x13, x2
  slli x6, x5, 5
  sw x14, 932(x28)
  andi x13, x5, 32
  or x7, x6, x15
  slt x12, x4, x14
.blk118:
  bltu x7, x8, .blk119
  sw x11, 464(x28)
  slti x14, x4, 1
  blt x7, x8, .blk119
  sltu x6, x12, x8
.blk119:
  ame.ld.w x23
  ame.ld.x x24
  lw x12, 808(x28)
  slti x15, x8, 2863311530
  slt x8, x15, x2
  blt x1, x2, .blk120
  lw x6, 512(x28)
  sw x15, 196(x28)
.blk120:
  blt x13, x4, .blk121
  sltu x9, x13, x7
  bne x6, x8, .fwd76
  sltiu x9, x14, 2863311530
  xori x14, x10, -1
  .fwd76:
  xor x6, x15, x9
  csrs mscratch, x2
.blk121:
  xori x10, x11, 2147483647
  srli x10, x2, 15
  lb x12, 216(x28)
  sw x10, 556(x28)
  sll x14, x3, x11
.blk122:
  remu x14, x15, x4
  srl x10, x7, x2
  lhu x2, 52(x28)
  sw x5, 416(x28)
  ori x5, x15, 128
  sh x6, 268(x28)
.blk123:
  sltu x9, x5, x1
  ame.ld.w x23
  ame.ld.x x25
  lb x15, 868(x28)
  lw x1, 500(x28)
  xor x11, x10, x1
.blk124:
  sh x7, 1012(x28)
  sltiu x15, x6, 255
  and x11, x6, x2
  blt x7, x10, .fwd77
  .fwd77:
  bne x5, x2, .fwd78
  ori x3, x11, 1
  xori x3, x11, -2147483648
  .fwd78:
  sltiu x5, x9, 1
  srl x2, x2, x5
  sub x4, x7, x15
.blk125:
  srli x1, x14, 9
  sh x15, 592(x28)
  sw x12, 212(x28)
  divu x6, x1, x12
.blk126:
  ame.sync
  li x27, 0
  ame.st.y x27, x8
  ori x14, x12, -31
  lw x13, 888(x28)
  sra x12, x1, x2
  blt x12, x1, .fwd79
  slli x15, x4, 6
  .fwd79:
.blk127:
  ame.ld.w x23
  ame.ld.x x25
  ame.exef x26
  ame.sync
  sltu x2, x1, x9
  blt x11, x14, .blk128
  srai x9, x5, 1
.blk128:
  or x10, x2, x9
  blt x7, x11, .fwd80
  addi x15, x7, 31
  .fwd80:
  blt x2, x4, .blk129
.blk129:
  ame.ld.w x22
  ame.ld.x x24
  ori x1, x2, 32
  bne x13, x8, .fwd81
  andi x1, x4, 31
  ori x9, x4, 305419896
  .fwd81:
  sll x12, x6, x13
  srl x2, x14, x14
.blk130:
  ori x11, x15, -344865
  srli x6, x7, 28
  sub x2, x6, x6
  sb x13, 232(x28)
  bge x13, x9, .blk131
  lw x10, 812(x28)
  bge x10, x14, .blk131
  ame.ld.w x22
  ame.ld.x x24
  ame.exe x24
  ame.sync
.blk131:
  slt x15, x12, x8
  blt x4, x3, .fwd82
  addi x6, x10, 2863311530
  ori x13, x3, -1
  .fwd82:
  add x12, x4, x13
.blk132:
  csrr x7, minstret
  sh x13, 560(x28)
  lhu x14, 596(x28)
  blt x6, x9, .fwd83
  srli x7, x7, 4
  .fwd83:
  srai x6, x2, 3
  sh x11, 64(x28)
  andi x3, x6, -1
  andi x1, x2, -2
.blk133:
  srai x9, x3, 26
  lbu x9, 252(x28)
  sh x4, 920(x28)
  addi x6, x9, 305419896
  lw x7, 160(x28)
  sw x4, 908(x28)
.blk134:
  blt x8, x11, .blk135
  and x5, x11, x2
  slli x3, x2, 12
  slti x5, x8, 0
  ame.ld.w x23
  ame.ld.x x25
  ame.exef x26
  ame.sync
.blk135:
  lw x2, 36(x28)
  lb x5, 208(x28)
  sltiu x5, x8, 255
.blk136:
  add x3, x11, x5
  add x12, x5, x7
  ame.sync
  li x27, 3
  ame.st.y x27, x4
  srli x7, x7, 17
.blk137:
  srai x2, x5, 30
  sra x12, x7, x14
  sw x4, 164(x28)
  add x7, x6, x12
.blk138:
  sh x7, 904(x28)
  srai x4, x2, 9
  and x10, x6, x8
  divu x15, x8, x8
.blk139:
  bne x11, x6, .fwd84
  .fwd84:
  ame.ld.w x22
  ame.ld.x x25
  add x1, x11, x15
  bge x5, x15, .blk140
  andi x10, x14, 305419896
.blk140:
  ori x2, x7, -2
  bltu x2, x5, .fwd85
  andi x1, x15, 32
  srli x13, x1, 29
  .fwd85:
  ori x11, x9, 0
  mulhsu x3, x5, x6
  sb x15, 756(x28)
.blk141:
  sll x2, x10, x3
  sw x6, 776(x28)
  csrr x14, flags
  sub x1, x4, x13
  sub x1, x11, x4
  sub x7, x14, x5
  or x2, x3, x3
.blk142:
  slt x1, x10, x10
  sb x13, 832(x28)
  sb x9, 268(x28)
  srl x15, x8, x7
.blk143:
  beq x7, x13, .fwd86
  srli x12, x2, 3
  .fwd86:
  slt x10, x4, x11
  bltu x9, x5, .fwd87
  addi x13, x5, -1
  srli x14, x13, 19
  .fwd87:
  lb x15, 936(x28)
  bne x2, x5, .blk144
  lhu x7, 968(x28)
.blk144:
  sltu x9, x3, x12
  beq x12, x13, .fwd88
  slti x12, x5, 0
  .fwd88:
  sra x12, x9, x10
  or x3, x14, x3
  bgeu x5, x12, .blk145
  blt x9, x6, .fwd89
  .fwd89:
  lh x6, 800(x28)
  sub x14, x8, x2
.blk145:
  xori x4, x11, -31
  andi x3, x6, 2863311530
  csrr x10, minstret
  sra x2, x4, x3
  bltu x9, x7, .fwd90
  sltiu x9, x5, 305419896
  .fwd90:
  ame.ld.w x23
  ame.ld.x x24
  ame.ld.w x22
  ame.ld.x x24
  ame.exe x24
  ame.sync
.blk146:
  csrr x13, minstret
  addi x11, x11, 2147483647
  csrr x14, flags
.blk147:
  andi x3, x10, 2147483647
  srai x3, x9, 23
  lw x9, 756(x28)
  sb x13, 724(x28)
  addi x14, x6, 2
  andi x2, x12, -344865
.blk148:
  sub x7, x8, x1
  bge x8, x6, .fwd91
  slli x8, x5, 11
  .fwd91:
  ori x3, x11, -344865
  ame.ld.w x22
  ame.ld.x x24
  ame.exe x24
  ame.sync
  sra x6, x14, x4
  srl x5, x8, x4
  and x12, x1, x10
.blk149:
  sh x14, 160(x28)
  sltu x12, x8, x2
  sra x5, x15, x9
.blk150:
  csrr x2, minstret
  sltu x13, x4, x10
  addi x1, x1, -31
  mulh x11, x8, x10
  srl x7, x6, x1
  bgeu x5, x8, .blk151
  add x2, x11, x2
.blk151:
  bne x8, x12, .blk152
  bge x10, x5, .fwd92
  slti x12, x5, 4294901760
  .fwd92:
  bge x2, x8, .blk152
  bltu x8, x15, .fwd93
  .fwd93:
  lw x4, 156(x28)
  lw x10, 748(x28)
  andi x14, x12, 2
  srai x11, x11, 31
.blk152:
  sw x3, 856(x28)
  or x10, x5, x9
  lw x5, 756(x28)
.blk153:
  lhu x6, 744(x28)
  ame.ld.w x22
  ame.ld.x x24
  ame.exef x24
  ame.sync
  ame.ld.w x22
  ame.ld.x x24
  ame.exe x24
  ame.sync
  xor x12, x14, x4
  lbu x1, 860(x28)
  andi x7, x14, -31
  beq x6, x10, .blk154
  ame.ld.w x23
  ame.ld.x x25
  ame.exef x26
  ame.sync
.blk154:
  andi x14, x8, 2
  and x11, x13, x6
  lw x5, 468(x28)
.blk155:
  lw x1, 948(x28)
  lb x12, 844(x28)
  lh x5, 188(x28)
  or x2, x4, x6
.blk156:
  srai x1, x4, 26
  sra x2, x11, x12
  slt x1, x13, x12
  ame.ld.w x23
  ame.ld.x x24
  srai x3, x14, 22
.blk157:
  ori x12, x1, -31
  sub x5, x14, x12
  sub x2, x13, x5
  slli x12, x12, 13
.blk158:
  lw x3, 288(x28)
  lb x12, 232(x28)
  andi x12, x2, 1431655765
  lhu x9, 636(x28)
  srai x12, x8, 30
  blt x7, x3, .fwd94
  .fwd94:
  addi x9, x14, -2147483648
.blk159:
  lbu x6, 264(x28)
  sw x5, 252(x28)
  and x6, x1, x1
  or x13, x5, x15
  ame.ld.w x23
  ame.ld.x x25
  ame.exe x26
  ame.sync
  slli x5, x13, 4
.blk160:
  xor x15, x15, x5
  lw x12, 296(x28)
  ame.ld.w x22
  ame.ld.x x24
  bgeu x5, x4, .fwd95
  srli x10, x14, 13
  slti x15, x11, 305419896
  .fwd95:
.blk161:
  sra x1, x10, x8
  ame.sync
  li x27, 10
  ame.st.q x27, x12
  csrr x7, flags
  xori x7, x1, 1
  sltiu x2, x12, 65535
  srli x10, x15, 1
.blk162:
  sra x8, x2, x7
  xori x12, x1, 65535
  ori x4, x11, 65535
.blk163:
  sltiu x13, x2, 128
  srl x2, x15, x15
  ame.ld.w x23
  ame.ld.x x25
  ame.exe x26
  ame.sync
.blk164:
  divu x12, x1, x9
  bge x11, x9, .blk165
  csrr x1, minstret
  bgeu x6, x3, .fwd96
  addi x13, x12, 2863311530
  slli x11, x9, 16
  .fwd96:
.blk165:
  bge x9, x11, .fwd97
  srli x13, x2, 28
  .fwd97:
  ame.ld.w x23
  ame.ld.x x24
  bge x8, x3, .blk166
  divu x11, x4, x15
.blk166:
  sw x14, 872(x28)
  or x11, x1, x5
  srli x11, x7, 28
  xori x3, x12, -1
  ori x8, x5, 65535
.blk167:
  sb x5, 596(x28)
  add x6, x12, x2
  lbu x9, 640(x28)
  remu x11, x2, x5
.blk168:
  ame.ld.w x22
  ame.ld.x x24
  ame.exef x24
  ame.sync
  lbu x4, 584(x28)
  ame.ld.w x22
  ame.ld.x x24
  ame.exe x24
  ame.sync
  xori x15, x14, 255
.blk169:
  sltiu x14, x13, 65535
  sltiu x12, x10, -344865
  mul x5, x4, x3
  sub x13, x1, x13
  sb x7, 1008(x28)
  bne x14, x5, .fwd98
  .fwd98:
  addi x12, x11, 1431655765
  ame.ld.w x23
  ame.ld.x x25
  ame.exe x26
  ame.sync
.blk170:
  lw x12, 996(x28)
  remu x6, x1, x7
  csrr x7, minstret
.blk171:
  ori x14, x7, 2863311530
  and x10, x7, x11
  csrr x10, mscratch
  sh x10, 884(x28)
  lbu x13, 900(x28)
  csrr x13, flags
.blk172:
  ori x5, x11, -2
  sltiu x3, x11, 1431655765
  sw x13, 476(x28)
  slti x5, x15, -31
  slli x13, x14, 2
  srl x10, x12, x13
.blk173:
  ame.ld.w x23
  ame.ld.x x25
  ame.exe x26
  ame.sync
  sh x10, 280(x28)
  sub x10, x14, x7
  csrc mscratch, x11
  beq x2, x6, .fwd99
  srai x9, x13, 7
  slli x14, x9, 16
  .fwd99:
  slli x2, x12, 7
  sra x7, x6, x8
  xori x10, x1, -31
.blk174:
  sh x7, 408(x28)
  bge x13, x2, .blk175
  remu x11, x6, x10
  bgeu x11, x4, .blk175
.blk175:
  sra x1, x3, x9
  sw x13, 740(x28)
  csrr x2, flags
  andi x2, x8, 32
  add x4, x15, x7
  sltiu x14, x5, 1431655765
  xori x6, x7, 4294901760
  sb x13, 384(x28)
.blk176:
  sw x1, 712(x28)
  xori x15, x3, -2
  or x13, x6, x7
  srai x12, x1, 16
  srl x6, x9, x7
  sw x10, 332(x28)
  sltiu x5, x14, -2147483648
  or x11, x5, x15
.blk177:
  mulh x2, x9, x15
  bgeu x11, x9, .fwd100
  xori x11, x5, -2147483648
  .fwd100:
  csrr x12, minstret
  csrr x5, minstret
  slt x13, x10, x8
  ame.ld.w x22
  ame.ld.x x24
  ame.exef x24
  ame.sync
.blk178:
  sll x2, x8, x14
  ori x3, x6, -2147483648
  ame.sync
  li x27, 6
  ame.st.q x27, x12
.blk179:
  lh x11, 576(x28)
  add x3, x15, x7
  add x11, x2, x13
  add x10, x12, x5
  ame.ld.w x22
  ame.ld.x x25
  sb x8, 552(x28)
  sltu x5, x12, x11
.blk180:
  mulhu x10, x8, x12
  beq x6, x11, .blk181
  slli x1, x8, 8
  srl x9, x3, x4
  csrr x6, minstret
  xori x15, x12, 305419896
.blk181:
  andi x10, x6, 128
  slti x14, x12, 305419896
  bne x11, x14, .fwd101
  slli x7, x7, 31
  .fwd101:
  xori x13, x13, 2
  ame.ld.w x22
  ame.ld.x x24
  lbu x7, 300(x28)
.blk182:
  div x11, x12, x8
  sltu x2, x4, x4
  andi x14, x1, -2
.blk183:
  mulh x6, x11, x3
  sltu x13, x15, x7
  andi x9, x14, 0
  slti x3, x11, 4294901760
  sb x1, 356(x28)
  lb x5, 608(x28)
  ori x7, x5, 2147483647
  divu x9, x4, x14
.blk184:
  lh x9, 32(x28)
  sw x4, 120(x28)
  or x12, x1, x15
  bge x15, x13, .fwd102
  .fwd102:
  slt x13, x1, x8
  lh x2, 532(x28)
.blk185:
  lw x4, 676(x28)
  slli x15, x5, 9
  lhu x7, 108(x28)
.blk186:
  lw x2, 212(x28)
  ame.ld.w x23
  ame.ld.x x25
  sb x12, 0(x28)
  xor x12, x6, x3
  mulhsu x15, x10, x5
  sll x11, x12, x1
  bne x6, x7, .blk187
  blt x7, x14, .fwd103
  slti x5, x13, 31
  slti x11, x13, -2147483648
  .fwd103:
.blk187:
  srai x13, x10, 16
  xor x12, x4, x1
  ame.ld.w x22
  ame.ld.x x24
  ame.exef x24
  ame.sync
  srli x12, x3, 22
  slt x3, x3, x10
  beq x15, x4, .blk188
  sw x7, 792(x28)
  sh x1, 328(x28)
.blk188:
  lhu x12, 8(x28)
  bge x4, x1, .fwd104
  slli x11, x6, 26
  .fwd104:
  addi x8, x3, -2147483648
  ame.sync
  li x27, 4
  ame.st.y x27, x1
.blk189:
  csrr x10, minstret
  sra x7, x10, x1
  sltiu x3, x2, -344865
  srai x10, x6, 15
  slti x14, x12, 1
  sltu x2, x10, x1
  slt x11, x10, x6
.blk190:
  lw x9, 172(x28)
  add x12, x8, x15
  lb x10, 528(x28)
  slt x14, x10, x4
  lw x3, 948(x28)
  sll x2, x4, x8
  or x12, x8, x7
.blk191:
  ori x14, x4, 305419896
  beq x5, x11, .blk192
  sb x9, 856(x28)
.blk192:
  bne x6, x3, .fwd105
  xori x12, x3, 31
  .fwd105:
  blt x15, x14, .fwd106
  srli x12, x7, 14
  slli x9, x5, 1
  .fwd106:
  srai x9, x10, 31
  addi x11, x5, 2147483647
  bltu x11, x14, .blk193
.blk193:
  ame.ld.w x23
  ame.ld.x x25
  ame.exef x26
  ame.sync
  ame.ld.w x23
  ame.ld.x x25
  ame.exe x26
  ame.sync
  sb x14, 600(x28)
.blk194:
  sub x4, x10, x9
  sub x15, x5, x15
  ame.ld.w x23
  ame.ld.x x25
  ame.exef x26
  ame.sync
  srl x5, x10, x3
  sw x14, 1008(x28)
  ame.ld.w x22
  ame.ld.x x24
  ame.exe x24
  ame.sync
  mulhsu x9, x8, x4
  lbu x13, 720(x28)
.blk195:
  lhu x11, 616(x28)
  lh x12, 920(x28)
  bge x3, x12, .blk196
  bgeu x9, x10, .fwd107
  srli x8, x5, 29
  slli x12, x15, 31
  .fwd107:
  addi x13, x8, 0
  sll x11, x1, x12
  bltu x8, x3, .fwd108
  .fwd108:
  sltu x13, x6, x3
.blk196:
  addi x8, x13, 65535
  sw x9, 180(x28)
  sh x10, 200(x28)
  lh x8, 704(x28)
  sw x14, 704(x28)
.blk197:
  slt x3, x2, x6
  lh x9, 612(x28)
  lh x4, 756(x28)
  bne x14, x8, .blk198
.blk198:
  sb x14, 156(x28)
  div x4, x14, x12
  sw x13, 764(x28)
.blk199:
  xor x3, x12, x5
  csrr x4, minstret
  lhu x12, 220(x28)
.blk200:
  add x8, x8, x1
  andi x11, x5, -2147483648
  andi x5, x11, 65535
  andi x14, x15, -31
  add x15, x1, x5
  sltiu x6, x7, -2
.blk201:
  csrs mscratch, x6
  xori x15, x10, 2863311530
  blt x15, x5, .fwd109
  sltiu x7, x7, -1
  srai x10, x10, 18
  .fwd109:
  ame.ld.w x23
  ame.ld.x x25
  ame.exe x26
  ame.sync
  slli x14, x9, 1
  ame.sync
  li x27, 5
  ame.st.q x27, x15
  sh x9, 76(x28)
.blk202:
  add x8, x8, x1
  bge x1, x15, .fwd110
  srai x2, x12, 13
  .fwd110:
  ame.ld.w x22
  ame.ld.x x24
  ame.exef x24
  ame.sync
  bge x1, x9, .blk203
  sltiu x5, x5, 128
.blk203:
  lw x9, 152(x28)
  csrr x13, flags
  srai x12, x6, 13
  andi x12, x9, 2
.blk204:
  lb x12, 628(x28)
  sltu x4, x2, x6
  bne x3, x11, .blk205
.blk205:
  mulhsu x5, x8, x3
  xor x5, x6, x6
  sb x5, 876(x28)
  blt x6, x6, .fwd111
  .fwd111:
  ame.ld.w x23
  ame.ld.x x25
  ame.exe x26
  ame.sync
  srli x2, x15, 4
.blk206:
  blt x7, x15, .blk207
  sh x14, 500(x28)
  sltiu x13, x12, 2
.blk207:
  xor x5, x5, x1
  slt x3, x2, x8
  sltu x5, x7, x6
  sub x11, x14, x15
.blk208:
  and x15, x2, x7
  ame.ld.w x23
  ame.ld.x x25
  sltiu x3, x8, 0
  lbu x14, 88(x28)
  bgeu x8, x7, .fwd112
  srai x13, x12, 19
  .fwd112:
  div x3, x6, x15
  sltu x3, x12, x13
  bge x11, x12, .fwd113
  slti x11, x5, 2
  addi x4, x5, -344865
  .fwd113:
.blk209:
  lh x8, 460(x28)
  sb x10, 288(x28)
  lhu x2, 800(x28)
  blt x10, x1, .fwd114
  .fwd114:
  ame.ld.w x22
  ame.ld.x x25
  csrr x9, minstret
  lh x9, 844(x28)
  beq x1, x12, .fwd115
  slli x15, x1, 18
  .fwd115:
.blk210:
  sra x6, x13, x8
  csrr x15, minstret
  ame.ld.w x22
  ame.ld.x x25
  ori x14, x2, 1431655765
  slt x9, x1, x7
  slti x2, x15, 255
.blk211:
  slt x2, x8, x12
  sw x1, 212(x28)
  or x12, x14, x13
  sw x9, 660(x28)
.blk212:
  xor x11, x14, x1
  sltiu x2, x10, 31
  beq x15, x3, .blk213
  lw x3, 564(x28)
.blk213:
  bltu x7, x12, .blk214
  bne x8, x3, .blk214
  blt x15, x15, .fwd116
  slli x10, x13, 23
  .fwd116:
  addi x10, x12, -2
.blk214:
  ame.ld.w x23
  ame.ld.x x24
  addi x3, x9, 2863311530
  srli x9, x3, 30
.blk215:
  or x7, x15, x3
  ori x13, x6, 1431655765
  slti x11, x4, -31
  lw x15, 772(x28)
  xor x13, x14, x12
  sltiu x3, x5, 2
.blk216:
  csrr x1, minstret
  add x1, x7, x6
  bltu x2, x15, .fwd117
  .fwd117:
.blk217:
  ame.sync
  li x27, 3
  ame.st.q x27, x3
  slti x8, x4, 4294901760
  sh x1, 280(x28)
.blk218:
  bgeu x8, x11, .fwd118
  xori x6, x11, -31
  .fwd118:
  andi x6, x1, 2147483647
  xor x2, x6, x8
  addi x13, x15, -1
  ame.ld.w x22
  ame.ld.x x24
  ame.exe x24
  ame.sync
  sra x5, x1, x13
  beq x13, x4, .fwd119
  .fwd119:
  mul x10, x11, x15
.blk219:
  ame.ld.w x22
  ame.ld.x x24
  ame.exef x24
  ame.sync
  slt x7, x3, x3
  xori x4, x6, -2147483648
  lh x14, 484(x28)
  lh x14, 632(x28)
.blk220:
  rem x15, x5, x13
  bgeu x7, x6, .fwd120
  andi x9, x14, 305419896
  .fwd120:
  mulhsu x13, x6, x10
  sb x2, 796(x28)
  sltiu x3, x9, -31
  bne x13, x10, .fwd121
  srli x4, x5, 14
  .fwd121:
.blk221:
  sltiu x6, x14, 32
  add x7, x15, x4
  srai x3, x4, 14
  srai x13, x4, 23
  sw x8, 724(x28)
.blk222:
  slli x14, x2, 13
  lhu x1, 48(x28)
  lw x7, 224(x28)
  sw x9, 692(x28)
.blk223:
  addi x8, x11, -344865
  sb x11, 432(x28)
  xori x7, x3, 2
.blk224:
  slli x2, x7, 29
  mulh x15, x9, x13
  beq x3, x8, .fwd122
  slti x7, x3, 255
  slti x12, x7, 1
  .fwd122:
.blk225:
  bgeu x1, x1, .fwd123
  sltiu x7, x7, 1431655765
  .fwd123:
  sub x13, x2, x13
  sltu x9, x9, x2
  andi x11, x5, 31
  srl x1, x3, x15
  sb x3, 16(x28)
  ori x10, x1, -2
  slt x6, x9, x15
.blk226:
  ame.sync
  li x27, 3
  ame.st.y x27, x1
  lh x6, 300(x28)
  slt x6, x9, x5
  bne x11, x12, .fwd124
  srai x5, x13, 10
  srai x5, x13, 4
  .fwd124:
.blk227:
  sltu x7, x10, x3
  add x14, x13, x6
  andi x15, x1, 4294901760
  blt x5, x3, .fwd125
  addi x12, x1, 4294901760
  .fwd125:
.blk228:
  sb x2, 484(x28)
  ame.sync
  li x27, 1
  ame.st.q x27, x6
  sltu x6, x1, x5
.blk229:
  beq x10, x11, .fwd126
  addi x9, x14, 2863311530
  .fwd126:
  ori x8, x13, -2147483648
  ame.sync
  li x27, 8
  ame.st.y x27, x10
  slti x9, x14, -1
.blk230:
  slt x9, x13, x15
  lhu x4, 740(x28)
  and x9, x13, x12
  ori x1, x12, 1
.blk231:
  bge x12, x8, .fwd127
  sltiu x1, x10, 65535
  xori x9, x11, -1
  .fwd127:
  slli x9, x9, 2
  sw x1, 900(x28)
  sub x9, x12, x1
  xor x3, x10, x15
  and x3, x8, x11
  sltu x4, x3, x7
  sw x4, 884(x28)
.blk232:
  ame.sync
  li x27, 15
  ame.st.q x27, x13
  addi x13, x14, 1
  beq x1, x13, .blk233
  slli x7, x9, 27
.blk233:
  sb x2, 200(x28)
  slti x8, x9, -31
  sll x15, x12, x5
  ame.sync
  li x27, 14
  ame.st.y x27, x3
  sra x11, x6, x12
  ame.ld.w x22
  ame.ld.x x24
  ame.exef x24
  ame.sync
.blk234:
  sub x9, x15, x14
  lw x1, 84(x28)
  mul x8, x10, x13
.blk235:
  slti x4, x14, -2147483648
  sra x8, x7, x7
  lbu x5, 64(x28)
  srli x3, x5, 9
.blk236:
  ame.ld.w x22
  ame.ld.x x24
  ame.exef x24
  ame.sync
  sw x5, 732(x28)
  csrs mscratch, x8
  lb x9, 836(x28)
  xori x8, x12, 32
  divu x6, x13, x7
  csrr x10, flags
  andi x6, x10, 65535
.blk237:
  bge x5, x8, .fwd128
  andi x4, x2, 255
  slli x15, x5, 23
  .fwd128:
  sra x1, x9, x13
  ori x14, x5, 0
  slt x11, x13, x14
  sub x11, x3, x7
  csrr x10, minstret
  lhu x15, 0(x28)
  sll x14, x9, x15
.blk238:
  bge x6, x11, .fwd129
  slti x6, x10, 255
  srli x5, x6, 11
  .fwd129:
  slt x3, x8, x3
  lhu x11, 488(x28)
  srli x2, x9, 31
.blk239:
  bltu x3, x4, .fwd130
  .fwd130:
  slti x4, x5, 2147483647
  ame.ld.w x23
  ame.ld.x x25
  ame.exe x26
  ame.sync
  sw x4, 884(x28)
  divu x10, x6, x13
  beq x1, x7, .blk240
  sltu x13, x4, x14
  lb x5, 4(x28)
.blk240:
  lw x15, 384(x28)
  and x6, x9, x5
  ame.ld.w x22
  ame.ld.x x25
  andi x11, x13, 65535
  sw x3, 540(x28)
  sw x2, 584(x28)
  ame.sync
  li x27, 2
  ame.st.q x27, x14
.blk241:
  bgeu x3, x9, .fwd131
  slti x7, x13, -2147483648
  .fwd131:
  lw x2, 404(x28)
  lb x15, 584(x28)
.blk242:
  lh x11, 664(x28)
  or x10, x2, x4
  sub x12, x7, x1
.blk243:
  ame.ld.w x23
  ame.ld.x x25
  sltiu x10, x2, 32
  sw x2, 440(x28)
.blk244:
  slli x5, x12, 31
  lbu x15, 580(x28)
  csrr x8, minstret
  mulhu x1, x3, x8
  slli x14, x2, 21
  xori x9, x14, 128
  ame.sync
  li x27, 15
  ame.st.q x27, x10
  lw x6, 48(x28)
.blk245:
  sw x15, 780(x28)
  ame.sync
  li x27, 5
  ame.st.y x27, x9
  lbu x1, 120(x28)
  sra x6, x1, x15
  lbu x8, 336(x28)
  ori x7, x4, 305419896
  bne x10, x11, .fwd132
  slli x7, x10, 29
  srai x2, x8, 11
  .fwd132:
  lbu x15, 32(x28)
.blk246:
  blt x11, x2, .fwd133
  ori x7, x14, -344865
  addi x14, x12, 255
  .fwd133:
  sltu x13, x9, x4
  sb x13, 536(x28)
.blk247:
  ame.ld.w x22
  ame.ld.x x24
  ame.exef x24
  ame.sync
  or x4, x11, x3
  sll x13, x9, x2
  xor x2, x10, x13
  csrr x14, minstret
  slt x8, x8, x2
  sub x13, x4, x8
  ame.ld.w x23
  ame.ld.x x24
.blk248:
  slti x6, x11, 31
  mul x14, x5, x12
  blt x10, x7, .blk249
  csrc mscratch, x14
.blk249:
  addi x3, x5, 2147483647
  sh x6, 852(x28)
  bltu x1, x1, .blk250
  beq x5, x12, .blk250
  srli x11, x9, 29
  sw x2, 592(x28)
.blk250:
  addi x10, x10, -2
  andi x5, x9, -31
  csrr x2, minstret
  divu x12, x1, x13
  andi x11, x14, 65535
.blk251:
  addi x2, x12, 31
  sltiu x1, x14, 2863311530
  ame.ld.w x22
  ame.ld.x x24
  ame.exe x24
  ame.sync
  sltu x4, x8, x13
  mul x1, x2, x8
.blk252:
  add x2, x4, x2
  csrr x11, minstret
  srl x3, x12, x7
  bne x11, x9, .fwd134
  andi x8, x6, -31
  slti x2, x12, 1431655765
  .fwd134:
  xor x3, x4, x12
  sll x14, x13, x1
.blk253:
  slt x13, x12, x13
  slt x1, x14, x2
  sub x4, x14, x11
  lw x8, 32(x28)
  mulhsu x6, x10, x8
  ame.ld.w x23
  ame.ld.x x25
.blk254:
  slli x12, x5, 15
  lw x5, 432(x28)
  lw x4, 804(x28)
  sb x1, 564(x28)
  lw x13, 48(x28)
  sub x7, x15, x11
.blk255:
  lw x6, 104(x28)
  lbu x4, 540(x28)
  csrr x5, minstret
  sub x1, x1, x14
  srl x4, x2, x9
.blk256:
  csrr x4, flags
  sw x9, 712(x28)
  sltu x15, x11, x14
.blk257:
  sra x9, x8, x3
  mulh x1, x12, x2
  ame.ld.w x22
  ame.ld.x x24
  ame.exe x24
  ame.sync
  sra x6, x2, x14
  ame.ld.w x22
  ame.ld.x x24
  sltu x5, x8, x15
  ame.sync
  li x27, 13
  ame.st.q x27, x3
.blk258:
  lb x1, 180(x28)
  lh x11, 1008(x28)
  bge x6, x1, .fwd135
  ori x1, x11, 255
  srai x11, x5, 1
  .fwd135:
  beq x12, x14, .blk259
  andi x15, x3, -1
.blk259:
  slti x5, x5, 1
  ori x2, x15, -1
  ame.ld.w x22
  ame.ld.x x24
  ame.exe x24
  ame.sync
  ame.ld.w x23
  ame.ld.x x25
  ame.exe x26
  ame.sync
  or x13, x15, x10
  sw x5, 936(x28)
.blk_end:
  ame.sync
  li x28, 0x1FFF0
  li x29, 0x600D
  sw x29, 0(x28)
  ebreak
