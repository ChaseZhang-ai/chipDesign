# 随机生成(cpu_gen_random.py)
  .org 0x10000
boot:
  j start
  .org 0x0
start:
  li x1, 305419896
  li x2, 1431655765
  li x3, 2
  li x4, 4294901760
  li x5, -31
  li x6, -2
  li x7, -1
  li x8, -1
  li x9, 0
  li x10, 4294901760
  li x11, 128
  li x12, 1431655765
  li x13, 1
  li x14, 305419896
  li x15, 255
  li x28, 0x4000
.blk0:
  mulh x5, x13, x3
  xor x4, x15, x1
  xor x4, x3, x5
  blt x14, x12, .fwd1
  slli x6, x11, 15
  srli x3, x4, 17
  .fwd1:
  srai x15, x14, 19
  slti x15, x5, 255
  xor x7, x7, x10
.blk1:
  lb x3, 476(x28)
  sub x14, x13, x1
  slti x8, x11, 255
  sb x11, 964(x28)
  xori x11, x4, 31
  xor x11, x11, x8
.blk2:
  divu x7, x12, x10
  blt x9, x4, .fwd2
  .fwd2:
  ame.cfg 16, 16
  li x20, 3
  li x21, 65
  ame.qcfg 0, x20, x21
  li x22, 0
  li x23, 5
  li x24, 0
  li x25, 528
  li x26, 1
  sltu x5, x13, x10
.blk3:
  ori x6, x15, 1431655765
  lb x1, 84(x28)
  ame.ld.w x22
  ame.ld.x x24
  ame.exe x24
  ame.sync
  csrr x11, flags
.blk4:
  srl x5, x6, x3
  beq x11, x14, .fwd3
  .fwd3:
  lb x5, 276(x28)
.blk5:
  bltu x3, x6, .fwd4
  .fwd4:
  lb x3, 744(x28)
  or x10, x2, x8
  lw x15, 424(x28)
  ori x1, x1, -2
  bge x1, x9, .fwd5
  srai x1, x2, 18
  .fwd5:
.blk6:
  bne x4, x8, .fwd6
  andi x8, x1, 31
  .fwd6:
  lw x4, 876(x28)
  sw x4, 64(x28)
  or x5, x4, x9
  and x7, x14, x5
  sll x1, x15, x15
.blk7:
  addi x10, x7, -31
  mulhsu x2, x7, x4
  sll x5, x11, x8
  lhu x9, 440(x28)
  ame.ld.w x23
  ame.ld.x x25
  sw x2, 572(x28)
  ori x7, x15, -344865
.blk8:
  srli x14, x3, 30
  csrr x7, mscratch
  ori x4, x15, 0
  beq x15, x5, .fwd7
  srai x15, x4, 3
  .fwd7:
  sll x3, x11, x10
  bge x13, x13, .blk9
  lw x1, 160(x28)
  ame.ld.w x22
  ame.ld.x x24
  ame.exe x24
  ame.sync
.blk9:
  add x10, x13, x3
  mul x2, x13, x15
  sub x14, x6, x14
  slli x9, x8, 13
  sra x7, x4, x13
  lw x2, 156(x28)
  blt x13, x15, .fwd8
  srli x7, x14, 4
  .fwd8:
.blk10:
  sra x11, x5, x15
  lb x2, 340(x28)
  ori x3, x12, 2863311530
  sb x14, 692(x28)
  sw x15, 8(x28)
  xori x11, x5, 128
  srli x8, x13, 4
  sb x4, 840(x28)
.blk11:
  add x13, x3, x14
  ame.ld.w x22
  ame.ld.x x24
  ame.exe x24
  ame.sync
  sb x15, 956(x28)
  sh x13, 900(x28)
  lh x3, 512(x28)
.blk12:
  ame.ld.w x22
  ame.ld.x x25
  ori x10, x3, 1431655765
  divu x4, x10, x13
  ame.ld.w x22
  ame.ld.x x24
  ame.exef x24
  ame.sync
  lb x11, 364(x28)
.blk13:
  mul x6, x3, x5
  beq x1, x9, .blk14
  srli x3, x3, 4
  srli x3, x11, 14
  bgeu x13, x14, .fwd9
  andi x7, x15, -31
  slti x12, x4, 65535
  .fwd9:
  slt x12, x6, x9
  lh x15, 816(x28)
  lb x14, 640(x28)
.blk14:
  lb x10, 24(x28)
  slt x15, x9, x8
  bge x14, x6, .blk15
  bltu x1, x3, .fwd10
  slti x15, x6, -1
  srli x13, x5, 14
  .fwd10:
  bltu x15, x8, .blk15
  xori x15, x4, 1431655765
.blk15:
  srai x3, x7, 16
  ori x9, x4, 2
  sub x1, x6, x2
  xor x1, x15, x11
.blk16:
  bgeu x12, x3, .fwd11
  xori x3, x15, 128
  .fwd11:
  mulhsu x12, x1, x12
  sw x7, 312(x28)
  srl x8, x9, x2
  slti x3, x14, 255
  lbu x9, 620(x28)
  srl x3, x7, x1
.blk17:
  xor x15, x11, x1
  xori x2, x3, 0
  sra x4, x9, x1
.blk18:
  sh x3, 924(x28)
  slt x14, x3, x14
  bge x4, x2, .fwd12
  slli x5, x15, 2
  .fwd12:
  bltu x4, x5, .blk19
  ame.ld.w x23
  ame.ld.x x25
  sltiu x15, x4, 2
  ame.ld.w x22
  ame.ld.x x24
  ame.exe x24
  ame.sync
  sw x8, 720(x28)
.blk19:
  ame.ld.w x22
  ame.ld.x x24
  ame.exe x24
  ame.sync
  sw x9, 508(x28)
  sltu x11, x2, x6
  xori x12, x5, 255
.blk20:
  andi x2, x14, -344865
  bgeu x1, x15, .blk21
  ori x8, x12, -2147483648
  divu x4, x15, x12
  sltu x14, x7, x11
  lbu x1, 352(x28)
  sb x2, 608(x28)
.blk21:
  ame.sync
  li x27, 10
  ame.st.y x27, x4
  slli x8, x15, 17
  srl x13, x15, x7
  xor x13, x10, x4
.blk22:
  sh x2, 60(x28)
  and x10, x5, x11
  beq x13, x6, .blk23
  andi x10, x2, -344865
  ame.ld.w x23
  ame.ld.x x25
  ame.exe x26
  ame.sync
.blk23:
  bge x6, x1, .fwd13
  .fwd13:
  srai x2, x4, 6
  slti x13, x6, -2
.blk24:
  ori x11, x14, 0
  add x11, x4, x5
  blt x6, x11, .blk25
  bne x14, x6, .fwd14
  .fwd14:
  addi x1, x3, -344865
  ame.sync
  li x27, 3
  ame.st.y x27, x13
  srai x7, x8, 31
  sh x6, 740(x28)
.blk25:
  lw x14, 72(x28)
  xor x3, x6, x4
  or x6, x10, x14
  bge x11, x6, .fwd15
  andi x2, x4, 65535
  andi x3, x9, 0
  .fwd15:
  slti x2, x4, 2863311530
  sb x8, 84(x28)
  csrr x13, mscratch
  srli x7, x10, 22
.blk26:
  ori x8, x12, 32
  slli x12, x13, 13
  srai x6, x5, 3
  srai x8, x3, 3
  sltu x14, x10, x4
.blk27:
  bgeu x1, x12, .fwd16
  ori x4, x13, 1
  .fwd16:
  slti x3, x10, 305419896
  lh x12, 640(x28)
  bgeu x6, x3, .fwd17
  sltiu x14, x9, -344865
  srai x10, x6, 2
  .fwd17:
  sw x3, 748(x28)
.blk28:
  sw x14, 244(x28)
  bne x10, x4, .fwd18
  addi x3, x10, 128
  xori x14, x6, 1
  .fwd18:
  bne x3, x9, .fwd19
  .fwd19:
  xor x8, x15, x14
  xor x11, x8, x13
  sw x12, 124(x28)
.blk29:
  lb x1, 4(x28)
  sw x10, 736(x28)
  srl x7, x11, x2
  andi x5, x4, 2147483647
  sub x12, x15, x12
.blk30:
  slti x15, x1, 255
  sw x9, 868(x28)
  sltiu x9, x11, 2147483647
.blk31:
  add x9, x12, x9
  ame.ld.w x22
  ame.ld.x x24
  ame.exef x24
  ame.sync
  xori x7, x3, 255
  xor x9, x6, x11
  xori x10, x10, -1
  beq x1, x3, .blk32
  sb x11, 868(x28)
  bne x6, x13, .fwd20
  srli x8, x4, 10
  srai x8, x11, 1
  .fwd20:
.blk32:
  blt x10, x4, .blk33
  ame.sync
  li x27, 10
  ame.st.y x27, x5
  sltiu x6, x5, -2147483648
  sb x8, 596(x28)
  divu x14, x11, x3
  sltiu x14, x4, -2147483648
  add x8, x2, x5
.blk33:
  addi x1, x14, 128
  sll x4, x15, x4
  bne x7, x7, .fwd21
  srai x7, x5, 5
  addi x6, x13, 2
  .fwd21:
  srl x1, x7, x1
  addi x7, x11, 128
  sll x6, x6, x9
  ame.ld.w x23
  ame.ld.x x25
  ame.exef x26
  ame.sync
.blk34:
  mulhu x2, x13, x7
  sw x6, 884(x28)
  lbu x3, 176(x28)
  mul x9, x4, x13
  ori x5, x2, -2
.blk35:
  lbu x12, 712(x28)
  srl x7, x11, x5
  csrr x2, flags
  remu x9, x14, x2
  lw x12, 752(x28)
  bne x14, x10, .blk36
.blk36:
  addi x6, x9, 255
  bgeu x14, x11, .fwd22
  .fwd22:
  sh x4, 724(x28)
  lbu x7, 252(x28)
  slli x14, x12, 22
.blk37:
  csrr x12, flags
  and x3, x6, x6
  sra x9, x12, x10
  bge x13, x3, .blk38
  csrr x8, flags
  beq x9, x14, .blk38
.blk38:
  lhu x5, 380(x28)
  sh x3, 36(x28)
  ame.ld.w x22
  ame.ld.x x24
  sltiu x14, x4, -2
  sra x14, x6, x14
  beq x4, x5, .fwd23
  .fwd23:
  lw x2, 496(x28)
  sw x13, 128(x28)
.blk39:
  slt x1, x14, x4
  sra x4, x1, x9
  srl x6, x5, x10
  blt x3, x12, .fwd24
  slti x2, x10, -344865
  sltiu x2, x1, 1
  .fwd24:
.blk40:
  andi x4, x12, 1
  sb x12, 792(x28)
  xori x14, x13, -2
  csrc mscratch, x15
  csrc mscratch, x7
  addi x3, x3, 2147483647
.blk41:
  lbu x9, 964(x28)
  div x10, x7, x4
  srl x10, x1, x5
  ame.ld.w x23
  ame.ld.x x24
  andi x9, x13, 2147483647
  ame.sync
  li x27, 4
  ame.st.y x27, x10
  slt x9, x15, x2
  csrr x2, flags
.blk42:
  xori x9, x8, 255
  andi x5, x5, -2147483648
  slli x13, x5, 17
.blk43:
  sll x1, x2, x7
  bgeu x13, x3, .fwd25
  andi x6, x12, -31
  ori x4, x3, 2863311530
  .fwd25:
  csrr x1, minstret
  slt x12, x9, x8
  sll x3, x10, x3
  bgeu x9, x7, .fwd26
  xori x15, x12, 32
  .fwd26:
  sw x5, 532(x28)
.blk44:
  ame.ld.w x23
  ame.ld.x x25
  ame.sync
  li x27, 2
  ame.st.q x27, x6
  csrr x9, minstret
.blk45:
  srl x10, x1, x3
  sh x15, 360(x28)
  sb x3, 64(x28)
  slt x11, x4, x7
  srli x4, x8, 19
  mulhu x5, x6, x7
  ame.ld.w x22
  ame.ld.x x24
  ame.exef x24
  ame.sync
.blk46:
  add x12, x14, x14
  sb x8, 680(x28)
  addi x3, x6, 4294901760
  lw x13, 760(x28)
  mul x8, x6, x7
  remu x12, x3, x3
  lhu x5, 344(x28)
.blk47:
  lb x9, 740(x28)
  bne x2, x13, .fwd27
  ori x15, x9, -1
  srai x8, x11, 2
  .fwd27:
  ame.ld.w x22
  ame.ld.x x24
  lbu x7, 552(x28)
  addi x14, x15, 2
  slti x15, x7, 128
  lhu x15, 148(x28)
  sra x5, x9, x12
.blk48:
  slti x14, x6, -344865
  sltu x7, x6, x1
  blt x3, x7, .fwd28
  .fwd28:
  bge x2, x2, .blk49
.blk49:
  lbu x15, 252(x28)
  lh x13, 956(x28)
  bne x8, x10, .fwd29
  slti x9, x3, 65535
  .fwd29:
  sra x11, x11, x2
  ame.ld.w x23
  ame.ld.x x25
  ame.exe x26
  ame.sync
.blk50:
  ame.sync
  li x27, 8
  ame.st.q x27, x13
  sb x6, 124(x28)
  bltu x8, x6, .blk51
  divu x3, x4, x4
  bge x2, x5, .blk51
  and x11, x7, x9
  bne x12, x7, .blk51
  and x13, x6, x12
.blk51:
  lbu x4, 412(x28)
  ori x11, x8, -1
  sll x10, x1, x3
  lhu x6, 748(x28)
  srai x2, x10, 3
.blk52:
  divu x3, x12, x6
  srai x6, x9, 6
  bgeu x15, x8, .fwd30
  ori x12, x8, -2
  sltiu x12, x11, 31
  .fwd30:
  slti x14, x9, 32
  bgeu x13, x14, .fwd31
  ori x3, x15, 305419896
  srli x12, x15, 12
  .fwd31:
  bltu x7, x3, .fwd32
  .fwd32:
.blk53:
  and x10, x13, x6
  sb x11, 464(x28)
  ame.sync
  li x27, 3
  ame.st.y x27, x6
  sh x5, 348(x28)
  andi x12, x5, 2147483647
  bgeu x2, x9, .fwd33
  ori x2, x1, -2
  .fwd33:
  bne x14, x2, .fwd34
  .fwd34:
.blk54:
  ame.ld.w x23
  ame.ld.x x25
  lhu x8, 304(x28)
  slti x9, x6, -344865
.blk55:
  bltu x5, x1, .fwd35
  addi x11, x5, 255
  .fwd35:
  mul x2, x12, x5
  csrc mscratch, x9
  srli x8, x7, 30
  bgeu x14, x14, .fwd36
  andi x1, x9, 2147483647
  slti x7, x10, 65535
  .fwd36:
  sb x12, 64(x28)
  srai x7, x4, 26
  rem x2, x15, x4
.blk56:
  ame.ld.w x23
  ame.ld.x x25
  ame.exe x26
  ame.sync
  xori x3, x14, -1
  csrr x8, minstret
  lw x10, 200(x28)
  and x10, x9, x3
.blk57:
  slti x5, x3, -2147483648
  sltu x2, x13, x14
  ame.ld.w x22
  ame.ld.x x24
  ame.exe x24
  ame.sync
  lh x8, 584(x28)
.blk58:
  sra x2, x7, x8
  bltu x13, x13, .fwd37
  sltiu x5, x12, -2147483648
  .fwd37:
  or x4, x14, x8
  csrr x9, minstret
  sw x6, 884(x28)
  div x8, x4, x13
.blk59:
  sw x1, 308(x28)
  sb x9, 112(x28)
  lh x11, 812(x28)
  bltu x1, x12, .fwd38
  .fwd38:
.blk60:
  and x7, x4, x3
  slti x8, x13, -2
  ori x13, x14, 255
.blk61:
  rem x12, x11, x10
  srl x13, x1, x6
  xor x15, x14, x7
  ori x7, x14, 1431655765
.blk62:
  slti x4, x2, 4294901760
  lw x13, 556(x28)
  xor x6, x12, x2
.blk63:
  csrr x15, minstret
  sll x8, x11, x8
  sh x13, 456(x28)
  csrr x11, flags
  ame.sync
  li x27, 15
  ame.st.q x27, x2
  lw x7, 52(x28)
  srai x14, x8, 22
.blk64:
  slli x10, x10, 14
  or x6, x8, x9
  sll x7, x2, x3
  xor x14, x9, x4
  slli x3, x5, 30
.blk65:
  addi x14, x11, 2
  slli x9, x2, 5
  ame.ld.w x23
  ame.ld.x x25
  ame.exef x26
  ame.sync
  and x7, x2, x12
.blk66:
  ame.ld.w x23
  ame.ld.x x25
  ame.exe x26
  ame.sync
  slti x10, x8, 31
  sltu x8, x3, x14
  ame.sync
  li x27, 15
  ame.st.y x27, x12
  sltu x13, x5, x5
.blk67:
  beq x3, x2, .blk68
  ame.ld.w x22
  ame.ld.x x24
  lbu x13, 288(x28)
  lh x11, 832(x28)
  sra x2, x6, x3
  ame.sync
  li x27, 4
  ame.st.y x27, x4
.blk68:
  lhu x4, 776(x28)
  sub x14, x5, x13
  addi x6, x8, 1
.blk69:
  sw x8, 876(x28)
  bge x12, x3, .blk70
  ame.ld.w x23
  ame.ld.x x25
  bge x11, x10, .fwd39
  slli x11, x12, 10
  .fwd39:
  ame.ld.w x23
  ame.ld.x x25
  ame.exef x26
  ame.sync
.blk70:
  lh x3, 716(x28)
  ame.ld.w x22
  ame.ld.x x25
  sltiu x9, x14, 255
  lhu x12, 404(x28)
.blk71:
  mulhsu x9, x5, x10
  srai x14, x7, 8
  xori x14, x14, 2863311530
  add x1, x13, x8
  sb x5, 980(x28)
  lw x9, 908(x28)
  ori x12, x1, 305419896
.blk72:
  bge x4, x3, .fwd40
  .fwd40:
  sltu x5, x5, x4
  srai x11, x10, 13
  bltu x9, x4, .fwd41
  .fwd41:
  add x6, x4, x10
.blk73:
  and x13, x10, x6
  blt x3, x7, .fwd42
  .fwd42:
  sb x15, 932(x28)
  ame.ld.w x23
  ame.ld.x x25
  ame.exe x26
  ame.sync
  or x6, x11, x1
  sll x9, x3, x14
  andi x15, x10, 0
  ori x1, x13, 32
.blk74:
  mulhsu x12, x3, x11
  sw x1, 884(x28)
  csrr x11, flags
  and x6, x13, x1
  ame.sync
  li x27, 3
  ame.st.y x27, x9
.blk75:
  or x14, x14, x4
  addi x4, x10, -31
  bge x1, x6, .fwd43
  slli x11, x1, 24
  .fwd43:
  csrr x9, minstret
.blk76:
  srl x13, x3, x3
  sh x2, 892(x28)
  ame.sync
  li x27, 4
  ame.st.q x27, x9
  sll x4, x5, x2
  ame.ld.w x22
  ame.ld.x x24
  ame.exe x24
  ame.sync
.blk77:
  sw x14, 256(x28)
  mulhsu x14, x6, x6
  ame.ld.w x23
  ame.ld.x x25
  sltu x10, x5, x1
.blk78:
  andi x11, x9, 305419896
  lh x4, 292(x28)
  srl x14, x12, x3
  and x2, x5, x3
  beq x15, x3, .blk79
  lw x1, 420(x28)
  ame.ld.w x23
  ame.ld.x x25
  ame.exef x26
  ame.sync
  divu x6, x3, x5
.blk79:
  addi x15, x5, -2
  ame.ld.w x22
  ame.ld.x x25
  srai x12, x10, 16
  ame.ld.w x22
  ame.ld.x x24
  ame.exe x24
  ame.sync
  or x7, x3, x3
  bge x6, x8, .fwd44
  slli x4, x7, 25
  slli x1, x3, 30
  .fwd44:
  sw x8, 704(x28)
.blk80:
  ori x3, x8, -344865
  xori x13, x15, -2
  ame.ld.w x23
  ame.ld.x x25
  ame.exe x26
  ame.sync
  sh x5, 284(x28)
  sll x10, x3, x15
  beq x15, x10, .fwd45
  .fwd45:
  blt x4, x11, .fwd46
  ori x14, x12, 255
  sltiu x4, x10, 0
  .fwd46:
.blk81:
  sltiu x10, x13, 2863311530
  sw x14, 20(x28)
  slt x6, x10, x7
  lh x15, 160(x28)
  addi x12, x3, 2147483647
  bge x10, x6, .fwd47
  srai x5, x6, 9
  slli x5, x3, 6
  .fwd47:
  andi x11, x13, -1
.blk82:
  srai x1, x6, 0
  or x2, x3, x11
  sub x1, x4, x13
  addi x12, x14, -2
  sw x13, 688(x28)
  bge x14, x7, .fwd48
  ori x6, x1, 255
  slti x5, x15, 1
  .fwd48:
  blt x5, x5, .fwd49
  andi x8, x6, 1
  .fwd49:
.blk83:
  srli x4, x5, 12
  ame.ld.w x23
  ame.ld.x x24
  lb x6, 692(x28)
  srai x2, x14, 14
  mulh x15, x11, x8
  sra x5, x10, x6
.blk84:
  ame.sync
  li x27, 13
  ame.st.q x27, x8
  ame.ld.w x23
  ame.ld.x x24
  lw x2, 644(x28)
  andi x7, x6, 255
  csrs mscratch, x7
  csrr x13, flags
.blk85:
  slt x1, x14, x13
  xor x5, x6, x11
  xori x2, x14, 2
  srai x15, x6, 7
  sltu x5, x7, x14
  ame.ld.w x23
  ame.ld.x x25
  ame.exef x26
  ame.sync
  csrr x10, minstret
.blk86:
  csrr x4, minstret
  bne x1, x8, .fwd50
  .fwd50:
  mulh x5, x10, x5
  sltiu x4, x10, 32
  bge x5, x13, .fwd51
  .fwd51:
.blk87:
  lw x3, 632(x28)
  bltu x7, x6, .blk88
  bge x1, x3, .fwd52
  srli x9, x8, 24
  .fwd52:
  srai x1, x13, 28
  ame.ld.w x23
  ame.ld.x x25
  ame.exe x26
  ame.sync
  bgeu x12, x6, .fwd53
  slti x13, x1, 1431655765
  addi x15, x6, 0
  .fwd53:
  addi x12, x10, -344865
  mulhsu x10, x14, x11
.blk88:
  add x3, x15, x9
  slli x1, x12, 4
  bge x8, x7, .blk89
.blk89:
  ame.ld.w x22
  ame.ld.x x24
  ame.exef x24
  ame.sync
  bltu x4, x10, .fwd54
  .fwd54:
  lw x11, 176(x28)
.blk90:
  blt x14, x8, .fwd55
  .fwd55:
  ame.ld.w x22
  ame.ld.x x24
  ame.exef x24
  ame.sync
  bltu x11, x12, .fwd56
  srai x12, x6, 21
  ori x5, x1, 305419896
  .fwd56:
  sh x14, 788(x28)
  addi x9, x5, 4294901760
  xori x13, x3, 0
  slt x11, x10, x1
  andi x15, x1, 1431655765
.blk91:
  sub x3, x12, x12
  lh x1, 528(x28)
  sw x5, 160(x28)
  sb x8, 352(x28)
.blk92:
  blt x2, x3, .blk93
  srai x2, x11, 5
  sub x13, x2, x11
  bgeu x7, x11, .fwd57
  slli x12, x12, 4
  slti x1, x13, 305419896
  .fwd57:
  lb x10, 232(x28)
.blk93:
  lw x14, 576(x28)
  sh x6, 840(x28)
  and x12, x15, x15
  lh x9, 476(x28)
  sw x4, 280(x28)
  add x12, x1, x10
.blk94:
  csrr x2, minstret
  sra x13, x9, x4
  sltu x15, x4, x4
.blk95:
  lb x6, 940(x28)
  ame.sync
  li x27, 11
  ame.st.y x27, x1
  slli x5, x12, 7
  sh x1, 956(x28)
  rem x6, x10, x15
.blk96:
  sra x3, x2, x5
  add x7, x1, x2
  ame.ld.w x22
  ame.ld.x x24
  ame.exef x24
  ame.sync
  ame.ld.w x23
  ame.ld.x x25
  ame.exe x26
  ame.sync
  blt x11, x11, .blk97
.blk97:
  bgeu x3, x14, .fwd58
  xori x3, x6, 305419896
  slli x13, x1, 27
  .fwd58:
  srl x2, x6, x1
  ame.ld.w x22
  ame.ld.x x24
  ame.exef x24
  ame.sync
  lw x12, 560(x28)
  xori x6, x5, -2
  beq x15, x4, .fwd59
  .fwd59:
  ame.sync
  li x27, 3
  ame.st.y x27, x7
.blk98:
  sltiu x14, x11, -2147483648
  ame.ld.w x23
  ame.ld.x x25
  ame.exef x26
  ame.sync
  add x8, x14, x2
  addi x6, x12, 128
.blk99:
  csrr x3, flags
  slti x8, x3, 255
  srai x12, x15, 24
  mul x3, x6, x1
  bne x15, x1, .fwd60
  sltiu x5, x15, 32
  srli x6, x6, 21
  .fwd60:
.blk100:
  slli x13, x13, 27
  ame.ld.w x23
  ame.ld.x x25
  ame.exe x26
  ame.sync
  xor x6, x8, x10
  sw x6, 152(x28)
  sltiu x10, x9, 2863311530
  slti x13, x4, 31
  ori x1, x2, 255
  csrr x7, minstret
.blk101:
  sub x14, x6, x15
  sw x9, 456(x28)
  lw x15, 200(x28)
  or x10, x5, x10
  srai x15, x12, 30
.blk102:
  sub x9, x13, x13
  sub x14, x11, x4
  and x7, x11, x12
  ame.sync
  li x27, 13
  ame.st.y x27, x8
  slt x9, x7, x14
  srli x14, x6, 4
  srli x14, x15, 27
  divu x3, x10, x10
.blk103:
  blt x1, x12, .fwd61
  slti x13, x6, 1
  .fwd61:
  lw x5, 124(x28)
  sltiu x7, x1, 2863311530
  sw x4, 640(x28)
  srl x15, x7, x9
  bgeu x9, x4, .blk104
.blk104:
  sw x2, 392(x28)
  addi x2, x4, 4294901760
  srli x13, x13, 25
.blk105:
  slt x6, x5, x2
  lw x8, 856(x28)
  ame.sync
  li x27, 15
  ame.st.q x27, x2
  sh x12, 660(x28)
  sw x11, 640(x28)
  ori x11, x3, -2
.blk106:
  sw x12, 724(x28)
  ame.ld.w x22
  ame.ld.x x24
  ame.exe x24
  ame.sync
  xori x7, x7, 1
  slt x15, x9, x4
  lw x14, 176(x28)
.blk107:
  xor x15, x4, x6
  bltu x13, x6, .fwd62
  andi x8, x11, 1431655765
  .fwd62:
  and x1, x4, x7
  sb x5, 808(x28)
.blk108:
  sltiu x7, x7, -2147483648
  sra x11, x14, x7
  slti x10, x12, 0
  bgeu x6, x11, .blk109
  sll x2, x12, x13
  slt x5, x6, x6
  lhu x14, 540(x28)
.blk109:
  ame.sync
  li x27, 7
  ame.st.q x27, x12
  mulhsu x14, x14, x15
  lhu x8, 608(x28)
  bne x4, x10, .fwd63
  srai x2, x10, 19
  .fwd63:
  sw x4, 988(x28)
  bgeu x3, x14, .fwd64
  .fwd64:
  bltu x8, x15, .blk110
  ame.ld.w x22
  ame.ld.x x24
  ame.exef x24
  ame.sync
.blk110:
  srl x7, x9, x15
  addi x13, x15, 1431655765
  csrr x3, flags
.blk111:
  slt x10, x5, x3
  lbu x10, 216(x28)
  sll x8, x14, x6
  sw x14, 788(x28)
  sh x4, 616(x28)
.blk112:
  lhu x4, 516(x28)
  sw x4, 244(x28)
  add x6, x8, x9
  lh x7, 328(x28)
.blk113:
  lb x10, 196(x28)
  sw x9, 404(x28)
  csrr x12, minstret
  addi x7, x15, 2147483647
  sltu x12, x5, x8
.blk114:
  csrr x2, flags
  sw x5, 852(x28)
  lw x5, 184(x28)
  slt x6, x8, x12
  sw x7, 488(x28)
.blk115:
  sh x5, 360(x28)
  slti x4, x12, 4294901760
  sb x8, 752(x28)
  slli x4, x10, 27
  lb x4, 148(x28)
  sw x15, 1016(x28)
  lhu x9, 996(x28)
.blk116:
  ori x14, x2, 31
  lw x5, 192(x28)
  csrs mscratch, x9
  srai x9, x12, 13
  ori x1, x11, -344865
  bne x10, x15, .fwd65
  .fwd65:
.blk117:
  add x12, x8, x11
  slli x2, x2, 31
  lh x13, 1004(x28)
  xor x6, x1, x5
  srai x6, x10, 28
  or x6, x13, x8
  lh x15, 116(x28)
.blk118:
  slti x8, x11, -31
  slt x5, x11, x14
  sltiu x8, x10, -2147483648
  addi x13, x13, -344865
  lw x9, 416(x28)
  and x5, x4, x11
  sra x11, x5, x12
.blk119:
  lh x13, 200(x28)
  sw x14, 256(x28)
  slti x11, x8, 305419896
  sltu x9, x10, x2
  ame.ld.w x23
  ame.ld.x x25
  ame.exe x26
  ame.sync
  bltu x6, x11, .fwd66
  .fwd66:
  ame.ld.w x22
  ame.ld.x x24
  ame.exe x24
  ame.sync
.blk120:
  bge x12, x5, .blk121
  slt x12, x12, x2
  bge x2, x14, .blk121
  andi x3, x10, 128
  sh x4, 824(x28)
  csrr x2, minstret
.blk121:
  lb x12, 12(x28)
  and x10, x11, x12
  srai x15, x12, 8
  sltiu x6, x3, -344865
.blk122:
  srli x5, x10, 16
  csrc mscratch, x7
  sltiu x4, x1, 128
.blk123:
  beq x7, x14, .fwd67
  xori x8, x11, 65535
  .fwd67:
  sb x9, 1000(x28)
  slt x5, x2, x9
  bne x9, x4, .fwd68
  sltiu x5, x10, -1
  andi x3, x15, 4294901760
  .fwd68:
.blk124:
  srai x9, x6, 3
  sb x11, 356(x28)
  srai x3, x1, 10
  slt x4, x5, x13
.blk125:
  slti x14, x10, 2863311530
  bne x3, x14, .fwd69
  .fwd69:
  bne x13, x4, .blk126
  ame.ld.w x22
  ame.ld.x x24
  ame.exe x24
  ame.sync
.blk126:
  bne x14, x15, .fwd70
  slti x2, x8, 31
  .fwd70:
  remu x13, x3, x5
  andi x13, x2, 305419896
  or x14, x15, x15
.blk127:
  xor x10, x5, x8
  or x2, x11, x10
  mulh x2, x15, x12
  sra x9, x6, x3
  csrs mscratch, x11
.blk128:
  bltu x13, x9, .fwd71
  slli x1, x4, 15
  sltiu x10, x5, 4294901760
  .fwd71:
  lh x13, 124(x28)
  sw x14, 144(x28)
  sll x12, x1, x2
  sw x1, 616(x28)
  sll x12, x14, x9
.blk129:
  srli x5, x5, 11
  or x3, x12, x1
  lw x15, 356(x28)
  add x5, x4, x3
  bltu x1, x12, .fwd72
  addi x3, x15, 128
  addi x5, x13, 32
  .fwd72:
.blk130:
  csrr x7, minstret
  csrc mscratch, x12
  and x8, x5, x4
  bne x5, x8, .fwd73
  .fwd73:
  sw x8, 220(x28)
  ori x4, x7, -2147483648
  sub x15, x7, x3
  xori x2, x8, 32
.blk131:
  bgeu x13, x1, .blk132
  mulh x13, x1, x10
  srai x2, x11, 11
  sra x4, x13, x9
  lh x2, 308(x28)
  lb x10, 920(x28)
  andi x9, x12, -2147483648
.blk132:
  slli x5, x3, 12
  lhu x6, 40(x28)
  beq x10, x4, .fwd74
  .fwd74:
  sh x3, 728(x28)
.blk133:
  ame.ld.w x22
  ame.ld.x x24
  ame.exef x24
  ame.sync
  sll x1, x2, x12
  csrr x13, flags
  addi x4, x11, 4294901760
.blk134:
  rem x6, x11, x9
  slt x1, x1, x8
  srl x11, x13, x6
  beq x2, x7, .fwd75
  .fwd75:
.blk135:
  xor x9, x10, x11
  sra x2, x2, x7
  ame.ld.w x22
  ame.ld.x x25
  sh x5, 880(x28)
  csrr x3, minstret
.blk136:
  sltu x14, x14, x2
  csrc mscratch, x1
  and x3, x1, x5
  slli x4, x8, 0
  srli x14, x1, 3
  ame.ld.w x23
  ame.ld.x x25
  ame.exe x26
  ame.sync
  srli x1, x11, 4
.blk137:
  sltu x2, x3, x15
  slt x1, x9, x6
  sub x4, x3, x7
  bne x4, x9, .fwd76
  xori x4, x8, 255
  .fwd76:
  sltiu x13, x6, 32
  lh x3, 480(x28)
.blk138:
  bne x9, x15, .fwd77
  .fwd77:
  sub x15, x5, x7
  sw x8, 132(x28)
  ame.ld.w x23
  ame.ld.x x25
  ame.exe x26
  ame.sync
  beq x3, x8, .blk139
  and x4, x7, x15
  sltiu x12, x15, 1431655765
.blk139:
  bne x12, x10, .blk140
  addi x11, x12, 1431655765
  srl x3, x11, x14
  srai x2, x15, 4
  sll x2, x7, x13
  bge x7, x9, .fwd78
  ori x12, x13, 305419896
  .fwd78:
  sw x5, 72(x28)
  csrr x4, flags
.blk140:
  sra x15, x14, x11
  ame.ld.w x23
  ame.ld.x x24
  lw x12, 664(x28)
  sltu x10, x6, x12
  addi x1, x5, 305419896
  or x14, x1, x2
  srai x7, x12, 21
.blk141:
  srli x4, x2, 4
  csrr x9, minstret
  slt x11, x13, x2
  mulhu x8, x13, x2
  ame.ld.w x22
  ame.ld.x x24
  ame.exe x24
  ame.sync
  sw x15, 56(x28)
  srli x8, x4, 20
.blk142:
  bltu x8, x4, .fwd79
  srai x8, x2, 3
  xori x14, x15, 2
  .fwd79:
  sw x8, 900(x28)
  and x15, x8, x5
  mul x3, x1, x1
.blk143:
  lbu x2, 460(x28)
  sw x1, 664(x28)
  srli x4, x4, 4
  bge x10, x2, .blk144
  sltiu x15, x7, 32
  sh x9, 856(x28)
.blk144:
  xori x14, x8, -31
  sub x8, x11, x9
  lb x12, 588(x28)
  sh x12, 636(x28)
.blk145:
  lhu x1, 80(x28)
  lbu x11, 248(x28)
  srai x15, x12, 26
  csrr x6, minstret
  slli x14, x3, 21
  add x5, x12, x6
  ame.sync
  li x27, 1
  ame.st.q x27, x3
.blk146:
  sltiu x14, x9, -31
  blt x9, x9, .fwd80
  slli x2, x9, 15
  addi x5, x15, -344865
  .fwd80:
  ame.ld.w x23
  ame.ld.x x24
  beq x5, x10, .blk147
  sltu x5, x1, x11
  ori x2, x5, 1431655765
.blk147:
  lw x6, 944(x28)
  addi x15, x2, 2147483647
  ori x12, x5, -2
  sw x8, 924(x28)
.blk148:
  sb x10, 656(x28)
  sra x15, x4, x2
  csrr x11, minstret
.blk149:
  sw x10, 644(x28)
  sub x5, x9, x7
  bne x13, x14, .fwd81
  .fwd81:
  lhu x3, 524(x28)
  sltu x12, x2, x10
  sra x15, x8, x5
.blk150:
  bgeu x2, x1, .blk151
  beq x15, x1, .fwd82
  srai x6, x7, 1
  addi x2, x6, 1
  .fwd82:
  addi x9, x8, 65535
  csrr x3, minstret
  sltu x15, x15, x5
.blk151:
  addi x8, x10, -1
  or x7, x1, x13
  lb x14, 688(x28)
  addi x8, x3, -31
.blk152:
  sw x3, 784(x28)
  xor x1, x9, x7
  lh x2, 416(x28)
  bge x2, x11, .fwd83
  sltiu x8, x3, 1431655765
  .fwd83:
  srl x3, x11, x2
.blk153:
  sw x2, 752(x28)
  slti x12, x8, -2147483648
  mul x15, x9, x13
  csrr x7, mscratch
  srl x4, x14, x14
  blt x2, x2, .fwd84
  .fwd84:
  csrr x5, flags
  srli x4, x9, 12
.blk154:
  bgeu x5, x5, .fwd85
  sltiu x10, x7, 31
  .fwd85:
  ame.sync
  li x27, 8
  ame.st.q x27, x10
  bgeu x1, x3, .blk155
  slt x3, x6, x2
  srl x3, x13, x11
  ame.ld.w x23
  ame.ld.x x25
  ame.exef x26
  ame.sync
  ame.ld.w x23
  ame.ld.x x24
.blk155:
  lhu x11, 216(x28)
  ame.sync
  li x27, 8
  ame.st.y x27, x1
  bge x9, x4, .fwd86
  andi x1, x10, 1431655765
  .fwd86:
  sltiu x4, x3, 32
  sltiu x11, x14, 1
  sll x12, x5, x11
  lbu x10, 284(x28)
.blk156:
  lbu x6, 552(x28)
  or x5, x1, x12
  ame.ld.w x22
  ame.ld.x x24
  ame.exe x24
  ame.sync
  slti x14, x8, 128
  add x1, x5, x6
  srli x7, x13, 8
  slli x5, x7, 13
  sltu x14, x6, x7
.blk157:
  sltiu x2, x8, -2147483648
  andi x5, x11, 32
  ame.ld.w x23
  ame.ld.x x25
  ame.exef x26
  ame.sync
  or x11, x11, x6
  mulhu x7, x12, x9
  lbu x3, 180(x28)
  lbu x9, 156(x28)
.blk158:
  mul x7, x12, x3
  csrr x7, flags
  srai x14, x7, 3
  csrc mscratch, x14
  csrr x14, flags
  sw x4, 668(x28)
.blk159:
  srli x6, x12, 16
  ori x14, x8, -2
  lh x9, 928(x28)
  xori x11, x6, -31
  slti x9, x15, 65535
.blk160:
  sltu x6, x14, x11
  sw x4, 476(x28)
  bltu x14, x14, .blk161
  sub x13, x5, x14
  sltiu x4, x4, 2147483647
.blk161:
  sub x13, x6, x13
  andi x2, x2, 255
  ori x7, x2, -1
  csrr x4, minstret
.blk162:
  blt x11, x12, .fwd87
  .fwd87:
  sh x9, 80(x28)
  sltiu x11, x3, -2
  srai x3, x10, 19
  slt x3, x2, x4
.blk163:
  ame.sync
  li x27, 12
  ame.st.y x27, x11
  lbu x14, 28(x28)
  ame.ld.w x23
  ame.ld.x x25
  ame.exe x26
  ame.sync
  bltu x7, x5, .blk164
.blk164:
  srl x4, x15, x6
  bge x10, x6, .fwd88
  .fwd88:
  sltu x5, x9, x5
  lhu x11, 440(x28)
  and x8, x6, x2
.blk165:
  sw x3, 992(x28)
  xor x13, x5, x11
  mul x5, x9, x1
  csrr x15, flags
  sra x5, x13, x8
  csrr x13, flags
  ame.ld.w x22
  ame.ld.x x24
  ame.exef x24
  ame.sync
.blk166:
  bne x13, x2, .fwd89
  ori x5, x2, 0
  andi x9, x8, 1431655765
  .fwd89:
  sltiu x14, x15, 65535
  xori x9, x2, 2863311530
  ame.ld.w x23
  ame.ld.x x24
  mulhsu x13, x2, x13
  sw x14, 600(x28)
  ori x6, x14, 31
.blk167:
  srli x15, x6, 21
  sll x13, x12, x3
  csrc mscratch, x14
  xori x12, x15, 1431655765
.blk168:
  sw x7, 0(x28)
  ame.ld.w x23
  ame.ld.x x25
  ame.exe x26
  ame.sync
  sra x15, x3, x5
  ame.ld.w x22
  ame.ld.x x24
  ame.exe x24
  ame.sync
.blk169:
  lbu x13, 192(x28)
  slt x9, x9, x9
  srli x5, x8, 28
.blk170:
  mulh x1, x12, x15
  slt x12, x1, x9
  sub x7, x8, x15
  csrr x2, flags
  addi x5, x14, 305419896
.blk171:
  srli x9, x4, 1
  lb x12, 364(x28)
  sb x8, 76(x28)
  blt x13, x15, .blk172
  remu x2, x7, x15
  or x9, x5, x10
.blk172:
  bne x11, x1, .fwd90
  slti x5, x7, 2863311530
  srli x10, x4, 10
  .fwd90:
  ame.sync
  li x27, 13
  ame.st.y x27, x5
  blt x12, x14, .fwd91
  andi x7, x15, 31
  .fwd91:
  add x5, x3, x7
  csrs mscratch, x1
.blk173:
  sb x2, 288(x28)
  csrr x5, mscratch
  add x9, x8, x11
  andi x8, x3, 65535
  bltu x14, x4, .blk174
  sll x11, x9, x12
  sra x2, x3, x15
.blk174:
  sw x7, 200(x28)
  sltiu x12, x15, 2147483647
  and x9, x9, x12
.blk175:
  lhu x2, 532(x28)
  sltiu x3, x4, 0
  slli x4, x13, 10
.blk176:
  mulhu x15, x12, x7
  bne x4, x9, .fwd92
  srli x3, x7, 26
  ori x8, x5, 255
  .fwd92:
  slli x14, x5, 19
  remu x5, x15, x2
  bge x13, x10, .fwd93
  xori x13, x10, 65535
  .fwd93:
  sltu x4, x14, x14
  ame.sync
  li x27, 0
  ame.st.q x27, x14
  srl x15, x5, x3
.blk177:
  ame.ld.w x23
  ame.ld.x x25
  ame.exef x26
  ame.sync
  or x5, x13, x6
  ame.ld.w x22
  ame.ld.x x24
  ame.exe x24
  ame.sync
  lhu x15, 12(x28)
  sb x15, 536(x28)
  lhu x7, 84(x28)
.blk178:
  sb x4, 320(x28)
  andi x11, x3, 0
  sb x2, 1000(x28)
  blt x3, x8, .fwd94
  addi x2, x10, 2
  ori x9, x10, -31
  .fwd94:
  bge x10, x10, .blk179
  csrs mscratch, x12
.blk179:
  sra x3, x6, x13
  ame.sync
  li x27, 9
  ame.st.q x27, x13
  srai x15, x2, 12
  sll x6, x2, x4
  xori x4, x14, 128
  andi x5, x4, -31
  csrc mscratch, x15
  div x3, x15, x15
.blk180:
  sub x7, x13, x6
  sra x9, x11, x3
  blt x2, x4, .fwd95
  andi x6, x9, 2
  sltiu x11, x9, 255
  .fwd95:
.blk181:
  ame.sync
  li x27, 14
  ame.st.q x27, x4
  sb x1, 792(x28)
  bltu x9, x6, .blk182
  sh x7, 804(x28)
.blk182:
  sra x6, x8, x3
  srli x3, x6, 20
  ame.ld.w x22
  ame.ld.x x25
  mulh x6, x5, x12
  sltu x14, x3, x11
.blk183:
  ame.ld.w x23
  ame.ld.x x25
  lbu x7, 436(x28)
  sw x8, 992(x28)
  srl x11, x3, x4
  csrc mscratch, x7
  bgeu x3, x11, .fwd96
  srli x1, x2, 25
  xori x13, x2, 0
  .fwd96:
  div x14, x8, x7
.blk184:
  slli x3, x10, 20
  addi x3, x1, 128
  sb x4, 576(x28)
  divu x10, x5, x14
  ame.ld.w x23
  ame.ld.x x25
  ame.exef x26
  ame.sync
.blk185:
  div x11, x10, x12
  mulh x9, x8, x4
  bgeu x4, x7, .blk186
  srl x14, x9, x4
  lw x9, 860(x28)
.blk186:
  slli x6, x12, 8
  blt x2, x7, .fwd97
  slti x2, x8, 31
  xori x4, x1, -2147483648
  .fwd97:
  srai x10, x11, 24
  blt x7, x10, .fwd98
  addi x15, x9, 1431655765
  slli x9, x14, 12
  .fwd98:
  bge x14, x2, .fwd99
  srli x3, x9, 7
  sltiu x14, x3, 128
  .fwd99:
  add x15, x9, x4
  mul x7, x10, x3
.blk187:
  bne x8, x1, .fwd100
  .fwd100:
  sh x2, 648(x28)
  ame.sync
  li x27, 4
  ame.st.y x27, x14
.blk188:
  bge x13, x1, .blk189
  xori x5, x13, -2147483648
  bge x9, x7, .fwd101
  addi x12, x14, 32
  srli x8, x7, 7
  .fwd101:
  lh x15, 964(x28)
  lhu x11, 700(x28)
  addi x15, x2, 1431655765
  xori x3, x15, 4294901760
.blk189:
  sll x5, x6, x13
  slli x12, x5, 30
  addi x13, x15, 4294901760
.blk190:
  srli x8, x8, 14
  mulhu x2, x7, x15
  slt x5, x4, x7
  blt x7, x15, .blk191
  divu x2, x4, x3
  sb x6, 88(x28)
  bgeu x9, x5, .fwd102
  .fwd102:
  and x1, x10, x6
.blk191:
  rem x4, x15, x11
  ame.ld.w x22
  ame.ld.x x24
  ame.exef x24
  ame.sync
  mul x3, x10, x2
  slti x15, x8, -344865
  srl x2, x1, x11
  csrs mscratch, x15
  bltu x13, x14, .fwd103
  addi x15, x9, -1
  .fwd103:
  lw x8, 748(x28)
.blk192:
  bgeu x3, x10, .fwd104
  addi x10, x3, -2
  addi x12, x15, -1
  .fwd104:
  addi x8, x11, 305419896
  xor x15, x13, x12
  xor x12, x9, x9
  lw x4, 656(x28)
  lw x3, 192(x28)
  bltu x15, x4, .fwd105
  andi x15, x15, 4294901760
  .fwd105:
.blk193:
  beq x1, x2, .fwd106
  .fwd106:
  andi x3, x15, -344865
  mulh x9, x6, x3
  srli x2, x14, 28
  lhu x10, 324(x28)
.blk194:
  sub x4, x3, x5
  lh x6, 308(x28)
  lw x7, 12(x28)
  and x13, x12, x2
  sb x1, 320(x28)
  sltu x6, x13, x15
  csrr x8, flags
.blk195:
  lw x8, 500(x28)
  slli x3, x10, 23
  lhu x11, 336(x28)
  srli x8, x1, 17
  or x2, x15, x10
  sw x12, 964(x28)
.blk196:
  sltiu x14, x10, 65535
  srai x2, x14, 4
  slti x6, x9, 128
  csrr x5, mscratch
  ame.ld.w x22
  ame.ld.x x24
  ame.exef x24
  ame.sync
.blk197:
  sltiu x2, x12, 0
  srli x1, x11, 26
  ame.ld.w x22
  ame.ld.x x25
  rem x7, x8, x5
  ame.ld.w x22
  ame.ld.x x24
  ame.exe x24
  ame.sync
  and x14, x12, x3
  remu x14, x14, x9
  sra x1, x7, x9
.blk198:
  lw x7, 200(x28)
  slli x1, x15, 3
  srli x13, x9, 7
  bge x2, x5, .fwd107
  srli x6, x15, 21
  xori x11, x5, 128
  .fwd107:
.blk199:
  lb x6, 856(x28)
  xor x2, x8, x12
  bge x11, x2, .blk200
  mulhu x13, x3, x11
  lb x15, 180(x28)
  divu x1, x8, x13
  andi x8, x13, 32
.blk200:
  xori x15, x5, 32
  sltiu x11, x7, -2
  xor x4, x9, x11
.blk201:
  addi x11, x15, -2147483648
  sh x13, 344(x28)
  ori x3, x3, 31
  lb x15, 528(x28)
  add x13, x11, x11
  slli x3, x13, 12
  sltiu x11, x3, 128
  xori x15, x10, 305419896
.blk202:
  srli x12, x14, 17
  sw x4, 272(x28)
  ame.sync
  li x27, 9
  ame.st.q x27, x7
  ori x3, x10, 128
  xori x2, x2, -2
  sra x11, x14, x5
  ame.ld.w x23
  ame.ld.x x25
  ame.exef x26
  ame.sync
  bltu x2, x11, .fwd108
  .fwd108:
.blk203:
  lbu x5, 796(x28)
  bgeu x1, x6, .fwd109
  srli x9, x6, 13
  xori x15, x3, -31
  .fwd109:
  bgeu x8, x7, .fwd110
  .fwd110:
  bltu x4, x1, .blk204
  or x8, x4, x12
.blk204:
  ame.sync
  li x27, 15
  ame.st.y x27, x9
  ori x6, x13, 4294901760
  sra x10, x5, x13
  lb x14, 200(x28)
  slt x5, x2, x10
  beq x4, x8, .blk205
.blk205:
  sll x14, x9, x4
  srai x4, x7, 9
  ori x13, x5, 32
  blt x2, x3, .blk206
  csrs mscratch, x15
.blk206:
  csrr x11, minstret
  slti x2, x8, 2863311530
  or x4, x15, x9
  csrr x9, minstret
  beq x13, x7, .fwd111
  .fwd111:
  slt x9, x3, x7
  slti x4, x8, 1431655765
  xori x10, x14, 1431655765
.blk207:
  andi x1, x7, 305419896
  xori x8, x9, -344865
  lw x1, 920(x28)
  csrr x14, flags
  sb x15, 36(x28)
  mul x2, x13, x7
  bgeu x4, x7, .fwd112
  slti x12, x3, 65535
  .fwd112:
.blk208:
  csrr x6, minstret
  divu x11, x11, x11
  or x12, x5, x7
  bge x12, x13, .blk209
  srli x15, x2, 30
  divu x2, x10, x13
.blk209:
  ame.ld.w x22
  ame.ld.x x25
  sh x6, 268(x28)
  sub x5, x1, x11
  slti x11, x12, 0
  slt x15, x2, x15
.blk210:
  andi x6, x6, 2147483647
  addi x2, x8, 1431655765
  bltu x10, x5, .fwd113
  addi x7, x6, -1
  .fwd113:
  lw x12, 628(x28)
  bltu x6, x5, .blk211
  ame.sync
  li x27, 12
  ame.st.y x27, x1
.blk211:
  srli x1, x2, 19
  sw x1, 480(x28)
  ame.ld.w x22
  ame.ld.x x24
  ame.exef x24
  ame.sync
  and x8, x6, x6
  sltiu x10, x3, 32
  add x9, x12, x14
  slli x2, x6, 21
.blk212:
  xori x9, x11, 2863311530
  csrr x11, mscratch
  lhu x15, 644(x28)
  ori x5, x11, 32
  csrr x13, minstret
  slt x4, x12, x2
.blk213:
  lw x5, 252(x28)
  bge x6, x1, .blk214
  sw x12, 528(x28)
  andi x8, x9, 4294901760
  csrr x7, minstret
  bgeu x11, x8, .fwd114
  .fwd114:
.blk214:
  bge x11, x2, .blk215
  beq x11, x10, .fwd115
  andi x15, x11, 2147483647
  .fwd115:
  xori x11, x1, 2147483647
  and x14, x8, x7
  slt x13, x8, x5
.blk215:
  slli x1, x9, 0
  sh x8, 376(x28)
  bge x7, x6, .fwd116
  addi x5, x5, 0
  slti x4, x3, 2
  .fwd116:
  sw x10, 784(x28)
.blk216:
  lw x5, 36(x28)
  ame.ld.w x22
  ame.ld.x x24
  ame.exef x24
  ame.sync
  sb x12, 908(x28)
  bgeu x7, x15, .fwd117
  .fwd117:
  ame.sync
  li x27, 1
  ame.st.y x27, x12
.blk217:
  lw x9, 680(x28)
  bge x6, x1, .fwd118
  andi x3, x2, 2
  .fwd118:
  remu x12, x11, x5
  srl x2, x9, x12
  sw x9, 876(x28)
.blk218:
  slli x8, x10, 20
  srli x12, x10, 29
  addi x9, x6, 128
.blk219:
  xori x11, x1, 31
  beq x4, x5, .fwd119
  srai x15, x4, 17
  slti x15, x5, -344865
  .fwd119:
  lw x10, 768(x28)
  csrr x11, flags
  divu x9, x12, x7
.blk220:
  addi x15, x8, 2
  csrr x6, flags
  sltiu x2, x14, 4294901760
  sw x6, 920(x28)
  srai x13, x10, 12
  lw x13, 788(x28)
  sll x11, x8, x14
  and x15, x4, x11
.blk221:
  sltu x14, x3, x5
  div x1, x1, x6
  rem x15, x5, x4
  sb x2, 492(x28)
  divu x6, x14, x14
  xor x12, x2, x4
  slt x6, x10, x11
  ame.ld.w x22
  ame.ld.x x24
  ame.exef x24
  ame.sync
.blk222:
  sb x15, 648(x28)
  bne x5, x1, .fwd120
  srai x11, x14, 0
  sltiu x15, x3, 65535
  .fwd120:
  srai x5, x3, 17
  bgeu x4, x14, .fwd121
  andi x9, x8, 2
  .fwd121:
  xori x13, x4, -2
.blk223:
  sltiu x14, x7, 2
  lb x7, 472(x28)
  sh x5, 488(x28)
  divu x1, x12, x7
  blt x7, x8, .fwd122
  .fwd122:
  add x2, x3, x3
  slli x2, x9, 3
  ame.ld.w x23
  ame.ld.x x25
  ame.exef x26
  ame.sync
.blk224:
  blt x4, x12, .blk225
  sb x11, 836(x28)
  and x14, x1, x14
  sh x13, 284(x28)
  mulhsu x8, x9, x5
  addi x5, x14, -2
  lbu x13, 376(x28)
  sltiu x14, x3, 0
.blk225:
  or x5, x2, x8
  ame.ld.w x23
  ame.ld.x x25
  sb x1, 960(x28)
  bltu x6, x2, .blk226
  csrr x1, minstret
  sw x3, 592(x28)
  rem x12, x3, x8
  srai x3, x3, 15
.blk226:
  mul x8, x10, x7
  rem x14, x9, x11
  slli x3, x8, 17
  ori x6, x14, -31
  sra x1, x5, x3
.blk227:
  sw x7, 108(x28)
  bltu x8, x6, .fwd123
  andi x3, x5, -2147483648
  .fwd123:
  sltu x11, x7, x15
  sh x6, 220(x28)
  srl x1, x12, x12
  csrr x5, minstret
.blk228:
  sra x6, x11, x12
  bltu x10, x12, .fwd124
  slli x3, x3, 21
  .fwd124:
  lhu x8, 776(x28)
  csrr x14, minstret
  addi x8, x9, 65535
  add x2, x9, x3
  lbu x1, 908(x28)
  csrr x6, minstret
.blk229:
  bgeu x7, x10, .fwd125
  ori x6, x12, 128
  .fwd125:
  ori x14, x11, 2
  slti x12, x3, 1431655765
  ame.ld.w x22
  ame.ld.x x24
  srli x12, x4, 12
.blk230:
  and x12, x8, x5
  xori x8, x13, -2147483648
  beq x8, x15, .blk231
  sb x7, 828(x28)
.blk231:
  ame.sync
  li x27, 9
  ame.st.y x27, x1
  rem x11, x10, x12
  lh x10, 464(x28)
.blk232:
  ori x3, x7, -2147483648
  sh x10, 556(x28)
  divu x7, x9, x14
  ame.sync
  li x27, 6
  ame.st.q x27, x7
  slti x11, x9, 1
  slti x9, x14, -2
  mulhsu x8, x15, x1
  lw x14, 228(x28)
.blk233:
  srli x4, x11, 28
  ame.ld.w x23
  ame.ld.x x24
  sub x4, x8, x8
  slli x5, x13, 29
.blk234:
  sw x12, 760(x28)
  sltu x4, x3, x14
  ame.ld.w x22
  ame.ld.x x25
  ame.sync
  li x27, 4
  ame.st.y x27, x11
  xori x11, x2, -31
.blk235:
  lhu x9, 264(x28)
  sltu x15, x14, x11
  bne x9, x2, .fwd126
  sltiu x13, x4, 65535
  .fwd126:
.blk236:
  srl x7, x14, x2
  blt x9, x11, .fwd127
  .fwd127:
  sll x1, x11, x3
  ame.sync
  li x27, 2
  ame.st.y x27, x1
  sll x9, x13, x7
  mulh x10, x10, x15
  ame.ld.w x22
  ame.ld.x x24
  ame.exe x24
  ame.sync
  lb x5, 352(x28)
.blk237:
  bltu x12, x14, .fwd128
  slli x10, x7, 8
  srai x9, x2, 7
  .fwd128:
  slli x12, x11, 12
  bge x3, x6, .blk238
  ame.ld.w x23
  ame.ld.x x24
  sw x5, 776(x28)
  sb x7, 956(x28)
  sh x7, 0(x28)
.blk238:
  div x5, x13, x10
  sub x9, x6, x13
  ame.ld.w x23
  ame.ld.x x25
  ame.exe x26
  ame.sync
  bne x7, x11, .fwd129
  .fwd129:
  addi x9, x14, 1431655765
  sra x8, x9, x11
  sll x8, x9, x12
  remu x15, x4, x14
.blk239:
  xori x4, x6, 31
  bgeu x10, x3, .fwd130
  .fwd130:
  ame.ld.w x23
  ame.ld.x x25
  ame.exef x26
  ame.sync
  sh x15, 328(x28)
  divu x10, x9, x2
.blk240:
  sb x2, 328(x28)
  ame.ld.w x23
  ame.ld.x x24
  csrr x3, minstret
  or x7, x10, x13
  csrs mscratch, x8
  bne x13, x13, .blk241
  xor x13, x7, x14
.blk241:
  sltiu x11, x1, 65535
  beq x1, x4, .fwd131
  slli x11, x10, 8
  .fwd131:
  ame.ld.w x22
  ame.ld.x x24
  ame.exe x24
  ame.sync
.blk242:
  lh x12, 840(x28)
  mul x1, x15, x10
  add x12, x14, x6
  slti x11, x7, -1
  srli x2, x10, 18
.blk243:
  csrr x2, minstret
  addi x11, x3, -1
  slti x11, x1, -31
  beq x7, x2, .blk244
  bge x12, x12, .blk244
.blk244:
  slli x4, x15, 25
  sw x2, 204(x28)
  sll x13, x8, x2
  ame.ld.w x22
  ame.ld.x x24
  bge x5, x8, .fwd132
  .fwd132:
  andi x12, x8, 255
  ori x6, x6, 128
.blk245:
  mul x5, x6, x13
  csrr x9, minstret
  lbu x2, 920(x28)
  xor x1, x5, x10
.blk246:
  or x8, x1, x3
  lb x7, 492(x28)
  slli x13, x14, 2
  ame.ld.w x22
  ame.ld.x x24
  ame.exef x24
  ame.sync
  slli x4, x4, 20
  sb x2, 660(x28)
.blk247:
  sltu x6, x8, x7
  ame.ld.w x22
  ame.ld.x x24
  ame.exe x24
  ame.sync
  bge x1, x3, .blk248
  xor x11, x5, x10
  srai x9, x15, 9
.blk248:
  ame.ld.w x23
  ame.ld.x x25
  ame.exef x26
  ame.sync
  bge x8, x1, .fwd133
  sltiu x10, x9, -1
  .fwd133:
  slli x2, x1, 30
  or x3, x7, x3
  lh x15, 548(x28)
  sb x6, 216(x28)
.blk249:
  sub x4, x14, x1
  andi x13, x4, 2147483647
  blt x13, x11, .fwd134
  sltiu x11, x6, 32
  .fwd134:
  ame.sync
  li x27, 3
  ame.st.q x27, x15
  bge x5, x5, .fwd135
  addi x14, x14, 4294901760
  .fwd135:
  sh x12, 688(x28)
  srl x13, x1, x1
.blk250:
  lh x5, 1004(x28)
  sub x12, x4, x4
  remu x5, x15, x10
  slti x1, x6, 128
.blk251:
  slt x7, x15, x2
  slti x6, x8, 31
  add x15, x3, x9
.blk252:
  csrr x7, minstret
  mulhu x5, x13, x13
  xor x1, x2, x14
  sll x12, x12, x1
  sltiu x13, x2, 1431655765
  ori x1, x8, -2
  sh x2, 992(x28)
  lhu x13, 848(x28)
.blk253:
  sll x4, x15, x13
  slt x11, x10, x5
  xori x6, x11, 65535
  mul x4, x12, x11
  sw x7, 292(x28)
  sb x10, 12(x28)
  sra x6, x2, x11
  lw x9, 984(x28)
.blk254:
  sw x9, 720(x28)
  blt x13, x4, .fwd136
  srai x4, x12, 2
  ori x11, x6, 2863311530
  .fwd136:
  csrr x4, minstret
  csrc mscratch, x3
  srli x11, x7, 24
  and x5, x3, x5
  bge x11, x15, .fwd137
  .fwd137:
  bne x11, x15, .fwd138
  addi x14, x12, 2863311530
  xori x10, x1, 305419896
  .fwd138:
.blk255:
  and x5, x11, x1
  lhu x14, 28(x28)
  bgeu x10, x8, .fwd139
  .fwd139:
  slt x7, x12, x8
  ori x9, x15, 255
  lw x4, 276(x28)
.blk256:
  sub x5, x12, x14
  slli x13, x11, 4
  ame.ld.w x23
  ame.ld.x x25
  ame.exe x26
  ame.sync
  slli x2, x14, 24
.blk257:
  sra x7, x12, x4
  ori x13, x12, -2
  csrr x5, mscratch
.blk258:
  lh x7, 556(x28)
  xor x7, x7, x4
  lw x7, 272(x28)
  addi x8, x3, 0
  bge x1, x1, .fwd140
  slli x2, x1, 2
  slti x12, x9, 1
  .fwd140:
  sw x7, 600(x28)
  bltu x12, x13, .fwd141
  .fwd141:
.blk259:
  bltu x15, x1, .fwd142
  xori x4, x10, 32
  .fwd142:
  lh x5, 612(x28)
  or x4, x8, x14
  mulhsu x8, x13, x7
.blk_end:
  ame.sync
  li x28, 0x1FFF0
  li x29, 0x600D
  sw x29, 0(x28)
  ebreak
