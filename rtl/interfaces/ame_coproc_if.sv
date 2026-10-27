`ifndef _AMECHIP_PKG_SV
 `include "amechip_pkg.sv"
`endif

interface ame_coproc_if (
  input logic clk,
  input logic rst_n              // 同步释放后的片内复位(clk_rst_if.rst_n)
);

  logic        req_valid;        // CPU 保持直至接受
  logic        req_ready;        // AME 可完成(不 ready = 阻塞该指令)
  logic [31:0] req_instr;        // 完整 32-bit 指令字(opcode=amechip_pkg::AME_OPCODE)
  logic [31:0] req_rs1;          // rs1 GPR 值(经全部旁路后的值)
  logic [31:0] req_rs2;          // rs2 GPR 值(当前所有 AME 指令未用,仍须正确驱动)

  logic        resp_valid;       // 接受沿后 1 拍,单脉冲
  logic [31:0] resp_data;        // rd 写回值
  logic        resp_err;         // 本指令是否触发 AME ERR(sticky 源)

  modport master (             // CPU 侧
    output req_valid, req_instr, req_rs1, req_rs2,
    input  req_ready, resp_valid, resp_data, resp_err,
    input  clk, rst_n
  );

  modport slave (              // AME 侧
    input  req_valid, req_instr, req_rs1, req_rs2,
    output req_ready, resp_valid, resp_data, resp_err,
    input  clk, rst_n
  );

endinterface
