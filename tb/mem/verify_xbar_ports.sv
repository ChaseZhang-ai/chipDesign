`timescale 1ns/1ps
`include "amechip_pkg.sv"

package verify_xbar_pkg;

  function automatic logic [31:0] sdata(input int unsigned sid, input logic [31:0] a);
    sdata = {a[15:0], 8'hA5, 8'(sid)};
  endfunction

  function automatic logic [1:0] sresp(input int unsigned sid, input bit wr);
    if (sid == 1 && wr) return amechip_pkg::AXI_SLVERR;
    return amechip_pkg::AXI_OKAY;
  endfunction

endpackage

module verify_xbar_slave #(
  parameter int unsigned SID = 0
) (
  input  logic clk_i,
  input  logic rst_ni,
  input  logic aw_valid_i, output logic aw_ready_o, input  logic [31:0] aw_addr_i,
  input  logic w_valid_i,  output logic w_ready_o,  input  logic [31:0] w_data_i,
  input  logic [3:0]  w_strb_i,
  output logic b_valid_o,  input  logic b_ready_i,  output logic [1:0] b_resp_o,
  input  logic ar_valid_i, output logic ar_ready_o, input  logic [31:0] ar_addr_i,
  output logic r_valid_o,  input  logic r_ready_i,  output logic [31:0] r_data_o,
  output logic [1:0] r_resp_o
);
  logic [31:0] lfsr;
  logic        b_valid_q, r_valid_q;
  logic [31:0] b_addr_q, r_addr_q, r_data_q;
  logic [1:0]  b_resp_q, r_resp_q;

  logic [3:0] cnt;
  wire accept_now = (cnt != 4'd0);
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      lfsr <= 32'h1234_5678 + SID * 32'h0101_0101;
      cnt  <= 4'd0;
    end else begin
      lfsr <= lfsr * 32'h9E37_79B9 + 32'h517C_C1B7 + SID;
      if (cnt == 4'd0) cnt <= 4'd1 + lfsr[3:1];
      else             cnt <= cnt - 4'd1;
    end
  end

  assign aw_ready_o = accept_now && !b_valid_q;
  assign w_ready_o  = accept_now && !b_valid_q;
  assign ar_ready_o = accept_now && !r_valid_q;

  logic wr_acc;
  assign wr_acc = aw_valid_i && w_valid_i && aw_ready_o;
  logic rd_acc;
  assign rd_acc = ar_valid_i && ar_ready_o;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      b_valid_q <= 1'b0; r_valid_q <= 1'b0;
      b_resp_q <= 2'b0;  r_resp_q <= 2'b0;
      b_addr_q <= '0;    r_addr_q <= '0; r_data_q <= '0;
    end else begin
      if (wr_acc) begin
        b_valid_q <= 1'b1;
        b_addr_q  <= aw_addr_i;
        b_resp_q  <= verify_xbar_pkg::sresp(SID, 1'b1);
      end else if (b_valid_q && b_ready_i) begin
        b_valid_q <= 1'b0;
      end
      if (rd_acc) begin
        r_valid_q <= 1'b1;
        r_addr_q  <= ar_addr_i;
        r_data_q  <= verify_xbar_pkg::sdata(SID, ar_addr_i);
        r_resp_q  <= verify_xbar_pkg::sresp(SID, 1'b0);
      end else if (r_valid_q && r_ready_i) begin
        r_valid_q <= 1'b0;
      end
    end
  end
  assign b_valid_o = b_valid_q;
  assign b_resp_o  = b_resp_q;
  assign r_valid_o = r_valid_q;
  assign r_data_o  = r_data_q;
  assign r_resp_o  = r_resp_q;

  logic _unused;
  assign _unused = ^{w_data_i, w_strb_i, b_addr_q, r_addr_q};
endmodule

module verify_xbar_ports;

  localparam int NM = 4;
  localparam int NS = 9;

  logic clk = 1'b0;
  logic rst_n;
  always #5 clk = ~clk;

  logic [NM-1:0]    m_aw_valid, m_aw_ready;
  logic [32*NM-1:0] m_aw_addr;
  logic [NM-1:0]    m_w_valid, m_w_ready;
  logic [32*NM-1:0] m_w_data;
  logic [4*NM-1:0]  m_w_strb;
  logic [NM-1:0]    m_b_valid, m_b_ready;
  logic [2*NM-1:0]  m_b_resp;
  logic [NM-1:0]    m_ar_valid, m_ar_ready;
  logic [32*NM-1:0] m_ar_addr;
  logic [NM-1:0]    m_r_valid, m_r_ready;
  logic [32*NM-1:0] m_r_data;
  logic [2*NM-1:0]  m_r_resp;

  logic [NS-1:0]    s_aw_valid, s_aw_ready;
  logic [32*NS-1:0] s_aw_addr;
  logic [NS-1:0]    s_w_valid, s_w_ready;
  logic [32*NS-1:0] s_w_data;
  logic [4*NS-1:0]  s_w_strb;
  logic [NS-1:0]    s_b_valid, s_b_ready;
  logic [2*NS-1:0]  s_b_resp;
  logic [NS-1:0]    s_ar_valid, s_ar_ready;
  logic [32*NS-1:0] s_ar_addr;
  logic [NS-1:0]    s_r_valid, s_r_ready;
  logic [32*NS-1:0] s_r_data;
  logic [2*NS-1:0]  s_r_resp;

  axi_xbar #(.NM(NM), .NS(NS)) dut (
    .clk_i(clk), .rst_ni(rst_n),
    .m_aw_valid_i(m_aw_valid), .m_aw_ready_o(m_aw_ready), .m_aw_addr_i(m_aw_addr),
    .m_w_valid_i(m_w_valid),   .m_w_ready_o(m_w_ready),   .m_w_data_i(m_w_data),
    .m_w_strb_i(m_w_strb),
    .m_b_valid_o(m_b_valid),   .m_b_ready_i(m_b_ready),   .m_b_resp_o(m_b_resp),
    .m_ar_valid_i(m_ar_valid), .m_ar_ready_o(m_ar_ready), .m_ar_addr_i(m_ar_addr),
    .m_r_valid_o(m_r_valid),   .m_r_ready_i(m_r_ready),   .m_r_data_o(m_r_data),
    .m_r_resp_o(m_r_resp),
    .s_aw_valid_o(s_aw_valid), .s_aw_ready_i(s_aw_ready), .s_aw_addr_o(s_aw_addr),
    .s_w_valid_o(s_w_valid),   .s_w_ready_i(s_w_ready),   .s_w_data_o(s_w_data),
    .s_w_strb_o(s_w_strb),
    .s_b_valid_i(s_b_valid),   .s_b_ready_o(s_b_ready),   .s_b_resp_i(s_b_resp),
    .s_ar_valid_o(s_ar_valid), .s_ar_ready_i(s_ar_ready), .s_ar_addr_o(s_ar_addr),
    .s_r_valid_i(s_r_valid),   .s_r_ready_o(s_r_ready),   .s_r_data_i(s_r_data),
    .s_r_resp_i(s_r_resp)
  );

  for (genvar s = 0; s < NS; s++) begin : g_slv
    verify_xbar_slave #(.SID(s)) u_slv (
      .clk_i(clk), .rst_ni(rst_n),
      .aw_valid_i(s_aw_valid[s]), .aw_ready_o(s_aw_ready[s]),
      .aw_addr_i(s_aw_addr[s*32 +: 32]),
      .w_valid_i(s_w_valid[s]), .w_ready_o(s_w_ready[s]),
      .w_data_i(s_w_data[s*32 +: 32]), .w_strb_i(s_w_strb[s*4 +: 4]),
      .b_valid_o(s_b_valid[s]), .b_ready_i(s_b_ready[s]),
      .b_resp_o(s_b_resp[s*2 +: 2]),
      .ar_valid_i(s_ar_valid[s]), .ar_ready_o(s_ar_ready[s]),
      .ar_addr_i(s_ar_addr[s*32 +: 32]),
      .r_valid_o(s_r_valid[s]), .r_ready_i(s_r_ready[s]),
      .r_data_o(s_r_data[s*32 +: 32]), .r_resp_o(s_r_resp[s*2 +: 2])
    );
  end

  verify_protocol #(.NM(NM), .NS(NS)) u_proto (
    .clk_i(clk), .rst_ni(rst_n),
    .m_aw_valid_i(m_aw_valid), .m_aw_ready_o(m_aw_ready), .m_aw_addr_i(m_aw_addr),
    .m_w_valid_i(m_w_valid),   .m_w_ready_o(m_w_ready),   .m_w_data_i(m_w_data),
    .m_w_strb_i(m_w_strb),
    .m_b_valid_o(m_b_valid),   .m_b_ready_i(m_b_ready),   .m_b_resp_o(m_b_resp),
    .m_ar_valid_i(m_ar_valid), .m_ar_ready_o(m_ar_ready), .m_ar_addr_i(m_ar_addr),
    .m_r_valid_o(m_r_valid),   .m_r_ready_i(m_r_ready),   .m_r_data_o(m_r_data),
    .m_r_resp_o(m_r_resp),
    .s_aw_valid_o(s_aw_valid), .s_aw_ready_i(s_aw_ready), .s_aw_addr_o(s_aw_addr),
    .s_w_valid_o(s_w_valid),   .s_w_ready_i(s_w_ready),   .s_w_data_o(s_w_data),
    .s_w_strb_o(s_w_strb),
    .s_b_valid_i(s_b_valid),   .s_b_ready_o(s_b_ready),   .s_b_resp_i(s_b_resp),
    .s_ar_valid_o(s_ar_valid), .s_ar_ready_i(s_ar_ready), .s_ar_addr_o(s_ar_addr),
    .s_r_valid_i(s_r_valid),   .s_r_ready_o(s_r_ready),   .s_r_data_i(s_r_data),
    .s_r_resp_i(s_r_resp)
  );

  int  errors, checks;
  int  out_r [0:NM-1], out_w [0:NM-1];
  int  lim_r [0:NM-1], lim_w [0:NM-1];
  logic [31:0] erd_q [0:NM*32-1];
  logic [1:0]  ers_q [0:NM*32-1];
  logic [31:0] ewr_q [0:NM*32-1];
  logic [31:0] ewr_a [0:NM*32-1];
  logic [1:0]  ews_q [0:NM*32-1];
  int  rwp [0:NM-1], rrp [0:NM-1], wwp [0:NM-1], wrp [0:NM-1];
  int  nrd [0:NM-1], nwr [0:NM-1];
  int  seed [0:NM-1];

  task automatic fail(input string msg);
    errors = errors + 1;
    if (errors <= 40) $display("[FAIL] %0t %s", $time, msg);
  endtask

  function automatic logic [31:0] rnd(input int m);
    seed[m] = (seed[m] * 1103515245 + 12345) & 32'h7FFF_FFFF;
    rnd = 32'(seed[m]);
  endfunction

  function automatic logic [31:0] slv_base(input int unsigned s);
    case (s)
      0: slv_base = 32'h0000_0000;
      1: slv_base = 32'h0001_0000;
      2: slv_base = 32'h1000_0000;
      3: slv_base = 32'h1000_1000;
      4: slv_base = 32'h1000_2000;
      5: slv_base = 32'h2000_0000;
      6: slv_base = 32'h2000_1000;
      7: slv_base = 32'h2000_3000;
      default: slv_base = 32'h4000_0000;
    endcase
  endfunction

  function automatic int unsigned dec_sid(input logic [31:0] a);
    if (a <= 32'h0000_0FFF)                       return 0;
    if (a >= 32'h0001_0000 && a <= 32'h0001_07FF) return 1;
    if (a >= 32'h1000_0000 && a <= 32'h1000_0FFF) return 2;
    if (a >= 32'h1000_1000 && a <= 32'h1000_1FFF) return 3;
    if (a >= 32'h1000_2000 && a <= 32'h1000_2FFF) return 4;
    if (a >= 32'h2000_0000 && a <= 32'h2000_0FFF) return 5;
    if (a >= 32'h2000_1000 && a <= 32'h2000_2FFF) return 6;
    if (a >= 32'h2000_3000 && a <= 32'h2000_3FFF) return 7;
    if (a >= 32'h4000_0000 && a <= 32'h407F_FFFF) return 8;
    return 9;
  endfunction

  function automatic logic [31:0] slv_addr(input int unsigned s, input logic [31:0] r);
    logic [31:0] span;
    span = (s == 1) ? 32'h7FC : ((s == 0) ? 32'hFFC : 32'hFFC);
    slv_addr = slv_base(s) + ((r % (span >> 2)) << 2);
  endfunction

  logic [31:0] rdy_seed [0:NM-1];
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int m = 0; m < NM; m++) begin
        rdy_seed[m] <= 32'h0BAD_0001 + m * 32'h0001_0101;
        m_b_ready[m] <= 1'b1;
        m_r_ready[m] <= 1'b1;
      end
    end else begin
      for (int m = 0; m < NM; m++) begin
        rdy_seed[m] <= rdy_seed[m] * 32'h9E37_79B9 + 32'h517C_C1B7;
        m_b_ready[m] <= (rdy_seed[m][6:5] != 2'b00);
        m_r_ready[m] <= (rdy_seed[m][9:8] != 2'b00);
      end
    end
  end

  always @(posedge clk) begin
    if (rst_n) begin
      for (int m = 0; m < NM; m++) begin
        if (m_r_valid[m] && m_r_ready[m]) begin
          checks = checks + 1;
          if (out_r[m] == 0) fail($sformatf("M%0d 多余读响应", m));
          else begin
            if (m_r_data[m*32 +: 32] !== erd_q[m*32 + (rrp[m] % 32)])
              fail($sformatf("M%0d R data got=%08h exp=%08h", m,
                   m_r_data[m*32 +: 32], erd_q[m*32 + (rrp[m] % 32)]));
            if (m_r_resp[m*2 +: 2] !== ers_q[m*32 + (rrp[m] % 32)])
              fail($sformatf("M%0d R resp got=%b exp=%b", m,
                   m_r_resp[m*2 +: 2], ers_q[m*32 + (rrp[m] % 32)]));
            rrp[m] = rrp[m] + 1;
            out_r[m] = out_r[m] - 1;
          end
        end
        if (m_b_valid[m] && m_b_ready[m]) begin
          checks = checks + 1;
          if (out_w[m] == 0) fail($sformatf("M%0d 多余写响应 (wrp=%0d wwp=%0d)", m, wrp[m], wwp[m]));
          else begin
            if (m_b_resp[m*2 +: 2] !== ews_q[m*32 + (wrp[m] % 32)])
              fail($sformatf("M%0d B resp got=%b exp=%b addr=%08h", m,
                   m_b_resp[m*2 +: 2], ews_q[m*32 + (wrp[m] % 32)],
                   ewr_a[m*32 + (wrp[m] % 32)]));
            wrp[m] = wrp[m] + 1;
            out_w[m] = out_w[m] - 1;
          end
        end
      end
    end
  end

  task automatic issue_read(input int m, input logic [31:0] a, input logic [1:0] exp_resp);
    begin
      while (out_r[m] >= lim_r[m]) @(posedge clk);
      erd_q[m*32 + (rwp[m] % 32)] = (dec_sid(a) == NS) ? 32'h0
                                                       : verify_xbar_pkg::sdata(dec_sid(a), a);
      ers_q[m*32 + (rwp[m] % 32)]  = exp_resp;
      rwp[m] = rwp[m] + 1;
      out_r[m] = out_r[m] + 1;
      nrd[m] = nrd[m] + 1;
      @(negedge clk);
      m_ar_valid[m] = 1'b1; m_ar_addr[m*32 +: 32] = a;
      @(posedge clk);
      while (!m_ar_ready[m]) @(posedge clk);
      @(negedge clk);
      m_ar_valid[m] = 1'b0;
    end
  endtask

  task automatic issue_write(input int m, input logic [31:0] a, input logic [31:0] d,
                             input logic [1:0] exp_resp);
    begin
      while (out_w[m] >= lim_w[m]) @(posedge clk);
      ewr_q[m*32 + (wwp[m] % 32)] = d;
      ewr_a[m*32 + (wwp[m] % 32)] = a;
      ews_q[m*32 + (wwp[m] % 32)]  = exp_resp;
      wwp[m] = wwp[m] + 1;
      out_w[m] = out_w[m] + 1;
      nwr[m] = nwr[m] + 1;
      @(negedge clk);
      m_aw_valid[m] = 1'b1; m_w_valid[m] = 1'b1;
      m_aw_addr[m*32 +: 32] = a;
      m_w_data[m*32 +: 32]  = d;
      m_w_strb[m*4 +: 4]    = 4'hF;
      @(posedge clk);
      while (!(m_aw_ready[m] && m_w_ready[m])) @(posedge clk);
      @(negedge clk);
      m_aw_valid[m] = 1'b0; m_w_valid[m] = 1'b0;
    end
  endtask

  task automatic master_flow(input int m);
    logic [31:0] a, d;
    logic [1:0]  er;
    int sid;
    begin
      for (int s = 0; s < NS; s++) begin
        a = slv_addr(s, rnd(m));
        issue_read(m, a, amechip_pkg::AXI_OKAY);
        a = slv_addr(s, rnd(m));
        er = (s == 1) ? amechip_pkg::AXI_SLVERR : amechip_pkg::AXI_OKAY;
        issue_write(m, a, rnd(m), er);
      end
      for (int k = 0; k < 200; k++) begin
        sid = rnd(m) % NS;
        a = slv_addr(sid, rnd(m));
        d = rnd(m);
        if (d[8]) issue_read(m, a, amechip_pkg::AXI_OKAY);
        else issue_write(m, a, rnd(m),
                         (sid == 1) ? amechip_pkg::AXI_SLVERR : amechip_pkg::AXI_OKAY);
      end
    end
  endtask

  task automatic depth_phase();
    logic [31:0] a;
    begin
      $display("[xbar] 深度阶段:4 主并发压 S8(读)/S0(写),每主 4 笔在途");
      for (int m = 0; m < NM; m++) begin
        lim_r[m] = 4; lim_w[m] = 4;
      end
      fork
        for (int i = 0; i < 4; i++) issue_read(0, 32'h4000_1000 + 4*i, amechip_pkg::AXI_OKAY);
        for (int i = 0; i < 4; i++) issue_read(1, 32'h4000_2000 + 4*i, amechip_pkg::AXI_OKAY);
        for (int i = 0; i < 4; i++) issue_write(2, 32'h0000_0300 + 4*i, 32'hD000_0000 + i,
                                                amechip_pkg::AXI_OKAY);
        for (int i = 0; i < 4; i++) issue_read(3, 32'h4000_3000 + 4*i, amechip_pkg::AXI_OKAY);
      join
      while (out_r[0] || out_r[1] || out_r[3] || out_w[2]) @(posedge clk);
      for (int m = 0; m < NM; m++) begin
        lim_r[m] = 1; lim_w[m] = 1;
      end
    end
  endtask

  task automatic decerr_phase();
    logic [31:0] addrs [0:5];
    logic [31:0] a;
    begin
      $display("[xbar] DECERR 阶段:全主口访问全部保留区");
      addrs[0] = 32'h0000_2000; addrs[1] = 32'h0001_1000;
      addrs[2] = 32'h1000_5000; addrs[3] = 32'h2000_5000;
      addrs[4] = 32'h4080_0000; addrs[5] = 32'hFFFF_FFFC;
      for (int m = 0; m < NM; m++) begin
        for (int i = 0; i < 6; i++) begin
          issue_read(m, addrs[i], amechip_pkg::AXI_DECERR);
          issue_write(m, addrs[i], 32'hBAD0_0000 + i, amechip_pkg::AXI_DECERR);
        end
      end
      while (out_r[0] || out_r[1] || out_r[2] || out_r[3] ||
             out_w[0] || out_w[1] || out_w[2] || out_w[3]) @(posedge clk);
    end
  endtask

  initial begin
    rst_n = 1'b0;
    errors = 0; checks = 0;
    m_aw_valid = '0; m_w_valid = '0; m_ar_valid = '0;
    m_aw_addr = '0; m_w_data = '0; m_w_strb = '0; m_ar_addr = '0;
    m_b_ready = '1; m_r_ready = '1;
    for (int m = 0; m < NM; m++) begin
      out_r[m] = 0; out_w[m] = 0; lim_r[m] = 1; lim_w[m] = 1;
      rwp[m] = 0; rrp[m] = 0; wwp[m] = 0; wrp[m] = 0;
      nrd[m] = 0; nwr[m] = 0;
      seed[m] = 32'h1000_0001 + m * 32'h00A5_00A5;
    end
    repeat (5) @(posedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);

    fork
      master_flow(0); master_flow(1); master_flow(2); master_flow(3);
    join

    depth_phase();
    decerr_phase();

    repeat (20) @(posedge clk);
    $display("=== verify_xbar_ports: checks=%0d errors=%0d rd=[%0d %0d %0d %0d] wr=[%0d %0d %0d %0d] ===",
             checks, errors, nrd[0], nrd[1], nrd[2], nrd[3],
             nwr[0], nwr[1], nwr[2], nwr[3]);
    if (errors == 0) $display("VERIFY_XBAR_PORTS: PASS");
    else             $display("VERIFY_XBAR_PORTS: FAIL");
    $finish;
  end

  initial begin
    #2_000_000;
    $display("[FAIL] verify_xbar_ports 全局超时");
    $display("VERIFY_XBAR_PORTS: FAIL");
    $finish;
  end

endmodule
