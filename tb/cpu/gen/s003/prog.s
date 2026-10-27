# 随机生成(cpu_gen_random.py)
  .org 0x10000
boot:
  j start
  .org 0x0
start:
  li x1, 305419896
  li x2, 128
  li x3, -2
  li x4, 65535
  li x5, -31
  li x6, -1
  li x7, 0
  li x8, -31
  li x9, -344865
  li x10, 128
  li x11, 305419896
  li x12, -2147483648
  li x13, -31
  li x14, 128
  li x15, 128
  li x28, 0x4000
.blk0:
  lw x11, 308(x28)
  bltu x3, x14, .fwd1
  .fwd1:
  ame.cfg 16, 16
  li x20, 3
  li x21, 65
  ame.qcfg 0, x20, x21
  li x22, 0
  li x23, 5
  li x24, 0
  li x25, 528
  li x26, 1
  addi x3, x13, 1431655765
  slti x14, x14, -31
  bge x12, x15, .blk1
.blk1:
  lw x12, 908(x28)
  remu x2, x1, x3
  xor x5, x11, x7
  lh x9, 788(x28)
  mulhu x9, x10, x7
  add x11, x15, x15
.blk2:
  bne x11, x12, .fwd2
  xori x9, x15, -2147483648
  .fwd2:
  blt x14, x10, .fwd3
  .fwd3:
  sw x14, 988(x28)
  mulhsu x13, x2, x7
  slli x5, x7, 7
.blk3:
  beq x10, x13, .fwd4
  slti x6, x9, 255
  slti x4, x1, 0
  .fwd4:
  srai x2, x10, 2
  xor x7, x5, x10
.blk4:
  ame.ld.w x22
  ame.ld.x x24
  ame.exe x24
  ame.sync
  srl x6, x3, x15
  rem x8, x14, x9
  bgeu x14, x10, .fwd5
  slti x13, x9, 31
  andi x11, x12, 1431655765
  .fwd5:
.blk5:
  sll x9, x5, x9
  sltiu x13, x7, 0
  mulhsu x10, x10, x11
  sltiu x11, x11, 32
  div x11, x15, x6
  csrr x8, minstret
.blk6:
  sltiu x11, x1, -344865
  bltu x8, x5, .fwd6
  .fwd6:
  divu x3, x6, x13
  bge x5, x5, .fwd7
  .fwd7:
  bne x11, x12, .fwd8
  .fwd8:
  bne x13, x5, .fwd9
  xori x7, x11, 2
  sltiu x10, x6, 305419896
  .fwd9:
  lw x13, 344(x28)
.blk7:
  csrr x11, minstret
  bne x8, x5, .blk8
  sltiu x9, x4, 2147483647
  sub x6, x13, x14
  bne x6, x10, .fwd10
  slti x13, x14, 32
  slli x6, x11, 18
  .fwd10:
.blk8:
  bge x7, x1, .fwd11
  .fwd11:
  sw x14, 888(x28)
  srai x12, x8, 18
  sw x6, 464(x28)
  bne x5, x2, .fwd12
  andi x9, x15, 31
  addi x10, x1, -31
  .fwd12:
  csrr x2, minstret
.blk9:
  slt x4, x11, x1
  sw x7, 108(x28)
  slt x3, x5, x14
  sb x13, 124(x28)
  sub x4, x2, x9
  slti x4, x13, -2
  slli x8, x11, 3
.blk10:
  slt x5, x10, x9
  lb x1, 968(x28)
  ori x14, x1, 1
  srli x1, x2, 2
  ame.ld.w x22
  ame.ld.x x24
  ame.exe x24
  ame.sync
.blk11:
  sltiu x6, x2, 4294901760
  blt x7, x10, .fwd13
  .fwd13:
  slt x7, x2, x3
  slli x12, x12, 5
  blt x3, x1, .fwd14
  slli x13, x9, 2
  slli x10, x15, 3
  .fwd14:
.blk12:
  bgeu x8, x13, .fwd15
  addi x7, x8, 305419896
  slti x4, x9, -1
  .fwd15:
  lw x4, 872(x28)
  sltiu x15, x6, 128
  sub x2, x8, x12
  csrc mscratch, x11
.blk13:
  csrr x6, minstret
  bge x12, x1, .fwd16
  xori x1, x9, 2
  .fwd16:
  ame.sync
  li x27, 5
  ame.st.y x27, x6
.blk14:
  srli x14, x2, 18
  beq x5, x13, .fwd17
  andi x9, x9, 2
  xori x9, x12, 128
  .fwd17:
  ori x9, x6, -1
.blk15:
  sltu x11, x4, x8
  ame.sync
  li x27, 8
  ame.st.q x27, x10
  lw x6, 856(x28)
  rem x9, x4, x15
.blk16:
  srai x7, x12, 30
  ori x11, x7, 2147483647
  srli x8, x12, 28
  bne x12, x14, .fwd18
  .fwd18:
  sltiu x10, x9, 305419896
  ame.ld.w x23
  ame.ld.x x25
  sra x5, x1, x5
  divu x4, x3, x10
.blk17:
  and x8, x13, x14
  lhu x12, 980(x28)
  bltu x4, x8, .blk18
  bge x9, x1, .blk18
.blk18:
  lbu x13, 92(x28)
  sub x15, x4, x11
  or x14, x5, x4
.blk19:
  addi x3, x10, -344865
  sltiu x14, x1, 2147483647
  lw x2, 172(x28)
  slti x5, x14, 1
  divu x8, x10, x12
.blk20:
  slli x6, x6, 24
  sh x2, 428(x28)
  lw x3, 652(x28)
.blk21:
  xori x11, x7, 32
  sw x15, 512(x28)
  sb x12, 764(x28)
  lw x5, 540(x28)
  slt x11, x10, x9
.blk22:
  ame.sync
  li x27, 11
  ame.st.y x27, x12
  and x11, x12, x10
  bgeu x11, x12, .fwd19
  srli x15, x15, 7
  .fwd19:
.blk23:
  blt x3, x15, .fwd20
  srai x10, x7, 19
  srli x11, x3, 30
  .fwd20:
  sub x13, x3, x12
  srai x12, x3, 25
.blk24:
  slli x5, x5, 3
  srai x1, x8, 17
  sll x12, x13, x9
  sub x7, x8, x9
  mulhsu x8, x14, x2
.blk25:
  beq x2, x11, .fwd21
  andi x2, x3, 31
  slli x11, x12, 8
  .fwd21:
  bge x10, x3, .blk26
  sw x9, 348(x28)
  xor x14, x5, x6
  srli x14, x13, 26
.blk26:
  xor x9, x15, x10
  bgeu x8, x9, .blk27
  ame.sync
  li x27, 0
  ame.st.y x27, x12
  bgeu x1, x2, .fwd22
  .fwd22:
  sw x11, 940(x28)
  add x13, x9, x4
.blk27:
  bltu x8, x2, .fwd23
  ori x15, x3, 32
  addi x13, x2, 0
  .fwd23:
  mulh x10, x4, x9
  sb x9, 36(x28)
  and x6, x14, x6
  addi x14, x14, -1
  csrr x6, minstret
  slli x14, x4, 14
.blk28:
  srl x2, x13, x1
  ori x14, x4, 4294901760
  sh x8, 136(x28)
  add x11, x8, x5
  lbu x8, 820(x28)
  xor x8, x15, x1
.blk29:
  rem x8, x9, x6
  xor x1, x13, x4
  mulhu x3, x14, x8
  ori x4, x1, 4294901760
  sw x3, 56(x28)
.blk30:
  bge x3, x8, .fwd24
  .fwd24:
  lbu x8, 648(x28)
  addi x12, x12, 305419896
.blk31:
  addi x7, x8, 305419896
  or x2, x7, x8
  xori x6, x10, 65535
  slti x10, x1, -344865
  lbu x13, 612(x28)
  sll x9, x5, x1
.blk32:
  rem x6, x2, x1
  addi x10, x10, 2
  addi x11, x2, 2147483647
  sw x1, 984(x28)
  sll x11, x9, x15
  sll x15, x13, x8
  sw x15, 716(x28)
  rem x5, x13, x10
.blk33:
  sub x3, x14, x7
  sh x7, 684(x28)
  srl x14, x12, x14
.blk34:
  rem x15, x3, x6
  lhu x4, 908(x28)
  sw x6, 548(x28)
  sh x12, 792(x28)
  addi x3, x3, 32
  xori x13, x12, 2863311530
  add x10, x14, x13
.blk35:
  sltiu x8, x8, 65535
  slli x2, x4, 6
  sra x10, x5, x2
  andi x14, x11, 305419896
  ame.ld.w x22
  ame.ld.x x24
  ame.exef x24
  ame.sync
  beq x3, x10, .fwd25
  srai x4, x4, 26
  .fwd25:
  sw x13, 652(x28)
.blk36:
  sub x10, x2, x1
  beq x1, x14, .fwd26
  srli x2, x2, 25
  .fwd26:
  sltu x14, x14, x11
  sltiu x11, x8, 4294901760
  beq x11, x8, .fwd27
  slli x8, x14, 13
  addi x2, x9, 32
  .fwd27:
  sll x12, x11, x2
.blk37:
  slt x8, x13, x2
  ame.ld.w x23
  ame.ld.x x24
  bne x9, x4, .fwd28
  .fwd28:
  sub x4, x7, x8
  or x4, x6, x3
.blk38:
  sltu x14, x15, x12
  lb x15, 856(x28)
  sra x15, x10, x7
  lb x8, 68(x28)
  xori x3, x15, 0
  csrr x3, flags
  sh x9, 124(x28)
  andi x4, x12, -344865
.blk39:
  lbu x1, 704(x28)
  csrr x4, flags
  slti x2, x8, 31
  lw x2, 420(x28)
  sh x13, 580(x28)
  bge x6, x3, .fwd29
  srai x8, x9, 14
  .fwd29:
.blk40:
  sll x5, x1, x8
  mulhu x13, x14, x5
  sw x1, 28(x28)
  bltu x9, x3, .fwd30
  .fwd30:
  srli x4, x13, 22
.blk41:
  bne x1, x8, .fwd31
  sltiu x7, x15, 1
  .fwd31:
  beq x9, x13, .fwd32
  srli x4, x11, 26
  .fwd32:
  csrr x5, flags
  addi x1, x7, 2147483647
  bgeu x4, x3, .blk42
.blk42:
  sw x13, 688(x28)
  add x1, x3, x1
  sh x11, 120(x28)
  lb x9, 848(x28)
  sb x11, 348(x28)
  slt x2, x11, x3
.blk43:
  lbu x13, 720(x28)
  lbu x5, 520(x28)
  sll x9, x3, x10
.blk44:
  sh x1, 840(x28)
  sltu x14, x8, x15
  blt x5, x1, .fwd33
  ori x2, x8, -344865
  slti x13, x12, 2
  .fwd33:
  lb x11, 152(x28)
.blk45:
  sw x8, 916(x28)
  srl x15, x6, x3
  lb x6, 100(x28)
.blk46:
  slli x6, x6, 18
  slti x3, x7, 31
  andi x8, x4, -1
  ame.ld.w x22
  ame.ld.x x24
  ame.exef x24
  ame.sync
.blk47:
  xori x5, x12, 31
  xor x8, x8, x5
  sw x9, 96(x28)
  and x8, x3, x3
  ame.ld.w x23
  ame.ld.x x25
  ame.exe x26
  ame.sync
  ame.sync
  li x27, 0
  ame.st.y x27, x7
  ori x3, x13, 1431655765
  and x11, x14, x3
.blk48:
  sh x3, 436(x28)
  ori x7, x7, 0
  and x2, x3, x2
.blk49:
  xori x7, x6, -2147483648
  srli x6, x3, 15
  srli x6, x9, 6
  ame.ld.w x23
  ame.ld.x x24
  csrc mscratch, x6
.blk50:
  lbu x9, 624(x28)
  slli x9, x8, 12
  bgeu x5, x15, .blk51
  and x5, x14, x14
  and x5, x14, x4
  slli x10, x1, 11
.blk51:
  beq x1, x3, .blk52
  bltu x11, x6, .fwd34
  srai x2, x8, 28
  .fwd34:
  or x3, x10, x10
.blk52:
  lhu x9, 764(x28)
  sltu x10, x6, x12
  csrr x15, flags
  ame.ld.w x23
  ame.ld.x x25
  slt x3, x2, x10
.blk53:
  csrr x6, minstret
  and x7, x5, x8
  sh x6, 360(x28)
  bge x1, x2, .fwd35
  addi x13, x5, 305419896
  slli x14, x7, 13
  .fwd35:
.blk54:
  remu x9, x4, x1
  slli x7, x12, 23
  srai x5, x6, 23
.blk55:
  lh x6, 212(x28)
  sw x3, 660(x28)
  addi x6, x2, -2
  slli x4, x6, 18
  sll x1, x1, x9
  sw x8, 744(x28)
.blk56:
  slt x11, x10, x2
  div x4, x8, x3
  and x9, x4, x2
  bge x15, x2, .fwd36
  srli x7, x1, 11
  .fwd36:
  sh x5, 284(x28)
  sltu x9, x11, x7
.blk57:
  ame.ld.w x23
  ame.ld.x x25
  xori x11, x12, -1
  lw x15, 656(x28)
  slli x6, x8, 6
  ame.ld.w x23
  ame.ld.x x24
  sub x4, x11, x7
  addi x11, x9, 255
  sw x4, 172(x28)
.blk58:
  sb x14, 808(x28)
  mulhu x8, x11, x9
  sltu x10, x5, x6
  sltiu x10, x9, 255
.blk59:
  sltu x13, x14, x15
  csrr x12, minstret
  lb x1, 884(x28)
  bne x4, x8, .fwd37
  .fwd37:
  lw x2, 812(x28)
.blk60:
  sra x13, x1, x6
  add x7, x15, x14
  or x7, x6, x7
  xor x5, x5, x6
  xori x12, x6, -2147483648
.blk61:
  and x8, x3, x10
  or x8, x12, x4
  ame.ld.w x22
  ame.ld.x x24
  ame.sync
  li x27, 13
  ame.st.y x27, x11
.blk62:
  lw x6, 112(x28)
  sh x14, 936(x28)
  slti x10, x3, 255
  lw x11, 1012(x28)
  divu x14, x9, x8
.blk63:
  bne x8, x13, .fwd38
  ori x6, x14, 2863311530
  .fwd38:
  ori x6, x9, 1431655765
  sh x11, 308(x28)
  divu x8, x1, x10
  beq x4, x10, .blk64
  bltu x10, x5, .blk64
.blk64:
  sb x6, 840(x28)
  srai x7, x11, 22
  lh x8, 756(x28)
  or x4, x5, x12
  bgeu x14, x7, .fwd39
  srli x3, x6, 11
  srli x9, x7, 12
  .fwd39:
.blk65:
  beq x10, x6, .blk66
  bne x8, x12, .fwd40
  xori x3, x2, 128
  slli x9, x2, 20
  .fwd40:
  lbu x5, 132(x28)
  xor x11, x6, x4
  srli x4, x2, 23
  lb x3, 536(x28)
.blk66:
  slt x5, x10, x13
  xor x11, x4, x4
  mulh x12, x6, x15
  ori x14, x12, -1
  sll x8, x6, x2
  srli x3, x1, 17
  sh x3, 760(x28)
  csrs mscratch, x7
.blk67:
  srl x9, x5, x10
  ori x1, x1, 31
  bne x1, x4, .fwd41
  .fwd41:
  ame.ld.w x23
  ame.ld.x x24
  bgeu x9, x10, .blk68
.blk68:
  sub x2, x3, x4
  sw x7, 588(x28)
  ori x9, x6, -344865
  xori x2, x10, -2
  xori x1, x12, 255
.blk69:
  ame.sync
  li x27, 14
  ame.st.q x27, x3
  ame.ld.w x22
  ame.ld.x x24
  ame.exef x24
  ame.sync
  and x11, x12, x7
  srai x1, x6, 20
  mulhu x2, x1, x13
  remu x1, x13, x9
.blk70:
  csrr x6, minstret
  lw x8, 484(x28)
  rem x4, x4, x3
  lb x2, 808(x28)
  bgeu x2, x9, .fwd42
  slli x2, x1, 1
  .fwd42:
  bne x6, x4, .fwd43
  slli x5, x11, 13
  slli x9, x10, 19
  .fwd43:
  srli x3, x13, 6
  and x15, x10, x10
.blk71:
  sw x3, 628(x28)
  sub x6, x9, x5
  srli x8, x2, 15
  csrr x15, mscratch
  addi x1, x8, 1
  ame.sync
  li x27, 0
  ame.st.y x27, x6
.blk72:
  sra x5, x14, x8
  and x13, x5, x13
  srl x11, x10, x2
  bgeu x1, x2, .fwd44
  .fwd44:
  srai x12, x7, 8
  bgeu x3, x2, .fwd45
  xori x1, x8, 65535
  xori x11, x8, 31
  .fwd45:
  ame.ld.w x23
  ame.ld.x x25
  lb x6, 56(x28)
.blk73:
  sh x12, 528(x28)
  csrr x5, minstret
  remu x2, x11, x5
  lhu x8, 412(x28)
  or x10, x1, x11
.blk74:
  andi x10, x7, 4294901760
  and x6, x2, x11
  sh x8, 520(x28)
  lbu x10, 696(x28)
  lb x14, 80(x28)
  csrs mscratch, x14
  csrr x7, flags
.blk75:
  or x3, x4, x15
  bge x1, x11, .blk76
  slli x10, x13, 30
  sw x7, 884(x28)
  sw x7, 116(x28)
  xori x4, x10, -2
  lw x13, 236(x28)
.blk76:
  blt x4, x15, .fwd46
  .fwd46:
  lw x7, 296(x28)
  srl x12, x14, x11
.blk77:
  add x11, x8, x9
  sll x9, x1, x10
  sub x9, x7, x4
  srl x4, x2, x4
  sll x14, x4, x14
  sll x12, x15, x2
.blk78:
  slt x13, x4, x14
  add x9, x12, x7
  sw x11, 608(x28)
  xori x13, x5, -344865
  divu x4, x5, x3
  slt x15, x4, x15
  slti x8, x7, 1
.blk79:
  lh x5, 588(x28)
  xor x8, x15, x4
  rem x11, x2, x2
  lhu x12, 704(x28)
  bgeu x4, x5, .fwd47
  ori x2, x1, 2863311530
  ori x6, x10, 305419896
  .fwd47:
  sll x1, x2, x13
  bge x9, x2, .blk80
.blk80:
  sra x1, x8, x8
  xori x8, x1, 2147483647
  div x14, x14, x8
  remu x14, x9, x4
  divu x8, x6, x12
  csrr x1, flags
  sh x10, 1012(x28)
.blk81:
  sw x2, 624(x28)
  and x9, x2, x11
  sll x12, x13, x5
.blk82:
  mulhu x9, x1, x14
  add x15, x1, x10
  remu x3, x2, x11
.blk83:
  csrr x8, minstret
  lhu x11, 888(x28)
  beq x12, x2, .blk84
  andi x11, x2, 2
  add x2, x11, x6
.blk84:
  addi x12, x8, 2
  sb x15, 436(x28)
  ame.sync
  li x27, 9
  ame.st.q x27, x12
  srai x14, x4, 0
.blk85:
  bgeu x7, x3, .blk86
  lhu x9, 840(x28)
  sb x3, 620(x28)
  ori x4, x13, 128
.blk86:
  lw x13, 796(x28)
  sb x15, 648(x28)
  and x6, x13, x13
  srl x6, x2, x3
  csrs mscratch, x5
.blk87:
  lw x14, 440(x28)
  bltu x6, x1, .blk88
  lh x1, 936(x28)
  ame.ld.w x23
  ame.ld.x x25
  csrr x4, flags
  xori x14, x12, -31
  lw x7, 336(x28)
.blk88:
  ame.ld.w x23
  ame.ld.x x25
  ame.exe x26
  ame.sync
  andi x3, x15, 305419896
  lb x11, 240(x28)
  mulh x11, x4, x14
  slti x6, x8, -31
.blk89:
  sltiu x15, x13, 1431655765
  sltu x11, x8, x10
  sb x5, 972(x28)
  add x2, x4, x9
  divu x15, x9, x2
  srli x3, x1, 10
  sll x2, x3, x14
.blk90:
  slt x8, x12, x9
  srai x1, x13, 14
  ame.ld.w x22
  ame.ld.x x25
  blt x4, x6, .fwd48
  .fwd48:
  lw x7, 828(x28)
  lw x15, 824(x28)
  bltu x12, x13, .fwd49
  sltiu x7, x5, 2
  .fwd49:
.blk91:
  srl x13, x13, x2
  csrc mscratch, x1
  lhu x13, 508(x28)
.blk92:
  lb x1, 540(x28)
  sll x7, x15, x11
  lw x12, 40(x28)
.blk93:
  bne x6, x9, .blk94
  div x6, x12, x6
  blt x3, x4, .blk94
  ori x4, x11, -31
  sra x4, x3, x10
  sw x10, 904(x28)
  lbu x14, 520(x28)
  bne x7, x2, .fwd50
  .fwd50:
.blk94:
  ame.ld.w x23
  ame.ld.x x25
  srl x14, x15, x12
  bge x9, x13, .fwd51
  slti x9, x2, 2863311530
  .fwd51:
  blt x13, x13, .blk95
.blk95:
  csrc mscratch, x12
  slt x11, x12, x4
  xor x6, x14, x10
  lhu x4, 240(x28)
.blk96:
  sh x10, 36(x28)
  srai x13, x14, 19
  slt x10, x6, x3
.blk97:
  sra x15, x15, x3
  ame.sync
  li x27, 8
  ame.st.y x27, x3
  ame.sync
  li x27, 2
  ame.st.y x27, x14
  remu x1, x10, x11
.blk98:
  beq x7, x7, .fwd52
  slti x7, x14, 65535
  .fwd52:
  bge x15, x10, .blk99
  lhu x4, 144(x28)
.blk99:
  lb x13, 232(x28)
  sb x2, 480(x28)
  or x13, x11, x14
  blt x11, x11, .blk100
  addi x2, x10, -2
.blk100:
  beq x4, x11, .fwd53
  .fwd53:
  sw x13, 176(x28)
  lw x9, 932(x28)
  andi x14, x6, 4294901760
.blk101:
  sub x2, x1, x2
  bgeu x12, x5, .blk102
  sub x3, x8, x3
  ame.ld.w x22
  ame.ld.x x25
  sw x11, 312(x28)
  xor x4, x11, x8
.blk102:
  ame.ld.w x22
  ame.ld.x x24
  ame.exef x24
  ame.sync
  bgeu x5, x14, .fwd54
  .fwd54:
  bgeu x3, x3, .fwd55
  andi x2, x13, 2
  .fwd55:
  sll x14, x3, x9
  ame.ld.w x23
  ame.ld.x x25
  ame.exe x26
  ame.sync
  srli x5, x2, 15
.blk103:
  lbu x4, 244(x28)
  bltu x11, x12, .blk104
  slt x11, x15, x15
  srl x2, x3, x8
  xori x10, x7, 305419896
  sw x7, 336(x28)
  addi x15, x8, 2147483647
.blk104:
  sll x14, x10, x14
  sb x15, 940(x28)
  xori x14, x15, 65535
  beq x10, x1, .blk105
.blk105:
  slti x2, x3, 2
  srli x14, x5, 0
  lw x12, 784(x28)
  slt x6, x3, x14
  mulh x4, x11, x12
.blk106:
  bgeu x5, x9, .fwd56
  .fwd56:
  mulhu x5, x2, x12
  sh x11, 184(x28)
  slt x2, x10, x14
  bgeu x13, x6, .fwd57
  .fwd57:
.blk107:
  csrs mscratch, x10
  ame.ld.w x22
  ame.ld.x x24
  ame.ld.w x22
  ame.ld.x x24
  ame.exef x24
  ame.sync
  srl x9, x8, x6
  bgeu x13, x7, .fwd58
  srai x5, x7, 24
  xori x13, x5, 2863311530
  .fwd58:
  slli x2, x15, 27
  sub x12, x8, x5
.blk108:
  lw x14, 988(x28)
  srli x10, x7, 13
  ame.sync
  li x27, 9
  ame.st.y x27, x12
  blt x5, x11, .fwd59
  addi x15, x4, 1
  srai x8, x7, 24
  .fwd59:
.blk109:
  mul x14, x15, x7
  slli x13, x1, 26
  lw x2, 500(x28)
  ame.ld.w x23
  ame.ld.x x25
  ame.exe x26
  ame.sync
  sltiu x11, x10, 65535
  blt x1, x5, .fwd60
  slti x14, x10, -31
  addi x6, x13, -2147483648
  .fwd60:
  mul x12, x12, x15
.blk110:
  sltiu x2, x4, -31
  slli x8, x11, 0
  remu x14, x1, x5
  bge x3, x11, .fwd61
  xori x13, x9, -1
  .fwd61:
  andi x14, x2, 0
.blk111:
  ame.ld.w x23
  ame.ld.x x25
  bne x1, x7, .blk112
  or x2, x8, x11
  divu x3, x14, x14
.blk112:
  mulh x6, x9, x6
  and x8, x2, x6
  mulhsu x4, x2, x14
  sh x9, 620(x28)
.blk113:
  sub x9, x2, x7
  sltu x2, x14, x2
  or x5, x6, x15
  sltu x3, x11, x12
  sw x2, 316(x28)
  or x11, x6, x13
  ori x11, x14, 4294901760
.blk114:
  slti x4, x13, 1431655765
  sltiu x6, x8, 2863311530
  sh x5, 688(x28)
  beq x15, x14, .blk115
  ame.ld.w x23
  ame.ld.x x25
  ame.exe x26
  ame.sync
  bne x15, x8, .fwd62
  sltiu x12, x4, 2
  .fwd62:
  sw x2, 1016(x28)
  sll x11, x3, x1
.blk115:
  bne x5, x1, .fwd63
  srli x3, x10, 8
  .fwd63:
  sltiu x6, x9, 128
  sb x4, 632(x28)
.blk116:
  ame.ld.w x22
  ame.ld.x x24
  ame.exe x24
  ame.sync
  xor x14, x10, x2
  bne x13, x2, .fwd64
  sltiu x8, x5, 1431655765
  .fwd64:
  sub x5, x7, x13
  slli x2, x11, 5
  sh x3, 328(x28)
.blk117:
  add x6, x10, x7
  lbu x4, 20(x28)
  sb x9, 560(x28)
  ame.ld.w x22
  ame.ld.x x25
.blk118:
  and x12, x2, x3
  srl x10, x15, x2
  srai x8, x7, 30
.blk119:
  srai x6, x13, 16
  sw x6, 52(x28)
  bgeu x4, x9, .blk120
  bge x8, x10, .fwd65
  addi x11, x13, -31
  sltiu x8, x11, 2147483647
  .fwd65:
.blk120:
  addi x6, x14, -344865
  lb x9, 900(x28)
  div x10, x2, x1
  xori x13, x9, 1431655765
  lbu x14, 600(x28)
.blk121:
  slti x9, x5, 1
  mulhu x7, x5, x15
  bne x6, x3, .fwd66
  addi x6, x2, 0
  slli x9, x8, 18
  .fwd66:
  ame.sync
  li x27, 12
  ame.st.q x27, x6
  lh x12, 104(x28)
  lw x9, 200(x28)
.blk122:
  sll x3, x14, x6
  srai x4, x5, 25
  or x6, x6, x12
  srli x9, x1, 5
  srl x10, x11, x5
  xori x3, x10, 65535
  ori x3, x15, -2147483648
.blk123:
  sra x11, x8, x11
  slt x15, x4, x11
  sll x10, x5, x6
  ame.ld.w x23
  ame.ld.x x25
  ame.exe x26
  ame.sync
  div x3, x5, x15
  csrc mscratch, x4
  remu x8, x15, x12
.blk124:
  slli x15, x1, 28
  lb x12, 908(x28)
  add x15, x8, x6
.blk125:
  sub x3, x14, x15
  slti x2, x1, 65535
  lh x9, 944(x28)
  ame.ld.w x22
  ame.ld.x x24
  sra x5, x10, x11
  srl x15, x12, x10
  srl x10, x13, x6
  remu x13, x13, x4
.blk126:
  or x14, x4, x9
  slti x13, x2, 32
  slt x11, x13, x3
  sh x15, 252(x28)
  bge x7, x12, .fwd67
  .fwd67:
  sw x2, 528(x28)
  add x12, x7, x15
  csrr x8, minstret
.blk127:
  ame.ld.w x22
  ame.ld.x x24
  ame.exef x24
  ame.sync
  ame.sync
  li x27, 15
  ame.st.q x27, x6
  xori x10, x5, 0
  bltu x5, x11, .fwd68
  .fwd68:
  ame.ld.w x22
  ame.ld.x x24
  ame.exe x24
  ame.sync
  sh x12, 144(x28)
.blk128:
  bltu x2, x7, .fwd69
  addi x2, x14, 1431655765
  sltiu x15, x6, 2863311530
  .fwd69:
  lb x10, 280(x28)
  remu x5, x10, x4
  sltiu x3, x9, 305419896
  divu x14, x10, x2
.blk129:
  or x12, x14, x13
  sw x3, 44(x28)
  sw x14, 800(x28)
  bne x1, x12, .fwd70
  sltiu x14, x7, 65535
  .fwd70:
.blk130:
  csrr x12, mscratch
  csrs mscratch, x13
  sra x13, x4, x7
  sll x13, x1, x6
.blk131:
  xori x6, x6, -2147483648
  sw x12, 952(x28)
  sll x10, x6, x9
.blk132:
  lhu x14, 892(x28)
  sw x15, 828(x28)
  rem x5, x13, x12
  sw x12, 604(x28)
  srai x8, x9, 6
.blk133:
  srli x14, x6, 16
  bne x5, x13, .fwd71
  .fwd71:
  sb x13, 984(x28)
.blk134:
  sw x14, 44(x28)
  sll x4, x11, x7
  bgeu x11, x8, .fwd72
  sltiu x9, x5, -2147483648
  .fwd72:
  srai x5, x1, 26
  ori x14, x2, 4294901760
  csrr x13, flags
  srl x12, x13, x14
  andi x1, x5, 1
.blk135:
  sub x14, x10, x9
  sltiu x5, x10, -2147483648
  sh x14, 216(x28)
  or x9, x13, x2
  srai x3, x4, 25
  xori x11, x11, 0
  remu x8, x1, x5
.blk136:
  srli x11, x6, 20
  lh x14, 560(x28)
  bgeu x6, x7, .fwd73
  xori x8, x10, 128
  .fwd73:
  mulhu x3, x1, x5
.blk137:
  slti x15, x15, -2
  ame.sync
  li x27, 7
  ame.st.q x27, x2
  sb x11, 344(x28)
  bltu x3, x14, .fwd74
  srai x8, x15, 12
  .fwd74:
.blk138:
  sw x1, 964(x28)
  srl x8, x2, x8
  slt x13, x6, x8
  or x12, x6, x2
  srai x12, x2, 4
  srl x15, x9, x10
.blk139:
  and x15, x4, x10
  beq x3, x5, .fwd75
  sltiu x3, x8, 1
  .fwd75:
  sltiu x4, x15, 32
.blk140:
  sh x14, 620(x28)
  sb x1, 48(x28)
  ame.ld.w x22
  ame.ld.x x24
  ame.exe x24
  ame.sync
  lw x13, 168(x28)
  ori x11, x3, 65535
.blk141:
  ori x10, x2, 32
  add x10, x7, x2
  sra x4, x13, x13
  blt x12, x10, .fwd76
  andi x1, x12, -344865
  srli x11, x11, 29
  .fwd76:
  and x6, x14, x9
.blk142:
  srl x10, x7, x3
  ame.ld.w x22
  ame.ld.x x24
  ame.exe x24
  ame.sync
  or x12, x3, x14
  slt x15, x15, x8
  and x1, x10, x14
  xor x7, x5, x6
  or x4, x1, x5
.blk143:
  ame.ld.w x23
  ame.ld.x x25
  sw x11, 648(x28)
  csrc mscratch, x8
  and x6, x13, x12
  mulh x1, x11, x5
.blk144:
  lw x15, 232(x28)
  ame.ld.w x23
  ame.ld.x x25
  ame.exef x26
  ame.sync
  bne x10, x6, .blk145
  csrr x1, flags
  or x14, x13, x10
.blk145:
  div x3, x1, x14
  sra x6, x3, x12
  mulhu x9, x5, x11
.blk146:
  sra x5, x2, x3
  divu x12, x10, x11
  ame.sync
  li x27, 14
  ame.st.q x27, x11
  mul x6, x15, x3
  div x8, x12, x14
  mulhsu x9, x11, x2
  bgeu x15, x8, .blk147
  bne x1, x2, .blk147
.blk147:
  and x3, x5, x13
  sltu x15, x3, x13
  sll x13, x11, x6
  slli x6, x3, 20
  ame.ld.w x22
  ame.ld.x x25
.blk148:
  blt x10, x8, .blk149
  addi x14, x3, 31
  slli x10, x8, 18
  srai x4, x2, 14
  bgeu x6, x2, .fwd77
  ori x5, x15, 255
  slti x4, x1, -31
  .fwd77:
  sb x2, 1000(x28)
.blk149:
  sw x4, 288(x28)
  lh x9, 64(x28)
  ame.ld.w x23
  ame.ld.x x25
.blk150:
  ame.ld.w x22
  ame.ld.x x24
  srai x4, x8, 27
  ori x9, x13, 65535
  bge x12, x10, .fwd78
  xori x12, x13, 32
  .fwd78:
.blk151:
  csrr x4, minstret
  slt x12, x11, x4
  sltiu x1, x3, -1
  xori x6, x8, 2147483647
  slti x4, x15, -2
  mulhu x5, x10, x9
  andi x10, x9, 1
  andi x7, x11, 128
.blk152:
  sh x3, 476(x28)
  srai x13, x2, 19
  lh x1, 48(x28)
.blk153:
  andi x13, x11, 65535
  addi x11, x5, 2
  sw x15, 900(x28)
.blk154:
  ame.sync
  li x27, 1
  ame.st.y x27, x12
  lbu x11, 180(x28)
  sw x14, 100(x28)
  csrr x5, flags
.blk155:
  ame.ld.w x23
  ame.ld.x x25
  bgeu x6, x13, .fwd79
  srai x15, x13, 1
  slli x7, x8, 28
  .fwd79:
  sb x10, 1008(x28)
  sltiu x11, x14, -2
.blk156:
  xor x3, x8, x12
  bltu x5, x8, .fwd80
  xori x1, x1, -2147483648
  .fwd80:
  rem x9, x12, x10
  andi x1, x9, 2147483647
  or x11, x13, x2
  add x10, x3, x14
.blk157:
  ame.ld.w x23
  ame.ld.x x25
  ame.exef x26
  ame.sync
  sw x15, 108(x28)
  bne x4, x3, .fwd81
  slti x6, x9, 0
  xori x10, x12, 2
  .fwd81:
  slt x4, x7, x13
  ame.ld.w x22
  ame.ld.x x25
  sb x12, 952(x28)
.blk158:
  bgeu x8, x2, .fwd82
  ori x14, x1, -1
  .fwd82:
  xori x8, x4, 255
  srli x9, x8, 5
  rem x12, x8, x1
  slli x12, x3, 2
  sll x14, x7, x14
.blk159:
  ame.ld.w x23
  ame.ld.x x25
  ame.exef x26
  ame.sync
  lb x7, 160(x28)
  bne x10, x6, .fwd83
  sltiu x6, x8, 31
  .fwd83:
  ori x12, x1, 31
  xori x8, x8, 4294901760
  srai x13, x6, 4
  lb x6, 916(x28)
  srai x5, x13, 17
.blk160:
  ame.ld.w x23
  ame.ld.x x25
  sra x2, x8, x4
  sltiu x2, x7, 305419896
  sb x5, 12(x28)
  csrr x4, mscratch
  sub x13, x8, x5
  bne x13, x10, .fwd84
  addi x5, x15, 255
  ori x2, x6, 65535
  .fwd84:
  ori x5, x15, 2147483647
.blk161:
  srl x1, x12, x10
  ame.ld.w x22
  ame.ld.x x24
  ame.exef x24
  ame.sync
  sub x10, x11, x11
  sltiu x14, x1, -344865
  ame.sync
  li x27, 14
  ame.st.y x27, x14
  sra x12, x11, x5
  lbu x3, 620(x28)
  ame.ld.w x23
  ame.ld.x x25
  ame.exef x26
  ame.sync
.blk162:
  lh x11, 172(x28)
  ame.ld.w x23
  ame.ld.x x25
  lh x2, 276(x28)
  blt x7, x8, .blk163
  blt x6, x6, .fwd85
  .fwd85:
  remu x4, x4, x4
.blk163:
  ame.ld.w x22
  ame.ld.x x25
  addi x4, x1, -1
  lh x6, 728(x28)
.blk164:
  and x5, x7, x7
  slti x9, x13, 0
  bltu x4, x7, .fwd86
  srli x11, x8, 19
  slli x15, x2, 27
  .fwd86:
  bltu x15, x12, .fwd87
  srai x3, x8, 31
  .fwd87:
.blk165:
  ame.ld.w x22
  ame.ld.x x24
  ame.exef x24
  ame.sync
  blt x6, x2, .blk166
  csrr x7, minstret
  slti x10, x10, -2147483648
  sh x4, 536(x28)
.blk166:
  addi x1, x4, 4294901760
  add x3, x10, x13
  sw x14, 436(x28)
  lh x4, 888(x28)
  or x2, x1, x2
.blk167:
  sltu x4, x2, x13
  sh x3, 124(x28)
  sw x13, 404(x28)
  mul x7, x1, x15
  addi x14, x4, -1
  sb x9, 304(x28)
  addi x7, x8, 65535
  xori x9, x8, 255
.blk168:
  addi x6, x12, 2863311530
  ame.ld.w x22
  ame.ld.x x24
  ame.exe x24
  ame.sync
  slti x4, x15, 1431655765
  sll x12, x7, x6
  sltu x9, x8, x13
  ame.ld.w x23
  ame.ld.x x25
  ame.exef x26
  ame.sync
  xori x7, x12, -2147483648
.blk169:
  ame.ld.w x22
  ame.ld.x x24
  ame.exef x24
  ame.sync
  xor x1, x4, x14
  ame.ld.w x22
  ame.ld.x x24
  ame.exef x24
  ame.sync
  bge x3, x6, .fwd88
  sltiu x8, x7, 1431655765
  .fwd88:
  sltiu x8, x5, 0
.blk170:
  lhu x13, 136(x28)
  bgeu x9, x2, .blk171
  slli x15, x5, 21
  sw x11, 444(x28)
.blk171:
  slti x3, x1, -2
  xori x7, x10, 1431655765
  sh x14, 836(x28)
.blk172:
  sh x6, 84(x28)
  beq x5, x3, .fwd89
  .fwd89:
  and x14, x7, x3
  divu x14, x10, x13
  and x15, x13, x13
  sub x9, x7, x6
.blk173:
  sb x11, 288(x28)
  ame.ld.w x22
  ame.ld.x x24
  ame.exe x24
  ame.sync
  sb x13, 436(x28)
  lw x4, 928(x28)
  srai x14, x5, 29
  xori x12, x12, 4294901760
  csrr x1, minstret
.blk174:
  xori x8, x14, 0
  addi x6, x4, 1431655765
  mulh x7, x7, x7
  andi x1, x14, 4294901760
  csrr x11, flags
  slti x11, x7, -2
.blk175:
  add x6, x3, x1
  xor x1, x14, x3
  blt x7, x4, .fwd90
  xori x14, x15, 65535
  .fwd90:
.blk176:
  srl x1, x8, x7
  ame.sync
  li x27, 2
  ame.st.q x27, x7
  and x9, x2, x15
  sb x14, 112(x28)
  slti x7, x15, 65535
.blk177:
  mulh x5, x9, x7
  sw x5, 564(x28)
  srai x13, x5, 20
  ame.ld.w x23
  ame.ld.x x25
  ame.exe x26
  ame.sync
  srl x3, x11, x15
  sb x9, 120(x28)
  srli x15, x12, 21
.blk178:
  srl x12, x6, x7
  bge x10, x14, .fwd91
  slli x4, x2, 11
  .fwd91:
  sw x13, 896(x28)
  andi x9, x14, -2
  sh x2, 184(x28)
  div x10, x1, x9
.blk179:
  sw x4, 972(x28)
  ame.sync
  li x27, 8
  ame.st.q x27, x3
  sltu x3, x1, x13
  or x5, x11, x2
  sll x14, x5, x15
  sw x4, 96(x28)
  mulhsu x5, x6, x2
  bge x12, x8, .blk180
.blk180:
  mulhu x7, x15, x8
  srai x13, x4, 22
  and x13, x6, x6
  ame.ld.w x22
  ame.ld.x x24
  ame.exe x24
  ame.sync
  bne x12, x5, .fwd92
  .fwd92:
  slti x13, x13, 2863311530
  or x14, x13, x4
  bgeu x2, x14, .fwd93
  slti x7, x15, -2
  .fwd93:
.blk181:
  mul x1, x15, x9
  sra x15, x5, x1
  lh x5, 748(x28)
.blk182:
  srl x11, x12, x14
  ame.ld.w x23
  ame.ld.x x25
  ame.exe x26
  ame.sync
  sltu x9, x11, x4
  sra x12, x9, x10
  or x7, x12, x2
  bge x6, x1, .blk183
  bne x9, x6, .blk183
.blk183:
  sra x1, x6, x2
  sub x4, x6, x3
  or x10, x13, x8
  sra x2, x7, x6
  ame.sync
  li x27, 7
  ame.st.q x27, x1
  slt x10, x3, x10
  andi x4, x6, 305419896
.blk184:
  srai x7, x4, 6
  slti x10, x9, -2147483648
  addi x12, x8, 0
  slti x10, x13, 1431655765
  slli x14, x13, 22
  srai x6, x11, 19
  slt x4, x4, x8
.blk185:
  lw x12, 820(x28)
  srli x3, x12, 1
  lb x3, 976(x28)
  slli x2, x4, 7
  sltu x6, x14, x1
  bgeu x6, x12, .fwd94
  .fwd94:
.blk186:
  srli x5, x15, 20
  rem x10, x11, x8
  sw x5, 728(x28)
  sub x15, x14, x15
  lhu x10, 284(x28)
  lhu x8, 548(x28)
  lb x12, 164(x28)
  csrr x5, minstret
.blk187:
  sll x3, x8, x6
  ori x9, x4, -1
  divu x2, x3, x1
  andi x5, x9, 255
.blk188:
  and x5, x13, x9
  sra x13, x7, x1
  ame.ld.w x22
  ame.ld.x x25
.blk189:
  blt x7, x2, .fwd95
  .fwd95:
  csrr x15, flags
  blt x15, x15, .fwd96
  sltiu x12, x2, -1
  ori x8, x8, 2863311530
  .fwd96:
.blk190:
  and x9, x3, x2
  sltiu x2, x6, 2147483647
  srl x13, x7, x11
  sll x13, x15, x1
  sw x14, 308(x28)
  lh x3, 12(x28)
.blk191:
  mul x7, x9, x13
  bgeu x11, x10, .fwd97
  xori x8, x4, -1
  .fwd97:
  ori x13, x4, 2863311530
  sltu x4, x5, x11
  rem x15, x10, x6
  or x10, x5, x12
.blk192:
  xori x7, x1, 0
  ame.ld.w x23
  ame.ld.x x25
  ame.exe x26
  ame.sync
  sll x10, x10, x4
  addi x8, x1, 0
  and x3, x12, x6
  and x9, x11, x6
  slti x3, x11, -344865
  bgeu x9, x5, .fwd98
  .fwd98:
.blk193:
  xor x3, x14, x6
  andi x11, x12, 2
  srli x7, x12, 27
  andi x9, x7, 65535
.blk194:
  slli x15, x5, 19
  slt x13, x13, x15
  slt x10, x9, x6
.blk195:
  bgeu x10, x8, .fwd99
  .fwd99:
  sltiu x14, x13, -2147483648
  mul x13, x14, x14
  lw x4, 340(x28)
  sltiu x5, x4, 1431655765
  or x4, x10, x14
  beq x12, x11, .fwd100
  .fwd100:
  sh x10, 712(x28)
.blk196:
  lw x14, 436(x28)
  sw x1, 520(x28)
  lbu x15, 8(x28)
.blk197:
  csrr x2, flags
  bne x9, x1, .fwd101
  addi x13, x11, 4294901760
  .fwd101:
  and x4, x14, x8
  sw x11, 948(x28)
  sh x4, 172(x28)
  slli x15, x11, 20
  lb x1, 520(x28)
  add x7, x1, x6
.blk198:
  srl x14, x8, x7
  sub x5, x5, x5
  srli x14, x7, 26
  srai x13, x14, 23
  rem x13, x14, x3
  lw x7, 428(x28)
  lw x2, 800(x28)
  lb x11, 660(x28)
.blk199:
  xori x10, x8, 4294901760
  sw x5, 56(x28)
  sh x11, 448(x28)
  and x5, x4, x15
.blk200:
  sb x6, 452(x28)
  bge x14, x7, .blk201
  ame.ld.w x22
  ame.ld.x x24
  ame.exe x24
  ame.sync
  bge x3, x12, .fwd102
  addi x7, x14, 305419896
  .fwd102:
  sw x7, 192(x28)
  sb x9, 672(x28)
  ame.ld.w x22
  ame.ld.x x24
  ame.exe x24
  ame.sync
  ame.ld.w x23
  ame.ld.x x25
  ame.exef x26
  ame.sync
.blk201:
  blt x1, x6, .fwd103
  .fwd103:
  srl x4, x13, x1
  ame.ld.w x23
  ame.ld.x x25
  ame.exef x26
  ame.sync
  or x10, x4, x1
  srai x14, x3, 19
.blk202:
  sltiu x12, x10, 1431655765
  ame.ld.w x22
  ame.ld.x x25
  rem x1, x7, x14
  sw x14, 728(x28)
.blk203:
  ori x8, x15, 4294901760
  lh x4, 528(x28)
  xori x9, x11, 0
  sh x9, 584(x28)
.blk204:
  mulhsu x9, x14, x4
  sb x14, 632(x28)
  sw x3, 0(x28)
  ame.sync
  li x27, 1
  ame.st.y x27, x13
  beq x13, x2, .fwd104
  .fwd104:
  sra x14, x9, x11
.blk205:
  mulh x7, x8, x11
  ame.sync
  li x27, 11
  ame.st.q x27, x15
  mulh x15, x7, x5
  sw x6, 936(x28)
  andi x8, x7, 128
  bge x14, x6, .blk206
  sll x15, x11, x2
  sh x11, 168(x28)
.blk206:
  srai x9, x7, 30
  andi x6, x8, 2863311530
  srai x5, x13, 12
  sltu x2, x5, x2
.blk207:
  sh x13, 380(x28)
  lw x12, 416(x28)
  or x10, x5, x9
  andi x1, x15, -344865
  sb x11, 532(x28)
  sb x10, 744(x28)
  addi x13, x5, -2147483648
.blk208:
  bge x5, x11, .blk209
  xori x1, x2, 255
  lbu x12, 992(x28)
  xori x8, x14, 305419896
  addi x6, x14, -344865
  sb x13, 740(x28)
.blk209:
  bltu x3, x9, .blk210
  sb x8, 728(x28)
  ame.ld.w x22
  ame.ld.x x24
.blk210:
  csrr x5, flags
  bne x3, x9, .fwd105
  .fwd105:
  rem x2, x14, x7
  ame.sync
  li x27, 7
  ame.st.q x27, x10
  sra x4, x3, x9
  csrr x10, flags
  ame.ld.w x23
  ame.ld.x x25
  ame.exef x26
  ame.sync
.blk211:
  or x10, x4, x4
  addi x4, x14, -1
  sh x14, 408(x28)
  xor x11, x10, x6
  bne x14, x3, .blk212
.blk212:
  lhu x15, 724(x28)
  sb x6, 648(x28)
  or x4, x10, x14
  srli x2, x3, 5
  sb x6, 332(x28)
  ori x5, x11, -344865
  bltu x9, x11, .fwd106
  andi x6, x10, 2863311530
  srli x2, x6, 18
  .fwd106:
  lw x15, 732(x28)
.blk213:
  sw x7, 72(x28)
  slti x14, x2, 1431655765
  srl x15, x9, x13
.blk214:
  sw x12, 20(x28)
  bge x4, x14, .blk215
  xor x15, x4, x8
  xori x5, x7, 1431655765
.blk215:
  beq x15, x10, .blk216
  sra x8, x9, x8
  sltiu x15, x12, -1
.blk216:
  xori x14, x13, -344865
  ame.ld.w x22
  ame.ld.x x24
  ame.exe x24
  ame.sync
  addi x3, x6, 4294901760
  srli x5, x7, 22
  ame.sync
  li x27, 6
  ame.st.q x27, x9
.blk217:
  sh x6, 732(x28)
  ori x10, x15, -2147483648
  slli x15, x12, 12
  blt x15, x4, .fwd107
  slli x11, x2, 11
  xori x9, x14, 32
  .fwd107:
  ori x15, x8, 1
  mulh x11, x11, x15
.blk218:
  sw x4, 292(x28)
  rem x14, x15, x9
  slli x15, x9, 23
.blk219:
  beq x1, x13, .blk220
  ori x8, x12, -31
  srai x12, x9, 11
  slli x7, x6, 10
  mulhu x10, x1, x6
  sltiu x14, x2, 31
.blk220:
  srai x3, x9, 1
  xor x5, x11, x6
  or x14, x10, x1
.blk221:
  srai x7, x12, 17
  csrr x2, minstret
  lw x9, 68(x28)
  ame.sync
  li x27, 14
  ame.st.y x27, x10
.blk222:
  mulhu x2, x14, x12
  sll x8, x4, x6
  sb x6, 332(x28)
  bltu x4, x2, .fwd108
  .fwd108:
  mul x9, x7, x15
  sw x2, 424(x28)
.blk223:
  ame.sync
  li x27, 14
  ame.st.y x27, x5
  sb x6, 508(x28)
  mulh x13, x6, x14
  sll x10, x2, x4
  sltiu x14, x11, 1431655765
  sub x14, x10, x8
  xor x1, x15, x5
  xori x13, x8, -31
.blk224:
  sll x11, x8, x12
  lbu x5, 756(x28)
  mulhsu x6, x15, x13
  lw x5, 592(x28)
  bge x3, x4, .blk225
  sltiu x11, x11, 31
  sra x2, x4, x2
.blk225:
  srai x2, x13, 27
  sb x1, 464(x28)
  lw x9, 396(x28)
  sll x5, x11, x4
.blk226:
  lb x5, 64(x28)
  sra x4, x7, x6
  add x5, x7, x3
  sw x5, 896(x28)
  lw x12, 664(x28)
  ame.ld.w x23
  ame.ld.x x25
  ame.exe x26
  ame.sync
  blt x13, x13, .fwd109
  .fwd109:
.blk227:
  or x4, x11, x3
  ori x6, x1, 255
  bne x2, x1, .fwd110
  srli x13, x6, 0
  addi x9, x1, 32
  .fwd110:
.blk228:
  sh x5, 724(x28)
  sw x13, 292(x28)
  sw x1, 20(x28)
  slli x15, x15, 11
  ame.ld.w x22
  ame.ld.x x24
  ame.exe x24
  ame.sync
  ori x13, x10, -1
.blk229:
  ame.ld.w x23
  ame.ld.x x25
  ame.exe x26
  ame.sync
  srli x15, x14, 12
  xor x13, x1, x8
  sll x11, x14, x2
  sll x8, x15, x8
  slti x14, x2, 305419896
  lw x7, 652(x28)
.blk230:
  sub x7, x10, x7
  ame.ld.w x23
  ame.ld.x x25
  ame.exe x26
  ame.sync
  srli x2, x1, 15
  and x7, x15, x1
  or x10, x5, x13
  csrr x12, minstret
  lhu x10, 552(x28)
  slli x11, x1, 20
.blk231:
  sb x13, 1008(x28)
  xor x1, x13, x11
  xor x1, x11, x3
  ori x7, x4, -344865
.blk232:
  sw x7, 284(x28)
  bgeu x11, x1, .fwd111
  .fwd111:
  sw x9, 320(x28)
  slt x8, x9, x7
  ame.ld.w x23
  ame.ld.x x25
  ame.exef x26
  ame.sync
  srli x6, x6, 10
.blk233:
  or x6, x2, x6
  blt x9, x14, .fwd112
  addi x15, x5, 4294901760
  .fwd112:
  bne x7, x10, .blk234
  ame.sync
  li x27, 8
  ame.st.y x27, x14
  ame.ld.w x23
  ame.ld.x x25
  lbu x1, 388(x28)
.blk234:
  slt x5, x4, x8
  mul x14, x11, x1
  lhu x7, 492(x28)
.blk235:
  srai x2, x5, 22
  sra x9, x14, x5
  csrr x14, minstret
  sub x10, x14, x3
  sw x13, 184(x28)
  lb x10, 600(x28)
.blk236:
  lbu x9, 360(x28)
  srl x10, x9, x1
  slti x10, x8, 31
  slli x15, x4, 16
  sub x15, x1, x11
  bne x4, x4, .fwd113
  .fwd113:
  slli x11, x1, 9
  bge x9, x6, .fwd114
  .fwd114:
.blk237:
  ame.ld.w x22
  ame.ld.x x24
  ame.exef x24
  ame.sync
  ori x14, x3, -2
  sw x12, 60(x28)
  sw x8, 348(x28)
.blk238:
  sltiu x12, x5, 32
  lb x5, 648(x28)
  slt x6, x15, x4
.blk239:
  sltu x11, x2, x5
  mulhsu x1, x5, x14
  blt x13, x7, .blk240
  bne x11, x8, .fwd115
  addi x5, x8, 32
  andi x10, x4, 4294901760
  .fwd115:
.blk240:
  csrr x6, flags
  sll x7, x9, x7
  addi x6, x1, 128
  bltu x10, x6, .fwd116
  andi x15, x12, -344865
  .fwd116:
.blk241:
  or x10, x1, x2
  sra x11, x13, x7
  addi x4, x5, 1431655765
  srai x7, x12, 17
  sub x12, x13, x12
  beq x4, x3, .fwd117
  ori x12, x6, -344865
  .fwd117:
  srai x3, x15, 15
  slli x5, x9, 23
.blk242:
  bltu x8, x12, .blk243
  lh x6, 892(x28)
  add x5, x4, x8
  csrr x9, minstret
  bltu x10, x3, .blk243
.blk243:
  lw x5, 396(x28)
  sb x3, 776(x28)
  and x4, x12, x2
  bne x6, x7, .blk244
  andi x12, x10, -2
  sw x4, 232(x28)
  csrs mscratch, x2
  srli x14, x1, 26
.blk244:
  add x8, x4, x3
  blt x9, x14, .fwd118
  slti x11, x5, 1431655765
  srai x11, x1, 28
  .fwd118:
  sltiu x9, x10, 2
  xor x1, x10, x10
  sll x5, x9, x8
  xor x3, x10, x4
.blk245:
  sub x2, x14, x3
  andi x8, x1, 65535
  add x11, x1, x12
  and x13, x1, x14
  slli x6, x11, 26
.blk246:
  sub x13, x7, x14
  lw x1, 436(x28)
  andi x15, x14, 65535
  bgeu x3, x8, .fwd119
  slti x9, x2, 32
  .fwd119:
  slt x2, x7, x14
  srli x14, x1, 31
  lb x13, 280(x28)
  ame.sync
  li x27, 0
  ame.st.y x27, x1
.blk247:
  srl x3, x14, x10
  or x15, x6, x12
  sb x8, 292(x28)
  srai x11, x1, 4
  sw x14, 124(x28)
  csrs mscratch, x11
  slti x1, x9, 2
  bne x3, x1, .fwd120
  srli x10, x5, 28
  .fwd120:
.blk248:
  lbu x6, 660(x28)
  sh x9, 564(x28)
  sltu x7, x6, x6
.blk249:
  csrr x7, minstret
  lh x7, 460(x28)
  lhu x9, 572(x28)
.blk250:
  and x4, x1, x8
  bge x15, x6, .fwd121
  sltiu x6, x1, 2147483647
  .fwd121:
  sra x15, x5, x8
  srai x6, x2, 1
  lh x14, 868(x28)
  lh x4, 388(x28)
.blk251:
  sh x3, 304(x28)
  csrr x11, flags
  andi x11, x9, 4294901760
  xori x3, x6, 128
  blt x7, x6, .fwd122
  .fwd122:
  ame.sync
  li x27, 8
  ame.st.y x27, x12
  ame.sync
  li x27, 13
  ame.st.q x27, x11
  xori x12, x14, -2
.blk252:
  and x7, x13, x10
  srai x11, x14, 17
  ame.sync
  li x27, 11
  ame.st.q x27, x8
  lw x12, 84(x28)
  andi x4, x12, -1
  sh x13, 564(x28)
.blk253:
  rem x13, x7, x14
  sh x9, 852(x28)
  beq x7, x8, .blk254
  lw x1, 580(x28)
  ori x13, x8, -2
.blk254:
  sub x7, x6, x8
  sb x8, 564(x28)
  sw x1, 936(x28)
  sw x13, 124(x28)
.blk255:
  sw x2, 448(x28)
  sll x3, x8, x3
  ori x3, x15, -31
  addi x12, x5, -1
  slti x6, x5, 255
  bge x4, x1, .fwd123
  slti x2, x4, 4294901760
  .fwd123:
.blk256:
  sh x12, 976(x28)
  addi x14, x14, 305419896
  bne x4, x3, .fwd124
  .fwd124:
  bltu x3, x15, .fwd125
  srai x1, x11, 27
  srli x1, x7, 24
  .fwd125:
  sub x11, x15, x6
  ori x10, x3, 128
  mulhsu x4, x1, x11
  addi x10, x9, 31
.blk257:
  ame.ld.w x22
  ame.ld.x x24
  ame.exe x24
  ame.sync
  mulhu x6, x11, x13
  slt x10, x2, x13
  lw x2, 264(x28)
  ame.ld.w x22
  ame.ld.x x25
  or x2, x13, x9
  lbu x15, 608(x28)
.blk258:
  slt x10, x4, x15
  csrr x4, minstret
  add x5, x6, x2
  beq x2, x14, .fwd126
  xori x14, x5, 0
  .fwd126:
  lb x13, 928(x28)
.blk259:
  lbu x6, 644(x28)
  lhu x15, 1000(x28)
  sltiu x6, x9, 128
  and x9, x2, x12
.blk_end:
  ame.sync
  li x28, 0x1FFF0
  li x29, 0x600D
  sw x29, 0(x28)
  ebreak
