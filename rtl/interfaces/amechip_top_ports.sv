
module amechip_top_ports (
  input  wire         clk_i,        // 唯一时钟,120MHz 目标
  input  wire         rst_ni,       // 异步进入同步释放,低有效

  output wire         uart_tx_o,
  input  wire         uart_rx_i,

  output wire         xmem_clk_o,   // = clk_i 直通
  output wire [22:0]  xmem_a_o,     // 字节地址 A[22:0](器件按 A[22:1] 半字编址)
  input  wire [15:0]  xmem_di_i,    // 器件 → 芯片
  output wire [15:0]  xmem_do_o,    // 芯片 → 器件
  output wire         xmem_ce_no,   // 片选,低有效
  output wire         xmem_oe_no,   // 读使能,低有效
  output wire         xmem_we_no,   // 写使能,低有效
  input  wire         xmem_wait_i,  // 器件 wait(TB 接 0)

  input  wire [3:0]   gpio_i,
  output wire [3:0]   gpio_o,

  output wire         irq_o
);


endmodule
