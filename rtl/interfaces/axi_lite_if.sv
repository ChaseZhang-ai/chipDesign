`ifndef _AMECHIP_PKG_SV
 `include "amechip_pkg.sv"
`endif

interface axi_lite_if (
  input logic clk,
  input logic rst_n
);

  amechip_pkg::axi_aw_t aw;
  logic                 aw_valid;
  logic                 aw_ready;
  amechip_pkg::axi_w_t  w;
  logic                 w_valid;
  logic                 w_ready;
  amechip_pkg::axi_b_t  b;
  logic                 b_valid;
  logic                 b_ready;
  amechip_pkg::axi_ar_t ar;
  logic                 ar_valid;
  logic                 ar_ready;
  amechip_pkg::axi_r_t  r;
  logic                 r_valid;
  logic                 r_ready;

  modport master (  // 发起方(CPU / DMA_RD / DMA_WR / KV)
    output aw, aw_valid,  input aw_ready,
    output w,  w_valid,   input w_ready,
    input  b,  b_valid,   output b_ready,
    output ar, ar_valid,  input ar_ready,
    input  r,  r_valid,   output r_ready,
    input  clk, rst_n
  );

  modport slave (   // 响应方(xbar 从端口 / 各外设)
    input  aw, aw_valid,  output aw_ready,
    input  w,  w_valid,   output w_ready,
    output b,  b_valid,   input  b_ready,
    input  ar, ar_valid,  output ar_ready,
    output r,  r_valid,   input  r_ready,
    input  clk, rst_n
  );

  modport monitor ( // TB/断言用
    input aw, aw_valid, aw_ready,
    input w,  w_valid,  w_ready,
    input b,  b_valid,  b_ready,
    input ar, ar_valid, ar_ready,
    input r,  r_valid,  r_ready,
    input clk, rst_n
  );

endinterface
