`ifndef _AMECHIP_PKG_SV
 `include "amechip_pkg.sv"
`endif

interface ame_dma_if (
  input logic clk,
  input logic rst_n
);

  logic        req_valid;
  logic        req_ready;
  logic        req_write;
  logic [31:0] req_addr;
  logic [31:0] req_wdata;
  logic [3:0]  req_wstrb;

  logic        resp_valid;
  logic [31:0] resp_rdata;
  logic        resp_err;

  modport master (
    output req_valid, req_write, req_addr, req_wdata, req_wstrb,
    input  req_ready, resp_valid, resp_rdata, resp_err,
    input  clk, rst_n
  );

  modport slave (
    input  req_valid, req_write, req_addr, req_wdata, req_wstrb,
    output req_ready, resp_valid, resp_rdata, resp_err,
    input  clk, rst_n
  );

endinterface
