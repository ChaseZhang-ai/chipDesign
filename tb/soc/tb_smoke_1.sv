
`timescale 1ns/1ps

module tb_smoke_1;

  localparam int    BIT_CYC = 13;
  localparam real   CLKP    = 10.0;
  localparam int    NBYTES  = 12;

  logic       clk = 1'b0;
  logic       rst_ni = 1'b0;
  logic       uart_tx;
  logic       irq;
  logic [3:0] gpio;

  always #(CLKP/2.0) clk = ~clk;

  amechip_top dut (
    .clk_i      (clk),
    .rst_ni     (rst_ni),
    .uart_tx_o  (uart_tx),
    .uart_rx_i  (1'b1),
    .xmem_clk_o (),
    .xmem_a_o   (),
    .xmem_di_i  (16'h0),
    .xmem_do_o  (),
    .xmem_ce_no (),
    .xmem_oe_no (),
    .xmem_we_no (),
    .xmem_wait_i(1'b0),
    .gpio_i     (4'h0),
    .gpio_o     (gpio),
    .irq_o      (irq)
  );

  task automatic recv_byte (output logic [7:0] b);
    integer i;
    begin
      @(negedge uart_tx);
      #(BIT_CYC * CLKP / 2.0);
      if (uart_tx !== 1'b0) $display("[TB] WARN: start bit != 0");
      for (i = 0; i < 8; i++) begin
        #(BIT_CYC * CLKP);
        b[i] = uart_tx;
      end
      #(BIT_CYC * CLKP);
    end
  endtask

  logic [7:0] exp [0:NBYTES-1];
  logic [7:0] got [0:NBYTES-1];
  logic [7:0] b;
  integer     k, errs;
  integer     cycle_cnt;

  initial begin
    exp[ 0]=8'h50; exp[ 1]=8'h33; exp[ 2]=8'h44; exp[ 3]=8'h20; exp[ 4]=8'h42;
    exp[ 5]=8'h4F; exp[ 6]=8'h4F; exp[ 7]=8'h54; exp[ 8]=8'h20; exp[ 9]=8'h4F;
    exp[10]=8'h4B; exp[11]=8'h0A;
  end

  initial begin
    cycle_cnt = 0;
    repeat (400000) begin
      @(posedge clk);
      cycle_cnt = cycle_cnt + 1;
    end
    $display("[TB] TIMEOUT: %0d cycles, uart bytes so far:", cycle_cnt);
    for (k = 0; k < NBYTES; k++) $write("%c", got[k]);
    $write("\n");
    $display("SMOKE1 FAIL");
    $finish;
  end

  initial begin
    if (!$test$plusargs("QUIET"))
      $display("[TB] smoke_1: 全 stub boot 冒烟(DIV=%0d)", BIT_CYC);
    rst_ni = 1'b0;
    repeat (10) @(posedge clk);
    rst_ni = 1'b1;

    for (k = 0; k < NBYTES; k++) begin
      recv_byte(b);
      got[k] = b;
    end

    errs = 0;
    for (k = 0; k < NBYTES; k++) begin
      if (got[k] !== exp[k]) begin
        $display("[TB] MISMATCH [%0d]: got=%02x exp=%02x", k, got[k], exp[k]);
        errs = errs + 1;
      end
    end

    $write("[TB] UART: ");
    for (k = 0; k < NBYTES; k++) $write("%c", got[k]);
    $write("\n");

    repeat (2000) @(posedge clk);
    if (gpio[0] !== 1'b1)
      $display("[TB] WARN: CPU 未进入 WFI (gpio=%b)", gpio);

    if (errs == 0) begin
      $display("[TB] boot 字符串逐字节一致; irq=%b gpio=%b", irq, gpio);
      $display("SMOKE1 PASS");
    end else begin
      $display("SMOKE1 FAIL (%0d mismatches)", errs);
    end
    $finish;
  end

  initial begin
    if ($test$plusargs("WAVE")) begin
      $dumpfile("smoke1.vcd");
      $dumpvars(0, tb_smoke_1);
    end
  end

endmodule
