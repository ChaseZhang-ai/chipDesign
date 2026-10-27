# 停等场景:load-use 链、store→load 同地址、乘除后立即依赖、混合
  .org 0x10000
boot:
  j start

  .org 0x0
start:
  li x28, 0x2000
  li x1, 1
  li x2, 2
  li x3, 3
  li x4, 4

  # 1) 连续 load-use(逐条互锁)
  sw x1, 0(x28)
  sw x2, 4(x28)
  sw x3, 8(x28)
  lw x5, 0(x28)
  add x6, x5, x5           # 紧跟依赖
  lw x7, 4(x28)
  add x8, x7, x6
  lw x9, 8(x28)
  sub x10, x9, x7

  # 2) load 后隔一条再依赖(旁路 vs 互锁混合)
  lw x11, 0(x28)
  addi x12, x0, 5
  add x13, x11, x12        # 隔 1 条:仍互锁(2 拍)
  nop
  add x14, x11, x11        # 已在 WB,旁路供给

  # 3) store→load 同地址(写读保序)与不同地址
  sw x5, 12(x28)
  lw x15, 12(x28)
  sw x6, 16(x28)
  lw x16, 16(x28)
  lw x17, 0(x28)           # 更早地址

  # 4) 子字 store→load
  sb x2, 20(x28)
  lb x18, 20(x28)
  sh x3, 22(x28)
  lhu x19, 22(x28)

  # 5) 乘除后立即依赖
  mul x20, x1, x3          # 3
  add x21, x20, x1         # EX 级停等后旁路
  div x22, x3, x2          # 1(33 拍)
  add x23, x22, x21
  rem x24, x9, x4
  sub x25, x24, x23

  # 6) mul→mul 连发(单元复用)
  mul x26, x2, x2
  mul x27, x26, x26
  mulh x31, x27, x27

  # 7) load-use 混在乘除之间
  lw x5, 16(x28)
  mul x6, x5, x4           # 依赖 load 的乘法(互锁+停等)
  add x7, x6, x5

  # 8) AME 阻塞指令后紧跟依赖(st.y 旁路路径)
  ebreak
