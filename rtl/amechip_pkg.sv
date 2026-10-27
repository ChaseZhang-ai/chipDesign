
`ifndef _AMECHIP_PKG_SV
 `define _AMECHIP_PKG_SV

package amechip_pkg;

  localparam int unsigned XLEN     = 32;  // RV32
  localparam int unsigned AXI_AW   = 32;  // AXI4-Lite 地址宽
  localparam int unsigned AXI_DW   = 32;  // AXI4-Lite 数据宽
  localparam int unsigned AXI_STRB = AXI_DW/8;

  typedef logic [XLEN-1:0]     xlen_t;
  typedef logic [AXI_AW-1:0]   axi_addr_t;
  typedef logic [AXI_DW-1:0]   axi_data_t;
  typedef logic [AXI_STRB-1:0] axi_strb_t;

  localparam logic [6:0] AME_OPCODE = 7'h0B; // @ISA:AME_OPCODE

  localparam logic [2:0] AME_F3_CFG = 3'h0;  // @ISA:AME_F3_CFG
  localparam logic [2:0] AME_F3_QCFG = 3'h1; // @ISA:AME_F3_QCFG
  localparam logic [2:0] AME_F3_LDW  = 3'h2; // @ISA:AME_F3_LDW
  localparam logic [2:0] AME_F3_LDX  = 3'h3; // @ISA:AME_F3_LDX
  localparam logic [2:0] AME_F3_EXE  = 3'h4; // @ISA:AME_F3_EXE
  localparam logic [2:0] AME_F3_STY  = 3'h5; // @ISA:AME_F3_STY
  localparam logic [2:0] AME_F3_STQ  = 3'h6; // @ISA:AME_F3_STQ
  localparam logic [2:0] AME_F3_SYNC = 3'h7; // @ISA:AME_F3_SYNC

  localparam logic [6:0] AME_F7_QCFG = 7'h01; // @ISA:AME_F7_QCFG
  localparam logic [6:0] AME_F7_LDW  = 7'h02; // @ISA:AME_F7_LDW
  localparam logic [6:0] AME_F7_LDX  = 7'h03; // @ISA:AME_F7_LDX
  localparam logic [6:0] AME_F7_EXE  = 7'h04; // @ISA:AME_F7_EXE
  localparam logic [6:0] AME_F7_EXEF = 7'h05; // @ISA:AME_F7_EXEF
  localparam logic [6:0] AME_F7_STY  = 7'h06; // @ISA:AME_F7_STY
  localparam logic [6:0] AME_F7_STQ  = 7'h07; // @ISA:AME_F7_STQ
  localparam logic [6:0] AME_F7_SYNC = 7'h08; // @ISA:AME_F7_SYNC

  localparam int unsigned CFG_N_EFF_OFF = 0;  // imm[4:0]
  localparam int unsigned CFG_KT_OFF    = 5;  // imm[9:5]
  localparam int unsigned CFG_RSVD_OFF  = 10; // imm[11:10] 必须 00
  localparam int unsigned QCFG_S_OFF    = 0;  // rs2[5:0]
  localparam int unsigned QCFG_S_W      = 6;  // 1..63(GOLDEN 禁止 0)
  localparam int unsigned QCFG_ROUND_OFF = 6; // rs2[6]
  localparam int unsigned RQ_M_W        = 32; // 无符号乘数(int64 语义乘法)
  localparam int unsigned RQ_ENTRIES    = 32; // per-channel 参数表项数
  localparam int unsigned LDW_REGION_OFF = 0; // rs1[1:0] WBUF region
  localparam int unsigned LDW_REGION_W   = 2;
  localparam int unsigned LDW_TSEL_OFF   = 2; // rs1[2] tile 组
  localparam int unsigned LDX_OFF_OFF   = 0;  // rs1[8:0] XBUF 字节偏移
  localparam int unsigned LDX_OFF_W     = 9;
  localparam int unsigned LDX_XSEL_OFF  = 9;  // rs1[9] x 组
  localparam int unsigned EXE_TSEL_OFF  = 0;  // rs1[0]
  localparam int unsigned ST_IDX_OFF    = 0;  // rs1[4:0] Y 索引
  localparam int unsigned ST_IDX_W      = 5;

  localparam int unsigned AME_M_DEF     = 16; // K-tile 深度
  localparam int unsigned AME_N_DEF     = 16; // 并行输出路数(MAC lane)
  localparam int unsigned AME_TSETS     = 2;  // tile/x 寄存器组(固定)
  localparam int unsigned WBUF_TILES    = 4;
  localparam int unsigned WBUF_DEPTH    = WBUF_TILES * AME_M_DEF * AME_N_DEF; // 1024 B
  localparam int unsigned XBUF_DEPTH    = 1024;                               // B

  localparam int unsigned RQ_S_MIN      = 1;  // S ≥ 1(S=0 被拒绝)

  localparam logic [31:0] A_OCSRAM_BASE  = 32'h0000_0000; // @MAP:OCSRAM_BASE
  localparam logic [31:0] A_OCSRAM_END   = 32'h0000_0FFF; // @MAP:OCSRAM_END
  localparam logic [31:0] A_RSV1_BASE    = 32'h0000_1000; // @MAP:RSV1_BASE
  localparam logic [31:0] A_RSV1_END     = 32'h0000_FFFF; // @MAP:RSV1_END
  localparam logic [31:0] A_BOOTROM_BASE = 32'h0001_0000; // @MAP:BOOTROM_BASE
  localparam logic [31:0] A_BOOTROM_END  = 32'h0001_07FF; // @MAP:BOOTROM_END
  localparam logic [31:0] A_RSV2_BASE    = 32'h0001_0800; // @MAP:RSV2_BASE
  localparam logic [31:0] A_RSV2_END     = 32'h0FFF_FFFF; // @MAP:RSV2_END
  localparam logic [31:0] A_SYS_BASE     = 32'h1000_0000; // @MAP:SYS_BASE
  localparam logic [31:0] A_SYS_END      = 32'h1000_0FFF; // @MAP:SYS_END
  localparam logic [31:0] A_INTC_BASE    = 32'h1000_1000; // @MAP:INTC_BASE
  localparam logic [31:0] A_INTC_END     = 32'h1000_1FFF; // @MAP:INTC_END
  localparam logic [31:0] A_UART_BASE    = 32'h1000_2000; // @MAP:UART_BASE
  localparam logic [31:0] A_UART_END     = 32'h1000_2FFF; // @MAP:UART_END
  localparam logic [31:0] A_RSV3_BASE    = 32'h1000_3000; // @MAP:RSV3_BASE
  localparam logic [31:0] A_RSV3_END     = 32'h1FFF_FFFF; // @MAP:RSV3_END
  localparam logic [31:0] A_DMA_BASE     = 32'h2000_0000; // @MAP:DMA_BASE
  localparam logic [31:0] A_DMA_END      = 32'h2000_0FFF; // @MAP:DMA_END
  localparam logic [31:0] A_AME_BASE     = 32'h2000_1000; // @MAP:AME_BASE
  localparam logic [31:0] A_AME_END      = 32'h2000_2FFF; // @MAP:AME_END
  localparam logic [31:0] A_KV_BASE      = 32'h2000_3000; // @MAP:KV_BASE
  localparam logic [31:0] A_KV_END       = 32'h2000_3FFF; // @MAP:KV_END
  localparam logic [31:0] A_RSV4_BASE    = 32'h2000_4000; // @MAP:RSV4_BASE
  localparam logic [31:0] A_RSV4_END     = 32'h3FFF_FFFF; // @MAP:RSV4_END
  localparam logic [31:0] A_XMEM_BASE    = 32'h4000_0000; // @MAP:XMEM_BASE
  localparam logic [31:0] A_XMEM_END     = 32'h407F_FFFF; // @MAP:XMEM_END
  localparam logic [31:0] A_RSV5_BASE    = 32'h4080_0000; // @MAP:RSV5_BASE
  localparam logic [31:0] A_RSV5_END     = 32'hFFFF_FFFF; // @MAP:RSV5_END

  localparam logic [31:0] RESET_VECTOR   = A_BOOTROM_BASE; // 0x0001_0000
  localparam logic [31:0] MTVEC_RESET    = 32'h0000_0100;

  localparam logic [31:0] AME_WBUF_OFF      = 32'h0000_0000; // @AMEW:WBUF
  localparam logic [31:0] AME_WBUF_APERTURE = 32'h0000_0400; // @AMEW:WBUF_APERTURE
  localparam logic [31:0] AME_XBUF_OFF      = 32'h0000_0400; // @AMEW:XBUF
  localparam logic [31:0] AME_XBUF_APERTURE = 32'h0000_0400; // @AMEW:XBUF_APERTURE
  localparam logic [31:0] AME_Y32_OFF       = 32'h0000_0800; // @AMEW:Y32
  localparam logic [31:0] AME_YQ_OFF        = 32'h0000_0880; // @AMEW:YQ
  localparam logic [31:0] AME_STATUS_OFF    = 32'h0000_08C0; // @AMEW:STATUS
  localparam logic [31:0] AME_IRQEN_OFF     = 32'h0000_08C4; // @AMEW:IRQEN
  localparam logic [31:0] AME_EVCLEAR_OFF   = 32'h0000_08C8; // @AMEW:EVCLEAR

  localparam int unsigned AME_STATUS_BUSY_BIT  = 0;
  localparam int unsigned AME_STATUS_DONE_BIT  = 1;
  localparam int unsigned AME_STATUS_W0RDY_BIT = 2;
  localparam int unsigned AME_STATUS_W1RDY_BIT = 3;
  localparam int unsigned AME_STATUS_X0RDY_BIT = 4;
  localparam int unsigned AME_STATUS_X1RDY_BIT = 5;
  localparam int unsigned AME_STATUS_ERR_BIT   = 7;

  localparam logic [31:0] SYS_ID_VAL    = 32'h414D_4343; // "AMCC"
  localparam logic [31:0] SYS_VER_VAL   = 32'h0100_0000; // 1.0.0
  localparam logic [31:0] SYS_ID_OFF    = 32'h00;
  localparam logic [31:0] SYS_VER_OFF   = 32'h04;
  localparam logic [31:0] SYS_STAT_OFF  = 32'h08;
  localparam logic [31:0] SYS_SCR0_OFF  = 32'h10;
  localparam logic [31:0] SYS_SCR1_OFF  = 32'h14;
  localparam logic [31:0] SYS_SIRQ_SET_OFF   = 32'h18;
  localparam logic [31:0] SYS_SIRQ_CLEAR_OFF = 32'h1C;

  localparam logic [31:0] INTC_EN_OFF     = 32'h00;
  localparam logic [31:0] INTC_PEND_OFF   = 32'h04;
  localparam logic [31:0] INTC_CLEAR_OFF  = 32'h08;
  localparam logic [31:0] INTC_SET_OFF    = 32'h0C;
  localparam int unsigned IRQ_UART_TX = 0;
  localparam int unsigned IRQ_UART_RX = 1;
  localparam int unsigned IRQ_DMA_DONE = 2;
  localparam int unsigned IRQ_DMA_ERR  = 3;
  localparam int unsigned IRQ_AME_DONE = 4;
  localparam int unsigned IRQ_AME_ERR  = 5;
  localparam int unsigned IRQ_KV_DONE  = 6;
  localparam int unsigned IRQ_KV_ERR   = 7;
  localparam int unsigned IRQ_BUSERR   = 8;
  localparam int unsigned IRQ_SOFT     = 9;

  localparam logic [31:0] UART_TXDATA_OFF = 32'h00;
  localparam logic [31:0] UART_RXDATA_OFF = 32'h04;
  localparam logic [31:0] UART_DIV_OFF    = 32'h08;
  localparam logic [31:0] UART_CTRL_OFF   = 32'h0C;
  localparam logic [31:0] UART_STAT_OFF   = 32'h10;
  localparam logic [31:0] UART_EVCLR_OFF  = 32'h1C;
  localparam int unsigned UART_DIV_RESET = 1042; // 120MHz/115200
  localparam int unsigned UART_FIFO_DEPTH = 16;

  localparam logic [31:0] DMA_SRC_OFF      = 32'h00;
  localparam logic [31:0] DMA_DST_OFF      = 32'h04;
  localparam logic [31:0] DMA_XCNT_OFF     = 32'h08;
  localparam logic [31:0] DMA_YCNT_OFF     = 32'h0C;
  localparam logic [31:0] DMA_SPITCH_OFF   = 32'h10;
  localparam logic [31:0] DMA_DPITCH_OFF   = 32'h14;
  localparam logic [31:0] DMA_CTRL_OFF     = 32'h18;
  localparam logic [31:0] DMA_STATUS_OFF   = 32'h1C;
  localparam int unsigned DMA_FIFO_DEPTH = 8; // 每通道最小 FIFO 字数
  typedef enum logic [3:0] {
    DMA_ERR_NONE   = 4'd0,
    DMA_ERR_ALIGN  = 4'd1,
    DMA_ERR_BUS    = 4'd2,
    DMA_ERR_ABORT  = 4'd3
  } dma_err_e;

  localparam logic [31:0] KV_CTRL_OFF   = 32'h00;
  localparam logic [31:0] KV_LAYER_OFF  = 32'h04;
  localparam logic [31:0] KV_HEAD_OFF   = 32'h08;
  localparam logic [31:0] KV_POS_OFF    = 32'h0C;
  localparam logic [31:0] KV_COUNT_OFF  = 32'h10;
  localparam logic [31:0] KV_SRC_OFF    = 32'h14;
  localparam logic [31:0] KV_DST_OFF    = 32'h18;
  localparam logic [31:0] KV_PITCH_OFF  = 32'h1C;
  localparam logic [31:0] KV_STATUS_OFF = 32'h20;
  localparam logic [31:0] KV_SLICE_OFF  = 32'h24; // [5:0] DDOFF [11:6] DLEN(0=64);P1BX-A 裁决 C
  typedef enum logic [2:0] {
    KV_MODE_APPEND_K  = 3'd0,
    KV_MODE_APPEND_V  = 3'd1,
    KV_MODE_APPEND_KV8 = 3'd2,
    KV_MODE_READ_K    = 3'd3,
    KV_MODE_READ_V    = 3'd4,
    KV_MODE_CLEAR     = 3'd5
  } kv_mode_e;
  typedef enum logic [3:0] {
    KV_ERR_NONE  = 4'd0,
    KV_ERR_POS   = 4'd1,
    KV_ERR_BUS   = 4'd2,
    KV_ERR_ABORT = 4'd3
  } kv_err_e;

  localparam int unsigned XMEM_AW_DEF = 23; // 字节地址引脚宽 → 8MB
  localparam int unsigned XMEM_DW_DEF = 16; // 数据总线宽(8/16/32)
  localparam int unsigned XMEM_WS_DEF = 0;  // 附加等待拍

  localparam logic [31:0] XM_PROG_OFF    = 32'h0000_0000; // 128KB
  localparam logic [31:0] XM_PROG_SIZE   = 32'h0002_0000;
  localparam logic [31:0] XM_WEIGHTS_OFF = 32'h0002_0000; // 2.25MB,ROWMAJOR [N][K]
  localparam logic [31:0] XM_WEIGHTS_SIZE = 32'h0022_0000;
  localparam logic [31:0] XM_KV_OFF      = 32'h0040_0000; // 256KB
  localparam logic [31:0] XM_KV_SIZE     = 32'h0004_0000;
  localparam logic [31:0] XM_SCRATCH_OFF = 32'h0048_0000; // 64KB
  localparam logic [31:0] XM_SCRATCH_SIZE = 32'h0001_0000;

  localparam int unsigned KV_BANKS_DEF   = 4;    // = n_head
  localparam int unsigned KV_CTX_MAX     = 256;  // 最大上下文
  localparam int unsigned KV_ROW_BYTES   = 64;   // d_head INT8
  localparam int unsigned KV_ROW_WORDS   = KV_ROW_BYTES/4;   // 16
  localparam int unsigned KV_BANK_DEPTH  = KV_CTX_MAX * KV_ROW_WORDS; // 4096 字
  localparam int unsigned KV_BANK_AW     = 12;   // log2(KV_BANK_DEPTH)

  function automatic logic [31:0] kv_off (
    input logic        layer,    // 0/1
    input logic        k_v,      // 0=K, 1=V
    input logic [1:0]  head,     // 0..3(bank)
    input logic [8:0]  pos,      // 0..KV_CTX_MAX-1
    input logic [5:0]  byte_idx  // 0..63
  );
    logic [31:0] off;
    off = (layer ? 32'h0002_0000 : 32'h0000_0000);
    off = off + (k_v ? 32'h0001_0000 : 32'h0000_0000);
    off = off + (32'h0000_4000 * {30'h0, head});
    off = off + (32'd64 * {23'h0, pos});
    off = off + {26'h0, byte_idx};
    kv_off = off;
  endfunction

  function automatic logic [31:0] w_layer_off (input logic [3:0] idx);
    case (idx)
      4'd0:    w_layer_off = 32'h0000_0000; // tok_emb   262144 B
      4'd1:    w_layer_off = 32'h0004_0000; // L0.qkv     196608 B
      4'd2:    w_layer_off = 32'h0007_0000; // L0.o        65536 B
      4'd3:    w_layer_off = 32'h0008_0000; // L0.ffn1    262144 B
      4'd4:    w_layer_off = 32'h000C_0000; // L0.ffn2    262144 B
      4'd5:    w_layer_off = 32'h0010_0000; // L1.qkv     196608 B
      4'd6:    w_layer_off = 32'h0013_0000; // L1.o        65536 B
      4'd7:    w_layer_off = 32'h0014_0000; // L1.ffn1    262144 B
      4'd8:    w_layer_off = 32'h0018_0000; // L1.ffn2    262144 B
      4'd9:    w_layer_off = 32'h001C_0000; // lm_head    262144 B
      default: w_layer_off = 32'h0020_0000; // blob 总末址(= 2MB)
    endcase
  endfunction

  typedef logic [1:0] axi_resp_t;
  localparam axi_resp_t AXI_OKAY   = 2'b00;
  localparam axi_resp_t AXI_EXOKAY = 2'b01;
  localparam axi_resp_t AXI_SLVERR = 2'b10;
  localparam axi_resp_t AXI_DECERR = 2'b11;

  typedef struct packed {
    axi_addr_t addr;
    logic [2:0] prot; // 恒 0
  } axi_aw_t;

  typedef struct packed {
    axi_data_t data;
    axi_strb_t strb;
  } axi_w_t;

  typedef struct packed {
    axi_resp_t resp;
  } axi_b_t;

  typedef struct packed {
    axi_addr_t addr;
    logic [2:0] prot;
  } axi_ar_t;

  typedef struct packed {
    axi_data_t data;
    axi_resp_t resp;
  } axi_r_t;

  typedef enum logic [2:0] {
    AME_OP_CFG  = 3'h0,
    AME_OP_QCFG = 3'h1,
    AME_OP_LDW  = 3'h2,
    AME_OP_LDX  = 3'h3,
    AME_OP_EXE  = 3'h4, // EXEF 由 funct7 区分,枚举同 funct3
    AME_OP_STY  = 3'h5,
    AME_OP_STQ  = 3'h6,
    AME_OP_SYNC = 3'h7
  } ame_op_e;

  typedef enum logic [1:0] {
    AME_TSET_EMPTY   = 2'b00,
    AME_TSET_LOADING = 2'b01,
    AME_TSET_READY   = 2'b10,
    AME_TSET_RUNNING = 2'b11
  } ame_tset_e;

endpackage

`endif // _AMECHIP_PKG_SV
