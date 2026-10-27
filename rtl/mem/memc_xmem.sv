`ifndef _AMECHIP_PKG_SV
 `include "amechip_pkg.sv"
`endif

module memc_xmem #(
  parameter int unsigned AW = 23, // 字节地址引脚宽
  parameter int unsigned WS = 0   // 每半字附加等待拍
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

  output logic          xmem_clk_o,   // = clk_i 直通
  output logic [AW-1:0] xmem_a_o,     // 字节地址
  input  logic [15:0]   xmem_di_i,
  output logic [15:0]   xmem_do_o,
  output logic          xmem_ce_no,
  output logic          xmem_oe_no,
  output logic          xmem_we_no,
  input  logic          xmem_wait_i
);

  /* verilator lint_off WIDTHTRUNC */
  localparam logic [2:0] WS_L = WS; // 每半字附加等待拍
  /* verilator lint_on WIDTHTRUNC */

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

  localparam logic [2:0] S_IDLE = 3'd0, S_W0 = 3'd1, S_W1 = 3'd2, S_WB = 3'd3,
                         S_R0 = 3'd4, S_R1 = 3'd5, S_RV = 3'd6;
  logic [2:0]  st_q;
  logic [2:0]  ws_cnt;
  logic [15:0] hw0_q;      // 读低半字缓存
  logic        b_pend_q;   // 上一笔写 B 待交付

  wire stall = xmem_wait_i;
  wire ws_hold = stall || (ws_cnt != 3'd0);

  wire wq_v = (wq_cnt != 3'd0);
  wire rq_v = (rq_cnt != 3'd0);

  logic last_wr_q;
  assign b_valid_o = (st_q == S_WB) && b_pend_q;
  assign b_resp_o  = amechip_pkg::AXI_OKAY;
  wire b_done = b_valid_o && b_ready_i;

  assign r_valid_o = (st_q == S_RV);
  assign r_data_o  = {xmem_di_i, hw0_q}; // 高半字当拍在 DQ 上
  assign r_resp_o  = amechip_pkg::AXI_OKAY;
  wire r_done = r_valid_o && r_ready_i;
  wire rv_next_rd = (rq_next != 3'd0) && (wq_cnt == 3'd0);

  wire [AW-1:0] w_head_a  = wq_addr[wq_rp];
  wire [1:0]    rq_rp_nx  = rq_rp + 2'd1;
  wire          rq_nx_pushing = r_push && (rq_rp_nx == rq_wp);
  wire [AW-1:0] r_next_a  = rq_nx_pushing ? ar_addr_i[AW-1:0] : rq_addr[rq_rp_nx];
  wire [31:0]   w_head_d  = wq_data[wq_rp];
  wire [15:0]   w_head_lo = w_head_d[15:0];
  wire [15:0]   w_head_hi = w_head_d[31:16];
  wire [AW-1:0] w_head_a2 = w_head_a + {{(AW-2){1'b0}}, 2'd2};
  wire [AW-1:0] r_head_a  = rq_addr[rq_rp];
  wire [AW-1:0] r_head_a2 = r_head_a + {{(AW-2){1'b0}}, 2'd2};

  assign xmem_clk_o = clk_i;
  always_comb begin
    xmem_a_o   = {AW{1'b0}};
    xmem_do_o  = 16'h0;
    xmem_ce_no = 1'b1;
    xmem_oe_no = 1'b1;
    xmem_we_no = 1'b1;
    case (st_q)
      S_W0: begin xmem_a_o = w_head_a;        xmem_do_o = w_head_lo;
                  xmem_ce_no = 1'b0; xmem_we_no = 1'b0; end
      S_W1: begin xmem_a_o = w_head_a2;       xmem_do_o = w_head_hi;
                  xmem_ce_no = 1'b0; xmem_we_no = 1'b0; end
      S_R0: begin xmem_a_o = r_head_a;
                  xmem_ce_no = 1'b0; xmem_oe_no = 1'b0; end
      S_R1: begin xmem_a_o = r_head_a2;
                  xmem_ce_no = 1'b0; xmem_oe_no = 1'b0; end
      S_RV: begin
        if (rv_next_rd) begin // 预驱下一读行首地址(与 RVAL 重叠)
          xmem_a_o = r_next_a;
          xmem_ce_no = 1'b0; xmem_oe_no = 1'b0;
        end
      end
      default: ;
    endcase
  end

  wire w_pop = (st_q == S_W1) && !ws_hold; // 第二半字已驱动(器件将锁存)
  wire r_pop = (st_q == S_RV) && r_done;
  wire [2:0] rq_next = rq_cnt + (r_push ? 3'd1 : 3'd0) - (r_pop ? 3'd1 : 3'd0);
  wire start_rd_sel = (rq_cnt != 3'd0) && ((wq_cnt == 3'd0) || last_wr_q);
  wire start_wr_sel = (wq_cnt != 3'd0) && !start_rd_sel;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      wq_wp <= '0; wq_rp <= '0; wq_cnt <= '0;
      rq_wp <= '0; rq_rp <= '0; rq_cnt <= '0;
      st_q <= S_IDLE; ws_cnt <= '0; hw0_q <= '0; b_pend_q <= 1'b0;
      last_wr_q <= 1'b0;
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
              st_q <= S_W0; ws_cnt <= WS_L; last_wr_q <= 1'b1;
            end else if (start_rd_sel) begin
              st_q <= S_R0; ws_cnt <= WS_L; last_wr_q <= 1'b0;
            end
          end
          S_W0: begin st_q <= S_W1; ws_cnt <= WS_L; end
          S_W1: begin
            b_pend_q <= 1'b1; // 本笔写完成,交 B
            st_q     <= S_WB;
          end
          S_WB: begin
            if (b_done) begin
              b_pend_q <= 1'b0;
              if (rq_cnt != 3'd0) begin
                st_q <= S_R0; ws_cnt <= WS_L; last_wr_q <= 1'b0;
              end else if (wq_cnt != 3'd0) begin
                st_q <= S_W0; ws_cnt <= WS_L; last_wr_q <= 1'b1;
              end else begin
                st_q <= S_IDLE; ws_cnt <= 3'd0;
              end
            end
          end
          S_R0: begin st_q <= S_R1; ws_cnt <= WS_L; end
          S_R1: begin
            hw0_q <= xmem_di_i; // 低半字当拍在 DQ 上
            st_q  <= S_RV;
          end
          S_RV: begin
            if (r_done) begin
              if (wq_cnt != 3'd0) begin
                st_q <= S_W0; ws_cnt <= WS_L; last_wr_q <= 1'b1;
              end else if (rq_next != 3'd0) begin
                st_q <= S_R1; ws_cnt <= WS_L; last_wr_q <= 1'b0;
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
