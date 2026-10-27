# 冒烟:BOOTROM j 主程序,基本 ALU/访存,写自检魔数,ebreak 停机
  .org 0x10000
boot:
  j start

  .org 0x0
start:
  li x1, 5
  li x2, 7
  add x3, x1, x2        # 12
  sub x4, x1, x2        # -2
  lui x5, 0xDEADB
  addi x5, x5, -1       # 0xDEADAFFF? (0xDEADB000-1)
  li x28, 0x1FFF0
  li x29, 0x600D
  sw x29, 0(x28)
  lw x30, 0(x28)
  ebreak
