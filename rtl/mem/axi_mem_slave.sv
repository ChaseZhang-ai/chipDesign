`ifndef _AMECHIP_PKG_SV
 `include "amechip_pkg.sv"
`endif

module axi_mem_slave #(
  parameter int unsigned DEPTH     = 1024,  // 32-bit 字数
  parameter              INIT_FILE = "",
  parameter bit          IS_ROM    = 1'b0
) (
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

  localparam int unsigned AWW = $clog2(DEPTH);

  logic wr_busy;

  wire wr_accept = aw_valid_i && w_valid_i && !wr_busy;

  assign aw_ready_o = !wr_busy;
  assign w_ready_o  = !wr_busy;
  assign b_resp_o   = IS_ROM ? amechip_pkg::AXI_SLVERR : amechip_pkg::AXI_OKAY;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      wr_busy <= 1'b0;
    end else begin
      if (wr_accept) begin
        wr_busy <= 1'b1;
      end else if (wr_busy && b_ready_i) begin
        wr_busy <= 1'b0;
      end
    end
  end

  assign b_valid_o = wr_busy; // 接受拍提交,下一拍 B

  logic rd_pend_q; // 1 = RAM 读已发出,R 待交付

  wire rd_accept = ar_valid_i && !rd_pend_q && !wr_accept && !wr_busy;

  assign ar_ready_o = !rd_pend_q && !wr_accept && !wr_busy;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rd_pend_q <= 1'b0;
    end else begin
      if (rd_accept) begin
        rd_pend_q <= 1'b1;
      end else if (rd_pend_q && r_ready_i) begin
        rd_pend_q <= 1'b0;
      end
    end
  end

  assign r_valid_o = rd_pend_q;
  assign r_resp_o  = amechip_pkg::AXI_OKAY;

  logic [31:0] ram_rdata;
  sram_behav #(
    .WIDTH     (32),
    .DEPTH     (DEPTH),
    .INIT_FILE (INIT_FILE)
  ) u_ram (
    .clk_i   (clk_i),
    .rst_ni  (rst_ni),
    .cs_i    (wr_accept || rd_accept),
    .we_i    (wr_accept && !IS_ROM),
    .addr_i  (wr_accept ? aw_addr_i[AWW-1+2:2] : ar_addr_i[AWW-1+2:2]),
    .wdata_i (w_data_i),
    .wstrb_i (w_strb_i),
    .rdata_o (ram_rdata)
  );

  assign r_data_o = ram_rdata;

  logic _unused;
  assign _unused = ^{aw_addr_i[1:0], ar_addr_i[1:0]};

endmodule
