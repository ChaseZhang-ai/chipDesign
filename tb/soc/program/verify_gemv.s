// -----------------------------------------------------------------------------
// verify_gemv.s — P3B 微内核 A:表驱动 GEMV 循环(真实 decode 控制流)
//
// 控制流 = ARCH_SPEC §5 GEMV 宏:多层 for(job → N 切片 → K tile)、指针递增、
// cfg/qcfg 运行时重配(自改码槽)、WBUF region 乒乓 + tile 组乒乓、DMA 预取与
// exe 重叠、sync 后 st.q 逐通道取回。形状/指针全部来自 XMEM job 表 → 配置差分
// 零重汇编(M/N/K/kt/作业数参数化)。
//
// XMEM job 表(vrfb_golden.py 生成;word0=n_jobs,每 job 8 word):
//   {w_ptr, x_ptr, ms_ptr, out_ptr, K, N, kt, tag}
//   tag: bit[7:0]=打印字符(0=不打印);bit[8]=argmax 模式(st.y 流式取最大,
//        不落内存,例程返回 a0=最大索引)
// ms 块(每 N 切片 80B=20 word):M[16](u32) + RS2[16](u8 = S|ROUND_SEL<<6)
//
// 校验:①UART 流 = boot 头 + 每 job:tag + 8 位小写 hex 校验和 + '\n'
//       (csum = rotl32(csum,1) + (y_q8&0xFF),通道 n 升序,跨切片累计);
//       ②XMEM SCRATCH 输出区终态与 golden 逐字节(回归脚本比对)。
// 契约规避:无 bias(Y32 总线窗口越界,issues #4)→ 全部 exef 起片;不走总线
// 读 YQ/Y32(一律 st.q/st.y 指令路径)。
// -----------------------------------------------------------------------------

.equ UART_BASE, 0x10002000
.equ DMA_BASE,  0x20000000
.equ AME_WBUF,  0x20001000
.equ AME_XBUF,  0x20001400
.equ XMEM_BASE, 0x40000000

.equ UART_DIV_OFF,  0x08
.equ UART_STAT_OFF, 0x10
.equ STAT_TX_FULL,  18
.equ DMA_STATUS_OFF, 0x1C

.text
.globl _start
_start:
    li   sp, 0x00000C00             // 栈顶(OC SRAM 高处,远离 text/data)
    li   s0, DMA_BASE
    li   s1, UART_BASE
    li   t0, 13
    sw   t0, UART_DIV_OFF(s1)        // DIV=13(与 boot 一致,幂等)

    li   s2, XMEM_BASE
    lw   s3, 0(s2)                   // n_jobs
    addi s2, s2, 4
job_loop:
    beq  s3, zero, prog_done
    mv   a0, s2
    jal  ra, gemv_job
    addi s2, s2, 32
    addi s3, s3, -1
    j    job_loop

prog_done:
    wfi
    j    prog_done

// ===========================================================================
// gemv_job — 执行一个 GEMV 作业。入口 a0 = job 指针(XMEM)
// 辅助例程约定:dma_*/txchar 只破坏 t0-t2(dma)与 t3/t4(txchar)、a0-a5(实参);
// 本例程的 t3/t4/t5 与 a6/a7、s4-s11 跨调用存活。
// ===========================================================================
gemv_job:
    addi sp, sp, -48
    sw   ra, 44(sp)
    sw   a7, 40(sp)
    sw   a6, 36(sp)
    sw   s11, 32(sp)
    sw   s10, 28(sp)
    sw   s9, 24(sp)
    sw   s8, 20(sp)
    sw   s7, 16(sp)
    sw   s6, 12(sp)
    sw   s5, 8(sp)
    sw   s4, 4(sp)
    lw   s4, 0(a0)                  // w_ptr
    lw   s5, 4(a0)                  // x_ptr
    lw   s6, 8(a0)                  // ms_ptr
    lw   s7, 12(a0)                 // out_ptr
    lw   s8, 16(a0)                 // K
    lw   s9, 20(a0)                 // N
    lw   s10, 24(a0)                // kt
    lw   a7, 28(a0)                 // tag/flags
    li   s11, 0                     // s = 0(N 切片号)
    addi t0, s9, 15
    srli a6, t0, 4                  // a6 = NS(t 循环/prefetch 不碰 a6)
    la   t0, csum_var
    sw   zero, 0(t0)
    la   t0, bestv_var
    li   t1, 0x80000000
    sw   t1, 0(t0)
    la   t0, besti_var
    sw   zero, 0(t0)

    // ---- x 向量整条预载 XBUF(K ≤ 1024,一次即可;ld.x 按 t*kt 偏移分片) ----
    mv   a0, s5
    li   a1, AME_XBUF
    srli a2, s8, 2
    li   a3, 1
    jal  ra, dma_start
    jal  ra, dma_wait

// ---- 逐 N 切片 -----------------------------------------------------------
slice_loop:
    // n_eff = min(16, N - 16s) → a5(dma_start2 实参寄存器,预取段不复用)
    slli t0, s11, 4
    sub  t0, s9, t0
    li   t1, 16
    bge  t0, t1, neff_ok
    mv   a5, t0
    j    neff_set
neff_ok:
    li   a5, 16
neff_set:
    // cfg n_eff,kt —— 跳转表(cfg_tab;自改码在取指预取下不可靠)
    mv   t0, a5
    mv   t1, s10
    jal  ra, cfg_exec

    // ---- 本片 ms 块 DMA → SRAM,再 qcfg ×16 ----
    mv   a0, s6
    slli t1, s11, 6
    slli t2, s11, 4
    add  t1, t1, t2                 // + s*80
    add  a0, a0, t1
    la   a1, ms_buf
    li   a2, 20
    li   a3, 1
    jal  ra, dma_start
    jal  ra, dma_wait
    la   t0, ms_buf
    lw   a0, 0(t0)
    lbu  a1, 64(t0)
    ame.qcfg 0, a0, a1
    lw   a0, 4(t0)
    lbu  a1, 65(t0)
    ame.qcfg 1, a0, a1
    lw   a0, 8(t0)
    lbu  a1, 66(t0)
    ame.qcfg 2, a0, a1
    lw   a0, 12(t0)
    lbu  a1, 67(t0)
    ame.qcfg 3, a0, a1
    lw   a0, 16(t0)
    lbu  a1, 68(t0)
    ame.qcfg 4, a0, a1
    lw   a0, 20(t0)
    lbu  a1, 69(t0)
    ame.qcfg 5, a0, a1
    lw   a0, 24(t0)
    lbu  a1, 70(t0)
    ame.qcfg 6, a0, a1
    lw   a0, 28(t0)
    lbu  a1, 71(t0)
    ame.qcfg 7, a0, a1
    lw   a0, 32(t0)
    lbu  a1, 72(t0)
    ame.qcfg 8, a0, a1
    lw   a0, 36(t0)
    lbu  a1, 73(t0)
    ame.qcfg 9, a0, a1
    lw   a0, 40(t0)
    lbu  a1, 74(t0)
    ame.qcfg 10, a0, a1
    lw   a0, 44(t0)
    lbu  a1, 75(t0)
    ame.qcfg 11, a0, a1
    lw   a0, 48(t0)
    lbu  a1, 76(t0)
    ame.qcfg 12, a0, a1
    lw   a0, 52(t0)
    lbu  a1, 77(t0)
    ame.qcfg 13, a0, a1
    lw   a0, 56(t0)
    lbu  a1, 78(t0)
    ame.qcfg 14, a0, a1
    lw   a0, 60(t0)
    lbu  a1, 79(t0)
    ame.qcfg 15, a0, a1

    // ---- x 下半区恢复(P1BXB 修复 g24/ch16):K>512 时上一 N 切片的 t=32
    //      重装已把 x[512..) 覆盖到 XBUF[0..511],本片 tile0..31 需要
    //      x[0..511) → 每片开头把 x[0..512) 重新 DMA 到 XBUF+0 ----
    li   t1, 512
    ble  s8, t1, xrestore_done    // K ≤ 512:一次预载即覆盖全 K,无需恢复
    mv   a0, s5                   // x_ptr
    li   a1, AME_XBUF
    li   a2, 128                  // 512 B = 128 字
    li   a3, 1
    jal  ra, dma_start
    jal  ra, dma_wait
xrestore_done:

    // ---- K 片循环:TS = K/kt(t4),last = (s==NS-1)(t5),t 计数(t3) ----
    divu t4, s8, s10
    addi t0, s11, 1
    bge  t0, a6, last_yes
    li   t5, 0
    j    ts_ready
last_yes:
    li   t5, 1
ts_ready:
    li   t3, 0

    // 预取 tile(s,0)→ WBUF region0
    mv   a0, s4
    slli t1, s11, 4
    mul  t1, t1, s8
    add  a0, a0, t1
    li   a1, AME_WBUF
    srli a2, s10, 2
    li   a3, 16
    mv   a4, s8                     // SRCPITCH = K
    li   a5, 0                      // DSTPITCH = 0
    jal  ra, dma_start2

t_loop:
    jal  ra, dma_wait               // tile t 的 WBUF DMA 完成
    // XBUF 上半区重装:ld.x 的 off 仅 9 位(0..511),K>512 时在 t*kt==512 处
    // 把 x[512..K) 重新 DMA 到 XBUF[0..511](§3.4 回卷口径)
    mul  t1, t3, s10                // off = t*kt
    li   t2, 512
    bne  t1, t2, xno_reload
    mv   a0, s5
    addi a0, a0, 512
    li   a1, AME_XBUF
    srli a2, s8, 2
    addi a2, a2, -128
    li   a3, 1
    jal  ra, dma_start
    jal  ra, dma_wait
    mul  t1, t3, s10
xno_reload:
    andi t1, t1, 511                // off 9 位
    andi t2, t3, 1
    slli t2, t2, 9
    or   a0, t1, t2                 // sel = off | xsel<<9
    ame.ld.x a0
    andi t1, t3, 3                  // region = t%4
    andi t2, t3, 1
    slli t2, t2, 2
    or   a0, t1, t2                 // sel = region | tsel<<2
    ame.ld.w a0
    andi a0, t3, 1                  // tsel
    bnez t3, exe_norm
    ame.exef a0                     // 每个 N 切片的首 tile 清 Y(§5 GEMV 宏)
    j    prefetch
exe_norm:
    ame.exe a0                      // 背靠背 exe:忙时 CPU EX 级反压停等

prefetch:
    // 预取 tile(s,t+1) → WBUF region (t+1)%4;本片末 tile 不预取
    // (下片 tile0 由切片头预取,避免 DMA 在途吞掉 ms-DMA 寄存器写)
    addi t1, t3, 1
    bge  t1, t4, pf_none
    mv   t2, t1                     // t' = t+1
    mv   t1, s11                    // s' = s
pf_go:
    mv   a0, s4
    slli t0, t1, 4
    mul  t0, t0, s8
    add  a0, a0, t0                 // + s'*16*K
    mul  t0, t2, s10
    add  a0, a0, t0                 // + t'*kt
    addi t0, t3, 1
    andi t0, t0, 3
    slli t0, t0, 8
    li   a1, AME_WBUF
    add  a1, a1, t0                 // WBUF + region*256
    srli a2, s10, 2
    li   a3, 16
    mv   a4, s8
    li   a5, 0
    jal  ra, dma_start2
pf_none:
    addi t3, t3, 1
    blt  t3, t4, t_loop

    // ---- sync 后取回:argmax 模式(st.y)/普通模式(st.q) ----
    ame.sync
    slli t0, a7, 23                 // tag bit8 → bit31
    bltz t0, argmax_mode
    slli t1, s11, 4
    add  t1, s7, t1                 // out_ptr + s*16
    la   t2, csum_var
    lw   t2, 0(t2)
    li   t3, 0                      // i
    slli t4, s11, 4
    sub  t4, s9, t4
    li   t0, 16
    bge  t4, t0, stq_ne
    j    stq_go
stq_ne:
    li   t4, 16
stq_go:
stq_loop:
    mv   a0, t3
    ame.st.q a0, a1                 // a1 = sext8(requant_i(Y[i]))
    slli t5, t2, 1
    srli t0, t2, 31
    or   t5, t5, t0                 // rotl32(csum,1)
    andi t0, a1, 255
    add  t2, t5, t0
    sb   a1, 0(t1)
    addi t1, t1, 1
    addi t3, t3, 1
    blt  t3, t4, stq_loop
    la   t0, csum_var
    sw   t2, 0(t0)
    j    slice_next

argmax_mode:
    la   t2, bestv_var
    lw   t2, 0(t2)                  // best(signed)
    la   t3, besti_var
    lw   t3, 0(t3)
    li   t1, 0                      // i
    slli t4, s11, 4
    sub  t4, s9, t4
    li   t0, 16
    bge  t4, t0, amx_ne
    j    amx_go
amx_ne:
    li   t4, 16
amx_go:
amx_loop:
    mv   a0, t1
    ame.st.y a0, a1                 // a1 = Y[i](INT32)
    bge  t2, a1, amx_next
    mv   t2, a1
    mv   t3, t1
amx_next:
    addi t1, t1, 1
    blt  t1, t4, amx_loop
    la   t0, bestv_var
    sw   t2, 0(t0)
    la   t0, besti_var
    sw   t3, 0(t0)

slice_next:
    addi s11, s11, 1
    blt  s11, a6, slice_loop

    andi t0, a7, 255
    beqz t0, gj_tail
    mv   t5, a7
    andi t5, t5, 255
    jal  ra, txchar
    la   t0, csum_var
    lw   a0, 0(t0)
    jal  ra, print_hex8
    li   t5, 10
    jal  ra, txchar
gj_tail:
    slli t0, a7, 23
    bgez t0, gj_ret
    la   t0, besti_var
    lw   a0, 0(t0)
gj_ret:
    lw   ra, 44(sp)
    lw   a7, 40(sp)
    lw   a6, 36(sp)
    lw   s11, 32(sp)
    lw   s10, 28(sp)
    lw   s9, 24(sp)
    lw   s8, 20(sp)
    lw   s7, 16(sp)
    lw   s6, 12(sp)
    lw   s5, 8(sp)
    lw   s4, 4(sp)
    addi sp, sp, 48
    ret

// ===========================================================================
// 辅助例程
// ===========================================================================

// dma_start:a0=src a1=dst a2=xcnt a3=ycnt(pitch=0 紧凑)
dma_start:
    mv   a4, zero
    mv   a5, zero
    // 落入 dma_start2
// dma_start2:a4=SRCPITCH a5=DSTPITCH(0=紧凑)
dma_start2:
    sw   a0, 0(s0)
    sw   a1, 4(s0)
    sw   a2, 8(s0)
    sw   a3, 12(s0)
    sw   a4, 16(s0)
    sw   a5, 20(s0)
    li   t1, 1
    sw   t1, 24(s0)                  // GO
    ret

// dma_wait:等 DONE|ERR 并 W1C(§4.5:错误时不置 DONE,故两位一起等)
dma_wait:
    lw   t1, DMA_STATUS_OFF(s0)
    srli t2, t1, 1
    andi t2, t2, 3
    beq  t2, zero, dma_wait
    li   t1, 6
    sw   t1, DMA_STATUS_OFF(s0)      // W1C DONE|ERR
    ret

// txchar:t5 = 字节(等 STAT[18] TX_FULL=0)
txchar:
txf_wait:
    lw   t3, UART_STAT_OFF(s1)
    srli t3, t3, STAT_TX_FULL
    andi t3, t3, 1
    bne  t3, zero, txf_wait
    sw   t5, 0(s1)
    ret

// print_hex8:a0 = 32 位值 → 8 个小写 hex 字符
print_hex8:
    addi sp, sp, -8
    sw   ra, 4(sp)
    li   t0, 8
    la   t1, hexdig
ph_loop:
    addi t0, t0, -1
    slli t3, t0, 2
    srl  t2, a0, t3
    andi t2, t2, 15
    add  t2, t2, t1
    lbu  t5, 0(t2)
    jal  ra, txchar
    bnez t0, ph_loop
    lw   ra, 4(sp)
    addi sp, sp, 8
    ret

// ===========================================================================
// AME cfg / qcfg 跳转表(运行期形状/通道号分派;自改码在预取流水下不可靠)
// ===========================================================================
// cfg_exec:t0 = n_eff(1..16),t1 = kt(8/16) → 跳转执行对应字面 cfg
cfg_exec:
    addi sp, sp, -8
    sw   ra, 4(sp)
    addi t0, t0, -1
    slli t0, t0, 3
    li   t2, 8
    beq  t1, t2, ce_run
    addi t0, t0, 128
ce_run:
    la   t2, cfg_tab
    add  t0, t2, t0
    jalr ra, t0, 0                  // 表项执行 cfg 后 ret 回下一条
    lw   ra, 4(sp)
    addi sp, sp, 8
    ret

.align 2
cfg_tab:
    ame.cfg 1, 8
    ret
    ame.cfg 2, 8
    ret
    ame.cfg 3, 8
    ret
    ame.cfg 4, 8
    ret
    ame.cfg 5, 8
    ret
    ame.cfg 6, 8
    ret
    ame.cfg 7, 8
    ret
    ame.cfg 8, 8
    ret
    ame.cfg 9, 8
    ret
    ame.cfg 10, 8
    ret
    ame.cfg 11, 8
    ret
    ame.cfg 12, 8
    ret
    ame.cfg 13, 8
    ret
    ame.cfg 14, 8
    ret
    ame.cfg 15, 8
    ret
    ame.cfg 16, 8
    ret
    ame.cfg 1, 16
    ret
    ame.cfg 2, 16
    ret
    ame.cfg 3, 16
    ret
    ame.cfg 4, 16
    ret
    ame.cfg 5, 16
    ret
    ame.cfg 6, 16
    ret
    ame.cfg 7, 16
    ret
    ame.cfg 8, 16
    ret
    ame.cfg 9, 16
    ret
    ame.cfg 10, 16
    ret
    ame.cfg 11, 16
    ret
    ame.cfg 12, 16
    ret
    ame.cfg 13, 16
    ret
    ame.cfg 14, 16
    ret
    ame.cfg 15, 16
    ret
    ame.cfg 16, 16
    ret

qcfg_tab:
    ame.qcfg 0, t1, t2
    ret
    ame.qcfg 1, t1, t2
    ret
    ame.qcfg 2, t1, t2
    ret
    ame.qcfg 3, t1, t2
    ret
    ame.qcfg 4, t1, t2
    ret
    ame.qcfg 5, t1, t2
    ret
    ame.qcfg 6, t1, t2
    ret
    ame.qcfg 7, t1, t2
    ret
    ame.qcfg 8, t1, t2
    ret
    ame.qcfg 9, t1, t2
    ret
    ame.qcfg 10, t1, t2
    ret
    ame.qcfg 11, t1, t2
    ret
    ame.qcfg 12, t1, t2
    ret
    ame.qcfg 13, t1, t2
    ret
    ame.qcfg 14, t1, t2
    ret
    ame.qcfg 15, t1, t2
    ret

// ---- 数据段 ----
.data
.align 2
csum_var:  .word 0
bestv_var: .word 0
besti_var: .word 0
.align 2
ms_buf:    .space 80
.align 2
hexdig:    .ascii "0123456789abcdef"
