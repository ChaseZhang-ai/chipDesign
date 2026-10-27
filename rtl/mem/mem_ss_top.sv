`ifndef _AMECHIP_PKG_SV
 `include "amechip_pkg.sv"
`endif

module mem_ss_top #(
  parameter int unsigned OC_SRAM_KB   = 4,
  parameter int unsigned BOOT_ROM_KB  = 2,
  parameter              BOOT_INIT    = "",
  parameter bit          KV_BACKEND_B = 1'b0,
  parameter int unsigned KV_CTX       = amechip_pkg::KV_CTX_MAX,
  parameter int unsigned DMA_FIFO     = amechip_pkg::DMA_FIFO_DEPTH,
  parameter int unsigned XMEM_WS      = amechip_pkg::XMEM_WS_DEF
) (
  input  logic clk_i,
  input  logic rst_ni,

  input  logic        cpu_aw_valid_i,
  output logic        cpu_aw_ready_o,
  input  logic [31:0] cpu_aw_addr_i,
  input  logic        cpu_w_valid_i,
  output logic        cpu_w_ready_o,
  input  logic [31:0] cpu_w_data_i,
  input  logic [3:0]  cpu_w_strb_i,
  output logic        cpu_b_valid_o,
  input  logic        cpu_b_ready_i,
  output logic [1:0]  cpu_b_resp_o,
  input  logic        cpu_ar_valid_i,
  output logic        cpu_ar_ready_o,
  input  logic [31:0] cpu_ar_addr_i,
  output logic        cpu_r_valid_o,
  input  logic        cpu_r_ready_i,
  output logic [31:0] cpu_r_data_o,
  output logic [1:0]  cpu_r_resp_o,

  output logic        sys_aw_valid_o,
  input  logic        sys_aw_ready_i,
  output logic [31:0] sys_aw_addr_o,
  output logic        sys_w_valid_o,
  input  logic        sys_w_ready_i,
  output logic [31:0] sys_w_data_o,
  output logic [3:0]  sys_w_strb_o,
  input  logic        sys_b_valid_i,
  output logic        sys_b_ready_o,
  input  logic [1:0]  sys_b_resp_i,
  output logic        sys_ar_valid_o,
  input  logic        sys_ar_ready_i,
  output logic [31:0] sys_ar_addr_o,
  input  logic        sys_r_valid_i,
  output logic        sys_r_ready_o,
  input  logic [31:0] sys_r_data_i,
  input  logic [1:0]  sys_r_resp_i,

  output logic        intc_aw_valid_o,
  input  logic        intc_aw_ready_i,
  output logic [31:0] intc_aw_addr_o,
  output logic        intc_w_valid_o,
  input  logic        intc_w_ready_i,
  output logic [31:0] intc_w_data_o,
  output logic [3:0]  intc_w_strb_o,
  input  logic        intc_b_valid_i,
  output logic        intc_b_ready_o,
  input  logic [1:0]  intc_b_resp_i,
  output logic        intc_ar_valid_o,
  input  logic        intc_ar_ready_i,
  output logic [31:0] intc_ar_addr_o,
  input  logic        intc_r_valid_i,
  output logic        intc_r_ready_o,
  input  logic [31:0] intc_r_data_i,
  input  logic [1:0]  intc_r_resp_i,

  output logic        uart_aw_valid_o,
  input  logic        uart_aw_ready_i,
  output logic [31:0] uart_aw_addr_o,
  output logic        uart_w_valid_o,
  input  logic        uart_w_ready_i,
  output logic [31:0] uart_w_data_o,
  output logic [3:0]  uart_w_strb_o,
  input  logic        uart_b_valid_i,
  output logic        uart_b_ready_o,
  input  logic [1:0]  uart_b_resp_i,
  output logic        uart_ar_valid_o,
  input  logic        uart_ar_ready_i,
  output logic [31:0] uart_ar_addr_o,
  input  logic        uart_r_valid_i,
  output logic        uart_r_ready_o,
  input  logic [31:0] uart_r_data_i,
  input  logic [1:0]  uart_r_resp_i,

  output logic        ame_aw_valid_o,
  input  logic        ame_aw_ready_i,
  output logic [31:0] ame_aw_addr_o,
  output logic        ame_w_valid_o,
  input  logic        ame_w_ready_i,
  output logic [31:0] ame_w_data_o,
  output logic [3:0]  ame_w_strb_o,
  input  logic        ame_b_valid_i,
  output logic        ame_b_ready_o,
  input  logic [1:0]  ame_b_resp_i,
  output logic        ame_ar_valid_o,
  input  logic        ame_ar_ready_i,
  output logic [31:0] ame_ar_addr_o,
  input  logic        ame_r_valid_i,
  output logic        ame_r_ready_o,
  input  logic [31:0] ame_r_data_i,
  input  logic [1:0]  ame_r_resp_i,

  output logic          xmem_clk_o,
  output logic [22:0]   xmem_a_o,
  input  logic [15:0]   xmem_di_i,
  output logic [15:0]   xmem_do_o,
  output logic          xmem_ce_no,
  output logic          xmem_oe_no,
  output logic          xmem_we_no,
  input  logic          xmem_wait_i,

  output logic        irq_dma_done_o,
  output logic        irq_dma_err_o,
  output logic        irq_kv_done_o,
  output logic        irq_kv_err_o
);

  localparam int unsigned NM = 4;
  localparam int unsigned NS = 9;
  localparam int unsigned BPAW = $clog2(KV_CTX * 16);
  localparam int unsigned KV_BANKS_DEFAULT = amechip_pkg::KV_BANKS_DEF;

  logic [NM-1:0]     xb_aw_valid, xb_aw_ready, xb_w_valid, xb_w_ready;
  logic [32*NM-1:0]  xb_aw_addr, xb_w_data;
  logic [4*NM-1:0]   xb_w_strb;
  logic [NM-1:0]     xb_b_valid, xb_b_ready;
  logic [2*NM-1:0]   xb_b_resp;
  logic [NM-1:0]     xb_ar_valid, xb_ar_ready;
  logic [32*NM-1:0]  xb_ar_addr;
  logic [NM-1:0]     xb_r_valid, xb_r_ready;
  logic [32*NM-1:0]  xb_r_data;
  logic [2*NM-1:0]   xb_r_resp;

  logic        dma_rd_ar_valid, dma_rd_ar_ready;
  logic [31:0] dma_rd_ar_addr;
  logic        dma_rd_r_valid, dma_rd_r_ready;
  logic [31:0] dma_rd_r_data;
  logic [1:0]  dma_rd_r_resp;
  logic        dma_wr_aw_valid, dma_wr_aw_ready;
  logic [31:0] dma_wr_aw_addr;
  logic        dma_wr_w_valid, dma_wr_w_ready;
  logic [31:0] dma_wr_w_data;
  logic [3:0]  dma_wr_w_strb;
  logic        dma_wr_b_valid, dma_wr_b_ready;
  logic [1:0]  dma_wr_b_resp;

  logic        kv_ar_valid, kv_ar_ready;
  logic [31:0] kv_ar_addr;
  logic        kv_r_valid, kv_r_ready;
  logic [31:0] kv_r_data;
  logic [1:0]  kv_r_resp;
  logic        kv_aw_valid, kv_aw_ready;
  logic [31:0] kv_aw_addr;
  logic        kv_w_valid, kv_w_ready;
  logic [31:0] kv_w_data;
  logic [3:0]  kv_w_strb;
  logic        kv_b_valid, kv_b_ready;
  logic [1:0]  kv_b_resp;

  always_comb begin
    xb_aw_valid = '0; xb_w_valid = '0; xb_ar_valid = '0; xb_b_ready = '0;
    xb_r_ready  = '0; xb_aw_addr = '0; xb_w_data   = '0; xb_w_strb  = '0;
    xb_ar_addr  = '0;
    xb_aw_valid[0] = cpu_aw_valid_i;  cpu_aw_ready_o = xb_aw_ready[0];
    xb_aw_addr[0 +: 32] = cpu_aw_addr_i;
    xb_w_valid[0]  = cpu_w_valid_i;   cpu_w_ready_o  = xb_w_ready[0];
    xb_w_data[0 +: 32]  = cpu_w_data_i;
    xb_w_strb[0 +: 4]    = cpu_w_strb_i;
    cpu_b_valid_o = xb_b_valid[0];    xb_b_ready[0] = cpu_b_ready_i;
    cpu_b_resp_o  = xb_b_resp[0 +: 2];
    xb_ar_valid[0] = cpu_ar_valid_i;  cpu_ar_ready_o = xb_ar_ready[0];
    xb_ar_addr[0 +: 32] = cpu_ar_addr_i;
    cpu_r_valid_o = xb_r_valid[0];    xb_r_ready[0] = cpu_r_ready_i;
    cpu_r_data_o  = xb_r_data[0 +: 32];
    cpu_r_resp_o  = xb_r_resp[0 +: 2];
    xb_ar_valid[1] = dma_rd_ar_valid; dma_rd_ar_ready = xb_ar_ready[1];
    xb_ar_addr[32 +: 32] = dma_rd_ar_addr;
    dma_rd_r_valid = xb_r_valid[1];   xb_r_ready[1] = dma_rd_r_ready;
    dma_rd_r_data  = xb_r_data[32 +: 32];
    dma_rd_r_resp  = xb_r_resp[1*2 +: 2];
    xb_aw_valid[2] = dma_wr_aw_valid; dma_wr_aw_ready = xb_aw_ready[2];
    xb_aw_addr[64 +: 32] = dma_wr_aw_addr;
    xb_w_valid[2]  = dma_wr_w_valid;  dma_wr_w_ready  = xb_w_ready[2];
    xb_w_data[64 +: 32]  = dma_wr_w_data;
    xb_w_strb[8 +: 4]    = dma_wr_w_strb;
    dma_wr_b_valid = xb_b_valid[2];   xb_b_ready[2] = dma_wr_b_ready;
    dma_wr_b_resp  = xb_b_resp[4 +: 2];
    xb_aw_valid[3] = kv_aw_valid;     kv_aw_ready = xb_aw_ready[3];
    xb_aw_addr[96 +: 32] = kv_aw_addr;
    xb_w_valid[3]  = kv_w_valid;      kv_w_ready  = xb_w_ready[3];
    xb_w_data[96 +: 32]  = kv_w_data;
    xb_w_strb[12 +: 4]    = kv_w_strb;
    kv_b_valid     = xb_b_valid[3];   xb_b_ready[3] = kv_b_ready;
    kv_b_resp      = xb_b_resp[6 +: 2];
    xb_ar_valid[3] = kv_ar_valid;     kv_ar_ready = xb_ar_ready[3];
    xb_ar_addr[96 +: 32] = kv_ar_addr;
    kv_r_valid     = xb_r_valid[3];   xb_r_ready[3] = kv_r_ready;
    kv_r_data      = xb_r_data[96 +: 32];
    kv_r_resp      = xb_r_resp[6 +: 2];
  end

  logic [NS-1:0]     xs_aw_valid, xs_aw_ready, xs_w_valid, xs_w_ready;
  logic [32*NS-1:0]  xs_aw_addr, xs_w_data;
  logic [4*NS-1:0]   xs_w_strb;
  logic [NS-1:0]     xs_b_valid, xs_b_ready;
  logic [2*NS-1:0]   xs_b_resp;
  logic [NS-1:0]     xs_ar_valid, xs_ar_ready;
  logic [32*NS-1:0]  xs_ar_addr;
  logic [NS-1:0]     xs_r_valid, xs_r_ready;
  logic [32*NS-1:0]  xs_r_data;
  logic [2*NS-1:0]   xs_r_resp;

  axi_xbar #(
    .NM (NM),
    .NS (NS)
  ) u_xbar (
    .clk_i       (clk_i),
    .rst_ni      (rst_ni),
    .m_aw_valid_i(xb_aw_valid),
    .m_aw_ready_o(xb_aw_ready),
    .m_aw_addr_i (xb_aw_addr),
    .m_w_valid_i (xb_w_valid),
    .m_w_ready_o (xb_w_ready),
    .m_w_data_i  (xb_w_data),
    .m_w_strb_i  (xb_w_strb),
    .m_b_valid_o (xb_b_valid),
    .m_b_ready_i (xb_b_ready),
    .m_b_resp_o  (xb_b_resp),
    .m_ar_valid_i(xb_ar_valid),
    .m_ar_ready_o(xb_ar_ready),
    .m_ar_addr_i (xb_ar_addr),
    .m_r_valid_o (xb_r_valid),
    .m_r_ready_i (xb_r_ready),
    .m_r_data_o  (xb_r_data),
    .m_r_resp_o  (xb_r_resp),
    .s_aw_valid_o(xs_aw_valid),
    .s_aw_ready_i(xs_aw_ready),
    .s_aw_addr_o (xs_aw_addr),
    .s_w_valid_o (xs_w_valid),
    .s_w_ready_i (xs_w_ready),
    .s_w_data_o  (xs_w_data),
    .s_w_strb_o  (xs_w_strb),
    .s_b_valid_i (xs_b_valid),
    .s_b_ready_o (xs_b_ready),
    .s_b_resp_i  (xs_b_resp),
    .s_ar_valid_o(xs_ar_valid),
    .s_ar_ready_i(xs_ar_ready),
    .s_ar_addr_o (xs_ar_addr),
    .s_r_valid_i (xs_r_valid),
    .s_r_ready_o (xs_r_ready),
    .s_r_data_i  (xs_r_data),
    .s_r_resp_i  (xs_r_resp)
  );

  axi_mem_slave #(
    .DEPTH (OC_SRAM_KB * 256)
  ) u_ocram (
    .clk_i     (clk_i),
    .rst_ni    (rst_ni),
    .aw_valid_i(xs_aw_valid[0]),
    .aw_ready_o(xs_aw_ready[0]),
    .aw_addr_i (xs_aw_addr[0 +: 32]),
    .w_valid_i (xs_w_valid[0]),
    .w_ready_o (xs_w_ready[0]),
    .w_data_i  (xs_w_data[0 +: 32]),
    .w_strb_i  (xs_w_strb[0 +: 4]),
    .b_valid_o (xs_b_valid[0]),
    .b_ready_i (xs_b_ready[0]),
    .b_resp_o  (xs_b_resp[0 +: 2]),
    .ar_valid_i(xs_ar_valid[0]),
    .ar_ready_o(xs_ar_ready[0]),
    .ar_addr_i (xs_ar_addr[0 +: 32]),
    .r_valid_o (xs_r_valid[0]),
    .r_ready_i (xs_r_ready[0]),
    .r_data_o  (xs_r_data[0 +: 32]),
    .r_resp_o  (xs_r_resp[0 +: 2])
  );

  axi_mem_slave #(
    .DEPTH     (BOOT_ROM_KB * 256),
    .INIT_FILE (BOOT_INIT),
    .IS_ROM    (1'b1)
  ) u_bootrom (
    .clk_i     (clk_i),
    .rst_ni    (rst_ni),
    .aw_valid_i(xs_aw_valid[1]),
    .aw_ready_o(xs_aw_ready[1]),
    .aw_addr_i (xs_aw_addr[32 +: 32]),
    .w_valid_i (xs_w_valid[1]),
    .w_ready_o (xs_w_ready[1]),
    .w_data_i  (xs_w_data[32 +: 32]),
    .w_strb_i  (xs_w_strb[1*4 +: 4]),
    .b_valid_o (xs_b_valid[1]),
    .b_ready_i (xs_b_ready[1]),
    .b_resp_o  (xs_b_resp[1*2 +: 2]),
    .ar_valid_i(xs_ar_valid[1]),
    .ar_ready_o(xs_ar_ready[1]),
    .ar_addr_i (xs_ar_addr[32 +: 32]),
    .r_valid_o (xs_r_valid[1]),
    .r_ready_i (xs_r_ready[1]),
    .r_data_o  (xs_r_data[32 +: 32]),
    .r_resp_o  (xs_r_resp[1*2 +: 2])
  );

  assign sys_aw_valid_o = xs_aw_valid[2];
  assign xs_aw_ready[2] = sys_aw_ready_i;
  assign sys_aw_addr_o  = xs_aw_addr[64 +: 32];
assign sys_w_valid_o  = xs_w_valid[2];
  assign xs_w_ready[2]  = sys_w_ready_i;
  assign sys_w_data_o   = xs_w_data[64 +: 32];
  assign sys_w_strb_o   = xs_w_strb[8 +: 4];
assign xs_b_valid[2]  = sys_b_valid_i;
  assign sys_b_ready_o  = xs_b_ready[2];
  assign xs_b_resp[4 +: 2] = sys_b_resp_i;
  assign sys_ar_valid_o = xs_ar_valid[2];
  assign xs_ar_ready[2] = sys_ar_ready_i;
  assign sys_ar_addr_o  = xs_ar_addr[64 +: 32];
assign xs_r_valid[2]  = sys_r_valid_i;
  assign sys_r_ready_o  = xs_r_ready[2];
  assign xs_r_data[64 +: 32] = sys_r_data_i;
  assign xs_r_resp[4 +: 2]   = sys_r_resp_i;

  assign intc_aw_valid_o = xs_aw_valid[3];
  assign xs_aw_ready[3] = intc_aw_ready_i;
  assign intc_aw_addr_o  = xs_aw_addr[96 +: 32];
assign intc_w_valid_o  = xs_w_valid[3];
  assign xs_w_ready[3]  = intc_w_ready_i;
  assign intc_w_data_o   = xs_w_data[96 +: 32];
  assign intc_w_strb_o   = xs_w_strb[12 +: 4];
assign xs_b_valid[3]   = intc_b_valid_i;
  assign intc_b_ready_o = xs_b_ready[3];
  assign xs_b_resp[6 +: 2] = intc_b_resp_i;
  assign intc_ar_valid_o = xs_ar_valid[3];
  assign xs_ar_ready[3] = intc_ar_ready_i;
  assign intc_ar_addr_o  = xs_ar_addr[96 +: 32];
assign xs_r_valid[3]   = intc_r_valid_i;
  assign intc_r_ready_o = xs_r_ready[3];
  assign xs_r_data[96 +: 32] = intc_r_data_i;
  assign xs_r_resp[6 +: 2]   = intc_r_resp_i;

  assign uart_aw_valid_o = xs_aw_valid[4];
  assign xs_aw_ready[4] = uart_aw_ready_i;
  assign uart_aw_addr_o  = xs_aw_addr[4*32 +: 32];
assign uart_w_valid_o  = xs_w_valid[4];
  assign xs_w_ready[4]  = uart_w_ready_i;
  assign uart_w_data_o   = xs_w_data[4*32 +: 32];
  assign uart_w_strb_o   = xs_w_strb[4*4 +: 4];
assign xs_b_valid[4]   = uart_b_valid_i;
  assign uart_b_ready_o = xs_b_ready[4];
  assign xs_b_resp[4*2 +: 2] = uart_b_resp_i;
  assign uart_ar_valid_o = xs_ar_valid[4];
  assign xs_ar_ready[4] = uart_ar_ready_i;
  assign uart_ar_addr_o  = xs_ar_addr[4*32 +: 32];
assign xs_r_valid[4]   = uart_r_valid_i;
  assign uart_r_ready_o = xs_r_ready[4];
  assign xs_r_data[4*32 +: 32] = uart_r_data_i;
  assign xs_r_resp[4*2 +: 2]   = uart_r_resp_i;

  assign ame_aw_valid_o = xs_aw_valid[6];
  assign xs_aw_ready[6] = ame_aw_ready_i;
  assign ame_aw_addr_o  = xs_aw_addr[6*32 +: 32];
assign ame_w_valid_o  = xs_w_valid[6];
  assign xs_w_ready[6]  = ame_w_ready_i;
  assign ame_w_data_o   = xs_w_data[6*32 +: 32];
  assign ame_w_strb_o   = xs_w_strb[6*4 +: 4];
assign xs_b_valid[6]  = ame_b_valid_i;
  assign ame_b_ready_o  = xs_b_ready[6];
  assign xs_b_resp[6*2 +: 2] = ame_b_resp_i;
  assign ame_ar_valid_o = xs_ar_valid[6];
  assign xs_ar_ready[6] = ame_ar_ready_i;
  assign ame_ar_addr_o  = xs_ar_addr[6*32 +: 32];
assign xs_r_valid[6]  = ame_r_valid_i;
  assign ame_r_ready_o  = xs_r_ready[6];
  assign xs_r_data[6*32 +: 32] = ame_r_data_i;
  assign xs_r_resp[6*2 +: 2]   = ame_r_resp_i;

  dma_engine #(
    .FIFO_DEPTH (DMA_FIFO)
  ) u_dma (
    .clk_i           (clk_i),
    .rst_ni          (rst_ni),
    .csr_aw_valid_i  (xs_aw_valid[5]),
    .csr_aw_ready_o  (xs_aw_ready[5]),
    .csr_aw_addr_i   (xs_aw_addr[5*32 +: 32]),
    .csr_w_valid_i   (xs_w_valid[5]),
    .csr_w_ready_o   (xs_w_ready[5]),
    .csr_w_data_i    (xs_w_data[5*32 +: 32]),
    .csr_w_strb_i    (xs_w_strb[5*4 +: 4]),
    .csr_b_valid_o   (xs_b_valid[5]),
    .csr_b_ready_i   (xs_b_ready[5]),
    .csr_b_resp_o    (xs_b_resp[5*2 +: 2]),
    .csr_ar_valid_i  (xs_ar_valid[5]),
    .csr_ar_ready_o  (xs_ar_ready[5]),
    .csr_ar_addr_i   (xs_ar_addr[5*32 +: 32]),
    .csr_r_valid_o   (xs_r_valid[5]),
    .csr_r_ready_i   (xs_r_ready[5]),
    .csr_r_data_o    (xs_r_data[5*32 +: 32]),
    .csr_r_resp_o    (xs_r_resp[5*2 +: 2]),
    .rd_ar_valid_o   (dma_rd_ar_valid),
    .rd_ar_ready_i   (dma_rd_ar_ready),
    .rd_ar_addr_o    (dma_rd_ar_addr),
    .rd_r_valid_i    (dma_rd_r_valid),
    .rd_r_ready_o    (dma_rd_r_ready),
    .rd_r_data_i     (dma_rd_r_data),
    .rd_r_resp_i     (dma_rd_r_resp),
    .wr_aw_valid_o   (dma_wr_aw_valid),
    .wr_aw_ready_i   (dma_wr_aw_ready),
    .wr_aw_addr_o    (dma_wr_aw_addr),
    .wr_w_valid_o    (dma_wr_w_valid),
    .wr_w_ready_i    (dma_wr_w_ready),
    .wr_w_data_o     (dma_wr_w_data),
    .wr_w_strb_o     (dma_wr_w_strb),
    .wr_b_valid_i    (dma_wr_b_valid),
    .wr_b_ready_o    (dma_wr_b_ready),
    .wr_b_resp_i     (dma_wr_b_resp),
    .irq_done_pulse_o(irq_dma_done_o),
    .irq_err_pulse_o (irq_dma_err_o)
  );

  logic [KV_BANKS_DEFAULT-1:0]     bp_cs, bp_we;
  logic [KV_BANKS_DEFAULT*BPAW-1:0] bp_addr;
  logic [KV_BANKS_DEFAULT*32-1:0]   bp_wdata, bp_rdata;
  logic       bp_layer, bp_kvt, bp_done, bp_err, bp_ready;

  logic        bx_ar_valid, bx_ar_ready;
  logic [31:0] bx_ar_addr;
  logic        bx_r_valid, bx_r_ready;
  logic [31:0] bx_r_data;
  logic [1:0]  bx_r_resp;
  logic        bx_aw_valid, bx_aw_ready;
  logic [31:0] bx_aw_addr;
  logic        bx_w_valid, bx_w_ready;
  logic [31:0] bx_w_data;
  logic [3:0]  bx_w_strb;
  logic        bx_b_valid, bx_b_ready;
  logic [1:0]  bx_b_resp;

  kv_ctrl #(
    .CTX_MAX      (KV_CTX),
    .BANKS        (KV_BANKS_DEFAULT),
    .BPAW         (BPAW),
    .KV_BACKEND_B (KV_BACKEND_B)
  ) u_kvc (
    .clk_i           (clk_i),
    .rst_ni          (rst_ni),
    .csr_aw_valid_i  (xs_aw_valid[7]),
    .csr_aw_ready_o  (xs_aw_ready[7]),
    .csr_aw_addr_i   (xs_aw_addr[7*32 +: 32]),
    .csr_w_valid_i   (xs_w_valid[7]),
    .csr_w_ready_o   (xs_w_ready[7]),
    .csr_w_data_i    (xs_w_data[7*32 +: 32]),
    .csr_w_strb_i    (xs_w_strb[7*4 +: 4]),
    .csr_b_valid_o   (xs_b_valid[7]),
    .csr_b_ready_i   (xs_b_ready[7]),
    .csr_b_resp_o    (xs_b_resp[7*2 +: 2]),
    .csr_ar_valid_i  (xs_ar_valid[7]),
    .csr_ar_ready_o  (xs_ar_ready[7]),
    .csr_ar_addr_i   (xs_ar_addr[7*32 +: 32]),
    .csr_r_valid_o   (xs_r_valid[7]),
    .csr_r_ready_i   (xs_r_ready[7]),
    .csr_r_data_o    (xs_r_data[7*32 +: 32]),
    .csr_r_resp_o    (xs_r_resp[7*2 +: 2]),
    .m_ar_valid_o    (kv_ar_valid),
    .m_ar_ready_i    (kv_ar_ready),
    .m_ar_addr_o     (kv_ar_addr),
    .m_r_valid_i     (kv_r_valid),
    .m_r_ready_o     (kv_r_ready),
    .m_r_data_i      (kv_r_data),
    .m_r_resp_i      (kv_r_resp),
    .m_aw_valid_o    (kv_aw_valid),
    .m_aw_ready_i    (kv_aw_ready),
    .m_aw_addr_o     (kv_aw_addr),
    .m_w_valid_o     (kv_w_valid),
    .m_w_ready_i     (kv_w_ready),
    .m_w_data_o      (kv_w_data),
    .m_w_strb_o      (kv_w_strb),
    .m_b_valid_i     (kv_b_valid),
    .m_b_ready_o     (kv_b_ready),
    .m_b_resp_i      (kv_b_resp),
    .x_ar_valid_i    (bx_ar_valid),
    .x_ar_ready_o    (bx_ar_ready),
    .x_ar_addr_i     (bx_ar_addr),
    .x_r_valid_o     (bx_r_valid),
    .x_r_ready_i     (bx_r_ready),
    .x_r_data_o      (bx_r_data),
    .x_r_resp_o      (bx_r_resp),
    .x_aw_valid_i    (bx_aw_valid),
    .x_aw_ready_o    (bx_aw_ready),
    .x_aw_addr_i     (bx_aw_addr),
    .x_w_valid_i     (bx_w_valid),
    .x_w_ready_o     (bx_w_ready),
    .x_w_data_i      (bx_w_data),
    .x_w_strb_i      (bx_w_strb),
    .x_b_valid_o     (bx_b_valid),
    .x_b_ready_i     (bx_b_ready),
    .x_b_resp_o      (bx_b_resp),
    .bp_cs_o         (bp_cs),
    .bp_we_o         (bp_we),
    .bp_addr_o       (bp_addr),
    .bp_wdata_o      (bp_wdata),
    .bp_rdata_i      (bp_rdata),
    .bp_layer_o      (bp_layer),
    .bp_kvt_o        (bp_kvt),
    .bp_done_i       (bp_done),
    .bp_err_i        (bp_err),
    .bp_ready_i      (bp_ready),
    .irq_done_pulse_o(irq_kv_done_o),
    .irq_err_pulse_o (irq_kv_err_o)
  );

  generate
    if (KV_BACKEND_B) begin : g_kv_b
      kv_backend_sram #(
        .BANKS (KV_BANKS_DEFAULT),
        .CTX   (KV_CTX),
        .BPAW  (BPAW)
      ) u_kvbe (
        .clk_i     (clk_i),
        .rst_ni    (rst_ni),
        .bp_cs_i   (bp_cs),
        .bp_we_i   (bp_we),
        .bp_addr_i (bp_addr),
        .bp_wdata_i(bp_wdata),
        .bp_rdata_o(bp_rdata),
        .bp_layer_i(bp_layer),
        .bp_kvt_i  (bp_kvt),
        .bp_done_o (bp_done),
        .bp_err_o  (bp_err),
        .bp_ready_o(bp_ready)
      );
      assign bx_ar_valid = 1'b0;
      assign bx_ar_addr  = '0;
      assign bx_aw_valid = 1'b0;
      assign bx_aw_addr  = '0;
      assign bx_w_valid  = 1'b0;
      assign bx_w_data   = '0;
      assign bx_w_strb   = '0;
    end else begin : g_kv_a
      kv_backend_axi #(
        .BANKS   (KV_BANKS_DEFAULT),
        .BPAW    (BPAW),
        .KV_BASE (amechip_pkg::A_XMEM_BASE + amechip_pkg::XM_KV_OFF)
      ) u_kvbe (
        .clk_i      (clk_i),
        .rst_ni     (rst_ni),
        .bp_cs_i    (bp_cs),
        .bp_we_i    (bp_we),
        .bp_addr_i  (bp_addr),
        .bp_wdata_i (bp_wdata),
        .bp_rdata_o (bp_rdata),
        .bp_layer_i (bp_layer),
        .bp_kvt_i   (bp_kvt),
        .bp_done_o  (bp_done),
        .bp_err_o   (bp_err),
        .bp_ready_o (bp_ready),
        .m_ar_valid_o(bx_ar_valid),
        .m_ar_ready_i(bx_ar_ready),
        .m_ar_addr_o (bx_ar_addr),
        .m_r_valid_i (bx_r_valid),
        .m_r_ready_o (bx_r_ready),
        .m_r_data_i  (bx_r_data),
        .m_r_resp_i  (bx_r_resp),
        .m_aw_valid_o(bx_aw_valid),
        .m_aw_ready_i(bx_aw_ready),
        .m_aw_addr_o (bx_aw_addr),
        .m_w_valid_o (bx_w_valid),
        .m_w_ready_i (bx_w_ready),
        .m_w_data_o  (bx_w_data),
        .m_w_strb_o  (bx_w_strb),
        .m_b_valid_i (bx_b_valid),
        .m_b_ready_o (bx_b_ready),
        .m_b_resp_i  (bx_b_resp)
      );
    end
  endgenerate

  memc_xmem #(
    .AW (23),
    .WS (XMEM_WS)
  ) u_memc (
    .clk_i      (clk_i),
    .rst_ni     (rst_ni),
    .aw_valid_i (xs_aw_valid[8]),
    .aw_ready_o (xs_aw_ready[8]),
    .aw_addr_i  (xs_aw_addr[8*32 +: 32]),
    .w_valid_i  (xs_w_valid[8]),
    .w_ready_o  (xs_w_ready[8]),
    .w_data_i   (xs_w_data[8*32 +: 32]),
    .w_strb_i   (xs_w_strb[8*4 +: 4]),
    .b_valid_o  (xs_b_valid[8]),
    .b_ready_i  (xs_b_ready[8]),
    .b_resp_o   (xs_b_resp[8*2 +: 2]),
    .ar_valid_i (xs_ar_valid[8]),
    .ar_ready_o (xs_ar_ready[8]),
    .ar_addr_i  (xs_ar_addr[8*32 +: 32]),
    .r_valid_o  (xs_r_valid[8]),
    .r_ready_i  (xs_r_ready[8]),
    .r_data_o   (xs_r_data[8*32 +: 32]),
    .r_resp_o   (xs_r_resp[8*2 +: 2]),
    .xmem_clk_o (xmem_clk_o),
    .xmem_a_o   (xmem_a_o),
    .xmem_di_i  (xmem_di_i),
    .xmem_do_o  (xmem_do_o),
    .xmem_ce_no (xmem_ce_no),
    .xmem_oe_no (xmem_oe_no),
    .xmem_we_no (xmem_we_no),
    .xmem_wait_i(xmem_wait_i)
  );

endmodule
