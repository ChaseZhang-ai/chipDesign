// -----------------------------------------------------------------------------
// p4b2_decode.s — P4B2 裁剪 decode 场景主程序(P4A3 p4a3fin 门仿用)
//
// 由 boot ROM(P3D loader,"P3D BOOT OK" + 4KB 拷贝 + 跳转 0)装载执行。
// 场景 = 跳转标记 + 1 次 x 装载 DMA + 1 次权重流 DMA(1 个 GEMV tile)+
// tile-0 GEMV(exef/sync/st.q)+ UART 十六进制输出。
// 目的:门级(p4a3fin 6_final.v)vs RTL v0.3 同场景 UART 流逐字节一致性;
// 结果数据只需确定性,不需对 golden(GEMV 只算 tile 0,非完整 K)。
//
// 汇编:python3 scripts/build_hex.py asm p4b2_decode.s -o p4b2_prog.hex \
//        --base 0x0 --text-limit 4096 --data-limit 512
// 汇编语法/AME 语义与 tb/soc/verify_p3d_decode.s 同源(gemv_w tile-0 路径)。
// -----------------------------------------------------------------------------

.equ UART_BASE,    0x10002000
.equ UART_TXDATA,  0x00
.equ UART_DIV,     0x08
.equ UART_STAT,    0x10
.equ STAT_TX_FULL, 18

.equ INTC_BASE,    0x10001000
.equ INTC_EN,      0x00

.equ DMA_BASE,     0x20000000
.equ DMA_SRC,      0x00
.equ DMA_DST,      0x04
.equ DMA_XCNT,     0x08
.equ DMA_YCNT,     0x0C
.equ DMA_SP,       0x10
.equ DMA_DP,       0x14
.equ DMA_CTRL,     0x18
.equ DMA_STATUS,   0x1C

.equ AME_WBUF,     0x20001000
.equ AME_XBUF,     0x20001400

// 场景数据(XMEM 系统地址;生成器 tb/gate/p4b2_gen_scene.py 单一来源)
.equ XW_BASE,      0x40020000   // 权重 16 行 × 256B(行距 256B,每行前 16B 有效)
.equ XX_BASE,      0x40040000   // x 向量 256B
.equ XM_BASE,      0x40041000   // M 16 × word(全 1)

.text
.globl _start
_start:
    li   t0, UART_BASE
    li   t1, 13                  // 仿真波特率(DIV=13,与 boot/基线一致)
    sw   t1, UART_DIV(t0)
    li   t0, INTC_BASE
    sw   zero, INTC_EN(t0)

    // ---- 跳转/装载标记:能打出 'D' 即 loader 4KB 拷贝 + 跳转 0 成立 ----
    li   a0, 'D'
    jal  ra, putchar
    nop

    // ---- DMA #1:x 向量(256B = 64 word)→ XBUF ----
    li   a0, XX_BASE
    li   a1, AME_XBUF
    li   a2, 64                  // xcnt: word 数(K=256B)
    li   a3, 1
    li   a4, 0
    li   a5, 0
    jal  ra, dma_copy_wait
    nop

    // ---- DMA #2(权重流):16 行 × 4 word,行距 256B → WBUF region 0 ----
    li   a0, XW_BASE
    li   a1, AME_WBUF
    li   a2, 4                   // xcnt: 4 word = 16B = KT=16 权重
    li   a3, 16
    li   a4, 256                 // sp: 行距 256B(K=256)
    li   a5, 0
    jal  ra, dma_copy_wait
    nop

    // ---- qcfg ×16:M=XMEM(全 1),S=4,ROUND_SEL=1 ----
    li   t0, XM_BASE
    li   t4, 0x44
    lw   t3, 0(t0)
    ame.qcfg 0, t3, t4
    lw   t3, 4(t0)
    ame.qcfg 1, t3, t4
    lw   t3, 8(t0)
    ame.qcfg 2, t3, t4
    lw   t3, 12(t0)
    ame.qcfg 3, t3, t4
    lw   t3, 16(t0)
    ame.qcfg 4, t3, t4
    lw   t3, 20(t0)
    ame.qcfg 5, t3, t4
    lw   t3, 24(t0)
    ame.qcfg 6, t3, t4
    lw   t3, 28(t0)
    ame.qcfg 7, t3, t4
    lw   t3, 32(t0)
    ame.qcfg 8, t3, t4
    lw   t3, 36(t0)
    ame.qcfg 9, t3, t4
    lw   t3, 40(t0)
    ame.qcfg 10, t3, t4
    lw   t3, 44(t0)
    ame.qcfg 11, t3, t4
    lw   t3, 48(t0)
    ame.qcfg 12, t3, t4
    lw   t3, 52(t0)
    ame.qcfg 13, t3, t4
    lw   t3, 56(t0)
    ame.qcfg 14, t3, t4
    lw   t3, 60(t0)
    ame.qcfg 15, t3, t4

    // ---- 形状配置:16 输出 × KT=16 ----
    ame.cfg 16, 16

    // ---- tile 0:WBUF region0/tsel0,XBUF off0,xsel0,EXEF(清 Y 起算) ----
    li   t0, 0
    ame.ld.w t0
    ame.ld.x t0
    ame.exef t0
    ame.sync

    // ---- 结果:16 通道 yq,按字节十六进制打印 ----
    ame.st.q 0, t1
    andi a0, t1, 255
    jal  ra, puthex
    nop
    ame.st.q 1, t1
    andi a0, t1, 255
    jal  ra, puthex
    nop
    ame.st.q 2, t1
    andi a0, t1, 255
    jal  ra, puthex
    nop
    ame.st.q 3, t1
    andi a0, t1, 255
    jal  ra, puthex
    nop
    ame.st.q 4, t1
    andi a0, t1, 255
    jal  ra, puthex
    nop
    ame.st.q 5, t1
    andi a0, t1, 255
    jal  ra, puthex
    nop
    ame.st.q 6, t1
    andi a0, t1, 255
    jal  ra, puthex
    nop
    ame.st.q 7, t1
    andi a0, t1, 255
    jal  ra, puthex
    nop
    ame.st.q 8, t1
    andi a0, t1, 255
    jal  ra, puthex
    nop
    ame.st.q 9, t1
    andi a0, t1, 255
    jal  ra, puthex
    nop
    ame.st.q 10, t1
    andi a0, t1, 255
    jal  ra, puthex
    nop
    ame.st.q 11, t1
    andi a0, t1, 255
    jal  ra, puthex
    nop
    ame.st.q 12, t1
    andi a0, t1, 255
    jal  ra, puthex
    nop
    ame.st.q 13, t1
    andi a0, t1, 255
    jal  ra, puthex
    nop
    ame.st.q 14, t1
    andi a0, t1, 255
    jal  ra, puthex
    nop
    ame.st.q 15, t1
    andi a0, t1, 255
    jal  ra, puthex
    nop

    li   a0, 10                  // '\n'
    jal  ra, putchar
    nop
halt:
    wfi
    j    halt
    nop

// ============================================================================
// putchar:a0 = 字符;占用 t0/t3;不影响 a0
// ============================================================================
putchar:
    li   t0, UART_BASE
pc_wait:
    lw   t3, UART_STAT(t0)
    srli t3, t3, STAT_TX_FULL
    andi t3, t3, 1
    bne  t3, zero, pc_wait
    nop
    sw   a0, UART_TXDATA(t0)
    ret
    nop

// ============================================================================
// puthex:a0 = 字节(0..255),打两位小写十六进制;占用 s1/s2/t0/t1/t2/t3
// ============================================================================
puthex:
    mv   s1, ra
    andi s2, a0, 255
    srli t1, s2, 4
    andi t1, t1, 15
    la   t2, hex_tab
    add  t2, t2, t1
    lbu  a0, 0(t2)
    jal  ra, putchar
    nop
    andi t1, s2, 15
    la   t2, hex_tab
    add  t2, t2, t1
    lbu  a0, 0(t2)
    jal  ra, putchar
    nop
    jr   s1
    nop

// ============================================================================
// DMA 原语(同 verify_p3d_decode.s;xcnt/ycnt 单位=word,sp/dp 单位=字节)
// ============================================================================
dma_start:                        // a0 src,a1 dst,a2 xcnt,a3 ycnt,a4 sp,a5 dp
    li   t0, DMA_BASE
    sw   a0, DMA_SRC(t0)
    sw   a1, DMA_DST(t0)
    sw   a2, DMA_XCNT(t0)
    sw   a3, DMA_YCNT(t0)
    sw   a4, DMA_SP(t0)
    sw   a5, DMA_DP(t0)
    addi t1, zero, 1
    sw   t1, DMA_CTRL(t0)
    ret
    nop

dma_copy_wait:
    mv   s1, ra
    jal  ra, dma_start
    nop
    jal  ra, wait_dma
    nop
    jr   s1
    nop

wait_dma:                         // 轮询 DONE|ERR(有界),W1C
    li   t0, DMA_BASE
    li   t2, 200000
wd_poll:
    lw   t1, DMA_STATUS(t0)
    srli t3, t1, 1
    andi t3, t3, 1
    bne  t3, zero, wd_done
    nop
    srli t3, t1, 2
    andi t3, t3, 1
    bne  t3, zero, wd_done
    nop
    addi t2, t2, -1
    beq  t2, zero, wd_done
    nop
    j    wd_poll
    nop
wd_done:
    addi t3, zero, 6
    sw   t3, DMA_STATUS(t0)
    ret
    nop

// ============================================================================
// 数据段
// ============================================================================
.data
.align 2
hex_tab:
    .ascii "0123456789abcdef"
    .space 16                    // 对齐垫充
    .space 64                    // 局部栈垫(本程序实际不用栈)
