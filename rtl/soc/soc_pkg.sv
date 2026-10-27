
`ifndef _SOC_PKG_SV
`define _SOC_PKG_SV

package soc_pkg;

  typedef struct packed {
    logic        valid;
    logic        write;   // 1=store 0=load
    logic [31:0] addr;
    logic [31:0] wdata;
    logic [3:0]  wstrb;
  } soc_req_t;

  typedef struct packed {
    logic        valid;
    logic [31:0] rdata;
    logic [1:0]  resp;    // amechip_pkg::AXI_OKAY / SLVERR / DECERR
  } soc_resp_t;

  function automatic logic [3:0] soc_slave_decode (input logic [31:0] addr);
    if (addr <= amechip_pkg::A_OCSRAM_END)                 return 4'd0;
    else if (addr <= amechip_pkg::A_BOOTROM_END
         && addr >= amechip_pkg::A_BOOTROM_BASE)           return 4'd1;
    else if (addr >= amechip_pkg::A_SYS_BASE
         && addr <= amechip_pkg::A_SYS_END)                return 4'd2;
    else if (addr >= amechip_pkg::A_INTC_BASE
         && addr <= amechip_pkg::A_INTC_END)               return 4'd3;
    else if (addr >= amechip_pkg::A_UART_BASE
         && addr <= amechip_pkg::A_UART_END)               return 4'd4;
    else if (addr >= amechip_pkg::A_DMA_BASE
         && addr <= amechip_pkg::A_DMA_END)                return 4'd5;
    else if (addr >= amechip_pkg::A_AME_BASE
         && addr <= amechip_pkg::A_AME_END)                return 4'd6;
    else if (addr >= amechip_pkg::A_KV_BASE
         && addr <= amechip_pkg::A_KV_END)                 return 4'd7;
    else if (addr >= amechip_pkg::A_XMEM_BASE
         && addr <= amechip_pkg::A_XMEM_END)               return 4'd8;
    else                                                   return 4'd15;
  endfunction

endpackage

`endif // _SOC_PKG_SV
