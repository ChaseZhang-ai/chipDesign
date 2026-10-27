// -----------------------------------------------------------------------------
// verify_edge.s — P3B 微内核 C:边界与非法(定向;全部使用可达观测路径)
//
// 观测口径说明(联测发现,见 reports/issues/P3B.md I1):
//   AME 的 DONE/ERR 事件被 AME_IRQEN 门控,而契约偏移 +0x20C4 落在 8KB AME
//   窗口之外(与 KV CSR 区冲突,issues #4 未裁决)→ INTC bit4/5 不可达。
//   因此 AME 非法字段的验证改用**状态不变性**:非法操作后重跑同一合法微 GEMV,
//   结果必须逐位不变(y=0x0000002e)。E9 直接读契约 IRQEN 偏移 0x2000_30C4,
//   打印其值以留证别名冲突(期望 0,来自 KV CSR 未定义偏移)。
//
// E1  cfg 保留位 imm[11:10]≠00(.word 直编)→ ERR(配置不变)   → 重跑 y=0000002e
// E2  qcfg S=0 → ERR(不装载)                                → y=0000002e
// E3  exe rs1[31:1]≠0 → ERR(不启动)                         → y=0000002e
// E4  ld.x rs1[31:10]≠0 → ERR                               → y=0000002e
// E5  ld.w rs1[31:3]≠0 → ERR                                → y=0000002e
// E6  st.y i≥N_eff(cfg n=1)→ 返回 0 + ERR                    → 打印 st.y(3)=00000000
// E7  合法微 GEMV(W/x 由 CPU 字节 store 直填 WBUF/XBUF)      → y=0000002e
// E8  同组重装(Y 保持)→ exe 累加                             → 2y=0000005c
// E9  lw 0x2000_30C4(契约 AME_IRQEN 偏移)→ KV CSR 别名       → 打印读数(期望 0)
// E10 lw 保留区 0x0000_2000 → DECERR → CPU bus_err → INTC[8] → '1'
// E11 sw BOOTROM(RO)→ SLVERR → INTC[8]                      → '1'
// E12 lw 0x6000_0000(保留)→ DECERR → INTC[8]                → '1'
// E13 DMA SRC 未对齐 → ERRCODE=1                             → 打印 ERRCODE '1'
// E14 DMA SRC→保留区 → ERRCODE=2                             → '2'
// E15 KV POS+COUNT 越界(CTRL 含 IRQ_EN=1)→ ERR → INTC[7]     → '1'
// -----------------------------------------------------------------------------

.equ UART_BASE, 0x10002000
.equ DMA_BASE,  0x20000000
.equ KV_BASE,   0x20003000
.equ INTC_BASE, 0x10001000
.equ AME_WBUF,  0x20001000
.equ AME_XBUF,  0x20001400

.equ UART_STAT_OFF, 0x10
.equ STAT_TX_FULL,  18
.equ DMA_STATUS_OFF, 0x1C
.equ INTC_PEND_OFF,  0x04
.equ INTC_CLEAR_OFF, 0x08

.text
.globl _start
_start:
    li   sp, 0x00000C00
    li   s0, DMA_BASE
    li   s1, UART_BASE                 // UART DIV=13 由 boot 设置

    // ---- 公共前置:合法 cfg(1 通道,16 深)+ 填充 WBUF/XBUF ----
    ame.cfg 1, 16
    // AME 窗口只接受**对齐字写**(未对齐字节写 → SLVERR 且不落盘):
    // 按字装载 WBUF/XBUF
    la   t0, wvec
    li   t1, AME_WBUF
    lw   t3, 0(t0)
    sw   t3, 0(t1)
    lw   t3, 4(t0)
    sw   t3, 4(t1)
    lw   t3, 8(t0)
    sw   t3, 8(t1)
    lw   t3, 12(t0)
    sw   t3, 12(t1)
    la   t0, xvec
    li   t1, AME_XBUF
    lw   t3, 0(t0)
    sw   t3, 0(t1)
    lw   t3, 4(t0)
    sw   t3, 4(t1)
    lw   t3, 8(t0)
    sw   t3, 8(t1)
    lw   t3, 12(t0)
    sw   t3, 12(t1)

    // ---- E1:非法 cfg(保留位)后重跑微 GEMV ----
    la   a0, s_e1
    jal  ra, print_str
    .word 0x6100000B                // cfg imm[11:10]=01 → ERR,配置不变
    jal  ra, micro_gemv
    // ---- E2:qcfg S=0 ----
    la   a0, s_e2
    jal  ra, print_str
    li   a0, 256
    li   a1, 0                      // rs2=0 → S=0 非法
    ame.qcfg 0, a0, a1
    jal  ra, micro_gemv
    // ---- E3:exe rs1[31:1]≠0 ----
    la   a0, s_e3
    jal  ra, print_str
    li   a0, 2
    ame.exe a0
    jal  ra, micro_gemv
    // ---- E4:ld.x rs1[31:10]≠0 ----
    la   a0, s_e4
    jal  ra, print_str
    li   a0, 0x400
    ame.ld.x a0
    jal  ra, micro_gemv
    // ---- E5:ld.w rs1[31:3]≠0 ----
    la   a0, s_e5
    jal  ra, print_str
    li   a0, 8
    ame.ld.w a0
    jal  ra, micro_gemv

    // ---- E6:st.y i=3(i≥N_eff)----
    la   a0, s_e6
    jal  ra, print_str
    li   a0, 0
    ame.ld.w a0
    ame.ld.x a0
    ame.exef a0
    ame.sync
    li   a0, 3
    ame.st.y a0, a1                 // i≥N_eff → 数据 0 + ERR
    mv   a0, a1
    jal  ra, print_hex8
    li   t5, 10
    jal  ra, txchar

    // ---- E7:合法微 GEMV ----
    la   a0, s_e7
    jal  ra, print_str
    jal  ra, micro_gemv
    // ---- E8:重装 + exe(无 exef)→ 2y ----
    la   a0, s_e8
    jal  ra, print_str
    jal  ra, micro_gemv2

    // ---- E9:契约 AME_IRQEN 偏移(窗口外)读 → KV CSR 别名 ----
    la   a0, s_e9
    jal  ra, print_str
    li   t0, 0x20003000
    lw   a1, 0xC4(t0)               // 契约偏移 +0x20C4 = KV 基址+0xC4
    mv   a0, a1
    jal  ra, print_hex8
    li   t5, 10
    jal  ra, txchar

    // ---- E10:lw 保留区 → INTC[8] ----
    la   a0, s_e10
    jal  ra, print_str
    li   t0, 0x00002000
    lw   t1, 0(t0)
    li   a0, 8
    jal  ra, chk_bit
    // ---- E11:sw BOOTROM(RO)→ INTC[8] ----
    la   a0, s_e11
    jal  ra, print_str
    li   t0, 0x00010000
    sw   t1, 0(t0)
    li   a0, 8
    jal  ra, chk_bit
    // ---- E12:lw 0x6000_0000 → INTC[8] ----
    la   a0, s_e12
    jal  ra, print_str
    li   t0, 0x60000000
    lw   t1, 0(t0)
    li   a0, 8
    jal  ra, chk_bit

    // ---- E13:DMA SRC 未对齐 → ERRCODE=1 ----
    la   a0, s_e13
    jal  ra, print_str
    li   a0, 0x00000002
    li   a1, 0x00000800
    li   a2, 1
    li   a3, 1
    jal  ra, dma_start
    jal  ra, dma_wait
    jal  ra, print_errcode
    // ---- E14:DMA SRC→保留区 → ERRCODE=2 ----
    la   a0, s_e14
    jal  ra, print_str
    li   a0, 0x00020000
    li   a1, 0x00000800
    li   a2, 1
    li   a3, 1
    jal  ra, dma_start
    jal  ra, dma_wait
    jal  ra, print_errcode

    // ---- E15:KV POS+COUNT 越界(IRQ_EN=1)→ INTC[7] ----
    la   a0, s_e15
    jal  ra, print_str
    li   t0, KV_BASE
    sw   zero, 4(t0)
    sw   zero, 8(t0)
    li   t1, 254
    sw   t1, 12(t0)                 // POS=254
    li   t1, 4
    sw   t1, 16(t0)                 // COUNT=4 → 254+4>256
    sw   zero, 20(t0)
    sw   zero, 36(t0)
    li   t1, 0x10B                  // MODE=3(READ_K)|IRQ_EN=1|GO → POS+COUNT 越界
    sw   t1, 0(t0)
    li   a0, 7
    jal  ra, chk_bit

halt:
    wfi
    j    halt

// ===========================================================================
// 子程序
// ===========================================================================
// micro_gemv:重新装载 tile 组 → exef(清 Y)→ sync → st.y0 打印 8 hex
micro_gemv:
    addi sp, sp, -8
    sw   ra, 4(sp)
    li   a0, 0
    ame.ld.w a0
    ame.ld.x a0
    ame.exef a0
    ame.sync
    li   a0, 0
    ame.st.y a0, a1
    mv   a0, a1
    jal  ra, print_hex8
    li   t5, 10
    jal  ra, txchar
    lw   ra, 4(sp)
    addi sp, sp, 8
    ret

// micro_gemv2:重装 → exe(保留 Y 累加)→ sync → st.y0 打印
micro_gemv2:
    addi sp, sp, -8
    sw   ra, 4(sp)
    li   a0, 0
    ame.ld.w a0
    ame.ld.x a0
    ame.exe a0
    ame.sync
    li   a0, 0
    ame.st.y a0, a1
    mv   a0, a1
    jal  ra, print_hex8
    li   t5, 10
    jal  ra, txchar
    lw   ra, 4(sp)
    addi sp, sp, 8
    ret

// chk_bit:a0 = INTC 位号 → 打印 '0'/'1' + 换行 + W1C
chk_bit:
    addi sp, sp, -8
    sw   ra, 4(sp)
    li   t0, INTC_BASE
    lw   t1, INTC_PEND_OFF(t0)
    srl  t2, t1, a0
    andi t2, t2, 1
    addi t5, t2, 48
    jal  ra, txchar
    li   t5, 10
    jal  ra, txchar
    li   t1, 1
    sll  t1, t1, a0
    sw   t1, INTC_CLEAR_OFF(t0)
    lw   ra, 4(sp)
    addi sp, sp, 8
    ret

// dma_start:a0=src a1=dst a2=xcnt a3=ycnt
dma_start:
    sw   a0, 0(s0)
    sw   a1, 4(s0)
    sw   a2, 8(s0)
    sw   a3, 12(s0)
    sw   zero, 16(s0)
    sw   zero, 20(s0)
    li   t1, 1
    sw   t1, 24(s0)
    ret

// dma_wait:等 DONE|ERR + W1C
dma_wait:
    lw   t1, DMA_STATUS_OFF(s0)
    srli t2, t1, 1
    andi t2, t2, 3
    beq  t2, zero, dma_wait
    li   t1, 6
    sw   t1, DMA_STATUS_OFF(s0)
    ret

// print_errcode:打印 DMA ERRCODE nibble + 换行
print_errcode:
    addi sp, sp, -8
    sw   ra, 4(sp)
    lw   t1, DMA_STATUS_OFF(s0)
    srli t1, t1, 4
    andi t1, t1, 15
    addi t5, t1, 48
    jal  ra, txchar
    li   t5, 10
    jal  ra, txchar
    li   t1, 6
    sw   t1, DMA_STATUS_OFF(s0)
    lw   ra, 4(sp)
    addi sp, sp, 8
    ret

// print_str:a0 = .asciz 指针
print_str:
    addi sp, sp, -8
    sw   ra, 4(sp)
    mv   t0, a0
ps_l:
    lbu  t5, 0(t0)
    beqz t5, ps_d
    jal  ra, txchar
    addi t0, t0, 1
    j    ps_l
ps_d:
    lw   ra, 4(sp)
    addi sp, sp, 8
    ret

// print_hex8:a0 = 32 位值 → 8 个小写 hex
print_hex8:
    addi sp, sp, -8
    sw   ra, 4(sp)
    li   t0, 8
    la   t1, hexdig
ph_l:
    addi t0, t0, -1
    slli t3, t0, 2
    srl  t2, a0, t3
    andi t2, t2, 15
    add  t2, t2, t1
    lbu  t5, 0(t2)
    jal  ra, txchar
    bnez t0, ph_l
    lw   ra, 4(sp)
    addi sp, sp, 8
    ret

txchar:
txf_wait:
    lw   t3, UART_STAT_OFF(s1)
    srli t3, t3, STAT_TX_FULL
    andi t3, t3, 1
    bne  t3, zero, txf_wait
    sw   t5, 0(s1)
    ret

// ---- 数据段 ----
.data
.align 2
wvec:   .byte 255, 2, 254, 1, 253, 0, 3, 255, 2, 254, 1, 253, 0, 3, 255, 2
xvec:   .byte 251, 0, 5, 255, 4, 254, 3, 253, 2, 252, 1, 251, 0, 5, 255, 4
s_e1:   .asciz "E1:"
s_e2:   .asciz "E2:"
s_e3:   .asciz "E3:"
s_e4:   .asciz "E4:"
s_e5:   .asciz "E5:"
s_e6:   .asciz "E6:"
s_e7:   .asciz "E7:"
s_e8:   .asciz "E8:"
s_e9:   .asciz "E9:"
s_e10:  .asciz "E10:"
s_e11:  .asciz "E11:"
s_e12:  .asciz "E12:"
s_e13:  .asciz "E13:"
s_e14:  .asciz "E14:"
s_e15:  .asciz "E15:"
.align 2
hexdig: .ascii "0123456789abcdef"
