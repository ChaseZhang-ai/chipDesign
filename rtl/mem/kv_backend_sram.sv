`ifndef _AMECHIP_PKG_SV
 `include "amechip_pkg.sv"
`endif

module kv_backend_sram #(
  parameter int unsigned BANKS = amechip_pkg::KV_BANKS_DEF,
  parameter int unsigned CTX   = 128,
  parameter int unsigned BPAW  = 11 // = $clog2(CTX*16)
) (
  input  logic clk_i,
  input  logic rst_ni,

  input  logic [BANKS-1:0]      bp_cs_i,
  input  logic [BANKS-1:0]      bp_we_i,
  input  logic [BANKS*BPAW-1:0] bp_addr_i,
  input  logic [BANKS*32-1:0]   bp_wdata_i,
  output logic [BANKS*32-1:0]   bp_rdata_o,
  input  logic                  bp_layer_i, // 记录用,后端不区分层
  input  logic                  bp_kvt_i,
  output logic                  bp_done_o,
  output logic                  bp_err_o,
  output logic                  bp_ready_o
);

  localparam int unsigned DEPTH = 2 * CTX * 16;
  localparam int unsigned AWIN  = BPAW + 1;

  generate
    for (genvar b = 0; b < BANKS; b++) begin : g_bank
      logic [31:0] rd;
      sram_behav #(
        .WIDTH (32),
        .DEPTH (DEPTH)
      ) u_bank (
        .clk_i   (clk_i),
        .rst_ni  (rst_ni),
        .cs_i    (bp_cs_i[b]),
        .we_i    (bp_we_i[b]),
        .addr_i  ({bp_kvt_i, bp_addr_i[b*BPAW +: BPAW]}),
        .wdata_i (bp_wdata_i[b*32 +: 32]),
        .wstrb_i (4'b1111),
        .rdata_o (rd)
      );
      assign bp_rdata_o[b*32 +: 32] = rd;
    end
  endgenerate

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) bp_done_o <= 1'b0;
    else         bp_done_o <= |bp_cs_i;
  end

  assign bp_err_o = 1'b0;
  assign bp_ready_o = 1'b1;

  logic _unused;
  assign _unused = ^{bp_layer_i, 1'b0};

endmodule
