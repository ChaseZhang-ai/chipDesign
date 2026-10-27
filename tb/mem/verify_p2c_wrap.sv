//     rtl/amechip_pkg.sv rtl/mem/*.sv tb/mem/tb_stubs.sv tb/mem/tb_bfm_tasks.svh \
//     tb/mem/tb_xbar.sv tb/mem/verify_protocol.sv tb/mem/verify_p2c_wrap.sv
`timescale 1ns/1ps
`include "amechip_pkg.sv"

`define VFRC_CONNECT_MON(INST) \
  .clk_i        (INST.clk), \
  .rst_ni       (INST.rst_n), \
  .m_aw_valid_i (INST.dut.u_xbar.m_aw_valid_i), \
  .m_aw_ready_o (INST.dut.u_xbar.m_aw_ready_o), \
  .m_aw_addr_i  (INST.dut.u_xbar.m_aw_addr_i), \
  .m_w_valid_i  (INST.dut.u_xbar.m_w_valid_i), \
  .m_w_ready_o  (INST.dut.u_xbar.m_w_ready_o), \
  .m_w_data_i   (INST.dut.u_xbar.m_w_data_i), \
  .m_w_strb_i   (INST.dut.u_xbar.m_w_strb_i), \
  .m_b_valid_o  (INST.dut.u_xbar.m_b_valid_o), \
  .m_b_ready_i  (INST.dut.u_xbar.m_b_ready_i), \
  .m_b_resp_o   (INST.dut.u_xbar.m_b_resp_o), \
  .m_ar_valid_i (INST.dut.u_xbar.m_ar_valid_i), \
  .m_ar_ready_o (INST.dut.u_xbar.m_ar_ready_o), \
  .m_ar_addr_i  (INST.dut.u_xbar.m_ar_addr_i), \
  .m_r_valid_o  (INST.dut.u_xbar.m_r_valid_o), \
  .m_r_ready_i  (INST.dut.u_xbar.m_r_ready_i), \
  .m_r_data_o   (INST.dut.u_xbar.m_r_data_o), \
  .m_r_resp_o   (INST.dut.u_xbar.m_r_resp_o), \
  .s_aw_valid_o (INST.dut.u_xbar.s_aw_valid_o), \
  .s_aw_ready_i (INST.dut.u_xbar.s_aw_ready_i), \
  .s_aw_addr_o  (INST.dut.u_xbar.s_aw_addr_o), \
  .s_w_valid_o  (INST.dut.u_xbar.s_w_valid_o), \
  .s_w_ready_i  (INST.dut.u_xbar.s_w_ready_i), \
  .s_w_data_o   (INST.dut.u_xbar.s_w_data_o), \
  .s_w_strb_o   (INST.dut.u_xbar.s_w_strb_o), \
  .s_b_valid_i  (INST.dut.u_xbar.s_b_valid_i), \
  .s_b_ready_o  (INST.dut.u_xbar.s_b_ready_o), \
  .s_b_resp_i   (INST.dut.u_xbar.s_b_resp_i), \
  .s_ar_valid_o (INST.dut.u_xbar.s_ar_valid_o), \
  .s_ar_ready_i (INST.dut.u_xbar.s_ar_ready_i), \
  .s_ar_addr_o  (INST.dut.u_xbar.s_ar_addr_o), \
  .s_r_valid_i  (INST.dut.u_xbar.s_r_valid_i), \
  .s_r_ready_o  (INST.dut.u_xbar.s_r_ready_o), \
  .s_r_data_i   (INST.dut.u_xbar.s_r_data_i), \
  .s_r_resp_i   (INST.dut.u_xbar.s_r_resp_i)

module verify_wrap_xbar;
  tb_xbar u_tb();
  verify_protocol #(.NM(4), .NS(9)) u_mon (`VFRC_CONNECT_MON(u_tb));
endmodule

module verify_wrap_dma;
  tb_dma u_tb();
  verify_protocol #(.NM(4), .NS(9)) u_mon (`VFRC_CONNECT_MON(u_tb));
endmodule

module verify_wrap_kv;
  tb_kv u_tb();
  verify_protocol #(.NM(4), .NS(9)) u_mon (`VFRC_CONNECT_MON(u_tb));
endmodule
