`ifndef _AMECHIP_PKG_SV
 `include "amechip_pkg.sv"
`endif

module ame_ctrl #(
  parameter int unsigned AME_M      = amechip_pkg::AME_M_DEF,
  parameter int unsigned AME_N      = amechip_pkg::AME_N_DEF,
  parameter int unsigned WBUF_DEPTH = amechip_pkg::WBUF_TILES * amechip_pkg::AME_M_DEF * amechip_pkg::AME_N_DEF,
  parameter int unsigned XBUF_DEPTH = amechip_pkg::XBUF_DEPTH
) (
  input logic clk_i,
  input logic rst_ni,

  input  logic        cp_req_valid_i,
  input  logic [31:0] cp_req_instr_i,
  input  logic [31:0] cp_req_rs1_i,
  input  logic [31:0] cp_req_rs2_i,
  output logic        cp_req_ready_o,
  output logic        cp_resp_valid_o,
  output logic [31:0] cp_resp_data_o,
  output logic        cp_resp_err_o,

  output logic               tld_en_o,
  output logic               tld_sel_o,
  output logic [5:0]         tld_n_o,
  output logic               xld_en_o,
  output logic               xld_sel_o,
  output logic               mac_sel_o,
  output logic [5:0]         mac_k_o,
  output logic               mac_en_o,
  output logic               mac_acc_o,   // 累加相(mac_en_o 延迟 1 拍)
  output logic [5:0]         mac_n_eff_o,
  output logic               y_clr_o,
  input  logic [32*amechip_pkg::RQ_ENTRIES-1:0] y_val_i, // 通道 n 在 [32n+:32](扁平,iverilog 兼容)

  output logic [WBUF_AW-1:0] wrow_addr_o,
  output logic [XBUF_AW-1:0] xrow_addr_o,
  input  logic               row_w_stall_i, // WBUF 读口本拍被总线读占用 → 装载顺延
  input  logic               row_x_stall_i,

  output logic        rq_we_o,
  output logic [4:0]  rq_waddr_o,
  output logic [31:0] rq_wm_o,
  output logic [5:0]  rq_ws_o,
  output logic        rq_wround_o,

  output logic [4:0]  rq_ra_idx_o,
  input  logic [31:0] rq_ra_m_i,
  input  logic [5:0]  rq_ra_s_i,
  input  logic        rq_ra_round_i,

  input  logic       bus_err_i,        // 总线窗口非法访问 → sticky ERR
  input  logic       evclear_done_i,
  input  logic       evclear_err_i,
  input  logic       irqen_we_i,
  input  logic [1:0] irqen_wdata_i,
  output logic [1:0] irqen_o,          // 读回(STATUS 窗口 CSR)
  output logic       irq_done_o,       // 电平 = IRQEN[0] & DONE(INTC 边沿锁存)
  output logic       irq_err_o,

  output logic       st_busy_o,        // STATUS[0]:阵列 exe 在跑
  output logic       st_done_o,        // STATUS[1]
  output logic       st_err_o,         // STATUS[7]
  output logic [3:0] st_rdy_o,         // STATUS[5:2] = {X1,X0,W1,W0}
  output logic       idle_o
);

  localparam int unsigned WBUF_AW    = $clog2(WBUF_DEPTH);
  localparam int unsigned XBUF_AW    = $clog2(XBUF_DEPTH);
  localparam int unsigned TILE_BYTES = AME_M * AME_N;
  localparam logic [5:0]  AME_M_C    = 6'(AME_M);
  localparam logic [5:0]  AME_N_C    = 6'(AME_N);

  localparam logic [1:0] PH_SETUP = 2'd0, PH_RUN = 2'd1, PH_DRAIN = 2'd2;

  logic [5:0] cfg_n_eff_q, cfg_kt_q;

  amechip_pkg::ame_tset_e tset_q [2];
  amechip_pkg::ame_tset_e xset_q [2];

  logic               wld_active_q;
  logic               wld_sel_q;
  logic [5:0]         wld_n_q;
  logic [WBUF_AW-1:0] wld_base_q;

  logic               xld_active_q;
  logic               xld_sel_q;
  logic [XBUF_AW-1:0] xld_off_q;

  logic       mac_busy_q;
  logic       mac_sel_q;
  logic [5:0] mac_k_q;
  logic [1:0] mac_phase_q;
  logic       mac_acc_q;

  logic        resp_v1_q, stq1_q, stq2_q, resp_v2_q;
  logic [31:0] resp_data_q;
  logic        resp_err_q;
  logic        stq_pend_q;

  logic       done_q, err_q;
  logic [1:0] irqen_q;

  logic [2:0]             f3;
  logic [6:0]             f7;
  amechip_pkg::ame_op_e   op;
  logic [4:0]             rd_f;

  logic [4:0]  cfg_n_c;
  logic [5:0]  cfg_kt_c;
  logic [1:0]  cfg_rsv_c;

  logic [1:0]  w_region_c;
  logic        w_sel_c;
  logic [28:0] w_rsv_c;
  logic [WBUF_AW-1:0] w_base_c;

  logic [8:0]  x_off_c;
  logic        x_sel_c;
  logic [21:0] x_rsv_c;

  logic        e_tsel_c;
  logic        e_isf_c;
  logic [30:0] e_rsv_c;

  logic [4:0]  st_idx_c;
  logic [26:0] st_rsv_c;

  logic [5:0]  q_s_c;
  logic        q_round_c;
  logic [24:0] q_rsv_c;
  logic [4:0]  q_n_c;

  always_comb begin
    f3   = cp_req_instr_i[14:12];
    f7   = cp_req_instr_i[31:25];
    op   = amechip_pkg::ame_op_e'(f3);
    rd_f = cp_req_instr_i[11:7];

    cfg_n_c   = cp_req_instr_i[24:20];
    cfg_kt_c  = {1'b0, cp_req_instr_i[29:25]};
    cfg_rsv_c = cp_req_instr_i[31:30];

    w_region_c = cp_req_rs1_i[1:0];
    w_sel_c    = cp_req_rs1_i[2];
    w_rsv_c    = cp_req_rs1_i[31:3];
    w_base_c   = WBUF_AW'((w_region_c * TILE_BYTES) % WBUF_DEPTH); // region 回卷(§3.3)

    x_off_c = cp_req_rs1_i[amechip_pkg::LDX_OFF_W-1:0];
    x_sel_c = cp_req_rs1_i[9];
    x_rsv_c = cp_req_rs1_i[31:10];

    e_tsel_c = cp_req_rs1_i[amechip_pkg::EXE_TSEL_OFF];
    e_isf_c  = (f7 == amechip_pkg::AME_F7_EXEF);
    e_rsv_c  = cp_req_rs1_i[31:1];

    st_idx_c = cp_req_rs1_i[amechip_pkg::ST_IDX_W-1:0];
    st_rsv_c = cp_req_rs1_i[31:5];

    q_s_c     = cp_req_rs2_i[amechip_pkg::QCFG_S_W-1:0];
    q_round_c = cp_req_rs2_i[amechip_pkg::QCFG_ROUND_OFF];
    q_rsv_c   = cp_req_rs2_i[31:7];
    q_n_c     = rd_f;
  end

  logic idle_c;
  assign idle_c = !mac_busy_q && !wld_active_q && !xld_active_q;
  assign idle_o = idle_c;

  logic        f7_ok_c;
  logic        grp_w_ok_c, grp_x_ok_c, grp_e_ok_c;
  logic        op_err_c, op_ready_c;
  logic [31:0] op_data_c;
  logic        accept_c;
  logic [7:0]  stq_q8;

  always_comb begin
    unique case (op)
      amechip_pkg::AME_OP_CFG : f7_ok_c = 1'b1; // I-type:f7 即 imm 域
      amechip_pkg::AME_OP_QCFG: f7_ok_c = (f7 == amechip_pkg::AME_F7_QCFG);
      amechip_pkg::AME_OP_LDW : f7_ok_c = (f7 == amechip_pkg::AME_F7_LDW);
      amechip_pkg::AME_OP_LDX : f7_ok_c = (f7 == amechip_pkg::AME_F7_LDX);
      amechip_pkg::AME_OP_EXE : f7_ok_c = (f7 == amechip_pkg::AME_F7_EXE) ||
                                          (f7 == amechip_pkg::AME_F7_EXEF);
      amechip_pkg::AME_OP_STY : f7_ok_c = (f7 == amechip_pkg::AME_F7_STY);
      amechip_pkg::AME_OP_STQ : f7_ok_c = (f7 == amechip_pkg::AME_F7_STQ);
      amechip_pkg::AME_OP_SYNC: f7_ok_c = (f7 == amechip_pkg::AME_F7_SYNC);
      default                 : f7_ok_c = 1'b0;
    endcase
  end

  assign grp_w_ok_c = (tset_q[w_sel_c] == amechip_pkg::AME_TSET_EMPTY) ||
                      (tset_q[w_sel_c] == amechip_pkg::AME_TSET_READY);
  assign grp_x_ok_c = (xset_q[x_sel_c] == amechip_pkg::AME_TSET_EMPTY) ||
                      (xset_q[x_sel_c] == amechip_pkg::AME_TSET_READY);
  assign grp_e_ok_c = (tset_q[e_tsel_c] == amechip_pkg::AME_TSET_READY) &&
                      (xset_q[e_tsel_c] == amechip_pkg::AME_TSET_READY);

  always_comb begin
    unique case (op)
      amechip_pkg::AME_OP_CFG:
        op_err_c = (cfg_rsv_c != 2'b00) || (cfg_n_c == 5'd0) || ({1'b0, cfg_n_c} > AME_N_C) ||
                   (cfg_kt_c == 6'd0) || (cfg_kt_c > AME_M_C);
      amechip_pkg::AME_OP_QCFG:
        op_err_c = !f7_ok_c || (q_rsv_c != 25'd0) || (q_s_c == 6'd0) || ({1'b0, q_n_c} >= AME_N_C);
      amechip_pkg::AME_OP_LDW:
        op_err_c = !f7_ok_c || (w_rsv_c != 29'd0);
      amechip_pkg::AME_OP_LDX:
        op_err_c = !f7_ok_c || (x_rsv_c != 22'd0);
      amechip_pkg::AME_OP_EXE:
        op_err_c = !f7_ok_c || (e_rsv_c != 31'd0) ||
                   (cfg_n_eff_q == 6'd0) || (cfg_kt_q == 6'd0);
      amechip_pkg::AME_OP_STY, amechip_pkg::AME_OP_STQ:
        op_err_c = !f7_ok_c || (st_rsv_c != 27'd0) || ({1'b0, st_idx_c} >= AME_N_C);
      amechip_pkg::AME_OP_SYNC:
        op_err_c = !f7_ok_c;
      default:
        op_err_c = 1'b1; // 合法编码之外(CPU 本应 trap,防御性按 ERR 接受)
    endcase

    if (op_err_c) begin
      op_ready_c = !stq_pend_q;
    end else begin
      unique case (op)
        amechip_pkg::AME_OP_CFG, amechip_pkg::AME_OP_QCFG,
        amechip_pkg::AME_OP_STY, amechip_pkg::AME_OP_STQ,
        amechip_pkg::AME_OP_SYNC:
          op_ready_c = idle_c && !stq_pend_q;
        amechip_pkg::AME_OP_LDW: op_ready_c = grp_w_ok_c && !wld_active_q && !stq_pend_q;
        amechip_pkg::AME_OP_LDX: op_ready_c = grp_x_ok_c && !xld_active_q && !stq_pend_q;
        amechip_pkg::AME_OP_EXE: op_ready_c = idle_c && grp_e_ok_c && !stq_pend_q;
        default:                 op_ready_c = !stq_pend_q; // 未知编码:防御性消费
      endcase
    end

    unique case (op)
      amechip_pkg::AME_OP_STY:
        op_data_c = op_err_c ? 32'd0 : y_val_i[32*st_idx_c +: 32];
      default:                 op_data_c = 32'd0; // st.q 数据由流水第 2 拍捕获
    endcase
  end

  assign accept_c       = cp_req_valid_i && op_ready_c;
  assign cp_req_ready_o = op_ready_c;
  wire stq_acc_c = accept_c && (op == amechip_pkg::AME_OP_STQ) && !op_err_c;

  assign rq_ra_idx_o = st_idx_c;
  ame_requant u_rq_stq (
    .clk_i (clk_i),
    .y_i   (y_val_i[32*st_idx_c +: 32]),
    .m_i   (rq_ra_m_i),
    .s_i   (rq_ra_s_i),
    .rnd_i (rq_ra_round_i),
    .q_o   (stq_q8)
  );

  logic wld_row_go, xld_row_go;
  assign wld_row_go = wld_active_q && !row_w_stall_i && (wld_n_q < cfg_n_eff_q);
  assign xld_row_go = xld_active_q && !row_x_stall_i;

  assign wrow_addr_o = wld_active_q
                     ? (wld_base_q + WBUF_AW'(wld_n_q * cfg_kt_q))
                     : '0;
  assign xrow_addr_o = xld_off_q;

  assign tld_en_o  = wld_row_go;
  assign tld_sel_o = wld_sel_q;
  assign tld_n_o   = wld_n_q;
  assign xld_en_o  = xld_row_go;
  assign xld_sel_o = xld_sel_q;

  logic wld_done_c;
  assign wld_done_c = wld_active_q && ((cfg_n_eff_q == 6'd0) ||
                      (wld_row_go && (wld_n_q == cfg_n_eff_q - 6'd1)));

  logic done_set_c;
  assign done_set_c = mac_busy_q && (mac_phase_q == PH_DRAIN);

  assign mac_sel_o   = mac_sel_q;
  assign mac_k_o     = mac_k_q;
  assign mac_en_o    = mac_busy_q && (mac_phase_q == PH_RUN);
  assign mac_acc_o   = mac_acc_q;      // mac_en 延迟 1 拍;末乘积在 DRAIN 相累加
  assign mac_n_eff_o = cfg_n_eff_q;    // exe 期间 cfg 被反压锁定,实况读安全
  assign y_clr_o   = accept_c && (op == amechip_pkg::AME_OP_EXE) && e_isf_c && !op_err_c;

  assign rq_we_o     = accept_c && (op == amechip_pkg::AME_OP_QCFG) && !op_err_c;
  assign rq_waddr_o  = q_n_c;
  assign rq_wm_o     = cp_req_rs1_i;
  assign rq_ws_o     = q_s_c;
  assign rq_wround_o = q_round_c;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      cfg_n_eff_q  <= 6'd0;
      cfg_kt_q     <= 6'd0;
      tset_q[0]    <= amechip_pkg::AME_TSET_EMPTY;
      tset_q[1]    <= amechip_pkg::AME_TSET_EMPTY;
      xset_q[0]    <= amechip_pkg::AME_TSET_EMPTY;
      xset_q[1]    <= amechip_pkg::AME_TSET_EMPTY;
      wld_active_q <= 1'b0;
      wld_sel_q    <= 1'b0;
      wld_n_q      <= 6'd0;
      wld_base_q   <= '0;
      xld_active_q <= 1'b0;
      xld_sel_q    <= 1'b0;
      xld_off_q    <= '0;
      mac_busy_q   <= 1'b0;
      mac_sel_q    <= 1'b0;
      mac_k_q      <= 6'd0;
      mac_phase_q  <= PH_SETUP;
      mac_acc_q    <= 1'b0;
      resp_v1_q    <= 1'b0;
      stq1_q       <= 1'b0;
      stq2_q       <= 1'b0;
      resp_v2_q    <= 1'b0;
      resp_data_q  <= 32'd0;
      resp_err_q   <= 1'b0;
      stq_pend_q   <= 1'b0;
      done_q       <= 1'b0;
      err_q        <= 1'b0;
      irqen_q      <= 2'b00;
    end else begin
      if (wld_done_c) begin
        tset_q[wld_sel_q] <= amechip_pkg::AME_TSET_READY;
        wld_active_q      <= 1'b0;
      end else if (wld_row_go) begin
        wld_n_q <= wld_n_q + 6'd1;
      end

      if (xld_row_go) begin
        xset_q[xld_sel_q] <= amechip_pkg::AME_TSET_READY;
        xld_active_q      <= 1'b0;
      end

      mac_acc_q <= mac_busy_q && (mac_phase_q == PH_RUN);
      if (mac_busy_q) begin
        unique case (mac_phase_q)
          PH_SETUP: begin
            mac_phase_q <= PH_RUN;
            mac_k_q     <= 6'd0;
          end
          PH_RUN: begin
            if (mac_k_q == cfg_kt_q - 6'd1) begin
              mac_phase_q <= PH_DRAIN;
            end else begin
              mac_k_q <= mac_k_q + 6'd1;
            end
          end
          default: begin // PH_DRAIN:末乘积本拍经 mac_acc_q 累加;BUSY 1→0
            mac_busy_q        <= 1'b0;
            tset_q[mac_sel_q] <= amechip_pkg::AME_TSET_EMPTY;
            xset_q[mac_sel_q] <= amechip_pkg::AME_TSET_EMPTY;
          end
        endcase
      end

      if (evclear_done_i) done_q <= 1'b0;
      else if (done_set_c) done_q <= 1'b1;

      if (evclear_err_i) err_q <= 1'b0;
      else if (bus_err_i || (accept_c && op_err_c)) err_q <= 1'b1;

      if (irqen_we_i) irqen_q <= irqen_wdata_i;

      resp_v1_q  <= accept_c && !stq_acc_c;
      stq1_q     <= stq_acc_c;
      stq2_q     <= stq1_q;
      resp_v2_q  <= stq2_q;
      stq_pend_q <= stq1_q || stq2_q;
      if (accept_c) begin
        resp_data_q <= op_data_c;      // st.y=INT32,其余 0(st.q 占位)
        resp_err_q  <= op_err_c;
      end else if (stq2_q) begin
        resp_data_q <= {{24{stq_q8[7]}}, stq_q8};  // requant 第 3 拍结果
      end

      if (accept_c) begin
        unique case (op)
          amechip_pkg::AME_OP_CFG: begin
            if (!op_err_c) begin
              cfg_n_eff_q <= {1'b0, cfg_n_c};
              cfg_kt_q    <= cfg_kt_c;
            end
          end
          amechip_pkg::AME_OP_LDW: begin
            if (!op_err_c) begin
              tset_q[w_sel_c] <= amechip_pkg::AME_TSET_LOADING;
              wld_active_q    <= 1'b1;
              wld_sel_q       <= w_sel_c;
              wld_n_q         <= 6'd0;
              wld_base_q      <= w_base_c;
            end
          end
          amechip_pkg::AME_OP_LDX: begin
            if (!op_err_c) begin
              xset_q[x_sel_c] <= amechip_pkg::AME_TSET_LOADING;
              xld_active_q    <= 1'b1;
              xld_sel_q       <= x_sel_c;
              xld_off_q       <= XBUF_AW'(x_off_c);
            end
          end
          amechip_pkg::AME_OP_EXE: begin
            if (!op_err_c) begin
              mac_busy_q       <= 1'b1;
              mac_phase_q      <= PH_SETUP;
              mac_sel_q        <= e_tsel_c;
              tset_q[e_tsel_c] <= amechip_pkg::AME_TSET_RUNNING;
              xset_q[e_tsel_c] <= amechip_pkg::AME_TSET_RUNNING;
            end
          end
          default: ; // QCFG/ST*/SYNC:动作由组合写口与 resp 数据覆盖
        endcase
      end
    end
  end

  assign cp_resp_valid_o = resp_v1_q || resp_v2_q;
  assign cp_resp_data_o  = resp_data_q;
  assign cp_resp_err_o   = resp_err_q;

  assign st_busy_o = mac_busy_q;
  assign st_done_o = done_q;
  assign st_err_o  = err_q;
  assign st_rdy_o  = {(xset_q[1] == amechip_pkg::AME_TSET_READY),
                      (xset_q[0] == amechip_pkg::AME_TSET_READY),
                      (tset_q[1] == amechip_pkg::AME_TSET_READY),
                      (tset_q[0] == amechip_pkg::AME_TSET_READY)};

  assign irq_done_o = irqen_q[0] && done_q;
  assign irq_err_o  = irqen_q[1] && err_q;
  assign irqen_o    = irqen_q;

endmodule
