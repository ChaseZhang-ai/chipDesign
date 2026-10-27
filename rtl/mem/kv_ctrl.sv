`ifndef _AMECHIP_PKG_SV
 `include "amechip_pkg.sv"
`endif

module kv_ctrl #(
  parameter int unsigned CTX_MAX      = amechip_pkg::KV_CTX_MAX,
  parameter int unsigned BANKS        = amechip_pkg::KV_BANKS_DEF,
  parameter int unsigned BPAW         = amechip_pkg::KV_BANK_AW,
  parameter bit          KV_BACKEND_B = 1'b0 // 1=片上 bank 后端(bp 不占总线)
) (
  input  logic clk_i,
  input  logic rst_ni,

  input  logic        csr_aw_valid_i,
  output logic        csr_aw_ready_o,
  input  logic [31:0] csr_aw_addr_i,
  input  logic        csr_w_valid_i,
  output logic        csr_w_ready_o,
  input  logic [31:0] csr_w_data_i,
  input  logic [3:0]  csr_w_strb_i,
  output logic        csr_b_valid_o,
  input  logic        csr_b_ready_i,
  output logic [1:0]  csr_b_resp_o,
  input  logic        csr_ar_valid_i,
  output logic        csr_ar_ready_o,
  input  logic [31:0] csr_ar_addr_i,
  output logic        csr_r_valid_o,
  input  logic        csr_r_ready_i,
  output logic [31:0] csr_r_data_o,
  output logic [1:0]  csr_r_resp_o,

  output logic        m_ar_valid_o,
  input  logic        m_ar_ready_i,
  output logic [31:0] m_ar_addr_o,
  input  logic        m_r_valid_i,
  output logic        m_r_ready_o,
  input  logic [31:0] m_r_data_i,
  input  logic [1:0]  m_r_resp_i,
  output logic        m_aw_valid_o,
  input  logic        m_aw_ready_i,
  output logic [31:0] m_aw_addr_o,
  output logic        m_w_valid_o,
  input  logic        m_w_ready_i,
  output logic [31:0] m_w_data_o,
  output logic [3:0]  m_w_strb_o,
  input  logic        m_b_valid_i,
  output logic        m_b_ready_o,
  input  logic [1:0]  m_b_resp_i,

  input  logic        x_ar_valid_i,
  output logic        x_ar_ready_o,
  input  logic [31:0] x_ar_addr_i,
  output logic        x_r_valid_o,
  input  logic        x_r_ready_i,
  output logic [31:0] x_r_data_o,
  output logic [1:0]  x_r_resp_o,
  input  logic        x_aw_valid_i,
  output logic        x_aw_ready_o,
  input  logic [31:0] x_aw_addr_i,
  input  logic        x_w_valid_i,
  output logic        x_w_ready_o,
  input  logic [31:0] x_w_data_i,
  input  logic [3:0]  x_w_strb_i,
  output logic        x_b_valid_o,
  input  logic        x_b_ready_i,
  output logic [1:0]  x_b_resp_o,

  output logic [BANKS-1:0]      bp_cs_o,
  output logic [BANKS-1:0]      bp_we_o,
  output logic [BANKS*BPAW-1:0] bp_addr_o,
  output logic [BANKS*32-1:0]   bp_wdata_o,
  input  logic [BANKS*32-1:0]   bp_rdata_i,
  output logic                  bp_layer_o,
  output logic                  bp_kvt_o,
  input  logic                  bp_done_i,
  input  logic                  bp_err_i,
  input  logic                  bp_ready_i, // 后端就绪(桥空闲;片上后端恒 1)

  output logic                  irq_done_pulse_o,
  output logic                  irq_err_pulse_o
);

  logic [4:0]  reg_ctrl;   // [2:0] mode [3] irq_en [4] transpose
  logic [31:0] reg_layer, reg_head, reg_pos, reg_count;
  logic [31:0] reg_src, reg_dst, reg_pitch;
  logic [11:0] reg_slice;  // [5:0] DDOFF [11:6] DLEN(0=64)
  logic        busy_q, done_q, err_q;
  logic [3:0]  errcode_q;

  logic        csr_wr_busy, csr_rd_busy;
  logic [5:2]  csr_waddr_q, csr_raddr_q;

  wire csr_w_accept = csr_aw_valid_i && csr_w_valid_i && !csr_wr_busy;
  assign csr_aw_ready_o = !csr_wr_busy;
  assign csr_w_ready_o  = !csr_wr_busy;
  assign csr_b_resp_o   = amechip_pkg::AXI_OKAY;
  assign csr_b_valid_o  = csr_wr_busy;

  wire csr_r_accept = csr_ar_valid_i && !csr_rd_busy;
  assign csr_ar_ready_o = !csr_rd_busy;
  assign csr_r_resp_o   = amechip_pkg::AXI_OKAY;
  assign csr_r_valid_o  = csr_rd_busy;

  wire [5:2]  w_off = csr_aw_addr_i[5:2];
  wire [31:0] w_dat = csr_w_data_i;

  localparam logic [5:2] OFF_CTRL = 4'h0; // 0x00 CTRL

  wire [4:0] ctrl_eff_g = (csr_w_accept && (w_off == OFF_CTRL))
                          ? w_dat[4:0] : reg_ctrl;
  wire       go_fire_w = csr_w_accept && !busy_q && (w_off == OFF_CTRL) && w_dat[8];
  logic      go_pend_q;
  wire       go_fire = go_pend_q && !busy_q;   // 下一拍:寄存器已更新
  wire [2:0] go_mode  = reg_ctrl[2:0];
  wire       go_tr    = reg_ctrl[4];
  wire [5:0] go_ddoff = reg_slice[5:0];
  wire [6:0] go_dlen  = (reg_slice[11:6] == 6'd0) ? 7'd64
                                                  : {1'b0, reg_slice[11:6]};
  wire [6:0] go_sum7  = {1'b0, go_ddoff} + go_dlen;
  wire [5:0] go_lastb = go_sum7[5:0] - 6'd1; // 和 ≤64 校验通过后恰为末字节

  wire go_bad =
      (go_mode > 3'd5)
   || (reg_layer[31:1] != '0)
   || ((go_mode != 3'd2) && ((reg_head >= BANKS) || (reg_head[31:2] != '0)))
   || ((go_mode <= 3'd2) && (reg_src[1:0] != 2'b00))
   || ((go_mode <= 3'd2) && (reg_pos >= CTX_MAX))
   || ((go_mode == 3'd3 || go_mode == 3'd4) && (reg_dst[1:0] != 2'b00))
   || ((go_mode >= 3'd3) && ((reg_count == 32'b0) ||
                             (reg_pos >= CTX_MAX) ||
                             (reg_count > (CTX_MAX - reg_pos))))
   || ((go_mode == 3'd3 || go_mode == 3'd4) && go_tr && (reg_count > 32'd16))
   || ((go_mode == 3'd3 || go_mode == 3'd4) && (go_sum7 > 7'd64));
  wire go_ok = go_fire && !go_bad;

  logic [2:0]  e_mode_q;
  logic        e_tr_q, e_layer_q, e_kvt_q;
  logic [1:0]  e_head_q;
  logic [8:0]  e_pos_q;
  logic [31:0] e_cnt_q, e_src_q, e_dst_q, e_dst_cur_q, e_peff_q;
  logic [5:0]  e_ddoff_q;
  logic [6:0]  e_dlen_q;
  logic [3:0]  e_wlo_q, e_whi_q;
  logic [1:0]  h_q;
  logic [31:0] r_q;
  logic [3:0]  g_q;
  logic [1:0]  j_q;
  logic        kv_q;

  logic [16*32-1:0] line_buf;

  function automatic logic [7:0] buf_byte (input logic [5:0] idx);
    buf_byte = line_buf[idx*8 +: 8];
  endfunction


  localparam logic [3:0]
    S_IDLE   = 4'd0,
    S_A_BUS  = 4'd1,  S_A_BP  = 4'd2,
    S_K8_BUS = 4'd3,  S_K8_BP = 4'd4,
    S_R_BP   = 4'd5,  S_R_BUS = 4'd6,
    S_T_BP   = 4'd7,  S_T_J   = 4'd8, S_T_BUS = 4'd9,
    S_C_BP   = 4'd10,
    S_DRAIN  = 4'd11;
  logic [3:0] st_q;

  wire st_append = (st_q == S_A_BUS)  || (st_q == S_A_BP);
  wire st_kv8    = (st_q == S_K8_BUS) || (st_q == S_K8_BP);
  wire st_rdnt   = (st_q == S_R_BP)   || (st_q == S_R_BUS);
  wire st_clear  = (st_q == S_C_BP);

  wire busrd_start = (st_q == S_A_BUS) || (st_q == S_K8_BUS);
  wire [31:0] busrd_base =
      (st_q == S_K8_BUS) ? (e_src_q + {23'b0, h_q, 7'b0} + {25'b0, kv_q, 6'b0})
                         : e_src_q;

  wire [5:0]  t_d    = {g_q, 2'b00} + {4'b0, j_q};
  wire [6:0]  t_end  = {1'b0, e_ddoff_q} + e_dlen_q;
  wire        t_in   = (t_d >= e_ddoff_q) && ({1'b0, t_d} < t_end);
  wire [5:0]  t_disp = t_d - e_ddoff_q;
  wire [31:0] t_base = e_dst_q + {22'b0, t_disp, 4'b0};

  wire buswr_start = (st_q == S_R_BUS) || (st_q == S_T_BUS) ||
                     ((st_q == S_T_J) && t_in);
  wire [31:0] buswr_base = (st_q == S_R_BUS) ? e_dst_cur_q : t_base;
  wire [31:0] buswr_len  = (st_q == S_R_BUS) ? {25'b0, e_dlen_q}
                                             : {27'b0, e_cnt_q[4:0]};
  wire [5:0]  buswr_off  = (st_q == S_R_BUS) ? e_ddoff_q : 6'd0;
  wire        buswr_stripe = (st_q == S_T_BUS) || ((st_q == S_T_J) && t_in);
  wire [1:0]  buswr_lane   = j_q;

  wire bp_start = (st_q == S_A_BP) || (st_q == S_K8_BP) ||
                  (st_q == S_R_BP) || (st_q == S_T_BP) ||
                  (st_q == S_C_BP);
  wire [2:0] bp_op_s =
      (st_q == S_R_BP) ? 3'd3 :
      (st_q == S_T_BP) ? 3'd4 :
      (st_q == S_C_BP) ? 3'd2 : 3'd1;
  wire [1:0] bp_bank_s = (st_q == S_K8_BP) ? h_q : e_head_q;
  wire       bp_kvt_s  = (st_q == S_K8_BP) ? kv_q :
                         (st_q == S_C_BP) ? kv_q : e_kvt_q;
  wire [8:0] bp_pos_s  = (st_rdnt || st_clear) ? (e_pos_q + r_q[8:0]) : e_pos_q;
  wire [4:0] bp_lo_s   = (st_q == S_R_BP) ? {1'b0, e_wlo_q} :
                         (st_q == S_T_BP) ? {1'b0, g_q}    : 5'd0;
  wire [4:0] bp_hi_s   = (st_q == S_R_BP) ? {1'b0, e_whi_q} :
                         (st_q == S_T_BP) ? (e_cnt_q[4:0] - 5'd1) : 5'd15;

  logic [2:0] bp_op_q;
  logic [1:0] bp_bank_q;
  logic       bp_kvt_q, bp_layer_q;
  logic [8:0] bp_pos_q;
  logic [4:0] bp_lo_q, bp_hi_q, bp_idx_q;
  logic       bp_run_q, bp_err_lat_q, bp_op_done, bp_gap_q;

  wire [BANKS-1:0] bp_bank_oh = {{(BANKS-1){1'b0}}, 1'b1} << bp_bank_q;
  wire [31:0] bp_waddr = (bp_op_q == 3'd4)
      ? ({19'b0, bp_pos_q, 4'b0} + {23'b0, bp_idx_q, 4'b0} + {27'b0, bp_lo_q})
      : ({19'b0, bp_pos_q, 4'b0} + {27'b0, bp_idx_q});

  for (genvar b = 0; b < BANKS; b++) begin : g_bp
    assign bp_cs_o[b] = bp_run_q && !bp_gap_q && (32'(b) == 32'(bp_bank_q));
    assign bp_we_o[b] = bp_run_q && !bp_gap_q &&
                        (bp_op_q == 3'd1 || bp_op_q == 3'd2) &&
                        (32'(b) == 32'(bp_bank_q));
    assign bp_addr_o[b*BPAW +: BPAW] =
        ((BANKS)'(b) == (BANKS)'(bp_bank_q)) ? bp_waddr[BPAW-1:0] : '0;
    assign bp_wdata_o[b*32 +: 32] =
        ((BANKS)'(b) == (BANKS)'(bp_bank_q))
            ? ((bp_op_q == 3'd2) ? 32'b0 : line_buf[bp_idx_q[3:0]*32 +: 32])
            : 32'b0;
  end

  wire [31:0] bp_rdata_bank = bp_rdata_i[bp_bank_q*32 +: 32];

  assign bp_layer_o = bp_layer_q;
  assign bp_kvt_o   = bp_kvt_q;

  logic owner_bridge_q;
  wire ib_r_take = m_r_valid_i && !owner_bridge_q;
  wire ib_b_take = m_b_valid_i && !owner_bridge_q;

  logic       busrd_busy_q, busrd_pend_q, busrd_err_q;
  logic [4:0] busrd_beat_q;
  logic [31:0] busrd_base_q;
  wire        ib_rd_req  = busrd_busy_q && !busrd_pend_q;
  wire [31:0] ib_rd_addr = {busrd_base_q[31:2], 2'b00};
  wire        ib_rd_acc  = ib_rd_req && m_ar_ready_i && !owner_bridge_q;

  logic       buswr_busy_q, buswr_pend_q, buswr_err_q;
  logic [31:0] buswr_cur_q, buswr_s_q, buswr_e_q;
  logic [5:0]  buswr_off_q;
  logic        wr_ph_q;
  logic [31:0] wr_slot_addr_q, wr_slot_data_q;
  logic [3:0]  wr_slot_strb_q;
  logic        buswr_stripe_q;
  logic [1:0]  buswr_lane_q;
  wire        ib_wr_req  = buswr_busy_q && !buswr_pend_q && wr_ph_q &&
                           (buswr_cur_q < buswr_e_q);
  wire [31:0] ib_wr_addr = wr_slot_addr_q;
  wire [7:0]  lane_b0 = {2'b00, buswr_off_q} +
                        {2'b00, buswr_cur_q[5:0]} -
                        {2'b00, buswr_s_q[5:0]};
  wire [7:0]  lane_b1 = lane_b0 + 8'd1;
  wire [7:0]  lane_b2 = lane_b0 + 8'd2;
  wire [7:0]  lane_b3 = lane_b0 + 8'd3;
  wire [31:0] lane_p0 = buswr_cur_q + 32'd0;
  wire [31:0] lane_p1 = buswr_cur_q + 32'd1;
  wire [31:0] lane_p2 = buswr_cur_q + 32'd2;
  wire [31:0] lane_p3 = buswr_cur_q + 32'd3;
  wire lane_i0 = (lane_p0 >= buswr_s_q) && (lane_p0 < buswr_e_q);
  wire lane_i1 = (lane_p1 >= buswr_s_q) && (lane_p1 < buswr_e_q);
  wire lane_i2 = (lane_p2 >= buswr_s_q) && (lane_p2 < buswr_e_q);
  wire lane_i3 = (lane_p3 >= buswr_s_q) && (lane_p3 < buswr_e_q);
  wire [5:0] stripe_k0 = lane_b0[5:0];
  wire [5:0] stripe_k1 = lane_b1[5:0];
  wire [5:0] stripe_k2 = lane_b2[5:0];
  wire [5:0] stripe_k3 = lane_b3[5:0];
  wire [7:0] struct_byte0 = buswr_stripe_q
      ? line_buf[stripe_k0*32 + 8*buswr_lane_q +: 8]
      : line_buf[lane_b0[5:0]*8 +: 8];
  wire [7:0] struct_byte1 = buswr_stripe_q
      ? line_buf[stripe_k1*32 + 8*buswr_lane_q +: 8]
      : line_buf[lane_b1[5:0]*8 +: 8];
  wire [7:0] struct_byte2 = buswr_stripe_q
      ? line_buf[stripe_k2*32 + 8*buswr_lane_q +: 8]
      : line_buf[lane_b2[5:0]*8 +: 8];
  wire [7:0] struct_byte3 = buswr_stripe_q
      ? line_buf[stripe_k3*32 + 8*buswr_lane_q +: 8]
      : line_buf[lane_b3[5:0]*8 +: 8];
  wire [8:0] lane0 = {lane_i0, lane_i0 ? struct_byte0 : 8'h00};
  wire [8:0] lane1 = {lane_i1, lane_i1 ? struct_byte1 : 8'h00};
  wire [8:0] lane2 = {lane_i2, lane_i2 ? struct_byte2 : 8'h00};
  wire [8:0] lane3 = {lane_i3, lane_i3 ? struct_byte3 : 8'h00};
  wire [3:0]  ib_wr_strb_l = {lane3[8], lane2[8], lane1[8], lane0[8]};
  wire [31:0] ib_wr_data_l = {lane3[7:0], lane2[7:0], lane1[7:0], lane0[7:0]};
  wire        ib_wr_acc  = ib_wr_req && m_aw_ready_i && m_w_ready_i &&
                           !owner_bridge_q;

  assign m_ar_valid_o = owner_bridge_q ? x_ar_valid_i : ib_rd_req;
  assign m_ar_addr_o  = owner_bridge_q ? x_ar_addr_i  : ib_rd_addr;
  assign x_ar_ready_o = m_ar_ready_i && owner_bridge_q;

  assign m_aw_valid_o = owner_bridge_q ? x_aw_valid_i : ib_wr_req;
  assign m_aw_addr_o  = owner_bridge_q ? x_aw_addr_i  : ib_wr_addr;
  assign m_w_valid_o  = owner_bridge_q ? x_w_valid_i  : ib_wr_req;
  assign m_w_data_o   = owner_bridge_q ? x_w_data_i   : wr_slot_data_q;
  assign m_w_strb_o   = owner_bridge_q ? x_w_strb_i   : wr_slot_strb_q;
  assign x_aw_ready_o = m_aw_ready_i && owner_bridge_q;
  assign x_w_ready_o  = m_w_ready_i  && owner_bridge_q;

  assign m_r_ready_o = owner_bridge_q ? x_r_ready_i : 1'b1;
  assign m_b_ready_o = owner_bridge_q ? x_b_ready_i : 1'b1;

  assign x_r_valid_o = m_r_valid_i && owner_bridge_q;
  assign x_r_data_o  = m_r_data_i;
  assign x_r_resp_o  = m_r_resp_i;
  assign x_b_valid_o = m_b_valid_i && owner_bridge_q;
  assign x_b_resp_o  = m_b_resp_i;

  wire bus_quiet = !busrd_busy_q && !buswr_busy_q &&
                   !busrd_pend_q && !buswr_pend_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      csr_wr_busy <= 1'b0; csr_waddr_q <= '0;
      csr_rd_busy <= 1'b0; csr_raddr_q <= '0;
    end else begin
      if (csr_w_accept) begin
        csr_waddr_q <= w_off; csr_wr_busy <= 1'b1;
      end else if (csr_wr_busy && csr_b_ready_i) begin
        csr_wr_busy <= 1'b0;
      end
      if (csr_r_accept) begin
        csr_raddr_q <= csr_ar_addr_i[5:2]; csr_rd_busy <= 1'b1;
      end else if (csr_rd_busy && csr_r_ready_i) begin
        csr_rd_busy <= 1'b0;
      end
    end
  end

  always_comb begin
    case (csr_raddr_q)
      4'h0: csr_r_data_o = {27'b0, reg_ctrl};
      4'h1: csr_r_data_o = reg_layer;
      4'h2: csr_r_data_o = reg_head;
      4'h3: csr_r_data_o = reg_pos;
      4'h4: csr_r_data_o = reg_count;
      4'h5: csr_r_data_o = reg_src;
      4'h6: csr_r_data_o = reg_dst;
      4'h7: csr_r_data_o = reg_pitch;
      4'h8: csr_r_data_o = {24'b0, errcode_q, 1'b0, err_q, done_q, busy_q};
      4'h9: csr_r_data_o = {20'b0, reg_slice};
      default: csr_r_data_o = 32'h0;
    endcase
  end

  logic        busrd_done;
  logic        buswr_done;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      reg_ctrl <= 5'b0; reg_layer <= '0; reg_head <= '0; reg_pos <= '0;
      reg_count <= '0; reg_src <= '0; reg_dst <= '0; reg_pitch <= '0;
      reg_slice <= 12'b0;
      busy_q <= 1'b0; done_q <= 1'b0; err_q <= 1'b0; errcode_q <= 4'h0;
      go_pend_q <= 1'b0;
      e_mode_q <= '0; e_tr_q <= 1'b0; e_layer_q <= 1'b0; e_kvt_q <= 1'b0;
      e_head_q <= '0; e_pos_q <= '0; e_cnt_q <= '0; e_src_q <= '0;
      e_dst_q <= '0; e_dst_cur_q <= '0; e_peff_q <= '0;
      e_ddoff_q <= '0; e_dlen_q <= '0; e_wlo_q <= '0; e_whi_q <= '0;
      h_q <= '0; r_q <= '0; g_q <= '0; j_q <= '0; kv_q <= 1'b0;
      st_q <= S_IDLE;
      busrd_busy_q <= 1'b0; busrd_pend_q <= 1'b0; busrd_err_q <= 1'b0;
      busrd_beat_q <= '0; busrd_base_q <= '0; busrd_done <= 1'b0;
      buswr_busy_q <= 1'b0; buswr_pend_q <= 1'b0; buswr_err_q <= 1'b0;
      buswr_cur_q <= '0; buswr_s_q <= '0; buswr_e_q <= '0;
      buswr_off_q <= '0; buswr_done <= 1'b0;
      wr_ph_q <= 1'b0; wr_slot_addr_q <= '0; wr_slot_data_q <= '0;
      wr_slot_strb_q <= '0; buswr_stripe_q <= 1'b0; buswr_lane_q <= '0;
      bp_op_q <= 3'd0; bp_bank_q <= '0; bp_kvt_q <= 1'b0; bp_layer_q <= 1'b0;
      bp_pos_q <= '0; bp_lo_q <= '0; bp_hi_q <= '0; bp_idx_q <= '0;
      bp_run_q <= 1'b0; bp_err_lat_q <= 1'b0; bp_op_done <= 1'b0; bp_gap_q <= 1'b0;
      owner_bridge_q <= 1'b0;
      irq_done_pulse_o <= 1'b0; irq_err_pulse_o <= 1'b0;
      line_buf <= '0;
    end else begin
      irq_done_pulse_o <= 1'b0;
      irq_err_pulse_o  <= 1'b0;
      busrd_done    <= 1'b0;
      buswr_done    <= 1'b0;
      bp_op_done    <= 1'b0;

      go_pend_q <= go_fire_w;

      if (csr_w_accept && !busy_q) begin
        case (w_off)
          4'h1: reg_layer <= w_dat;
          4'h2: reg_head  <= w_dat;
          4'h3: reg_pos   <= w_dat;
          4'h4: reg_count <= w_dat;
          4'h5: reg_src   <= w_dat;
          4'h6: reg_dst   <= w_dat;
          4'h7: reg_pitch <= w_dat;
          4'h8: begin
            done_q <= done_q & ~w_dat[1];
            err_q  <= err_q  & ~w_dat[2];
          end
          4'h9: reg_slice <= w_dat[11:0];
          4'h0: reg_ctrl <= w_dat[4:0];
          default: ;
        endcase
      end
      if (csr_w_accept && busy_q && (w_off == OFF_CTRL) && w_dat[9]) begin
        err_q     <= 1'b1;
        errcode_q <= amechip_pkg::KV_ERR_ABORT;
        irq_err_pulse_o <= reg_ctrl[3];
        st_q      <= S_DRAIN;
      end

      if (go_fire && go_bad) begin   // 仅在 GO 拍判参数错(不随寄存器变化误报)
        err_q     <= 1'b1;
        errcode_q <= amechip_pkg::KV_ERR_POS;
        irq_err_pulse_o <= reg_ctrl[3];
      end
      if (go_ok) begin
        e_mode_q    <= reg_ctrl[2:0];
        e_tr_q      <= reg_ctrl[4];
        e_layer_q   <= reg_layer[0];
        e_kvt_q     <= reg_ctrl[0] ^ (reg_ctrl[1] | reg_ctrl[2]);
        e_head_q    <= reg_head[1:0];
        e_pos_q     <= reg_pos[8:0];
        e_cnt_q     <= reg_count;
        e_src_q     <= reg_src;
        e_dst_q     <= reg_dst;
        e_dst_cur_q <= reg_dst;
        e_ddoff_q   <= go_ddoff;
        e_dlen_q    <= go_dlen;
        e_peff_q    <= (reg_pitch != 32'b0) ? reg_pitch : {25'b0, go_dlen};
        e_wlo_q     <= go_ddoff[5:2];
        e_whi_q     <= go_lastb[5:2];
        h_q  <= 2'd0;
        kv_q <= 1'b0;
        r_q  <= 32'd0;
        g_q  <= go_ddoff[5:2];
        j_q  <= 2'd0;
        busy_q <= 1'b1;
        if (reg_ctrl[2:0] == 3'd5) begin
          st_q <= S_C_BP;
        end else if (reg_ctrl[2:0] <= 3'd1) begin
          st_q <= S_A_BUS;
        end else if (reg_ctrl[2:0] == 3'd2) begin
          st_q <= S_K8_BUS;
        end else begin
          st_q <= reg_ctrl[4] ? S_T_BP : S_R_BP;
        end
      end

      if (busrd_start && !busrd_busy_q && !busrd_done) begin
        busrd_busy_q <= 1'b1;
        busrd_pend_q <= 1'b0;
        busrd_err_q  <= 1'b0;
        busrd_beat_q <= 5'd0;
        busrd_base_q <= busrd_base;
      end
      if (ib_rd_acc) begin
        busrd_pend_q <= 1'b1;
      end
      if (ib_r_take && busrd_busy_q && busrd_pend_q) begin
        busrd_pend_q <= 1'b0;
        line_buf[busrd_beat_q[3:0]*32 +: 32] <= m_r_data_i;
        if (m_r_resp_i != amechip_pkg::AXI_OKAY) busrd_err_q <= 1'b1;
        if (busrd_beat_q == 5'd15) begin
          busrd_busy_q <= 1'b0;
          busrd_done   <= 1'b1;
        end else begin
          busrd_beat_q <= busrd_beat_q + 5'd1;
          busrd_base_q <= busrd_base_q + 32'd4;
        end
      end

      if (buswr_start && !buswr_busy_q && !buswr_done) begin
        buswr_busy_q <= 1'b1;
        buswr_pend_q <= 1'b0;
        buswr_err_q  <= 1'b0;
        buswr_s_q    <= buswr_base;
        buswr_e_q    <= buswr_base + buswr_len;
        buswr_cur_q  <= {buswr_base[31:2], 2'b00};
        buswr_off_q  <= buswr_off;
        buswr_stripe_q <= buswr_stripe;
        buswr_lane_q   <= buswr_lane;
        wr_ph_q      <= 1'b0; // 先算首窗口
      end
      if (buswr_busy_q && !buswr_pend_q && !wr_ph_q && (buswr_cur_q < buswr_e_q)) begin
        wr_slot_addr_q <= buswr_cur_q;
        wr_slot_data_q <= ib_wr_data_l;
        wr_slot_strb_q <= ib_wr_strb_l;
        wr_ph_q        <= 1'b1;
      end
      if (ib_wr_acc) begin
        buswr_pend_q <= 1'b1;
        buswr_cur_q  <= buswr_cur_q + 32'd4;
        wr_ph_q      <= 1'b0; // 下一窗口重新计算
      end
      if (ib_b_take && buswr_busy_q && buswr_pend_q) begin
        buswr_pend_q <= 1'b0;
        if (m_b_resp_i != amechip_pkg::AXI_OKAY) buswr_err_q <= 1'b1;
      end
      if (buswr_busy_q && !buswr_pend_q && (buswr_cur_q >= buswr_e_q)) begin
        buswr_busy_q <= 1'b0;
        buswr_done   <= 1'b1;
      end

      if (bp_start && !bp_run_q && !bp_op_done && bp_ready_i) begin
        bp_gap_q      <= 1'b0;
        bp_run_q      <= 1'b1;
        bp_op_q       <= bp_op_s;
        bp_bank_q     <= bp_bank_s;
        bp_kvt_q      <= bp_kvt_s;
        bp_layer_q    <= e_layer_q;
        bp_pos_q      <= bp_pos_s;
        bp_lo_q       <= bp_lo_s;
        bp_hi_q       <= bp_hi_s;
        bp_idx_q      <= (bp_op_s == 3'd3) ? bp_lo_s : 5'd0;
        bp_err_lat_q  <= 1'b0;
      end
      if (!KV_BACKEND_B && bp_start && !bp_run_q && !bp_op_done && bp_ready_i)
        owner_bridge_q <= 1'b1;
      if (bp_done_i && bp_run_q && !bp_gap_q) begin
        if (bp_err_i) bp_err_lat_q <= 1'b1;
        if (bp_op_q == 3'd3 || bp_op_q == 3'd4) begin
          line_buf[bp_idx_q[3:0]*32 +: 32] <= bp_rdata_bank;
        end
        if (bp_idx_q == bp_hi_q) begin
          bp_run_q       <= 1'b0;
          bp_op_done     <= 1'b1; // 整笔 bank 操作完成脉冲
          owner_bridge_q <= 1'b0;
        end else begin
          bp_idx_q  <= bp_idx_q + 5'd1;
          bp_gap_q  <= 1'b1;      // 下一字前插一拍 cs=0
        end
      end
      if (bp_gap_q && !(bp_done_i && bp_run_q && !bp_gap_q)) begin
        bp_gap_q <= 1'b0;   // 间隙只持续一拍(拍内 done 被忽略)
      end

      case (st_q)
        S_IDLE: ;
        S_A_BUS: if (busrd_done) st_q <= S_A_BP;
        S_A_BP: if (bp_op_done) begin
          if (bp_err_lat_q || busrd_err_q) begin
            err_q <= 1'b1; errcode_q <= amechip_pkg::KV_ERR_BUS;
            irq_err_pulse_o <= reg_ctrl[3];
            busy_q <= 1'b0; st_q <= S_IDLE;
          end else begin
            done_q <= 1'b1; busy_q <= 1'b0;
            irq_done_pulse_o <= reg_ctrl[3];
            st_q <= S_IDLE;
          end
        end
        S_K8_BUS: if (busrd_done) st_q <= S_K8_BP;
        S_K8_BP: if (bp_op_done) begin
          if (bp_err_lat_q || busrd_err_q) begin
            err_q <= 1'b1; errcode_q <= amechip_pkg::KV_ERR_BUS;
            irq_err_pulse_o <= reg_ctrl[3];
            busy_q <= 1'b0; st_q <= S_IDLE;
          end else if (kv_q == 1'b0) begin
            kv_q <= 1'b1; st_q <= S_K8_BUS;
          end else if (h_q == 2'd3) begin
            done_q <= 1'b1; busy_q <= 1'b0;
            irq_done_pulse_o <= reg_ctrl[3];
            st_q <= S_IDLE;
          end else begin
            h_q <= h_q + 2'd1; kv_q <= 1'b0; st_q <= S_K8_BUS;
          end
        end
        S_R_BP: if (bp_op_done) st_q <= S_R_BUS;
        S_R_BUS: if (buswr_done) begin
          if (bp_err_lat_q || buswr_err_q) begin
            err_q <= 1'b1; errcode_q <= amechip_pkg::KV_ERR_BUS;
            irq_err_pulse_o <= reg_ctrl[3];
            busy_q <= 1'b0; st_q <= S_IDLE;
          end else if (r_q == e_cnt_q - 32'd1) begin
            done_q <= 1'b1; busy_q <= 1'b0;
            irq_done_pulse_o <= reg_ctrl[3];
            st_q <= S_IDLE;
          end else begin
            r_q         <= r_q + 32'd1;
            e_dst_cur_q <= e_dst_cur_q + e_peff_q;
            st_q        <= S_R_BP;
          end
        end
        S_T_BP: if (bp_op_done) begin
          j_q <= 2'd0; st_q <= S_T_J;
        end
        S_T_J: begin
          if (t_in) begin
            st_q <= S_T_BUS;
          end else if (j_q == 2'd3) begin
            if (g_q == e_whi_q) begin
              done_q <= 1'b1; busy_q <= 1'b0;
              irq_done_pulse_o <= reg_ctrl[3];
              st_q <= S_IDLE;
            end else begin
              g_q <= g_q + 4'd1; st_q <= S_T_BP;
            end
          end else begin
            j_q <= j_q + 2'd1;
          end
        end
        S_T_BUS: if (buswr_done) begin
          if (bp_err_lat_q || buswr_err_q) begin
            err_q <= 1'b1; errcode_q <= amechip_pkg::KV_ERR_BUS;
            irq_err_pulse_o <= reg_ctrl[3];
            busy_q <= 1'b0; st_q <= S_IDLE;
          end else if (j_q == 2'd3) begin
            if (g_q == e_whi_q) begin
              done_q <= 1'b1; busy_q <= 1'b0;
              irq_done_pulse_o <= reg_ctrl[3];
              st_q <= S_IDLE;
            end else begin
              g_q <= g_q + 4'd1; st_q <= S_T_BP;
            end
          end else begin
            j_q <= j_q + 2'd1; st_q <= S_T_J;
          end
        end
        S_C_BP: if (bp_op_done) begin
          if (bp_err_lat_q) begin
            err_q <= 1'b1; errcode_q <= amechip_pkg::KV_ERR_BUS;
            irq_err_pulse_o <= reg_ctrl[3];
            busy_q <= 1'b0; st_q <= S_IDLE;
          end else if (kv_q == 1'b0) begin
            kv_q <= 1'b1; // 原状态重启引擎写 V 行
          end else if (r_q == e_cnt_q - 32'd1) begin
            done_q <= 1'b1; busy_q <= 1'b0;
            irq_done_pulse_o <= reg_ctrl[3];
            st_q <= S_IDLE;
          end else begin
            r_q <= r_q + 32'd1; kv_q <= 1'b0;
          end
        end
        S_DRAIN: if (bus_quiet && !bp_run_q) begin
          busy_q <= 1'b0; st_q <= S_IDLE;
        end
        default: st_q <= S_IDLE;
      endcase
    end
  end

  logic _unused;
  assign _unused = ^{e_tr_q, e_mode_q, csr_w_strb_i};

endmodule
