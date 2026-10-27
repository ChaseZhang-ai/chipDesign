`timescale 1ns/1ps
module tb_probe;
  logic clk = 1'b0;
  logic rst_ni = 1'b0;
  logic uart_tx, irq;
  logic [3:0] gpio;
  logic [15:0] xmem_di, xmem_do;
  logic [22:0] xmem_a;
  logic ce, oe, we, xclk;

  always #5 clk = ~clk;

  amechip_top dut (
    .clk_i(clk), .rst_ni(rst_ni),
    .uart_tx_o(uart_tx), .uart_rx_i(1'b1),
    .xmem_clk_o(xclk), .xmem_a_o(xmem_a),
    .xmem_di_i(xmem_di), .xmem_do_o(xmem_do),
    .xmem_ce_no(ce), .xmem_oe_no(oe), .xmem_we_no(we),
    .xmem_wait_i(1'b0),
    .gpio_i(4'h0), .gpio_o(gpio), .irq_o(irq)
  );

  initial begin
    $monitor("t=%0t rst=%b net15=%b uart=%b net37=%b gpio=%b ce=%b clk_net=%b",
             $time, rst_ni, dut.net15, uart_tx, dut.net37, gpio, ce, dut.clknet_2_1__leaf_clk_i);
    #50 rst_ni = 1;
    #2000 $finish;
  end
endmodule
