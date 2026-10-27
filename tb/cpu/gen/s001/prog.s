# 随机生成(cpu_gen_random.py)
  .org 0x10000
boot:
  j start
  .org 0x0
start:
  li x1, -2
  li x2, -1
  li x3, -344865
  li x4, 2
  li x5, -31
  li x6, 32
  li x7, -31
  li x8, 4294901760
  li x9, -2147483648
  li x10, 2
  li x11, -31
  li x12, 0
  li x13, 4294901760
  li x14, 31
  li x15, 0
  li x28, 0x4000
.blk0:
  lh x5, 468(x28)
  addi x15, x6, 0
  addi x11, x9, 4294901760
  ame.cfg 16, 16
  li x20, 3
  li x21, 65
  ame.qcfg 0, x20, x21
  li x22, 0
  li x23, 5
  li x24, 0
  li x25, 528
  li x26, 1
  slt x7, x12, x1
  slt x13, x8, x8
  or x6, x4, x11
  lbu x5, 44(x28)
.blk1:
  bgeu x2, x3, .blk2
  slt x2, x12, x6
  lb x9, 388(x28)
  slt x10, x15, x8
  lbu x10, 68(x28)
  srl x12, x13, x7
  ame.ld.w x23
  ame.ld.x x25
  ame.exe x26
  ame.sync
.blk2:
  ame.ld.w x22
  ame.ld.x x25
  ame.ld.w x22
  ame.ld.x x24
  ame.exef x24
  ame.sync
  sb x14, 804(x28)
  sh x12, 60(x28)
  slli x5, x12, 10
  addi x9, x4, -2147483648
  sh x15, 472(x28)
.blk3:
  remu x14, x10, x6
  add x11, x9, x10
  mulhsu x13, x14, x14
  sh x13, 420(x28)
  sltiu x8, x14, 128
  sll x9, x7, x8
  lh x6, 0(x28)
.blk4:
  blt x13, x10, .fwd1
  .fwd1:
  sltu x11, x3, x9
  slt x14, x2, x13
  sub x1, x14, x11
  srli x14, x1, 0
  sltu x4, x5, x2
  and x6, x5, x2
.blk5:
  xor x9, x3, x11
  bge x12, x5, .blk6
  sw x8, 232(x28)
  or x7, x6, x7
.blk6:
  srai x5, x15, 13
  beq x7, x14, .fwd2
  ori x3, x1, 32
  .fwd2:
  ame.sync
  li x27, 7
  ame.st.q x27, x4
  sh x11, 60(x28)
  ame.ld.w x23
  ame.ld.x x24
.blk7:
  add x3, x4, x15
  xor x2, x14, x2
  sltu x12, x3, x7
  add x3, x1, x9
  bltu x14, x4, .fwd3
  addi x10, x9, 4294901760
  xori x4, x6, -2147483648
  .fwd3:
  bge x11, x15, .fwd4
  slli x2, x11, 18
  .fwd4:
  sb x8, 32(x28)
  blt x14, x7, .fwd5
  .fwd5:
.blk8:
  blt x13, x3, .fwd6
  slli x11, x2, 22
  .fwd6:
  ame.sync
  li x27, 7
  ame.st.y x27, x12
  ori x2, x3, 2147483647
  sb x4, 548(x28)
  blt x9, x14, .fwd7
  andi x2, x5, -31
  .fwd7:
.blk9:
  beq x9, x13, .fwd8
  ori x2, x7, -2
  .fwd8:
  srl x2, x10, x10
  andi x10, x9, -1
  sltu x6, x15, x5
.blk10:
  slti x8, x15, 2
  addi x14, x5, 0
  addi x7, x2, -2147483648
  and x13, x10, x7
  andi x8, x3, 2147483647
  csrr x14, minstret
  lh x15, 772(x28)
.blk11:
  bge x5, x12, .fwd9
  .fwd9:
  beq x6, x1, .fwd10
  sltiu x12, x10, 32
  .fwd10:
  lw x6, 816(x28)
  srli x15, x6, 7
  slt x4, x13, x10
.blk12:
  sb x11, 728(x28)
  or x9, x4, x5
  xor x6, x2, x14
  xori x13, x8, 2863311530
  sll x7, x5, x1
  sltu x6, x13, x14
  slt x4, x6, x2
  bltu x10, x13, .fwd11
  .fwd11:
.blk13:
  slt x7, x2, x5
  addi x12, x2, 0
  sra x13, x13, x6
.blk14:
  sltiu x2, x9, -1
  sw x11, 352(x28)
  sltiu x3, x14, 1431655765
  slti x12, x9, -2
  add x3, x9, x15
  slt x14, x15, x10
.blk15:
  ame.ld.w x23
  ame.ld.x x25
  ame.exef x26
  ame.sync
  add x7, x9, x3
  ame.ld.w x23
  ame.ld.x x25
  ame.exe x26
  ame.sync
  slli x11, x8, 16
  sw x8, 928(x28)
  lw x14, 692(x28)
  srl x8, x1, x13
  bgeu x1, x1, .fwd12
  .fwd12:
.blk16:
  slti x3, x5, 4294901760
  bltu x7, x3, .fwd13
  srai x1, x3, 20
  .fwd13:
  sw x15, 896(x28)
  sra x6, x8, x11
  slt x12, x7, x6
  bgeu x15, x12, .fwd14
  xori x4, x1, 255
  sltiu x11, x15, 2147483647
  .fwd14:
  sb x13, 416(x28)
.blk17:
  ame.ld.w x23
  ame.ld.x x24
  ame.sync
  li x27, 2
  ame.st.y x27, x15
  bge x9, x10, .fwd15
  addi x7, x4, -31
  .fwd15:
  ame.sync
  li x27, 11
  ame.st.q x27, x9
  addi x9, x12, 255
.blk18:
  sub x11, x2, x5
  xori x13, x10, 32
  srl x14, x7, x13
.blk19:
  srli x15, x6, 8
  bne x15, x8, .fwd16
  xori x9, x7, 1431655765
  slli x5, x4, 0
  .fwd16:
  add x9, x8, x10
  andi x11, x10, -344865
  slt x3, x5, x3
  xor x5, x5, x10
.blk20:
  lh x13, 344(x28)
  mulh x8, x7, x14
  or x10, x15, x7
  add x13, x2, x15
  addi x10, x12, 128
  and x11, x13, x12
  slti x9, x6, 31
  sb x11, 728(x28)
.blk21:
  srli x8, x12, 22
  sltu x9, x7, x6
  sh x2, 772(x28)
.blk22:
  bgeu x1, x5, .fwd17
  srai x14, x12, 12
  srai x15, x8, 26
  .fwd17:
  csrr x12, flags
  ame.ld.w x23
  ame.ld.x x25
  ame.exe x26
  ame.sync
  bne x11, x9, .fwd18
  .fwd18:
.blk23:
  divu x10, x7, x7
  bgeu x10, x12, .blk24
  csrc mscratch, x2
  add x11, x11, x5
  lhu x12, 316(x28)
  lw x13, 552(x28)
  addi x14, x13, 65535
  slt x13, x12, x7
.blk24:
  slti x8, x14, -31
  addi x8, x9, -344865
  sw x2, 864(x28)
  mul x2, x11, x8
  ori x9, x12, -1
.blk25:
  bltu x12, x5, .fwd19
  sltiu x4, x4, -344865
  srai x2, x2, 23
  .fwd19:
  lw x9, 100(x28)
  slt x11, x12, x12
  or x6, x10, x12
  lw x9, 816(x28)
  sb x13, 528(x28)
.blk26:
  or x5, x10, x12
  ame.ld.w x22
  ame.ld.x x24
  ame.exe x24
  ame.sync
  or x15, x7, x15
  and x4, x2, x11
  bgeu x8, x10, .fwd20
  ori x8, x9, -2
  .fwd20:
  srli x15, x12, 23
  sub x13, x7, x4
  ame.ld.w x23
  ame.ld.x x25
  ame.exe x26
  ame.sync
.blk27:
  sltiu x4, x7, -31
  addi x3, x1, 0
  slt x11, x1, x8
.blk28:
  bgeu x8, x6, .blk29
  ori x10, x12, 2
  sra x7, x4, x8
  mulhu x13, x3, x4
  srl x8, x9, x10
  sll x8, x12, x5
  sw x10, 224(x28)
  addi x1, x1, -31
.blk29:
  mulhu x14, x10, x5
  lw x3, 308(x28)
  srai x7, x3, 3
  bne x7, x5, .fwd21
  addi x14, x5, 1
  srai x9, x1, 8
  .fwd21:
  xori x15, x5, 31
.blk30:
  and x1, x8, x11
  csrr x5, minstret
  ame.sync
  li x27, 12
  ame.st.q x27, x11
.blk31:
  or x11, x11, x4
  ori x10, x15, 65535
  lb x10, 124(x28)
  bne x7, x9, .blk32
  sb x7, 140(x28)
.blk32:
  beq x12, x13, .fwd22
  .fwd22:
  andi x1, x15, 31
  xori x1, x11, 255
  sw x9, 756(x28)
  add x1, x3, x9
  lbu x11, 260(x28)
  ame.sync
  li x27, 0
  ame.st.q x27, x2
  xor x13, x6, x2
.blk33:
  divu x1, x12, x5
  csrr x3, flags
  div x13, x2, x14
.blk34:
  lh x14, 500(x28)
  blt x4, x6, .fwd23
  srli x15, x10, 6
  .fwd23:
  srli x11, x14, 1
.blk35:
  csrr x3, minstret
  mulh x7, x9, x6
  lh x6, 256(x28)
  srai x1, x5, 20
  lb x5, 652(x28)
.blk36:
  slt x12, x12, x9
  ori x9, x2, 2863311530
  csrr x6, flags
  blt x2, x8, .fwd24
  slli x15, x12, 5
  .fwd24:
  bne x13, x1, .fwd25
  slti x10, x14, 305419896
  .fwd25:
.blk37:
  blt x12, x6, .blk38
  blt x6, x7, .fwd26
  ori x9, x9, 0
  .fwd26:
  andi x5, x11, -2
  slli x3, x13, 3
  slti x9, x11, 2
  sltu x5, x2, x11
  sw x11, 160(x28)
  slt x11, x14, x3
.blk38:
  srli x10, x6, 18
  sra x15, x4, x10
  sll x7, x8, x11
  sh x15, 384(x28)
  csrr x2, flags
  lhu x4, 16(x28)
.blk39:
  mulh x9, x15, x8
  lw x10, 868(x28)
  mulhu x14, x8, x1
  add x12, x12, x11
  sb x2, 616(x28)
  sh x11, 576(x28)
  sb x14, 836(x28)
.blk40:
  sltu x3, x9, x8
  ori x9, x13, -344865
  bgeu x1, x7, .fwd27
  .fwd27:
  mul x7, x7, x5
  addi x15, x2, 4294901760
  sll x8, x5, x13
.blk41:
  csrs mscratch, x14
  remu x8, x13, x2
  mul x3, x7, x3
  and x14, x5, x6
  bge x13, x5, .fwd28
  slli x5, x12, 17
  srli x7, x6, 13
  .fwd28:
  ame.sync
  li x27, 12
  ame.st.q x27, x2
  ori x3, x4, 305419896
  csrr x1, minstret
.blk42:
  xori x8, x13, 4294901760
  beq x12, x3, .fwd29
  andi x1, x9, 128
  addi x7, x6, 2
  .fwd29:
  csrc mscratch, x9
  csrr x2, flags
  ame.ld.w x22
  ame.ld.x x25
.blk43:
  xori x13, x4, 4294901760
  slti x11, x8, 255
  sw x15, 804(x28)
  beq x14, x8, .fwd30
  andi x15, x12, 2147483647
  slli x9, x5, 18
  .fwd30:
  sb x11, 436(x28)
  sb x2, 16(x28)
  ame.ld.w x22
  ame.ld.x x25
  sub x13, x15, x14
.blk44:
  sw x5, 552(x28)
  lb x3, 264(x28)
  sltu x7, x9, x11
  srai x9, x14, 9
.blk45:
  xor x5, x8, x12
  sll x8, x4, x8
  blt x8, x4, .fwd31
  .fwd31:
  csrc mscratch, x15
  sltiu x1, x9, 255
  ame.ld.w x23
  ame.ld.x x25
  ame.exef x26
  ame.sync
.blk46:
  blt x8, x8, .fwd32
  .fwd32:
  ame.ld.w x22
  ame.ld.x x24
  bgeu x9, x14, .fwd33
  .fwd33:
  ame.ld.w x22
  ame.ld.x x24
  ame.exef x24
  ame.sync
  bltu x4, x9, .fwd34
  addi x7, x6, 0
  .fwd34:
.blk47:
  bgeu x4, x2, .fwd35
  sltiu x11, x14, -344865
  srai x10, x12, 24
  .fwd35:
  sltiu x2, x6, -2
  ori x5, x15, 1
  mulh x2, x2, x12
  slt x6, x4, x5
.blk48:
  rem x1, x2, x3
  mulhu x15, x12, x11
  slti x11, x6, 0
.blk49:
  and x2, x6, x15
  blt x15, x14, .fwd36
  srai x10, x10, 30
  srai x10, x7, 25
  .fwd36:
  xor x15, x4, x11
  bltu x3, x1, .fwd37
  .fwd37:
  xor x4, x15, x7
  sb x1, 512(x28)
  sw x5, 968(x28)
.blk50:
  ame.ld.w x22
  ame.ld.x x24
  ame.exe x24
  ame.sync
  sltiu x11, x9, 128
  bgeu x14, x13, .fwd38
  slti x1, x10, 32
  ori x11, x3, -1
  .fwd38:
  bne x3, x11, .fwd39
  slti x6, x15, 2147483647
  .fwd39:
  slli x14, x13, 28
  lb x2, 296(x28)
.blk51:
  ame.ld.w x22
  ame.ld.x x24
  ame.exef x24
  ame.sync
  bgeu x3, x7, .fwd40
  .fwd40:
  lh x1, 884(x28)
  ame.sync
  li x27, 8
  ame.st.q x27, x7
  lw x10, 944(x28)
.blk52:
  sw x13, 76(x28)
  ori x14, x2, 255
  sb x13, 728(x28)
.blk53:
  bge x6, x13, .blk54
  or x15, x13, x10
  ori x9, x6, 2
  sltiu x15, x12, 31
  csrr x6, flags
  ame.ld.w x22
  ame.ld.x x24
  ame.exe x24
  ame.sync
  lb x7, 732(x28)
.blk54:
  lhu x13, 484(x28)
  beq x9, x3, .fwd41
  .fwd41:
  sb x3, 996(x28)
  ame.ld.w x22
  ame.ld.x x24
  ame.exef x24
  ame.sync
  sh x15, 428(x28)
.blk55:
  sub x7, x12, x4
  or x6, x6, x11
  ame.sync
  li x27, 15
  ame.st.q x27, x8
  bgeu x13, x11, .blk56
  lh x8, 816(x28)
  slti x10, x8, -2
  slli x1, x7, 6
  ori x11, x2, 32
.blk56:
  ame.ld.w x22
  ame.ld.x x24
  sb x14, 216(x28)
  andi x8, x7, 128
  ame.sync
  li x27, 0
  ame.st.y x27, x7
  sltiu x11, x3, 305419896
  srai x13, x9, 10
.blk57:
  mulhu x10, x1, x9
  lh x4, 80(x28)
  csrr x4, minstret
  sub x7, x13, x8
.blk58:
  beq x1, x7, .fwd42
  addi x14, x8, 255
  addi x4, x13, 0
  .fwd42:
  srl x8, x5, x12
  srai x10, x3, 20
  sh x11, 916(x28)
  bge x3, x12, .fwd43
  .fwd43:
  sb x14, 568(x28)
  slti x5, x10, 2147483647
.blk59:
  blt x2, x12, .fwd44
  .fwd44:
  srl x5, x5, x6
  and x10, x8, x1
  andi x5, x4, -1
  bne x9, x10, .fwd45
  ori x14, x4, 128
  andi x8, x7, -1
  .fwd45:
  bne x15, x2, .blk60
  slli x1, x12, 24
  lh x11, 280(x28)
.blk60:
  srai x11, x9, 4
  xor x14, x7, x3
  sll x11, x12, x7
  csrr x14, minstret
  sll x5, x12, x3
  sw x9, 596(x28)
  sw x14, 612(x28)
.blk61:
  lh x1, 592(x28)
  blt x2, x10, .blk62
  sll x10, x1, x1
  xori x13, x3, 2
  lhu x11, 500(x28)
  sub x9, x9, x7
  ame.ld.w x23
  ame.ld.x x25
  ame.exe x26
  ame.sync
  ame.ld.w x23
  ame.ld.x x25
  ame.exe x26
  ame.sync
.blk62:
  andi x12, x2, 4294901760
  ame.sync
  li x27, 7
  ame.st.q x27, x1
  bgeu x3, x11, .blk63
  sb x4, 840(x28)
  ame.sync
  li x27, 12
  ame.st.q x27, x8
  ori x11, x14, 2147483647
  beq x1, x8, .fwd46
  srai x14, x12, 21
  .fwd46:
  add x2, x2, x11
.blk63:
  lh x4, 352(x28)
  sb x4, 788(x28)
  sltu x4, x6, x11
  addi x6, x15, 32
  ori x14, x10, -2
  slt x8, x1, x10
.blk64:
  bge x7, x2, .blk65
  bge x11, x5, .fwd47
  addi x8, x15, 128
  .fwd47:
  sb x1, 872(x28)
.blk65:
  csrr x6, minstret
  blt x10, x9, .fwd48
  sltiu x13, x13, 31
  addi x7, x9, 2
  .fwd48:
  addi x10, x9, 2
  slt x6, x15, x6
  xori x11, x6, -31
  bltu x2, x14, .fwd49
  srai x15, x13, 0
  sltiu x15, x3, 65535
  .fwd49:
  and x3, x15, x10
.blk66:
  srai x7, x6, 26
  divu x6, x14, x5
  andi x12, x2, -344865
  lh x9, 580(x28)
  bgeu x2, x2, .fwd50
  ori x7, x2, 1431655765
  .fwd50:
  blt x12, x11, .fwd51
  .fwd51:
  slt x12, x8, x1
.blk67:
  slt x14, x9, x2
  slt x6, x15, x5
  sltiu x1, x8, 1
  ori x6, x7, 128
  srai x12, x10, 27
.blk68:
  and x4, x2, x10
  bgeu x9, x2, .fwd52
  .fwd52:
  sltiu x6, x8, 65535
  add x15, x15, x11
.blk69:
  sb x1, 336(x28)
  bne x1, x1, .blk70
  ori x9, x14, 1
.blk70:
  or x4, x8, x5
  sb x9, 760(x28)
  lw x11, 148(x28)
  bgeu x3, x4, .fwd53
  srli x7, x10, 23
  addi x1, x8, 2
  .fwd53:
  ame.sync
  li x27, 10
  ame.st.q x27, x2
  bgeu x7, x4, .fwd54
  srai x14, x14, 30
  .fwd54:
  bltu x11, x12, .blk71
.blk71:
  blt x8, x3, .fwd55
  slli x5, x10, 16
  addi x5, x5, 1
  .fwd55:
  lw x8, 728(x28)
  sh x8, 428(x28)
  srl x12, x11, x3
  lb x1, 224(x28)
  srai x5, x13, 3
.blk72:
  div x1, x6, x6
  beq x15, x13, .fwd56
  .fwd56:
  sub x2, x11, x14
  slti x13, x12, 31
  beq x6, x4, .blk73
.blk73:
  ame.ld.w x23
  ame.ld.x x25
  ame.exe x26
  ame.sync
  slt x5, x7, x7
  lw x13, 148(x28)
  lh x4, 84(x28)
  srl x11, x4, x4
  div x4, x10, x3
  csrr x12, flags
  slti x12, x12, 32
.blk74:
  addi x11, x3, 65535
  lh x9, 700(x28)
  sb x6, 228(x28)
  bge x11, x5, .fwd57
  srli x13, x2, 7
  .fwd57:
  sh x4, 540(x28)
  mulh x13, x4, x1
.blk75:
  sw x9, 332(x28)
  sub x15, x1, x15
  srl x1, x11, x1
  csrr x12, minstret
  addi x1, x1, 128
  sltu x6, x13, x1
  srli x9, x4, 12
.blk76:
  xor x10, x9, x9
  add x3, x4, x7
  add x9, x12, x8
  add x6, x7, x2
  bgeu x3, x9, .fwd58
  .fwd58:
.blk77:
  sub x3, x5, x15
  ori x13, x6, -1
  lw x3, 472(x28)
  csrr x5, flags
.blk78:
  bne x2, x8, .blk79
  ame.ld.w x23
  ame.ld.x x25
  ame.exef x26
  ame.sync
  xori x4, x1, -1
.blk79:
  slt x5, x12, x5
  lhu x14, 508(x28)
  andi x12, x5, 2863311530
  rem x6, x8, x13
  ame.sync
  li x27, 2
  ame.st.q x27, x15
  sll x14, x14, x8
  or x10, x11, x2
  slli x13, x13, 17
.blk80:
  sll x15, x15, x6
  lb x8, 744(x28)
  add x7, x8, x9
  div x3, x5, x3
  bltu x3, x14, .blk81
  ori x3, x8, -2
  slti x2, x14, 305419896
.blk81:
  blt x6, x3, .blk82
  slt x2, x7, x3
  mulh x15, x8, x15
  xori x11, x6, 2147483647
  sw x9, 68(x28)
.blk82:
  sll x11, x6, x12
  sb x15, 724(x28)
  srl x11, x2, x3
  andi x5, x15, 1
  sll x14, x14, x5
  blt x7, x4, .blk83
  add x5, x12, x10
  sll x2, x3, x4
.blk83:
  sub x3, x3, x4
  slt x10, x9, x9
  bltu x15, x14, .blk84
  lw x10, 972(x28)
  sw x14, 728(x28)
  lb x13, 148(x28)
  and x4, x13, x3
.blk84:
  sltiu x3, x8, 2147483647
  xori x13, x6, 305419896
  ame.ld.w x23
  ame.ld.x x25
  ame.exef x26
  ame.sync
  lh x11, 400(x28)
.blk85:
  addi x10, x12, -2147483648
  add x15, x8, x9
  srli x14, x6, 22
  srai x8, x2, 20
  ame.ld.w x23
  ame.ld.x x24
.blk86:
  xor x7, x14, x2
  sltiu x11, x11, 0
  sll x15, x6, x4
  xor x14, x14, x5
  sb x7, 24(x28)
  addi x11, x5, 2
.blk87:
  lb x15, 444(x28)
  remu x13, x11, x12
  blt x5, x10, .fwd59
  xori x3, x6, 4294901760
  .fwd59:
  mulhu x9, x12, x10
  lbu x8, 304(x28)
  ame.ld.w x23
  ame.ld.x x25
  ame.exef x26
  ame.sync
.blk88:
  bgeu x4, x2, .fwd60
  srli x9, x8, 20
  ori x15, x9, -31
  .fwd60:
  lh x1, 788(x28)
  csrr x9, mscratch
  beq x10, x6, .blk89
  mulhu x14, x6, x8
  ame.ld.w x22
  ame.ld.x x25
  remu x4, x3, x3
  sltiu x6, x10, 2147483647
.blk89:
  sw x8, 16(x28)
  bgeu x1, x8, .fwd61
  .fwd61:
  lb x8, 252(x28)
  and x3, x3, x6
  sltu x13, x15, x12
  sh x5, 476(x28)
  lw x8, 636(x28)
.blk90:
  bltu x9, x5, .blk91
  add x5, x11, x3
  slt x2, x7, x7
  csrs mscratch, x3
  sw x8, 744(x28)
  xori x2, x12, 2
  sh x7, 280(x28)
.blk91:
  sltu x8, x8, x9
  srli x10, x4, 31
  mulhsu x5, x15, x6
  beq x5, x3, .fwd62
  srai x2, x15, 14
  sltiu x8, x14, 32
  .fwd62:
  srl x15, x12, x2
  slti x12, x8, 31
.blk92:
  srl x9, x2, x3
  sh x14, 872(x28)
  sw x3, 652(x28)
  mulhu x3, x10, x4
  and x15, x8, x11
  slli x12, x2, 3
.blk93:
  sltiu x6, x9, -344865
  lbu x1, 792(x28)
  ame.sync
  li x27, 9
  ame.st.q x27, x11
  blt x7, x6, .fwd63
  ori x3, x8, 32
  .fwd63:
  srai x9, x2, 20
  slt x14, x8, x11
.blk94:
  slt x12, x10, x6
  blt x13, x8, .fwd64
  andi x14, x9, 2147483647
  .fwd64:
  sltu x9, x4, x14
  sltu x1, x13, x6
  addi x6, x7, 65535
  rem x6, x10, x10
  xor x13, x15, x14
  srl x6, x7, x12
.blk95:
  sll x1, x7, x11
  bltu x13, x13, .blk96
  sltu x4, x2, x14
  xor x7, x4, x12
  sltiu x7, x1, -1
  lh x3, 228(x28)
  csrr x14, minstret
  sll x3, x7, x7
.blk96:
  blt x12, x9, .blk97
  slt x4, x3, x3
  srli x3, x2, 8
  lh x3, 680(x28)
  csrr x12, flags
  blt x3, x1, .blk97
  sltu x4, x12, x8
.blk97:
  xori x15, x11, -2
  sw x8, 292(x28)
  divu x12, x3, x5
  addi x7, x8, 255
  lhu x15, 400(x28)
  add x4, x12, x15
.blk98:
  ame.ld.w x22
  ame.ld.x x25
  sw x4, 144(x28)
  sltiu x14, x7, 2
  lhu x12, 988(x28)
  sll x3, x7, x6
  mulhu x7, x7, x6
  or x2, x3, x4
  slli x4, x11, 29
.blk99:
  lw x10, 192(x28)
  slt x14, x14, x14
  slti x1, x7, 31
  sltiu x14, x4, 31
  slt x10, x12, x1
  lh x3, 744(x28)
  andi x6, x2, 2
.blk100:
  sltiu x13, x1, -2
  srli x5, x1, 1
  sw x2, 880(x28)
  sw x9, 196(x28)
  sh x14, 804(x28)
  sra x15, x9, x7
.blk101:
  or x8, x2, x2
  bgeu x10, x14, .fwd65
  .fwd65:
  mulhu x2, x15, x15
  xori x12, x11, 0
  sw x7, 480(x28)
  sltu x8, x10, x1
  lbu x9, 608(x28)
  bltu x1, x11, .fwd66
  andi x8, x8, -344865
  sltiu x15, x14, -31
  .fwd66:
.blk102:
  sw x1, 548(x28)
  csrs mscratch, x12
  sll x10, x10, x3
  sh x11, 812(x28)
  ame.sync
  li x27, 15
  ame.st.y x27, x5
  srli x2, x3, 7
.blk103:
  slt x14, x14, x5
  and x3, x2, x9
  lbu x14, 76(x28)
  sb x12, 664(x28)
  srai x12, x1, 12
.blk104:
  bge x13, x2, .fwd67
  srai x5, x12, 1
  xori x10, x7, 2
  .fwd67:
  ame.ld.w x23
  ame.ld.x x24
  blt x8, x9, .fwd68
  ori x1, x4, 1
  addi x10, x2, 2
  .fwd68:
  bne x9, x5, .fwd69
  .fwd69:
  slt x14, x4, x2
.blk105:
  ame.sync
  li x27, 8
  ame.st.y x27, x5
  beq x13, x4, .blk106
  srl x1, x15, x1
  bge x5, x14, .fwd70
  .fwd70:
  add x4, x13, x11
.blk106:
  lb x14, 848(x28)
  mulhsu x9, x15, x3
  sll x4, x13, x1
  sltiu x14, x8, -2147483648
  slt x5, x3, x12
  mul x2, x8, x11
  sb x5, 536(x28)
  srl x13, x3, x12
.blk107:
  slli x13, x13, 29
  sw x14, 48(x28)
  sub x14, x8, x11
  or x12, x10, x7
  sw x6, 200(x28)
  and x8, x10, x2
  sh x6, 884(x28)
  beq x7, x14, .fwd71
  .fwd71:
.blk108:
  slli x1, x5, 27
  bltu x2, x4, .fwd72
  srai x7, x5, 6
  ori x6, x13, 128
  .fwd72:
  ame.ld.w x22
  ame.ld.x x24
  mulh x8, x5, x13
  srl x3, x13, x2
  ame.sync
  li x27, 0
  ame.st.q x27, x10
.blk109:
  srai x13, x13, 25
  sw x13, 476(x28)
  mulh x13, x1, x7
  sra x11, x1, x15
  addi x5, x10, 65535
  addi x2, x2, 1431655765
  remu x5, x2, x9
  blt x6, x14, .blk110
.blk110:
  bltu x6, x15, .fwd73
  andi x4, x4, 1431655765
  srai x5, x14, 20
  .fwd73:
  ame.ld.w x22
  ame.ld.x x25
  or x14, x11, x13
  ori x4, x14, -1
.blk111:
  lw x4, 280(x28)
  bltu x15, x13, .fwd74
  andi x15, x12, 2147483647
  .fwd74:
  slli x8, x4, 7
  ame.ld.w x22
  ame.ld.x x25
  sb x13, 912(x28)
.blk112:
  andi x2, x14, 2
  sw x8, 936(x28)
  bge x3, x8, .fwd75
  .fwd75:
.blk113:
  sltu x5, x4, x9
  sll x15, x5, x5
  add x5, x1, x1
.blk114:
  lw x1, 420(x28)
  sub x8, x11, x5
  or x11, x14, x2
  ori x4, x11, 0
  lh x12, 56(x28)
  slt x14, x8, x3
  xori x4, x3, 0
  xori x6, x15, 255
.blk115:
  slt x4, x7, x1
  srl x6, x5, x9
  lb x9, 952(x28)
  srli x3, x13, 25
  andi x15, x10, 255
  sltiu x9, x1, -2
  srl x6, x7, x1
.blk116:
  bltu x8, x14, .blk117
  addi x13, x12, -2
  bge x7, x9, .fwd76
  andi x1, x4, 1431655765
  slti x12, x7, 255
  .fwd76:
  slti x15, x10, -2147483648
  sw x9, 332(x28)
  ori x4, x8, 1
  ame.sync
  li x27, 9
  ame.st.y x27, x3
  slli x14, x1, 30
.blk117:
  sub x10, x8, x13
  ame.sync
  li x27, 7
  ame.st.y x27, x3
  slt x9, x8, x8
  ame.ld.w x23
  ame.ld.x x24
.blk118:
  sltu x7, x6, x7
  sub x7, x15, x10
  sll x11, x14, x10
  srli x1, x7, 3
  lhu x15, 224(x28)
  bge x13, x4, .fwd77
  .fwd77:
.blk119:
  ame.ld.w x22
  ame.ld.x x24
  ame.exe x24
  ame.sync
  bltu x9, x13, .blk120
  slli x10, x3, 19
  ame.sync
  li x27, 7
  ame.st.q x27, x12
  mulh x1, x9, x5
.blk120:
  sll x1, x10, x2
  bne x9, x11, .fwd78
  srli x2, x3, 23
  srli x7, x11, 30
  .fwd78:
  ame.ld.w x22
  ame.ld.x x24
  ame.exe x24
  ame.sync
  bgeu x2, x15, .fwd79
  .fwd79:
  and x1, x5, x5
.blk121:
  sw x10, 688(x28)
  lw x14, 700(x28)
  add x6, x12, x14
  andi x8, x9, 4294901760
  xori x3, x4, 4294901760
  addi x3, x6, 32
  sw x14, 332(x28)
.blk122:
  slt x14, x15, x5
  lh x4, 80(x28)
  ame.sync
  li x27, 13
  ame.st.q x27, x9
  lb x5, 904(x28)
  beq x15, x1, .fwd80
  ori x12, x7, 31
  srai x3, x14, 11
  .fwd80:
  xor x7, x12, x8
.blk123:
  ame.sync
  li x27, 12
  ame.st.q x27, x5
  slt x6, x9, x9
  sub x5, x1, x14
  and x12, x15, x7
  xor x13, x13, x10
.blk124:
  srli x3, x14, 7
  add x3, x2, x7
  slt x2, x2, x8
  csrr x11, mscratch
  srai x5, x1, 30
  csrr x11, minstret
.blk125:
  blt x8, x2, .blk126
  div x15, x11, x7
  srli x4, x14, 22
  lh x7, 892(x28)
  add x3, x3, x14
.blk126:
  divu x7, x2, x11
  bne x15, x3, .blk127
  bne x2, x9, .fwd81
  srai x4, x6, 10
  slti x13, x4, 2147483647
  .fwd81:
  csrs mscratch, x3
  sw x6, 68(x28)
.blk127:
  rem x4, x3, x4
  lbu x9, 556(x28)
  bge x14, x6, .blk128
.blk128:
  bne x10, x1, .blk129
  bne x12, x8, .fwd82
  .fwd82:
  andi x3, x5, 32
.blk129:
  ame.ld.w x23
  ame.ld.x x25
  srli x12, x7, 15
  sltiu x12, x12, -2
  ame.ld.w x22
  ame.ld.x x24
  ame.exe x24
  ame.sync
  blt x1, x5, .blk130
  srli x12, x10, 20
.blk130:
  sltiu x13, x9, 4294901760
  ame.ld.w x22
  ame.ld.x x24
  ame.exe x24
  ame.sync
  ame.ld.w x22
  ame.ld.x x24
  ame.exe x24
  ame.sync
  lh x12, 252(x28)
  srai x1, x15, 26
  mul x3, x7, x12
  slti x15, x13, 255
.blk131:
  bgeu x7, x14, .fwd83
  slti x8, x12, -344865
  addi x12, x11, 4294901760
  .fwd83:
  sw x10, 840(x28)
  sltu x3, x8, x7
  bne x15, x11, .fwd84
  slli x2, x10, 16
  addi x7, x8, 1431655765
  .fwd84:
  slti x14, x11, 4294901760
  sub x2, x5, x1
  ame.ld.w x22
  ame.ld.x x24
  ame.exe x24
  ame.sync
  andi x8, x4, 1
.blk132:
  xori x2, x14, 1
  beq x11, x2, .fwd85
  .fwd85:
  rem x2, x1, x14
  bne x10, x14, .fwd86
  ori x8, x15, 65535
  slli x14, x10, 10
  .fwd86:
.blk133:
  sw x14, 144(x28)
  slti x13, x10, 2
  lhu x2, 0(x28)
  srai x12, x5, 19
  blt x15, x10, .fwd87
  .fwd87:
.blk134:
  and x5, x11, x11
  sb x9, 48(x28)
  ame.sync
  li x27, 3
  ame.st.q x27, x13
  ame.ld.w x23
  ame.ld.x x25
  ame.exe x26
  ame.sync
  andi x6, x5, 2863311530
  bne x3, x9, .blk135
  srli x4, x12, 22
  bgeu x3, x7, .fwd88
  slti x8, x2, 1
  srai x9, x5, 20
  .fwd88:
.blk135:
  or x4, x14, x12
  mul x6, x5, x14
  sh x13, 284(x28)
  sw x2, 564(x28)
.blk136:
  ori x7, x7, 2
  ame.sync
  li x27, 6
  ame.st.y x27, x4
  sll x6, x14, x12
  mulhsu x12, x5, x10
.blk137:
  sltu x5, x15, x8
  sw x1, 700(x28)
  or x12, x4, x5
.blk138:
  lhu x12, 752(x28)
  mulhu x13, x14, x13
  slli x1, x15, 21
.blk139:
  sll x11, x13, x7
  blt x13, x12, .blk140
  blt x5, x13, .fwd89
  srli x4, x10, 22
  .fwd89:
  sltu x12, x1, x2
  sw x1, 348(x28)
  sh x8, 600(x28)
  lw x10, 8(x28)
.blk140:
  andi x12, x10, -31
  ame.sync
  li x27, 15
  ame.st.y x27, x7
  bgeu x15, x3, .fwd90
  .fwd90:
  beq x5, x9, .blk141
  slt x13, x3, x5
  sll x8, x3, x7
.blk141:
  xor x4, x5, x1
  sh x15, 600(x28)
  xor x5, x3, x5
  sra x3, x5, x7
  ame.sync
  li x27, 5
  ame.st.q x27, x1
  sltiu x10, x4, 1
  sw x12, 624(x28)
.blk142:
  sltiu x10, x11, -2
  sltiu x6, x4, 255
  lh x12, 492(x28)
  addi x1, x6, 32
  slti x3, x15, -2147483648
  lw x5, 336(x28)
.blk143:
  sh x7, 228(x28)
  or x7, x15, x1
  sra x7, x10, x10
.blk144:
  sub x10, x9, x11
  and x13, x11, x7
  sub x9, x14, x8
  bge x7, x11, .fwd91
  .fwd91:
  sub x1, x5, x13
  sra x10, x5, x13
  ame.sync
  li x27, 9
  ame.st.y x27, x5
.blk145:
  sw x3, 520(x28)
  slli x1, x11, 0
  beq x9, x5, .blk146
.blk146:
  andi x5, x3, -1
  sltu x13, x12, x11
  bltu x7, x9, .blk147
  add x15, x7, x11
  ame.ld.w x22
  ame.ld.x x24
  ame.exe x24
  ame.sync
.blk147:
  srl x1, x12, x15
  bne x7, x4, .fwd92
  srai x8, x9, 21
  slti x14, x11, -2147483648
  .fwd92:
  sh x10, 520(x28)
  xor x11, x5, x10
  ame.ld.w x23
  ame.ld.x x25
  ame.exe x26
  ame.sync
  mulhu x10, x12, x5
  sub x9, x11, x1
.blk148:
  or x3, x12, x6
  addi x11, x11, 305419896
  div x5, x5, x4
  mulhsu x1, x13, x1
.blk149:
  sb x7, 616(x28)
  lh x13, 728(x28)
  xor x5, x15, x5
  sb x10, 312(x28)
  xori x7, x1, -344865
  andi x13, x8, 32
  add x1, x5, x6
  ame.sync
  li x27, 13
  ame.st.q x27, x7
.blk150:
  bne x12, x8, .blk151
  lw x5, 196(x28)
  csrr x3, flags
  rem x10, x7, x12
  slli x14, x14, 3
.blk151:
  bne x4, x2, .blk152
  sw x7, 352(x28)
  sll x10, x2, x12
  and x9, x8, x13
  mulhsu x11, x8, x10
  andi x9, x4, -2
.blk152:
  sll x9, x1, x1
  add x14, x14, x4
  and x11, x11, x3
.blk153:
  ame.ld.w x23
  ame.ld.x x25
  ame.exe x26
  ame.sync
  sub x13, x13, x3
  sltu x15, x13, x3
.blk154:
  sra x13, x7, x9
  sra x10, x2, x13
  and x4, x2, x11
  sltu x15, x4, x10
  ame.ld.w x23
  ame.ld.x x25
  ame.exe x26
  ame.sync
  sltiu x13, x13, -1
.blk155:
  sh x5, 364(x28)
  lw x13, 452(x28)
  bge x10, x2, .blk156
  rem x4, x8, x11
  add x11, x10, x3
.blk156:
  mulhsu x14, x10, x8
  ame.sync
  li x27, 11
  ame.st.q x27, x3
  lh x4, 976(x28)
.blk157:
  bltu x4, x3, .fwd93
  .fwd93:
  ame.ld.w x22
  ame.ld.x x24
  ame.exef x24
  ame.sync
  lhu x9, 436(x28)
  srl x8, x12, x1
  xor x11, x12, x1
.blk158:
  add x10, x4, x7
  lw x6, 856(x28)
  bltu x2, x3, .fwd94
  addi x3, x15, 255
  .fwd94:
  sb x15, 992(x28)
  beq x14, x7, .blk159
  bge x11, x7, .blk159
  sw x1, 88(x28)
  beq x14, x6, .blk159
.blk159:
  lbu x14, 364(x28)
  srai x3, x5, 24
  ame.ld.w x22
  ame.ld.x x24
  ame.exef x24
  ame.sync
  srli x12, x7, 23
.blk160:
  andi x9, x7, -31
  slt x3, x4, x4
  ame.ld.w x23
  ame.ld.x x25
  bltu x10, x13, .fwd95
  .fwd95:
.blk161:
  addi x13, x10, 1
  bltu x6, x2, .fwd96
  slli x9, x2, 8
  .fwd96:
  sb x1, 284(x28)
  ame.ld.w x23
  ame.ld.x x24
  lbu x8, 172(x28)
.blk162:
  sltiu x5, x4, 65535
  bge x1, x2, .blk163
  lb x5, 352(x28)
  csrr x11, minstret
  csrr x6, flags
.blk163:
  ori x1, x1, 32
  sltu x12, x1, x5
  sw x15, 556(x28)
  ame.ld.w x23
  ame.ld.x x25
  ame.exef x26
  ame.sync
.blk164:
  lbu x6, 552(x28)
  slti x7, x2, 31
  srl x4, x9, x10
  beq x5, x1, .blk165
.blk165:
  ame.ld.w x23
  ame.ld.x x25
  ame.exe x26
  ame.sync
  andi x10, x15, 128
  bne x14, x9, .blk166
  lw x3, 676(x28)
  xori x3, x10, -2
  slti x10, x5, 65535
.blk166:
  addi x12, x14, -1
  lhu x12, 884(x28)
  lbu x5, 272(x28)
.blk167:
  div x13, x8, x6
  sw x3, 548(x28)
  add x4, x12, x14
  sw x1, 12(x28)
  bgeu x8, x1, .fwd97
  slli x7, x13, 14
  slti x10, x14, 2147483647
  .fwd97:
  csrr x4, minstret
.blk168:
  slt x6, x2, x2
  slt x4, x6, x13
  sh x8, 168(x28)
.blk169:
  mulh x15, x3, x3
  remu x14, x3, x11
  bge x2, x8, .fwd98
  .fwd98:
  ame.ld.w x23
  ame.ld.x x25
  mulh x10, x6, x7
  slt x15, x7, x6
  csrr x8, flags
.blk170:
  addi x8, x6, 305419896
  and x7, x11, x11
  sltu x5, x12, x9
  slti x3, x14, 1
  ame.ld.w x22
  ame.ld.x x24
  ame.exe x24
  ame.sync
  bne x10, x2, .blk171
  bne x8, x10, .blk171
  lbu x1, 288(x28)
.blk171:
  sw x5, 768(x28)
  bgeu x7, x3, .blk172
  sh x4, 876(x28)
  sltiu x10, x12, 128
  sw x3, 124(x28)
.blk172:
  andi x6, x4, 255
  sh x11, 840(x28)
  addi x13, x4, 305419896
  sw x9, 116(x28)
.blk173:
  ori x13, x1, 128
  and x4, x6, x6
  slli x5, x15, 22
  bltu x14, x1, .fwd99
  sltiu x8, x1, 1431655765
  slli x15, x5, 19
  .fwd99:
  mulh x8, x5, x11
  beq x11, x11, .blk174
  lw x2, 424(x28)
.blk174:
  xori x4, x8, -2147483648
  xor x4, x15, x5
  lhu x8, 428(x28)
  lhu x7, 168(x28)
  srli x2, x5, 13
  csrr x5, mscratch
  bgeu x10, x15, .fwd100
  andi x8, x4, -31
  slti x1, x5, -31
  .fwd100:
  sw x15, 720(x28)
.blk175:
  csrr x12, minstret
  or x12, x8, x7
  lhu x1, 360(x28)
  ame.sync
  li x27, 13
  ame.st.q x27, x9
  srai x13, x2, 10
  andi x10, x13, 255
  sb x15, 952(x28)
.blk176:
  sh x3, 40(x28)
  lbu x11, 704(x28)
  ame.ld.w x22
  ame.ld.x x25
  sra x11, x8, x10
  xor x11, x10, x7
.blk177:
  lb x2, 224(x28)
  lh x15, 588(x28)
  sll x9, x15, x15
  or x3, x3, x5
  lhu x14, 60(x28)
.blk178:
  lw x4, 276(x28)
  slli x3, x8, 14
  add x10, x7, x5
  srl x3, x2, x12
  srl x12, x11, x5
  bgeu x1, x11, .fwd101
  .fwd101:
.blk179:
  sw x8, 884(x28)
  sltiu x6, x11, 1431655765
  srli x5, x13, 2
  mulhu x5, x9, x11
.blk180:
  csrr x5, minstret
  sub x9, x6, x9
  ame.ld.w x22
  ame.ld.x x24
  ame.exef x24
  ame.sync
  sltiu x7, x6, -31
  slti x5, x1, 0
.blk181:
  beq x10, x10, .fwd102
  addi x14, x13, 255
  .fwd102:
  mul x2, x2, x14
  mulhu x2, x8, x14
  rem x10, x1, x14
  sw x14, 652(x28)
  srli x3, x8, 16
  lbu x11, 204(x28)
.blk182:
  beq x9, x5, .fwd103
  sltiu x3, x15, -2147483648
  .fwd103:
  xori x8, x6, 2863311530
  ame.ld.w x22
  ame.ld.x x24
  ame.exef x24
  ame.sync
  bne x6, x3, .fwd104
  .fwd104:
  slt x12, x13, x5
  bltu x2, x8, .fwd105
  sltiu x8, x7, 255
  srai x13, x11, 30
  .fwd105:
.blk183:
  ame.ld.w x23
  ame.ld.x x25
  ame.exef x26
  ame.sync
  and x5, x3, x11
  or x14, x13, x3
  lw x13, 280(x28)
.blk184:
  sh x9, 796(x28)
  bge x11, x12, .fwd106
  slli x9, x11, 30
  ori x5, x8, -2147483648
  .fwd106:
  mulhsu x1, x15, x5
  lbu x4, 316(x28)
  lb x11, 124(x28)
  ame.ld.w x23
  ame.ld.x x25
  ame.exef x26
  ame.sync
.blk185:
  bltu x13, x11, .blk186
  sw x15, 676(x28)
  bgeu x11, x15, .blk186
  ame.sync
  li x27, 2
  ame.st.y x27, x1
  xori x11, x2, -2
.blk186:
  srl x1, x4, x14
  sll x11, x5, x11
  srl x14, x11, x3
  slli x6, x2, 28
  add x9, x15, x2
  ame.ld.w x22
  ame.ld.x x24
  ame.exef x24
  ame.sync
  lw x13, 432(x28)
.blk187:
  ame.ld.w x23
  ame.ld.x x25
  ame.exe x26
  ame.sync
  sb x1, 668(x28)
  ame.ld.w x22
  ame.ld.x x25
.blk188:
  addi x5, x3, 2863311530
  slti x14, x3, 2
  sltu x5, x13, x11
.blk189:
  sw x4, 156(x28)
  or x15, x1, x11
  ori x13, x11, 305419896
  beq x10, x8, .fwd107
  .fwd107:
  bgeu x6, x11, .fwd108
  .fwd108:
  slli x5, x4, 19
.blk190:
  ori x15, x5, 1431655765
  sw x2, 612(x28)
  sub x8, x7, x11
  srli x13, x7, 0
  sll x12, x8, x8
  slt x4, x8, x14
  slt x9, x12, x13
.blk191:
  or x3, x7, x12
  ame.ld.w x23
  ame.ld.x x24
  xori x4, x14, 65535
  andi x12, x1, 31
  sra x12, x7, x8
  lb x15, 916(x28)
  slti x4, x15, -2
  sh x13, 220(x28)
.blk192:
  or x2, x14, x1
  srl x12, x13, x14
  sll x5, x14, x5
  or x1, x11, x15
.blk193:
  sub x5, x3, x13
  ori x6, x12, 4294901760
  sw x8, 228(x28)
  beq x6, x1, .fwd109
  .fwd109:
  lbu x3, 772(x28)
  beq x6, x15, .fwd110
  sltiu x8, x13, 1431655765
  sltiu x12, x6, 65535
  .fwd110:
  xori x15, x14, 4294901760
.blk194:
  slt x1, x11, x14
  sh x5, 104(x28)
  sra x14, x12, x7
  bltu x15, x9, .fwd111
  slti x1, x7, -2147483648
  xori x6, x4, 2147483647
  .fwd111:
  lh x7, 516(x28)
.blk195:
  andi x2, x5, -344865
  bge x14, x3, .blk196
  srai x3, x5, 8
  srli x7, x1, 31
  sh x12, 88(x28)
  slti x12, x13, 31
  lbu x2, 872(x28)
  addi x14, x5, 1431655765
.blk196:
  slt x9, x1, x3
  xori x4, x6, 2147483647
  and x12, x7, x9
  srai x9, x8, 4
  lbu x6, 304(x28)
.blk197:
  blt x6, x11, .fwd112
  ori x2, x9, 0
  andi x11, x2, 65535
  .fwd112:
  sw x9, 300(x28)
  ame.ld.w x23
  ame.ld.x x25
  ame.exe x26
  ame.sync
  slti x2, x6, -344865
  csrr x6, flags
  sra x7, x7, x8
.blk198:
  srl x15, x10, x12
  srli x13, x3, 16
  blt x15, x12, .fwd113
  addi x8, x10, 1431655765
  srli x9, x13, 22
  .fwd113:
  sw x3, 912(x28)
  bne x12, x8, .blk199
.blk199:
  slt x13, x2, x11
  bne x10, x6, .blk200
  blt x7, x5, .fwd114
  .fwd114:
  beq x8, x6, .blk200
.blk200:
  csrr x7, mscratch
  lh x5, 996(x28)
  andi x6, x3, 4294901760
  sltiu x2, x13, -2
  sw x11, 916(x28)
  sw x14, 316(x28)
.blk201:
  ame.sync
  li x27, 10
  ame.st.q x27, x8
  or x1, x7, x2
  slli x10, x6, 18
  sll x5, x14, x7
.blk202:
  xor x14, x11, x12
  addi x11, x6, 1431655765
  sltu x12, x10, x2
  csrr x5, minstret
  sra x6, x2, x7
  and x9, x5, x6
.blk203:
  srli x2, x7, 20
  srli x15, x15, 15
  andi x6, x3, -31
  sltiu x15, x5, 305419896
  bgeu x13, x12, .blk204
  bge x1, x10, .blk204
.blk204:
  ame.sync
  li x27, 14
  ame.st.q x27, x6
  lw x7, 136(x28)
  rem x1, x6, x2
  sb x12, 1020(x28)
  xori x15, x4, -344865
  sh x15, 996(x28)
  sra x8, x9, x2
  bltu x5, x12, .blk205
.blk205:
  ame.ld.w x23
  ame.ld.x x25
  ame.exe x26
  ame.sync
  slli x12, x3, 6
  lw x15, 444(x28)
.blk206:
  beq x11, x10, .blk207
  sltiu x2, x11, 2
  ame.ld.w x23
  ame.ld.x x25
.blk207:
  lb x14, 920(x28)
  csrs mscratch, x13
  lbu x10, 272(x28)
.blk208:
  sb x7, 216(x28)
  xor x11, x14, x3
  ame.ld.w x22
  ame.ld.x x24
  ame.exef x24
  ame.sync
  addi x12, x11, 0
  srl x6, x1, x3
  lbu x10, 32(x28)
  beq x10, x7, .blk209
.blk209:
  andi x1, x3, 255
  sb x11, 796(x28)
  ori x5, x10, -2
  bne x3, x13, .fwd115
  andi x15, x14, 0
  srli x14, x4, 29
  .fwd115:
  mul x8, x11, x7
  lhu x15, 488(x28)
.blk210:
  slt x10, x15, x1
  or x2, x13, x9
  lh x5, 264(x28)
  lb x10, 752(x28)
  xori x15, x12, 65535
  lbu x8, 744(x28)
.blk211:
  sh x8, 1020(x28)
  sh x1, 96(x28)
  add x13, x4, x2
  remu x2, x12, x3
  srli x4, x3, 4
  srli x11, x5, 23
  sra x4, x1, x5
  sb x9, 928(x28)
.blk212:
  ori x5, x8, -2147483648
  xor x3, x5, x2
  slti x7, x11, 2147483647
  lhu x15, 812(x28)
.blk213:
  mul x10, x6, x4
  sh x10, 336(x28)
  bge x3, x5, .blk214
.blk214:
  and x5, x14, x1
  add x5, x4, x11
  addi x15, x11, 32
  sub x4, x9, x13
  csrr x2, minstret
.blk215:
  and x15, x1, x7
  addi x8, x6, 32
  bgeu x9, x6, .fwd116
  .fwd116:
  sw x15, 104(x28)
.blk216:
  lw x15, 1004(x28)
  sb x6, 228(x28)
  slli x5, x11, 16
.blk217:
  sltiu x1, x15, 255
  add x1, x6, x3
  andi x1, x5, 0
.blk218:
  sltu x8, x12, x12
  bltu x8, x6, .fwd117
  .fwd117:
  divu x12, x12, x2
  srli x6, x4, 24
  lw x6, 160(x28)
  xor x2, x4, x2
  sw x6, 164(x28)
  blt x14, x10, .blk219
.blk219:
  xor x13, x15, x15
  slli x15, x3, 13
  lw x3, 400(x28)
  lw x2, 780(x28)
  blt x4, x15, .fwd118
  srli x12, x10, 24
  sltiu x2, x2, 32
  .fwd118:
  sw x11, 808(x28)
  bgeu x6, x3, .fwd119
  addi x4, x15, 4294901760
  xori x5, x6, -2
  .fwd119:
.blk220:
  mul x8, x11, x6
  ori x12, x8, 32
  sb x9, 436(x28)
  sub x10, x3, x5
.blk221:
  sub x6, x6, x4
  lw x4, 860(x28)
  sh x14, 180(x28)
  slli x7, x3, 22
  bge x13, x9, .fwd120
  srai x11, x2, 14
  srli x13, x4, 30
  .fwd120:
.blk222:
  ame.ld.w x23
  ame.ld.x x24
  sw x13, 532(x28)
  mulhsu x12, x9, x7
  xori x10, x5, 31
  slli x12, x8, 3
  sw x2, 160(x28)
.blk223:
  divu x10, x11, x11
  div x12, x11, x13
  or x7, x3, x13
  ame.sync
  li x27, 1
  ame.st.y x27, x4
  blt x3, x10, .fwd121
  .fwd121:
.blk224:
  lh x1, 680(x28)
  ame.ld.w x23
  ame.ld.x x25
  srl x6, x15, x13
  srli x4, x15, 8
.blk225:
  bge x6, x2, .fwd122
  slti x7, x13, -1
  .fwd122:
  lb x8, 304(x28)
  ame.ld.w x22
  ame.ld.x x24
  ame.exe x24
  ame.sync
  lb x15, 484(x28)
  ame.sync
  li x27, 10
  ame.st.q x27, x9
.blk226:
  andi x13, x12, 2
  sltu x5, x6, x4
  add x8, x6, x6
.blk227:
  ame.ld.w x23
  ame.ld.x x25
  ame.exe x26
  ame.sync
  sh x6, 708(x28)
  sub x9, x5, x8
  slti x2, x9, 1431655765
  or x7, x9, x10
  srl x5, x2, x7
  ame.ld.w x23
  ame.ld.x x25
  andi x7, x4, -31
.blk228:
  sw x6, 168(x28)
  srli x6, x4, 5
  and x15, x1, x8
.blk229:
  ame.sync
  li x27, 2
  ame.st.y x27, x3
  sh x3, 1012(x28)
  sb x5, 20(x28)
.blk230:
  beq x2, x10, .blk231
  sw x9, 748(x28)
  and x9, x11, x9
  slli x13, x15, 2
  slli x6, x11, 4
  blt x13, x8, .fwd123
  slli x8, x2, 16
  .fwd123:
  xori x11, x11, 1431655765
.blk231:
  add x10, x10, x7
  lw x2, 184(x28)
  srai x7, x14, 28
  bltu x14, x5, .blk232
  sltiu x8, x8, -2
  blt x2, x4, .fwd124
  .fwd124:
  sw x11, 924(x28)
  srli x6, x7, 17
.blk232:
  lhu x10, 756(x28)
  lw x13, 168(x28)
  sltu x9, x4, x4
  ame.ld.w x23
  ame.ld.x x24
  andi x1, x13, 2863311530
  slt x12, x15, x4
  srai x9, x2, 10
.blk233:
  sll x11, x5, x10
  mulhu x7, x6, x13
  srli x10, x10, 8
.blk234:
  div x1, x3, x1
  mulhu x15, x14, x13
  lw x11, 384(x28)
  lbu x15, 412(x28)
.blk235:
  mul x1, x3, x10
  beq x4, x2, .fwd125
  sltiu x7, x10, 2147483647
  ori x15, x10, 2147483647
  .fwd125:
  sh x14, 300(x28)
  bge x2, x15, .fwd126
  srli x5, x6, 15
  .fwd126:
  bgeu x12, x1, .blk236
  blt x4, x14, .fwd127
  slli x12, x14, 17
  andi x12, x15, 65535
  .fwd127:
  sw x15, 840(x28)
.blk236:
  sw x11, 644(x28)
  srl x4, x9, x3
  slli x9, x2, 27
  sw x7, 936(x28)
  slt x1, x7, x4
  ame.ld.w x23
  ame.ld.x x25
  ame.exe x26
  ame.sync
.blk237:
  csrs mscratch, x9
  bgeu x2, x7, .blk238
  sll x9, x13, x6
  slt x15, x14, x7
  or x4, x2, x14
  slli x5, x11, 14
  sw x11, 524(x28)
.blk238:
  rem x7, x15, x8
  or x1, x5, x15
  sltiu x3, x15, 128
  ame.ld.w x23
  ame.ld.x x25
  ame.ld.w x23
  ame.ld.x x25
  sll x4, x8, x7
.blk239:
  bgeu x13, x4, .fwd128
  sltiu x3, x4, -2
  srli x12, x9, 25
  .fwd128:
  and x1, x7, x6
  or x2, x4, x7
.blk240:
  beq x9, x9, .fwd129
  ori x4, x2, 4294901760
  .fwd129:
  srai x7, x13, 15
  lh x13, 988(x28)
  addi x3, x13, 65535
  ori x10, x8, -31
  mulhu x4, x14, x12
.blk241:
  srli x6, x4, 17
  csrc mscratch, x3
  csrr x14, mscratch
  slti x4, x1, 31
  ame.ld.w x22
  ame.ld.x x24
  ame.exef x24
  ame.sync
  blt x1, x7, .fwd130
  .fwd130:
  xor x3, x3, x15
.blk242:
  xor x13, x13, x11
  lh x10, 432(x28)
  sltu x12, x1, x4
  rem x6, x6, x11
  xori x11, x7, 2147483647
  sb x3, 720(x28)
  sra x1, x12, x8
.blk243:
  mulhu x6, x10, x9
  sh x3, 492(x28)
  ame.ld.w x22
  ame.ld.x x24
  ame.exef x24
  ame.sync
  sra x5, x9, x15
  sra x11, x8, x1
.blk244:
  sh x3, 52(x28)
  rem x3, x5, x9
  srl x14, x10, x11
  csrr x12, minstret
  sll x11, x8, x15
  mul x8, x5, x2
  sw x6, 320(x28)
  andi x6, x8, 1
.blk245:
  srli x15, x8, 29
  lw x4, 828(x28)
  slti x4, x5, 305419896
.blk246:
  slti x4, x7, -31
  sra x13, x5, x2
  slti x5, x6, 128
.blk247:
  slti x5, x4, 32
  sw x12, 456(x28)
  sub x15, x8, x2
  lw x6, 516(x28)
  srai x12, x12, 19
.blk248:
  add x7, x15, x3
  lw x14, 668(x28)
  bge x4, x14, .fwd131
  xori x9, x7, 1431655765
  .fwd131:
  ori x10, x8, 31
  sw x11, 284(x28)
.blk249:
  bge x12, x9, .fwd132
  addi x3, x4, 128
  slli x13, x5, 29
  .fwd132:
  sll x10, x6, x9
  sw x6, 68(x28)
.blk250:
  sll x8, x14, x11
  ame.ld.w x22
  ame.ld.x x24
  blt x5, x14, .fwd133
  .fwd133:
  and x8, x15, x8
  srai x11, x10, 12
  srai x10, x10, 21
.blk251:
  andi x9, x10, 2147483647
  slli x11, x12, 20
  bltu x12, x4, .blk252
  lw x11, 376(x28)
  srl x1, x1, x2
.blk252:
  lw x4, 328(x28)
  lw x1, 500(x28)
  lb x2, 756(x28)
  bltu x14, x14, .fwd134
  xori x9, x11, 2863311530
  .fwd134:
  sh x11, 4(x28)
.blk253:
  lbu x9, 160(x28)
  beq x10, x7, .fwd135
  srli x4, x7, 25
  .fwd135:
  rem x1, x14, x1
  bne x7, x10, .fwd136
  srli x4, x3, 26
  .fwd136:
.blk254:
  sltiu x15, x6, 65535
  csrr x2, mscratch
  ame.ld.w x22
  ame.ld.x x24
  ame.exef x24
  ame.sync
  slti x12, x5, 2863311530
  ori x2, x3, 305419896
.blk255:
  or x13, x3, x8
  lb x6, 268(x28)
  beq x3, x8, .fwd137
  addi x11, x2, -2
  slti x7, x11, 255
  .fwd137:
  sltu x1, x15, x2
  sb x13, 868(x28)
.blk256:
  sh x9, 900(x28)
  beq x10, x10, .fwd138
  .fwd138:
  or x4, x13, x1
  slli x4, x3, 25
  bltu x3, x14, .fwd139
  ori x4, x8, 2
  sltiu x7, x8, 0
  .fwd139:
  bgeu x13, x8, .fwd140
  .fwd140:
  and x10, x15, x5
  sw x10, 960(x28)
.blk257:
  slt x2, x14, x5
  slt x14, x11, x3
  beq x1, x6, .fwd141
  ori x15, x12, 2147483647
  addi x11, x13, 128
  .fwd141:
  srai x1, x2, 23
  sh x1, 156(x28)
  lb x10, 36(x28)
  mulh x8, x2, x6
  add x3, x13, x10
.blk258:
  lw x4, 456(x28)
  sh x2, 712(x28)
  bltu x2, x12, .fwd142
  .fwd142:
  sw x15, 632(x28)
  sltu x2, x15, x15
  srai x10, x6, 28
  blt x12, x10, .fwd143
  srai x8, x13, 29
  slti x10, x3, -344865
  .fwd143:
.blk259:
  ame.ld.w x22
  ame.ld.x x25
  ame.ld.w x23
  ame.ld.x x25
  ame.exe x26
  ame.sync
  bgeu x11, x14, .blk_end
.blk_end:
  ame.sync
  li x28, 0x1FFF0
  li x29, 0x600D
  sw x29, 0(x28)
  ebreak
