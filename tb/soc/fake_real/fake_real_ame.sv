
module amechip_ame (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        req_valid,
  output logic        req_ready,
  input  logic [31:0] req_instr,
  input  logic [31:0] req_rs1,
  input  logic [31:0] req_rs2,
  output logic        resp_valid,
  output logic [31:0] resp_data,
  output logic        resp_err,
  input  logic        win_req_valid,
  output logic        win_req_ready,
  input  logic        win_req_write,
  input  logic [31:0] win_req_addr,
  input  logic [31:0] win_req_wdata,
  input  logic [3:0]  win_req_wstrb,
  output logic        win_resp_valid,
  output logic [31:0] win_resp_rdata,
  output logic        win_resp_err,
  output logic        busy_o,
  output logic        evt_done_o,
  output logic        evt_err_o
);

  initial $display("[amechip_ame] *** REAL-AME 槽位激活(fake_real 演示占位)***");

  stub_ame u_core (.*);

endmodule
