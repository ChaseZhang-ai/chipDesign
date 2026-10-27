`ifndef _AMECHIP_PKG_SV
 `include "amechip_pkg.sv"
`endif

module axi_decerr_slave (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        aw_valid_i,
  output logic        aw_ready_o,
  input  logic [31:0] aw_addr_i,
  input  logic        w_valid_i,
  output logic        w_ready_o,
  input  logic [31:0] w_data_i,
  input  logic [3:0]  w_strb_i,
  output logic        b_valid_o,
  input  logic        b_ready_i,
  output logic [1:0]  b_resp_o,
  input  logic        ar_valid_i,
  output logic        ar_ready_o,
  input  logic [31:0] ar_addr_i,
  output logic        r_valid_o,
  input  logic        r_ready_i,
  output logic [31:0] r_data_o,
  output logic [1:0]  r_resp_o
);

  logic wr_busy;
  wire wr_accept = aw_valid_i && w_valid_i && !wr_busy;
  assign aw_ready_o = !wr_busy;
  assign w_ready_o  = !wr_busy;
  assign b_resp_o   = amechip_pkg::AXI_DECERR;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) wr_busy <= 1'b0;
    else if (wr_accept)          wr_busy <= 1'b1;
    else if (wr_busy && b_ready_i) wr_busy <= 1'b0;
  end
  assign b_valid_o = wr_busy;

  logic rd_busy;
  wire rd_accept = ar_valid_i && !rd_busy;
  assign ar_ready_o = !rd_busy;
  assign r_resp_o   = amechip_pkg::AXI_DECERR;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) rd_busy <= 1'b0;
    else if (rd_accept)          rd_busy <= 1'b1;
    else if (rd_busy && r_ready_i) rd_busy <= 1'b0;
  end
  assign r_valid_o = rd_busy;
  assign r_data_o  = 32'h0;

  logic _unused;
  assign _unused = ^{aw_addr_i, w_data_i, w_strb_i, ar_addr_i};

endmodule
