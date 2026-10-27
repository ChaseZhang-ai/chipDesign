// P3D 异常注入专用主程序:直接跳 XIP 异常路径(不跑 decode 控制流)
.text
.globl _start
_start:
    li   t0, 0x40001000
    jr   t0
    nop
halt:
    ebreak
    j    halt
    nop
