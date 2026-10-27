# AME 指令序列:cfg/qcfg/ld.w/ld.x/exef/exe/sync/st.y/st.q + ERR 路径 + flags
# 差分断言:ISS 的 AmeModel 与 tb_ame_model.sv 逐语义一致,WBUF/XBUF 同模式
  .org 0x10000
boot:
  j start

  .org 0x0
start:
  li x28, 0x2000           # 结果落内存

  # ---- 1) 配置形状 + 16 通道 requant(M=i+1,S=3,ROUND=1) ----
  ame.cfg 16, 16
  li x8, 1                 # M
  li x9, 193               # rs2 = S=3 | ROUND_SEL=1<<6 = 0xC1
  ame.qcfg 0, x8, x9
  addi x8, x8, 1
  ame.qcfg 1, x8, x9
  addi x8, x8, 1
  ame.qcfg 2, x8, x9
  addi x8, x8, 1
  ame.qcfg 3, x8, x9
  addi x8, x8, 1
  ame.qcfg 4, x8, x9
  addi x8, x8, 1
  ame.qcfg 5, x8, x9
  addi x8, x8, 1
  ame.qcfg 6, x8, x9
  addi x8, x8, 1
  ame.qcfg 7, x8, x9
  addi x8, x8, 1
  ame.qcfg 8, x8, x9
  addi x8, x8, 1
  ame.qcfg 9, x8, x9
  addi x8, x8, 1
  ame.qcfg 10, x8, x9
  addi x8, x8, 1
  ame.qcfg 11, x8, x9
  addi x8, x8, 1
  ame.qcfg 12, x8, x9
  addi x8, x8, 1
  ame.qcfg 13, x8, x9
  addi x8, x8, 1
  ame.qcfg 14, x8, x9
  addi x8, x8, 1
  ame.qcfg 15, x8, x9

  # ---- 2) 第一片:exef(清 Y 累加) ----
  li x10, 0                # region0 | tsel0<<2
  ame.ld.w x10
  li x10, 0                # off0 | xsel0<<9
  ame.ld.x x10
  li x10, 0                # tsel0
  ame.exef x10
  ame.sync

  # ---- 3) 读回 16 路 INT32 + INT8 ----
  li x11, 0
sty_loop:
  ame.st.y x11, x12
  slli x13, x11, 2
  add x13, x28, x13
  sw x12, 0(x13)           # Y[i] → mem[0x2000+4i]
  ame.st.q x11, x14
  addi x15, x13, 64
  sb x14, 0(x15)           # y_q[i] → mem[0x2040+i]
  addi x11, x11, 1
  li x16, 16
  blt x11, x16, sty_loop

  # ---- 4) 第二片:exe(不清 Y,继续累加),乒乓组 1 ----
  li x10, 5                # region1 | tsel1<<2
  ame.ld.w x10
  li x10, 528              # off16 | xsel1<<9
  ame.ld.x x10
  li x10, 1                # tsel1
  ame.exe x10              # 累加(不清 Y)
  ame.sync

  li x11, 0
sty2_loop:
  ame.st.y x11, x12
  slli x13, x11, 2
  add x13, x28, x13
  lw x16, 0(x13)
  add x17, x16, x12        # 第一片 + 第二片(累加验证)
  sw x17, 0(x13)
  ame.st.q x11, x14
  addi x15, x13, 128
  sb x14, 0(x15)
  addi x11, x11, 1
  li x16, 16
  blt x11, x16, sty2_loop

  # ---- 5) ERR 路径(照常接受、置 ERR、数据 0;不 trap 不停机) ----
  .word 0x4000000B         # cfg 但 imm[11:10]!=0 → ERR,配置不变
  li x11, 20               # i=20 ≥ N_eff=16 → st.y 返回 0 + ERR
  ame.st.y x11, x18        # x18 = 0
  li x9, 0
  ame.qcfg 3, x8, x9       # S=0 → ERR(表不变)
  li x10, 0x80000002       # rs1[31:1]!=0 → exe ERR,不启动
  ame.exe x10
  ame.sync

  # ---- 6) custom-0 未定义 funct7 → CPU 本地非法(不转发 AME) ----
  .word 0xFE00200B         # f3=2,f7=0x7F → 非法

  # ---- 7) flags CSR 自检(可差分:非法/AME_ERR 位与 ISS 一致) ----
  csrr x19, flags
  sw x19, 256(x28)
  li x20, 0xFFFFFFFF
  csrc flags, x20          # 清零 flags
  csrr x21, flags
  sw x21, 260(x28)
  csrr x22, minstret       # 与 ISS 可比(同源指令计数)
  sw x22, 264(x28)
  csrr x23, mcycle         # 差分跳过 wdata(skip 标志)
  sw x23, 268(x28)

  ebreak
