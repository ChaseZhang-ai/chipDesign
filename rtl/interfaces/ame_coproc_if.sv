`ifndef _AMECHIP_PKG_SV
 `include "amechip_pkg.sv"
`endif

interface ame_coproc_if (
  input logic clk,
  input logic rst_n
);

  logic        req_valid;
  logic        req_ready;
  logic [31:0] req_instr;
  logic [31:0] req_rs1;
  logic [31:0] req_rs2;

  logic        resp_valid;
  logic [31:0] resp_data;
  logic        resp_err;

  modport master (
    output req_valid, req_instr, req_rs1, req_rs2,
    input  req_ready, resp_valid, resp_data, resp_err,
    input  clk, rst_n
  );

  modport slave (
    input  req_valid, req_instr, req_rs1, req_rs2,
    output req_ready, resp_valid, resp_data, resp_err,
    input  clk, rst_n
  );

endinterface
