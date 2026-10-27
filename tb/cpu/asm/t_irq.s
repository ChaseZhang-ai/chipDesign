# 中断最小实现(TB 定向测试,不做 ISS 差分:+IRQAT=拉高 irq)
# 期望:trap 进 handler,mcause=0x80000010,写魔数,mret 回主流程
  .org 0x10000
boot:
  j start

  .org 0x0
start:
  li x28, 0x1FFF0
  la x1, handler
  csrw mtvec, x1
  li x2, 0x8
  csrs mstatus, x2          # MIE=1
spin:
  wfi
  beq x10, x0, spin         # handler 置 x10=1 后落地
  li x6, 0x600D
  sw x6, 0(x28)
  ebreak

handler:
  csrr x3, mcause
  li x4, 0x80000010
  bne x3, x4, bad_irq
  csrr x5, mepc
  sw x5, 8(x28)             # 记录 mepc(观测用)
  li x10, 1
  mret
bad_irq:
  li x6, 0xDEAD
  sw x6, 0(x28)
  mret
