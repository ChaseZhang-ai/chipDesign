
module amechip_top (
  input  wire         clk_i,
  input  wire         rst_ni,

  output wire         uart_tx_o,
  input  wire         uart_rx_i,

  output wire         xmem_clk_o,
  output wire [22:0]  xmem_a_o,
  input  wire [15:0]  xmem_di_i,
  output wire [15:0]  xmem_do_o,
  output wire         xmem_ce_no,
  output wire         xmem_oe_no,
  output wire         xmem_we_no,
  input  wire         xmem_wait_i,

  input  wire [3:0]   gpio_i,
  output wire [3:0]   gpio_o,

  output wire         irq_o
);

  clk_rst_if u_cr ();
  assign u_cr.clk   = clk_i;
  assign u_cr.rst_ni = rst_ni;
  wire rst_int = u_cr.rst_n;
  wire rst_busy_unused = u_cr.rst_busy;

  soc_pkg::soc_req_t  cpu_req,  s1_req,  s2_req,  s3_req,  s4_req;
  soc_pkg::soc_resp_t cpu_resp, s1_resp, s2_resp, s3_resp, s4_resp;

  wire        cpu_wfi, cpu_buserr;
  wire        ame_req_valid, ame_req_ready, ame_resp_valid, ame_resp_err;
  wire [31:0] ame_req_instr, ame_req_rs1, ame_req_rs2, ame_resp_data;

`ifdef AMECHIP_REAL_CPU
  amechip_cpu u_cpu (
    .clk(clk_i), .rst_n(rst_int),
    .bus_req(cpu_req), .bus_resp(cpu_resp),
    .ame_req_valid(ame_req_valid), .ame_req_ready(ame_req_ready),
    .ame_req_instr(ame_req_instr), .ame_req_rs1(ame_req_rs1), .ame_req_rs2(ame_req_rs2),
    .ame_resp_valid(ame_resp_valid), .ame_resp_data(ame_resp_data), .ame_resp_err(ame_resp_err),
    .irq_i(irq_int), .cpu_wfi_o(cpu_wfi), .buserr_evt_o(cpu_buserr)
  );
`else
  stub_cpu u_cpu (
    .clk(clk_i), .rst_n(rst_int),
    .bus_req(cpu_req), .bus_resp(cpu_resp),
    .ame_req_valid(ame_req_valid), .ame_req_ready(ame_req_ready),
    .ame_req_instr(ame_req_instr), .ame_req_rs1(ame_req_rs1), .ame_req_rs2(ame_req_rs2),
    .ame_resp_valid(ame_resp_valid), .ame_resp_data(ame_resp_data), .ame_resp_err(ame_resp_err),
    .irq_i(irq_int), .cpu_wfi_o(cpu_wfi), .buserr_evt_o(cpu_buserr)
  );
`endif

  ame_coproc_if u_ame_coproc (clk_i, rst_int);
  assign u_ame_coproc.req_valid  = ame_req_valid;
  assign u_ame_coproc.req_instr  = ame_req_instr;
  assign u_ame_coproc.req_rs1    = ame_req_rs1;
  assign u_ame_coproc.req_rs2    = ame_req_rs2;
  assign u_ame_coproc.req_ready  = ame_req_ready;
  assign u_ame_coproc.resp_valid = ame_resp_valid;
  assign u_ame_coproc.resp_data  = ame_resp_data;
  assign u_ame_coproc.resp_err   = ame_resp_err;

  wire        ame_busy, ame_done_evt, ame_err_evt;
  wire        win_req_valid, win_req_ready, win_req_write, win_resp_valid, win_resp_err;
  wire [31:0] win_req_addr, win_req_wdata, win_resp_rdata;
  wire [3:0]  win_req_wstrb;

`ifdef AMECHIP_REAL_AME
  amechip_ame u_ame (
    .clk(clk_i), .rst_n(rst_int),
    .req_valid(ame_req_valid), .req_ready(ame_req_ready),
    .req_instr(ame_req_instr), .req_rs1(ame_req_rs1), .req_rs2(ame_req_rs2),
    .resp_valid(ame_resp_valid), .resp_data(ame_resp_data), .resp_err(ame_resp_err),
    .win_req_valid(win_req_valid), .win_req_ready(win_req_ready),
    .win_req_write(win_req_write), .win_req_addr(win_req_addr),
    .win_req_wdata(win_req_wdata), .win_req_wstrb(win_req_wstrb),
    .win_resp_valid(win_resp_valid), .win_resp_rdata(win_resp_rdata), .win_resp_err(win_resp_err),
    .busy_o(ame_busy), .evt_done_o(ame_done_evt), .evt_err_o(ame_err_evt)
  );
`else
  stub_ame u_ame (
    .clk(clk_i), .rst_n(rst_int),
    .req_valid(ame_req_valid), .req_ready(ame_req_ready),
    .req_instr(ame_req_instr), .req_rs1(ame_req_rs1), .req_rs2(ame_req_rs2),
    .resp_valid(ame_resp_valid), .resp_data(ame_resp_data), .resp_err(ame_resp_err),
    .win_req_valid(win_req_valid), .win_req_ready(win_req_ready),
    .win_req_write(win_req_write), .win_req_addr(win_req_addr),
    .win_req_wdata(win_req_wdata), .win_req_wstrb(win_req_wstrb),
    .win_resp_valid(win_resp_valid), .win_resp_rdata(win_resp_rdata), .win_resp_err(win_resp_err),
    .busy_o(ame_busy), .evt_done_o(ame_done_evt), .evt_err_o(ame_err_evt)
  );
`endif

  wire dma_busy, dma_done_evt, dma_err_evt, kv_busy;
  wire kv_done_evt, kv_err_evt;

`ifdef AMECHIP_REAL_MEM
  amechip_mem u_mem (
    .clk(clk_i), .rst_n(rst_int),
    .m0_req(cpu_req), .m0_resp(cpu_resp),
    .s1_req(s1_req), .s1_resp(s1_resp),
    .s2_req(s2_req), .s2_resp(s2_resp),
    .s3_req(s3_req), .s3_resp(s3_resp),
    .s4_req(s4_req), .s4_resp(s4_resp),
    .win_req_valid(win_req_valid), .win_req_ready(win_req_ready),
    .win_req_write(win_req_write), .win_req_addr(win_req_addr),
    .win_req_wdata(win_req_wdata), .win_req_wstrb(win_req_wstrb),
    .win_resp_valid(win_resp_valid), .win_resp_rdata(win_resp_rdata), .win_resp_err(win_resp_err),
    .xmem_clk_o, .xmem_a_o, .xmem_di_i, .xmem_do_o,
    .xmem_ce_no, .xmem_oe_no, .xmem_we_no, .xmem_wait_i,
    .dma_busy_o(dma_busy), .dma_done_evt_o(dma_done_evt), .dma_err_evt_o(dma_err_evt),
    .kv_busy_o(kv_busy), .kv_done_evt_o(kv_done_evt), .kv_err_evt_o(kv_err_evt)
  );
`else
  stub_mem u_mem (
    .clk(clk_i), .rst_n(rst_int),
    .m0_req(cpu_req), .m0_resp(cpu_resp),
    .s1_req(s1_req), .s1_resp(s1_resp),
    .s2_req(s2_req), .s2_resp(s2_resp),
    .s3_req(s3_req), .s3_resp(s3_resp),
    .s4_req(s4_req), .s4_resp(s4_resp),
    .win_req_valid(win_req_valid), .win_req_ready(win_req_ready),
    .win_req_write(win_req_write), .win_req_addr(win_req_addr),
    .win_req_wdata(win_req_wdata), .win_req_wstrb(win_req_wstrb),
    .win_resp_valid(win_resp_valid), .win_resp_rdata(win_resp_rdata), .win_resp_err(win_resp_err),
    .xmem_clk_o, .xmem_a_o, .xmem_di_i, .xmem_do_o,
    .xmem_ce_no, .xmem_oe_no, .xmem_we_no, .xmem_wait_i,
    .dma_busy_o(dma_busy), .dma_done_evt_o(dma_done_evt), .dma_err_evt_o(dma_err_evt),
    .kv_busy_o(kv_busy)
  );
  assign kv_done_evt = 1'b0;
  assign kv_err_evt  = 1'b0;
`endif

`ifdef AMECHIP_REAL_BOOTROM
  boot_rom u_bootrom (
    .clk(clk_i), .rst_n(rst_int),
    .bus_req(s1_req), .bus_resp(s1_resp)
  );
`else
  stub_bootrom u_bootrom (
    .clk(clk_i), .rst_n(rst_int),
    .bus_req(s1_req), .bus_resp(s1_resp)
  );
`endif

  wire uart_irq_tx, uart_irq_rx;

  soc_uart u_uart (
    .clk(clk_i), .rst_n(rst_int),
    .bus_req(s4_req), .bus_resp(s4_resp),
    .tx_o(uart_tx_o), .rx_i(uart_rx_i),
    .irq_tx_o(uart_irq_tx), .irq_rx_o(uart_irq_rx)
  );

  wire soft_set, soft_clear;

  soc_syscsr u_sys (
    .clk(clk_i), .rst_n(rst_int),
    .bus_req(s2_req), .bus_resp(s2_resp),
    .cpu_wfi_i(cpu_wfi), .ame_busy_i(ame_busy),
    .dma_busy_i(dma_busy), .kv_busy_i(kv_busy),
    .soft_set_o(soft_set), .soft_clear_o(soft_clear)
  );

  wire irq_int;

  soc_intc u_intc (
    .clk(clk_i), .rst_n(rst_int),
    .bus_req(s3_req), .bus_resp(s3_resp),
    .lvl_uart_tx_i(uart_irq_tx), .lvl_uart_rx_i(uart_irq_rx),
    .evt_dma_done_i(dma_done_evt), .evt_dma_err_i(dma_err_evt),
    .evt_ame_done_i(ame_done_evt), .evt_ame_err_i(ame_err_evt),
    .evt_kv_done_i(kv_done_evt), .evt_kv_err_i(kv_err_evt),
    .evt_buserr_i(cpu_buserr),
    .soft_set_i(soft_set), .soft_clear_i(soft_clear),
    .irq_o(irq_int)
  );

  assign irq_o  = irq_int;
  assign gpio_o = {irq_int, dma_busy, ame_busy, cpu_wfi};
  wire [3:0] gpio_i_unused = gpio_i;

endmodule
