
module amechip_top_ports (
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


endmodule
