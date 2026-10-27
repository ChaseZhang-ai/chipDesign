`ifndef _AMECHIP_PKG_SV
 `include "amechip_pkg.sv"
`endif

module ame_rqtab (
  input logic clk,
  input logic rst_n,

  input logic        we_i,
  input logic [4:0]  waddr_i,
  input logic [31:0] wM_i,
  input logic [5:0]  wS_i,
  input logic        wround_i,

  input  logic [4:0] ra_idx_i,
  output logic [31:0] ra_m_o,
  output logic [5:0]  ra_s_o,
  output logic        ra_round_o,

  input  logic [19:0]  rb_idx_i,
  output logic [4*32-1:0] rb_m_o,
  output logic [4*6-1:0]  rb_s_o,
  output logic [3:0]      rb_round_o
);

  logic [31:0] m_q    [amechip_pkg::RQ_ENTRIES];
  logic [5:0]  s_q    [amechip_pkg::RQ_ENTRIES];
  logic        rnd_q  [amechip_pkg::RQ_ENTRIES];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < amechip_pkg::RQ_ENTRIES; i++) begin
        m_q[i]   <= 32'd0;
        s_q[i]   <= 6'd0;
        rnd_q[i] <= 1'b0;
      end
    end else if (we_i) begin
      m_q[waddr_i]   <= wM_i;
      s_q[waddr_i]   <= wS_i;
      rnd_q[waddr_i] <= wround_i;
    end
  end

  assign ra_m_o    = m_q[ra_idx_i];
  assign ra_s_o    = s_q[ra_idx_i];
  assign ra_round_o = rnd_q[ra_idx_i];

  always_comb begin
    for (int j = 0; j < 4; j++) begin
      rb_m_o[32*j +: 32] = m_q[rb_idx_i[5*j +: 5]];
      rb_s_o[6*j +: 6]   = s_q[rb_idx_i[5*j +: 5]];
      rb_round_o[j]      = rnd_q[rb_idx_i[5*j +: 5]];
    end
  end

endmodule
