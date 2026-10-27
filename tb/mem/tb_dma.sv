`timescale 1ns/1ps
`include "amechip_pkg.sv"

module tb_dma;

  logic clk = 1'b0;
  logic rst_n;
  always #5 clk = ~clk;

  logic        c_aw_valid, c_aw_ready; logic [31:0] c_aw_addr;
  logic        c_w_valid, c_w_ready;   logic [31:0] c_w_data; logic [3:0] c_w_strb;
  logic        c_b_valid, c_b_ready;   logic [1:0] c_b_resp;
  logic        c_ar_valid, c_ar_ready; logic [31:0] c_ar_addr;
  logic        c_r_valid, c_r_ready;   logic [31:0] c_r_data; logic [1:0] c_r_resp;

  logic [22:0] xa; logic [15:0] xdi, xdo;
  logic xce, xoe, xwe;
  logic irq_dma_done, irq_dma_err, irq_kv_done, irq_kv_err, soft_pulse, irq_line;

  logic sys_aw_valid_o, sys_aw_ready_i;  logic [31:0] sys_aw_addr_o;
  logic sys_w_valid_o,  sys_w_ready_i;   logic [31:0] sys_w_data_o; logic [3:0] sys_w_strb_o;
  logic sys_b_valid_i,  sys_b_ready_o;   logic [1:0]  sys_b_resp_i;
  logic sys_ar_valid_o, sys_ar_ready_i;  logic [31:0] sys_ar_addr_o;
  logic sys_r_valid_i,  sys_r_ready_o;   logic [31:0] sys_r_data_i; logic [1:0] sys_r_resp_i;
  logic intc_aw_valid_o, intc_aw_ready_i; logic [31:0] intc_aw_addr_o;
  logic intc_w_valid_o,  intc_w_ready_i;  logic [31:0] intc_w_data_o; logic [3:0] intc_w_strb_o;
  logic intc_b_valid_i,  intc_b_ready_o;  logic [1:0]  intc_b_resp_i;
  logic intc_ar_valid_o, intc_ar_ready_i; logic [31:0] intc_ar_addr_o;
  logic intc_r_valid_i,  intc_r_ready_o;  logic [31:0] intc_r_data_i; logic [1:0] intc_r_resp_i;
  logic uart_aw_valid_o, uart_aw_ready_i; logic [31:0] uart_aw_addr_o;
  logic uart_w_valid_o,  uart_w_ready_i;  logic [31:0] uart_w_data_o; logic [3:0] uart_w_strb_o;
  logic uart_b_valid_i,  uart_b_ready_o;  logic [1:0]  uart_b_resp_i;
  logic uart_ar_valid_o, uart_ar_ready_i; logic [31:0] uart_ar_addr_o;
  logic uart_r_valid_i,  uart_r_ready_o;  logic [31:0] uart_r_data_i; logic [1:0] uart_r_resp_i;
  logic ame_aw_valid_o, ame_aw_ready_i;  logic [31:0] ame_aw_addr_o;
  logic ame_w_valid_o,  ame_w_ready_i;   logic [31:0] ame_w_data_o; logic [3:0] ame_w_strb_o;
  logic ame_b_valid_i,  ame_b_ready_o;   logic [1:0]  ame_b_resp_i;
  logic ame_ar_valid_o, ame_ar_ready_i;  logic [31:0] ame_ar_addr_o;
  logic ame_r_valid_i,  ame_r_ready_o;   logic [31:0] ame_r_data_i; logic [1:0] ame_r_resp_i;

  mem_ss_top #(
    .OC_SRAM_KB   (4),
    .BOOT_ROM_KB  (2),
    .BOOT_INIT    ("boot_rom.memh"),
    .KV_BACKEND_B (1'b1),
    .KV_CTX       (128)
  ) dut (
    .clk_i(clk), .rst_ni(rst_n),
    .cpu_aw_valid_i(c_aw_valid), .cpu_aw_ready_o(c_aw_ready), .cpu_aw_addr_i(c_aw_addr),
    .cpu_w_valid_i(c_w_valid), .cpu_w_ready_o(c_w_ready), .cpu_w_data_i(c_w_data),
    .cpu_w_strb_i(c_w_strb),
    .cpu_b_valid_o(c_b_valid), .cpu_b_ready_i(c_b_ready), .cpu_b_resp_o(c_b_resp),
    .cpu_ar_valid_i(c_ar_valid), .cpu_ar_ready_o(c_ar_ready), .cpu_ar_addr_i(c_ar_addr),
    .cpu_r_valid_o(c_r_valid), .cpu_r_ready_i(c_r_ready), .cpu_r_data_o(c_r_data),
    .cpu_r_resp_o(c_r_resp),
    .sys_aw_valid_o(sys_aw_valid_o), .sys_aw_ready_i(sys_aw_ready_i), .sys_aw_addr_o(sys_aw_addr_o),
    .sys_w_valid_o(sys_w_valid_o), .sys_w_ready_i(sys_w_ready_i), .sys_w_data_o(sys_w_data_o),
    .sys_w_strb_o(sys_w_strb_o),
    .sys_b_valid_i(sys_b_valid_i), .sys_b_ready_o(sys_b_ready_o), .sys_b_resp_i(sys_b_resp_i),
    .sys_ar_valid_o(sys_ar_valid_o), .sys_ar_ready_i(sys_ar_ready_i), .sys_ar_addr_o(sys_ar_addr_o),
    .sys_r_valid_i(sys_r_valid_i), .sys_r_ready_o(sys_r_ready_o), .sys_r_data_i(sys_r_data_i),
    .sys_r_resp_i(sys_r_resp_i),
    .intc_aw_valid_o(intc_aw_valid_o), .intc_aw_ready_i(intc_aw_ready_i), .intc_aw_addr_o(intc_aw_addr_o),
    .intc_w_valid_o(intc_w_valid_o), .intc_w_ready_i(intc_w_ready_i), .intc_w_data_o(intc_w_data_o),
    .intc_w_strb_o(intc_w_strb_o),
    .intc_b_valid_i(intc_b_valid_i), .intc_b_ready_o(intc_b_ready_o), .intc_b_resp_i(intc_b_resp_i),
    .intc_ar_valid_o(intc_ar_valid_o), .intc_ar_ready_i(intc_ar_ready_i), .intc_ar_addr_o(intc_ar_addr_o),
    .intc_r_valid_i(intc_r_valid_i), .intc_r_ready_o(intc_r_ready_o), .intc_r_data_i(intc_r_data_i),
    .intc_r_resp_i(intc_r_resp_i),
    .uart_aw_valid_o(uart_aw_valid_o), .uart_aw_ready_i(uart_aw_ready_i), .uart_aw_addr_o(uart_aw_addr_o),
    .uart_w_valid_o(uart_w_valid_o), .uart_w_ready_i(uart_w_ready_i), .uart_w_data_o(uart_w_data_o),
    .uart_w_strb_o(uart_w_strb_o),
    .uart_b_valid_i(uart_b_valid_i), .uart_b_ready_o(uart_b_ready_o), .uart_b_resp_i(uart_b_resp_i),
    .uart_ar_valid_o(uart_ar_valid_o), .uart_ar_ready_i(uart_ar_ready_i), .uart_ar_addr_o(uart_ar_addr_o),
    .uart_r_valid_i(uart_r_valid_i), .uart_r_ready_o(uart_r_ready_o), .uart_r_data_i(uart_r_data_i),
    .uart_r_resp_i(uart_r_resp_i),
    .ame_aw_valid_o(ame_aw_valid_o), .ame_aw_ready_i(ame_aw_ready_i), .ame_aw_addr_o(ame_aw_addr_o),
    .ame_w_valid_o(ame_w_valid_o), .ame_w_ready_i(ame_w_ready_i), .ame_w_data_o(ame_w_data_o),
    .ame_w_strb_o(ame_w_strb_o),
    .ame_b_valid_i(ame_b_valid_i), .ame_b_ready_o(ame_b_ready_o), .ame_b_resp_i(ame_b_resp_i),
    .ame_ar_valid_o(ame_ar_valid_o), .ame_ar_ready_i(ame_ar_ready_i), .ame_ar_addr_o(ame_ar_addr_o),
    .ame_r_valid_i(ame_r_valid_i), .ame_r_ready_o(ame_r_ready_o), .ame_r_data_i(ame_r_data_i),
    .ame_r_resp_i(ame_r_resp_i),
    .xmem_clk_o(), .xmem_a_o(xa), .xmem_di_i(xdo), .xmem_do_o(xdi),
    .xmem_ce_no(xce), .xmem_oe_no(xoe), .xmem_we_no(xwe), .xmem_wait_i(1'b0),
    .irq_dma_done_o(irq_dma_done), .irq_dma_err_o(irq_dma_err),
    .irq_kv_done_o(irq_kv_done), .irq_kv_err_o(irq_kv_err)
  );

  tb_sys_stub u_sys (.clk_i(clk), .rst_ni(rst_n),
    .aw_valid_i(sys_aw_valid_o), .aw_ready_o(sys_aw_ready_i), .aw_addr_i(sys_aw_addr_o),
    .w_valid_i(sys_w_valid_o), .w_ready_o(sys_w_ready_i), .w_data_i(sys_w_data_o),
    .w_strb_i(sys_w_strb_o),
    .b_valid_o(sys_b_valid_i), .b_ready_i(sys_b_ready_o), .b_resp_o(sys_b_resp_i),
    .ar_valid_i(sys_ar_valid_o), .ar_ready_o(sys_ar_ready_i), .ar_addr_i(sys_ar_addr_o),
    .r_valid_o(sys_r_valid_i), .r_ready_i(sys_r_ready_o), .r_data_o(sys_r_data_i),
    .r_resp_o(sys_r_resp_i), .soft_irq_pulse_o(soft_pulse));

  tb_intc_stub u_intc (.clk_i(clk), .rst_ni(rst_n),
    .aw_valid_i(intc_aw_valid_o), .aw_ready_o(intc_aw_ready_i), .aw_addr_i(intc_aw_addr_o),
    .w_valid_i(intc_w_valid_o), .w_ready_o(intc_w_ready_i), .w_data_i(intc_w_data_o),
    .w_strb_i(intc_w_strb_o),
    .b_valid_o(intc_b_valid_i), .b_ready_i(intc_b_ready_o), .b_resp_o(intc_b_resp_i),
    .ar_valid_i(intc_ar_valid_o), .ar_ready_o(intc_ar_ready_i), .ar_addr_i(intc_ar_addr_o),
    .r_valid_o(intc_r_valid_i), .r_ready_i(intc_r_ready_o), .r_data_o(intc_r_data_i),
    .r_resp_o(intc_r_resp_i),
    .irq_dma_done_i(irq_dma_done), .irq_dma_err_i(irq_dma_err),
    .irq_kv_done_i(irq_kv_done), .irq_kv_err_i(irq_kv_err),
    .irq_soft_i(soft_pulse), .irq_o(irq_line));

  tb_uart_stub u_uart (.clk_i(clk), .rst_ni(rst_n),
    .aw_valid_i(uart_aw_valid_o), .aw_ready_o(uart_aw_ready_i), .aw_addr_i(uart_aw_addr_o),
    .w_valid_i(uart_w_valid_o), .w_ready_o(uart_w_ready_i), .w_data_i(uart_w_data_o),
    .w_strb_i(uart_w_strb_o),
    .b_valid_o(uart_b_valid_i), .b_ready_i(uart_b_ready_o), .b_resp_o(uart_b_resp_i),
    .ar_valid_i(uart_ar_valid_o), .ar_ready_o(uart_ar_ready_i), .ar_addr_i(uart_ar_addr_o),
    .r_valid_o(uart_r_valid_i), .r_ready_i(uart_r_ready_o), .r_data_o(uart_r_data_i),
    .r_resp_o(uart_r_resp_i));

  tb_ame_stub u_ame (.clk_i(clk), .rst_ni(rst_n),
    .aw_valid_i(ame_aw_valid_o), .aw_ready_o(ame_aw_ready_i), .aw_addr_i(ame_aw_addr_o),
    .w_valid_i(ame_w_valid_o), .w_ready_o(ame_w_ready_i), .w_data_i(ame_w_data_o),
    .w_strb_i(ame_w_strb_o),
    .b_valid_o(ame_b_valid_i), .b_ready_i(ame_b_ready_o), .b_resp_o(ame_b_resp_i),
    .ar_valid_i(ame_ar_valid_o), .ar_ready_o(ame_ar_ready_i), .ar_addr_i(ame_ar_addr_o),
    .r_valid_o(ame_r_valid_i), .r_ready_i(ame_r_ready_o), .r_data_o(ame_r_data_i),
    .r_resp_o(ame_r_resp_i));

  tb_xmem_psram u_psram (.clk_i(clk), .a_i(xa), .di_i(xdi), .do_o(xdo),
    .ce_ni(xce), .oe_ni(xoe), .we_ni(xwe), .dump_req_i(1'b0));

  `include "tb_bfm_tasks.svh"

  task automatic dma_model(input logic [31:0] src, dst,
                           input int xcnt, ycnt,
                           input logic [31:0] sp_in, dp_in,
                           input bit sfix, dfix,
                           input int unsigned base_hi,  // 期望图像高 16 位(区分测试)
                           input int unsigned n);
  endtask

  longint cyc_cnt;
  always @(posedge clk) cyc_cnt <= cyc_cnt + 1;

  task automatic dma_run_measure(input logic [31:0] src, dst,
                                 input logic [31:0] xcnt, ycnt,
                                 input logic [31:0] sp, dp,
                                 input logic [31:0] ctrl,
                                 output longint cycles,
                                 output logic [31:0] st);
    longint t0;
    begin
      dma_cfg(src, dst, xcnt, ycnt, sp, dp, ctrl);
      t0 = cyc_cnt;
      dma_go((ctrl & 32'h10) != 0);
      dma_wait(st);
      cycles = cyc_cnt - t0;
    end
  endtask

  task automatic check_mem(input string tag, input logic [31:0] base,
                           input int unsigned n, input logic [31:0] pattern_base);
    logic [31:0] d;
    begin
      for (int i = 0; i < n; i++) begin
        axi_read(base + 4*i, d);
        if (d !== pattern_base + i) begin
          $display("[FAIL] %s[%0d] @%08h got=%08h exp=%08h",
                   tag, i, base + 4*i, d, pattern_base + i);
          bfm_errors = bfm_errors + 1;
        end
      end
      bfm_checks = bfm_checks + 1;
      if (bfm_errors == 0) $display("[ ok ] %s (%0d words) 逐字匹配", tag, n);
    end
  endtask

  task automatic test_1d_copy();
    logic [31:0] st;
    longint cyc;
    begin
      for (int i = 0; i < 16; i++) axi_write(32'h0000_0400 + 4*i, 32'h1000_0000 + i);
      dma_run_measure(32'h0000_0400, 32'h0000_0500, 32'd16, 32'd1,
                      0, 0, 32'h10, cyc, st);
      bfm_check_eq("1D DONE", {30'b0, st[1]}, 32'b1);
      bfm_check_eq("1D ERR",  {31'b0, st[2]}, 32'b0);
      check_mem("1D dst", 32'h0000_0500, 16, 32'h1000_0000);
      $display("[perf] OCSRAM→OCSRAM 16 字: %0d 周期 (%.2f 周期/字)",
               cyc, real'(cyc) / 16.0);
      axi_write(32'h2000_001C, 32'h2); // DONE W1C
    end
  endtask

  task automatic test_2d_strided();
    logic [31:0] st;
    longint cyc;
    int xc, yc, spitch, dpitch;
    begin
      xc = 5; yc = 4; spitch = 32; dpitch = 0;
      for (int y = 0; y < yc; y++)
        for (int x = 0; x < 8; x++)
          axi_write(32'h0000_0600 + y*spitch + 4*x, 32'h2000_0000 + y*8 + x);
      dma_run_measure(32'h0000_0600, 32'h0000_0800, xc, yc, spitch, dpitch,
                      32'h10, cyc, st);
      bfm_check_eq("2D-a DONE", {30'b0, st[1]}, 32'b1);
      for (int y = 0; y < yc; y++)
        for (int x = 0; x < xc; x++) begin
          logic [31:0] d;
          axi_read(32'h0000_0800 + 4*(y*xc + x), d);
          bfm_check_eq($sformatf("2D-a[%0d][%0d]", y, x), d, 32'h2000_0000 + y*8 + x);
        end
      axi_write(32'h2000_001C, 32'h2);

      xc = 4; yc = 3; spitch = 0; dpitch = 20;
      for (int i = 0; i < 12; i++) axi_write(32'h0000_0900 + 4*i, 32'h3000_0000 + i);
      dma_run_measure(32'h0000_0900, 32'h0000_0A00, xc, yc, spitch, dpitch,
                      32'h10, cyc, st);
      bfm_check_eq("2D-b DONE", {30'b0, st[1]}, 32'b1);
      for (int y = 0; y < yc; y++)
        for (int x = 0; x < xc; x++) begin
          logic [31:0] d;
          axi_read(32'h0000_0A00 + y*dpitch + 4*x, d);
          bfm_check_eq($sformatf("2D-b[%0d][%0d]", y, x), d, 32'h3000_0000 + y*xc + x);
        end
      axi_write(32'h2000_001C, 32'h2);

      xc = 2; yc = 3; spitch = 24; dpitch = 12;
      for (int y = 0; y < 3; y++)
        for (int x = 0; x < 6; x++)
          axi_write(32'h0000_0B00 + y*24 + 4*x, 32'h4000_0000 + y*6 + x);
      dma_run_measure(32'h0000_0B00, 32'h0000_0C00, xc, yc, spitch, dpitch,
                      32'h10, cyc, st);
      bfm_check_eq("2D-c DONE", {30'b0, st[1]}, 32'b1);
      for (int y = 0; y < yc; y++)
        for (int x = 0; x < xc; x++) begin
          logic [31:0] d;
          axi_read(32'h0000_0C00 + y*dpitch + 4*x, d);
          bfm_check_eq($sformatf("2D-c[%0d][%0d]", y, x), d, 32'h4000_0000 + y*6 + x);
        end
      axi_write(32'h2000_001C, 32'h2);
    end
  endtask

  task automatic test_fixed_modes();
    logic [31:0] st, d;
    longint cyc;
    begin
      axi_write(32'h0000_0D00, 32'h5A5A_5A5A);
      dma_run_measure(32'h0000_0D00, 32'h0000_0E00, 32'd4, 32'd4, 0, 0,
                      32'h14, cyc, st); // GO|IRQ_EN|SRC_FIXED
      bfm_check_eq("FIX-S DONE", {30'b0, st[1]}, 32'b1);
      for (int i = 0; i < 16; i++) begin
        axi_read(32'h0000_0E00 + 4*i, d);
        bfm_check_eq($sformatf("FIX-S[%0d]", i), d, 32'h5A5A_5A5A);
      end
      axi_write(32'h2000_001C, 32'h2);

      for (int i = 0; i < 8; i++) axi_write(32'h0000_0F00 + 4*i, 32'h6000_0000 + i);
      dma_run_measure(32'h0000_0F00, 32'h0000_0F80, 32'd4, 32'd2, 0, 0,
                      32'h18, cyc, st); // GO|IRQ_EN|DST_FIXED
      bfm_check_eq("FIX-D DONE", {30'b0, st[1]}, 32'b1);
      axi_read(32'h0000_0F80, d);
      bfm_check_eq("FIX-D 最后一字", d, 32'h6000_0007);
      axi_write(32'h2000_001C, 32'h2);
    end
  endtask

  task automatic test_errors();
    logic [31:0] st, d;
    longint cyc;
    begin
      dma_cfg(32'h0000_0102, 32'h0000_2000, 32'd4, 32'd1, 0, 0, 32'h0);
      dma_go(1'b0);
      dma_wait(st);
      $display("[dbg] align status=%08h", st);
      bfm_check_eq("ALIGN ERR", {31'b0, st[2]}, 32'b1);
      bfm_check_eq("ALIGN CODE", st[7:4], 32'd1);
      bfm_check_eq("ALIGN DONE", {31'b0, st[1]}, 32'b0);
      axi_write(32'h2000_001C, 32'h6); // W1C done|err

      dma_cfg(32'h2000_4000, 32'h0000_2100, 32'd4, 32'd1, 0, 0, 32'h0);
      $display("[dbg] bus test: cfg done");
      dma_go(1'b0);
      $display("[dbg] bus test: go done");
      dma_wait(st);
      $display("[dbg] bus status=%08h", st);
      bfm_check_eq("BUS ERR", {31'b0, st[2]}, 32'b1);
      bfm_check_eq("BUS CODE", st[7:4], 32'd2);
      axi_write(32'h2000_001C, 32'h6);

      dma_cfg(32'h4000_8000, 32'h4000_9000, 32'd64, 32'd16, 0, 0, 32'h0);
      dma_go(1'b0);
      repeat (10) @(posedge clk);
      bfm_check_eq("BUSY=1", {31'b0, dut.u_dma.busy_q}, 32'b1);
      axi_write(32'h2000_0000, 32'hDEAD_BEEF); // BUSY 中写 SRC 应被忽略
      axi_read(32'h2000_0000, d);
      bfm_check_eq("BUSY 写忽略", d, 32'h4000_8000);
      axi_write(32'h2000_0018, 32'h2);        // ABORT(W1P)
      dma_wait(st);
      $display("[dbg] abort status=%08h", st);
      bfm_check_eq("ABORT ERR", {31'b0, st[2]}, 32'b1);
      bfm_check_eq("ABORT CODE", st[7:4], 32'd3);
      axi_write(32'h2000_001C, 32'h6);

      axi_write(32'h0000_0540, 32'h7777_7777);
      dma_run_measure(32'h0000_0540, 32'h0000_0544, 32'd1, 32'd1, 0, 0, 32'h0, cyc, st);
      bfm_check_eq("ABORT 后可用 DONE", {30'b0, st[1]}, 32'b1);
      axi_read_check("ABORT 后数据", 32'h0000_0544, 32'h7777_7777);
      axi_write(32'h2000_001C, 32'h2);
    end
  endtask

  task automatic test_back_to_back();
    logic [31:0] st, d;
    longint cyc;
    begin
      for (int i = 0; i < 8; i++) axi_write(32'h0000_0560 + 4*i, 32'h8A00_0000 + i);
      dma_run_measure(32'h0000_0560, 32'h0000_0580, 32'd8, 32'd1, 0, 0, 32'h0, cyc, st);
      bfm_check_eq("B2B-1 DONE", {30'b0, st[1]}, 32'b1);
      dma_run_measure(32'h0000_0560, 32'h0000_05A0, 32'd8, 32'd1, 0, 0, 32'h0, cyc, st);
      bfm_check_eq("B2B-2 DONE", {30'b0, st[1]}, 32'b1);
      bfm_check_eq("B2B-2 ERR",  {31'b0, st[2]}, 32'b0);
      check_mem("B2B-1 dst", 32'h0000_0580, 8, 32'h8A00_0000);
      check_mem("B2B-2 dst", 32'h0000_05A0, 8, 32'h8A00_0000);
      axi_write(32'h2000_001C, 32'h2);
    end
  endtask

  task automatic test_throughput();
    logic [31:0] st;
    longint cyc;
    int unsigned n;
    real mbps;
    begin
      n = 256;
      for (int i = 0; i < n; i++) axi_write(32'h4002_0000 + 4*i, 32'hC000_0000 + i);
      dma_run_measure(32'h4002_0000, 32'h0000_0000, n[31:0], 32'd1, 0, 0, 32'h10, cyc, st);
      mbps = real'(n) * 4.0 * 120.0 / real'(cyc); // 4B/字 × 120MHz / 周期数 = MB/s
      $display("[perf] XMEM→OCSRAM  %0d 字: %0d 周期 = %.2f 周期/字 = %.1f MB/s",
               n, cyc, real'(cyc) / real'(n), mbps);
      check_mem("THR xm2oc 抽查", 32'h0000_0000, 8, 32'hC000_0000);
      axi_write(32'h2000_001C, 32'h2);

      dma_run_measure(32'h4002_0000, 32'h2000_1000, n[31:0], 32'd1, 0, 0, 32'h10, cyc, st);
      mbps = real'(n) * 4.0 * 120.0 / real'(cyc);
      $display("[perf] XMEM→AME WBUF %0d 字: %0d 周期 = %.2f 周期/字 = %.1f MB/s",
               n, cyc, real'(cyc) / real'(n), mbps);
      axi_write(32'h2000_001C, 32'h2);

      dma_run_measure(32'h0000_0000, 32'h0000_0400, n[31:0], 32'd1, 0, 0, 32'h10, cyc, st);
      mbps = real'(n) * 4.0 * 120.0 / real'(cyc);
      $display("[perf] OCSRAM→OCSRAM %0d 字: %0d 周期 = %.2f 周期/字 = %.1f MB/s",
               n, cyc, real'(cyc) / real'(n), mbps);
      axi_write(32'h2000_001C, 32'h2);

      dma_run_measure(32'h4002_0000, 32'h4003_0000, n[31:0], 32'd1, 0, 0, 32'h10, cyc, st);
      mbps = real'(n) * 4.0 * 120.0 / real'(cyc);
      $display("[perf] XMEM→XMEM   %0d 字: %0d 周期 = %.2f 周期/字 = %.1f MB/s",
               n, cyc, real'(cyc) / real'(n), mbps);
      axi_write(32'h2000_001C, 32'h2);
    end
  endtask

  initial begin
    rst_n = 1'b0;
    c_aw_valid = 0; c_w_valid = 0; c_ar_valid = 0; c_b_ready = 0; c_r_ready = 0;
    c_aw_addr = '0; c_w_data = '0; c_w_strb = '0; c_ar_addr = '0;
    cyc_cnt = 0;
    repeat (5) @(posedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);

    axi_read_check("DMA.STATUS 复位", 32'h2000_001C, 32'h0);
    test_1d_copy();
    test_2d_strided();
    test_fixed_modes();
    test_errors();
    test_back_to_back();
    test_throughput();

    $display("=== tb_dma: checks=%0d errors=%0d ===", bfm_checks, bfm_errors);
    if (bfm_errors == 0) $display("TB_DMA: PASS");
    else                 $display("TB_DMA: FAIL");
    $finish;
  end

  initial begin
    #20_000_000;
    $display("[FAIL] tb_dma 全局超时");
    $display("TB_DMA: FAIL");
    $finish;
  end

endmodule
