`ifndef _AMECHIP_PKG_SV
 `include "amechip_pkg.sv"
`endif

interface clk_rst_if;

  logic clk;          // 唯一时钟(外部直入)
  logic rst_ni;       // 原始复位输入(异步断言)
  logic rst_n;        // 同步释放后的片内复位(全片分发)
  logic rst_busy;     // 释放同步中(仅观测/断言用)

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
