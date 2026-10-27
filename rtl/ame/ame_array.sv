`ifndef _AMECHIP_PKG_SV
 `include "amechip_pkg.sv"
`endif

module ame_array #(
  parameter int unsigned AME_M = amechip_pkg::AME_M_DEF,
  parameter int unsigned AME_N = amechip_pkg::AME_N_DEF
) (
  input logic clk,
  input logic rst_n,

  input logic               tld_en_i,
  input logic               tld_sel_i,
  input logic [5:0]         tld_n_i,
  input logic [8*AME_M-1:0] tld_row_i,

  input logic               xld_en_i,
  input logic               xld_sel_i,
  input logic [8*AME_M-1:0] xld_row_i,

  input logic        sel_i,
  input logic [5:0]  k_i,
  input logic        mac_en_i,
  input logic        mac_acc_i,
  input logic [5:0]  mac_n_eff_i,
  input logic        y_clr_i,

  input logic        y32_we_i,
  input logic [5:0]  y32_addr_i,
  input logic [31:0] y32_wdata_i,

  output logic [32*amechip_pkg::RQ_ENTRIES-1:0] y_rdata_o
);

  localparam int unsigned NW = (AME_N  > 1) ? $clog2(AME_N)  : 1;
  localparam int unsigned KW = (AME_M  > 1) ? $clog2(AME_M)  : 1;

  logic [7:0] tile_q [2][AME_N][AME_M];
  logic [7:0] x_q    [2][AME_M];

  always_ff @(posedge clk) begin
    if (tld_en_i) begin
      for (int k = 0; k < AME_M; k++)
        tile_q[tld_sel_i][tld_n_i[NW-1:0]][k] <= tld_row_i[8*k +: 8];
    end
  end

  always_ff @(posedge clk) begin
    if (xld_en_i) begin
      for (int k = 0; k < AME_M; k++)
        x_q[xld_sel_i][k] <= xld_row_i[8*k +: 8];
    end
  end

  logic [7:0] x_byte;
  assign x_byte = x_q[sel_i][k_i[KW-1:0]];

  logic [15:0] prod_q [AME_N];

  always_ff @(posedge clk) begin
    for (int n = 0; n < AME_N; n++)
      prod_q[n] <= mult8(tile_q[sel_i][n][k_i[KW-1:0]], x_byte);
  end

  logic [31:0] y_q [AME_N];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int n = 0; n < AME_N; n++) y_q[n] <= 32'd0;
    end else if (y_clr_i) begin
      for (int n = 0; n < AME_N; n++) y_q[n] <= 32'd0;
    end else if (y32_we_i) begin
      y_q[y32_addr_i[NW-1:0]] <= y32_wdata_i;
    end else if (mac_acc_i) begin
      for (int n = 0; n < AME_N; n++)
        if (5'(n) < mac_n_eff_i[4:0])
          y_q[n] <= sat_add32(y_q[n], prod_q[n]);
    end
  end

  function automatic logic [15:0] mult8 (input logic [7:0] a, input logic [7:0] b);
    mult8 = $signed(a) * $signed(b);
  endfunction

  function automatic logic [31:0] sat_add32 (input logic [31:0] acc, input logic [15:0] prod);
    logic signed [33:0] s;
    s = $signed({{2{acc[31]}}, acc}) + $signed({{18{prod[15]}}, prod});
    if (s > $signed(34'sd2147483647))
      sat_add32 = 32'h7FFF_FFFF;
    else if (s < -$signed(34'sd2147483648))
      sat_add32 = 32'h8000_0000;
    else
      sat_add32 = s[31:0];
  endfunction

  always_comb begin
    for (int n = 0; n < amechip_pkg::RQ_ENTRIES; n++) begin
      y_rdata_o[32*n +: 32] = (n < AME_N) ? y_q[n] : 32'd0;
    end
  end

endmodule
