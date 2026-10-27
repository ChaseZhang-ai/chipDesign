`ifndef _AMECHIP_PKG_SV
 `include "amechip_pkg.sv"
`endif

module dma_engine #(
  parameter int unsigned FIFO_DEPTH = 8
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

  output logic        rd_ar_valid_o,
  input  logic        rd_ar_ready_i,
  output logic [31:0] rd_ar_addr_o,
  input  logic        rd_r_valid_i,
  output logic        rd_r_ready_o,
  input  logic [31:0] rd_r_data_i,
  input  logic [1:0]  rd_r_resp_i,

  output logic        wr_aw_valid_o,
  input  logic        wr_aw_ready_i,
  output logic [31:0] wr_aw_addr_o,
  output logic        wr_w_valid_o,
  input  logic        wr_w_ready_i,
  output logic [31:0] wr_w_data_o,
  output logic [3:0]  wr_w_strb_o,
  input  logic        wr_b_valid_i,
  output logic        wr_b_ready_o,
  input  logic [1:0]  wr_b_resp_i,

  output logic        irq_done_pulse_o,
  output logic        irq_err_pulse_o
);

  localparam int unsigned PW = $clog2(FIFO_DEPTH);
  localparam int unsigned RW = $clog2(FIFO_DEPTH + 1);
  localparam logic [5:2]  OFF_CTRL = 4'h6;  // DMA_CTRL_OFF   字偏移
  localparam logic [5:2]  OFF_STAT = 4'h7;  // DMA_STATUS_OFF 字偏移
  /* verilator lint_off WIDTHTRUNC */
  localparam logic [RW-1:0]  DEPTH_W  = FIFO_DEPTH;
  localparam logic [RW+1:0]  DEPTH_W2 = FIFO_DEPTH;
  /* verilator lint_on WIDTHTRUNC */

  logic [31:0] reg_src, reg_dst, reg_xcnt, reg_ycnt, reg_spitch, reg_dpitch;
  logic        reg_src_fix, reg_dst_fix, reg_irq_en;
  logic        busy_q, done_q, err_q, discard_q;
  logic [3:0]  errcode_q;

  logic [31:0] s_line_s, s_line_d, s_sp, s_dp, s_xcnt, s_ycnt;
  logic        s_sfix, s_dfix;

  logic [31:0] rd_x, rd_y, wr_x, wr_y;
  logic [RW-1:0] rd_inflight, wr_inflight;

  wire wr_gen_done = (wr_y == s_ycnt);
  wire drained     = (rd_inflight == '0) && (wr_inflight == '0);

  logic       csr_wr_busy, csr_rd_busy;
  logic [5:2] csr_waddr_q, csr_raddr_q;

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

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      csr_wr_busy <= 1'b0; csr_waddr_q <= '0;
      csr_rd_busy <= 1'b0; csr_raddr_q <= '0;
    end else begin
      if (csr_w_accept) begin
        csr_waddr_q <= w_off;
        csr_wr_busy <= 1'b1;
      end else if (csr_wr_busy && csr_b_ready_i) begin
        csr_wr_busy <= 1'b0;
      end
      if (csr_r_accept) begin
        csr_raddr_q <= csr_ar_addr_i[5:2];
        csr_rd_busy <= 1'b1;
      end else if (csr_rd_busy && csr_r_ready_i) begin
        csr_rd_busy <= 1'b0;
      end
    end
  end

  always_comb begin
    case (csr_raddr_q)
      4'h0:     csr_r_data_o = reg_src;
      4'h1:     csr_r_data_o = reg_dst;
      4'h2:     csr_r_data_o = reg_xcnt;
      4'h3:     csr_r_data_o = reg_ycnt;
      4'h4:     csr_r_data_o = reg_spitch;
      4'h5:     csr_r_data_o = reg_dpitch;
      4'h6:     csr_r_data_o = {27'b0, reg_irq_en, reg_dst_fix, reg_src_fix, 2'b00};
      4'h7:     csr_r_data_o = {24'b0, errcode_q, 1'b0, err_q, done_q, busy_q};
      default:  csr_r_data_o = 32'h0;
    endcase
  end

  logic [31:0]   fifo_mem [0:FIFO_DEPTH-1];
  logic [PW-1:0] fifo_wp, fifo_rp;
  logic [RW:0]   fifo_cnt;

  wire go_fire = csr_w_accept && !busy_q && (w_off == OFF_CTRL) && w_dat[0];

  wire [31:0] sp_eff = (reg_spitch != 32'b0) ? reg_spitch : (reg_xcnt << 2);
  wire [31:0] dp_eff = (reg_dpitch != 32'b0) ? reg_dpitch : (reg_xcnt << 2);
  wire go_bad = go_fire &&
                ((reg_src[1:0] != 2'b00) || (reg_dst[1:0] != 2'b00) ||
                 (sp_eff[1:0]  != 2'b00) || (dp_eff[1:0]  != 2'b00) ||
                 (reg_xcnt == 32'b0)     || (reg_ycnt == 32'b0));
  wire go_ok  = go_fire && !go_bad;

  wire [RW+1:0] rd_occupancy = (fifo_cnt + {2'b00, rd_inflight});
  wire rd_issue = busy_q && !discard_q && (rd_y != s_ycnt) &&
                  (rd_occupancy < DEPTH_W2); // fifo_cnt + inflight < DEPTH
  wire [31:0] rd_addr = s_sfix ? s_line_s : (s_line_s + {rd_x[29:0], 2'b00});

  logic rd_active_q;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)                       rd_active_q <= 1'b0;
    else if (rd_ar_acc)                rd_active_q <= 1'b0;
    else if (rd_issue && !discard_q)   rd_active_q <= 1'b1;
  end

  assign rd_ar_valid_o = (rd_issue && !discard_q) || rd_active_q;
  assign rd_ar_addr_o  = rd_addr;
  wire rd_ar_acc = rd_ar_valid_o && rd_ar_ready_i;

  assign rd_r_ready_o = 1'b1; // 始终接收(错误/丢弃时仅吞掉)
  wire rd_r_acc = rd_r_valid_i && rd_r_ready_o;

  wire rd_bus_err = rd_r_acc && !discard_q && (rd_r_resp_i != amechip_pkg::AXI_OKAY);

  wire wr_issue = busy_q && !discard_q && !wr_gen_done &&
                  (fifo_cnt != '0) && (wr_inflight != DEPTH_W);
  wire [31:0] wr_addr = s_dfix ? s_line_d : (s_line_d + {wr_x[29:0], 2'b00});

  assign wr_aw_valid_o = wr_issue;
  assign wr_aw_addr_o  = wr_addr;
  assign wr_w_valid_o  = wr_issue;
  assign wr_w_data_o   = fifo_mem[fifo_rp];
  assign wr_w_strb_o   = 4'b1111;
  wire wr_accept = wr_issue && wr_aw_ready_i && wr_w_ready_i;

  assign wr_b_ready_o = 1'b1;
  wire wr_b_acc = wr_b_valid_i && wr_b_ready_o;

  wire wr_bus_err = wr_b_acc && !discard_q && (wr_b_resp_i != amechip_pkg::AXI_OKAY);
  logic wr_last_q;
  wire wr_last_beat = wr_accept && (wr_x == s_xcnt - 32'd1) && (wr_y == s_ycnt - 32'd1);
  wire done_ev = wr_b_acc && !discard_q && !wr_bus_err && wr_last_q;

  wire err_ev = go_bad || (csr_w_accept && busy_q && (w_off == OFF_CTRL) && w_dat[1]) ||
                rd_bus_err || wr_bus_err;

  wire fifo_push_v = rd_r_acc && !discard_q && !rd_bus_err;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      reg_src <= '0; reg_dst <= '0; reg_xcnt <= '0; reg_ycnt <= '0;
      reg_spitch <= '0; reg_dpitch <= '0;
      reg_src_fix <= 1'b0; reg_dst_fix <= 1'b0; reg_irq_en <= 1'b0;
      busy_q <= 1'b0; done_q <= 1'b0; err_q <= 1'b0; discard_q <= 1'b0;
      errcode_q <= 4'h0;
      wr_last_q <= 1'b0;
      s_line_s <= '0; s_line_d <= '0; s_sp <= '0; s_dp <= '0;
      s_xcnt <= '0; s_ycnt <= '0; s_sfix <= 1'b0; s_dfix <= 1'b0;
      rd_x <= '0; rd_y <= '0; wr_x <= '0; wr_y <= '0;
      rd_inflight <= '0; wr_inflight <= '0;
      fifo_wp <= '0; fifo_rp <= '0; fifo_cnt <= '0;
      irq_done_pulse_o <= 1'b0; irq_err_pulse_o <= 1'b0;
    end else begin
      irq_done_pulse_o <= 1'b0;
      irq_err_pulse_o  <= 1'b0;

      if (csr_w_accept && !busy_q) begin
        case (w_off)
          4'h0: reg_src    <= w_dat;
          4'h1: reg_dst    <= w_dat;
          4'h2: reg_xcnt   <= w_dat;
          4'h3: reg_ycnt   <= w_dat;
          4'h4: reg_spitch <= w_dat;
          4'h5: reg_dpitch <= w_dat;
          4'h6: begin
            reg_src_fix <= w_dat[2];
            reg_dst_fix <= w_dat[3];
            reg_irq_en  <= w_dat[4];
          end
          4'h7: begin // STATUS W1C
            done_q <= done_q & ~w_dat[1];
            err_q  <= err_q  & ~w_dat[2];
          end
          default: ;
        endcase
      end
      if (go_ok) begin
        s_line_s <= reg_src;
        s_line_d <= reg_dst;
        s_sp     <= sp_eff;
        s_dp     <= dp_eff;
        s_xcnt   <= reg_xcnt;
        s_ycnt   <= reg_ycnt;
        s_sfix   <= reg_src_fix;
        s_dfix   <= reg_dst_fix;
        rd_x <= '0; rd_y <= '0; wr_x <= '0; wr_y <= '0;
        busy_q <= 1'b1;
      end

      if (rd_ar_acc) begin
        if (rd_x == s_xcnt - 32'd1) begin
          rd_x     <= '0;
          rd_y     <= rd_y + 32'd1;
          s_line_s <= s_sfix ? s_line_s : (s_line_s + s_sp);
        end else begin
          rd_x <= rd_x + 32'd1;
        end
      end

      if (wr_accept) begin
        if (wr_x == s_xcnt - 32'd1) begin
          wr_x     <= '0;
          wr_y     <= wr_y + 32'd1;
          s_line_d <= s_dfix ? s_line_d : (s_line_d + s_dp);
        end else begin
          wr_x <= wr_x + 32'd1;
        end
      end

      rd_inflight <= rd_inflight
                   + {{(RW-1){1'b0}}, rd_ar_acc}
                   - {{(RW-1){1'b0}}, rd_r_acc};
      wr_inflight <= wr_inflight
                   + {{(RW-1){1'b0}}, wr_accept}
                   - {{(RW-1){1'b0}}, wr_b_acc};

      if (err_ev || done_ev) wr_last_q <= 1'b0;
      else if (wr_last_beat) wr_last_q <= 1'b1;

      if (fifo_push_v) begin
        fifo_mem[fifo_wp] <= rd_r_data_i;
        fifo_wp <= (fifo_wp == PW'(FIFO_DEPTH-1)) ? '0 : fifo_wp + PW'(1);
      end
      if (wr_accept) begin
        fifo_rp <= (fifo_rp == PW'(FIFO_DEPTH-1)) ? '0 : fifo_rp + PW'(1);
      end

      if (done_ev) begin
        done_q <= 1'b1;
        busy_q <= 1'b0;
        irq_done_pulse_o <= reg_irq_en;
      end
      if (err_ev) begin
        err_q     <= 1'b1;
        discard_q <= 1'b1;
        irq_err_pulse_o <= reg_irq_en;
        if (go_bad)        errcode_q <= amechip_pkg::DMA_ERR_ALIGN;
        else if (csr_w_accept && busy_q && (w_off == OFF_CTRL) && w_dat[1])
                           errcode_q <= amechip_pkg::DMA_ERR_ABORT;
        else               errcode_q <= amechip_pkg::DMA_ERR_BUS;
        fifo_wp <= '0; fifo_rp <= '0; fifo_cnt <= '0; // 丢弃在途数据
      end

      if (discard_q && drained) begin
        discard_q <= 1'b0;
        busy_q    <= 1'b0;
      end

      if (!err_ev) begin
        case ({fifo_push_v, wr_accept})
          2'b10: fifo_cnt <= fifo_cnt + 1'b1;
          2'b01: fifo_cnt <= fifo_cnt - 1'b1;
          default: ;
        endcase
      end
    end
  end

  initial begin
    if (FIFO_DEPTH < 4) begin
      $display("dma_engine: FIFO_DEPTH 必须 ≥4(ARCH_SPEC §3)");
      $finish;
    end
  end

endmodule
