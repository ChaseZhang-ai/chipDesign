`ifndef _AMECPU_PKG_SV
 `include "amecpu_pkg.sv"
`endif

module cpu_regfile (
  input  logic              clk_i,
  input  logic              rst_ni,
  input  logic [4:0]        raddr1_i,
  output logic [31:0]       rdata1_o,
  input  logic [4:0]        raddr2_i,
  output logic [31:0]       rdata2_o,
  input  logic              we_i,
  input  logic [4:0]        waddr_i,
  input  logic [31:0]       wdata_i
);

  logic [31:0] regs [0:31];

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      for (int i = 0; i < 32; i++) regs[i] <= 32'h0;
    end else if (we_i && waddr_i != 5'h0) begin
      regs[waddr_i] <= wdata_i;
    end
  end

  wire wr_hit1 = we_i && (waddr_i != 5'h0) && (waddr_i == raddr1_i);
  wire wr_hit2 = we_i && (waddr_i != 5'h0) && (waddr_i == raddr2_i);

  assign rdata1_o = (raddr1_i == 5'h0) ? 32'h0
                  : wr_hit1            ? wdata_i
                  :                      regs[raddr1_i];
  assign rdata2_o = (raddr2_i == 5'h0) ? 32'h0
                  : wr_hit2            ? wdata_i
                  :                      regs[raddr2_i];

endmodule
