`ifndef _AMECHIP_PKG_SV
 `include "amechip_pkg.sv"
`endif

interface ame_dma_if (
  input logic clk,
  input logic rst_n
);

  logic        req_valid;
  logic        req_ready;        // 单笔 outstanding:接受后下一拍即响应
  logic        req_write;        // 1=写 0=读
  logic [31:0] req_addr;         // 绝对字节地址(AME 窗口内)
  logic [31:0] req_wdata;
  logic [3:0]  req_wstrb;        // 读时忽略

  logic        resp_valid;
  logic [31:0] resp_rdata;
  logic        resp_err;         // SLVERR 映射

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
