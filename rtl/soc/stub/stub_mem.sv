
module stub_mem (
  input  logic clk,
  input  logic rst_n,

  input  soc_pkg::soc_req_t  m0_req,
  output soc_pkg::soc_resp_t m0_resp,

  output soc_pkg::soc_req_t  s1_req,        // BOOTROM
  input  soc_pkg::soc_resp_t s1_resp,
  output soc_pkg::soc_req_t  s2_req,        // SYS CSR
  input  soc_pkg::soc_resp_t s2_resp,
  output soc_pkg::soc_req_t  s3_req,        // INTC
  input  soc_pkg::soc_resp_t s3_resp,
  output soc_pkg::soc_req_t  s4_req,        // UART
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
  output logic               kv_busy_o
);

  soc_pkg::soc_req_t  m1_req,  m2_req,  m3_req;
  soc_pkg::soc_resp_t m1_resp, m2_resp, m3_resp;

  soc_pkg::soc_req_t  s0_req,  s5_req,  s6_req,  s7_req,  s8_req;
  soc_pkg::soc_resp_t s0_resp, s5_resp, s6_resp, s7_resp, s8_resp;

  assign m3_req.valid = 1'b0;
  assign m3_req.write = 1'b0;
  assign m3_req.addr  = 32'd0;
  assign m3_req.wdata = 32'd0;
  assign m3_req.wstrb = 4'd0;

  stub_xbar u_xbar (
    .clk, .rst_n,
    .m0_req(m0_req), .m0_resp(m0_resp),
    .m1_req(m1_req), .m1_resp(m1_resp),
    .m2_req(m2_req), .m2_resp(m2_resp),
    .m3_req(m3_req), .m3_resp(m3_resp),
    .s0_req(s0_req), .s0_resp(s0_resp),
    .s1_req(s1_req), .s1_resp(s1_resp),
    .s2_req(s2_req), .s2_resp(s2_resp),
    .s3_req(s3_req), .s3_resp(s3_resp),
    .s4_req(s4_req), .s4_resp(s4_resp),
    .s5_req(s5_req), .s5_resp(s5_resp),
    .s6_req(s6_req), .s6_resp(s6_resp),
    .s7_req(s7_req), .s7_resp(s7_resp),
    .s8_req(s8_req), .s8_resp(s8_resp)
  );

  stub_sram u_sram (.clk, .rst_n, .bus_req(s0_req), .bus_resp(s0_resp));

  stub_dma u_dma (
    .clk, .rst_n,
    .csr_req(s5_req), .csr_resp(s5_resp),
    .rd_req(m1_req), .rd_resp(m1_resp),
    .wr_req(m2_req), .wr_resp(m2_resp),
    .busy_o(dma_busy_o),
    .evt_done_o(dma_done_evt_o),
    .evt_err_o(dma_err_evt_o)
  );

  stub_kvcsr u_kvc (.clk, .rst_n, .bus_req(s7_req), .bus_resp(s7_resp));
  assign kv_busy_o = 1'b0;

  stub_memc u_memc (
    .clk, .rst_n,
    .bus_req(s8_req), .bus_resp(s8_resp),
    .xmem_clk_o, .xmem_a_o, .xmem_di_i, .xmem_do_o,
    .xmem_ce_no, .xmem_oe_no, .xmem_we_no, .xmem_wait_i
  );

  typedef enum logic { AD_IDLE, AD_WAIT } ad_e;
  ad_e ad_st;

  always_comb begin
    win_req_valid = (ad_st == AD_IDLE) ? s6_req.valid : 1'b0;
    win_req_write = s6_req.write;
    win_req_addr  = s6_req.addr;
    win_req_wdata = s6_req.wdata;
    win_req_wstrb = s6_req.wstrb;
  end

  wire ad_fire = (ad_st == AD_IDLE) && s6_req.valid && win_req_ready;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) ad_st <= AD_IDLE;
    else begin
      case (ad_st)
        AD_IDLE: if (ad_fire) ad_st <= AD_WAIT;
        AD_WAIT: if (win_resp_valid) ad_st <= AD_IDLE;
        default: ad_st <= AD_IDLE;
      endcase
    end
  end

  always_comb begin
    s6_resp.valid = 1'b0;
    s6_resp.rdata = 32'd0;
    s6_resp.resp  = 2'd0;
    if (ad_st == AD_WAIT && win_resp_valid) begin
      s6_resp.valid = 1'b1;
      s6_resp.rdata = win_resp_rdata;
      s6_resp.resp  = win_resp_err ? amechip_pkg::AXI_SLVERR : amechip_pkg::AXI_OKAY;
    end
  end

endmodule
