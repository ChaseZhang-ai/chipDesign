`ifndef _AMECHIP_PKG_SV
 `include "amechip_pkg.sv"
`endif

module tb_sys_stub (
  input  logic clk_i,
  input  logic rst_ni,
  input  logic aw_valid_i, output logic aw_ready_o, input  logic [31:0] aw_addr_i,
  input  logic w_valid_i,  output logic w_ready_o,  input  logic [31:0] w_data_i,
  input  logic [3:0]  w_strb_i,
  output logic b_valid_o,  input  logic b_ready_i,  output logic [1:0] b_resp_o,
  input  logic ar_valid_i, output logic ar_ready_o, input  logic [31:0] ar_addr_i,
  output logic r_valid_o,  input  logic r_ready_i,  output logic [31:0] r_data_o,
  output logic [1:0] r_resp_o,
  output logic soft_irq_pulse_o
);
  logic        wr_busy, rd_busy;
  logic [2:0]  wa_q, ra_q;
  logic [31:0] wv_q;
  logic [31:0] scratch0_q, scratch1_q;

  wire wr_acc = aw_valid_i && w_valid_i && !wr_busy;
  wire rd_acc = ar_valid_i && !rd_busy;
  assign aw_ready_o = !wr_busy;
  assign w_ready_o  = !wr_busy;
  assign b_valid_o  = wr_busy;
  assign b_resp_o   = amechip_pkg::AXI_OKAY;
  assign ar_ready_o = !rd_busy;
  assign r_valid_o  = rd_busy;
  assign r_resp_o   = amechip_pkg::AXI_OKAY;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      wr_busy <= 1'b0; rd_busy <= 1'b0; wa_q <= '0; ra_q <= '0; wv_q <= '0;
      scratch0_q <= '0; scratch1_q <= '0;
      soft_irq_pulse_o <= 1'b0;
    end else begin
      soft_irq_pulse_o <= 1'b0;
      if (wr_acc) begin
        wa_q <= aw_addr_i[4:2]; wv_q <= w_data_i; wr_busy <= 1'b1;
        case (aw_addr_i[4:2])
          3'h4: scratch0_q <= w_data_i;              // 0x10 SCRATCH0
          3'h5: scratch1_q <= w_data_i;              // 0x14 SCRATCH1
          3'h6: soft_irq_pulse_o <= w_data_i[0];     // 0x18 SOFTIRQ_SET W1S
          3'h7: ;                                    // 0x1C SOFTIRQ_CLEAR W1C
          default: ;
        endcase
      end else if (wr_busy && b_ready_i) wr_busy <= 1'b0;
      if (rd_acc) begin
        ra_q <= ar_addr_i[4:2]; rd_busy <= 1'b1;
      end else if (rd_busy && r_ready_i) rd_busy <= 1'b0;
    end
  end

  always_comb begin
    case (ra_q)
      3'h0: r_data_o = amechip_pkg::SYS_ID_VAL;  // ID "AMCC"
      3'h1: r_data_o = amechip_pkg::SYS_VER_VAL; // VERSION 1.0.0
      3'h2: r_data_o = 32'h0;
      3'h4: r_data_o = scratch0_q;
      3'h5: r_data_o = scratch1_q;
      default: r_data_o = 32'h0;
    endcase
  end
endmodule

module tb_intc_stub (
  input  logic clk_i,
  input  logic rst_ni,
  input  logic aw_valid_i, output logic aw_ready_o, input  logic [31:0] aw_addr_i,
  input  logic w_valid_i,  output logic w_ready_o,  input  logic [31:0] w_data_i,
  input  logic [3:0]  w_strb_i,
  output logic b_valid_o,  input  logic b_ready_i,  output logic [1:0] b_resp_o,
  input  logic ar_valid_i, output logic ar_ready_o, input  logic [31:0] ar_addr_i,
  output logic r_valid_o,  input  logic r_ready_i,  output logic [31:0] r_data_o,
  output logic [1:0] r_resp_o,
  input  logic irq_dma_done_i,
  input  logic irq_dma_err_i,
  input  logic irq_kv_done_i,
  input  logic irq_kv_err_i,
  input  logic irq_soft_i,
  output logic irq_o
);
  logic        wr_busy, rd_busy;
  logic [1:0]  wa_q, ra_q;
  logic [31:0] wv_q;
  logic [31:0] en_q, pend_q;

  wire wr_acc = aw_valid_i && w_valid_i && !wr_busy;
  wire rd_acc = ar_valid_i && !rd_busy;
  assign aw_ready_o = !wr_busy;
  assign w_ready_o  = !wr_busy;
  assign b_valid_o  = wr_busy;
  assign b_resp_o   = amechip_pkg::AXI_OKAY;
  assign ar_ready_o = !rd_busy;
  assign r_valid_o  = rd_busy;
  assign r_resp_o   = amechip_pkg::AXI_OKAY;

  wire [31:0] edge_bits = {22'b0, irq_soft_i, 1'b0, irq_kv_err_i, irq_kv_done_i,
                           2'b00, irq_dma_err_i, irq_dma_done_i, 2'b00};

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      wr_busy <= 1'b0; rd_busy <= 1'b0; wa_q <= '0; ra_q <= '0; wv_q <= '0;
      en_q <= '0; pend_q <= '0;
    end else begin
      if (wr_acc) begin
        wa_q <= aw_addr_i[3:2]; wv_q <= w_data_i; wr_busy <= 1'b1;
      end else if (wr_busy && b_ready_i) wr_busy <= 1'b0;
      if (rd_acc) begin
        ra_q <= ar_addr_i[3:2]; rd_busy <= 1'b1;
      end else if (rd_busy && r_ready_i) rd_busy <= 1'b0;
      pend_q <= (pend_q | edge_bits |
                 ((wr_acc && aw_addr_i[3:2] == 2'h3) ? w_data_i : 32'b0))
                &
                ~((wr_acc && aw_addr_i[3:2] == 2'h2) ? w_data_i : 32'b0);
      if (wr_acc && aw_addr_i[3:2] == 2'h0) en_q <= w_data_i;
    end
  end

  always_comb begin
    case (ra_q)
      2'h0: r_data_o = en_q;
      2'h1: r_data_o = pend_q;
      default: r_data_o = 32'h0;
    endcase
  end
  assign irq_o = |(en_q & pend_q);
endmodule

module tb_uart_stub (
  input  logic clk_i,
  input  logic rst_ni,
  input  logic aw_valid_i, output logic aw_ready_o, input  logic [31:0] aw_addr_i,
  input  logic w_valid_i,  output logic w_ready_o,  input  logic [31:0] w_data_i,
  input  logic [3:0]  w_strb_i,
  output logic b_valid_o,  input  logic b_ready_i,  output logic [1:0] b_resp_o,
  input  logic ar_valid_i, output logic ar_ready_o, input  logic [31:0] ar_addr_i,
  output logic r_valid_o,  input  logic r_ready_i,  output logic [31:0] r_data_o,
  output logic [1:0] r_resp_o
);
  logic        wr_busy, rd_busy;
  logic [2:0]  wa_q, ra_q;
  logic [31:0] wv_q;
  logic [31:0] div_q, ctrl_q;

  wire wr_acc = aw_valid_i && w_valid_i && !wr_busy;
  wire rd_acc = ar_valid_i && !rd_busy;
  assign aw_ready_o = !wr_busy;
  assign w_ready_o  = !wr_busy;
  assign b_valid_o  = wr_busy;
  assign b_resp_o   = amechip_pkg::AXI_OKAY;
  assign ar_ready_o = !rd_busy;
  assign r_valid_o  = rd_busy;
  assign r_resp_o   = amechip_pkg::AXI_OKAY;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      wr_busy <= 1'b0; rd_busy <= 1'b0; wa_q <= '0; ra_q <= '0; wv_q <= '0;
      div_q <= 32'd1042; ctrl_q <= '0;
    end else begin
      if (wr_acc) begin
        wa_q <= aw_addr_i[4:2]; wv_q <= w_data_i; wr_busy <= 1'b1;
        case (aw_addr_i[4:2])
          3'h2: div_q  <= w_data_i;  // DIV
          3'h3: ctrl_q <= w_data_i;  // CTRL
          default: ;
        endcase
      end else if (wr_busy && b_ready_i) wr_busy <= 1'b0;
      if (rd_acc) begin
        ra_q <= ar_addr_i[4:2]; rd_busy <= 1'b1;
      end else if (rd_busy && r_ready_i) rd_busy <= 1'b0;
    end
  end

  always_comb begin
    case (ra_q)
      3'h1: r_data_o = 32'h0;   // RXDATA valid=0
      3'h2: r_data_o = div_q;
      3'h3: r_data_o = ctrl_q;
      3'h4: r_data_o = 32'h0;   // STAT
      default: r_data_o = 32'h0;
    endcase
  end
endmodule

module tb_ame_stub (
  input  logic clk_i,
  input  logic rst_ni,
  input  logic aw_valid_i, output logic aw_ready_o, input  logic [31:0] aw_addr_i,
  input  logic w_valid_i,  output logic w_ready_o,  input  logic [31:0] w_data_i,
  input  logic [3:0]  w_strb_i,
  output logic b_valid_o,  input  logic b_ready_i,  output logic [1:0] b_resp_o,
  input  logic ar_valid_i, output logic ar_ready_o, input  logic [31:0] ar_addr_i,
  output logic r_valid_o,  input  logic r_ready_i,  output logic [31:0] r_data_o,
  output logic [1:0] r_resp_o
);
  localparam int unsigned RAMW = 256; // 1KB/4
  logic        wr_busy, rd_busy;
  logic [12:0] wa_q, ra_q;
  logic [31:0] wv_q;
  logic [3:0]  wsb_q;
  logic [31:0] rd_ram_q;

  wire wr_acc = aw_valid_i && w_valid_i && !wr_busy;
  wire rd_acc = ar_valid_i && !rd_busy && !wr_acc && !wr_busy;
  assign aw_ready_o = !wr_busy;
  assign w_ready_o  = !wr_busy;
  assign ar_ready_o = !rd_busy && !wr_acc && !wr_busy;
  assign b_valid_o  = wr_busy;
  assign r_valid_o  = rd_busy;
  assign b_resp_o   = amechip_pkg::AXI_OKAY;
  assign r_resp_o   = amechip_pkg::AXI_OKAY;

  logic [31:0] wbuf [0:RAMW-1];
  logic [31:0] xbuf [0:RAMW-1];

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      wr_busy <= 1'b0; rd_busy <= 1'b0; wa_q <= '0; ra_q <= '0;
      wv_q <= '0; wsb_q <= '0; rd_ram_q <= '0;
      for (int i = 0; i < RAMW; i++) begin
        wbuf[i] <= '0; xbuf[i] <= '0;
      end
    end else begin
      if (wr_acc) begin
        wa_q <= aw_addr_i[12:0]; wv_q <= w_data_i; wsb_q <= w_strb_i;
        wr_busy <= 1'b1;
        if (aw_addr_i[12] == 1'b1) begin
          for (int k = 0; k < 4; k++) begin
            if (w_strb_i[k])
              wbuf[aw_addr_i[9:2]][8*k +: 8] <= w_data_i[8*k +: 8];
          end
        end else begin                   // XBUF(mod 1KB)
          for (int k = 0; k < 4; k++) begin
            if (w_strb_i[k])
              xbuf[aw_addr_i[9:2]][8*k +: 8] <= w_data_i[8*k +: 8];
          end
        end
      end else if (wr_busy && b_ready_i) wr_busy <= 1'b0;
      if (rd_acc) begin
        ra_q <= ar_addr_i[12:0]; rd_busy <= 1'b1;
        if (ar_addr_i[12] == 1'b1) rd_ram_q <= wbuf[ar_addr_i[9:2]];
        else                       rd_ram_q <= xbuf[ar_addr_i[9:2]];
      end else if (rd_busy && r_ready_i) rd_busy <= 1'b0;
    end
  end

  assign r_data_o = rd_ram_q;
endmodule

module tb_xmem_psram #(
  parameter int unsigned A_BITS = 23
) (
  input  logic              clk_i,
  input  logic [A_BITS-1:0] a_i,
  input  logic [15:0]       di_i,
  output logic [15:0]       do_o,
  input  logic              ce_ni,
  input  logic              oe_ni,
  input  logic              we_ni,
  input  logic              dump_req_i
);
  localparam int unsigned NW = 1 << (A_BITS - 1);
  logic [15:0] mem [0:NW-1];
  logic [15:0] do_q;
  logic [31:0] lcg_s;

  always_ff @(posedge clk_i) begin
    if (!ce_ni) begin
      if (!we_ni) mem[a_i[A_BITS-1:1]] <= di_i;
      if (!oe_ni) do_q <= mem[a_i[A_BITS-1:1]];
    end
  end
  assign do_o = do_q;

  initial begin
    lcg_s = 32'hACE1_2345;
    for (int i = 0; i < NW; i++) begin
      lcg_s = lcg_s * 32'h9E37_79B9 + 32'h517C_C1B7 + i;
      mem[i] = lcg_s[15:0];
    end
    do_q = '0;
  end

  integer dump_fd, dump_i;
  always @(posedge dump_req_i) begin
    dump_fd = $fopen("kv_dump_xmem.hex", "w");
    for (dump_i = 32'h200000; dump_i < 32'h220000; dump_i = dump_i + 1)
      $fwrite(dump_fd, "%04x\n", mem[dump_i]);
    $fclose(dump_fd);
    $display("[tb] PSRAM KV 区转储完成 -> kv_dump_xmem.hex");
  end

  function automatic logic [15:0] peek(input int unsigned hw_idx);
    peek = mem[hw_idx];
  endfunction
  task automatic poke(input int unsigned hw_idx, input logic [15:0] v);
    mem[hw_idx] = v;
  endtask
endmodule
