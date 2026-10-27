// -----------------------------------------------------------------------------
// verify_decode.s — P3B 微内核 B:2 层 transformer 单步 decode 完整指令流
//
// 数据流(ARCH_SPEC §5.2 的指令流骨架;LN/RoPE/GELU/softmax 走 golden 查表,
// 全部 GEMV/KV/argmax 为真实芯片指令路径):
//   每 token:emb 行 DMA → 每层{QKV/O/fc1/fc2 GEMV(XMEM 作业描述符驱动,
//   O 层输入 = 芯片 PV 拼接输出,真实数据流)→ CPU 聚合 k/v 行 → kv_ctrl
//   APPEND_KV8 写回 → 每 head:score GEMV(KV READ_K 切片直拼 WBUF,
//   n_eff=ctx=9 余数片)→ p 查表 DMA → P·V 子 GEMV ×4(KV READ_V TRANSPOSE)}
//   → lm_head GEMV(tag bit8=argmax 模式,st.y 流式 INT32 取最大,§2.4)
//   → token 写 UART('T'+3 位小写 hex+'\n')。
//
// XMEM 指针/参数表(word 布局,vrfb_golden.py build_decode_config 对应):
//   0 magic 1 {layers|tokens<<8|ctx<<16} 20 x_emb 21+4l.. ln1/attn/ln2/gelu[l]
//   31+4l+h p_tab 39 scr_qkv 40 scr_kvrow 41 out_score 42 out_attn
//   46+4l+h ms_score 54+4l+h ms_pv 62 scr_emb 63=GEMV 描述符区基址
//   描述符区:每层 4 个 {w,ms,x,out,K,N,kt=16,tag=0} + lm(tag=0x100)
// 契约规避同 verify_gemv(exef 起片、st.q/st.y 取回、不走 YQ/Y32 总线)。
// -----------------------------------------------------------------------------

.equ UART_BASE, 0x10002000
.equ DMA_BASE,  0x20000000
.equ KV_BASE,   0x20003000
.equ AME_WBUF,  0x20001000
.equ AME_XBUF,  0x20001400
.equ XMEM_BASE, 0x40000000

.equ UART_DIV_OFF,  0x08
.equ UART_STAT_OFF, 0x10
.equ STAT_TX_FULL,  18
.equ DMA_STATUS_OFF, 0x1C
.equ KV_STATUS_OFF,  0x20

.text
.globl _start
_start:
    li   sp, 0x00000C00
    li   s0, DMA_BASE
    li   s1, UART_BASE                 // UART DIV=13 由 boot 设置
    li   s2, XMEM_BASE

    lw   t0, 4(s2)
    andi s3, t0, 255                // layers
    srli t1, t0, 8
    andi s4, t1, 255                // tokens
    li   s5, 9                      // ctx(设计常量,golden step ctx=9)
    li   s6, 0                      // token 计数

tok_loop:
    bge  s6, s4, dec_done
    la   t0, bestv_var              // argmax 累加器逐 token 复位
    li   t1, 0x80000000
    sw   t1, 0(t0)
    sw   zero, 4(t0)                // besti_var 紧随其后
    li   s7, 0                      // layer(emb 行拉取已并入 QKV DMA 链,查表口径)

layer_loop:
    bge  s7, s3, layer_done
    // ---- QKV / O / fc1 / fc2 GEMV(作业描述符驱动,l*4 起)
    //      主侧保护 s3-s10(gemv_job 用 s4-s11,无 callee-save) ----
    addi sp, sp, -24
    sw   s7, 20(sp)
    sw   s6, 16(sp)
    sw   s5, 12(sp)
    sw   s4, 8(sp)
    sw   s3, 4(sp)
    lw   t0, 252(s2)
    slli t1, s7, 7
    add  t0, t0, t1                 // 首描述符 = jobbase + l*128
    la   t1, jptr_var
    sw   t0, 0(t1)
    addi t0, t0, 128
    la   t1, jend_var
    sw   t0, 0(t1)                  // 结束指针(4 个描述符共 128B)
job4_l:
    la   t1, jptr_var
    lw   a0, 0(t1)
    jal  ra, gemv_job               // 破坏 t0/t1 → 循状态存于 .data
    la   t1, jptr_var
    lw   t0, 0(t1)
    addi t0, t0, 32
    sw   t0, 0(t1)
    la   t1, jend_var
    lw   t1, 0(t1)
    blt  t0, t1, job4_l
    lw   s7, 20(sp)
    lw   s6, 16(sp)
    lw   s5, 12(sp)
    lw   s4, 8(sp)
    lw   s3, 4(sp)
    addi sp, sp, 24

    // ---- KV 聚合:k/v 行 → [h][{K,V}] 8×64B(scr_kvrow;512B 单循环) ----
    lw   t0, 156(s2)
    addi t0, t0, 256                // K 基址(qkv+256;V = +256)
    lw   t1, 160(s2)
    li   t3, 0
kgl:
    andi t2, t3, 64                 // r&1 → 行内 V 半区(+256)
    slli t2, t2, 2
    andi t4, t3, 384                // P1BXB 修复:r>>1 行基址(t3[8:7]*64;
    srli t4, t4, 1                  //   原漏 t3[8] → head2/3 别名到 head0/1)
    add  t2, t2, t4
    andi t4, t3, 63
    add  t2, t2, t4                 // 源字节偏移(qkv+256 起)
    lbu  t4, 0(t2)
    add  t5, t1, t3
    sb   t4, 0(t5)
    addi t3, t3, 1
    li   t2, 512
    blt  t3, t2, kgl

    // ---- kv_ctrl APPEND_KV8 写回(POS=ctx-1) ----
    li   a0, 0x104                  // MODE=2|GO<<8
    mv   a1, s7
    addi a3, s5, -1                 // POS(HEAD/COUNT/SLICE 对 mode2 为 don't-care)
    lw   a5, 160(s2)                // SRC
    jal  ra, kv_go
    jal  ra, kv_wait

    // ---- 每 head:score GEMV + p 查表 + P·V ×4 ----
    li   s8, 0
attn_h:
    li   a0, 256                    // q_tab(l,h) → XBUF(16B)
    li   a1, AME_XBUF
    li   a2, 16
    jal  ra, dma_ptr
    li   a0, 184                    // ms_score[l][h] → ms_buf
    la   a1, ms_buf
    li   a2, 20
    jal  ra, dma_ptr
    // cfg n=ctx(本核 ctx 恒 9),kt=16 + qcfg ×ctx(全 dt 共用)
    ame.cfg 9, 16
    la   a0, ms_buf
    mv   a1, s5
    jal  ra, qcfg_n
    li   s9, 0                      // dt
sc_dt:
    li   a0, 0x103                  // kv READ_K(tile[n=pos][k=d],无转置)
    andi t0, s9, 3                  // region = dt%4
    mv   a5, t0
    slli t0, t0, 4                  // DDOFF = 16*region
    jal  ra, kv_rd
    andi t0, s9, 3                  // ld.w region|tsel<<2
    andi t1, s9, 1
    slli t1, t1, 2
    or   a0, t0, t1
    ame.ld.w a0
    slli t0, s9, 4                  // ld.x off=dt*16|xsel<<9
    andi t1, s9, 1
    slli t1, t1, 9
    or   a0, t0, t1
    ame.ld.x a0
    andi a0, s9, 1
    bnez s9, sc_exe
    ame.exef a0
    j    sc_adv
sc_exe:
    ame.exe a0
sc_adv:
    addi s9, s9, 1
    li   t0, 4
    blt  s9, t0, sc_dt
    ame.sync
    lw   a0, 164(s2)                // st.q ×ctx → out_score+(l*4+h)*16
    slli t1, s7, 4
    add  t1, t1, s8
    slli t1, t1, 4
    add  a0, a0, t1
    mv   a1, s5
    jal  ra, stq_bytes
    li   a0, 216                    // PV 块:p(16B)+pad(4B)+ms_pv(80B) → ms_buf
    la   a1, ms_buf
    li   a2, 25
    jal  ra, dma_ptr
    ame.cfg 16, 16                  // cfg + qcfg ×16(全 ds 共用)
    la   a0, ms_buf
    li   a1, 16
    jal  ra, qcfg_n
    li   s10, 0                     // ds
pv_ds:
    li   a0, 0x114                  // kv READ_V TRANSPOSE=1(tile[d'][pos])
    andi t0, s10, 3
    mv   a5, t0
    slli t0, t0, 4
    jal  ra, kv_rd
    andi a0, s10, 3                 // ld.w region=ds%4, tsel0
    ame.ld.w a0
    li   a0, 0                      // ld.x off0/xsel0
    ame.ld.x a0
    li   a0, 0                      // tsel0(与 ld.w/ld.x 同组)
    ame.exef a0                     // 每 ds 独立子 GEMV
    ame.sync
    lw   a0, 168(s2)                // st.q ×16 → out_attn+l*256+h*64+ds*16
    slli t1, s7, 8
    add  a0, a0, t1
    slli t1, s8, 6
    add  a0, a0, t1
    slli t1, s10, 4
    add  a0, a0, t1
    li   a1, 16
    jal  ra, stq_bytes
    addi s10, s10, 1
    li   t0, 4
    blt  s10, t0, pv_ds
    addi s8, s8, 1
    li   t0, 4
    blt  s8, t0, attn_h

    addi s7, s7, 1
    j    layer_loop

// ---- lm_head(argmax 模式描述符)+ 打印 token ----
layer_done:
    addi sp, sp, -20
    sw   s6, 16(sp)
    sw   s5, 12(sp)
    sw   s4, 8(sp)
    sw   s3, 4(sp)
    lw   a0, 252(s2)
    slli t1, s3, 7
    add  a0, a0, t1
    jal  ra, gemv_job               // a0 = argmax token(tag bit8 描述符)
    lw   s6, 16(sp)
    lw   s5, 12(sp)
    lw   s4, 8(sp)
    lw   s3, 4(sp)
    addi sp, sp, 20
    la    t2, hexdig
    li    t5, 84                    // 'T'
    jal   ra, txchar
    li    t1, 3
tp_l:
    addi  t1, t1, -1
    slli  t0, t1, 2
    srl   t0, a0, t0
    andi  t0, t0, 15
    add   t0, t0, t2
    lbu   t5, 0(t0)
    jal   ra, txchar
    bnez  t1, tp_l
    li    t5, 10
    jal   ra, txchar
    addi s6, s6, 1
    j    tok_loop

dec_done:
    wfi
    j    dec_done

// ===========================================================================
// gemv_job — 执行一个 GEMV 作业。入口 a0 = 作业描述符(XMEM,8 word)
// {w_ptr,x_ptr,ms_ptr,out_ptr,K,N,kt,tag};tag bit8=argmax 模式(st.y 流式
// 取最大,返回 a0=索引),bit[7:0]=0(不打印)。callee-saved(s0-s2 之外)。
// ===========================================================================
gemv_job:
    addi sp, sp, -8
    sw   ra, 4(sp)                  // 本体内 jal 会覆盖 ra
    // 寄存器占用:s4..s11(作业字段/循环),a7=tag;t3/t4/t5 跨 dma_wait 存活。
    // 调用方(main job4/lm)负责保护其自身 s3-s10。
    lw   s4, 0(a0)                  // w_ptr
    lw   s5, 4(a0)                  // x_ptr
    lw   s6, 8(a0)                  // ms_ptr
    lw   s7, 12(a0)                 // out_ptr
    lw   s8, 16(a0)                 // K
    lw   s9, 20(a0)                 // N
    lw   a7, 28(a0)                 // tag/flags(kt 恒 16,无需读)
    li   s11, 0
    srli a6, s9, 4                  // NS(N%16==0)

    mv   a0, s5                     // x 整条预载 XBUF
    li   a1, AME_XBUF
    srli a2, s8, 2
    li   a3, 1
    jal  ra, dma_start
    jal  ra, dma_wait

slice_loop:
    ame.cfg 16, 16                  // 本核 job 恒 N%16==0、kt=16
    mv   a0, s6                     // ms 切片块 DMA → SRAM
    li   t1, 80
    mul  t1, s11, t1
    add  a0, a0, t1
    la   a1, ms_buf
    li   a2, 20
    li   a3, 1
    jal  ra, dma_start
    jal  ra, dma_wait
    la   a0, ms_buf
    li   a1, 16
    jal  ra, qcfg_n

    srli t4, s8, 4                  // TS = K/16(t4)/last(t5)/t(t3) 跨调用存活
    addi t0, s11, 1
    bge  t0, a6, last_yes
    li   t5, 0
    j    ts_ready
last_yes:
    li   t5, 1
ts_ready:
    li   t3, 0
    mv   a0, s4                     // 预取 tile(s,0)
    slli t1, s11, 4
    mul  t1, t1, s8
    add  a0, a0, t1
    li   a1, AME_WBUF
    li   a2, 4
    li   a3, 16
    mv   a4, s8
    li   a5, 0
    jal  ra, dma_start2

t_loop:
    jal  ra, dma_wait
    slli t1, t3, 4                  // off = t*16(先算;与 verify_gemv 同序)
    // XBUF 上半区重装(off 仅 9 位;K=1024 时 t==32 处重装上半)
    li   t2, 32
    bne  t3, t2, xno_reload
    mv   a0, s5
    addi a0, a0, 512
    li   a1, AME_XBUF
    srli a2, s8, 2
    addi a2, a2, -128
    li   a3, 1
    jal  ra, dma_start
    jal  ra, dma_wait
    slli t1, t3, 4                  // dma_wait 破坏 t1,重算
xno_reload:
    andi t1, t1, 511
    andi t2, t3, 1
    slli t2, t2, 9
    or   a0, t1, t2
    ame.ld.x a0
    andi t1, t3, 3
    andi t2, t3, 1
    slli t2, t2, 2
    or   a0, t1, t2
    ame.ld.w a0
    andi a0, t3, 1
    bnez t3, exe_norm
    ame.exef a0                     // 每个 N 切片的首 tile 清 Y(§5 GEMV 宏)
    j    prefetch
exe_norm:
    ame.exe a0
prefetch:
    addi t1, t3, 1
    bge  t1, t4, pf_none            // 末 tile 不预取(下片 tile0 由切片头预取)
    mv   a0, s4
    slli t0, s11, 4
    mul  t0, t0, s8
    add  a0, a0, t0
    slli t0, t1, 4                  // off = t*kt(16)
    add  a0, a0, t0
    andi t0, t1, 3
    slli t0, t0, 8
    li   a1, AME_WBUF
    add  a1, a1, t0
    li   a2, 4                      // xcnt = kt/4 = 4 字
    li   a3, 16
    mv   a4, s8
    li   a5, 0
    jal  ra, dma_start2
pf_none:
    addi t3, t3, 1
    blt  t3, t4, t_loop

    ame.sync
    slli t0, a7, 23
    bltz t0, argmax_mode
    slli t0, s11, 4
    mv   a0, s7
    add  a0, a0, t0
    li   a1, 16
    jal  ra, stq_bytes
    j    slice_next

argmax_mode:
    la   t2, bestv_var              // st.y ×n_eff 流式取最大(INT32 域)
    lw   t3, 4(t2)                  // besti(紧随 bestv)
    lw   t2, 0(t2)
    li   t1, 0
    li   t4, 16                     // argmax 仅 lm(N%16==0,恒 16 通道)
amx_loop:
    mv   a0, t1
    ame.st.y a0, a1
    bge  t2, a1, amx_next
    mv   t2, a1
    slli t3, s11, 4                // besti = slice*16 + 通道号(全局索引)
    add  t3, t3, t1
amx_next:
    addi t1, t1, 1
    blt  t1, t4, amx_loop
    la   t0, bestv_var
    sw   t2, 0(t0)
    sw   t3, 4(t0)                  // besti_var

slice_next:
    addi s11, s11, 1
    blt  s11, a6, slice_loop

gj_tail:
    slli t0, a7, 23
    bgez t0, gj_ret
    la   t0, besti_var
    lw   a0, 0(t0)
gj_ret:
    lw   ra, 4(sp)
    addi sp, sp, 8
    ret

// ===========================================================================
// 辅助例程(破坏面:t0-t2/t4/t5、a0-a6;txchar 另用 t3)
// ===========================================================================

// qcfg_n:a0 = ms 块基址,a1 = 通道数(≤16)。通道号在 rd 立即数,运行期经
// qcfg_tab 跳转表分派(自改码在取指预取下不可靠);M→x6,RS2→x7。
qcfg_n:
    mv   a3, ra                     // P1BXB:ra 存 a3 免栈帧(表项 ret 经 ra 返回,
                                    // a3 全程不被 jalr/表项触碰)
    addi a2, a0, 64                 // P1BXB 修复:S 表按字节步进(原 64(t4) 随
                                    // M 指针 +4 步进,通道 ≥4 读到块外残留,
                                    // qcfg 非法/置 0 → SCR ch4..15 requant 错)
    la   t0, qcfg_tab
    li   t5, 0
qc_loop:
    lw   t1, 0(a0)                  // x6 = M(a0 = M 字指针)
    lbu  t2, 0(a2)                  // x7 = S|ROUND<<6
    slli t3, t5, 3
    add  a4, t0, t3
    jalr ra, a4, 0                  // 表项:ame.qcfg i, x6, x7; ret
    addi a0, a0, 4
    addi a2, a2, 1
    addi t5, t5, 1
    blt  t5, a1, qc_loop
    jr   a3                         // 返回(原 ra)

// kv_rd:attention 读辅助(约定:s7=LAYER,s8=HEAD,s5=COUNT(ctx))
//       a0=CTRL,t0=DDOFF(已移位),a5=region → 拼 kv_go 参数并 GO
kv_rd:
    mv   a1, s7                     // LAYER
    mv   a2, s8                     // HEAD
    mv   a4, s5                     // COUNT
    li   a3, 0                      // POS=0
    li   t1, AME_WBUF
    slli t2, a5, 8
    add  a5, t1, t2                 // DST=WBUF+region*256
    li   t1, 512                    // DLEN=16<<5;PITCH 寄存器恒 16
    or   a6, t0, t1
    // 落入 kv_go
kv_go:
    li   t0, KV_BASE
    sw   a1, 4(t0)
    sw   a2, 8(t0)
    sw   a3, 12(t0)
    sw   a4, 16(t0)
    sw   a5, 20(t0)                 // SRC @0x14(APPEND 源)
    sw   a5, 24(t0)                 // DST @0x18(READ 目的)
    sw   a6, 36(t0)                 // SLICE @0x24
    sw   a0, 0(t0)                  // CTRL(GO)
    // 落入 kv_wait
kv_wait:
    li   t0, KV_BASE
kvw_l:
    lw   t1, KV_STATUS_OFF(t0)
    srli t2, t1, 1
    andi t2, t2, 3
    beq  t2, zero, kvw_l
    li   t1, 6
    sw   t1, KV_STATUS_OFF(t0)
    ret

// dma_ptr:a0 = 表字偏移基(184=ms_score / 216=PV 块),a1 = 目的,a2 = 字数
//         → 取表项指针(+(l*4+h)*4)后发紧凑 DMA
dma_ptr:
    slli t0, s7, 4
    add  t0, t0, s8
    slli t0, t0, 2
    add  a0, a0, t0
    add  a0, s2, a0
    lw   a0, 0(a0)
    li   a3, 1
    j    dma_start

// stq_bytes:a0=目的字节指针 a1=通道数 → st.q ×count 落内存
stq_bytes:
    li   t2, 0
sb_l:
    mv   a2, t2
    ame.st.q a2, a3
    sb   a3, 0(a0)
    addi a0, a0, 1
    addi t2, t2, 1
    blt  t2, a1, sb_l
    ret

// dma_start:a0=src a1=dst a2=xcnt a3=ycnt(pitch=0 紧凑)
dma_start:
    mv   a4, zero
    mv   a5, zero
dma_start2:                          // a4=SRCPITCH a5=DSTPITCH(0=紧凑)
    sw   a0, 0(s0)
    sw   a1, 4(s0)
    sw   a2, 8(s0)
    sw   a3, 12(s0)
    sw   a4, 16(s0)
    sw   a5, 20(s0)
    li   t1, 1
    sw   t1, 24(s0)
    ret

dma_wait:
    lw   t1, DMA_STATUS_OFF(s0)
    srli t2, t1, 1
    andi t2, t2, 3
    beq  t2, zero, dma_wait
    li   t1, 6
    sw   t1, DMA_STATUS_OFF(s0)
    ret

txchar:                              // t5 = 字节(等 STAT[18] TX_FULL=0)
txf_wait:
    lw   t3, UART_STAT_OFF(s1)
    srli t3, t3, STAT_TX_FULL
    andi t3, t3, 1
    bne  t3, zero, txf_wait
    sw   t5, 0(s1)
    ret


// ---- AME qcfg 通道跳转表(rd=0..15) ----
.align 2
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
jptr_var:  .word 0
jend_var:  .word 0
bestv_var: .word 0
besti_var: .word 0
.align 2
ms_buf:    .space 100
.align 2
hexdig:    .ascii "0123456789abcdef"
