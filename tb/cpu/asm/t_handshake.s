# AME 阻塞连发/握手:背靠背发射 + 语义反压(exe 忙时 st.y/sync 阻塞)
# 本测试在 Makefile 里配 STALLPCT=70 高强度人为反压,监视器核查 R1/R3
  .org 0x10000
boot:
  j start

  .org 0x0
start:
  li x28, 0x2000
  ame.cfg 8, 16
  li x8, 2
  li x9, 129                # S=1, ROUND=1
  ame.qcfg 0, x8, x9
  ame.qcfg 1, x8, x9

  # 背靠背:ld.w; ld.x; exef(exef 会等装载完成 → 阻塞)
  li x10, 0
  ame.ld.w x10
  ame.ld.x x10
  ame.exef x10
  ame.st.y x0, x11          # exe 忙 → 阻塞至 IDLE
  ame.sync

  # 乒乓:组 1 装载后立即 exe 组 0(已 READY→RUNNING→READY)
  li x10, 5
  ame.ld.w x10
  li x10, 512
  ame.ld.x x10
  li x10, 1
  ame.exef x10
  ame.sync
  ame.st.q x0, x12

  # 连发 8 条 st.y(每条都要 IDLE,夹在两次 exe 间)
  li x10, 0
  ame.ld.w x10
  ame.ld.x x10
  ame.exef x10
  ame.sync
  ame.st.y x0, x13
  ame.st.y x8, x14          # x8=2 → i=2 合法
  ame.st.y x9, x15          # x9=129 → i=129&31=1
  ame.sync

  sw x11, 0(x28)
  sw x12, 4(x28)
  sw x13, 8(x28)
  sw x14, 12(x28)
  sw x15, 16(x28)
  csrr x16, flags
  csrc flags, x16
  ebreak
