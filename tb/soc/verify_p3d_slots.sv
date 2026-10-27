`ifndef _AMECHIP_PKG_SV
 `include "amechip_pkg.sv"
`endif
`ifndef _SOC_PKG_SV
 `include "soc_pkg.sv"
`endif

module amechip_cpu (
  input  logic              clk,
  input  logic              rst_n,
  output soc_pkg::soc_req_t bus_req,
  input  soc_pkg::soc_resp_t bus_resp,
  output logic              ame_req_valid,
  output logic [31:0]       ame_req_instr,
  output logic [31:0]       ame_req_rs1,
  output logic [31:0]       ame_req_rs2,
  input  logic              ame_req_ready,
  input  logic              ame_resp_valid,
  input  logic [31:0]       ame_resp_data,
  input  logic              ame_resp_err,
  input  logic              irq_i,
  output logic              cpu_wfi_o,
  output logic              buserr_evt_o
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

  wire cpu_halt;

  ame_cpu u_core (
    .clk_i (clk), .rst_ni(rst_n),
    .ax_aw_addr(ax_aw_addr), .ax_aw_valid(ax_aw_valid), .ax_aw_ready(ax_aw_ready),
    .ax_w_data(ax_w_data), .ax_w_strb(ax_w_strb),
    .ax_w_valid(ax_w_valid), .ax_w_ready(ax_w_ready),
    .ax_b_resp(ax_b_resp), .ax_b_valid(ax_b_valid), .ax_b_ready(ax_b_ready),
    .ax_ar_addr(ax_ar_addr), .ax_ar_valid(ax_ar_valid), .ax_ar_ready(ax_ar_ready),
    .ax_r_data(ax_r_data), .ax_r_resp(ax_r_resp),
    .ax_r_valid(ax_r_valid), .ax_r_ready(ax_r_ready),
    .ame_req_valid(ame_req_valid), .ame_req_instr(ame_req_instr),
    .ame_req_rs1(ame_req_rs1), .ame_req_rs2(ame_req_rs2),
    .ame_req_ready(ame_req_ready), .ame_resp_valid(ame_resp_valid),
    .ame_resp_data(ame_resp_data), .ame_resp_err(ame_resp_err),
    .irq_i(irq_i), .halt_o(cpu_halt), .wfi_o(cpu_wfi_o), .bus_err_o(buserr_evt_o),
    .trace_valid_o(), .trace_pc_o(), .trace_instr_o(), .trace_rd_o(),
    .trace_wdata_o(), .trace_flag_o()
  );

  typedef enum logic [2:0] {C_IDLE, C_W, C_B, C_R, C_RD} cst_e;
  cst_e        st;
  logic        aw_v, w_v, ar_v;
  logic [31:0] aw_a, w_d, ar_a;
  logic [3:0]  w_s;
  logic        b_v, r_v;
  logic [1:0]  b_r, r_r;
  logic [31:0] r_d;

  assign ax_aw_ready = (st == C_IDLE) && !aw_v;
  assign ax_w_ready  = (st == C_IDLE) && !w_v;
  assign ax_ar_ready = (st == C_IDLE) && !ar_v && !aw_v && !w_v;
  assign ax_b_valid  = b_v;
  assign ax_b_resp   = b_r;
  assign ax_r_valid  = r_v;
  assign ax_r_data   = r_d;
  assign ax_r_resp   = r_r;

  always_comb begin
    bus_req = '0;
    if (st == C_W) begin
      bus_req.valid = 1'b1;
      bus_req.write = 1'b1;
      bus_req.addr  = aw_a;
      bus_req.wdata = w_d;
      bus_req.wstrb = w_s;
    end else if (st == C_R) begin
      bus_req.valid = 1'b1;
      bus_req.write = 1'b0;
      bus_req.addr  = ar_a;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      st <= C_IDLE; aw_v <= 1'b0; w_v <= 1'b0; ar_v <= 1'b0;
      aw_a <= '0; w_d <= '0; w_s <= '0; ar_a <= '0;
      b_v <= 1'b0; b_r <= 2'b00; r_v <= 1'b0; r_d <= '0; r_r <= 2'b00;
    end else begin
      case (st)
        C_IDLE: begin
          if (ax_aw_valid && ax_aw_ready) begin aw_v <= 1'b1; aw_a <= ax_aw_addr; end
          if (ax_w_valid  && ax_w_ready)  begin w_v  <= 1'b1; w_d  <= ax_w_data; w_s <= ax_w_strb; end
          if (ax_ar_valid && ax_ar_ready) begin
            ar_v <= 1'b1; ar_a <= ax_ar_addr;
          end
          if ((aw_v || (ax_aw_valid && ax_aw_ready)) &&
              (w_v  || (ax_w_valid  && ax_w_ready))) begin
            aw_v <= 1'b0; w_v <= 1'b0;
            st   <= C_W;
          end else if (ar_v || (ax_ar_valid && ax_ar_ready)) begin
            ar_v <= 1'b0;
            st   <= C_R;
          end
        end
        C_W: if (bus_resp.valid) begin
          b_v  <= 1'b1;
          b_r  <= bus_resp.resp;
          st   <= C_B;
        end
        C_B: if (ax_b_ready) begin
          b_v <= 1'b0;
          st  <= C_IDLE;
        end
        C_R: if (bus_resp.valid) begin
          r_v  <= 1'b1;
          r_d  <= bus_resp.rdata;
          r_r  <= bus_resp.resp;
          st   <= C_RD;
        end
        C_RD: if (ax_r_ready) begin
          r_v <= 1'b0;
          st  <= C_IDLE;
        end
        default: st <= C_IDLE;
      endcase
    end
  end
endmodule

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
  wire dbg_mac_en, dbg_idle;

  ame_core u_core (
    .clk_i(clk), .rst_ni(rst_n),
    .cp_req_valid_i(req_valid), .cp_req_instr_i(req_instr),
    .cp_req_rs1_i(req_rs1), .cp_req_rs2_i(req_rs2),
    .cp_req_ready_o(req_ready), .cp_resp_valid_o(resp_valid),
    .cp_resp_data_o(resp_data), .cp_resp_err_o(resp_err),
    .bus_req_valid_i(win_req_valid), .bus_req_write_i(win_req_write),
    .bus_req_addr_i(win_req_addr), .bus_req_wdata_i(win_req_wdata),
    .bus_req_wstrb_i(win_req_wstrb), .bus_req_ready_o(win_req_ready),
    .bus_resp_valid_o(win_resp_valid), .bus_resp_rdata_o(win_resp_rdata),
    .bus_resp_err_o(win_resp_err),
    .irq_done_o(evt_done_o), .irq_err_o(evt_err_o),
    .dbg_mac_en_o(dbg_mac_en), .dbg_idle_o(dbg_idle)
  );

  assign busy_o = !dbg_idle;
endmodule

module p3d_axi_m_to_soc (
  input  logic clk,
  input  logic rst_n,
  input  logic        aw_valid, output logic aw_ready, input logic [31:0] aw_addr,
  input  logic        w_valid,  output logic w_ready,  input logic [31:0] w_data,
  input  logic [3:0]  w_strb,
  output logic        b_valid,  input  logic b_ready,  output logic [1:0] b_resp,
  input  logic        ar_valid, output logic ar_ready, input logic [31:0] ar_addr,
  output logic        r_valid,  input  logic r_ready,  output logic [31:0] r_data,
  output logic [1:0]  r_resp,
  output soc_pkg::soc_req_t  bus_req,
  input  soc_pkg::soc_resp_t bus_resp
);
  typedef enum logic [2:0] {A_IDLE, A_W, A_R, A_B, A_RD} ast_e;
  ast_e st;
  logic [31:0] a_q, d_q;
  logic [3:0]  s_q;
  logic        b_v, r_v;
  logic [1:0]  b_rr, r_rr;
  logic [31:0] r_dd;

  assign aw_ready = (st == A_IDLE);
  assign w_ready  = (st == A_IDLE);
  assign ar_ready = (st == A_IDLE);
  assign b_valid  = b_v;
  assign b_resp   = b_rr;
  assign r_valid  = r_v;
  assign r_data   = r_dd;
  assign r_resp   = r_rr;

  always_comb begin
    bus_req = '0;
    if (st == A_W) begin
      bus_req.valid = 1'b1; bus_req.write = 1'b1;
      bus_req.addr = a_q; bus_req.wdata = d_q; bus_req.wstrb = s_q;
    end else if (st == A_R) begin
      bus_req.valid = 1'b1; bus_req.write = 1'b0; bus_req.addr = a_q;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      st <= A_IDLE; a_q <= '0; d_q <= '0; s_q <= '0;
      b_v <= 1'b0; r_v <= 1'b0; b_rr <= 2'b00; r_rr <= 2'b00; r_dd <= '0;
    end else begin
      case (st)
        A_IDLE: begin
          if (aw_valid && w_valid) begin
            a_q <= aw_addr; d_q <= w_data; s_q <= w_strb; st <= A_W;
          end else if (ar_valid) begin
            a_q <= ar_addr; st <= A_R;
          end
        end
        A_W: if (bus_resp.valid) begin
          b_v <= 1'b1; b_rr <= bus_resp.resp; st <= A_B;
        end
        A_B: if (b_ready) begin b_v <= 1'b0; st <= A_IDLE; end
        A_R: if (bus_resp.valid) begin
          r_v <= 1'b1; r_dd <= bus_resp.rdata; r_rr <= bus_resp.resp; st <= A_RD;
        end
        A_RD: if (r_ready) begin r_v <= 1'b0; st <= A_IDLE; end
        default: st <= A_IDLE;
      endcase
    end
  end
endmodule

module p3d_soc_to_axi_s (
  input  logic clk,
  input  logic rst_n,
  input  soc_pkg::soc_req_t  bus_req,
  output soc_pkg::soc_resp_t bus_resp,
  output logic        aw_valid, input  logic aw_ready, output logic [31:0] aw_addr,
  output logic        w_valid,  input  logic w_ready,  output logic [31:0] w_data,
  output logic [3:0]  w_strb,
  input  logic        b_valid,  output logic b_ready,  input  logic [1:0] b_resp,
  output logic        ar_valid, input  logic ar_ready, output logic [31:0] ar_addr,
  input  logic        r_valid,  output logic r_ready,  input  logic [31:0] r_data,
  input  logic [1:0]  r_resp
);
  typedef enum logic [2:0] {S_IDLE, S_WA, S_WB, S_RA, S_RR, S_RSP} sst_e;
  sst_e st;
  logic [31:0] a_q, d_q;
  logic [3:0]  s_q;
  logic        aw_done, w_done;
  logic [31:0] r_dd;
  logic [1:0]  r_rr;

  assign aw_valid = (st == S_WA) && !aw_done;
  assign aw_addr  = a_q;
  assign w_valid  = (st == S_WA) && !w_done;
  assign w_data   = d_q;
  assign w_strb   = s_q;
  assign b_ready  = 1'b1;
  assign ar_valid = (st == S_RA);
  assign ar_addr  = a_q;
  assign r_ready  = 1'b1;

  always_comb begin
    bus_resp = '0;
    if (st == S_RSP) begin
      bus_resp.valid = 1'b1;
      bus_resp.rdata = r_dd;
      bus_resp.resp  = r_rr;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      st <= S_IDLE; a_q <= '0; d_q <= '0; s_q <= '0;
      aw_done <= 1'b0; w_done <= 1'b0; r_dd <= '0; r_rr <= 2'b00;
    end else begin
      case (st)
        S_IDLE: if (bus_req.valid) begin
          a_q <= bus_req.addr; d_q <= bus_req.wdata; s_q <= bus_req.wstrb;
          aw_done <= 1'b0; w_done <= 1'b0;
          st <= bus_req.write ? S_WA : S_RA;
        end
        S_WA: begin
          if (aw_valid && aw_ready) aw_done <= 1'b1;
          if (w_valid  && w_ready)  w_done  <= 1'b1;
          if ((aw_done || (aw_valid && aw_ready)) && (w_done || (w_valid && w_ready)))
            st <= S_WB;
        end
        S_WB: begin
          if (b_valid) begin
            r_rr <= b_resp;
            st   <= S_RSP;
          end
        end
        S_RA: if (ar_ready) st <= S_RR;
        S_RR: if (r_valid) begin
          r_dd <= r_data; r_rr <= r_resp; st <= S_RSP;
        end
        S_RSP: begin
          st <= S_IDLE;
        end
        default: st <= S_IDLE;
      endcase
    end
  end
endmodule

module p3d_axi_s_to_ame (
  input  logic clk,
  input  logic rst_n,
  input  logic        aw_valid, output logic aw_ready, input logic [31:0] aw_addr,
  input  logic        w_valid,  output logic w_ready,  input logic [31:0] w_data,
  input  logic [3:0]  w_strb,
  output logic        b_valid,  input  logic b_ready,  output logic [1:0] b_resp,
  input  logic        ar_valid, output logic ar_ready, input logic [31:0] ar_addr,
  output logic        r_valid,  input  logic r_ready,  output logic [31:0] r_data,
  output logic [1:0]  r_resp,
  output logic        win_req_valid,
  input  logic        win_req_ready,
  output logic        win_req_write,
  output logic [31:0] win_req_addr,
  output logic [31:0] win_req_wdata,
  output logic [3:0]  win_req_wstrb,
  input  logic        win_resp_valid,
  input  logic [31:0] win_resp_rdata,
  input  logic        win_resp_err
);
  typedef enum logic [2:0] {M_IDLE, M_WR, M_WAIT, M_B, M_RD, M_WR2, M_R} mst_e;
  mst_e st;
  logic [31:0] a_q, d_q;
  logic [3:0]  s_q;
  logic        is_wr;
  logic [31:0] rd_q;
  logic        err_q;
  logic        b_v, r_v;
  logic [1:0]  b_rr, r_rr;

  assign aw_ready = (st == M_IDLE);
  assign w_ready  = (st == M_IDLE);
  assign ar_ready = (st == M_IDLE);
  assign win_req_valid = (st == M_WR) || (st == M_RD);
  assign win_req_write = is_wr;
  assign win_req_addr  = a_q;
  assign win_req_wdata = d_q;
  assign win_req_wstrb = s_q;
  assign b_valid = b_v;
  assign b_resp  = b_rr;
  assign r_valid = r_v;
  assign r_data  = rd_q;
  assign r_resp  = r_rr;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      st <= M_IDLE; a_q <= '0; d_q <= '0; s_q <= '0; is_wr <= 1'b0;
      rd_q <= '0; err_q <= 1'b0; b_v <= 1'b0; r_v <= 1'b0;
      b_rr <= 2'b00; r_rr <= 2'b00;
    end else begin
      case (st)
        M_IDLE: begin
          if (aw_valid && w_valid) begin
            a_q <= aw_addr; d_q <= w_data; s_q <= w_strb; is_wr <= 1'b1;
            st <= M_WR;
          end else if (ar_valid) begin
            a_q <= ar_addr; d_q <= '0; s_q <= '0; is_wr <= 1'b0;
            st <= M_RD;
          end
        end
        M_WR: if (win_req_ready) begin
          st <= M_WAIT;
        end
        M_RD: if (win_req_ready) st <= M_WR2;
        M_WR2: if (win_resp_valid) begin
          rd_q <= win_resp_rdata;
          err_q <= win_resp_err;
          r_v  <= 1'b1;
          r_rr <= win_resp_err ? amechip_pkg::AXI_SLVERR : amechip_pkg::AXI_OKAY;
          st   <= M_R;
        end
        M_WAIT: if (win_resp_valid) begin
          b_v  <= 1'b1;
          b_rr <= win_resp_err ? amechip_pkg::AXI_SLVERR : amechip_pkg::AXI_OKAY;
          st   <= M_B;
        end
        M_B: if (b_ready) begin b_v <= 1'b0; st <= M_IDLE; end
        M_R: if (r_ready) begin r_v <= 1'b0; st <= M_IDLE; end
        default: st <= M_IDLE;
      endcase
    end
  end
endmodule

module amechip_mem (
  input  logic clk,
  input  logic rst_n,
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
  output logic        win_req_valid,
  input  logic        win_req_ready,
  output logic        win_req_write,
  output logic [31:0] win_req_addr,
  output logic [31:0] win_req_wdata,
  output logic [3:0]  win_req_wstrb,
  input  logic        win_resp_valid,
  input  logic [31:0] win_resp_rdata,
  input  logic        win_resp_err,
  output logic          xmem_clk_o,
  output logic [22:0]   xmem_a_o,
  input  logic [15:0]   xmem_di_i,
  output logic [15:0]   xmem_do_o,
  output logic          xmem_ce_no,
  output logic          xmem_oe_no,
  output logic          xmem_we_no,
  input  logic          xmem_wait_i,
  output logic        dma_busy_o,
  output logic        dma_done_evt_o,
  output logic        dma_err_evt_o,
  output logic        kv_busy_o,
  output logic        kv_done_evt_o,
  output logic        kv_err_evt_o
);

  logic        c_aw_valid, c_aw_ready, c_w_valid, c_w_ready, c_b_valid, c_b_ready;
  logic [31:0] c_aw_addr, c_ar_addr, c_w_data, c_r_data;
  logic [3:0]  c_w_strb;
  logic [1:0]  c_b_resp, c_r_resp;
  logic        c_ar_valid, c_ar_ready, c_r_valid, c_r_ready;

  logic        sy_aw_valid, sy_aw_ready, sy_w_valid, sy_w_ready, sy_b_valid, sy_b_ready;
  logic [31:0] sy_aw_addr, sy_ar_addr, sy_w_data, sy_r_data;
  logic [3:0]  sy_w_strb;
  logic [1:0]  sy_b_resp, sy_r_resp;
  logic        sy_ar_valid, sy_ar_ready, sy_r_valid, sy_r_ready;
  logic        in_aw_valid, in_aw_ready, in_w_valid, in_w_ready, in_b_valid, in_b_ready;
  logic [31:0] in_aw_addr, in_ar_addr, in_w_data, in_r_data;
  logic [3:0]  in_w_strb;
  logic [1:0]  in_b_resp, in_r_resp;
  logic        in_ar_valid, in_ar_ready, in_r_valid, in_r_ready;
  logic        ua_aw_valid, ua_aw_ready, ua_w_valid, ua_w_ready, ua_b_valid, ua_b_ready;
  logic [31:0] ua_aw_addr, ua_ar_addr, ua_w_data, ua_r_data;
  logic [3:0]  ua_w_strb;
  logic [1:0]  ua_b_resp, ua_r_resp;
  logic        ua_ar_valid, ua_ar_ready, ua_r_valid, ua_r_ready;
  logic        am_aw_valid, am_aw_ready, am_w_valid, am_w_ready, am_b_valid, am_b_ready;
  logic [31:0] am_aw_addr, am_ar_addr, am_w_data, am_r_data;
  logic [3:0]  am_w_strb;
  logic [1:0]  am_b_resp, am_r_resp;
  logic        am_ar_valid, am_ar_ready, am_r_valid, am_r_ready;

  logic kv_done_evt, kv_err_evt;

  mem_ss_top #(
    .OC_SRAM_KB  (4),
    .BOOT_ROM_KB (2),
    .BOOT_INIT   ("p3d_boot.hex"),
    .KV_BACKEND_B(1'b0),
    .KV_CTX      (256),
    .DMA_FIFO    (8),
    .XMEM_WS     (0)
  ) u_mem_ss (
    .clk_i(clk), .rst_ni(rst_n),
    .cpu_aw_valid_i(c_aw_valid), .cpu_aw_ready_o(c_aw_ready), .cpu_aw_addr_i(c_aw_addr),
    .cpu_w_valid_i(c_w_valid), .cpu_w_ready_o(c_w_ready), .cpu_w_data_i(c_w_data),
    .cpu_w_strb_i(c_w_strb), .cpu_b_valid_o(c_b_valid), .cpu_b_ready_i(c_b_ready),
    .cpu_b_resp_o(c_b_resp), .cpu_ar_valid_i(c_ar_valid), .cpu_ar_ready_o(c_ar_ready),
    .cpu_ar_addr_i(c_ar_addr), .cpu_r_valid_o(c_r_valid), .cpu_r_ready_i(c_r_ready),
    .cpu_r_data_o(c_r_data), .cpu_r_resp_o(c_r_resp),
    .sys_aw_valid_o(sy_aw_valid), .sys_aw_ready_i(sy_aw_ready), .sys_aw_addr_o(sy_aw_addr),
    .sys_w_valid_o(sy_w_valid), .sys_w_ready_i(sy_w_ready), .sys_w_data_o(sy_w_data),
    .sys_w_strb_o(sy_w_strb), .sys_b_valid_i(sy_b_valid), .sys_b_ready_o(sy_b_ready),
    .sys_b_resp_i(sy_b_resp), .sys_ar_valid_o(sy_ar_valid), .sys_ar_ready_i(sy_ar_ready),
    .sys_ar_addr_o(sy_ar_addr), .sys_r_valid_i(sy_r_valid), .sys_r_ready_o(sy_r_ready),
    .sys_r_data_i(sy_r_data), .sys_r_resp_i(sy_r_resp),
    .intc_aw_valid_o(in_aw_valid), .intc_aw_ready_i(in_aw_ready), .intc_aw_addr_o(in_aw_addr),
    .intc_w_valid_o(in_w_valid), .intc_w_ready_i(in_w_ready), .intc_w_data_o(in_w_data),
    .intc_w_strb_o(in_w_strb), .intc_b_valid_i(in_b_valid), .intc_b_ready_o(in_b_ready),
    .intc_b_resp_i(in_b_resp), .intc_ar_valid_o(in_ar_valid), .intc_ar_ready_i(in_ar_ready),
    .intc_ar_addr_o(in_ar_addr), .intc_r_valid_i(in_r_valid), .intc_r_ready_o(in_r_ready),
    .intc_r_data_i(in_r_data), .intc_r_resp_i(in_r_resp),
    .uart_aw_valid_o(ua_aw_valid), .uart_aw_ready_i(ua_aw_ready), .uart_aw_addr_o(ua_aw_addr),
    .uart_w_valid_o(ua_w_valid), .uart_w_ready_i(ua_w_ready), .uart_w_data_o(ua_w_data),
    .uart_w_strb_o(ua_w_strb), .uart_b_valid_i(ua_b_valid), .uart_b_ready_o(ua_b_ready),
    .uart_b_resp_i(ua_b_resp), .uart_ar_valid_o(ua_ar_valid), .uart_ar_ready_i(ua_ar_ready),
    .uart_ar_addr_o(ua_ar_addr), .uart_r_valid_i(ua_r_valid), .uart_r_ready_o(ua_r_ready),
    .uart_r_data_i(ua_r_data), .uart_r_resp_i(ua_r_resp),
    .ame_aw_valid_o(am_aw_valid), .ame_aw_ready_i(am_aw_ready), .ame_aw_addr_o(am_aw_addr),
    .ame_w_valid_o(am_w_valid), .ame_w_ready_i(am_w_ready), .ame_w_data_o(am_w_data),
    .ame_w_strb_o(am_w_strb), .ame_b_valid_i(am_b_valid), .ame_b_ready_o(am_b_ready),
    .ame_b_resp_i(am_b_resp), .ame_ar_valid_o(am_ar_valid), .ame_ar_ready_i(am_ar_ready),
    .ame_ar_addr_o(am_ar_addr), .ame_r_valid_i(am_r_valid), .ame_r_ready_o(am_r_ready),
    .ame_r_data_i(am_r_data), .ame_r_resp_i(am_r_resp),
    .xmem_clk_o(xmem_clk_o), .xmem_a_o(xmem_a_o), .xmem_di_i(xmem_di_i),
    .xmem_do_o(xmem_do_o), .xmem_ce_no(xmem_ce_no), .xmem_oe_no(xmem_oe_no),
    .xmem_we_no(xmem_we_no), .xmem_wait_i(xmem_wait_i),
    .irq_dma_done_o(dma_done_evt_o), .irq_dma_err_o(dma_err_evt_o),
    .irq_kv_done_o(kv_done_evt_o), .irq_kv_err_o(kv_err_evt_o)
  );

  p3d_soc_to_axi_s u_cpu_bridge (
    .clk(clk), .rst_n(rst_n),
    .bus_req(m0_req), .bus_resp(m0_resp),
    .aw_valid(c_aw_valid), .aw_ready(c_aw_ready), .aw_addr(c_aw_addr),
    .w_valid(c_w_valid), .w_ready(c_w_ready), .w_data(c_w_data), .w_strb(c_w_strb),
    .b_valid(c_b_valid), .b_ready(c_b_ready), .b_resp(c_b_resp),
    .ar_valid(c_ar_valid), .ar_ready(c_ar_ready), .ar_addr(c_ar_addr),
    .r_valid(c_r_valid), .r_ready(c_r_ready), .r_data(c_r_data), .r_resp(c_r_resp)
  );

  p3d_axi_m_to_soc u_sys_bridge (
    .clk(clk), .rst_n(rst_n),
    .aw_valid(sy_aw_valid), .aw_ready(sy_aw_ready), .aw_addr(sy_aw_addr),
    .w_valid(sy_w_valid), .w_ready(sy_w_ready), .w_data(sy_w_data), .w_strb(sy_w_strb),
    .b_valid(sy_b_valid), .b_ready(sy_b_ready), .b_resp(sy_b_resp),
    .ar_valid(sy_ar_valid), .ar_ready(sy_ar_ready), .ar_addr(sy_ar_addr),
    .r_valid(sy_r_valid), .r_ready(sy_r_ready), .r_data(sy_r_data), .r_resp(sy_r_resp),
    .bus_req(s2_req), .bus_resp(s2_resp)
  );
  p3d_axi_m_to_soc u_intc_bridge (
    .clk(clk), .rst_n(rst_n),
    .aw_valid(in_aw_valid), .aw_ready(in_aw_ready), .aw_addr(in_aw_addr),
    .w_valid(in_w_valid), .w_ready(in_w_ready), .w_data(in_w_data), .w_strb(in_w_strb),
    .b_valid(in_b_valid), .b_ready(in_b_ready), .b_resp(in_b_resp),
    .ar_valid(in_ar_valid), .ar_ready(in_ar_ready), .ar_addr(in_ar_addr),
    .r_valid(in_r_valid), .r_ready(in_r_ready), .r_data(in_r_data), .r_resp(in_r_resp),
    .bus_req(s3_req), .bus_resp(s3_resp)
  );
  p3d_axi_m_to_soc u_uart_bridge (
    .clk(clk), .rst_n(rst_n),
    .aw_valid(ua_aw_valid), .aw_ready(ua_aw_ready), .aw_addr(ua_aw_addr),
    .w_valid(ua_w_valid), .w_ready(ua_w_ready), .w_data(ua_w_data), .w_strb(ua_w_strb),
    .b_valid(ua_b_valid), .b_ready(ua_b_ready), .b_resp(ua_b_resp),
    .ar_valid(ua_ar_valid), .ar_ready(ua_ar_ready), .ar_addr(ua_ar_addr),
    .r_valid(ua_r_valid), .r_ready(ua_r_ready), .r_data(ua_r_data), .r_resp(ua_r_resp),
    .bus_req(s4_req), .bus_resp(s4_resp)
  );
  p3d_axi_s_to_ame u_ame_bridge (
    .clk(clk), .rst_n(rst_n),
    .aw_valid(am_aw_valid), .aw_ready(am_aw_ready), .aw_addr(am_aw_addr),
    .w_valid(am_w_valid), .w_ready(am_w_ready), .w_data(am_w_data), .w_strb(am_w_strb),
    .b_valid(am_b_valid), .b_ready(am_b_ready), .b_resp(am_b_resp),
    .ar_valid(am_ar_valid), .ar_ready(am_ar_ready), .ar_addr(am_ar_addr),
    .r_valid(am_r_valid), .r_ready(am_r_ready), .r_data(am_r_data), .r_resp(am_r_resp),
    .win_req_valid(win_req_valid), .win_req_ready(win_req_ready),
    .win_req_write(win_req_write), .win_req_addr(win_req_addr),
    .win_req_wdata(win_req_wdata), .win_req_wstrb(win_req_wstrb),
    .win_resp_valid(win_resp_valid), .win_resp_rdata(win_resp_rdata),
    .win_resp_err(win_resp_err)
  );

  assign s1_req = '0;
  wire _unused_s1 = ^s1_resp.valid;

  assign dma_busy_o = u_mem_ss.u_dma.busy_q;
  assign kv_busy_o  = u_mem_ss.u_kvc.busy_q;
endmodule
