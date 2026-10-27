`ifndef _AMECHIP_PKG_SV
 `include "amechip_pkg.sv"
`endif

interface clk_rst_if;

  logic clk;
  logic rst_ni;
  logic rst_n;
  logic rst_busy;

  logic [1:0] sync_ff;
  always_ff @(posedge clk or negedge rst_ni) begin
    if (!rst_ni) begin
      sync_ff <= 2'b00;
    end else begin
      sync_ff <= {sync_ff[0], 1'b1};
    end
  end
  assign rst_n    = sync_ff[1];
  assign rst_busy = (sync_ff != 2'b11);

  modport src (input clk, rst_ni, output rst_n, rst_busy);

endinterface
