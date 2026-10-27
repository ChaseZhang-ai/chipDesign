// -----------------------------------------------------------------------------
// verify_p3d_exc.s — P3D 异常注入冷路径(XMEM XIP,基址 0x4000_1000)
//
// 主程序(OC SRAM)在 3 个 prompt 完成后 jr 到本镜像。检查三项并写结果字:
//   (1) CPU 访问保留区(0x1000_5000)→ DECERR:BUSERR sticky + INTC bit8
//   (2) DMA 源非 4 对齐 → ERR / ERRCODE=1 + IRQ(INTC bit3)
//   (3) KV POS+COUNT 越界 → ERR / ERRCODE=1(TOP 未接 KV 事件,查 STATUS)
// 全部有界轮询(不得死锁);通过写 0xE0C0DE01 到 0x406F_0000,否则写失败码。
// -----------------------------------------------------------------------------

.equ SYS_BASE,    0x10000000
.equ INTC_BASE,   0x10001000
.equ INTC_EN,     0x00
.equ INTC_PEND,   0x04
.equ INTC_CLEAR,  0x08

.equ DMA_BASE,    0x20000000
.equ DMA_SRC,     0x00
.equ DMA_DST,     0x04
.equ DMA_XCNT,    0x08
.equ DMA_YCNT,    0x0C
.equ DMA_SP,      0x10
.equ DMA_DP,      0x14
.equ DMA_CTRL,    0x18
.equ DMA_STATUS,  0x1C

.equ KV_BASE,     0x20003000
.equ KV_CTRL,     0x00
.equ KV_LAYER,    0x04
.equ KV_HEAD,     0x08
.equ KV_POS,      0x0C
.equ KV_COUNT,    0x10
.equ KV_STATUS,   0x20

.equ EXC_DUMP,    0x406F0000

.text
.globl _start
_start:
    la   sp, exc_stack_top
    li   s2, 0

    // ---- (1) 非法地址 ----
    li   t0, INTC_BASE
    li   t1, 0x108
    sw   t1, INTC_EN(t0)
    li   t1, 0x10005000
    lw   t2, 0(t1)
    bne  t2, zero, exc_f1
    nop
    li   t3, 1000
exc_bp:
    lw   t1, INTC_PEND(t0)
    srli t2, t1, 8
    andi t2, t2, 1
    bne  t2, zero, exc_bok
    nop
    addi t3, t3, -1
    beq  t3, zero, exc_f1
    nop
    j    exc_bp
    nop
exc_bok:
    li   t1, 0x100
    sw   t1, INTC_CLEAR(t0)

    // ---- (2) DMA 非对齐源 ----
    li   t0, DMA_BASE
    li   t1, 0x10
    sw   t1, DMA_CTRL(t0)
    li   t1, 0x40000001
    sw   t1, DMA_SRC(t0)
    sw   zero, DMA_DST(t0)
    li   t1, 1
    sw   t1, DMA_XCNT(t0)
    sw   t1, DMA_YCNT(t0)
    sw   zero, DMA_SP(t0)
    sw   zero, DMA_DP(t0)
    li   t1, 0x11
    sw   t1, DMA_CTRL(t0)
    li   t3, 1000
exc_dp:
    lw   t1, DMA_STATUS(t0)
    srli t2, t1, 2
    andi t2, t2, 1
    bne  t2, zero, exc_dok
    nop
    addi t3, t3, -1
    beq  t3, zero, exc_f2
    nop
    j    exc_dp
    nop
exc_dok:
    srli t2, t1, 4
    andi t2, t2, 15
    li   t4, 1
    bne  t2, t4, exc_f2
    nop
    li   t1, 6
    sw   t1, DMA_STATUS(t0)
    li   t0, INTC_BASE
    lw   t1, INTC_PEND(t0)
    srli t2, t1, 3
    andi t2, t2, 1
    beq  t2, zero, exc_f2
    nop
    li   t1, 0x08
    sw   t1, INTC_CLEAR(t0)

    // ---- (3) KV 参数越界 ----
    li   t0, KV_BASE
    li   t1, 0x0D
    sw   t1, KV_CTRL(t0)
    li   t1, 200
    sw   t1, KV_POS(t0)
    li   t1, 100
    sw   t1, KV_COUNT(t0)
    li   t1, 0x10D
    sw   t1, KV_CTRL(t0)
    li   t3, 1000
exc_kp:
    lw   t1, KV_STATUS(t0)
    srli t2, t1, 2
    andi t2, t2, 1
    bne  t2, zero, exc_kok
    nop
    addi t3, t3, -1
    beq  t3, zero, exc_f3
    nop
    j    exc_kp
    nop
exc_kok:
    srli t2, t1, 4
    andi t2, t2, 15
    li   t4, 1
    bne  t2, t4, exc_f3
    nop
    li   t1, 6
    sw   t1, KV_STATUS(t0)
    li   s2, 0xE0C0DE01
    j    exc_store
    nop

exc_f1:
    li   s2, 0xE0C0DE11
    j    exc_store
    nop
exc_f2:
    li   s2, 0xE0C0DE12
    j    exc_store
    nop
exc_f3:
    li   s2, 0xE0C0DE13
exc_store:
    li   t0, EXC_DUMP
    sw   s2, 0(t0)
    ebreak
    j    exc_store
    nop

// ============================================================================
// 打印例程(主程序经绝对地址调用;跨镜像调用用 jalr ra, t0, 0)
// ============================================================================
.globl print_token_xip
print_token_xip:                  // a0=token, a1=p -> "T<p>=<hex>\n"
    addi sp, sp, -4
    sw   ra, 0(sp)
    li   t3, 84
    jal  ra, txchar_xip
    nop
    addi t3, a1, 48
    jal  ra, txchar_xip
    nop
    li   t3, 61
    jal  ra, txchar_xip
    nop
    mv   t5, a0
    srli t3, t5, 8
    andi t3, t3, 15
    jal  ra, txhex_xip
    nop
    srli t3, t5, 4
    andi t3, t3, 15
    jal  ra, txhex_xip
    nop
    andi t3, t5, 15
    jal  ra, txhex_xip
    nop
    li   t3, 10
    jal  ra, txchar_xip
    nop
    lw   ra, 0(sp)
    addi sp, sp, 4
    ret
    nop

txhex_xip:
    li   t0, 10
    blt  t3, t0, txh_dec_xip
    nop
    addi t3, t3, 87
    j    txchar_xip
    nop
txh_dec_xip:
    addi t3, t3, 48
    j    txchar_xip
    nop

txchar_xip:
    li   t0, 0x10002000
tc_wait_xip:
    lw   t1, 0x10(t0)
    srli t1, t1, 18
    andi t1, t1, 1
    bne  t1, zero, tc_wait_xip
    nop
    sw   t3, 0(t0)
    ret
    nop

// ============================================================================
// argmax(跨镜像调用;a0=int32 数组, a1=个数 → a0=首个最大值下标)
// ============================================================================
.globl argmax_xip
argmax_xip:
    lw   t3, 0(a0)
    li   t4, 0
    li   t0, 1
am_loop_xip:
    bge  t0, a1, am_done_xip
    nop
    slli t1, t0, 2
    add  t1, a0, t1
    lw   t2, 0(t1)
    ble  t2, t3, am_skip_xip
    nop
    mv   t3, t2
    mv   t4, t0
am_skip_xip:
    addi t0, t0, 1
    j    am_loop_xip
    nop
am_done_xip:
    mv   a0, t4
    ret
    nop


.data
.align 2
    .space 32
exc_stack_top:
