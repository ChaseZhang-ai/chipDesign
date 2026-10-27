`ifndef _AMECHIP_PKG_SV
 `include "amechip_pkg.sv"
`endif

module ame_buf_rf #(
  parameter int unsigned DEPTH  = 1024,             // 字节数(2 的幂,4 的倍数)
  parameter int unsigned ROW_B  = 16,               // 宽读口每次读出的字节数(≤ DEPTH)
  parameter int unsigned AW     = $clog2(DEPTH)     // 字节地址宽
) (
  input logic clk,

  input logic        we_i,
  input logic [31:0] waddr_i,     // buffer 内字节偏移(已 mod DEPTH,4 对齐)
  input logic [31:0] wdata_i,
  input logic [3:0]  wstrb_i,

  input  logic        rd32_go_i,
  input  logic [31:0] raddr32_i,  // 4 对齐
  output logic [31:0] rdata32_o,

  input  logic              rd_row_go_i,
  input  logic [AW-1:0]     raddr_row_i,
  output logic [8*ROW_B-1:0] rdata_row_o
);

  logic [7:0] mem [DEPTH];

  always_ff @(posedge clk) begin
    if (we_i) begin
      if (wstrb_i[0]) mem[waddr_i[AW-1:0]]                 <= wdata_i[7:0];
      if (wstrb_i[1]) mem[waddr_i[AW-1:0] + AW'(1)]        <= wdata_i[15:8];
      if (wstrb_i[2]) mem[waddr_i[AW-1:0] + AW'(2)]        <= wdata_i[23:16];
      if (wstrb_i[3]) mem[waddr_i[AW-1:0] + AW'(3)]        <= wdata_i[31:24];
    end
  end

  always_ff @(posedge clk) begin
    if (rd32_go_i) begin
      rdata32_o <= {mem[raddr32_i[AW-1:0] + AW'(3)],
                    mem[raddr32_i[AW-1:0] + AW'(2)],
                    mem[raddr32_i[AW-1:0] + AW'(1)],
                    mem[raddr32_i[AW-1:0]]};
    end else if (rd_row_go_i) begin
      for (int b = 0; b < ROW_B; b++)
        rdata_row_o[8*b +: 8] <= mem[raddr_row_i + AW'(b)];
    end
  end

endmodule
