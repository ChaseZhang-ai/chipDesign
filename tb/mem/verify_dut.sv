`ifndef _AMECHIP_PKG_SV
 `include "amechip_pkg.sv"
`endif

module verify_dut #(
  parameter bit          KV_BACKEND_B = 1'b0,
  parameter int unsigned KV_CTX       = amechip_pkg::KV_CTX_MAX,
  parameter int unsigned OC_SRAM_KB   = 4,
  parameter int unsigned BOOT_ROM_KB  = 2
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

  output logic        irq_line_o
);

  logic sys_aw_valid_o, sys_aw_ready_i;  logic [31:0] sys_aw_addr_o;
  logic sys_w_valid_o,  sys_w_ready_i;   logic [31:0] sys_w_data_o;
  logic [3:0]  sys_w_strb_o;
  logic sys_b_valid_i,  sys_b_ready_o;   logic [1:0]  sys_b_resp_i;
  logic sys_ar_valid_o, sys_ar_ready_i;  logic [31:0] sys_ar_addr_o;
  logic sys_r_valid_i,  sys_r_ready_o;   logic [31:0] sys_r_data_i;
  logic [1:0]  sys_r_resp_i;

  logic intc_aw_valid_o, intc_aw_ready_i; logic [31:0] intc_aw_addr_o;
  logic intc_w_valid_o,  intc_w_ready_i;  logic [31:0] intc_w_data_o;
  logic [3:0]  intc_w_strb_o;
  logic intc_b_valid_i,  intc_b_ready_o;  logic [1:0]  intc_b_resp_i;
  logic intc_ar_valid_o, intc_ar_ready_i; logic [31:0] intc_ar_addr_o;
  logic intc_r_valid_i,  intc_r_ready_o;  logic [31:0] intc_r_data_i;
  logic [1:0]  intc_r_resp_i;

  logic uart_aw_valid_o, uart_aw_ready_i; logic [31:0] uart_aw_addr_o;
  logic uart_w_valid_o,  uart_w_ready_i;  logic [31:0] uart_w_data_o;
  logic [3:0]  uart_w_strb_o;
  logic uart_b_valid_i,  uart_b_ready_o;  logic [1:0]  uart_b_resp_i;
  logic uart_ar_valid_o, uart_ar_ready_i; logic [31:0] uart_ar_addr_o;
  logic uart_r_valid_i,  uart_r_ready_o;  logic [31:0] uart_r_data_i;
  logic [1:0]  uart_r_resp_i;

  logic ame_aw_valid_o, ame_aw_ready_i;  logic [31:0] ame_aw_addr_o;
  logic ame_w_valid_o,  ame_w_ready_i;   logic [31:0] ame_w_data_o;
  logic [3:0]  ame_w_strb_o;
  logic ame_b_valid_i,  ame_b_ready_o;   logic [1:0]  ame_b_resp_i;
  logic ame_ar_valid_o, ame_ar_ready_i;  logic [31:0] ame_ar_addr_o;
  logic ame_r_valid_i,  ame_r_ready_o;   logic [31:0] ame_r_data_i;
  logic [1:0]  ame_r_resp_i;

  logic        xmem_clk;
  logic [22:0] xmem_a;
  logic [15:0] xmem_di, xmem_do;
  logic        xmem_ce_n, xmem_oe_n, xmem_we_n;
  logic        irq_dma_done, irq_dma_err, irq_kv_done, irq_kv_err;
  logic        soft_pulse;

  mem_ss_top #(
    .OC_SRAM_KB   (OC_SRAM_KB),
    .BOOT_ROM_KB  (BOOT_ROM_KB),
    .BOOT_INIT    (""),
    .KV_BACKEND_B (KV_BACKEND_B),
    .KV_CTX       (KV_CTX)
  ) u_mem (
    .clk_i(clk_i), .rst_ni(rst_ni),
    .cpu_aw_valid_i(cpu_aw_valid_i), .cpu_aw_ready_o(cpu_aw_ready_o),
    .cpu_aw_addr_i (cpu_aw_addr_i),
    .cpu_w_valid_i (cpu_w_valid_i),  .cpu_w_ready_o (cpu_w_ready_o),
    .cpu_w_data_i  (cpu_w_data_i),   .cpu_w_strb_i  (cpu_w_strb_i),
    .cpu_b_valid_o (cpu_b_valid_o),  .cpu_b_ready_i (cpu_b_ready_i),
    .cpu_b_resp_o  (cpu_b_resp_o),
    .cpu_ar_valid_i(cpu_ar_valid_i), .cpu_ar_ready_o(cpu_ar_ready_o),
    .cpu_ar_addr_i (cpu_ar_addr_i),
    .cpu_r_valid_o (cpu_r_valid_o),  .cpu_r_ready_i (cpu_r_ready_i),
    .cpu_r_data_o  (cpu_r_data_o),   .cpu_r_resp_o  (cpu_r_resp_o),
    .sys_aw_valid_o(sys_aw_valid_o), .sys_aw_ready_i(sys_aw_ready_i),
    .sys_aw_addr_o (sys_aw_addr_o),
    .sys_w_valid_o (sys_w_valid_o),  .sys_w_ready_i (sys_w_ready_i),
    .sys_w_data_o  (sys_w_data_o),   .sys_w_strb_o  (sys_w_strb_o),
    .sys_b_valid_i (sys_b_valid_i),  .sys_b_ready_o (sys_b_ready_o),
    .sys_b_resp_i  (sys_b_resp_i),
    .sys_ar_valid_o(sys_ar_valid_o), .sys_ar_ready_i(sys_ar_ready_i),
    .sys_ar_addr_o (sys_ar_addr_o),
    .sys_r_valid_i (sys_r_valid_i),  .sys_r_ready_o (sys_r_ready_o),
    .sys_r_data_i  (sys_r_data_i),   .sys_r_resp_i  (sys_r_resp_i),
    .intc_aw_valid_o(intc_aw_valid_o), .intc_aw_ready_i(intc_aw_ready_i),
    .intc_aw_addr_o (intc_aw_addr_o),
    .intc_w_valid_o (intc_w_valid_o),  .intc_w_ready_i (intc_w_ready_i),
    .intc_w_data_o  (intc_w_data_o),   .intc_w_strb_o  (intc_w_strb_o),
    .intc_b_valid_i (intc_b_valid_i),  .intc_b_ready_o (intc_b_ready_o),
    .intc_b_resp_i  (intc_b_resp_i),
    .intc_ar_valid_o(intc_ar_valid_o), .intc_ar_ready_i(intc_ar_ready_i),
    .intc_ar_addr_o (intc_ar_addr_o),
    .intc_r_valid_i (intc_r_valid_i),  .intc_r_ready_o (intc_r_ready_o),
    .intc_r_data_i  (intc_r_data_i),   .intc_r_resp_i  (intc_r_resp_i),
    .uart_aw_valid_o(uart_aw_valid_o), .uart_aw_ready_i(uart_aw_ready_i),
    .uart_aw_addr_o (uart_aw_addr_o),
    .uart_w_valid_o (uart_w_valid_o),  .uart_w_ready_i (uart_w_ready_i),
    .uart_w_data_o  (uart_w_data_o),   .uart_w_strb_o  (uart_w_strb_o),
    .uart_b_valid_i (uart_b_valid_i),  .uart_b_ready_o (uart_b_ready_o),
    .uart_b_resp_i  (uart_b_resp_i),
    .uart_ar_valid_o(uart_ar_valid_o), .uart_ar_ready_i(uart_ar_ready_i),
    .uart_ar_addr_o (uart_ar_addr_o),
    .uart_r_valid_i (uart_r_valid_i),  .uart_r_ready_o (uart_r_ready_o),
    .uart_r_data_i  (uart_r_data_i),   .uart_r_resp_i  (uart_r_resp_i),
    .ame_aw_valid_o(ame_aw_valid_o), .ame_aw_ready_i(ame_aw_ready_i),
    .ame_aw_addr_o (ame_aw_addr_o),
    .ame_w_valid_o (ame_w_valid_o),  .ame_w_ready_i (ame_w_ready_i),
    .ame_w_data_o  (ame_w_data_o),   .ame_w_strb_o  (ame_w_strb_o),
    .ame_b_valid_i (ame_b_valid_i),  .ame_b_ready_o (ame_b_ready_o),
    .ame_b_resp_i  (ame_b_resp_i),
    .ame_ar_valid_o(ame_ar_valid_o), .ame_ar_ready_i(ame_ar_ready_i),
    .ame_ar_addr_o (ame_ar_addr_o),
    .ame_r_valid_i (ame_r_valid_i),  .ame_r_ready_o (ame_r_ready_o),
    .ame_r_data_i  (ame_r_data_i),   .ame_r_resp_i  (ame_r_resp_i),
    .xmem_clk_o (xmem_clk),
    .xmem_a_o   (xmem_a),
    .xmem_di_i  (xmem_di),
    .xmem_do_o  (xmem_do),
    .xmem_ce_no (xmem_ce_n),
    .xmem_oe_no (xmem_oe_n),
    .xmem_we_no (xmem_we_n),
    .xmem_wait_i(1'b0),
    .irq_dma_done_o(irq_dma_done),
    .irq_dma_err_o (irq_dma_err),
    .irq_kv_done_o (irq_kv_done),
    .irq_kv_err_o  (irq_kv_err)
  );

  tb_sys_stub u_sys (.clk_i(clk_i), .rst_ni(rst_ni),
    .aw_valid_i(sys_aw_valid_o), .aw_ready_o(sys_aw_ready_i),
    .aw_addr_i(sys_aw_addr_o),
    .w_valid_i(sys_w_valid_o), .w_ready_o(sys_w_ready_i),
    .w_data_i(sys_w_data_o), .w_strb_i(sys_w_strb_o),
    .b_valid_o(sys_b_valid_i), .b_ready_i(sys_b_ready_o), .b_resp_o(sys_b_resp_i),
    .ar_valid_i(sys_ar_valid_o), .ar_ready_o(sys_ar_ready_i),
    .ar_addr_i(sys_ar_addr_o),
    .r_valid_o(sys_r_valid_i), .r_ready_i(sys_r_ready_o),
    .r_data_o(sys_r_data_i), .r_resp_o(sys_r_resp_i),
    .soft_irq_pulse_o(soft_pulse));

  tb_intc_stub u_intc (.clk_i(clk_i), .rst_ni(rst_ni),
    .aw_valid_i(intc_aw_valid_o), .aw_ready_o(intc_aw_ready_i),
    .aw_addr_i(intc_aw_addr_o),
    .w_valid_i(intc_w_valid_o), .w_ready_o(intc_w_ready_i),
    .w_data_i(intc_w_data_o), .w_strb_i(intc_w_strb_o),
    .b_valid_o(intc_b_valid_i), .b_ready_i(intc_b_ready_o), .b_resp_o(intc_b_resp_i),
    .ar_valid_i(intc_ar_valid_o), .ar_ready_o(intc_ar_ready_i),
    .ar_addr_i(intc_ar_addr_o),
    .r_valid_o(intc_r_valid_i), .r_ready_i(intc_r_ready_o),
    .r_data_o(intc_r_data_i), .r_resp_o(intc_r_resp_i),
    .irq_dma_done_i(irq_dma_done), .irq_dma_err_i(irq_dma_err),
    .irq_kv_done_i(irq_kv_done), .irq_kv_err_i(irq_kv_err),
    .irq_soft_i(soft_pulse), .irq_o(irq_line_o));

  tb_uart_stub u_uart (.clk_i(clk_i), .rst_ni(rst_ni),
    .aw_valid_i(uart_aw_valid_o), .aw_ready_o(uart_aw_ready_i),
    .aw_addr_i(uart_aw_addr_o),
    .w_valid_i(uart_w_valid_o), .w_ready_o(uart_w_ready_i),
    .w_data_i(uart_w_data_o), .w_strb_i(uart_w_strb_o),
    .b_valid_o(uart_b_valid_i), .b_ready_i(uart_b_ready_o), .b_resp_o(uart_b_resp_i),
    .ar_valid_i(uart_ar_valid_o), .ar_ready_o(uart_ar_ready_i),
    .ar_addr_i(uart_ar_addr_o),
    .r_valid_o(uart_r_valid_i), .r_ready_i(uart_r_ready_o),
    .r_data_o(uart_r_data_i), .r_resp_o(uart_r_resp_i));

  tb_ame_stub u_ame (.clk_i(clk_i), .rst_ni(rst_ni),
    .aw_valid_i(ame_aw_valid_o), .aw_ready_o(ame_aw_ready_i),
    .aw_addr_i(ame_aw_addr_o),
    .w_valid_i(ame_w_valid_o), .w_ready_o(ame_w_ready_i),
    .w_data_i(ame_w_data_o), .w_strb_i(ame_w_strb_o),
    .b_valid_o(ame_b_valid_i), .b_ready_i(ame_b_ready_o), .b_resp_o(ame_b_resp_i),
    .ar_valid_i(ame_ar_valid_o), .ar_ready_o(ame_ar_ready_i),
    .ar_addr_i(ame_ar_addr_o),
    .r_valid_o(ame_r_valid_i), .r_ready_i(ame_r_ready_o),
    .r_data_o(ame_r_data_i), .r_resp_o(ame_r_resp_i));

  verify_psram u_psram (.clk_i(clk_i), .a_i(xmem_a), .di_i(xmem_do),
    .do_o(xmem_di), .ce_ni(xmem_ce_n), .oe_ni(xmem_oe_n), .we_ni(xmem_we_n));

`ifndef VFRC_NO_PROTO
  verify_protocol #(.NM(4), .NS(9)) u_proto (
    .clk_i(clk_i), .rst_ni(rst_ni),
    .m_aw_valid_i(u_mem.u_xbar.m_aw_valid_i),
    .m_aw_ready_o(u_mem.u_xbar.m_aw_ready_o),
    .m_aw_addr_i (u_mem.u_xbar.m_aw_addr_i),
    .m_w_valid_i (u_mem.u_xbar.m_w_valid_i),
    .m_w_ready_o (u_mem.u_xbar.m_w_ready_o),
    .m_w_data_i  (u_mem.u_xbar.m_w_data_i),
    .m_w_strb_i  (u_mem.u_xbar.m_w_strb_i),
    .m_b_valid_o (u_mem.u_xbar.m_b_valid_o),
    .m_b_ready_i (u_mem.u_xbar.m_b_ready_i),
    .m_b_resp_o  (u_mem.u_xbar.m_b_resp_o),
    .m_ar_valid_i(u_mem.u_xbar.m_ar_valid_i),
    .m_ar_ready_o(u_mem.u_xbar.m_ar_ready_o),
    .m_ar_addr_i (u_mem.u_xbar.m_ar_addr_i),
    .m_r_valid_o (u_mem.u_xbar.m_r_valid_o),
    .m_r_ready_i (u_mem.u_xbar.m_r_ready_i),
    .m_r_data_o  (u_mem.u_xbar.m_r_data_o),
    .m_r_resp_o  (u_mem.u_xbar.m_r_resp_o),
    .s_aw_valid_o(u_mem.u_xbar.s_aw_valid_o),
    .s_aw_ready_i(u_mem.u_xbar.s_aw_ready_i),
    .s_aw_addr_o (u_mem.u_xbar.s_aw_addr_o),
    .s_w_valid_o (u_mem.u_xbar.s_w_valid_o),
    .s_w_ready_i (u_mem.u_xbar.s_w_ready_i),
    .s_w_data_o  (u_mem.u_xbar.s_w_data_o),
    .s_w_strb_o  (u_mem.u_xbar.s_w_strb_o),
    .s_b_valid_i (u_mem.u_xbar.s_b_valid_i),
    .s_b_ready_o (u_mem.u_xbar.s_b_ready_o),
    .s_b_resp_i  (u_mem.u_xbar.s_b_resp_i),
    .s_ar_valid_o(u_mem.u_xbar.s_ar_valid_o),
    .s_ar_ready_i(u_mem.u_xbar.s_ar_ready_i),
    .s_ar_addr_o (u_mem.u_xbar.s_ar_addr_o),
    .s_r_valid_i (u_mem.u_xbar.s_r_valid_i),
    .s_r_ready_o (u_mem.u_xbar.s_r_ready_o),
    .s_r_data_i  (u_mem.u_xbar.s_r_data_i),
    .s_r_resp_i  (u_mem.u_xbar.s_r_resp_i)
  );
`endif

endmodule
