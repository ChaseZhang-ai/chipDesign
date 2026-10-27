// -----------------------------------------------------------------------------
// verify_p3d_decode.s — P3D 全芯片单步 decode 微内核(3 prompt)
//
// 流程(每 prompt):
//   KV CLEAR(16 行×8 bank)→ prefill 8 pos APPEND_KV8 → L0: Wqkv GEMV(768)
//   → 新 K/V 行 APPEND_KV8(芯片计算结果)→ attention(QK 4 head + PV 4 head,
//   KV 经 kv_ctrl READ_K / READ_V+TRANSPOSE 直接进 WBUF)→ Wo → fc1 → fc2
//   → L1 同构 → lm_head GEMV(1024)→ st.y argmax → UART "T<p>=<hex>"。
//   最后跑异常注入(非法地址 / DMA 参数非法 / KV 参数非法)并写结果字。
//
// 数据口径:
//   * GEMV 的 x 输入取自 GOLDEN_SPEC §5 的量化边界张量(XMEM),Wqkv 输出经
//     st.q 取回后作为 QK 的 q 与 KV 的 k/v;PV 输出直接作为 Wo 的输入。
//   * L2 逐元素(LN/GELU/softmax)按 GOLDEN_SPEC v1.0 属 fp32 参考边界,本内核
//     消费其量化结果(§5 定义的边界张量),不重复实现浮点。
//   * 结果一律走 st.q/st.y;不访问 AME Y32/YQ/STATUS/CSR(裁决 A 后新偏移虽
//     已在 pkg 生效,本会话按任务纪律不使用)。
//   * ld.x 偏移场 9 位: K=1024 时 t>=32 的 x 片先 DMA 重载到 XBUF+0(现行规避)。
//   * bias 全零(模型 Linear bias=0),全部用 exef 起算,不依赖 Y32。
//
// 布局常量由 scripts/vfrd_golden.py 通过 --define 注入(PB_*_C / DUMP_*_C /
// YQ_*_C),保证 Python 场景生成与汇编单一来源。
// -----------------------------------------------------------------------------

.equ UART_BASE,   0x10002000
.equ UART_TXDATA, 0x00
.equ UART_DIV,    0x08
.equ UART_STAT,   0x10

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
.equ KV_SRC,      0x14
.equ KV_DST,      0x18
.equ KV_PITCH,    0x1C
.equ KV_STATUS,   0x20
.equ KV_SLICE,    0x24

.equ AME_WBUF,    0x20001000
.equ AME_XBUF,    0x20001400

.equ PB_BASE,     0x40500000
.equ PB_STRIDE,   0x20000
.equ DUMP_BASE,   0x40600000
.equ DUMP_STRIDE, 0x10000

.text
.globl _start
_start:
    la   sp, stack_top
    li   t0, UART_BASE
    addi t1, zero, 13
    sw   t1, UART_DIV(t0)
    li   t0, INTC_BASE
    sw   zero, INTC_EN(t0)
    li   s11, 0                   // prompt 序号(存内存,子程序会占用 s0-s11)
    la   t0, pidx_w
    sw   s11, 0(t0)

// ============================================================ prompt 主循环
prompt_loop:
    la   t0, pidx_w
    lw   s11, 0(t0)
    slli t1, s11, 17              // p * 0x20000
    li   t2, PB_BASE
    add  s0, t2, t1               // pbase
    slli t1, s11, 16              // p * 0x10000
    li   t2, DUMP_BASE
    add  s1, t2, t1               // dump
    la   t3, pbase_w
    sw   s0, 0(t3)
    la   t3, dump_w
    sw   s1, 0(t3)
    // 起始窗口标记 SCRATCH0 = 0xA0000000|p
    li   t0, SYS_BASE
    li   t1, 0xA0000000
    or   t1, t1, s11
    sw   t1, 0x10(t0)

    la   t0, pbase_w
    lw   s0, 0(t0)
    jal  ra, kv_prefill_append
    nop

    addi t0, zero, 0
    la   t1, layer_w
    sw   t0, 0(t1)
    jal  ra, do_layer
    nop

    addi t0, zero, 1
    la   t1, layer_w
    sw   t0, 0(t1)
    jal  ra, do_layer
    nop

    // ---- lm_head: 描述符 8(唯一需要 y_int32 转储的 GEMV)----
    la   t0, pbase_w
    lw   s0, 0(t0)
    addi a0, s0, PB_DESC_C + 256
    addi t1, zero, 1
    la   t2, y32_en_w
    sw   t1, 0(t2)
    jal  ra, gemv_w
    nop

    // ---- argmax(st.y, int32 域;与 golden §2.4 一致) ----
    la   t0, dump_w
    lw   s1, 0(t0)
    li   t1, DUMP_Y32_C
    add  a0, s1, t1
    // slot8 y32 偏移 = yq_off[8]*4 = 4608*4 = 0x4800
    li   t1, 0x4800
    add  a0, a0, t1
    addi a1, zero, 1024
    li   t0, ARGMAX_XIP_C
    jalr ra, t0, 0
    nop

    // ---- 输出 T<p>=xxx ----
    la   t0, pidx_w
    lw   s11, 0(t0)
    mv   a1, s11
    li   t0, PRINT_XIP_C
    jalr ra, t0, 0
    nop
    nop

    // 结束窗口标记 SCRATCH1 = 0xB0000000|p(子程序占用 s11 → 从内存重载)
    la   t0, pidx_w
    lw   s11, 0(t0)
    li   t0, SYS_BASE
    li   t1, 0xB0000000
    or   t1, t1, s11
    sw   t1, 0x14(t0)

    la   t0, pidx_w
    lw   s11, 0(t0)
    addi s11, s11, 1
    sw   s11, 0(t0)
    addi t0, zero, 3
    blt  s11, t0, prompt_loop
    nop

    // ======================================================== 异常注入(XIP)
    li   t0, 0x40001000
    jr   t0
halt:
    ebreak
    j    halt
    nop

// ============================================================================
// do_layer: Wqkv → KV append → attention → Wo → fc1 → fc2
//   输入: layer_w / pbase_w / dump_w(内存)
// ============================================================================
do_layer:
    addi sp, sp, -4
    sw   ra, 0(sp)
    la   t0, pbase_w
    lw   s0, 0(t0)
    la   t0, layer_w
    lw   t1, 0(t0)
    slli t1, t1, 7                // l*4 desc*32
    addi a0, s0, PB_DESC_C
    add  a0, a0, t1
    jal  ra, gemv_w               // Wqkv
    nop

    la   t0, pbase_w
    lw   s0, 0(t0)
    la   t0, dump_w
    lw   s1, 0(t0)
    la   t0, layer_w
    lw   s2, 0(t0)
    jal  ra, kv_append_new
    nop

    la   t0, pbase_w
    lw   s0, 0(t0)
    la   t0, dump_w
    lw   s1, 0(t0)
    la   t0, layer_w
    lw   s2, 0(t0)
    jal  ra, attention
    nop

    // Wo / fc1 / fc2(s3 会被 gemv_w 占用 → 索引存内存)
    addi s3, zero, 1
    la   t0, gidx_w
    sw   s3, 0(t0)
dl_gemv:
    la   t0, gidx_w
    lw   s3, 0(t0)
    la   t0, pbase_w
    lw   s0, 0(t0)
    la   t0, layer_w
    lw   t1, 0(t0)
    slli t1, t1, 7
    add  a0, s0, t1
    addi a0, a0, PB_DESC_C
    slli t2, s3, 5
    add  a0, a0, t2
    jal  ra, gemv_w
    nop
    la   t0, gidx_w
    lw   s3, 0(t0)
    addi s3, s3, 1
    sw   s3, 0(t0)
    addi t0, zero, 4
    blt  s3, t0, dl_gemv
    nop

    lw   ra, 0(sp)
    addi sp, sp, 4
    ret
    nop

// ============================================================================
// gemv_w: 通用权重 GEMV(N 为 16 的倍数,K ∈ {256,1024})
//   a0 -> 8 字描述符: w_base,N,K,x_addr,m_addr,s_addr,yq_addr,y32_addr
//   y32 只在描述符第 9 字 bit0=1 时转储(仅 lm_head)
// ============================================================================
gemv_w:
    addi sp, sp, -4
    sw   ra, 0(sp)
    lw   s1, 0(a0)                // w_base
    lw   s2, 4(a0)                // N
    lw   s3, 8(a0)                // K
    lw   s4, 12(a0)               // x
    lw   s5, 16(a0)               // M
    lw   s6, 20(a0)               // S
    lw   s7, 24(a0)               // yq
    lw   s8, 28(a0)               // y32

    li   s9, 0                    // n_base
    mv   s0, s1                   // w_base + n_base*K
    slli t0, s3, 4                // 16*K
    la   t1, step_w
    sw   t0, 0(t1)
    srli s10, s3, 4               // TS

nsl_loop:
    bge  s9, s2, gemv_done
    nop
    // 每个 N 片重载整条 x(t>=32 的 x 片重载会破坏 x[0:16])
    mv   a0, s4
    li   a1, AME_XBUF
    srli a2, s3, 2
    addi a3, zero, 1
    addi a4, zero, 0
    addi a5, zero, 0
    jal  ra, dma_copy_wait
    nop
    // qcfg ×16
    slli a0, s9, 2
    add  a0, s5, a0
    add  a1, s6, s9
    jal  ra, qcfg16
    nop
    ame.cfg 16, 16

    // 预取 tile 0
    mv   a0, s0
    li   a1, AME_WBUF
    addi a2, zero, 4
    addi a3, zero, 16
    mv   a4, s3
    addi a5, zero, 0
    jal  ra, dma_start
    nop

    li   s11, 0                   // t
tile_loop:
    jal  ra, wait_dma
    nop
    // K>512 且 t>=32:x 片重载到 XBUF+0
    addi t0, zero, 512
    blt  s3, t0, no_xload
    nop
    addi t0, zero, 32
    blt  s11, t0, no_xload
    nop
    slli t1, s11, 4
    add  a0, s4, t1
    li   a1, AME_XBUF
    addi a2, zero, 4
    addi a3, zero, 1
    addi a4, zero, 0
    addi a5, zero, 0
    jal  ra, dma_copy_wait
    nop
no_xload:
    // ld.w: region=t&3, tsel=t&1
    andi t0, s11, 3
    andi t1, s11, 1
    slli t1, t1, 2
    or   t0, t0, t1
    ame.ld.w t0
    // ld.x off
    addi t0, zero, 512
    blt  s3, t0, xoff_t
    nop
    addi t0, zero, 32
    blt  s11, t0, xoff_t
    nop
    addi t0, zero, 0
    j    xoff_go
    nop
xoff_t:
    slli t0, s11, 4
xoff_go:
    andi t1, s11, 1
    slli t1, t1, 9
    or   t0, t0, t1
    ame.ld.x t0
    // 预取 t+1
    addi t4, s11, 1
    bge  t4, s10, no_pref
    nop
    slli t5, t4, 4
    add  a0, s0, t5
    andi t5, t4, 3
    slli t5, t5, 8
    li   a1, AME_WBUF
    add  a1, a1, t5
    addi a2, zero, 4
    addi a3, zero, 16
    mv   a4, s3
    addi a5, zero, 0
    jal  ra, dma_start
    nop
no_pref:
    andi t0, s11, 1
    beq  s11, zero, do_exef
    nop
    ame.exe t0
    j    after_exe
    nop
do_exef:
    ame.exef t0
after_exe:
    addi s11, s11, 1
    blt  s11, s10, tile_loop
    nop

    ame.sync
    add  a0, s7, s9
    slli a1, s9, 2
    add  a1, s8, a1
    jal  ra, dump16
    nop

    addi s9, s9, 16
    la   t0, step_w
    lw   t0, 0(t0)
    add  s0, s0, t0
    j    nsl_loop
    nop

gemv_done:
    lw   ra, 0(sp)
    addi sp, sp, 4
    ret
    nop

// ============================================================================
qcfg16:
    // S 按字对齐读取(规避 MEMC 未对齐读:P3D-08)
    lw   t5, 0(a1)
    lw   t3, 0(a0)
    andi t4, t5, 255
    ori  t4, t4, 64
    ame.qcfg 0, t3, t4
    lw   t3, 4(a0)
    srli t4, t5, 8
    andi t4, t4, 255
    ori  t4, t4, 64
    ame.qcfg 1, t3, t4
    lw   t3, 8(a0)
    srli t4, t5, 16
    andi t4, t4, 255
    ori  t4, t4, 64
    ame.qcfg 2, t3, t4
    lw   t3, 12(a0)
    srli t4, t5, 24
    andi t4, t4, 255
    ori  t4, t4, 64
    ame.qcfg 3, t3, t4
    lw   t5, 4(a1)
    lw   t3, 16(a0)
    andi t4, t5, 255
    ori  t4, t4, 64
    ame.qcfg 4, t3, t4
    lw   t3, 20(a0)
    srli t4, t5, 8
    andi t4, t4, 255
    ori  t4, t4, 64
    ame.qcfg 5, t3, t4
    lw   t3, 24(a0)
    srli t4, t5, 16
    andi t4, t4, 255
    ori  t4, t4, 64
    ame.qcfg 6, t3, t4
    lw   t3, 28(a0)
    srli t4, t5, 24
    andi t4, t4, 255
    ori  t4, t4, 64
    ame.qcfg 7, t3, t4
    lw   t5, 8(a1)
    lw   t3, 32(a0)
    andi t4, t5, 255
    ori  t4, t4, 64
    ame.qcfg 8, t3, t4
    lw   t3, 36(a0)
    srli t4, t5, 8
    andi t4, t4, 255
    ori  t4, t4, 64
    ame.qcfg 9, t3, t4
    lw   t3, 40(a0)
    srli t4, t5, 16
    andi t4, t4, 255
    ori  t4, t4, 64
    ame.qcfg 10, t3, t4
    lw   t3, 44(a0)
    srli t4, t5, 24
    andi t4, t4, 255
    ori  t4, t4, 64
    ame.qcfg 11, t3, t4
    lw   t5, 12(a1)
    lw   t3, 48(a0)
    andi t4, t5, 255
    ori  t4, t4, 64
    ame.qcfg 12, t3, t4
    lw   t3, 52(a0)
    srli t4, t5, 8
    andi t4, t4, 255
    ori  t4, t4, 64
    ame.qcfg 13, t3, t4
    lw   t3, 56(a0)
    srli t4, t5, 16
    andi t4, t4, 255
    ori  t4, t4, 64
    ame.qcfg 14, t3, t4
    lw   t3, 60(a0)
    srli t4, t5, 24
    andi t4, t4, 255
    ori  t4, t4, 64
    ame.qcfg 15, t3, t4
    ret
    nop

dump16:
    ame.st.q 0, t0
    ame.st.q 1, t1
    ame.st.q 2, t2
    ame.st.q 3, t3
    andi t0, t0, 255
    andi t1, t1, 255
    slli t1, t1, 8
    or   t0, t0, t1
    andi t2, t2, 255
    slli t2, t2, 16
    or   t0, t0, t2
    andi t3, t3, 255
    slli t3, t3, 24
    or   t0, t0, t3
    sw   t0, 0(a0)
    ame.st.q 4, t0
    ame.st.q 5, t1
    ame.st.q 6, t2
    ame.st.q 7, t3
    andi t0, t0, 255
    andi t1, t1, 255
    slli t1, t1, 8
    or   t0, t0, t1
    andi t2, t2, 255
    slli t2, t2, 16
    or   t0, t0, t2
    andi t3, t3, 255
    slli t3, t3, 24
    or   t0, t0, t3
    sw   t0, 4(a0)
    ame.st.q 8, t0
    ame.st.q 9, t1
    ame.st.q 10, t2
    ame.st.q 11, t3
    andi t0, t0, 255
    andi t1, t1, 255
    slli t1, t1, 8
    or   t0, t0, t1
    andi t2, t2, 255
    slli t2, t2, 16
    or   t0, t0, t2
    andi t3, t3, 255
    slli t3, t3, 24
    or   t0, t0, t3
    sw   t0, 8(a0)
    ame.st.q 12, t0
    ame.st.q 13, t1
    ame.st.q 14, t2
    ame.st.q 15, t3
    andi t0, t0, 255
    andi t1, t1, 255
    slli t1, t1, 8
    or   t0, t0, t1
    andi t2, t2, 255
    slli t2, t2, 16
    or   t0, t0, t2
    andi t3, t3, 255
    slli t3, t3, 24
    or   t0, t0, t3
    sw   t0, 12(a0)

    la   t2, y32_en_w
    lw   t2, 0(t2)
    andi t2, t2, 1
    beq  t2, zero, dump16_done
    nop
    ame.st.y 0, t1
    sw   t1, 0(a1)
    ame.st.y 1, t1
    sw   t1, 4(a1)
    ame.st.y 2, t1
    sw   t1, 8(a1)
    ame.st.y 3, t1
    sw   t1, 12(a1)
    ame.st.y 4, t1
    sw   t1, 16(a1)
    ame.st.y 5, t1
    sw   t1, 20(a1)
    ame.st.y 6, t1
    sw   t1, 24(a1)
    ame.st.y 7, t1
    sw   t1, 28(a1)
    ame.st.y 8, t1
    sw   t1, 32(a1)
    ame.st.y 9, t1
    sw   t1, 36(a1)
    ame.st.y 10, t1
    sw   t1, 40(a1)
    ame.st.y 11, t1
    sw   t1, 44(a1)
    ame.st.y 12, t1
    sw   t1, 48(a1)
    ame.st.y 13, t1
    sw   t1, 52(a1)
    ame.st.y 14, t1
    sw   t1, 56(a1)
    ame.st.y 15, t1
    sw   t1, 60(a1)
dump16_done:
    ret
    nop

// ============================================================================
// attention: QK(4 head)+PV(4 head)
//   s0=pbase, s1=dump, s2=layer
// ============================================================================
attention:
    addi sp, sp, -4
    sw   ra, 0(sp)
    // qkv 输出(y_q)基址
    li   t0, YQ_L0_QKV_C
    beq  s2, zero, att_qkv_ok
    nop
    li   t0, YQ_L1_QKV_C
att_qkv_ok:
    add  t0, s1, t0
    li   t2, DUMP_YQ_C
    add  t0, t0, t2
    la   t1, qkv_yq_w
    sw   t0, 0(t1)

    li   s3, 0                    // head
head_loop:
    // ---- aux: QK slot j = layer*8 + head ----
    slli t0, s2, 3
    add  t0, t0, s3
    slli t1, t0, 4
    li   t2, PB_AUX_C
    add  t1, t1, t2
    add  t1, s0, t1
    lw   s4, 0(t1)                // M
    lw   s5, 4(t1)                // S
    lw   s6, 8(t1)                // yq
    lw   s7, 12(t1)               // y32

    // q_h -> XBUF
    la   t0, qkv_yq_w
    lw   t0, 0(t0)
    slli t1, s3, 6
    add  a0, t0, t1
    li   a1, AME_XBUF
    addi a2, zero, 16
    addi a3, zero, 1
    addi a4, zero, 0
    addi a5, zero, 0
    jal  ra, dma_copy_wait
    nop

    mv   a0, s4
    mv   a1, s5
    jal  ra, qcfg16
    nop
    ame.cfg 16, 16

    li   s8, 0                    // dt
qk_dt:
    mv   a0, s2
    mv   a1, s3
    mv   a2, s8
    li   a3, 3                    // READ_K
    addi a4, zero, 0
    jal  ra, kv_read
    nop
    andi t0, s8, 3
    andi t1, s8, 1
    slli t1, t1, 2
    or   t0, t0, t1
    ame.ld.w t0
    slli t0, s8, 4
    andi t1, s8, 1
    slli t1, t1, 9
    or   t0, t0, t1
    ame.ld.x t0
    andi t0, s8, 1
    beq  s8, zero, qk_exef
    nop
    ame.exe t0
    j    qk_after
    nop
qk_exef:
    ame.exef t0
qk_after:
    addi s8, s8, 1
    addi t0, zero, 4
    blt  s8, t0, qk_dt
    nop
    ame.sync
    mv   a0, s6
    mv   a1, s7
    jal  ra, dump16
    nop

    // ---- aux: PV slot j = layer*8 + 4 + head ----
    slli t0, s2, 3
    addi t0, t0, 4
    add  t0, t0, s3
    slli t1, t0, 4
    li   t2, PB_AUX_C
    add  t1, t1, t2
    add  t1, s0, t1
    lw   s4, 0(t1)
    lw   s5, 4(t1)
    lw   s6, 8(t1)
    lw   s7, 12(t1)

    // prob -> XBUF
    li   t0, PB_PROB_C
    slli t1, s2, 6
    add  t0, t0, t1
    slli t1, s3, 4
    add  t0, t0, t1
    add  a0, s0, t0
    li   a1, AME_XBUF
    addi a2, zero, 4
    addi a3, zero, 1
    addi a4, zero, 0
    addi a5, zero, 0
    jal  ra, dma_copy_wait
    nop

    mv   a0, s4
    mv   a1, s5
    jal  ra, qcfg16
    nop
    ame.cfg 16, 16

    li   s8, 0                    // ds
pv_ds:
    mv   a0, s2
    mv   a1, s3
    mv   a2, s8
    li   a3, 4                    // READ_V
    li   a4, 1                    // TRANSPOSE
    jal  ra, kv_read
    nop
    andi t0, s8, 3
    andi t1, s8, 1
    slli t1, t1, 2
    or   t0, t0, t1
    ame.ld.w t0
    andi t1, s8, 1
    slli t1, t1, 9
    ame.ld.x t1
    andi t0, s8, 1
    ame.exef t0
    ame.sync
    slli t0, s8, 4
    add  a0, s6, t0
    slli t0, s8, 6
    add  a1, s7, t0
    jal  ra, dump16
    nop
    addi s8, s8, 1
    addi t0, zero, 4
    blt  s8, t0, pv_ds
    nop

    addi s3, s3, 1
    addi t0, zero, 4
    blt  s3, t0, head_loop
    nop

    lw   ra, 0(sp)
    addi sp, sp, 4
    ret
    nop

// ============================================================================
// kv_read: a0=layer,a1=head,a2=slice_idx,a3=mode(3=K,4=V),a4=transpose
//   固定 POS=0, COUNT=16, DLEN=16, DST=WBUF+idx*256, DDOFF=idx*16
// ============================================================================
kv_read:
    li   t0, KV_BASE
    sw   a0, KV_LAYER(t0)
    sw   a1, KV_HEAD(t0)
    sw   zero, KV_POS(t0)
    addi t1, zero, 16
    sw   t1, KV_COUNT(t0)
    andi t1, a2, 3
    slli t1, t1, 8
    li   t2, AME_WBUF
    add  t1, t2, t1
    sw   t1, KV_DST(t0)
    slli t1, a2, 4
    ori  t1, t1, 0x400            // DLEN=16<<6
    sw   t1, KV_SLICE(t0)
    slli t2, a4, 4
    or   t2, t2, a3
    ori  t2, t2, 0x100            // GO
    sw   t2, KV_CTRL(t0)
    j    kv_wait
    nop

// kv_wait: t0=KV base;轮询 DONE|ERR(有界),W1C 两位;无 ERR 分支处理
kv_wait:
    li   t0, KV_BASE
    li   t3, 200000
kv_poll:
    lw   t1, KV_STATUS(t0)
    srli t2, t1, 1
    andi t2, t2, 1
    bne  t2, zero, kv_done
    nop
    srli t2, t1, 2
    andi t2, t2, 1
    bne  t2, zero, kv_done
    nop
    addi t3, t3, -1
    beq  t3, zero, kv_done
    nop
    j    kv_poll
    nop
kv_done:
    addi t2, zero, 6
    sw   t2, KV_STATUS(t0)
    ret
    nop

// ============================================================================
// kv_prefill_append: 8 pos × 2 layer,源 = pbase + PB_KVPRE + (l*8+p)*512
//   输入 s0=pbase
// ============================================================================
kv_prefill_append:
    addi sp, sp, -4
    sw   ra, 0(sp)
    li   s3, 0                    // p
pp_pos:
    li   s4, 0                    // l
pp_layer:
    slli t0, s4, 3
    add  t0, t0, s3
    slli t0, t0, 9
    li   t3, PB_KVPRE_C
    add  t0, t0, t3
    add  t0, s0, t0
    li   t1, KV_BASE
    sw   s4, KV_LAYER(t1)
    sw   s3, KV_POS(t1)
    sw   t0, KV_SRC(t1)
    li   t2, 0x102                // APPEND_KV8 + GO
    sw   t2, KV_CTRL(t1)
    jal  ra, kv_wait
    nop
    addi s4, s4, 1
    addi t0, zero, 2
    blt  s4, t0, pp_layer
    nop
    addi s3, s3, 1
    addi t0, zero, 8
    blt  s3, t0, pp_pos
    nop
    lw   ra, 0(sp)
    addi sp, sp, 4
    ret
    nop

// ============================================================================
// kv_append_new: 把 Wqkv 输出的 k/v(各 4×64B)拼成 [h][K,V] 512B(OC SRAM)
//   再 APPEND_KV8,POS=8。输入 s0=pbase,s1=dump,s2=layer
// ============================================================================
kv_append_new:
    addi sp, sp, -4
    sw   ra, 0(sp)
    li   t0, YQ_L0_QKV_C
    beq  s2, zero, kan_base
    nop
    li   t0, YQ_L1_QKV_C
kan_base:
    add  s5, s1, t0               // qkv yq base
    li   t2, DUMP_YQ_C
    add  s5, s5, t2
    li   s3, PB_KVNEW_C           // dest(XMEM,避开 KV 读 OCSRAM 与 CPU 取指并发)
    add  s3, s0, s3
    li   s4, 0                    // h
kan_h:
    // k: src = s5 + 256 + h*64, dst = s3 + h*128
    slli t0, s4, 6
    addi t1, s5, 256
    add  a0, t1, t0
    slli t1, s4, 7
    add  t2, s3, t1
    addi t3, zero, 0
kan_ck:
    lw   t4, 0(a0)
    sw   t4, 0(t2)
    addi a0, a0, 4
    addi t2, t2, 4
    addi t3, t3, 1
    addi t5, zero, 16
    blt  t3, t5, kan_ck
    nop
    // v: src = s5 + 512 + h*64, dst = stage + h*128 + 64
    slli t0, s4, 6
    addi t1, s5, 512
    add  a0, t1, t0
    slli t1, s4, 7
    add  t2, s3, t1
    addi t2, t2, 64
    addi t3, zero, 0
kan_cv:
    lw   t4, 0(a0)
    sw   t4, 0(t2)
    addi a0, a0, 4
    addi t2, t2, 4
    addi t3, t3, 1
    addi t5, zero, 16
    blt  t3, t5, kan_cv
    nop
    addi s4, s4, 1
    addi t0, zero, 4
    blt  s4, t0, kan_h
    nop
    // 读一次 stage 强制此前 store 落地
    lw   t0, 0(s3)
    li   t1, KV_BASE
    sw   s2, KV_LAYER(t1)
    addi t2, zero, 8
    sw   t2, KV_POS(t1)
    mv   t2, s3
    sw   t2, KV_SRC(t1)
    li   t2, 0x102
    sw   t2, KV_CTRL(t1)
    jal  ra, kv_wait
    nop
    lw   ra, 0(sp)
    addi sp, sp, 4
    ret
    nop

// ============================================================================
// DMA 原语
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
    addi sp, sp, -4
    sw   ra, 0(sp)
    jal  ra, dma_start
    nop
    jal  ra, wait_dma
    nop
    lw   ra, 0(sp)
    addi sp, sp, 4
    ret
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
// 异常注入:移到 XMEM XIP 冷路径(verify_p3d_exc.s @0x4000_1000),
// 不占 OC SRAM 程序预算;主程序跳转后由该程序写结果字并 ebreak。
// ============================================================================

// ============================================================================
// 数据段
// ============================================================================
.data
.align 2
pbase_w:  .word 0
dump_w:   .word 0
layer_w:  .word 0
step_w:   .word 0
y32_en_w: .word 0
qkv_yq_w: .word 0
pidx_w:   .word 0
gidx_w:   .word 0

.align 2
kvstage:  .space 512
          .space 64
stack_top:
