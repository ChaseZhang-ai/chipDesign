`ifndef _AMECHIP_AME_SHIM_SV
`define _AMECHIP_AME_SHIM_SV

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

  logic dbg_idle, dbg_mac_en;

  ame_core u_core (
    .clk_i             (clk),
    .rst_ni            (rst_n),

    .cp_req_valid_i    (req_valid),
    .cp_req_instr_i    (req_instr),
    .cp_req_rs1_i      (req_rs1),
    .cp_req_rs2_i      (req_rs2),
    .cp_req_ready_o    (req_ready),
    .cp_resp_valid_o   (resp_valid),
    .cp_resp_data_o    (resp_data),
    .cp_resp_err_o     (resp_err),

    .bus_req_valid_i   (win_req_valid),
    .bus_req_write_i   (win_req_write),
    .bus_req_addr_i    (win_req_addr),
    .bus_req_wdata_i   (win_req_wdata),
    .bus_req_wstrb_i   (win_req_wstrb),
    .bus_req_ready_o   (win_req_ready),
    .bus_resp_valid_o  (win_resp_valid),
    .bus_resp_rdata_o  (win_resp_rdata),
    .bus_resp_err_o    (win_resp_err),

    .irq_done_o        (evt_done_o),
    .irq_err_o         (evt_err_o),

    .dbg_mac_en_o      (dbg_mac_en),
    .dbg_idle_o        (dbg_idle)
  );

  assign busy_o = ~dbg_idle;

endmodule

`endif // _AMECHIP_AME_SHIM_SV
