`ifndef _AMECHIP_PKG_SV
 `include "amechip_pkg.sv"
`endif

module axi_xbar #(
  parameter int unsigned NM = 4,
  parameter int unsigned NS = 9
) (
  input  logic clk_i,
  input  logic rst_ni,

  input  logic [NM-1:0]     m_aw_valid_i,
  output logic [NM-1:0]     m_aw_ready_o,
  input  logic [32*NM-1:0]  m_aw_addr_i,
  input  logic [NM-1:0]     m_w_valid_i,
  output logic [NM-1:0]     m_w_ready_o,
  input  logic [32*NM-1:0]  m_w_data_i,
  input  logic [4*NM-1:0]   m_w_strb_i,
  output logic [NM-1:0]     m_b_valid_o,
  input  logic [NM-1:0]     m_b_ready_i,
  output logic [2*NM-1:0]   m_b_resp_o,
  input  logic [NM-1:0]     m_ar_valid_i,
  output logic [NM-1:0]     m_ar_ready_o,
  input  logic [32*NM-1:0]  m_ar_addr_i,
  output logic [NM-1:0]     m_r_valid_o,
  input  logic [NM-1:0]     m_r_ready_i,
  output logic [32*NM-1:0]  m_r_data_o,
  output logic [2*NM-1:0]   m_r_resp_o,

  output logic [NS-1:0]     s_aw_valid_o,
  input  logic [NS-1:0]     s_aw_ready_i,
  output logic [32*NS-1:0]  s_aw_addr_o,
  output logic [NS-1:0]     s_w_valid_o,
  input  logic [NS-1:0]     s_w_ready_i,
  output logic [32*NS-1:0]  s_w_data_o,
  output logic [4*NS-1:0]   s_w_strb_o,
  input  logic [NS-1:0]     s_b_valid_i,
  output logic [NS-1:0]     s_b_ready_o,
  input  logic [2*NS-1:0]   s_b_resp_i,
  output logic [NS-1:0]     s_ar_valid_o,
  input  logic [NS-1:0]     s_ar_ready_i,
  output logic [32*NS-1:0]  s_ar_addr_o,
  input  logic [NS-1:0]     s_r_valid_i,
  output logic [NS-1:0]     s_r_ready_o,
  input  logic [32*NS-1:0]  s_r_data_i,
  input  logic [2*NS-1:0]   s_r_resp_i
);

  localparam int unsigned NSP = NS + 1;

  function automatic logic [3:0] addr2slave (input logic [31:0] a);
    if (a <= amechip_pkg::A_OCSRAM_END)  addr2slave = 4'd0;
    else if (a >= amechip_pkg::A_BOOTROM_BASE && a <= amechip_pkg::A_BOOTROM_END) addr2slave = 4'd1;
    else if (a >= amechip_pkg::A_SYS_BASE     && a <= amechip_pkg::A_SYS_END)     addr2slave = 4'd2;
    else if (a >= amechip_pkg::A_INTC_BASE    && a <= amechip_pkg::A_INTC_END)    addr2slave = 4'd3;
    else if (a >= amechip_pkg::A_UART_BASE    && a <= amechip_pkg::A_UART_END)    addr2slave = 4'd4;
    else if (a >= amechip_pkg::A_DMA_BASE     && a <= amechip_pkg::A_DMA_END)     addr2slave = 4'd5;
    else if (a >= amechip_pkg::A_AME_BASE     && a <= amechip_pkg::A_AME_END)     addr2slave = 4'd6;
    else if (a >= amechip_pkg::A_KV_BASE      && a <= amechip_pkg::A_KV_END)      addr2slave = 4'd7;
    else if (a >= amechip_pkg::A_XMEM_BASE    && a <= amechip_pkg::A_XMEM_END)    addr2slave = 4'd8;
    else addr2slave = 4'd9;
  endfunction

  logic [3:0] dec_w [0:NM-1];
  logic [3:0] dec_r [0:NM-1];
  always_comb begin
    for (int m = 0; m < NM; m++) begin
      dec_w[m] = addr2slave(m_aw_addr_i[m*32 +: 32]);
      dec_r[m] = addr2slave(m_ar_addr_i[m*32 +: 32]);
    end
  end

  logic [NSP*NM-1:0] req_w_mat;
  logic [NSP*NM-1:0] req_r_mat;
  always_comb begin
    req_w_mat = '0;
    req_r_mat = '0;
    for (int m = 0; m < NM; m++) begin
      for (int s = 0; s < NSP; s++) begin
        req_w_mat[s*NM + m] = m_aw_valid_i[m] && m_w_valid_i[m] &&
                              ({28'b0, dec_w[m]} == (s & 32'hF));
        req_r_mat[s*NM + m] = m_ar_valid_i[m] && ({28'b0, dec_r[m]} == (s & 32'hF));
      end
    end
  end

  logic [NSP*NM-1:0]   p_aw_ready, p_w_ready, p_b_valid, p_ar_ready, p_r_valid;
  logic [NSP*NM*2-1:0] p_b_resp, p_r_resp;
  logic [NSP*NM*32-1:0] p_r_data;

  for (genvar s = 0; s < NS; s++) begin : g_ports
    axi_xbar_port #(
      .NM (NM)
    ) u_port (
      .clk_i        (clk_i),
      .rst_ni       (rst_ni),
      .req_w_i      (req_w_mat[s*NM +: NM]),
      .aw_addr_i    (m_aw_addr_i),
      .w_data_i     (m_w_data_i),
      .w_strb_i     (m_w_strb_i),
      .req_r_i      (req_r_mat[s*NM +: NM]),
      .ar_addr_i    (m_ar_addr_i),
      .g_aw_ready_o (p_aw_ready[s*NM +: NM]),
      .g_w_ready_o  (p_w_ready[s*NM +: NM]),
      .g_ar_ready_o (p_ar_ready[s*NM +: NM]),
      .b_valid_o    (p_b_valid[s*NM +: NM]),
      .b_ready_i    (m_b_ready_i),
      .b_resp_o     (p_b_resp[s*NM*2 +: NM*2]),
      .r_valid_o    (p_r_valid[s*NM +: NM]),
      .r_ready_i    (m_r_ready_i),
      .r_data_o     (p_r_data[s*NM*32 +: NM*32]),
      .r_resp_o     (p_r_resp[s*NM*2 +: NM*2]),
      .s_aw_valid_o (s_aw_valid_o[s]),
      .s_aw_ready_i (s_aw_ready_i[s]),
      .s_aw_addr_o  (s_aw_addr_o[s*32 +: 32]),
      .s_w_valid_o  (s_w_valid_o[s]),
      .s_w_ready_i  (s_w_ready_i[s]),
      .s_w_data_o   (s_w_data_o[s*32 +: 32]),
      .s_w_strb_o   (s_w_strb_o[s*4 +: 4]),
      .s_b_valid_i  (s_b_valid_i[s]),
      .s_b_ready_o  (s_b_ready_o[s]),
      .s_b_resp_i   (s_b_resp_i[s*2 +: 2]),
      .s_ar_valid_o (s_ar_valid_o[s]),
      .s_ar_ready_i (s_ar_ready_i[s]),
      .s_ar_addr_o  (s_ar_addr_o[s*32 +: 32]),
      .s_r_valid_i  (s_r_valid_i[s]),
      .s_r_ready_o  (s_r_ready_o[s]),
      .s_r_data_i   (s_r_data_i[s*32 +: 32]),
      .s_r_resp_i   (s_r_resp_i[s*2 +: 2])
    );
  end

  logic [NM-1:0]   d_aw_ready, d_w_ready, d_b_valid, d_ar_ready, d_r_valid;
  logic [NM*2-1:0] d_b_resp, d_r_resp;
  logic [NM*32-1:0] d_r_data;

  logic        def_aw_valid, def_w_valid, def_ar_valid;
  logic        def_b_valid, def_r_valid, def_b_ready, def_r_ready;
  logic [31:0] def_aw_addr, def_w_data, def_ar_addr, def_r_data;
  logic [3:0]  def_w_strb;
  logic [1:0]  def_b_resp, def_r_resp;
  logic        def_aw_ready_nc, def_w_ready_nc, def_ar_ready_nc;

  axi_xbar_port #(
    .NM (NM)
  ) u_port_def (
    .clk_i        (clk_i),
    .rst_ni       (rst_ni),
    .req_w_i      (req_w_mat[NS*NM +: NM]),
    .aw_addr_i    (m_aw_addr_i),
    .w_data_i     (m_w_data_i),
    .w_strb_i     (m_w_strb_i),
    .req_r_i      (req_r_mat[NS*NM +: NM]),
    .ar_addr_i    (m_ar_addr_i),
    .g_aw_ready_o (d_aw_ready),
    .g_w_ready_o  (d_w_ready),
    .g_ar_ready_o (d_ar_ready),
    .b_valid_o    (d_b_valid),
    .b_ready_i    (m_b_ready_i),
    .b_resp_o     (d_b_resp),
    .r_valid_o    (d_r_valid),
    .r_ready_i    (m_r_ready_i),
    .r_data_o     (d_r_data),
    .r_resp_o     (d_r_resp),
    .s_aw_valid_o (def_aw_valid),
    .s_aw_ready_i (def_aw_ready_nc),
    .s_aw_addr_o  (def_aw_addr),
    .s_w_valid_o  (def_w_valid),
    .s_w_ready_i  (def_w_ready_nc),
    .s_w_data_o   (def_w_data),
    .s_w_strb_o   (def_w_strb),
    .s_b_valid_i  (def_b_valid),
    .s_b_ready_o  (def_b_ready),
    .s_b_resp_i   (def_b_resp),
    .s_ar_valid_o (def_ar_valid),
    .s_ar_ready_i (def_ar_ready_nc),
    .s_ar_addr_o  (def_ar_addr),
    .s_r_valid_i  (def_r_valid),
    .s_r_ready_o  (def_r_ready),
    .s_r_data_i   (def_r_data),
    .s_r_resp_i   (def_r_resp)
  );

  axi_decerr_slave u_def (
    .clk_i     (clk_i),
    .rst_ni    (rst_ni),
    .aw_valid_i(def_aw_valid),
    .aw_ready_o(def_aw_ready_nc),
    .aw_addr_i (def_aw_addr),
    .w_valid_i (def_w_valid),
    .w_ready_o (def_w_ready_nc),
    .w_data_i  (def_w_data),
    .w_strb_i  (def_w_strb),
    .b_valid_o (def_b_valid),
    .b_ready_i (def_b_ready),
    .b_resp_o  (def_b_resp),
    .ar_valid_i(def_ar_valid),
    .ar_ready_o(def_ar_ready_nc),
    .ar_addr_i (def_ar_addr),
    .r_valid_o (def_r_valid),
    .r_ready_i (def_r_ready),
    .r_data_o  (def_r_data),
    .r_resp_o  (def_r_resp)
  );

  always_comb begin
    for (int m = 0; m < NM; m++) begin
      logic aw_r, w_r, b_v, ar_r, r_v;
      logic [1:0] b_rr, r_rr;
      logic [31:0] r_dd;
      aw_r = 1'b0; w_r = 1'b0; b_v = 1'b0; ar_r = 1'b0; r_v = 1'b0;
      b_rr = 2'b00; r_rr = 2'b00; r_dd = 32'b0;
      for (int s = 0; s < NS; s++) begin
        aw_r = aw_r || p_aw_ready[s*NM + m];
        w_r  = w_r  || p_w_ready[s*NM + m];
        b_v  = b_v  || p_b_valid[s*NM + m];
        b_rr = b_rr | (p_b_resp[s*NM*2 + m*2 +: 2] & {2{p_b_valid[s*NM + m]}});
        ar_r = ar_r || p_ar_ready[s*NM + m];
        r_v  = r_v  || p_r_valid[s*NM + m];
        r_rr = r_rr | (p_r_resp[s*NM*2 + m*2 +: 2] & {2{p_r_valid[s*NM + m]}});
        r_dd = r_dd | p_r_data[s*NM*32 + m*32 +: 32];
      end
      aw_r = aw_r || d_aw_ready[m];
      w_r  = w_r  || d_w_ready[m];
      b_v  = b_v  || d_b_valid[m];
      b_rr = b_rr | (d_b_resp[m*2 +: 2] & {2{d_b_valid[m]}});
      ar_r = ar_r || d_ar_ready[m];
      r_v  = r_v  || d_r_valid[m];
      r_rr = r_rr | (d_r_resp[m*2 +: 2] & {2{d_r_valid[m]}});
      r_dd = r_dd | d_r_data[m*32 +: 32];
      m_aw_ready_o[m] = aw_r;
      m_w_ready_o[m]  = w_r;
      m_b_valid_o[m]  = b_v;
      m_b_resp_o[m*2 +: 2] = b_rr;
      m_ar_ready_o[m] = ar_r;
      m_r_valid_o[m]  = r_v;
      m_r_resp_o[m*2 +: 2] = r_rr;
      m_r_data_o[m*32 +: 32] = r_dd;
    end
  end

  logic _unused;
  assign _unused = ^{def_aw_ready_nc, def_w_ready_nc, def_ar_ready_nc};

endmodule
