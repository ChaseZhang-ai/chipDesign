`ifndef _MEMC_XMEM_DW32_SV
`define _MEMC_XMEM_DW32_SV

module memc_xmem_dw32 #(
  parameter int unsigned AW = 23,
  parameter int unsigned WS = 0
) (
  input  logic          clk_i,
  input  logic          rst_ni,

  input  logic        aw_valid_i,
  output logic        aw_ready_o,
  input  logic [31:0] aw_addr_i,
  input  logic        w_valid_i,
  output logic        w_ready_o,
  input  logic [31:0] w_data_i,
  input  logic [3:0]  w_strb_i,
  output logic        b_valid_o,
  input  logic        b_ready_i,
  output logic [1:0]  b_resp_o,
  input  logic        ar_valid_i,
  output logic        ar_ready_o,
  input  logic [31:0] ar_addr_i,
  output logic        r_valid_o,
  input  logic        r_ready_i,
  output logic [31:0] r_data_o,
  output logic [1:0]  r_resp_o,

  output logic          xmem_clk_o,
  output logic [AW-1:0] xmem_a_o,
  input  logic [31:0]   xmem_di_i,
  output logic [31:0]   xmem_do_o,
  output logic          xmem_ce_no,
  output logic          xmem_oe_no,
  output logic          xmem_we_no,
  input  logic          xmem_wait_i
);

  localparam logic [2:0] WS_L = WS;

  logic [AW-1:0]  wq_addr [0:3];
  logic [31:0]    wq_data [0:3];
  logic [1:0]     wq_wp, wq_rp;
  logic [2:0]     wq_cnt;

  logic [AW-1:0]  rq_addr [0:3];
  logic [1:0]     rq_wp, rq_rp;
  logic [2:0]     rq_cnt;

  wire w_push = aw_valid_i && w_valid_i && (wq_cnt < 4);
  assign aw_ready_o = (wq_cnt < 4);
  assign w_ready_o  = (wq_cnt < 4);
  wire r_push = ar_valid_i && (rq_cnt < 4);
  assign ar_ready_o = (rq_cnt < 4);

  localparam logic [1:0] S_IDLE = 2'd0, S_W = 2'd1, S_WB = 2'd2, S_R = 2'd3;
  logic [1:0] st_q;
  logic [2:0] ws_cnt;
  logic       b_pend_q;

  wire stall   = xmem_wait_i;
  wire ws_hold = stall || (ws_cnt != 3'd0);

  logic last_wr_q;
  assign b_valid_o = (st_q == S_WB) && b_pend_q;
  assign b_resp_o  = amechip_pkg::AXI_OKAY;
  wire b_done = b_valid_o && b_ready_i;

  assign r_valid_o = (st_q == S_R);
  assign r_data_o  = xmem_di_i;
  assign r_resp_o  = amechip_pkg::AXI_OKAY;
  wire r_done = r_valid_o && r_ready_i;

  wire [AW-1:0] w_head_a = wq_addr[wq_rp];
  wire [31:0]   w_head_d = wq_data[wq_rp];
  wire [AW-1:0] r_head_a = rq_addr[rq_rp];

  assign xmem_clk_o = clk_i;
  always_comb begin
    xmem_a_o   = {AW{1'b0}};
    xmem_do_o  = 32'h0;
    xmem_ce_no = 1'b1;
    xmem_oe_no = 1'b1;
    xmem_we_no = 1'b1;
    case (st_q)
      S_W: begin xmem_a_o = w_head_a; xmem_do_o = w_head_d;
                 xmem_ce_no = 1'b0; xmem_we_no = 1'b0; end
      S_R: begin xmem_a_o = r_head_a;
                 xmem_ce_no = 1'b0; xmem_oe_no = 1'b0; end
      default: ;
    endcase
  end

  wire w_pop = (st_q == S_W) && !ws_hold;
  wire r_pop = (st_q == S_R) && r_done;
  wire [2:0] rq_next = rq_cnt + (r_push ? 3'd1 : 3'd0) - (r_pop ? 3'd1 : 3'd0);
  wire start_rd_sel = (rq_cnt != 3'd0) && ((wq_cnt == 3'd0) || last_wr_q);
  wire start_wr_sel = (wq_cnt != 3'd0) && !start_rd_sel;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      wq_wp <= '0; wq_rp <= '0; wq_cnt <= '0;
      rq_wp <= '0; rq_rp <= '0; rq_cnt <= '0;
      st_q <= S_IDLE; ws_cnt <= '0; b_pend_q <= 1'b0; last_wr_q <= 1'b0;
    end else begin
      if (w_push) begin
        wq_addr[wq_wp] <= aw_addr_i[AW-1:0];
        wq_data[wq_wp] <= w_data_i;
        wq_wp <= wq_wp + 2'd1;
      end
      if (r_push) begin
        rq_addr[rq_wp] <= ar_addr_i[AW-1:0];
        rq_wp <= rq_wp + 2'd1;
      end
      if (w_pop) wq_rp <= wq_rp + 2'd1;
      if (r_pop) rq_rp <= rq_rp + 2'd1;
      case ({w_push, w_pop})
        2'b10: wq_cnt <= wq_cnt + 3'd1;
        2'b01: wq_cnt <= wq_cnt - 3'd1;
        default: ;
      endcase
      case ({r_push, r_pop})
        2'b10: rq_cnt <= rq_cnt + 3'd1;
        2'b01: rq_cnt <= rq_cnt - 3'd1;
        default: ;
      endcase

      if (stall) begin
      end else if (ws_cnt != 3'd0) begin
        ws_cnt <= ws_cnt - 3'd1;
      end else begin
        case (st_q)
          S_IDLE: begin
            if (start_wr_sel) begin
              st_q <= S_W; ws_cnt <= WS_L; last_wr_q <= 1'b1;
            end else if (start_rd_sel) begin
              st_q <= S_R; ws_cnt <= WS_L; last_wr_q <= 1'b0;
            end
          end
          S_W: begin
            b_pend_q <= 1'b1;
            st_q     <= S_WB;
          end
          S_WB: begin
            if (b_done) begin
              b_pend_q <= 1'b0;
              if (rq_cnt != 3'd0) begin
                st_q <= S_R; ws_cnt <= WS_L; last_wr_q <= 1'b0;
              end else if (wq_cnt != 3'd0) begin
                st_q <= S_W; ws_cnt <= WS_L; last_wr_q <= 1'b1;
              end else begin
                st_q <= S_IDLE; ws_cnt <= 3'd0;
              end
            end
          end
          S_R: begin
            if (r_done) begin
              if (wq_cnt != 3'd0) begin
                st_q <= S_W; ws_cnt <= WS_L; last_wr_q <= 1'b1;
              end else if (rq_next != 3'd0) begin
                st_q <= S_R; ws_cnt <= WS_L; last_wr_q <= 1'b0;
              end else begin
                st_q <= S_IDLE; ws_cnt <= 3'd0;
              end
            end
          end
          default: st_q <= S_IDLE;
        endcase
      end
    end
  end

  logic _unused;
  assign _unused = ^{w_strb_i};

endmodule

`endif // _MEMC_XMEM_DW32_SV
