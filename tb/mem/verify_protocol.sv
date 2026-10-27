`timescale 1ns/1ps
`ifndef _AMECHIP_PKG_SV
 `include "amechip_pkg.sv"
`endif

module verify_protocol #(
  parameter int unsigned NM = 4,
  parameter int unsigned NS = 9
) (
  input  logic clk_i,
  input  logic rst_ni,

  input  logic [NM-1:0]     m_aw_valid_i,
  input  logic [NM-1:0]     m_aw_ready_o,
  input  logic [32*NM-1:0]  m_aw_addr_i,
  input  logic [NM-1:0]     m_w_valid_i,
  input  logic [NM-1:0]     m_w_ready_o,
  input  logic [32*NM-1:0]  m_w_data_i,
  input  logic [4*NM-1:0]   m_w_strb_i,
  input  logic [NM-1:0]     m_b_valid_o,
  input  logic [NM-1:0]     m_b_ready_i,
  input  logic [2*NM-1:0]   m_b_resp_o,
  input  logic [NM-1:0]     m_ar_valid_i,
  input  logic [NM-1:0]     m_ar_ready_o,
  input  logic [32*NM-1:0]  m_ar_addr_i,
  input  logic [NM-1:0]     m_r_valid_o,
  input  logic [NM-1:0]     m_r_ready_i,
  input  logic [32*NM-1:0]  m_r_data_o,
  input  logic [2*NM-1:0]   m_r_resp_o,

  input  logic [NS-1:0]     s_aw_valid_o,
  input  logic [NS-1:0]     s_aw_ready_i,
  input  logic [32*NS-1:0]  s_aw_addr_o,
  input  logic [NS-1:0]     s_w_valid_o,
  input  logic [NS-1:0]     s_w_ready_i,
  input  logic [32*NS-1:0]  s_w_data_o,
  input  logic [4*NS-1:0]   s_w_strb_o,
  input  logic [NS-1:0]     s_b_valid_i,
  input  logic [NS-1:0]     s_b_ready_o,
  input  logic [2*NS-1:0]   s_b_resp_i,
  input  logic [NS-1:0]     s_ar_valid_o,
  input  logic [NS-1:0]     s_ar_ready_i,
  input  logic [32*NS-1:0]  s_ar_addr_o,
  input  logic [NS-1:0]     s_r_valid_i,
  input  logic [NS-1:0]     s_r_ready_o,
  input  logic [32*NS-1:0]  s_r_data_i,
  input  logic [2*NS-1:0]   s_r_resp_i
);

  localparam int unsigned QD = 64; // 每主每方向 outstanding 记录深度

  localparam int C_M_AW_ST = 0, C_M_W_ST = 1, C_M_AR_ST = 2,
                 C_S_AW_ST = 3, C_S_W_ST = 4, C_S_AR_ST = 5,
                 C_S_B_ST  = 6, C_S_R_ST = 7,
                 C_RESP    = 8, C_ORPHAN = 9, C_ALIGN = 10, C_PAIR = 11,
                 C_XCHK    = 12, C_LOST   = 13, C_N = 14;

  int hits  [0:C_N-1];
  int fails [0:C_N-1];
  int total_hits, total_fails;
  int mi, ci;
  string cls_name [0:C_N-1];

  initial begin
    for (int i = 0; i < C_N; i++) begin
      hits[i] = 0; fails[i] = 0;
    end
    total_hits = 0; total_fails = 0;
    cls_name[C_M_AW_ST] = "M_AW_STABLE";
    cls_name[C_M_W_ST]  = "M_W_STABLE";
    cls_name[C_M_AR_ST] = "M_AR_STABLE";
    cls_name[C_S_AW_ST] = "S_AW_STABLE";
    cls_name[C_S_W_ST]  = "S_W_STABLE";
    cls_name[C_S_AR_ST] = "S_AR_STABLE";
    cls_name[C_S_B_ST]  = "S_B_STABLE";
    cls_name[C_S_R_ST]  = "S_R_STABLE";
    cls_name[C_RESP]    = "RESP_CORRECT";
    cls_name[C_ORPHAN]  = "RESP_ORPHAN";
    cls_name[C_ALIGN]   = "ADDR_ALIGN";
    cls_name[C_PAIR]    = "S_AW_W_PAIR";
    cls_name[C_XCHK]    = "NO_X";
    cls_name[C_LOST]    = "RESP_LOST";
  end

`define VHIT(c) begin hits[c] = hits[c] + 1; total_hits = total_hits + 1; end

  task automatic bad(input int c, input string msg);
    fails[c] = fails[c] + 1;
    total_fails = total_fails + 1;
    if (fails[c] <= 8) $display("[PROTO-FAIL] %0t %s: %s", $time, cls_name[c], msg);
  endtask

  function automatic int unsigned slave_of(input logic [31:0] a);
    if (a <= 32'h0000_0FFF)                                  return 0; // OC SRAM
    if (a >= 32'h0001_0000 && a <= 32'h0001_07FF)            return 1; // BOOT ROM
    if (a >= 32'h1000_0000 && a <= 32'h1000_0FFF)            return 2; // SYS
    if (a >= 32'h1000_1000 && a <= 32'h1000_1FFF)            return 3; // INTC
    if (a >= 32'h1000_2000 && a <= 32'h1000_2FFF)            return 4; // UART
    if (a >= 32'h2000_0000 && a <= 32'h2000_0FFF)            return 5; // DMA
    if (a >= 32'h2000_1000 && a <= 32'h2000_2FFF)            return 6; // AME
    if (a >= 32'h2000_3000 && a <= 32'h2000_3FFF)            return 7; // KV
    if (a >= 32'h4000_0000 && a <= 32'h407F_FFFF)            return 8; // XMEM
    return 32'hFFFF_FFFF;                                            // 保留
  endfunction

  function automatic logic [1:0] resp_expected(input bit is_wr, input logic [31:0] a);
    int unsigned s;
    s = slave_of(a);
    if (s == 32'hFFFF_FFFF) return amechip_pkg::AXI_DECERR;
    if (is_wr && s == 1)     return amechip_pkg::AXI_SLVERR; // BOOT ROM 写
    return amechip_pkg::AXI_OKAY;
  endfunction

  logic [31:0] awq [0:NM*QD-1];
  logic [31:0] arq [0:NM*QD-1];
  int awq_wp [0:NM-1], awq_rp [0:NM-1];
  int arq_wp [0:NM-1], arq_rp [0:NM-1];
  int sp_wr [0:NS-1], sp_rd [0:NS-1];

  logic [NM-1:0]    p_aw_st, p_w_st, p_ar_st, p_b_st, p_r_st;
  logic [32*NM-1:0] p_aw_a, p_w_d, p_ar_a, p_r_d;
  logic [31:0]      a_resp;
  logic [4*NM-1:0]  p_w_s;
  logic [2*NM-1:0]  p_b_r, p_r_r;

  logic [NS-1:0]    q_aw_st, q_w_st, q_ar_st, q_b_st, q_r_st;
  logic [32*NS-1:0] q_aw_a, q_w_d, q_ar_a, q_r_d;
  logic [4*NS-1:0]  q_w_s;
  logic [2*NS-1:0]  q_b_r, q_r_r;


  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      for (int m = 0; m < NM; m++) begin
        awq_wp[m] = 0; awq_rp[m] = 0;
        arq_wp[m] = 0; arq_rp[m] = 0;
      end
      for (int s = 0; s < NS; s++) begin
        sp_wr[s] = 0; sp_rd[s] = 0;
      end
      p_aw_st <= '0; p_w_st <= '0; p_ar_st <= '0; p_b_st <= '0; p_r_st <= '0;
      p_aw_a <= '0; p_w_d <= '0; p_w_s <= '0; p_ar_a <= '0;
      p_b_r <= '0; p_r_r <= '0; p_r_d <= '0;
      q_aw_st <= '0; q_w_st <= '0; q_ar_st <= '0; q_b_st <= '0; q_r_st <= '0;
      q_aw_a <= '0; q_w_d <= '0; q_w_s <= '0; q_ar_a <= '0;
      q_b_r <= '0; q_r_r <= '0; q_r_d <= '0;
    end else begin
      for (int m = 0; m < NM; m++) begin
        if (p_aw_st[m]) begin
          `VHIT(C_M_AW_ST);
          if (!m_aw_valid_i[m]) bad(C_M_AW_ST, $sformatf("M%0d AW valid 撤销(未 ready)", m));
          else if (m_aw_addr_i[m*32 +: 32] !== p_aw_a[m*32 +: 32])
            bad(C_M_AW_ST, $sformatf("M%0d AW addr 变化 %08h->%08h", m,
                p_aw_a[m*32 +: 32], m_aw_addr_i[m*32 +: 32]));
        end
        if (p_w_st[m]) begin
          `VHIT(C_M_W_ST);
          if (!m_w_valid_i[m]) bad(C_M_W_ST, $sformatf("M%0d W valid 撤销(未 ready)", m));
          else if ((m_w_data_i[m*32 +: 32] !== p_w_d[m*32 +: 32]) ||
                   (m_w_strb_i[m*4 +: 4] !== p_w_s[m*4 +: 4]))
            bad(C_M_W_ST, $sformatf("M%0d W 载荷变化", m));
        end
        if (p_ar_st[m]) begin
          `VHIT(C_M_AR_ST);
          if (!m_ar_valid_i[m]) bad(C_M_AR_ST, $sformatf("M%0d AR valid 撤销(未 ready)", m));
          else if (m_ar_addr_i[m*32 +: 32] !== p_ar_a[m*32 +: 32])
            bad(C_M_AR_ST, $sformatf("M%0d AR addr 变化 %08h->%08h", m,
                p_ar_a[m*32 +: 32], m_ar_addr_i[m*32 +: 32]));
        end
        if (p_b_st[m]) begin
          `VHIT(C_S_B_ST);
          if (!m_b_valid_o[m]) bad(C_S_B_ST, $sformatf("M%0d B valid 撤销(未 ready)", m));
          else if (m_b_resp_o[m*2 +: 2] !== p_b_r[m*2 +: 2])
            bad(C_S_B_ST, $sformatf("M%0d B resp 变化", m));
        end
        if (p_r_st[m]) begin
          `VHIT(C_S_R_ST);
          if (!m_r_valid_o[m]) bad(C_S_R_ST, $sformatf("M%0d R valid 撤销(未 ready)", m));
          else if ((m_r_data_o[m*32 +: 32] !== p_r_d[m*32 +: 32]) ||
                   (m_r_resp_o[m*2 +: 2] !== p_r_r[m*2 +: 2]))
            bad(C_S_R_ST, $sformatf("M%0d R 载荷变化", m));
        end
      end

      for (int m = 0; m < NM; m++) begin
        if (m_aw_valid_i[m] && m_aw_ready_o[m]) begin
          `VHIT(C_ALIGN);
          if (m_aw_addr_i[m*32 +: 2] !== 2'b00)
            bad(C_ALIGN, $sformatf("M%0d AW 地址非字对齐 %08h", m, m_aw_addr_i[m*32 +: 32]));
          if ((awq_wp[m] - awq_rp[m]) >= QD) begin
            bad(C_ORPHAN, $sformatf("M%0d AW 队列溢出", m));
          end else begin
            awq[m*QD + (awq_wp[m] % QD)] = m_aw_addr_i[m*32 +: 32];
            awq_wp[m] = awq_wp[m] + 1;
          end
        end
        if (m_ar_valid_i[m] && m_ar_ready_o[m]) begin
          `VHIT(C_ALIGN);
          if (m_ar_addr_i[m*32 +: 2] !== 2'b00)
            bad(C_ALIGN, $sformatf("M%0d AR 地址非字对齐 %08h", m, m_ar_addr_i[m*32 +: 32]));
          if ((arq_wp[m] - arq_rp[m]) >= QD) begin
            bad(C_ORPHAN, $sformatf("M%0d AR 队列溢出", m));
          end else begin
            arq[m*QD + (arq_wp[m] % QD)] = m_ar_addr_i[m*32 +: 32];
            arq_wp[m] = arq_wp[m] + 1;
          end
        end
        if (m_b_valid_o[m] && m_b_ready_i[m]) begin
          `VHIT(C_RESP);
          if (awq_wp[m] == awq_rp[m]) begin
            bad(C_ORPHAN, $sformatf("M%0d 收到无请求的 B 响应", m));
          end else begin
            a_resp = awq[m*QD + (awq_rp[m] % QD)];
            awq_rp[m] = awq_rp[m] + 1;
            if (m_b_resp_o[m*2 +: 2] !== resp_expected(1'b1, a_resp))
              bad(C_RESP, $sformatf("M%0d W@%08h resp=%b exp=%b", m, a_resp,
                  m_b_resp_o[m*2 +: 2], resp_expected(1'b1, a_resp)));
          end
        end
        if (m_r_valid_o[m] && m_r_ready_i[m]) begin
          `VHIT(C_RESP);
          if (arq_wp[m] == arq_rp[m]) begin
            bad(C_ORPHAN, $sformatf("M%0d 收到无请求的 R 响应", m));
          end else begin
            a_resp = arq[m*QD + (arq_rp[m] % QD)];
            arq_rp[m] = arq_rp[m] + 1;
            if (m_r_resp_o[m*2 +: 2] !== resp_expected(1'b0, a_resp))
              bad(C_RESP, $sformatf("M%0d R@%08h resp=%b exp=%b", m, a_resp,
                  m_r_resp_o[m*2 +: 2], resp_expected(1'b0, a_resp)));
            if ((m_r_resp_o[m*2 +: 2] == amechip_pkg::AXI_DECERR) &&
                (m_r_data_o[m*32 +: 32] !== 32'h0))
              bad(C_RESP, $sformatf("M%0d DECERR 读数据非 0 @%08h", m, a_resp));
          end
        end
      end

      for (int s = 0; s < NS; s++) begin
        if (q_aw_st[s]) begin
          `VHIT(C_S_AW_ST);
          if (!s_aw_valid_o[s]) bad(C_S_AW_ST, $sformatf("S%0d AW valid 撤销", s));
          else if (s_aw_addr_o[s*32 +: 32] !== q_aw_a[s*32 +: 32])
            bad(C_S_AW_ST, $sformatf("S%0d AW addr 变化", s));
        end
        if (q_w_st[s]) begin
          `VHIT(C_S_W_ST);
          if (!s_w_valid_o[s]) bad(C_S_W_ST, $sformatf("S%0d W valid 撤销", s));
          else if ((s_w_data_o[s*32 +: 32] !== q_w_d[s*32 +: 32]) ||
                   (s_w_strb_o[s*4 +: 4] !== q_w_s[s*4 +: 4]))
            bad(C_S_W_ST, $sformatf("S%0d W 载荷变化", s));
        end
        if (q_ar_st[s]) begin
          `VHIT(C_S_AR_ST);
          if (!s_ar_valid_o[s]) bad(C_S_AR_ST, $sformatf("S%0d AR valid 撤销", s));
          else if (s_ar_addr_o[s*32 +: 32] !== q_ar_a[s*32 +: 32])
            bad(C_S_AR_ST, $sformatf("S%0d AR addr 变化", s));
        end
        if (q_b_st[s]) begin
          `VHIT(C_S_B_ST);
          if (!s_b_valid_i[s]) bad(C_S_B_ST, $sformatf("S%0d B valid 撤销", s));
          else if (s_b_resp_i[s*2 +: 2] !== q_b_r[s*2 +: 2])
            bad(C_S_B_ST, $sformatf("S%0d B resp 变化", s));
        end
        if (q_r_st[s]) begin
          `VHIT(C_S_R_ST);
          if (!s_r_valid_i[s]) bad(C_S_R_ST, $sformatf("S%0d R valid 撤销", s));
          else if ((s_r_data_i[s*32 +: 32] !== q_r_d[s*32 +: 32]) ||
                   (s_r_resp_i[s*2 +: 2] !== q_r_r[s*2 +: 2]))
            bad(C_S_R_ST, $sformatf("S%0d R 载荷变化", s));
        end
        `VHIT(C_PAIR);
        if (s_aw_valid_o[s] !== s_w_valid_o[s])
          bad(C_PAIR, $sformatf("S%0d AW valid=%b 与 W valid=%b 不成对", s,
              s_aw_valid_o[s], s_w_valid_o[s]));
        if (s_aw_valid_o[s] && s_aw_ready_i[s]) begin
          `VHIT(C_ALIGN);
          if (s_aw_addr_o[s*32 +: 2] !== 2'b00)
            bad(C_ALIGN, $sformatf("S%0d AW 地址非字对齐", s));
          sp_wr[s] = sp_wr[s] + 1;
        end
        if (s_ar_valid_o[s] && s_ar_ready_i[s]) begin
          `VHIT(C_ALIGN);
          if (s_ar_addr_o[s*32 +: 2] !== 2'b00)
            bad(C_ALIGN, $sformatf("S%0d AR 地址非字对齐", s));
          sp_rd[s] = sp_rd[s] + 1;
        end
        if (s_b_valid_i[s] && s_b_ready_o[s]) begin
          `VHIT(C_RESP);
          if (sp_wr[s] == 0) bad(C_ORPHAN, $sformatf("S%0d B 无请求", s));
          else sp_wr[s] = sp_wr[s] - 1;
        end
        if (s_r_valid_i[s] && s_r_ready_o[s]) begin
          `VHIT(C_RESP);
          if (sp_rd[s] == 0) bad(C_ORPHAN, $sformatf("S%0d R 无请求", s));
          else sp_rd[s] = sp_rd[s] - 1;
        end
      end

      `VHIT(C_XCHK);
      if (((^m_aw_valid_i) === 1'bx) || ((^m_w_valid_i) === 1'bx) ||
          ((^m_ar_valid_i) === 1'bx) || ((^m_b_valid_o) === 1'bx) ||
          ((^m_r_valid_o) === 1'bx) || ((^s_aw_valid_o) === 1'bx) ||
          ((^s_w_valid_o) === 1'bx) || ((^s_ar_valid_o) === 1'bx) ||
          ((^s_b_valid_i) === 1'bx) || ((^s_r_valid_i) === 1'bx))
        bad(C_XCHK, $sformatf("复位后 valid 出现 X: m_awv=%b m_wv=%b m_arv=%b m_bv=%b m_rv=%b s_awv=%b s_wv=%b s_arv=%b s_bv=%b s_rv=%b",
            m_aw_valid_i, m_w_valid_i, m_ar_valid_i, m_b_valid_o, m_r_valid_o,
            s_aw_valid_o, s_w_valid_o, s_ar_valid_o, s_b_valid_i, s_r_valid_i));

      for (int m = 0; m < NM; m++) begin
        p_aw_st[m] <= m_aw_valid_i[m] && !m_aw_ready_o[m];
        p_w_st[m]  <= m_w_valid_i[m]  && !m_w_ready_o[m];
        p_ar_st[m] <= m_ar_valid_i[m] && !m_ar_ready_o[m];
        p_b_st[m]  <= m_b_valid_o[m]  && !m_b_ready_i[m];
        p_r_st[m]  <= m_r_valid_o[m]  && !m_r_ready_i[m];
        p_aw_a[m*32 +: 32] <= m_aw_addr_i[m*32 +: 32];
        p_w_d[m*32 +: 32]  <= m_w_data_i[m*32 +: 32];
        p_w_s[m*4 +: 4]    <= m_w_strb_i[m*4 +: 4];
        p_ar_a[m*32 +: 32] <= m_ar_addr_i[m*32 +: 32];
        p_r_d[m*32 +: 32]  <= m_r_data_o[m*32 +: 32];
        p_b_r[m*2 +: 2]    <= m_b_resp_o[m*2 +: 2];
        p_r_r[m*2 +: 2]    <= m_r_resp_o[m*2 +: 2];
      end
      for (int s = 0; s < NS; s++) begin
        q_aw_st[s] <= s_aw_valid_o[s] && !s_aw_ready_i[s];
        q_w_st[s]  <= s_w_valid_o[s]  && !s_w_ready_i[s];
        q_ar_st[s] <= s_ar_valid_o[s] && !s_ar_ready_i[s];
        q_b_st[s]  <= s_b_valid_i[s]  && !s_b_ready_o[s];
        q_r_st[s]  <= s_r_valid_i[s]  && !s_r_ready_o[s];
        q_aw_a[s*32 +: 32] <= s_aw_addr_o[s*32 +: 32];
        q_w_d[s*32 +: 32]  <= s_w_data_o[s*32 +: 32];
        q_w_s[s*4 +: 4]    <= s_w_strb_o[s*4 +: 4];
        q_ar_a[s*32 +: 32] <= s_ar_addr_o[s*32 +: 32];
        q_r_d[s*32 +: 32]  <= s_r_data_i[s*32 +: 32];
        q_b_r[s*2 +: 2]    <= s_b_resp_i[s*2 +: 2];
        q_r_r[s*2 +: 2]    <= s_r_resp_i[s*2 +: 2];
      end
    end
  end

  always @(posedge clk_i) begin
    if (!rst_ni) begin
      if ((|m_aw_valid_i) || (|m_w_valid_i) || (|m_ar_valid_i) ||
          (|s_aw_valid_o) || (|s_ar_valid_o))
        bad(C_XCHK, "复位期间出现 valid");
    end
  end

`ifdef VFRC_SVA
  generate
    for (genvar m = 0; m < NM; m++) begin : g_sva_m
      property p_aw_stab;
        @(posedge clk_i) disable iff (!rst_ni)
          (m_aw_valid_i[m] && !m_aw_ready_o[m]) |=>
          (m_aw_valid_i[m] && (m_aw_addr_i[m*32 +: 32] == $past(m_aw_addr_i[m*32 +: 32])));
      endproperty
      property p_w_stab;
        @(posedge clk_i) disable iff (!rst_ni)
          (m_w_valid_i[m] && !m_w_ready_o[m]) |=>
          (m_w_valid_i[m] && (m_w_data_i[m*32 +: 32] == $past(m_w_data_i[m*32 +: 32])) &&
           (m_w_strb_i[m*4 +: 4] == $past(m_w_strb_i[m*4 +: 4])));
      endproperty
      property p_ar_stab;
        @(posedge clk_i) disable iff (!rst_ni)
          (m_ar_valid_i[m] && !m_ar_ready_o[m]) |=>
          (m_ar_valid_i[m] && (m_ar_addr_i[m*32 +: 32] == $past(m_ar_addr_i[m*32 +: 32])));
      endproperty
      property p_r_stab;
        @(posedge clk_i) disable iff (!rst_ni)
          (m_r_valid_o[m] && !m_r_ready_i[m]) |=>
          (m_r_valid_o[m] && (m_r_data_o[m*32 +: 32] == $past(m_r_data_o[m*32 +: 32])) &&
           (m_r_resp_o[m*2 +: 2] == $past(m_r_resp_o[m*2 +: 2])));
      endproperty
      a_aw_stab: assert property (p_aw_stab) else $display("[SVA-ASSERT-FAIL] M%0d AW unstable", m);
      a_w_stab:  assert property (p_w_stab)  else $display("[SVA-ASSERT-FAIL] M%0d W unstable", m);
      a_ar_stab: assert property (p_ar_stab) else $display("[SVA-ASSERT-FAIL] M%0d AR unstable", m);
      a_r_stab:  assert property (p_r_stab)  else $display("[SVA-ASSERT-FAIL] M%0d R unstable", m);
    end
    for (genvar s = 0; s < NS; s++) begin : g_sva_s
      property p_saw_stab;
        @(posedge clk_i) disable iff (!rst_ni)
          (s_aw_valid_o[s] && !s_aw_ready_i[s]) |=>
          (s_aw_valid_o[s] && (s_aw_addr_o[s*32 +: 32] == $past(s_aw_addr_o[s*32 +: 32])));
      endproperty
      property p_sar_stab;
        @(posedge clk_i) disable iff (!rst_ni)
          (s_ar_valid_o[s] && !s_ar_ready_i[s]) |=>
          (s_ar_valid_o[s] && (s_ar_addr_o[s*32 +: 32] == $past(s_ar_addr_o[s*32 +: 32])));
      endproperty
      property p_sb_stab;
        @(posedge clk_i) disable iff (!rst_ni)
          (s_b_valid_i[s] && !s_b_ready_o[s]) |=>
          (s_b_valid_i[s] && (s_b_resp_i[s*2 +: 2] == $past(s_b_resp_i[s*2 +: 2])));
      endproperty
      a_saw_stab: assert property (p_saw_stab) else $display("[SVA-ASSERT-FAIL] S%0d AW unstable", s);
      a_sar_stab: assert property (p_sar_stab) else $display("[SVA-ASSERT-FAIL] S%0d AR unstable", s);
      a_sb_stab:  assert property (p_sb_stab)  else $display("[SVA-ASSERT-FAIL] S%0d B unstable", s);
    end
  endgenerate
`endif

  final begin
    mi = 0;
    while (mi < NM) begin
      if (awq_wp[mi] != awq_rp[mi]) begin
        fails[C_LOST] = fails[C_LOST] + 1;
        total_fails = total_fails + 1;
        $display("[PROTO-FAIL] master %0d write responses lost: accepted=%0d responded=%0d",
                 mi, awq_wp[mi], awq_rp[mi]);
      end
      if (arq_wp[mi] != arq_rp[mi]) begin
        fails[C_LOST] = fails[C_LOST] + 1;
        total_fails = total_fails + 1;
        $display("[PROTO-FAIL] master %0d read responses lost: accepted=%0d responded=%0d",
                 mi, arq_wp[mi], arq_rp[mi]);
      end
      mi = mi + 1;
    end
    $display("[PROTO] ===== assertion hit statistics =====");
    ci = 0;
    while (ci < C_N) begin
      $display("[PROTO] %-14s hits=%0d fails=%0d", cls_name[ci], hits[ci], fails[ci]);
      ci = ci + 1;
    end
    $display("[PROTO] TOTAL checks=%0d fails=%0d", total_hits, total_fails);
    if (total_fails == 0) $display("PROTO: PASS");
    else                  $display("PROTO: FAIL");
  end

endmodule
