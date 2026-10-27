`ifndef _AMECHIP_MEM_SHIM_SV
`define _AMECHIP_MEM_SHIM_SV

module amechip_mem #(
  parameter BOOT_INIT = "/home/zcz/verda/autoDecodeChip/rtl/soc/boot/boot.hex"
) (
  input  logic               clk,
  input  logic               rst_n,

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
  output logic               kv_done_evt_o,   // P3D-03:KV 事件 → INTC bit6
  output logic               kv_err_evt_o     // P3D-03:KV 事件 → INTC bit7
);

  assign s1_req = '0;

  logic m0_aw_valid, m0_aw_ready;
  logic [31:0] m0_aw_addr;
  logic m0_w_valid, m0_w_ready;
  logic [31:0] m0_w_data;
  logic [3:0] m0_w_strb;
  logic m0_b_valid, m0_b_ready;
  logic [1:0] m0_b_resp;
  logic m0_ar_valid, m0_ar_ready;
  logic [31:0] m0_ar_addr;
  logic m0_r_valid, m0_r_ready;
  logic [31:0] m0_r_data;
  logic [1:0] m0_r_resp;

  soc2axi_master u_m0 (
    .clk(clk), .rst_n(rst_n),
    .req_i(m0_req), .resp_o(m0_resp),
    .aw_valid_o(m0_aw_valid), .aw_ready_i(m0_aw_ready), .aw_addr_o(m0_aw_addr),
    .w_valid_o(m0_w_valid), .w_ready_i(m0_w_ready), .w_data_o(m0_w_data), .w_strb_o(m0_w_strb),
    .b_valid_i(m0_b_valid), .b_ready_o(m0_b_ready), .b_resp_i(m0_b_resp),
    .ar_valid_o(m0_ar_valid), .ar_ready_i(m0_ar_ready), .ar_addr_o(m0_ar_addr),
    .r_valid_i(m0_r_valid), .r_ready_o(m0_r_ready), .r_data_i(m0_r_data), .r_resp_i(m0_r_resp)
  );

  logic s2_aw_valid, s2_aw_ready;
  logic [31:0] s2_aw_addr;
  logic s2_w_valid, s2_w_ready;
  logic [31:0] s2_w_data;
  logic [3:0] s2_w_strb;
  logic s2_b_valid, s2_b_ready;
  logic [1:0] s2_b_resp;
  logic s2_ar_valid, s2_ar_ready;
  logic [31:0] s2_ar_addr;
  logic s2_r_valid, s2_r_ready;
  logic [31:0] s2_r_data;
  logic [1:0] s2_r_resp;

  axi2soc_bridge u_s2 (
    .clk(clk), .rst_n(rst_n),
    .s_aw_valid_i(s2_aw_valid), .s_aw_ready_o(s2_aw_ready), .s_aw_addr_i(s2_aw_addr),
    .s_w_valid_i(s2_w_valid),   .s_w_ready_o(s2_w_ready),   .s_w_data_i(s2_w_data),
    .s_w_strb_i(s2_w_strb),
    .s_b_valid_o(s2_b_valid),   .s_b_ready_i(s2_b_ready),   .s_b_resp_o(s2_b_resp),
    .s_ar_valid_i(s2_ar_valid), .s_ar_ready_o(s2_ar_ready), .s_ar_addr_i(s2_ar_addr),
    .s_r_valid_o(s2_r_valid),   .s_r_ready_i(s2_r_ready),   .s_r_data_o(s2_r_data),
    .s_r_resp_o(s2_r_resp),
    .req_o(s2_req), .resp_i(s2_resp)
  );

  logic s3_aw_valid, s3_aw_ready;
  logic [31:0] s3_aw_addr;
  logic s3_w_valid, s3_w_ready;
  logic [31:0] s3_w_data;
  logic [3:0] s3_w_strb;
  logic s3_b_valid, s3_b_ready;
  logic [1:0] s3_b_resp;
  logic s3_ar_valid, s3_ar_ready;
  logic [31:0] s3_ar_addr;
  logic s3_r_valid, s3_r_ready;
  logic [31:0] s3_r_data;
  logic [1:0] s3_r_resp;

  axi2soc_bridge u_s3 (
    .clk(clk), .rst_n(rst_n),
    .s_aw_valid_i(s3_aw_valid), .s_aw_ready_o(s3_aw_ready), .s_aw_addr_i(s3_aw_addr),
    .s_w_valid_i(s3_w_valid),   .s_w_ready_o(s3_w_ready),   .s_w_data_i(s3_w_data),
    .s_w_strb_i(s3_w_strb),
    .s_b_valid_o(s3_b_valid),   .s_b_ready_i(s3_b_ready),   .s_b_resp_o(s3_b_resp),
    .s_ar_valid_i(s3_ar_valid), .s_ar_ready_o(s3_ar_ready), .s_ar_addr_i(s3_ar_addr),
    .s_r_valid_o(s3_r_valid),   .s_r_ready_i(s3_r_ready),   .s_r_data_o(s3_r_data),
    .s_r_resp_o(s3_r_resp),
    .req_o(s3_req), .resp_i(s3_resp)
  );

  logic s4_aw_valid, s4_aw_ready;
  logic [31:0] s4_aw_addr;
  logic s4_w_valid, s4_w_ready;
  logic [31:0] s4_w_data;
  logic [3:0] s4_w_strb;
  logic s4_b_valid, s4_b_ready;
  logic [1:0] s4_b_resp;
  logic s4_ar_valid, s4_ar_ready;
  logic [31:0] s4_ar_addr;
  logic s4_r_valid, s4_r_ready;
  logic [31:0] s4_r_data;
  logic [1:0] s4_r_resp;

  axi2soc_bridge u_s4 (
    .clk(clk), .rst_n(rst_n),
    .s_aw_valid_i(s4_aw_valid), .s_aw_ready_o(s4_aw_ready), .s_aw_addr_i(s4_aw_addr),
    .s_w_valid_i(s4_w_valid),   .s_w_ready_o(s4_w_ready),   .s_w_data_i(s4_w_data),
    .s_w_strb_i(s4_w_strb),
    .s_b_valid_o(s4_b_valid),   .s_b_ready_i(s4_b_ready),   .s_b_resp_o(s4_b_resp),
    .s_ar_valid_i(s4_ar_valid), .s_ar_ready_o(s4_ar_ready), .s_ar_addr_i(s4_ar_addr),
    .s_r_valid_o(s4_r_valid),   .s_r_ready_i(s4_r_ready),   .s_r_data_o(s4_r_data),
    .s_r_resp_o(s4_r_resp),
    .req_o(s4_req), .resp_i(s4_resp)
  );

  logic ame_aw_valid, ame_aw_ready;
  logic [31:0] ame_aw_addr;
  logic ame_w_valid, ame_w_ready;
  logic [31:0] ame_w_data;
  logic [3:0] ame_w_strb;
  logic ame_b_valid, ame_b_ready;
  logic [1:0] ame_b_resp;
  logic ame_ar_valid, ame_ar_ready;
  logic [31:0] ame_ar_addr;
  logic ame_r_valid, ame_r_ready;
  logic [31:0] ame_r_data;
  logic [1:0] ame_r_resp;

  soc_pkg::soc_req_t  win_req;
  soc_pkg::soc_resp_t win_resp;

  assign win_req_valid = win_req.valid;
  assign win_req_write = win_req.write;
  assign win_req_addr  = win_req.addr;
  assign win_req_wdata = win_req.wdata;
  assign win_req_wstrb = win_req.wstrb;
  assign win_resp.valid = win_resp_valid;
  assign win_resp.rdata = win_resp_rdata;
  assign win_resp.resp  = win_resp_err ? amechip_pkg::AXI_SLVERR : amechip_pkg::AXI_OKAY;

  axi2soc_bridge u_win (
    .clk(clk), .rst_n(rst_n),
    .s_aw_valid_i(ame_aw_valid), .s_aw_ready_o(ame_aw_ready), .s_aw_addr_i(ame_aw_addr),
    .s_w_valid_i(ame_w_valid),   .s_w_ready_o(ame_w_ready),   .s_w_data_i(ame_w_data),
    .s_w_strb_i(ame_w_strb),
    .s_b_valid_o(ame_b_valid),   .s_b_ready_i(ame_b_ready),   .s_b_resp_o(ame_b_resp),
    .s_ar_valid_i(ame_ar_valid), .s_ar_ready_o(ame_ar_ready), .s_ar_addr_i(ame_ar_addr),
    .s_r_valid_o(ame_r_valid),   .s_r_ready_i(ame_r_ready),   .s_r_data_o(ame_r_data),
    .s_r_resp_o(ame_r_resp),
    .req_o(win_req), .resp_i(win_resp)
  );

  logic _unused_win_ready;
  assign _unused_win_ready = win_req_ready;


  mem_ss_top #(.BOOT_INIT(BOOT_INIT)) u_core (
    .clk_i(clk), .rst_ni(rst_n),

    .cpu_aw_valid_i(m0_aw_valid), .cpu_aw_ready_o(m0_aw_ready), .cpu_aw_addr_i(m0_aw_addr),
    .cpu_w_valid_i(m0_w_valid),   .cpu_w_ready_o(m0_w_ready),   .cpu_w_data_i(m0_w_data),
    .cpu_w_strb_i(m0_w_strb),
    .cpu_b_valid_o(m0_b_valid),   .cpu_b_ready_i(m0_b_ready),   .cpu_b_resp_o(m0_b_resp),
    .cpu_ar_valid_i(m0_ar_valid), .cpu_ar_ready_o(m0_ar_ready), .cpu_ar_addr_i(m0_ar_addr),
    .cpu_r_valid_o(m0_r_valid),   .cpu_r_ready_i(m0_r_ready),   .cpu_r_data_o(m0_r_data),
    .cpu_r_resp_o(m0_r_resp),

    .sys_aw_valid_o(s2_aw_valid), .sys_aw_ready_i(s2_aw_ready), .sys_aw_addr_o(s2_aw_addr),
    .sys_w_valid_o(s2_w_valid),   .sys_w_ready_i(s2_w_ready),   .sys_w_data_o(s2_w_data),
    .sys_w_strb_o(s2_w_strb),
    .sys_b_valid_i(s2_b_valid),   .sys_b_ready_o(s2_b_ready),   .sys_b_resp_i(s2_b_resp),
    .sys_ar_valid_o(s2_ar_valid), .sys_ar_ready_i(s2_ar_ready), .sys_ar_addr_o(s2_ar_addr),
    .sys_r_valid_i(s2_r_valid),   .sys_r_ready_o(s2_r_ready),   .sys_r_data_i(s2_r_data),
    .sys_r_resp_i(s2_r_resp),

    .intc_aw_valid_o(s3_aw_valid), .intc_aw_ready_i(s3_aw_ready), .intc_aw_addr_o(s3_aw_addr),
    .intc_w_valid_o(s3_w_valid),   .intc_w_ready_i(s3_w_ready),   .intc_w_data_o(s3_w_data),
    .intc_w_strb_o(s3_w_strb),
    .intc_b_valid_i(s3_b_valid),   .intc_b_ready_o(s3_b_ready),   .intc_b_resp_i(s3_b_resp),
    .intc_ar_valid_o(s3_ar_valid), .intc_ar_ready_i(s3_ar_ready), .intc_ar_addr_o(s3_ar_addr),
    .intc_r_valid_i(s3_r_valid),   .intc_r_ready_o(s3_r_ready),   .intc_r_data_i(s3_r_data),
    .intc_r_resp_i(s3_r_resp),

    .uart_aw_valid_o(s4_aw_valid), .uart_aw_ready_i(s4_aw_ready), .uart_aw_addr_o(s4_aw_addr),
    .uart_w_valid_o(s4_w_valid),   .uart_w_ready_i(s4_w_ready),   .uart_w_data_o(s4_w_data),
    .uart_w_strb_o(s4_w_strb),
    .uart_b_valid_i(s4_b_valid),   .uart_b_ready_o(s4_b_ready),   .uart_b_resp_i(s4_b_resp),
    .uart_ar_valid_o(s4_ar_valid), .uart_ar_ready_i(s4_ar_ready), .uart_ar_addr_o(s4_ar_addr),
    .uart_r_valid_i(s4_r_valid),   .uart_r_ready_o(s4_r_ready),   .uart_r_data_i(s4_r_data),
    .uart_r_resp_i(s4_r_resp),

    .ame_aw_valid_o(ame_aw_valid), .ame_aw_ready_i(ame_aw_ready), .ame_aw_addr_o(ame_aw_addr),
    .ame_w_valid_o(ame_w_valid),   .ame_w_ready_i(ame_w_ready),   .ame_w_data_o(ame_w_data),
    .ame_w_strb_o(ame_w_strb),
    .ame_b_valid_i(ame_b_valid),   .ame_b_ready_o(ame_b_ready),   .ame_b_resp_i(ame_b_resp),
    .ame_ar_valid_o(ame_ar_valid), .ame_ar_ready_i(ame_ar_ready), .ame_ar_addr_o(ame_ar_addr),
    .ame_r_valid_i(ame_r_valid),   .ame_r_ready_o(ame_r_ready),   .ame_r_data_i(ame_r_data),
    .ame_r_resp_i(ame_r_resp),

    .xmem_clk_o(xmem_clk_o), .xmem_a_o(xmem_a_o),
    .xmem_di_i(xmem_di_i),   .xmem_do_o(xmem_do_o),
    .xmem_ce_no(xmem_ce_no), .xmem_oe_no(xmem_oe_no), .xmem_we_no(xmem_we_no),
    .xmem_wait_i(xmem_wait_i),

    .irq_dma_done_o(dma_done_evt_o), .irq_dma_err_o(dma_err_evt_o),
    .irq_kv_done_o(kv_done_evt_o),   .irq_kv_err_o(kv_err_evt_o)
  );

  assign dma_busy_o = 1'b0;
  assign kv_busy_o  = 1'b0;

  logic _unused_s1;
  assign _unused_s1 = ^s1_resp.valid | ^s1_resp.rdata | ^s1_resp.resp;

endmodule

`endif // _AMECHIP_MEM_SHIM_SV
