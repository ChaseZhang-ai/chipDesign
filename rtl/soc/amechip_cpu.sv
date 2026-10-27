`ifndef _AMECHIP_CPU_SHIM_SV
`define _AMECHIP_CPU_SHIM_SV

module amechip_cpu (
  input  logic               clk,
  input  logic               rst_n,

  output soc_pkg::soc_req_t  bus_req,
  input  soc_pkg::soc_resp_t bus_resp,

  output logic        ame_req_valid,
  input  logic        ame_req_ready,
  output logic [31:0] ame_req_instr,
  output logic [31:0] ame_req_rs1,
  output logic [31:0] ame_req_rs2,
  input  logic        ame_resp_valid,
  input  logic [31:0] ame_resp_data,
  input  logic        ame_resp_err,

  input  logic        irq_i,
  output logic        cpu_wfi_o,
  output logic        buserr_evt_o
);

  logic [31:0] ax_aw_addr;
  logic        ax_aw_valid, ax_aw_ready;
  logic [31:0] ax_w_data;
  logic [3:0]  ax_w_strb;
  logic        ax_w_valid, ax_w_ready;
  logic [1:0]  ax_b_resp;
  logic        ax_b_valid, ax_b_ready;
  logic [31:0] ax_ar_addr;
  logic        ax_ar_valid, ax_ar_ready;
  logic [31:0] ax_r_data;
  logic [1:0]  ax_r_resp;
  logic        ax_r_valid, ax_r_ready;

  axi2soc_bridge u_ax (
    .clk        (clk),
    .rst_n      (rst_n),
    .s_aw_valid_i (ax_aw_valid),
    .s_aw_ready_o (ax_aw_ready),
    .s_aw_addr_i  (ax_aw_addr),
    .s_w_valid_i  (ax_w_valid),
    .s_w_ready_o  (ax_w_ready),
    .s_w_data_i   (ax_w_data),
    .s_w_strb_i   (ax_w_strb),
    .s_b_valid_o  (ax_b_valid),
    .s_b_ready_i  (ax_b_ready),
    .s_b_resp_o   (ax_b_resp),
    .s_ar_valid_i (ax_ar_valid),
    .s_ar_ready_o (ax_ar_ready),
    .s_ar_addr_i  (ax_ar_addr),
    .s_r_valid_o  (ax_r_valid),
    .s_r_ready_i  (ax_r_ready),
    .s_r_data_o   (ax_r_data),
    .s_r_resp_o   (ax_r_resp),
    .req_o      (bus_req),
    .resp_i     (bus_resp)
  );

  logic halt_unused;
  logic trace_valid_unused;
  logic [31:0] trace_pc_unused, trace_instr_unused, trace_wdata_unused;
  logic [4:0] trace_rd_unused;
  logic [1:0] trace_flag_unused;

  ame_cpu u_core (
    .clk_i      (clk),
    .rst_ni     (rst_n),

    .ax_aw_addr (ax_aw_addr),
    .ax_aw_valid(ax_aw_valid),
    .ax_aw_ready(ax_aw_ready),
    .ax_w_data  (ax_w_data),
    .ax_w_strb  (ax_w_strb),
    .ax_w_valid (ax_w_valid),
    .ax_w_ready (ax_w_ready),
    .ax_b_resp  (ax_b_resp),
    .ax_b_valid (ax_b_valid),
    .ax_b_ready (ax_b_ready),
    .ax_ar_addr (ax_ar_addr),
    .ax_ar_valid(ax_ar_valid),
    .ax_ar_ready(ax_ar_ready),
    .ax_r_data  (ax_r_data),
    .ax_r_resp  (ax_r_resp),
    .ax_r_valid (ax_r_valid),
    .ax_r_ready (ax_r_ready),

    .ame_req_valid(ame_req_valid),
    .ame_req_instr(ame_req_instr),
    .ame_req_rs1  (ame_req_rs1),
    .ame_req_rs2  (ame_req_rs2),
    .ame_req_ready(ame_req_ready),
    .ame_resp_valid(ame_resp_valid),
    .ame_resp_data (ame_resp_data),
    .ame_resp_err  (ame_resp_err),

    .irq_i      (irq_i),
    .halt_o     (halt_unused),
    .wfi_o      (cpu_wfi_o),
    .bus_err_o  (buserr_evt_o),

    .trace_valid_o(trace_valid_unused),
    .trace_pc_o   (trace_pc_unused),
    .trace_instr_o(trace_instr_unused),
    .trace_rd_o   (trace_rd_unused),
    .trace_wdata_o(trace_wdata_unused),
    .trace_flag_o (trace_flag_unused)
  );

endmodule

`endif // _AMECHIP_CPU_SHIM_SV
