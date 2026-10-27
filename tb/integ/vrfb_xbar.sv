
`ifndef _AMECHIP_PKG_SV
 `include "amechip_pkg.sv"
`endif
`ifndef _SOC_PKG_SV
 `include "soc_pkg.sv"
`endif

module vrfb_xbar (
  input logic clk,
  input logic rst_n,
  input logic dbg_i,

  input  soc_pkg::soc_req_t  m0_req, output soc_pkg::soc_resp_t m0_resp,
  input  soc_pkg::soc_req_t  m1_req, output soc_pkg::soc_resp_t m1_resp,
  input  soc_pkg::soc_req_t  m2_req, output soc_pkg::soc_resp_t m2_resp,

  output soc_pkg::soc_req_t  s0_req, input soc_pkg::soc_resp_t s0_resp,
  output soc_pkg::soc_req_t  s1_req, input soc_pkg::soc_resp_t s1_resp,
  output soc_pkg::soc_req_t  s2_req, input soc_pkg::soc_resp_t s2_resp,
  output soc_pkg::soc_req_t  s3_req, input soc_pkg::soc_resp_t s3_resp,
  output soc_pkg::soc_req_t  s4_req, input soc_pkg::soc_resp_t s4_resp,
  output soc_pkg::soc_req_t  s5_req, input soc_pkg::soc_resp_t s5_resp,
  output soc_pkg::soc_req_t  s6_req, input soc_pkg::soc_resp_t s6_resp,
  output soc_pkg::soc_req_t  s7_req, input soc_pkg::soc_resp_t s7_resp
);

  localparam int NM = 3;
  localparam int NS = 8;

  function automatic int decode(input logic [31:0] addr);
    if (addr >= amechip_pkg::A_SYS_BASE && addr <= amechip_pkg::A_SYS_END)        return 1;
    else if (addr >= amechip_pkg::A_INTC_BASE && addr <= amechip_pkg::A_INTC_END) return 2;
    else if (addr >= amechip_pkg::A_UART_BASE && addr <= amechip_pkg::A_UART_END) return 3;
    else if (addr >= amechip_pkg::A_DMA_BASE  && addr <= amechip_pkg::A_DMA_END)  return 4;
    else if (addr >= amechip_pkg::A_AME_BASE  && addr <= amechip_pkg::A_AME_END)  return 5;
    else if (addr >= amechip_pkg::A_KV_BASE   && addr <= amechip_pkg::A_KV_END)   return 6;
    else if (addr >= amechip_pkg::A_XMEM_BASE && addr <= amechip_pkg::A_XMEM_END) return 7;
    else return 0;
  endfunction

  logic [1:0] rr_pt  [0:NS-1];
  logic       busy   [0:NS-1];
  logic [1:0] g_id   [0:NS-1];

  wire [NM-1:0] m_req_v   [0:NS-1];
  wire [NM-1:0] m_wr_v    [0:NS-1];
  wire [31:0]   m_addr_v  [0:NS-1][0:NM-1];
  wire [31:0]   m_wdata_v [0:NS-1][0:NM-1];
  wire [3:0]    m_wstrb_v [0:NS-1][0:NM-1];
  wire          s_rsp_v   [0:NS-1];

  logic [1:0]  lock_s  [0:NM-1];
  logic        lock_wr [0:NM-1];
  logic [31:0] lock_addr [0:NM-1];
  logic [31:0] lock_wdata[0:NM-1];
  logic [3:0]  lock_strb [0:NM-1];

  assign s_rsp_v[0] = s0_resp.valid;
  assign s_rsp_v[1] = s1_resp.valid;
  assign s_rsp_v[2] = s2_resp.valid;
  assign s_rsp_v[3] = s3_resp.valid;
  assign s_rsp_v[4] = s4_resp.valid;
  assign s_rsp_v[5] = s5_resp.valid;
  assign s_rsp_v[6] = s6_resp.valid;
  assign s_rsp_v[7] = s7_resp.valid;

  genvar gs, gm;
  generate
    for (gs = 0; gs < NS; gs = gs + 1) begin : g_slave
      wire [NM-1:0] rq;
      assign rq[0] = m0_req.valid && (decode(m0_req.addr) == gs);
      assign rq[1] = m1_req.valid && (decode(m1_req.addr) == gs);
      assign rq[2] = m2_req.valid && (decode(m2_req.addr) == gs);

      wire [1:0] base = rr_pt[gs];
      wire [1:0] pick =
        rq[base]                ? base :
        rq[(base + 1) % NM]     ? 2'((base + 1) % NM) :
        rq[(base + 2) % NM]     ? 2'((base + 2) % NM) : 2'd0;

      wire       grant  = |rq;
      wire [1:0] cur    = busy[gs] ? g_id[gs] : pick;

      wire        cur_v  = (cur == 2'd0) ? m0_req.valid : (cur == 2'd1) ? m1_req.valid : m2_req.valid;
      wire        cur_wr = (cur == 2'd0) ? m0_req.write : (cur == 2'd1) ? m1_req.write : m2_req.write;
      wire [31:0] cur_ad = (cur == 2'd0) ? m0_req.addr  : (cur == 2'd1) ? m1_req.addr  : m2_req.addr;
      wire [31:0] cur_wd = (cur == 2'd0) ? m0_req.wdata : (cur == 2'd1) ? m1_req.wdata : m2_req.wdata;
      wire [3:0]  cur_ws = (cur == 2'd0) ? m0_req.wstrb : (cur == 2'd1) ? m1_req.wstrb : m2_req.wstrb;

      wire vld = busy[gs] ? ~s_rsp_v[gs] : (grant && cur_v);

      always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
          rr_pt[gs] <= 2'd0;
          busy[gs]  <= 1'b0;
          g_id[gs]  <= 2'd0;
        end else if (!busy[gs]) begin
          if (grant) begin
            busy[gs]  <= 1'b1;
            g_id[gs]  <= pick;
            rr_pt[gs] <= (pick == 2'd2) ? 2'd0 : (pick + 2'd1);
            if (dbg_i) $display("[XBAR] t=%0t grant s=%0d m=%0d addr=%08h wr=%b", $time, gs, pick,
                              cur_ad, cur_wr);
          end
        end else if (s_rsp_v[gs]) begin
          busy[gs] <= 1'b0;
          if (dbg_i) $display("[XBAR] t=%0t rel   s=%0d m=%0d", $time, gs, g_id[gs]);
        end
      end

      assign m_req_v[gs] = rq;
      if (gs == 0) begin : g_s0
        assign s0_req.valid = vld;  assign s0_req.write = cur_wr;
        assign s0_req.addr  = cur_ad; assign s0_req.wdata = cur_wd;
        assign s0_req.wstrb = cur_ws;
      end
      if (gs == 1) begin : g_s1
        assign s1_req.valid = vld;  assign s1_req.write = cur_wr;
        assign s1_req.addr  = cur_ad; assign s1_req.wdata = cur_wd;
        assign s1_req.wstrb = cur_ws;
      end
      if (gs == 2) begin : g_s2
        assign s2_req.valid = vld;  assign s2_req.write = cur_wr;
        assign s2_req.addr  = cur_ad; assign s2_req.wdata = cur_wd;
        assign s2_req.wstrb = cur_ws;
      end
      if (gs == 3) begin : g_s3
        assign s3_req.valid = vld;  assign s3_req.write = cur_wr;
        assign s3_req.addr  = cur_ad; assign s3_req.wdata = cur_wd;
        assign s3_req.wstrb = cur_ws;
      end
      if (gs == 4) begin : g_s4
        assign s4_req.valid = vld;  assign s4_req.write = cur_wr;
        assign s4_req.addr  = cur_ad; assign s4_req.wdata = cur_wd;
        assign s4_req.wstrb = cur_ws;
      end
      if (gs == 5) begin : g_s5
        assign s5_req.valid = vld;  assign s5_req.write = cur_wr;
        assign s5_req.addr  = cur_ad; assign s5_req.wdata = cur_wd;
        assign s5_req.wstrb = cur_ws;
      end
      if (gs == 6) begin : g_s6
        assign s6_req.valid = vld;  assign s6_req.write = cur_wr;
        assign s6_req.addr  = cur_ad; assign s6_req.wdata = cur_wd;
        assign s6_req.wstrb = cur_ws;
      end
      if (gs == 7) begin : g_s7
        assign s7_req.valid = vld;  assign s7_req.write = cur_wr;
        assign s7_req.addr  = cur_ad; assign s7_req.wdata = cur_wd;
        assign s7_req.wstrb = cur_ws;
      end
    end
  endgenerate

  always_comb begin
    m0_resp.valid = 1'b0; m0_resp.rdata = 32'd0; m0_resp.resp = 2'b00;
    m1_resp.valid = 1'b0; m1_resp.rdata = 32'd0; m1_resp.resp = 2'b00;
    m2_resp.valid = 1'b0; m2_resp.rdata = 32'd0; m2_resp.resp = 2'b00;
    if (busy[0] && s0_resp.valid) begin
      if (g_id[0] == 0) begin m0_resp = s0_resp; end
      else if (g_id[0] == 1) begin m1_resp = s0_resp; end
      else begin m2_resp = s0_resp; end
    end
    if (busy[1] && s1_resp.valid) begin
      if (g_id[1] == 0) begin m0_resp = s1_resp; end
      else if (g_id[1] == 1) begin m1_resp = s1_resp; end
      else begin m2_resp = s1_resp; end
    end
    if (busy[2] && s2_resp.valid) begin
      if (g_id[2] == 0) begin m0_resp = s2_resp; end
      else if (g_id[2] == 1) begin m1_resp = s2_resp; end
      else begin m2_resp = s2_resp; end
    end
    if (busy[3] && s3_resp.valid) begin
      if (g_id[3] == 0) begin m0_resp = s3_resp; end
      else if (g_id[3] == 1) begin m1_resp = s3_resp; end
      else begin m2_resp = s3_resp; end
    end
    if (busy[4] && s4_resp.valid) begin
      if (g_id[4] == 0) begin m0_resp = s4_resp; end
      else if (g_id[4] == 1) begin m1_resp = s4_resp; end
      else begin m2_resp = s4_resp; end
    end
    if (busy[5] && s5_resp.valid) begin
      if (g_id[5] == 0) begin m0_resp = s5_resp; end
      else if (g_id[5] == 1) begin m1_resp = s5_resp; end
      else begin m2_resp = s5_resp; end
    end
    if (busy[6] && s6_resp.valid) begin
      if (g_id[6] == 0) begin m0_resp = s6_resp; end
      else if (g_id[6] == 1) begin m1_resp = s6_resp; end
      else begin m2_resp = s6_resp; end
    end
    if (busy[7] && s7_resp.valid) begin
      if (g_id[7] == 0) begin m0_resp = s7_resp; end
      else if (g_id[7] == 1) begin m1_resp = s7_resp; end
      else begin m2_resp = s7_resp; end
    end
  end

endmodule
