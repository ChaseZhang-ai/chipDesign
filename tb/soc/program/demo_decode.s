// -----------------------------------------------------------------------------
// demo_decode.s — AME-Chip 微内核 demo(P2D smoke_2;ARCH_SPEC §5 的指令级缩影)
//
// 数据流: UART 初始化 → DMA 拉一块 16×16 INT8 权重 tile(OC SRAM→AME WBUF)
//   → DMA 拉 16B 激活向量(OC SRAM→AME XBUF) → qcfg×16 装载 per-channel requant
//   参数 → cfg → ld.w/ld.x/exef/sync(一次 16×16 tile GEMV) → st.q 逐通道取回
//   requant 结果 → 两位 hex + 空格写 UART → 换行 → 停机。
//
// 数值: W[n][k] = ((3n+k) mod 7) - 3(含负数,INT8 有符号)
//       x[k]    = ((5k) mod 11) - 5
//       y[n]    = Σ_k W[n][k]·x[k](k 升序,GOLDEN_SPEC §2.1)
//       requant M=256, S=8, ROUND_SEL=1(恒等标定,y_q = y_int32)
// 期望输出字节序列(TB 硬编码比对):
//       21 07 DF FD 06 EC 0A 21 07 DF FD 06 EC 0A 21 07
//
// 尺寸: 程序+数据总镜像 ≤4KB(OC SRAM);build_hex.py 强制 text≤2KB/data≤2KB。
// -----------------------------------------------------------------------------

.equ UART_BASE, 0x10002000
.equ DMA_BASE,  0x20000000
.equ AME_WBUF,  0x20001000        // AME 窗口基址(ARCH_SPEC §4.7)
.equ AME_XBUF,  0x20001400

// DMA 寄存器偏移(§4.5)
.equ DMA_SRC_OFF,    0x00
.equ DMA_DST_OFF,    0x04
.equ DMA_XCNT_OFF,   0x08
.equ DMA_YCNT_OFF,   0x0C
.equ DMA_CTRL_OFF,   0x18
.equ DMA_STATUS_OFF, 0x1C
.equ DMA_GO,         1
.equ DMA_DONE,       2

.equ UART_DIV_OFF,    0x08
.equ UART_STAT_OFF,   0x10
.equ STAT_TX_FULL,    18

.text
.globl _start
_start:
    // ---- UART 初始化(DIV=13,仿真加速) ----
    li   t0, UART_BASE
    li   t1, 13
    sw   t1, UART_DIV_OFF(t0)

    // ---- DMA #1: 权重 64 字 OC SRAM wdata → AME WBUF ----
    li   t0, DMA_BASE
    la   t1, wdata
    sw   t1, DMA_SRC_OFF(t0)
    li   t1, AME_WBUF
    sw   t1, DMA_DST_OFF(t0)
    li   t1, 64                     // XCNT = 64 字 = 256B
    sw   t1, DMA_XCNT_OFF(t0)
    li   t1, 1                      // YCNT = 1
    sw   t1, DMA_YCNT_OFF(t0)
    li   t1, DMA_GO
    sw   t1, DMA_CTRL_OFF(t0)
    jal  ra, dma_wait_done         // 轮询 + W1C DONE(t0=DMA 基址保留)

    // ---- DMA #2: 激活 4 字 → AME XBUF ----
    li   t0, DMA_BASE
    la   t1, xdata
    sw   t1, DMA_SRC_OFF(t0)
    li   t1, AME_XBUF
    sw   t1, DMA_DST_OFF(t0)
    li   t1, 4
    sw   t1, DMA_XCNT_OFF(t0)
    li   t1, 1
    sw   t1, DMA_YCNT_OFF(t0)
    li   t1, DMA_GO
    sw   t1, DMA_CTRL_OFF(t0)
    jal  ra, dma_wait_done

    // ---- per-channel requant 参数:M=256 → x5;S=8|ROUND_SEL<<6 = 72 → x6 ----
    li   x5, 256
    li   x6, 72
    ame.qcfg 0,  x5, x6
    ame.qcfg 1,  x5, x6
    ame.qcfg 2,  x5, x6
    ame.qcfg 3,  x5, x6
    ame.qcfg 4,  x5, x6
    ame.qcfg 5,  x5, x6
    ame.qcfg 6,  x5, x6
    ame.qcfg 7,  x5, x6
    ame.qcfg 8,  x5, x6
    ame.qcfg 9,  x5, x6
    ame.qcfg 10, x5, x6
    ame.qcfg 11, x5, x6
    ame.qcfg 12, x5, x6
    ame.qcfg 13, x5, x6
    ame.qcfg 14, x5, x6
    ame.qcfg 15, x5, x6

    // ---- 形状配置 + 一次 16×16 tile GEMV ----
    ame.cfg 16, 16                   // N_eff=16, KT=16
    li   t0, 0                       // 选择子: ld.w region0/tsel0 = 0
    ame.ld.w t0
    ame.ld.x t0                      // ld.x off0/xsel0 = 0
    ame.exef t0                      // 首片清 Y(无 bias)
    ame.sync                         // 等 AME 空闲

    // ---- st.q 逐通道取回 → UART hex ----
    li   s0, UART_BASE
    la   s1, hexdig
    li   s2, 0                       // i = 通道号

print_loop:
    mv   t1, s2                      // st.q 选择子寄存器:value[4:0] = i
    ame.st.q t1, a0                  // a0 = sext8(requant_i(Y[i]))
    srli t2, a0, 4
    andi t2, t2, 15
    add  t3, t2, s1
    lbu  t3, 0(t3)                   // 高半 nibble
    jal  ra, txchar
    andi t2, a0, 15
    add  t3, t2, s1
    lbu  t3, 0(t3)                   // 低半 nibble
    jal  ra, txchar
    li   t3, 32                      // 空格分隔
    jal  ra, txchar
    addi s2, s2, 1
    li   t4, 16
    blt  s2, t4, print_loop
    li   t3, 10                      // '\n'
    jal  ra, txchar

halt:
    wfi
    j    halt

// ---- 子程序: 等一次 DMA 完成(DONE 轮询 + W1C)。入口 t0=DMA 基址,退出保持 ----
dma_wait_done:
dma_poll:
    lw   t1, DMA_STATUS_OFF(t0)
    srli t1, t1, 1
    andi t1, t1, 1                   // STATUS[1] = DONE
    beq  t1, zero, dma_poll
    li   t1, DMA_DONE
    sw   t1, DMA_STATUS_OFF(t0)      // W1C
    ret

// ---- 子程序: 发送 1 字节。入口 t3=字节, s0=UART 基址;破坏 t4/t5 ----
txchar:
txfull_wait:
    lw   t4, UART_STAT_OFF(s0)
    srli t4, t4, STAT_TX_FULL
    andi t4, t4, 1
    bne  t4, zero, txfull_wait
    sw   t3, 0(s0)                   // TXDATA
    ret

// ---- 数据段 ----
.data
.align 2
wdata:
    // W[n][k] = ((3n+k) mod 7) - 3,按 [n][k] 行主序(与 XMEM blob 同序,§4.10)
    .byte 253, 254, 255, 0, 1, 2, 3, 253, 254, 255, 0, 1, 2, 3, 253, 254
    .byte 0, 1, 2, 3, 253, 254, 255, 0, 1, 2, 3, 253, 254, 255, 0, 1
    .byte 3, 253, 254, 255, 0, 1, 2, 3, 253, 254, 255, 0, 1, 2, 3, 253
    .byte 255, 0, 1, 2, 3, 253, 254, 255, 0, 1, 2, 3, 253, 254, 255, 0
    .byte 2, 3, 253, 254, 255, 0, 1, 2, 3, 253, 254, 255, 0, 1, 2, 3
    .byte 254, 255, 0, 1, 2, 3, 253, 254, 255, 0, 1, 2, 3, 253, 254, 255
    .byte 1, 2, 3, 253, 254, 255, 0, 1, 2, 3, 253, 254, 255, 0, 1, 2
    .byte 253, 254, 255, 0, 1, 2, 3, 253, 254, 255, 0, 1, 2, 3, 253, 254
    .byte 0, 1, 2, 3, 253, 254, 255, 0, 1, 2, 3, 253, 254, 255, 0, 1
    .byte 3, 253, 254, 255, 0, 1, 2, 3, 253, 254, 255, 0, 1, 2, 3, 253
    .byte 255, 0, 1, 2, 3, 253, 254, 255, 0, 1, 2, 3, 253, 254, 255, 0
    .byte 2, 3, 253, 254, 255, 0, 1, 2, 3, 253, 254, 255, 0, 1, 2, 3
    .byte 254, 255, 0, 1, 2, 3, 253, 254, 255, 0, 1, 2, 3, 253, 254, 255
    .byte 1, 2, 3, 253, 254, 255, 0, 1, 2, 3, 253, 254, 255, 0, 1, 2
    .byte 253, 254, 255, 0, 1, 2, 3, 253, 254, 255, 0, 1, 2, 3, 253, 254
    .byte 0, 1, 2, 3, 253, 254, 255, 0, 1, 2, 3, 253, 254, 255, 0, 1

.align 2
xdata:
    // x[k] = ((5k) mod 11) - 5
    .byte 251, 0, 5, 255, 4, 254, 3, 253, 2, 252, 1, 251, 0, 5, 255, 4

hexdig:
    .ascii "0123456789abcdef"
