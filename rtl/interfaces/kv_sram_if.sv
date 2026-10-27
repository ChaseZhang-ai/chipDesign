`ifndef _AMECHIP_PKG_SV
 `include "amechip_pkg.sv"
`endif

interface kv_sram_if #(
  parameter int unsigned BANKS = amechip_pkg::KV_BANKS_DEF, // 4
  parameter int unsigned AW    = amechip_pkg::KV_BANK_AW    // 12(4096 字/bank)
) (
  input logic clk,
  input logic rst_n
);

  logic [BANKS-1:0]      cs;      // bank 访问使能(每 bank 至多 1 笔/拍)
  logic [BANKS-1:0]      we;      // 1=写 0=读(仅 cs=1 时有意义)
  logic [BANKS*AW-1:0]   addr;    // 拼接:addr[bank*AW +: AW],字地址
  logic [BANKS*32-1:0]   wdata;   // wdata[bank*32 +: 32]

  logic [BANKS*32-1:0]   rdata;   // rdata[bank*32 +: 32]

  modport ctrl (   // kv_ctrl 侧
    output cs, we, addr, wdata,
    input  rdata,
    input  clk, rst_n
  );

  modport mem (    // 后端侧(AXI 桥或 sram_behav 阵列)
    input  cs, we, addr, wdata,
    output rdata,
    input  clk, rst_n
  );

endinterface
