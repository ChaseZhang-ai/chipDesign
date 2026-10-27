`timescale 1ns/1ps

module tb_gate_boot;

  localparam int BIT_CYC = 13;
  localparam real CLKP = 10.0;
  localparam int RST_CYC = 20;
  localparam int IDLE_CYC = 2000;
  localparam int MAX_CYC = 300000;

  logic clk = 1'b0;
  logic rst_ni = 1'b0;
  logic uart_tx;
  logic irq;
  logic [3:0] gpio;
  logic [15:0] xmem_di;
  logic [22:0] xmem_a;
  logic [15:0] xmem_do;
  logic xmem_ce_n, xmem_oe_n, xmem_we_n, xmem_clk;

  always #(CLKP/2.0) clk = ~clk;

  amechip_top dut (
    .clk_i(clk), .rst_ni(rst_ni),
    .uart_tx_o(uart_tx), .uart_rx_i(1'b1),
    .xmem_clk_o(xmem_clk), .xmem_a_o(xmem_a),
    .xmem_di_i(xmem_di), .xmem_do_o(xmem_do),
    .xmem_ce_no(xmem_ce_n), .xmem_oe_no(xmem_oe_n), .xmem_we_no(xmem_we_n),
    .xmem_wait_i(1'b0),
    .gpio_i(4'h0), .gpio_o(gpio), .irq_o(irq)
  );

  localparam int unsigned A_BITS = 23;
  logic [15:0] pmem [0:(1<<(A_BITS-1))-1];
  logic [15:0] pdo_q;
  always_ff @(posedge clk) begin
    if (!xmem_ce_n) begin
      if (!xmem_we_n) pmem[xmem_a[A_BITS-1:1]] <= xmem_do;
      if (!xmem_oe_n) pdo_q <= pmem[xmem_a[A_BITS-1:1]];
    end
  end
  assign xmem_di = pdo_q;
  reg [1023:0] xmem_hex;
  initial begin
    pdo_q = 16'h0000;
    if ($value$plusargs("XMEM_HEX=%s", xmem_hex)) begin
      $readmemh(xmem_hex, pmem);
      $display("[p4b_tb] XMEM loaded %0s", xmem_hex);
    end
  end

  logic [7:0] rx_byte;
  integer nbytes = 0;
  logic [7:0] rx_all [0:65535];
  integer ufd;
  reg [1023:0] uart_bin;
  integer last_byte_cyc = 0;

  task automatic recv_byte(output logic [7:0] b);
    integer i;
    begin
      @(negedge uart_tx);
      #(BIT_CYC * CLKP / 2.0);
      for (i = 0; i < 8; i++) begin
        #(BIT_CYC * CLKP);
        b[i] = uart_tx;
      end
      #(BIT_CYC * CLKP);
    end
  endtask

  initial begin
    if (!$value$plusargs("UART_BIN=%s", uart_bin)) uart_bin = "uart_gate.bin";
    ufd = $fopen(uart_bin, "wb");
    forever begin
      recv_byte(rx_byte);
      if (nbytes < 65536) rx_all[nbytes] = rx_byte;
      $fwrite(ufd, "%c", rx_byte);
      $fflush(ufd);
      nbytes = nbytes + 1;
      last_byte_cyc = cyc;
      $write("%c", rx_byte);
      $fflush();
    end
  end

  integer cyc = 0;
  integer first_x_cyc = -1;
  integer all_known_cyc = -1;
  integer x_uart = 0, x_xmem_a = 0, x_xmem_do = 0, x_gpio = 0, x_irq = 0;
  integer x_xmem_ce = 0, x_xmem_oe = 0, x_xmem_we = 0, x_xmem_clk = 0;
  integer x_after_known = 0;

  function automatic logic any_x;
    any_x = (^uart_tx === 1'bx) || (^xmem_a === 1'bx) || (^xmem_do === 1'bx) ||
            (^gpio === 1'bx) || (^irq === 1'bx) || (^xmem_ce_n === 1'bx) ||
            (^xmem_oe_n === 1'bx) || (^xmem_we_n === 1'bx) || (^xmem_clk === 1'bx);
  endfunction

  always @(posedge clk) begin
    cyc = cyc + 1;
    if (cyc > RST_CYC) begin
      if (^uart_tx   === 1'bx) x_uart    = x_uart + 1;
      if (^xmem_a    === 1'bx) x_xmem_a  = x_xmem_a + 1;
      if (^xmem_do   === 1'bx) x_xmem_do = x_xmem_do + 1;
      if (^gpio      === 1'bx) x_gpio    = x_gpio + 1;
      if (^irq       === 1'bx) x_irq     = x_irq + 1;
      if (^xmem_ce_n === 1'bx) x_xmem_ce = x_xmem_ce + 1;
      if (^xmem_oe_n === 1'bx) x_xmem_oe = x_xmem_oe + 1;
      if (^xmem_we_n === 1'bx) x_xmem_we = x_xmem_we + 1;
      if (^xmem_clk  === 1'bx) x_xmem_clk = x_xmem_clk + 1;
      if (first_x_cyc < 0 && any_x()) first_x_cyc = cyc;
      if (all_known_cyc < 0 && !any_x()) begin
        all_known_cyc = cyc;
        $display("[p4b_tb] all top-level outputs known from cyc %0d", cyc);
      end
      if (all_known_cyc >= 0 && any_x()) begin
        x_after_known = x_after_known + 1;
        if (x_after_known <= 20)
          $display("[p4b_tb] X AFTER KNOWN @cyc %0d: uart=%b a=%h do=%h gpio=%h irq=%b ce=%b oe=%b we=%b clk=%b",
                   cyc, uart_tx, xmem_a, xmem_do, gpio, irq,
                   xmem_ce_n, xmem_oe_n, xmem_we_n, xmem_clk);
      end
    end
  end

  integer errs;
  initial begin
    errs = 0;
    $display("[p4b_tb] reset");
    repeat (RST_CYC) @(posedge clk);
    rst_ni = 1'b1;

    while (nbytes == 0 && cyc < MAX_CYC) @(posedge clk);
    while (nbytes > 0 && (cyc - last_byte_cyc) < IDLE_CYC && cyc < MAX_CYC)
      @(posedge clk);

    repeat (100) @(posedge clk);
    $fclose(ufd);

    $display("\n[p4b_tb] ---- UART (%0d bytes) ----", nbytes);
    for (integer i = 0; i < nbytes; i = i + 1) $write("%c", rx_all[i]);
    $write("\n");

    $display("[p4b_tb] cycles=%0d", cyc);
    $display("[p4b_tb] X-scan: first_x_cyc=%0d all_known_cyc=%0d x_after_known=%0d",
             first_x_cyc, all_known_cyc, x_after_known);
    $display("[p4b_tb] X-scan counts (cyc>%0d): uart=%0d xmem_a=%0d xmem_do=%0d gpio=%0d irq=%0d ce=%0d oe=%0d we=%0d clk=%0d",
             RST_CYC, x_uart, x_xmem_a, x_xmem_do, x_gpio, x_irq,
             x_xmem_ce, x_xmem_oe, x_xmem_we, x_xmem_clk);
    if (nbytes == 0) begin
      $display("[p4b_tb] FATAL: no UART byte");
      errs = errs + 1;
    end
    if (cyc >= MAX_CYC) begin
      $display("[p4b_tb] WARN: hit MAX_CYC");
    end
    $display("P4B GATE BOOT %s (%0d errors)", (errs == 0) ? "PASS" : "FAIL", errs);
    $finish;
  end

endmodule
