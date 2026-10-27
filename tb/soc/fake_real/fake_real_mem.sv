
module amechip_mem (
  input  logic clk,
  input  logic rst_n,

  input  soc_pkg::soc_req_t  m0_req,
  output soc_pkg::soc_resp_t m0_resp,

  output soc_pkg::soc_req_t  s1_req,
  input  soc_pkg::soc_resp_t s1_resp,
  output soc_pkg::soc_req_t  s2_req,
  input  soc_pkg::soc_resp_t s2_resp,
  output soc_pkg::soc_req_t  s3_req,
  input  soc_pkg::soc_resp_t s3_resp,
  output soc_pkg::soc_req_t  s4_req,
  input  soc_pkg::soc_resp_t s4_resp,

  output logic               win_req_valid,
  input  logic               win_req_ready,
  output logic               win_req_write,
  output logic [31:0]        win_req_addr,
  output logic [31:0]        win_req_wdata,
  output logic [3:0]         win_req_wstrb,
  input  logic               win_resp_valid,
  input  logic [31:0]        win_resp_rdata,
  input  logic               win_resp_err,

  output logic               xmem_clk_o,
  output logic [22:0]        xmem_a_o,
  input  logic [15:0]        xmem_di_i,
  output logic [15:0]        xmem_do_o,
  output logic               xmem_ce_no,
  output logic               xmem_oe_no,
  output logic               xmem_we_no,
  input  logic               xmem_wait_i,

  output logic               dma_busy_o,
  output logic               dma_done_evt_o,
  output logic               dma_err_evt_o,
  output logic               kv_busy_o,
  output logic               kv_done_evt_o,
  output logic               kv_err_evt_o
);

  initial $display("[amechip_mem] *** REAL-MEM 槽位激活(fake_real 演示占位)***");

  stub_mem u_core (.*);

  assign kv_done_evt_o = 1'b0;
  assign kv_err_evt_o  = 1'b0;

endmodule
