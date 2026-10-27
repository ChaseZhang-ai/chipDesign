// -----------------------------------------------------------------------------
// verify_p3d_loader.s — XMEM XIP 加载器(基址 0x4000_1000)
//
// boot ROM 打印后跳转到这里:用 CPU 逐字把 XMEM 0x4000_0000 处的 4 KB 主程序
// 复制到 OC SRAM 0x0,然后跳转执行。
// 不用 DMA:规避 P3D 发现的 DMA DONE 漏置/偶发 BUSY 不落问题(见 issues)。
// -----------------------------------------------------------------------------
.text
.globl _start
_start:
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
