
module stub_xbar (
  input  logic clk,
  input  logic rst_n,

  input  soc_pkg::soc_req_t  m0_req,   // CPU
  output soc_pkg::soc_resp_t m0_resp,
  input  soc_pkg::soc_req_t  m1_req,   // DMA_RD
  output soc_pkg::soc_resp_t m1_resp,
  input  soc_pkg::soc_req_t  m2_req,   // DMA_WR
  output soc_pkg::soc_resp_t m2_resp,
  input  soc_pkg::soc_req_t  m3_req,   // KV_CTRL(stub 恒不发)
  output soc_pkg::soc_resp_t m3_resp,

  output soc_pkg::soc_req_t  s0_req,   // OCSRAM
  input  soc_pkg::soc_resp_t s0_resp,
  output soc_pkg::soc_req_t  s1_req,   // BOOTROM
  input  soc_pkg::soc_resp_t s1_resp,
  output soc_pkg::soc_req_t  s2_req,   // SYS
  input  soc_pkg::soc_resp_t s2_resp,
  output soc_pkg::soc_req_t  s3_req,   // INTC
  input  soc_pkg::soc_resp_t s3_resp,
  output soc_pkg::soc_req_t  s4_req,   // UART
  input  soc_pkg::soc_resp_t s4_resp,
  output soc_pkg::soc_req_t  s5_req,   // DMA CSR
  input  soc_pkg::soc_resp_t s5_resp,
  output soc_pkg::soc_req_t  s6_req,   // AME 窗口
  input  soc_pkg::soc_resp_t s6_resp,
  output soc_pkg::soc_req_t  s7_req,   // KV CSR
  input  soc_pkg::soc_resp_t s7_resp,
  output soc_pkg::soc_req_t  s8_req,   // MEMC/XMEM
  input  soc_pkg::soc_resp_t s8_resp
);

  function automatic soc_pkg::soc_resp_t resp_or (soc_pkg::soc_resp_t a,
                                                  soc_pkg::soc_resp_t b);
    resp_or.valid = a.valid | b.valid;
    resp_or.rdata = a.rdata | b.rdata;
    resp_or.resp  = a.resp  | b.resp;
  endfunction

  wire [3:0] t0 = soc_pkg::soc_slave_decode(m0_req.addr);
  wire [3:0] t1 = soc_pkg::soc_slave_decode(m1_req.addr);
  wire [3:0] t2 = soc_pkg::soc_slave_decode(m2_req.addr);
  wire [3:0] t3 = soc_pkg::soc_slave_decode(m3_req.addr);

  soc_pkg::soc_resp_t d0, d1, d2, d3;
  always_comb begin
    d0.valid = m0_req.valid && (t0 == 4'd15);
    d0.rdata = 32'd0;
    d0.resp  = amechip_pkg::AXI_DECERR;
    d1.valid = m1_req.valid && (t1 == 4'd15);
    d1.rdata = 32'd0;
    d1.resp  = amechip_pkg::AXI_DECERR;
    d2.valid = m2_req.valid && (t2 == 4'd15);
    d2.rdata = 32'd0;
    d2.resp  = amechip_pkg::AXI_DECERR;
    d3.valid = m3_req.valid && (t3 == 4'd15);
    d3.rdata = 32'd0;
    d3.resp  = amechip_pkg::AXI_DECERR;
  end

  soc_pkg::soc_resp_t x0_m0, x0_m1, x0_m2, x0_m3;
  soc_pkg::soc_resp_t x1_m0, x1_m1, x1_m2, x1_m3;
  soc_pkg::soc_resp_t x2_m0, x2_m1, x2_m2, x2_m3;
  soc_pkg::soc_resp_t x3_m0, x3_m1, x3_m2, x3_m3;
  soc_pkg::soc_resp_t x4_m0, x4_m1, x4_m2, x4_m3;
  soc_pkg::soc_resp_t x5_m0, x5_m1, x5_m2, x5_m3;
  soc_pkg::soc_resp_t x6_m0, x6_m1, x6_m2, x6_m3;
  soc_pkg::soc_resp_t x7_m0, x7_m1, x7_m2, x7_m3;
  soc_pkg::soc_resp_t x8_m0, x8_m1, x8_m2, x8_m3;

  soc_rr_mux4 #(.SEL_ID(4'd0)) u_s0 (
    .clk, .rst_n,
    .m0_req(m0_req), .m0_resp(x0_m0), .m1_req(m1_req), .m1_resp(x0_m1),
    .m2_req(m2_req), .m2_resp(x0_m2), .m3_req(m3_req), .m3_resp(x0_m3),
    .s_req(s0_req), .s_resp(s0_resp));
  soc_rr_mux4 #(.SEL_ID(4'd1)) u_s1 (
    .clk, .rst_n,
    .m0_req(m0_req), .m0_resp(x1_m0), .m1_req(m1_req), .m1_resp(x1_m1),
    .m2_req(m2_req), .m2_resp(x1_m2), .m3_req(m3_req), .m3_resp(x1_m3),
    .s_req(s1_req), .s_resp(s1_resp));
  soc_rr_mux4 #(.SEL_ID(4'd2)) u_s2 (
    .clk, .rst_n,
    .m0_req(m0_req), .m0_resp(x2_m0), .m1_req(m1_req), .m1_resp(x2_m1),
    .m2_req(m2_req), .m2_resp(x2_m2), .m3_req(m3_req), .m3_resp(x2_m3),
    .s_req(s2_req), .s_resp(s2_resp));
  soc_rr_mux4 #(.SEL_ID(4'd3)) u_s3 (
    .clk, .rst_n,
    .m0_req(m0_req), .m0_resp(x3_m0), .m1_req(m1_req), .m1_resp(x3_m1),
    .m2_req(m2_req), .m2_resp(x3_m2), .m3_req(m3_req), .m3_resp(x3_m3),
    .s_req(s3_req), .s_resp(s3_resp));
  soc_rr_mux4 #(.SEL_ID(4'd4)) u_s4 (
    .clk, .rst_n,
    .m0_req(m0_req), .m0_resp(x4_m0), .m1_req(m1_req), .m1_resp(x4_m1),
    .m2_req(m2_req), .m2_resp(x4_m2), .m3_req(m3_req), .m3_resp(x4_m3),
    .s_req(s4_req), .s_resp(s4_resp));
  soc_rr_mux4 #(.SEL_ID(4'd5)) u_s5 (
    .clk, .rst_n,
    .m0_req(m0_req), .m0_resp(x5_m0), .m1_req(m1_req), .m1_resp(x5_m1),
    .m2_req(m2_req), .m2_resp(x5_m2), .m3_req(m3_req), .m3_resp(x5_m3),
    .s_req(s5_req), .s_resp(s5_resp));
  soc_rr_mux4 #(.SEL_ID(4'd6)) u_s6 (
    .clk, .rst_n,
    .m0_req(m0_req), .m0_resp(x6_m0), .m1_req(m1_req), .m1_resp(x6_m1),
    .m2_req(m2_req), .m2_resp(x6_m2), .m3_req(m3_req), .m3_resp(x6_m3),
    .s_req(s6_req), .s_resp(s6_resp));
  soc_rr_mux4 #(.SEL_ID(4'd7)) u_s7 (
    .clk, .rst_n,
    .m0_req(m0_req), .m0_resp(x7_m0), .m1_req(m1_req), .m1_resp(x7_m1),
    .m2_req(m2_req), .m2_resp(x7_m2), .m3_req(m3_req), .m3_resp(x7_m3),
    .s_req(s7_req), .s_resp(s7_resp));
  soc_rr_mux4 #(.SEL_ID(4'd8)) u_s8 (
    .clk, .rst_n,
    .m0_req(m0_req), .m0_resp(x8_m0), .m1_req(m1_req), .m1_resp(x8_m1),
    .m2_req(m2_req), .m2_resp(x8_m2), .m3_req(m3_req), .m3_resp(x8_m3),
    .s_req(s8_req), .s_resp(s8_resp));

  soc_pkg::soc_resp_t o0, o1, o2, o3;
  always_comb begin
    o0 = resp_or(resp_or(resp_or(resp_or(resp_or(resp_or(resp_or(resp_or(
         x0_m0, x1_m0), x2_m0), x3_m0), x4_m0), x5_m0), x6_m0), x7_m0), x8_m0);
    o1 = resp_or(resp_or(resp_or(resp_or(resp_or(resp_or(resp_or(resp_or(
         x0_m1, x1_m1), x2_m1), x3_m1), x4_m1), x5_m1), x6_m1), x7_m1), x8_m1);
    o2 = resp_or(resp_or(resp_or(resp_or(resp_or(resp_or(resp_or(resp_or(
         x0_m2, x1_m2), x2_m2), x3_m2), x4_m2), x5_m2), x6_m2), x7_m2), x8_m2);
    o3 = resp_or(resp_or(resp_or(resp_or(resp_or(resp_or(resp_or(resp_or(
         x0_m3, x1_m3), x2_m3), x3_m3), x4_m3), x5_m3), x6_m3), x7_m3), x8_m3);
  end

  always_comb begin
    m0_resp = d0.valid ? d0 : o0;
    m1_resp = d1.valid ? d1 : o1;
    m2_resp = d2.valid ? d2 : o2;
    m3_resp = d3.valid ? d3 : o3;
  end

endmodule
