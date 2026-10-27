// -----------------------------------------------------------------------------
// boot.s — AME-Chip boot ROM 程序(P2D;由 scripts/build_hex.py 汇编为 boot.hex)
//
// 复位向量 0x0001_0000(BOOT ROM 基址,ARCH_SPEC §2)。
//   BOOT_JUMP=0(默认): 打印 "AME-CHIP BOOT OK" 后 WFI 停机 —— smoke_1 用。
//   BOOT_JUMP=1:        打印后跳转 OC SRAM 0x0 —— smoke_2 用(TB 已把 demo 镜像
//                       预载进 OC SRAM;正式 boot 从 XMEM PROG 区拷贝属 §5.1/W3)。
// UART DIV=13 仅为仿真加速;硅上前两行可改 1042(115200@120MHz)。
// -----------------------------------------------------------------------------

.equ UART_BASE, 0x10002000
.equ UART_TXDATA_OFF, 0x00
.equ UART_DIV_OFF,    0x08
.equ UART_STAT_OFF,   0x10
.equ STAT_TX_FULL,    18        // STAT[18]

.text
.globl _start
_start:
    li   t0, UART_BASE
    li   t1, 13                  // 仿真波特率(DIV=13 bit/cyc)
    sw   t1, UART_DIV_OFF(t0)
    la   t1, msg

print_loop:
    lbu  t2, 0(t1)
    beq  t2, zero, boot_done
    // 等 TX FIFO 不满(STAT[18])
txfull_wait:
    lw   t3, UART_STAT_OFF(t0)
    srli t3, t3, STAT_TX_FULL
    andi t3, t3, 1
    bne  t3, zero, txfull_wait
    sw   t2, UART_TXDATA_OFF(t0)
    addi t1, t1, 1
    j    print_loop

boot_done:
.if BOOT_JUMP
    j    0x00000000              // 跳 OC SRAM 主程序
.endif
halt:
    wfi
    j    halt

msg:
    .asciz "AME-CHIP BOOT OK\n"
