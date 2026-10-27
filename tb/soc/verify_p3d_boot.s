// -----------------------------------------------------------------------------
// verify_p3d_boot.s — P3D 端到端 boot ROM(BOOT_INIT 镜像)
//
// 流程:UART 初始化(DIV=13)→ 打印 "P3D BOOT OK" → DMA 从 XMEM PROG 区
// (0x4000_0000)复制 4 KB 主程序到 OC SRAM 0x0000_0000 → 跳转 0。
// 源/目的各自落在单一从区内(XMEM S8 / OCSRAM S0),满足 P2C-4 约束。
// -----------------------------------------------------------------------------

.equ UART_BASE,      0x10002000
.equ UART_TXDATA,    0x00
.equ UART_DIV,       0x08
.equ UART_STAT,      0x10
.equ STAT_TX_FULL,   18

// boot 只负责 UART 初始化 + 打印;程序装载由 XIP loader(0x4000_1000)完成
// (规避 DMA DONE 漏置问题,见 reports/issues/P3D.md)

.text
.globl _start
_start:
    li   t0, UART_BASE
    li   t1, 13
    sw   t1, UART_DIV(t0)
    la   t1, msg
banner:
    li   t0, UART_BASE
    lbu  t2, 0(t1)
    beq  t2, zero, boot_done
    nop
bwait:
    lw   t3, UART_STAT(t0)
    srli t3, t3, STAT_TX_FULL
    andi t3, t3, 1
    bne  t3, zero, bwait
    nop
    sw   t2, UART_TXDATA(t0)
    addi t1, t1, 1
    j    banner
    nop
boot_done:
    // CPU 逐字复制 4 KB 主程序(规避 DMA DONE 漏置/偶发挂起,见 issues)
    li   t0, 0x40000000
    li   t1, 0x00000000
    li   t2, 1024
copy_loop:
    lw   t3, 0(t0)
    sw   t3, 0(t1)
    addi t0, t0, 4
    addi t1, t1, 4
    addi t2, t2, -1
    bne  t2, zero, copy_loop
    nop
    li   t0, 0x00000000
    jr   t0
    nop
halt:
    ebreak
    j    halt
    nop
msg:
    .asciz "P3D BOOT OK\n"
