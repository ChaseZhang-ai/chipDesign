# 分支:前跳/后跳、六种条件全组合、jal/jalr、call/ret 嵌套、循环
  .org 0x10000
boot:
  j start

  .org 0x0
start:
  li x1, 10
  li x2, 0
  li x3, 0
loop:                       # 后跳:sum += i; i--
  add x2, x2, x1
  addi x1, x1, -1
  bne x1, x0, loop          # x2 = 55
  beq x1, x0, fwd1
  addi x3, x3, 100          # 不执行
fwd1:
  blt x0, x2, fwd2          # taken
  addi x3, x3, 200          # skip
fwd2:
  bge x2, x0, fwd3          # taken
  addi x3, x3, 300
fwd3:
  bltu x0, x2, fwd4         # taken
  addi x3, x3, 400
fwd4:
  bgeu x2, x0, fwd5         # taken
  addi x3, x3, 500
fwd5:
  li x4, -1                 # 0xFFFFFFFF
  blt x2, x4, bad           # 55 < -1 有符号?否 → not taken
  bge x4, x2, bad           # -1 >= 55?否
  bltu x2, x4, fwd6         # 55 < 0xFFFFFFFF 无符号 → taken
  addi x3, x3, 600
fwd6:
  beq x2, x2, fwd7          # 恒真
  addi x3, x3, 700
fwd7:
  bne x2, x2, bad           # 恒假
  jal x1, sub1              # call/ret(ra 约定)
  addi x3, x3, 5            # 返回后执行
  jal x0, after             # j
  addi x3, x3, 900          # 跳过
after:
  # jalr:寄存器目标
  auipc x6, 0
  addi x7, x6, 24           # 目标 = 下一条 jalr +24 → jr_target
  jalr x8, x7, 0
  addi x3, x3, 950          # 跳过
jr_target:
  addi x3, x3, 10
  # 分支依赖 load(互锁 + EX 解析)
  li x28, 0x2000
  sw x2, 0(x28)
  lw x9, 0(x28)
  beq x9, x2, fwd8          # load-use 分支
  addi x3, x3, 800
fwd8:
  # 分支依赖乘除结果
  li x10, 6
  li x11, 7
  mul x12, x10, x11
  beq x12, x2, fwd9         # 42 != 55 → not taken
  bne x12, x2, fwd9         # taken
  addi x3, x3, 850
fwd9:
  # 小循环嵌套
  li x13, 3
outer:
  li x14, 2
inner:
  addi x3, x3, 1
  addi x14, x14, -1
  bnez x14, inner
  addi x13, x13, -1
  bnez x13, outer
  beq x0, x0, done
bad:
  addi x3, x3, 1000
done:
  sw x3, 4(x28)
  ebreak

sub1:                       # 子程序(ra=x1 约定,与 ret 伪指令一致)
  addi x3, x3, 1
  ret
