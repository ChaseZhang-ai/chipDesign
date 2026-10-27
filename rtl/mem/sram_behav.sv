`ifndef _AMECHIP_PKG_SV
 `include "amechip_pkg.sv"
`endif

module sram_behav #(
  parameter int unsigned WIDTH     = 32,
  parameter int unsigned DEPTH     = 1024,            // 字数(2 的幂)
  parameter int unsigned AW        = $clog2(DEPTH),
  parameter              INIT_FILE = ""               // "" = 不初始化
) (
  input  logic                 clk_i,
  input  logic                 rst_ni,   // 无复位逻辑,保留端口统一(未用)
  input  logic                 cs_i,     // 拍使能
  input  logic                 we_i,
  input  logic [AW-1:0]        addr_i,
  input  logic [WIDTH-1:0]     wdata_i,
  input  logic [WIDTH/8-1:0]   wstrb_i,
  output logic [WIDTH-1:0]     rdata_o   // cs 拍采样,下一拍有效;cs=0 保持
);

  logic [WIDTH-1:0] mem [0:DEPTH-1];

  always_ff @(posedge clk_i) begin
    if (cs_i) begin
      if (we_i) begin
        for (int b = 0; b < WIDTH/8; b++) begin
          if (wstrb_i[b]) begin
            mem[addr_i][8*b +: 8] <= wdata_i[8*b +: 8];
          end
        end
      end
      rdata_o <= mem[addr_i]; // 同拍写同地址:非阻塞读 → 旧值
    end
  end

  initial begin
    if (INIT_FILE != "") begin
      $readmemh(INIT_FILE, mem);
    end
  end

  logic _unused_rst;
  assign _unused_rst = ^rst_ni;

endmodule
