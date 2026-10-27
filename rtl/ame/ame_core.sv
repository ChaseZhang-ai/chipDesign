`ifndef _AMECHIP_PKG_SV
 `include "amechip_pkg.sv"
`endif

module ame_core #(
  parameter int unsigned AME_M      = amechip_pkg::AME_M_DEF,
  parameter int unsigned AME_N      = amechip_pkg::AME_N_DEF,
  parameter int unsigned WBUF_TILES = amechip_pkg::WBUF_TILES,
  parameter int unsigned WBUF_DEPTH = WBUF_TILES * AME_M * AME_N,
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

  input  logic        bus_req_valid_i,
  input  logic        bus_req_write_i,
  input  logic [31:0] bus_req_addr_i,
  input  logic [31:0] bus_req_wdata_i,
  input  logic [3:0]  bus_req_wstrb_i,
  output logic        bus_req_ready_o,
  output logic        bus_resp_valid_o,
  output logic [31:0] bus_resp_rdata_o,
  output logic        bus_resp_err_o,

  output logic irq_done_o,
  output logic irq_err_o,

  output logic dbg_mac_en_o,
  output logic dbg_idle_o
);

  localparam int unsigned WBUF_AW  = $clog2(WBUF_DEPTH);
  localparam int unsigned XBUF_AW  = $clog2(XBUF_DEPTH);
  localparam int unsigned YQ_WORDS = (AME_N + 3) / 4;

  logic [32*amechip_pkg::RQ_ENTRIES-1:0] y_val;

  logic               tld_en, tld_sel, xld_en, xld_sel;
  logic [5:0]         tld_n;
  logic [WBUF_AW-1:0] wrow_addr;
  logic [XBUF_AW-1:0] xrow_addr;
  logic [8*AME_M-1:0] wrow_data, xrow_data;
  logic               mac_sel, mac_en, mac_acc, y_clr;
  logic [5:0]         mac_k, mac_n_eff;
  logic               y32_we_arr;
  logic [5:0]         y32_addr_arr;

  logic        rq_we;
  logic [4:0]  rq_waddr, rq_ra_idx;
  logic [31:0] rq_wm, rq_ra_m;
  logic [5:0]  rq_ws, rq_ra_s;
  logic        rq_wround, rq_ra_round;
  logic [19:0]      rq_rb_idx;
  logic [4*32-1:0]  rq_rb_m;
  logic [4*6-1:0]   rq_rb_s;
  logic [3:0]       rq_rb_round;

  logic       st_busy, st_done, st_err, idle;
  logic [3:0] st_rdy;
  logic [1:0] irqen_q;
  logic        evclear_done, evclear_err, irqen_we, bus_err;
  logic [1:0]  irqen_wdata;

  logic        wbuf_we, xbuf_we;
  logic [31:0] wbuf_waddr, wbuf_wdata, xbuf_waddr, xbuf_wdata;
  logic [3:0]  wbuf_wstrb, xbuf_wstrb;
  logic [31:0] wbuf_rdata32, xbuf_rdata32;
  logic        wbuf_rd32_go, xbuf_rd32_go;
  logic        wbuf_rd_row_go, xbuf_rd_row_go;

  ame_buf_rf #(.DEPTH(WBUF_DEPTH), .ROW_B(AME_M)) u_wbuf (
    .clk         (clk_i),
    .we_i        (wbuf_we),
    .waddr_i     (wbuf_waddr),
    .wdata_i     (wbuf_wdata),
    .wstrb_i     (wbuf_wstrb),
    .rd32_go_i   (wbuf_rd32_go),
    .raddr32_i   (wbuf_waddr),
    .rdata32_o   (wbuf_rdata32),
    .rd_row_go_i (wbuf_rd_row_go),
    .raddr_row_i (wrow_addr),
    .rdata_row_o (wrow_data)
  );

  ame_buf_rf #(.DEPTH(XBUF_DEPTH), .ROW_B(AME_M)) u_xbuf (
    .clk         (clk_i),
    .we_i        (xbuf_we),
    .waddr_i     (xbuf_waddr),
    .wdata_i     (xbuf_wdata),
    .wstrb_i     (xbuf_wstrb),
    .rd32_go_i   (xbuf_rd32_go),
    .raddr32_i   (xbuf_waddr),
    .rdata32_o   (xbuf_rdata32),
    .rd_row_go_i (xbuf_rd_row_go),
    .raddr_row_i (xrow_addr),
    .rdata_row_o (xrow_data)
  );

  logic tld_en_d, tld_sel_d, xld_en_d, xld_sel_d;
  logic [5:0] tld_n_d;

  always_ff @(posedge clk_i) begin
    tld_en_d  <= tld_en;
    tld_sel_d <= tld_sel;
    tld_n_d   <= tld_n;
    xld_en_d  <= xld_en;
    xld_sel_d <= xld_sel;
  end

  ame_array #(.AME_M(AME_M), .AME_N(AME_N)) u_array (
    .clk        (clk_i),
    .rst_n      (rst_ni),
    .tld_en_i   (tld_en_d),
    .tld_sel_i  (tld_sel_d),
    .tld_n_i    (tld_n_d),
    .tld_row_i  (wrow_data),
    .xld_en_i   (xld_en_d),
    .xld_sel_i  (xld_sel_d),
    .xld_row_i  (xrow_data),
    .sel_i      (mac_sel),
    .k_i        (mac_k),
    .mac_en_i   (mac_en),
    .mac_acc_i  (mac_acc),
    .mac_n_eff_i(mac_n_eff),
    .y_clr_i    (y_clr),
    .y32_we_i   (y32_we_arr),
    .y32_addr_i (y32_addr_arr),
    .y32_wdata_i(bus_req_wdata_i),
    .y_rdata_o  (y_val)
  );

  ame_rqtab u_rqtab (
    .clk       (clk_i),
    .rst_n     (rst_ni),
    .we_i      (rq_we),
    .waddr_i   (rq_waddr),
    .wM_i      (rq_wm),
    .wS_i      (rq_ws),
    .wround_i  (rq_wround),
    .ra_idx_i  (rq_ra_idx),
    .ra_m_o    (rq_ra_m),
    .ra_s_o    (rq_ra_s),
    .ra_round_o(rq_ra_round),
    .rb_idx_i  (rq_rb_idx),
    .rb_m_o    (rq_rb_m),
    .rb_s_o    (rq_rb_s),
    .rb_round_o(rq_rb_round)
  );

  logic [7:0] yq_q8 [4];
  for (genvar j = 0; j < 4; j++) begin : g_yq
    assign rq_rb_idx[5*j +: 5] = {s1_rel[4:2], 2'(j)};
    ame_requant u_rq (
      .clk_i(clk_i),
      .y_i  (y_val[32*({s1_rel[4:2], 2'(j)}) +: 32]),
      .m_i  (rq_rb_m[32*j +: 32]),
      .s_i  (rq_rb_s[6*j +: 6]),
      .rnd_i(rq_rb_round[j]),
      .q_o  (yq_q8[j])
    );
  end

  ame_ctrl #(
    .AME_M     (AME_M),
    .AME_N     (AME_N),
    .WBUF_DEPTH(WBUF_DEPTH),
    .XBUF_DEPTH(XBUF_DEPTH)
  ) u_ctrl (
    .clk_i          (clk_i),
    .rst_ni         (rst_ni),
    .cp_req_valid_i (cp_req_valid_i),
    .cp_req_instr_i (cp_req_instr_i),
    .cp_req_rs1_i   (cp_req_rs1_i),
    .cp_req_rs2_i   (cp_req_rs2_i),
    .cp_req_ready_o (cp_req_ready_o),
    .cp_resp_valid_o(cp_resp_valid_o),
    .cp_resp_data_o (cp_resp_data_o),
    .cp_resp_err_o  (cp_resp_err_o),
    .tld_en_o       (tld_en),
    .tld_sel_o      (tld_sel),
    .tld_n_o        (tld_n),
    .xld_en_o       (xld_en),
    .xld_sel_o      (xld_sel),
    .mac_sel_o      (mac_sel),
    .mac_k_o        (mac_k),
    .mac_en_o       (mac_en),
    .mac_acc_o      (mac_acc),
    .mac_n_eff_o    (mac_n_eff),
    .y_clr_o        (y_clr),
    .y_val_i        (y_val),
    .wrow_addr_o    (wrow_addr),
    .xrow_addr_o    (xrow_addr),
    .row_w_stall_i  (wbuf_rd32_go),
    .row_x_stall_i  (xbuf_rd32_go),
    .rq_we_o        (rq_we),
    .rq_waddr_o     (rq_waddr),
    .rq_wm_o        (rq_wm),
    .rq_ws_o        (rq_ws),
    .rq_wround_o    (rq_wround),
    .rq_ra_idx_o    (rq_ra_idx),
    .rq_ra_m_i      (rq_ra_m),
    .rq_ra_s_i      (rq_ra_s),
    .rq_ra_round_i  (rq_ra_round),
    .bus_err_i      (bus_err),
    .evclear_done_i (evclear_done),
    .evclear_err_i  (evclear_err),
    .irqen_we_i     (irqen_we),
    .irqen_wdata_i  (irqen_wdata),
    .irqen_o        (irqen_q),
    .irq_done_o     (irq_done_o),
    .irq_err_o      (irq_err_o),
    .st_busy_o      (st_busy),
    .st_done_o      (st_done),
    .st_err_o       (st_err),
    .st_rdy_o       (st_rdy),
    .idle_o         (idle)
  );

  logic [31:0] rel;
  logic        in_win, aligned;

  logic sel_wbuf, sel_xbuf, sel_y32, sel_yq;
  logic sel_status, sel_irqen, sel_evclear, sel_def_wr;

  logic [4:0]  y32_idx, yq_idx;
  logic        y32_idx_ok, yq_idx_ok;
  logic        wr_err, rd_err;

  assign rel     = bus_req_addr_i - amechip_pkg::A_AME_BASE;
  assign in_win  = (bus_req_addr_i >= amechip_pkg::A_AME_BASE) &&
                   (rel <= 32'h1FFF);
  assign aligned = (bus_req_addr_i[1:0] == 2'b00);

  always_comb begin
    sel_wbuf    = in_win && (rel <  amechip_pkg::AME_XBUF_OFF);
    sel_xbuf    = in_win && (rel >= amechip_pkg::AME_XBUF_OFF) && (rel < amechip_pkg::AME_Y32_OFF);
    sel_y32     = in_win && (rel >= amechip_pkg::AME_Y32_OFF)  && (rel < amechip_pkg::AME_Y32_OFF + 32'h80);
    sel_yq      = in_win && (rel >= amechip_pkg::AME_YQ_OFF)   && (rel < amechip_pkg::AME_YQ_OFF + 32'h20);
    sel_status  = in_win && (rel == amechip_pkg::AME_STATUS_OFF);
    sel_irqen   = in_win && (rel == amechip_pkg::AME_STATUS_OFF + 32'h4);
    sel_evclear = in_win && (rel == amechip_pkg::AME_STATUS_OFF + 32'h8);
    sel_def_wr  = in_win && !sel_wbuf && !sel_xbuf && !sel_y32 && !sel_yq &&
                           !sel_status && !sel_irqen && !sel_evclear;
  end

  assign y32_idx    = rel[6:2];
  assign y32_idx_ok = (32'(y32_idx) < 32'(AME_N));

  assign wbuf_we    = bus_req_valid_i && bus_req_write_i && sel_wbuf && aligned;
  assign wbuf_waddr = rel;
  assign wbuf_wdata = bus_req_wdata_i;
  assign wbuf_wstrb = bus_req_wstrb_i;

  assign xbuf_we    = bus_req_valid_i && bus_req_write_i && sel_xbuf && aligned;
  assign xbuf_waddr = rel - amechip_pkg::AME_XBUF_OFF;
  assign xbuf_wdata = bus_req_wdata_i;
  assign xbuf_wstrb = bus_req_wstrb_i;

  assign y32_we_arr   = bus_req_valid_i && bus_req_write_i && sel_y32 && aligned &&
                        y32_idx_ok && idle;
  assign y32_addr_arr = {1'b0, y32_idx};

  assign irqen_we     = bus_req_valid_i && bus_req_write_i && sel_irqen && aligned && bus_req_wstrb_i[0];
  assign irqen_wdata  = bus_req_wdata_i[1:0];
  assign evclear_done = bus_req_valid_i && bus_req_write_i && sel_evclear && aligned &&
                        bus_req_wstrb_i[0] && bus_req_wdata_i[0];
  assign evclear_err  = bus_req_valid_i && bus_req_write_i && sel_evclear && aligned &&
                        bus_req_wstrb_i[0] && bus_req_wdata_i[1];

  assign wr_err = bus_req_valid_i && bus_req_write_i &&
                  (!in_win || !aligned || sel_yq || sel_status || sel_def_wr ||
                   (sel_y32 && (!y32_idx_ok || !idle)));

  assign rd_err = bus_req_valid_i && !bus_req_write_i && (!in_win || !aligned);

  assign bus_err = wr_err || rd_err;

  logic        s1_v;
  logic        s1_err, s1_yq;
  logic [12:0] s1_rel;
  logic [1:0]  s1_cnt;

  wire acc_rd_c  = bus_req_valid_i && !bus_req_write_i;
  wire acc_buf_c = acc_rd_c && aligned && (sel_wbuf || sel_xbuf);

  assign wbuf_rd32_go   = acc_buf_c &&  sel_wbuf;
  assign xbuf_rd32_go   = acc_buf_c && !sel_wbuf;
  assign wbuf_rd_row_go = tld_en;
  assign xbuf_rd_row_go = xld_en;

  logic s2_wbuf, s2_xbuf, s2_y32, s2_yq, s2_status, s2_irqen, s2_yq_ok;
  logic [4:0] s2_idx;
  logic       s2_idx_ok;
  logic [31:0] s1_rel32;
  assign s1_rel32 = {19'd0, s1_rel};
  always_comb begin
    s2_wbuf   = (s1_rel32 <  amechip_pkg::AME_XBUF_OFF);
    s2_xbuf   = (s1_rel32 >= amechip_pkg::AME_XBUF_OFF) && (s1_rel32 < amechip_pkg::AME_Y32_OFF);
    s2_y32    = (s1_rel32 >= amechip_pkg::AME_Y32_OFF)  && (s1_rel32 <  amechip_pkg::AME_Y32_OFF + 32'h80);
    s2_yq     = (s1_rel32 >= amechip_pkg::AME_YQ_OFF)   && (s1_rel32 <  amechip_pkg::AME_YQ_OFF + 32'h20);
    s2_status = (s1_rel32 == amechip_pkg::AME_STATUS_OFF);
    s2_irqen  = (s1_rel32 == amechip_pkg::AME_STATUS_OFF + 32'h4);
    s2_idx    = s1_rel[6:2];
    s2_idx_ok = (32'(s2_idx) < 32'(AME_N));
    s2_yq_ok  = (32'(s2_idx) < 32'(YQ_WORDS));
  end

  logic [31:0] rd_data_s2;
  always_comb begin
    rd_data_s2 = 32'd0;
    if (!s1_err) begin
      if (s2_wbuf)        rd_data_s2 = wbuf_rdata32;
      else if (s2_xbuf)   rd_data_s2 = xbuf_rdata32;
      else if (s2_y32)    rd_data_s2 = s2_idx_ok ? y_val[32*s2_idx +: 32] : 32'd0;
      else if (s2_status) rd_data_s2 = {{24{1'b0}}, st_err, 1'b0, st_rdy, st_done, st_busy};
      else if (s2_irqen)  rd_data_s2 = {30'd0, irqen_q};
      else                rd_data_s2 = 32'd0;
    end
  end

  logic        resp_v_q;
  logic [31:0] resp_rdata_q;
  logic        resp_err_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      s1_v         <= 1'b0;
      s1_err       <= 1'b0;
      s1_yq        <= 1'b0;
      s1_rel       <= 13'd0;
      s1_cnt       <= 2'd0;
      resp_v_q     <= 1'b0;
      resp_rdata_q <= 32'd0;
      resp_err_q   <= 1'b0;
    end else begin
      if (acc_rd_c) begin
        s1_v    <= 1'b1;
        s1_err  <= rd_err;
        s1_yq   <= sel_yq;
        s1_rel  <= rel[12:0];
        s1_cnt  <= 2'd0;
      end else if (s1_v && s1_yq) begin
        if (s1_cnt == 2'd2) begin
          s1_v   <= 1'b0;
          s1_cnt <= 2'd0;
        end else begin
          s1_cnt <= s1_cnt + 2'd1;
        end
      end else if (s1_v) begin
        s1_v    <= 1'b0;
        s1_cnt  <= 2'd0;
      end

      resp_v_q <= 1'b0;
      if (bus_req_valid_i && bus_req_write_i) begin
        resp_v_q     <= 1'b1;
        resp_rdata_q <= 32'd0;
        resp_err_q   <= wr_err;
      end else if (s1_v && s1_yq && (s1_cnt == 2'd2)) begin
        resp_v_q     <= 1'b1;
        resp_rdata_q <= (s1_err || !s2_yq_ok) ? 32'd0
                                              : {yq_q8[3], yq_q8[2], yq_q8[1], yq_q8[0]};
        resp_err_q   <= s1_err;
      end else if (s1_v && !s1_yq) begin
        resp_v_q     <= 1'b1;
        resp_rdata_q <= rd_data_s2;
        resp_err_q   <= s1_err;
      end
    end
  end

  assign dbg_mac_en_o = mac_en;
  assign dbg_idle_o   = idle;

  assign bus_req_ready_o  = 1'b1;
  assign bus_resp_valid_o = resp_v_q;
  assign bus_resp_rdata_o = resp_rdata_q;
  assign bus_resp_err_o   = resp_err_q;

endmodule
