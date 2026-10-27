`ifndef _AMECHIP_PKG_SV
 `include "amechip_pkg.sv"
`endif

module axi_xbar_port #(
  parameter int unsigned NM     = 4,
  parameter int unsigned PDEPTH = 16  // 属主 FIFO 深度(≥ 各主 outstanding 上限之和)
) (
  input  logic clk_i,
  input  logic rst_ni,
  input  logic [NM-1:0]    req_w_i,
  input  logic [32*NM-1:0] aw_addr_i,
  input  logic [32*NM-1:0] w_data_i,
  input  logic [4*NM-1:0]  w_strb_i,
  input  logic [NM-1:0]    req_r_i,
  input  logic [32*NM-1:0] ar_addr_i,
  output logic [NM-1:0]    g_aw_ready_o,
  output logic [NM-1:0]    g_w_ready_o,
  output logic [NM-1:0]    g_ar_ready_o,
  output logic [NM-1:0]    b_valid_o,
  input  logic [NM-1:0]    b_ready_i,
  output logic [2*NM-1:0]  b_resp_o,
  output logic [NM-1:0]    r_valid_o,
  input  logic [NM-1:0]    r_ready_i,
  output logic [32*NM-1:0] r_data_o,
  output logic [2*NM-1:0]  r_resp_o,
  output logic             s_aw_valid_o,
  input  logic             s_aw_ready_i,
  output logic [31:0]      s_aw_addr_o,
  output logic             s_w_valid_o,
  input  logic             s_w_ready_i,
  output logic [31:0]      s_w_data_o,
  output logic [3:0]       s_w_strb_o,
  input  logic             s_b_valid_i,
  output logic             s_b_ready_o,
  input  logic [1:0]       s_b_resp_i,
  output logic             s_ar_valid_o,
  input  logic             s_ar_ready_i,
  output logic [31:0]      s_ar_addr_o,
  input  logic             s_r_valid_i,
  output logic             s_r_ready_o,
  input  logic [31:0]      s_r_data_i,
  input  logic [1:0]       s_r_resp_i
);

  localparam int unsigned WIDX = (NM <= 1) ? 1 : $clog2(NM);
  localparam int unsigned PW   = $clog2(PDEPTH);

  function automatic logic [NM-1:0] rr_grant (
    input logic [NM-1:0] req,
    input logic [WIDX-1:0] last
  );
    logic [NM-1:0] g;
    logic found;
    int unsigned idx;
    int unsigned last_i;
    g = '0;
    found = 1'b0;
    last_i = {30'b0, last};
    for (int k = 0; k < NM; k++) begin
      idx = last_i + 32'd1 + 32'(k);
      if (idx >= 32'(NM)) idx = idx - 32'(NM);
      if (!found && req[idx]) begin
        g[idx]  = 1'b1;
        found   = 1'b1;
      end
    end
    return g;
  endfunction

  function automatic logic [WIDX-1:0] oh2idx (input logic [NM-1:0] oh);
    logic [WIDX-1:0] r;
    r = '0;
    for (int i = NM-1; i >= 0; i--) begin
      if (oh[i]) r = WIDX'(i);
    end
    return r;
  endfunction

  logic [PW-1:0]        w_wp, w_rp;
  logic [PW:0]          w_cnt;
  logic [PDEPTH*NM-1:0] w_own;
  logic [1:0]           w_state;         // 0=idle 1=driving
  logic [WIDX-1:0]      w_rr;
  logic [31:0]          w_l_addr, w_l_data;
  logic [3:0]           w_l_strb;
  logic                 w_aw_acc_q, w_w_acc_q;

  wire w_room = ~w_cnt[PW];
  wire [NM-1:0] w_req_m = req_w_i & {NM{(w_state == 2'd0) && w_room}};
  wire [NM-1:0] w_grant  = rr_grant(w_req_m, w_rr);
  wire          w_start  = (|w_grant);
  wire [WIDX-1:0] w_g_idx = oh2idx(w_grant);

  assign g_aw_ready_o = w_grant;
  assign g_w_ready_o  = w_grant;

  wire aw_drive = ((w_state == 2'd0) && w_start) ||
                  ((w_state == 2'd1) && !w_aw_acc_q);
  wire w_drive  = aw_drive;
  assign s_aw_valid_o = aw_drive;
  assign s_aw_addr_o  = (w_state == 2'd0) ? aw_addr_i[w_g_idx*32 +: 32] : w_l_addr;
  assign s_w_valid_o  = w_drive;
  assign s_w_data_o   = (w_state == 2'd0) ? w_data_i[w_g_idx*32 +: 32] : w_l_data;
  assign s_w_strb_o   = (w_state == 2'd0) ? w_strb_i[w_g_idx*4  +: 4]  : w_l_strb;

  wire aw_acc = s_aw_valid_o && s_aw_ready_i;
  wire w_acc  = s_w_valid_o  && s_w_ready_i;

  wire [NM-1:0] w_front = w_own[w_rp*NM +: NM];
  wire w_front_v = (w_cnt != '0);
  assign b_valid_o = w_front & {NM{s_b_valid_i && w_front_v}};
  logic [2*NM-1:0] b_resp_c;
  always_comb begin
    b_resp_c = '0;
    for (int m = 0; m < NM; m++) begin
      b_resp_c[m*2 +: 2] = b_valid_o[m] ? s_b_resp_i : 2'b00;
    end
  end
  assign b_resp_o = b_resp_c;
  wire w_pop = w_front_v && s_b_valid_i && b_ready_i[oh2idx(w_front)];
  assign s_b_ready_o = w_front_v && b_ready_i[oh2idx(w_front)];

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      w_wp <= '0; w_rp <= '0; w_cnt <= '0; w_own <= '0;
      w_state <= 2'd0; w_rr <= '0;
      w_l_addr <= '0; w_l_data <= '0; w_l_strb <= '0;
      w_aw_acc_q <= 1'b0; w_w_acc_q <= 1'b0;
    end else begin
      if (w_pop) begin
        w_own[w_rp*NM +: NM] <= '0;
        w_rp <= (w_rp == PW'(PDEPTH-1)) ? '0 : w_rp + PW'(1);
      end
      if (w_start) begin
        w_own[w_wp*NM +: NM] <= w_grant;
        w_wp <= (w_wp == PW'(PDEPTH-1)) ? '0 : w_wp + PW'(1);
        w_rr     <= w_g_idx;
        w_l_addr <= aw_addr_i[w_g_idx*32 +: 32];
        w_l_data <= w_data_i[w_g_idx*32 +: 32];
        w_l_strb <= w_strb_i[w_g_idx*4 +: 4];
      end
      case ({w_pop, w_start})
        2'b10: w_cnt <= w_cnt - 1'b1;
        2'b01: w_cnt <= w_cnt + 1'b1;
        default: ;
      endcase
      if (w_state == 2'd0) begin
        if (w_start) begin
          w_aw_acc_q <= aw_acc;
          w_w_acc_q  <= w_acc;
          w_state    <= (aw_acc && w_acc) ? 2'd0 : 2'd1;
        end
      end else begin
        if (aw_acc) w_aw_acc_q <= 1'b1;
        if (w_acc)  w_w_acc_q  <= 1'b1;
        if (aw_acc && w_acc) w_state <= 2'd0;
      end
    end
  end

  logic [PW-1:0]        r_wp, r_rp;
  logic [PW:0]          r_cnt;
  logic [PDEPTH*NM-1:0] r_own;
  logic [1:0]           r_state;
  logic [WIDX-1:0]      r_rr;
  logic [31:0]          r_l_addr;
  logic                 r_ar_acc_q;

  wire r_room = ~r_cnt[PW];
  wire [NM-1:0] r_req_m = req_r_i & {NM{(r_state == 2'd0) && r_room}};
  wire [NM-1:0] r_grant  = rr_grant(r_req_m, r_rr);
  wire          r_start  = (|r_grant);
  wire [WIDX-1:0] r_g_idx = oh2idx(r_grant);

  assign g_ar_ready_o = r_grant;

  wire ar_drive = ((r_state == 2'd0) && r_start) ||
                  ((r_state == 2'd1) && !r_ar_acc_q);
  assign s_ar_valid_o = ar_drive;
  assign s_ar_addr_o  = (r_state == 2'd0) ? ar_addr_i[r_g_idx*32 +: 32] : r_l_addr;

  wire ar_acc = s_ar_valid_o && s_ar_ready_i;

  wire [NM-1:0] r_front = r_own[r_rp*NM +: NM];
  wire r_front_v = (r_cnt != '0);
  assign r_valid_o = r_front & {NM{s_r_valid_i && r_front_v}};
  logic [32*NM-1:0] r_data_c;
  logic [2*NM-1:0]  r_resp_c;
  always_comb begin
    r_data_c = '0;
    r_resp_c = '0;
    for (int m = 0; m < NM; m++) begin
      r_data_c[m*32 +: 32] = r_valid_o[m] ? s_r_data_i : 32'b0;
      r_resp_c[m*2 +: 2]   = r_valid_o[m] ? s_r_resp_i : 2'b00;
    end
  end
  assign r_data_o = r_data_c;
  assign r_resp_o = r_resp_c;
  wire r_pop = r_front_v && s_r_valid_i && r_ready_i[oh2idx(r_front)];
  assign s_r_ready_o = r_front_v && r_ready_i[oh2idx(r_front)];

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      r_wp <= '0; r_rp <= '0; r_cnt <= '0; r_own <= '0;
      r_state <= 2'd0; r_rr <= '0;
      r_l_addr <= '0; r_ar_acc_q <= 1'b0;
    end else begin
      if (r_pop) begin
        r_own[r_rp*NM +: NM] <= '0;
        r_rp <= (r_rp == PW'(PDEPTH-1)) ? '0 : r_rp + PW'(1);
      end
      if (r_start) begin
        r_own[r_wp*NM +: NM] <= r_grant;
        r_wp <= (r_wp == PW'(PDEPTH-1)) ? '0 : r_wp + PW'(1);
        r_rr     <= r_g_idx;
        r_l_addr <= ar_addr_i[r_g_idx*32 +: 32];
      end
      case ({r_pop, r_start})
        2'b10: r_cnt <= r_cnt - 1'b1;
        2'b01: r_cnt <= r_cnt + 1'b1;
        default: ;
      endcase
      if (r_state == 2'd0) begin
        if (r_start) begin
          r_ar_acc_q <= ar_acc;
          r_state    <= ar_acc ? 2'd0 : 2'd1;
        end
      end else begin
        if (ar_acc) begin
          r_state <= 2'd0;
        end
      end
    end
  end

endmodule
