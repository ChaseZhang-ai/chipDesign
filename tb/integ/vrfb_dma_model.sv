
`ifndef _AMECHIP_PKG_SV
 `include "amechip_pkg.sv"
`endif
`ifndef _SOC_PKG_SV
 `include "soc_pkg.sv"
`endif

module vrfb_dma_model (
  input logic clk,
  input logic rst_n,

  input  soc_pkg::soc_req_t  bus_req,
  output soc_pkg::soc_resp_t bus_resp,

  output soc_pkg::soc_req_t  m_req,
  input  soc_pkg::soc_resp_t m_resp,

  output logic evt_done_o,
  output logic evt_err_o,
  output logic busy_o
);

  logic [31:0] src_q, dst_q, xcnt_q, ycnt_q, spitch_q, dpitch_q;
  logic [4:0]  ctrl_q;            // {irqen, dstf, srcf, abort(unused latched), go}
  logic        busy_q, done_q, err_q;
  int          dbg_wait_cnt;
  logic [3:0]  errcode_q;

  assign busy_o = busy_q;
  reg DBG;
  initial if ($test$plusargs("DBG")) DBG = 1'b1; else DBG = 1'b0;

  localparam logic [2:0] S_IDLE = 3'd0, S_RD = 3'd1, S_WR = 3'd2, S_GAP = 3'd3, S_NEXT = 3'd4;
  logic [2:0]  st_q;
  logic        phase_q;
  logic [31:0] cur_s, cur_d;
  logic [31:0] line_s, line_d;
  logic [31:0] xleft_q, yleft_q;
  logic [31:0] rd_data_q;
  logic [31:0] eff_sp_q, eff_dp_q;

  logic        csr_v_q;
  logic [31:0] csr_d_q;
  logic [1:0]  csr_r_q;
  wire  [4:0]  off = bus_req.addr[4:2];

  localparam logic [1:0] M_IDLE = 2'd0, M_REQ = 2'd1, M_RSP = 2'd2, M_GAP = 2'd3;
  logic [1:0]  mst_q;
  logic        m_wr_q;
  logic [31:0] m_addr_q, m_wdat_q;
  logic [3:0]  m_strb_q;

  assign m_req.valid = (mst_q == M_REQ);
  assign m_req.write = m_wr_q;
  assign m_req.addr  = m_addr_q;
  assign m_req.wdata = m_wdat_q;
  assign m_req.wstrb = m_strb_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      src_q <= 0; dst_q <= 0; xcnt_q <= 0; ycnt_q <= 0;
      spitch_q <= 0; dpitch_q <= 0; ctrl_q <= 0;
      busy_q <= 0; done_q <= 0; err_q <= 0; errcode_q <= 0; dbg_wait_cnt <= 0;
      st_q <= S_IDLE; phase_q <= 0;
      cur_s <= 0; cur_d <= 0; line_s <= 0; line_d <= 0;
      xleft_q <= 0; yleft_q <= 0; rd_data_q <= 0;
      eff_sp_q <= 0; eff_dp_q <= 0;
      mst_q <= M_IDLE; m_wr_q <= 0; m_addr_q <= 0; m_wdat_q <= 0; m_strb_q <= 0;
    end else begin
      evt_done_o <= 1'b0;
      evt_err_o  <= 1'b0;

      if (DBG && (mst_q == M_REQ))
        $display("[DMA] t=%0t M_REQ addr=%08h wr=%b resp_v=%b resp_err=%b", $time,
                 m_addr_q, m_wr_q, m_resp.valid, m_resp.resp);
      if (DBG && busy_q) dbg_wait_cnt <= dbg_wait_cnt + 1;
      else               dbg_wait_cnt <= 0;
      if (DBG && dbg_wait_cnt == 500)
        $display("[DMA] STUCK st=%0d mst=%0d addr=%08h wr=%b xleft=%0d yleft=%0d",
                 st_q, mst_q, m_addr_q, m_wr_q, xleft_q, yleft_q);
      case (mst_q)
        M_IDLE: begin
          if (st_q == S_RD || st_q == S_WR) begin
            mst_q    <= M_REQ;
            m_wr_q   <= (st_q == S_WR);
            m_addr_q <= (st_q == S_RD) ? cur_s : cur_d;
            m_wdat_q <= rd_data_q;
            m_strb_q <= 4'hF;
          end
        end
        M_REQ: begin
          if (m_resp.valid) begin
            if (m_resp.resp != amechip_pkg::AXI_OKAY) begin
              err_q     <= 1'b1;
              errcode_q <= 4'd2;
              busy_q    <= 1'b0;
              st_q      <= S_IDLE;
              mst_q     <= M_GAP;
              evt_err_o <= ctrl_q[4];
            end else begin
              rd_data_q <= m_resp.rdata;
              mst_q     <= M_RSP;
            end
          end
        end
        M_RSP: begin
          mst_q <= M_GAP;
          if (st_q == S_RD) begin
            st_q <= S_WR;
          end else begin
            st_q <= S_NEXT;
          end
        end
        M_GAP: mst_q <= M_IDLE;
        default: mst_q <= M_IDLE;
      endcase

      if (st_q == S_NEXT) begin
        if (!ctrl_q[2]) cur_s <= cur_s + 32'd4;    // SRC_FIXED=ctrl[2]
        if (!ctrl_q[3]) cur_d <= cur_d + 32'd4;    // DST_FIXED=ctrl[3]
        if (xleft_q > 1) begin
          xleft_q <= xleft_q - 1;
          st_q    <= S_RD;
        end else begin
          xleft_q <= 0;
          if (yleft_q > 1) begin
            yleft_q <= yleft_q - 1;
            if (!ctrl_q[2]) begin
              line_s <= line_s + eff_sp_q;
              cur_s  <= line_s + eff_sp_q;
            end
            if (!ctrl_q[3]) begin
              line_d <= line_d + eff_dp_q;
              cur_d  <= line_d + eff_dp_q;
            end
            xleft_q <= xcnt_q;
            st_q    <= S_RD;
          end else begin
            busy_q    <= 1'b0;
            done_q    <= 1'b1;
            st_q      <= S_IDLE;
            evt_done_o <= ctrl_q[4];
          end
        end
      end

      if (bus_req.valid && !csr_v_q && bus_req.write) begin
        if (DBG) $display("[DMA] t=%0t wr off=%0d data=%08h busy=%b st=%0d",
                          $time, off, bus_req.wdata, busy_q, st_q);
        case (off)
          5'd0: if (!busy_q) src_q    <= bus_req.wdata;
          5'd1: if (!busy_q) dst_q    <= bus_req.wdata;
          5'd2: if (!busy_q) xcnt_q   <= bus_req.wdata;
          5'd3: if (!busy_q) ycnt_q   <= bus_req.wdata;
          5'd4: if (!busy_q) spitch_q <= bus_req.wdata;
          5'd5: if (!busy_q) dpitch_q <= bus_req.wdata;
          5'd6: begin
            if (bus_req.wdata[1] && busy_q) begin
              busy_q    <= 1'b0;
              err_q     <= 1'b1;
              errcode_q <= 4'd3;
              st_q      <= S_IDLE;
              mst_q     <= M_GAP;
              evt_err_o <= ctrl_q[4];
            end else if (!busy_q) begin
              ctrl_q <= bus_req.wdata[4:0];
              if (bus_req.wdata[0]) begin
                if ((src_q[1:0] != 2'b00) || (dst_q[1:0] != 2'b00) ||
                    (spitch_q[1:0] != 2'b00) || (dpitch_q[1:0] != 2'b00)) begin
                  err_q     <= 1'b1;
                  errcode_q <= 4'd1;
                  evt_err_o <= bus_req.wdata[4];
                end else if ((xcnt_q == 0) || (ycnt_q == 0)) begin
                  err_q     <= 1'b1;
                  errcode_q <= 4'd1;
                  evt_err_o <= bus_req.wdata[4];
                end else begin
                  busy_q  <= 1'b1;
                  done_q  <= 1'b0;
                  err_q   <= 1'b0;
                  errcode_q <= 4'd0;
                  cur_s   <= src_q;
                  cur_d   <= dst_q;
                  line_s  <= src_q;
                  line_d  <= dst_q;
                  xleft_q <= xcnt_q;
                  yleft_q <= ycnt_q;
                  eff_sp_q <= (spitch_q == 0) ? (xcnt_q << 2) : spitch_q;
                  eff_dp_q <= (dpitch_q == 0) ? (xcnt_q << 2) : dpitch_q;
                  st_q    <= S_RD;
                end
              end
            end
          end
          5'd7: begin
            if (bus_req.wdata[1]) done_q <= 1'b0;   // W1C
            if (bus_req.wdata[2]) err_q  <= 1'b0;
          end
          default: ;
        endcase
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      csr_v_q <= 1'b0;
      csr_d_q <= 32'd0;
      csr_r_q <= 2'b00;
    end else begin
      csr_v_q <= bus_req.valid && !csr_v_q;
      csr_d_q <= 32'd0;
      csr_r_q <= amechip_pkg::AXI_OKAY;
      if (bus_req.valid && !csr_v_q && !bus_req.write) begin
        case (off)
          5'd0: csr_d_q <= src_q;
          5'd1: csr_d_q <= dst_q;
          5'd2: csr_d_q <= xcnt_q;
          5'd3: csr_d_q <= ycnt_q;
          5'd4: csr_d_q <= spitch_q;
          5'd5: csr_d_q <= dpitch_q;
          5'd6: csr_d_q <= {27'd0, ctrl_q};
          5'd7: csr_d_q <= {24'd0, errcode_q, 1'b0, err_q, done_q, busy_q};
          default: csr_d_q <= 32'd0;
        endcase
      end
    end
  end

  assign bus_resp.valid = csr_v_q;
  assign bus_resp.rdata = csr_d_q;
  assign bus_resp.resp  = csr_r_q;

endmodule
