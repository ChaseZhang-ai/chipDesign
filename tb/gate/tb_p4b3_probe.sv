`timescale 1ns/1ps

module tb_p4b3_probe;

  localparam int BIT_CYC = 13;
  localparam real CLKP = 10.0;
  localparam int RST_CYC = 20;
  localparam int DEFAULT_MAX_CYC = 63000;

  logic clk = 1'b0;
  logic rst_ni = 1'b0;
  logic uart_tx;
  logic irq;
  logic [3:0] gpio;
  logic [15:0] xmem_di;
  logic [22:0] xmem_a;
  logic [15:0] xmem_do;
  logic xmem_ce_n, xmem_oe_n, xmem_we_n, xmem_clk;

  integer PROBE_MAX_CYC = DEFAULT_MAX_CYC;
  reg [1023:0] trace_name;
  reg [1023:0] pmc_str;

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

`ifdef RTLREF
  `include "p4b3_rtl_probes.vh"
`else
  `include "p4b3_gate_probes.vh"
`endif

`ifdef XINIT
  initial begin
    `include "p4b3_xinit.vh"
    $display("[p4b_tb] XINIT: memc queue slots bits[1:0] forced 0 (protocol-const power-up)");
  end
`endif

  localparam int unsigned A_BITS = 23;
  logic [15:0] pmem [0:(1<<(A_BITS-1))-1];
  logic [15:0] pdo_q;
  integer dev_x_idx = 0, dev_loads = 0, dev_x_idx_printed = 0;
  integer dev_pmem_x = 0, dev_pmem_x_printed = 0;
  always_ff @(posedge clk) begin
    if (!xmem_ce_n) begin
      if (!xmem_we_n) pmem[xmem_a[A_BITS-1:1]] <= xmem_do;
      if (!xmem_oe_n) begin
        pdo_q <= pmem[xmem_a[A_BITS-1:1]];
        dev_loads = dev_loads + 1;
        if ((^xmem_a[A_BITS-1:1]) === 1'bx) begin
          dev_x_idx = dev_x_idx + 1;
          if (dev_x_idx_printed < 12) begin
            dev_x_idx_printed = dev_x_idx_printed + 1;
            $display("[P4B3] DEV_IDX_X t=%0t a=%h", $time, xmem_a);
          end
        end else if ((^pmem[xmem_a[A_BITS-1:1]]) === 1'bx) begin
          dev_pmem_x = dev_pmem_x + 1;
          if (dev_pmem_x_printed < 12) begin
            dev_pmem_x_printed = dev_pmem_x_printed + 1;
            $display("[P4B3] DEV_PMEM_X t=%0t a=%h val=%h", $time, xmem_a, pmem[xmem_a[A_BITS-1:1]]);
          end
        end
      end
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
    if ($value$plusargs("PROBE_MAX_CYC=%d", PROBE_MAX_CYC))
      $display("[p4b_tb] probe cap = %0d cycles", PROBE_MAX_CYC);
    if (!$value$plusargs("TRACE=%s", trace_name)) trace_name = "p4b3_memc_trace.txt";
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
    if (!$value$plusargs("UART_BIN=%s", uart_bin)) uart_bin = "uart_p4b3_probe.bin";
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
  integer pfd, pfd2;
  integer cnt_act = 0, cnt_push_w = 0, cnt_push_r = 0;
  integer a_x = 0, di_x = 0, hw0_x = 0, rqh_x = 0, wqh_x = 0;
  integer cone_x = 0, xb_x = 0;
  reg [22:0] rqh;
  reg [31:0] wqh;
  reg [1:0]  wq_wp_d = 2'hx, rq_wp_d = 2'hx;

  function automatic logic [22:0] rqsel(input logic [1:0] i);
    case (i)
      2'd0: rqsel = P_rq_addr_0;
      2'd1: rqsel = P_rq_addr_1;
      2'd2: rqsel = P_rq_addr_2;
      default: rqsel = P_rq_addr_3;
    endcase
  endfunction

  function automatic logic [31:0] wqsel(input logic [1:0] i);
    case (i)
      2'd0: wqsel = P_wq_data_0;
      2'd1: wqsel = P_wq_data_1;
      2'd2: wqsel = P_wq_data_2;
      default: wqsel = P_wq_data_3;
    endcase
  endfunction

  always @(posedge clk) cyc = cyc + 1;

  always @(negedge clk) begin
    if (cyc > RST_CYC && cyc <= PROBE_MAX_CYC) begin
      if (P_wq_wp !== wq_wp_d && wq_wp_d !== 2'hx) begin
        cnt_push_w = cnt_push_w + 1;
        $display("[P4B3] WPUSH c=%0d slot=%0d st=%b", cyc, P_wq_wp, P_st_q);
      end
      if (P_rq_wp !== rq_wp_d && rq_wp_d !== 2'hx) begin
        cnt_push_r = cnt_push_r + 1;
        $display("[P4B3] RPUSH c=%0d slot=%0d st=%b", cyc, P_rq_wp, P_st_q);
      end
      wq_wp_d = P_wq_wp;
      rq_wp_d = P_rq_wp;

      if (xmem_ce_n === 1'b0) begin
        cnt_act = cnt_act + 1;
        rqh = rqsel(P_rq_rp);
        wqh = wqsel(P_wq_rp);
        $fdisplay(pfd, "A c=%0d st=%b ce=%b oe=%b we=%b a=%h do=%h di=%h hw0=%h rqh=%h wqh=%b rrp=%b rwp=%b rcnt=%b wrp=%b wwp=%b wcnt=%b",
                  cyc, P_st_q, xmem_ce_n, xmem_oe_n, xmem_we_n,
                  xmem_a, xmem_do, xmem_di, P_hw0_q, rqh, wqh,
                  P_rq_rp, P_rq_wp, P_rq_cnt, P_wq_rp, P_wq_wp, P_wq_cnt);
        if ((^xmem_a) === 1'bx) begin
          a_x = a_x + 1;
          if (a_x <= 12) $display("[P4B3] A_X c=%0d a=%h st=%b oe=%b we=%b", cyc, xmem_a, P_st_q, xmem_oe_n, xmem_we_n);
        end
        if ((^xmem_di) === 1'bx && xmem_oe_n === 1'b0) begin
          di_x = di_x + 1;
          if (di_x <= 12) $display("[P4B3] DI_X c=%0d a=%h di=%h st=%b", cyc, xmem_a, xmem_di, P_st_q);
        end
        if ((^P_hw0_q) === 1'bx && cnt_act > 6) begin
          hw0_x = hw0_x + 1;
          if (hw0_x <= 12) $display("[P4B3] HW0_X c=%0d a=%h di=%h hw0=%h", cyc, xmem_a, xmem_di, P_hw0_q);
        end
        if ((^rqh) === 1'bx && xmem_oe_n === 1'b0 && xmem_we_n === 1'b1) begin
          rqh_x = rqh_x + 1;
          if (rqh_x <= 12) $display("[P4B3] RQH_X c=%0d rp=%0b rqh=%h a=%h", cyc, P_rq_rp, rqh, xmem_a);
        end
        if ((^wqh) === 1'bx && xmem_we_n === 1'b0) begin
          wqh_x = wqh_x + 1;
          if (wqh_x <= 12) $display("[P4B3] WQH_X c=%0d rp=%0b wqh=%h a=%h", cyc, P_wq_rp, wqh, xmem_a);
        end

`ifndef RTLREF
        if ((^xmem_a[3:0]) === 1'bx) begin
          cone_x = cone_x + 1;
          if (cone_x <= 12)
            $display("[P4B3] CONE c=%0d a=%h st=%b rs=%b rla=%h ar=%h | a0in=%b%b%b%b%b o=%b | a3in=%b%b%b%b%b o=%b",
                     cyc, xmem_a, P_st_q, P_r_state, P_r_l_addr, P_ar_addr_i,
                     C_035551, P_ar_addr_i_0, C_064887, C_net19822, C_064891, C_net38,
                     C_035582, C_net33615, P_ar_addr_i_3, C_035551, C_064905, C_net54);
        end
        if (cyc >= 1420 && cyc <= 1700)
          $fdisplay(pfd2, "C c=%0d st6=%b%b%b%b a=%b pin1=%b dutpin1=%b n49=%b m4589=%b o64894=%b o64893=%b inv64893=%b sl0=%b sl1=%b sl2=%b sl3=%b s0=%b s1=%b pre=%b ar1=%b g551=%b D=%b",
                    cyc, P_st_q_5, P_st_q_4, P_r_valid_o, P_st_q, xmem_a, xmem_a[1], P_dutpin1, C_net49, C_035589, C_064894, C_064893, C_035577,
                    P_rq_addr_0[1], P_rq_addr_1[1], P_rq_addr_2[1], P_rq_addr_3[1],
                    C_net27144, C_net26535, C_net33615, P_ar_addr_i_1, C_035551, C_net19451);
`endif
        if ((^P_r_state) === 1'bx || (^P_r_l_addr) === 1'bx || (^P_ar_addr_i) === 1'bx) begin
          xb_x = xb_x + 1;
          if (xb_x <= 12)
            $display("[P4B3] XB_X c=%0d rs=%b rla=%h ar=%h", cyc, P_r_state, P_r_l_addr, P_ar_addr_i);
        end
        if (cyc >= 1420 && cyc <= 1700 && ((cyc & 1) == 0))
          $fdisplay(pfd2, "C c=%0d st=%b a=%h rs=%b rla=%h ar=%h a0=%b/%b/%b/%b/%b->%b a3=%b/%b/%b/%b/%b->%b",
                    cyc, P_st_q, xmem_a, P_r_state, P_r_l_addr, P_ar_addr_i,
                    C_035551, P_ar_addr_i_0, C_064887, C_net19822, C_064891, C_net38,
                    C_035582, C_net33615, P_ar_addr_i_3, C_035551, C_064905, C_net54);
      end
    end
  end

  initial begin
    pfd = 0;
    $display("[p4b_tb] reset (P4B3 probe)");
    pfd = $fopen(trace_name, "w");
`ifndef RTLREF
    pfd2 = $fopen("p4b3_cone_trace.txt", "w");
`endif
    repeat (RST_CYC) @(posedge clk);
    rst_ni = 1'b1;

    while (cyc < PROBE_MAX_CYC) @(posedge clk);

    $fflush(pfd);
    $fclose(pfd);
    $display("\n[p4b_tb] ---- probe window closed at cyc %0d ----", cyc);
    $display("[p4b_tb] uart bytes so far = %0d", nbytes);
    $display("[p4b_tb] active cycles=%0d push_w=%0d push_r=%0d", cnt_act, cnt_push_w, cnt_push_r);
    $display("[P4B3] X counts: a_x=%0d di_x=%0d hw0_x=%0d rqh_x=%0d wqh_x=%0d cone_x=%0d xb_x=%0d",
             a_x, di_x, hw0_x, rqh_x, wqh_x, cone_x, xb_x);
    $display("[P4B3] device: loads=%0d idx_x=%0d pmem_x=%0d", dev_loads, dev_x_idx, dev_pmem_x);
    $display("P4B3 PROBE DONE");
    $finish;
  end

endmodule
