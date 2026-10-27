`ifndef _AMECHIP_PKG_SV
 `include "amechip_pkg.sv"
`endif

interface kv_sram_if #(
  parameter int unsigned BANKS = amechip_pkg::KV_BANKS_DEF, // 4
  parameter int unsigned AW    = amechip_pkg::KV_BANK_AW
) (
  input logic clk,
  input logic rst_n
);

  logic [BANKS-1:0]      cs;
  logic [BANKS-1:0]      we;
  logic [BANKS*AW-1:0]   addr;
  logic [BANKS*32-1:0]   wdata;   // wdata[bank*32 +: 32]

  logic [BANKS*32-1:0]   rdata;   // rdata[bank*32 +: 32]

  modport ctrl (
    output cs, we, addr, wdata,
    input  rdata,
    input  clk, rst_n
  );

  modport mem (
    input  cs, we, addr, wdata,
    output rdata,
    input  clk, rst_n
  );

endinterface
