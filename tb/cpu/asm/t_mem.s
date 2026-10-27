# load/store 字节序、子字访问、未对齐(按非法 NOP 处理)、store→load 保序
  .org 0x10000
boot:
  j start

  .org 0x0
start:
  li x28, 0x2000          # 数据区
  li x1, 0x11223344
  sw x1, 0(x28)
  lb x2, 0(x28)           # 0x44(小端)
  lb x3, 1(x28)           # 0x33
  lb x4, 2(x28)           # 0x22
  lb x5, 3(x28)           # 0x11
  lbu x6, 0(x28)          # 0x44
  lbu x7, 3(x28)          # 0x11
  lh x8, 0(x28)           # 0x3344
  lh x9, 2(x28)           # 0x1122
  lhu x10, 0(x28)
  lhu x11, 2(x28)
  lw x12, 0(x28)          # 0x11223344

  # 子字写入后整字读回
  li x13, 0xAABBCCDD
  sb x13, 4(x28)          # 只写低字节 → 4(x28) 字节0 = 0xDD
  lb x14, 4(x28)          # 0xFFFFFFDD
  lbu x15, 4(x28)         # 0xDD
  sh x13, 6(x28)          # 写低半字
  lhu x16, 6(x28)         # 0xCCDD
  lh x17, 6(x28)          # 0xFFFFCCDD
  li x18, 0x99
  sb x18, 5(x28)
  lw x19, 4(x28)          # 0x99CC_00DD? → 由 ISS/RTL 共同裁定

  # 跨字节组合
  li x20, 0x00FF00FF
  sw x20, 8(x28)
  sb x1, 9(x28)           # 字节1 = 0x44
  lhu x21, 8(x28)         # 0x4444
  lw x22, 8(x28)

  # 负偏移
  addi x23, x28, 16
  sw x1, -4(x23)          # = 12(x28)
  lw x24, 12(x28)

  # store→load 同地址(AXI 写读保序路径)
  li x25, 0xCAFEBABE
  sw x25, 16(x28)
  lw x26, 16(x28)
  sb x0, 16(x28)
  lbu x27, 16(x28)        # 0
  sh x13, 16(x28)
  lhu x31, 16(x28)        # 0xCCDD

  # 未对齐访问 → 非法 NOP + flags 粘滞(两侧一致)
  addi x5, x28, 1
  lw x6, 0(x5)            # 未对齐 lw → NOP
  lh x7, 3(x28)           # 奇地址 lh → NOP
  lw x8, 0(x28)           # 对齐恢复正常
  lb x9, 1(x28)

  # 未初始化区域读 0(镜像零填充)
  li x10, 0x4000
  lw x11, 0(x10)

  ebreak
