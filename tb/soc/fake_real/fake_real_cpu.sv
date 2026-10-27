
module amechip_cpu (
  input  logic               clk,
  input  logic               rst_n,
  output soc_pkg::soc_req_t  bus_req,
  input  soc_pkg::soc_resp_t bus_resp,
  output logic               ame_req_valid,
  input  logic               ame_req_ready,
  output logic [31:0]        ame_req_instr,
  output logic [31:0]        ame_req_rs1,
  output logic [31:0]        ame_req_rs2,
  input  logic               ame_resp_valid,
  input  logic [31:0]        ame_resp_data,
  input  logic               ame_resp_err,
  input  logic               irq_i,
  output logic               cpu_wfi_o,
  output logic               buserr_evt_o
);

  initial $display("[amechip_cpu] *** REAL-CPU 槽位激活(fake_real 演示占位)***");

  stub_cpu u_core (.*);

endmodule
