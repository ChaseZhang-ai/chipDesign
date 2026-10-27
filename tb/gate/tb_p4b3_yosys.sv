`timescale 1ns/1ps
module tb_p4b3_yosys;

  localparam int BIT_CYC = 13;
  localparam real CLKP = 10.0;
  localparam int RST_CYC = 20;

  logic clk = 1'b0;
  logic rst_ni = 1'b0;
  logic uart_tx, irq;
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

  wire        P_dutpin1 = dut.xmem_a_o[1];
  wire        P_hw0_0   = dut.\u_mem.u_core.u_memc.hw0_q[0] ;
  wire        P_hw0_15  = dut.\u_mem.u_core.u_memc.hw0_q[15] ;
  wire P_rq_s1_1 = dut.\u_mem.u_core.u_memc.rq_addr[1][1] ;
  wire P_rq_s2_1 = dut.\u_mem.u_core.u_memc.rq_addr[2][1] ;
  wire P_rq_s3_1 = dut.\u_mem.u_core.u_memc.rq_addr[3][1] ;
  wire P_wq_s0_1 = dut.\u_mem.u_core.u_memc.wq_addr[0][1] ;
  wire P_wq_s1_1 = dut.\u_mem.u_core.u_memc.wq_addr[1][1] ;
  wire P_ar_1    = dut.\u_mem.u_core.u_memc.ar_addr_i[1] ;

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
    if ($value$plusargs("XMEM_HEX=%s", xmem_hex)) $readmemh(xmem_hex, pmem);
  end

  integer cyc = 0, pfd;
  always @(posedge clk) cyc = cyc + 1;
  integer wq_force = 0;
  initial begin
    if ($value$plusargs("WQ_FORCE=%d", wq_force)) ;
  end

  initial begin
    pfd = $fopen("p4b3_yosys_trace.txt", "w");
    repeat (RST_CYC) @(posedge clk);
    rst_ni = 1'b1;
    while (cyc < (wq_force ? 1900 : 1700)) @(posedge clk);
    $fclose(pfd);
    $display("P4B3 YOSYS PROBE DONE");
    $finish;
  end

  initial begin
    while (cyc < 100) @(posedge clk);
    if (wq_force) begin
      while (cyc < 1700) @(posedge clk);
      force dut.\u_mem.u_core.u_memc.wq_addr[0][1] = 1'b1 ;
      force dut.\u_mem.u_core.u_memc.wq_addr[1][1] = 1'b1 ;
      force dut.\u_mem.u_core.u_memc.wq_addr[2][1] = 1'b1 ;
      force dut.\u_mem.u_core.u_memc.wq_addr[3][1] = 1'b1 ;
      $display("[P4B3] wq_addr[*][1] forced to 1 @c=%0d", cyc);
    end
  end

  always @(negedge clk)
    if (cyc > RST_CYC && xmem_ce_n === 1'b0)
      $fdisplay(pfd, "Y c=%0d ce=%b oe=%b a=%b pin1=%b hw0_0=%b rq_s1=%b s2=%b s3=%b wq0=%b wq1=%b ar1=%b",
                cyc, xmem_ce_n, xmem_oe_n, xmem_a, P_dutpin1, P_hw0_0,
                P_rq_s1_1, P_rq_s2_1, P_rq_s3_1, P_wq_s0_1, P_wq_s1_1, P_ar_1);

endmodule
