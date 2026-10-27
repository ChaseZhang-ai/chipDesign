`timescale 1ns/1ps
`include "amechip_pkg.sv"

module tb_xbar;

  logic clk = 1'b0;
  logic rst_n;
  always #5 clk = ~clk;

  logic        c_aw_valid, c_aw_ready;
  logic [31:0] c_aw_addr;
  logic        c_w_valid, c_w_ready;
  logic [31:0] c_w_data;
  logic [3:0]  c_w_strb;
  logic        c_b_valid, c_b_ready;
  logic [1:0]  c_b_resp;
  logic        c_ar_valid, c_ar_ready;
  logic [31:0] c_ar_addr;
  logic        c_r_valid, c_r_ready;
  logic [31:0] c_r_data;
  logic [1:0]  c_r_resp;

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
  logic        soft_pulse, irq_line;

  mem_ss_top #(
    .OC_SRAM_KB   (4),
    .BOOT_ROM_KB  (2),
    .BOOT_INIT    ("boot_rom.memh"),
    .KV_BACKEND_B (1'b0),
    .KV_CTX       (amechip_pkg::KV_CTX_MAX)
  ) dut (
    .clk_i(clk), .rst_ni(rst_n),
    .cpu_aw_valid_i(c_aw_valid), .cpu_aw_ready_o(c_aw_ready),
    .cpu_aw_addr_i (c_aw_addr),
    .cpu_w_valid_i (c_w_valid),  .cpu_w_ready_o (c_w_ready),
    .cpu_w_data_i  (c_w_data),   .cpu_w_strb_i  (c_w_strb),
    .cpu_b_valid_o (c_b_valid),  .cpu_b_ready_i (c_b_ready),
    .cpu_b_resp_o  (c_b_resp),
    .cpu_ar_valid_i(c_ar_valid), .cpu_ar_ready_o(c_ar_ready),
    .cpu_ar_addr_i (c_ar_addr),
    .cpu_r_valid_o (c_r_valid),  .cpu_r_ready_i (c_r_ready),
    .cpu_r_data_o  (c_r_data),   .cpu_r_resp_o  (c_r_resp),
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

  tb_sys_stub u_sys   (.clk_i(clk), .rst_ni(rst_n),
    .aw_valid_i(sys_aw_valid_o), .aw_ready_o(sys_aw_ready_i),
    .aw_addr_i(sys_aw_addr_o),
    .w_valid_i(sys_w_valid_o), .w_ready_o(sys_w_ready_i),
    .w_data_i(sys_w_data_o), .w_strb_i(sys_w_strb_o),
    .b_valid_o(sys_b_valid_i), .b_ready_i(sys_b_ready_o),
    .b_resp_o(sys_b_resp_i),
    .ar_valid_i(sys_ar_valid_o), .ar_ready_o(sys_ar_ready_i),
    .ar_addr_i(sys_ar_addr_o),
    .r_valid_o(sys_r_valid_i), .r_ready_i(sys_r_ready_o),
    .r_data_o(sys_r_data_i), .r_resp_o(sys_r_resp_i),
    .soft_irq_pulse_o(soft_pulse));

  tb_intc_stub u_intc (.clk_i(clk), .rst_ni(rst_n),
    .aw_valid_i(intc_aw_valid_o), .aw_ready_o(intc_aw_ready_i),
    .aw_addr_i(intc_aw_addr_o),
    .w_valid_i(intc_w_valid_o), .w_ready_o(intc_w_ready_i),
    .w_data_i(intc_w_data_o), .w_strb_i(intc_w_strb_o),
    .b_valid_o(intc_b_valid_i), .b_ready_i(intc_b_ready_o),
    .b_resp_o(intc_b_resp_i),
    .ar_valid_i(intc_ar_valid_o), .ar_ready_o(intc_ar_ready_i),
    .ar_addr_i(intc_ar_addr_o),
    .r_valid_o(intc_r_valid_i), .r_ready_i(intc_r_ready_o),
    .r_data_o(intc_r_data_i), .r_resp_o(intc_r_resp_i),
    .irq_dma_done_i(irq_dma_done), .irq_dma_err_i(irq_dma_err),
    .irq_kv_done_i(irq_kv_done), .irq_kv_err_i(irq_kv_err),
    .irq_soft_i(soft_pulse), .irq_o(irq_line));

  tb_uart_stub u_uart (.clk_i(clk), .rst_ni(rst_n),
    .aw_valid_i(uart_aw_valid_o), .aw_ready_o(uart_aw_ready_i),
    .aw_addr_i(uart_aw_addr_o),
    .w_valid_i(uart_w_valid_o), .w_ready_o(uart_w_ready_i),
    .w_data_i(uart_w_data_o), .w_strb_i(uart_w_strb_o),
    .b_valid_o(uart_b_valid_i), .b_ready_i(uart_b_ready_o),
    .b_resp_o(uart_b_resp_i),
    .ar_valid_i(uart_ar_valid_o), .ar_ready_o(uart_ar_ready_i),
    .ar_addr_i(uart_ar_addr_o),
    .r_valid_o(uart_r_valid_i), .r_ready_i(uart_r_ready_o),
    .r_data_o(uart_r_data_i), .r_resp_o(uart_r_resp_i));

  tb_ame_stub u_ame (.clk_i(clk), .rst_ni(rst_n),
    .aw_valid_i(ame_aw_valid_o), .aw_ready_o(ame_aw_ready_i),
    .aw_addr_i(ame_aw_addr_o),
    .w_valid_i(ame_w_valid_o), .w_ready_o(ame_w_ready_i),
    .w_data_i(ame_w_data_o), .w_strb_i(ame_w_strb_o),
    .b_valid_o(ame_b_valid_i), .b_ready_i(ame_b_ready_o),
    .b_resp_o(ame_b_resp_i),
    .ar_valid_i(ame_ar_valid_o), .ar_ready_o(ame_ar_ready_i),
    .ar_addr_i(ame_ar_addr_o),
    .r_valid_o(ame_r_valid_i), .r_ready_i(ame_r_ready_o),
    .r_data_o(ame_r_data_i), .r_resp_o(ame_r_resp_i));

  tb_xmem_psram u_psram (.clk_i(clk), .a_i(xmem_a), .di_i(xmem_do),
    .do_o(xmem_di), .ce_ni(xmem_ce_n), .oe_ni(xmem_oe_n),
    .we_ni(xmem_we_n), .dump_req_i(1'b0));

  `include "tb_bfm_tasks.svh"

  int dbg_cyc;
  always @(posedge clk) begin
    if (!rst_n) dbg_cyc = 0;
    else begin
      dbg_cyc = dbg_cyc + 1;
      if ($test$plusargs("trace") && dbg_cyc >= 176 && dbg_cyc <= 200)
        $display("[dbg %0d] dma_arv=%b dma_arr=%b dma_rv=%b | s8_arv=%b s8_arr=%b s8_rv=%b s8_rr=%b | p8_rcnt=%0d p8_rrp=%0d p8_front=%b | xb_rv1=%b xb_rr1=%b | memc.st=%0d rq_cnt=%0d rq_rp=%0d rdinf=%0d",
          dbg_cyc,
          dut.u_dma.rd_ar_valid_o, dut.u_dma.rd_ar_ready_i, dut.u_dma.rd_r_valid_i,
          dut.u_xbar.s_ar_valid_o[8], dut.u_xbar.s_ar_ready_i[8],
          dut.u_xbar.s_r_valid_i[8], dut.u_xbar.s_r_ready_o[8],
          dut.u_xbar.g_ports[8].u_port.r_cnt, dut.u_xbar.g_ports[8].u_port.r_rp,
          dut.u_xbar.g_ports[8].u_port.r_front,
          dut.u_xbar.m_r_valid_o[1], dut.u_xbar.m_r_ready_i[1],
          dut.u_memc.st_q, dut.u_memc.rq_cnt, dut.u_memc.rq_rp, dut.u_dma.rd_inflight);
    end
  end

  task automatic test_reset_values();
    logic [31:0] d;
    begin
      axi_read_check("SYS.ID",   32'h1000_0000, amechip_pkg::SYS_ID_VAL);
      axi_read_check("SYS.VER",  32'h1000_0004, amechip_pkg::SYS_VER_VAL);
      axi_read(32'h1000_0008, d);
      bfm_check_eq("SYS.STATUS[3:0]", {28'b0, d[3:0]}, 32'b0);
      axi_read_check("INTC.EN",      32'h1000_1000, 32'h0);
      axi_read_check("INTC.PENDING", 32'h1000_1004, 32'h0);
      axi_read_check("UART.DIV",     32'h1000_2008, 32'd1042);
      axi_read_check("DMA.STATUS",   32'h2000_001C, 32'h0);
      axi_read_check("DMA.SRC",      32'h2000_0000, 32'h0);
      axi_read_check("KV.STATUS",    32'h2000_3020, 32'h0);
      axi_read_check("KV.SLICE",     32'h2000_3024, 32'h0);
    end
  endtask

  task automatic test_routing();
    logic [31:0] d;
    begin
      axi_write(32'h0000_0100, 32'hA5A5_0001);
      axi_read_check("OCSRAM@100", 32'h0000_0100, 32'hA5A5_0001);
      axi_write(32'h0000_0FFC, 32'hA5A5_0002);
      axi_read_check("OCSRAM@FFC", 32'h0000_0FFC, 32'hA5A5_0002);
      axi_read_check("BOOTROM@000", 32'h0001_0000, 32'h1301_0000);
      axi_read_check("BOOTROM@1FC", 32'h0001_07F0, 32'h1301_07F0);
      axi_write(32'h0001_0000, 32'h0, amechip_pkg::AXI_SLVERR);
      axi_write(32'h1000_0010, 32'hDEAD_C0DE);
      axi_read_check("SYS.SCRATCH0", 32'h1000_0010, 32'hDEAD_C0DE);
      axi_write(32'h1000_1000, 32'h0000_00FF);
      axi_read_check("INTC.EN", 32'h1000_1000, 32'h0000_00FF);
      axi_write(32'h1000_1000, 32'h0);
      axi_write(32'h1000_2008, 32'd4);
      axi_read_check("UART.DIV", 32'h1000_2008, 32'd4);
      axi_read(32'h1000_2004, d);
      bfm_check_eq("UART.RXDATA[8]", {31'b0, d[8]}, 32'b0);
      axi_write(32'h2000_0000, 32'h1234_5678);
      axi_read_check("DMA.SRC", 32'h2000_0000, 32'h1234_5678);
      axi_write(32'h2000_0000, 32'h0);
      axi_write(32'h2000_1000, 32'h0BAD_F00D);
      axi_read_check("AME.WBUF@000", 32'h2000_1000, 32'h0BAD_F00D);
      axi_write(32'h2000_1400, 32'h1550_0002);
      axi_read_check("AME.WBUF@400", 32'h2000_1400, 32'h1550_0002);
      axi_write(32'h2000_2000, 32'h0BAD_F001);
      axi_read_check("AME.XBUF@000", 32'h2000_2000, 32'h0BAD_F001);
      axi_write(32'h2000_3004, 32'h1);
      axi_read_check("KV.LAYER", 32'h2000_3004, 32'h1);
      axi_write(32'h2000_3004, 32'h0);
      axi_write(32'h4000_0000, 32'hC0DE_600D);
      axi_read_check("XMEM@0", 32'h4000_0000, 32'hC0DE_600D);
      d = {u_psram.peek(1), u_psram.peek(0)};
      bfm_check_eq("PSRAM.peek@0", d, 32'hC0DE_600D);
      axi_write(32'h407F_FFFC, 32'h1234_5678);
      axi_read_check("XMEM@7FFFFFC", 32'h407F_FFFC, 32'h1234_5678);
      d = {u_psram.peek(32'h3FFFFF), u_psram.peek(32'h3FFFFE)};
      bfm_check_eq("PSRAM.peek@7FFFFC", d, 32'h1234_5678);
    end
  endtask

  task automatic test_decerr();
    logic [31:0] d;
    begin
      axi_read(32'h0000_2000, d, amechip_pkg::AXI_DECERR);
      axi_write(32'h0000_2000, 32'h0, amechip_pkg::AXI_DECERR);
      axi_read(32'h0001_1000, d, amechip_pkg::AXI_DECERR);
      axi_read(32'h1000_5000, d, amechip_pkg::AXI_DECERR);
      axi_read(32'h2000_5000, d, amechip_pkg::AXI_DECERR);
      axi_read(32'h4080_0000, d, amechip_pkg::AXI_DECERR);
      axi_read(32'hFFFF_FFFC, d, amechip_pkg::AXI_DECERR);
    end
  endtask

  task automatic test_dma_irq();
    logic [31:0] st, pend;
    begin
      axi_write(32'h4000_1000, 32'h1111_1111);
      axi_write(32'h4000_1004, 32'h2222_2222);
      dma_cfg(32'h4000_1000, 32'h0000_0200, 2, 1, 0, 0, 32'h10);
      dma_go(1'b1);
      dma_wait(st);
      $display("[dbg] DMA status=%08h (errcode=%0d) busy_q=%b fcnt=%0d rdinf=%0d wrinf=%0d rdy=%0d wry=%0d rdx=%0d wrx=%0d",
        st, st[7:4], dut.u_dma.busy_q, dut.u_dma.fifo_cnt, dut.u_dma.rd_inflight,
        dut.u_dma.wr_inflight, dut.u_dma.rd_y, dut.u_dma.wr_y, dut.u_dma.rd_x, dut.u_dma.wr_x);
      bfm_check_eq("DMA.STATUS(DONE)", {30'b0, st[1]}, 32'b1);
      bfm_check_eq("DMA.STATUS(ERR)",  {31'b0, st[2]}, 32'b0);
      axi_read_check("OCSRAM@200", 32'h0000_0200, 32'h1111_1111);
      axi_read_check("OCSRAM@204", 32'h0000_0204, 32'h2222_2222);
      axi_read_check("INTC.PENDING[2]", 32'h1000_1004, 32'h4);
      axi_write(32'h1000_1000, 32'hFFFF_FFFF);
      bfm_check_eq("IRQ线", {31'b0, irq_line}, 32'b1);
      axi_write(32'h1000_1000, 32'h0);
      axi_write(32'h1000_1008, 32'h4); // CLEAR
      axi_read_check("INTC.PENDING 清后", 32'h1000_1004, 32'h0);
      axi_write(32'h2000_001C, 32'h2); // DMA.DONE W1C
    end
  endtask

  task automatic test_kv_irq();
    logic [31:0] st;
    begin
      kv_cfg(32'h0000_0000, 32'h0, 32'h0, 32'h0, 32'h1,
             32'h0, 32'h0, 32'h0, 32'h0);
      kv_go(amechip_pkg::KV_MODE_CLEAR, 1'b0, 1'b1);
      kv_wait(st);
      $display("[dbg] KV status=%08h (errcode=%0d)", st, st[7:4]);
      bfm_check_eq("KV.STATUS(DONE)", {30'b0, st[1]}, 32'b1);
      bfm_check_eq("KV.STATUS(ERR)",  {31'b0, st[2]}, 32'b0);
      axi_read_check("INTC.PENDING[6]", 32'h1000_1004, 32'h40);
      axi_write(32'h1000_1008, 32'h40);
      axi_write(32'h2000_3020, 32'h2); // KV.DONE W1C
    end
  endtask

  task automatic test_kv_readback_a();
    logic [31:0] st, d, exp;
    begin
      $display("[kvA] 写 512B 源到 XMEM SCRATCH");
      for (int i = 0; i < 128; i++) begin
        d = (32'(4*i)) | (32'(4*i+1) << 8) | (32'(4*i+2) << 16) | (32'(4*i+3) << 24);
        axi_write(32'h4048_0000 + 4*i, d);
      end
      kv_cfg(32'h0, 32'h0, 32'h0, 32'h0, 32'h1, 32'h4048_0000, 32'h0, 32'h0, 32'h0);
      kv_go(amechip_pkg::KV_MODE_APPEND_KV8, 1'b0, 1'b0);
      kv_wait(st);
      $display("[kvA] append st=%08h", st);
      kv_cfg(32'h0, 32'h0, 32'h0, 32'h0, 32'h1, 32'h0, 32'h0000_0900, 32'h0, 32'h0);
      kv_go(amechip_pkg::KV_MODE_READ_K, 1'b0, 1'b0);
      kv_wait(st);
      $display("[kvA] read st=%08h", st);
      for (int i = 0; i < 16; i++) begin
        axi_read(32'h0000_0900 + 4*i, d);
        exp = (32'(4*i)) | (32'(4*i+1) << 8) | (32'(4*i+2) << 16) | (32'(4*i+3) << 24);
        bfm_check_eq($sformatf("kvA READ_K word[%0d]", i), d, exp);
      end
      axi_write(32'h2000_3020, 32'h6); // W1C
    end
  endtask

  int  cpu_rd_cnt;
  task automatic cpu_read_burst(input int n, input logic [31:0] addr);
    logic [31:0] d;
    begin
      for (int i = 0; i < n; i++) begin
        axi_read_lat(addr, d);
        cpu_rd_cnt = cpu_rd_cnt + 1;
      end
    end
  endtask

  task automatic test_fairness();
    int cycles0, cycles1;
    logic [31:0] st;
    begin
      $display("[fair] CPU 连续读 XMEM + DMA XMEM→XMEM 拷贝 + KV CLEAR 256 行(后端 A)同时压 XMEM 从口");
      for (int i = 0; i < 64; i++)
        axi_write(32'h4002_0000 + 4*i, 32'hF000_0000 + i);
      dma_cfg(32'h4002_0000, 32'h4003_0000, 64, 1, 0, 0, 32'h10); // IRQ_EN
      kv_cfg(32'h0, 32'h0, 32'h1, 32'h0, 32'd256,
             32'h0, 32'h0, 32'h0, 32'h0);
      lat_max    = 0;
      cpu_rd_cnt = 0;
      cycles0    = $time / 10;
      dma_go(1'b1);
      kv_go(amechip_pkg::KV_MODE_CLEAR, 1'b0, 1'b1);
      fork
        begin : cpu_traffic
          cpu_read_burst(96, 32'h4002_0000);
          $display("[fair] cpu burst done @%0t", $time);
        end
        begin : dma_traffic
          wait (dut.u_dma.busy_q == 1'b0);
          $display("[fair] dma done @%0t", $time);
        end
        begin : kv_traffic
          wait (dut.u_kvc.busy_q == 1'b0);
          $display("[fair] kv done @%0t", $time);
        end
      join
      cycles1 = $time / 10;
      axi_read(32'h2000_001C, st);
      bfm_check_eq("fair: DMA DONE", {30'b0, st[1]}, 32'b1);
      bfm_check_eq("fair: DMA ERR",  {31'b0, st[2]}, 32'b0);
      axi_read(32'h2000_3020, st);
      $display("[dbg] fair KV status=%08h errcode=%0d", st, st[7:4]);
      bfm_check_eq("fair: KV DONE", {30'b0, st[1]}, 32'b1);
      bfm_check_eq("fair: KV ERR",  {31'b0, st[2]}, 32'b0);
      $display("[fair] CPU 读完成 %0d 次,最坏读延迟 = %0d 周期,区间 = %0d 周期",
               cpu_rd_cnt, lat_max, cycles1 - cycles0);
      bfm_checks = bfm_checks + 1;
      if (lat_max > 40) begin
        bfm_fail($sformatf("fair: CPU 最坏延迟 %0d > 界 40", lat_max));
      end
      axi_read_check("fair: XMEM@40030000", 32'h4003_0000, 32'hF000_0000);
      axi_read_check("fair: XMEM@400300FC", 32'h4003_00FC, 32'hF000_003F);
      axi_write(32'h2000_001C, 32'h2); // W1C
      axi_write(32'h2000_3020, 32'h2);
      axi_write(32'h1000_1008, 32'h4C);
    end
  endtask

  always @(posedge clk) begin
    if (rst_n && $test$plusargs("trace2")) begin
      if (dut.u_xbar.s_r_valid_i[8] && dut.u_xbar.s_r_ready_o[8])
        $display("[rd8 %0d] front=%b cnt=%0d wp=%0d rp=%0d dma_rdi=%0d dma_rdv=%b",
          probe_cyc, dut.u_xbar.g_ports[8].u_port.r_front,
          dut.u_xbar.g_ports[8].u_port.r_cnt,
          dut.u_xbar.g_ports[8].u_port.r_wp,
          dut.u_xbar.g_ports[8].u_port.r_rp,
          dut.u_dma.rd_inflight, dut.u_dma.rd_r_valid_i);
      if (dut.u_dma.rd_ar_valid_o && dut.u_dma.rd_ar_ready_i)
        $display("[ar8 %0d] dma_ar_acc rdx=%0d rdy=%0d rdi=%0d",
          probe_cyc, dut.u_dma.rd_x, dut.u_dma.rd_y, dut.u_dma.rd_inflight);
    end
  end

  int bpd_cnt, s8b_cnt, s8w_cnt;
  always @(posedge clk) begin
    if (!rst_n) begin bpd_cnt = 0; s8b_cnt = 0; s8w_cnt = 0; end
    else begin
      if (dut.u_kvc.bp_done_i) begin
        bpd_cnt = bpd_cnt + 1;
        if ($test$plusargs("pace") && (bpd_cnt % 1024) == 0)
          $display("[bpd %0d] @%0t", bpd_cnt, $time);
      end
      if (dut.u_xbar.s_aw_valid_o[8] && dut.u_xbar.s_aw_ready_i[8]) s8w_cnt = s8w_cnt + 1;
      if (dut.u_xbar.s_b_valid_i[8] && dut.u_xbar.s_b_ready_o[8]) begin
        s8b_cnt = s8b_cnt + 1;
        if ($test$plusargs("pace") && (s8b_cnt % 1024) == 0)
          $display("[s8b %0d] @%0t (s8w=%0d)", s8b_cnt, $time, s8w_cnt);
      end
    end
  end

  always @(posedge clk) begin
    if (rst_n && $test$plusargs("trace") &&
        dut.u_kvc.csr_w_accept && (dut.u_kvc.w_off == 4'h0))
      $display("[kvw %0t] dat=%h go_fire=%b go_bad=%b go_ok=%b | mode=%0d layer=%h head=%0d pos=%0d cnt=%0d slice=%h busy=%b",
        $time, dut.u_kvc.w_dat, dut.u_kvc.go_fire, dut.u_kvc.go_bad, dut.u_kvc.go_ok,
        dut.u_kvc.ctrl_eff_g[2:0], dut.u_kvc.reg_layer, dut.u_kvc.reg_head,
        dut.u_kvc.reg_pos, dut.u_kvc.reg_count, dut.u_kvc.reg_slice, dut.u_kvc.busy_q);
  end

  int probe_cyc;
  always @(posedge clk) begin
    if (!rst_n) probe_cyc = 0;
    else begin
      probe_cyc = probe_cyc + 1;
      if ($test$plusargs("trace") && (probe_cyc % 2000) == 0 &&
          (dut.u_dma.busy_q || dut.u_kvc.busy_q))
        $display("[probe %0d] dma(b=%b f=%0d rdi=%0d wri=%0d rdx=%0d/%0d wry=%0d) kv(b=%b st=%0d) memc(st=%0d rq=%0d wq=%0d) | r: dma_arv=%b dma_arr=%b s8arv=%b s8arr=%b s8rv=%b s8rr=%b p8cnt=%0d p8front=%b xb_rv1=%b xbrr1=%b",
          probe_cyc, dut.u_dma.busy_q, dut.u_dma.fifo_cnt,
          dut.u_dma.rd_inflight, dut.u_dma.wr_inflight,
          dut.u_dma.rd_x, dut.u_dma.rd_y, dut.u_dma.wr_y,
          dut.u_kvc.busy_q, dut.u_kvc.st_q,
          dut.u_memc.st_q, dut.u_memc.rq_cnt, dut.u_memc.wq_cnt,
          dut.u_dma.rd_ar_valid_o, dut.u_dma.rd_ar_ready_i,
          dut.u_xbar.s_ar_valid_o[8], dut.u_xbar.s_ar_ready_i[8],
          dut.u_xbar.s_r_valid_i[8], dut.u_xbar.s_r_ready_o[8],
          dut.u_xbar.g_ports[8].u_port.r_cnt,
          dut.u_xbar.g_ports[8].u_port.r_front,
          dut.u_xbar.m_r_valid_o[1], dut.u_xbar.m_r_ready_i[1]);
    end
  end

  initial begin
    rst_n = 1'b0;
    c_aw_valid = 0; c_w_valid = 0; c_ar_valid = 0;
    c_b_ready = 0;  c_r_ready = 0;
    c_aw_addr = '0; c_w_data = '0; c_w_strb = '0; c_ar_addr = '0;
    repeat (5) @(posedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);

    test_reset_values();
    test_routing();
    test_decerr();
    test_dma_irq();
    test_kv_irq();
    test_kv_readback_a();
    if (!$test$plusargs("skipfair")) test_fairness();

    $display("=== tb_xbar: checks=%0d errors=%0d ===", bfm_checks, bfm_errors);
    if (bfm_errors == 0) $display("TB_XBAR: PASS");
    else                 $display("TB_XBAR: FAIL");
    $finish;
  end

  initial begin
    #40_000_000;
    $display("[FAIL] tb_xbar 全局超时");
    $display("TB_XBAR: FAIL");
    $finish;
  end

endmodule
