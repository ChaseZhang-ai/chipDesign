
module stub_dma (
  input  logic clk,
  input  logic rst_n,

  input  soc_pkg::soc_req_t  csr_req,
  output soc_pkg::soc_resp_t csr_resp,

  output soc_pkg::soc_req_t  rd_req,
  input  soc_pkg::soc_resp_t rd_resp,
  output soc_pkg::soc_req_t  wr_req,
  input  soc_pkg::soc_resp_t wr_resp,

  output logic               busy_o,
  output logic               evt_done_o,   // 已按 CTRL.IRQ_EN 门控
  output logic               evt_err_o
);

  logic [31:0] src_q, dst_q, xcnt_q, ycnt_q, spitch_q, dpitch_q, ctrl_q;
  logic        st_busy_q, st_done_q, st_err_q;
  logic [3:0]  st_errcode_q;

  typedef enum logic [1:0] { ENG_IDLE, ENG_RD, ENG_WR } eng_e;
  eng_e eng;
  logic [31:0] cur_s, cur_d;
  logic [31:0] x_left, y_left;
  logic [31:0] sp_eff, dp_eff;
  logic [31:0] wr_data_q;
  logic        fix_s, fix_d;

  wire       req_fire = csr_req.valid && !resp_vld_q;
  wire [4:0] aoff     = csr_req.addr[4:0];
  wire       wr_en    = req_fire && csr_req.write;
  wire       go_pulse   = wr_en && !st_busy_q && aoff == amechip_pkg::DMA_CTRL_OFF[4:0] && csr_req.wdata[0];
  wire       abort_pulse = wr_en && aoff == amechip_pkg::DMA_CTRL_OFF[4:0] && csr_req.wdata[1];

  wire rd_fire = (eng == ENG_RD) && rd_req.valid && rd_resp.valid;
  wire wr_fire = (eng == ENG_WR) && wr_req.valid && wr_resp.valid;

  always_comb begin
    rd_req.valid  = (eng == ENG_RD);
    rd_req.write  = 1'b0;
    rd_req.addr   = cur_s;
    rd_req.wdata  = 32'd0;
    rd_req.wstrb  = 4'd0;
    wr_req.valid  = (eng == ENG_WR);
    wr_req.write  = 1'b1;
    wr_req.addr   = cur_d;
    wr_req.wdata  = wr_data_q;
    wr_req.wstrb  = 4'hF;
  end

  wire done_pulse = wr_fire && (wr_resp.resp == amechip_pkg::AXI_OKAY)
                 && (x_left == 32'd1) && (y_left == 32'd1);
  wire err_pulse  = (rd_fire && (rd_resp.resp != amechip_pkg::AXI_OKAY))
                 || (wr_fire && (wr_resp.resp != amechip_pkg::AXI_OKAY));

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      eng <= ENG_IDLE; cur_s <= 0; cur_d <= 0; x_left <= 0; y_left <= 0;
      sp_eff <= 0; dp_eff <= 0; wr_data_q <= 0; fix_s <= 0; fix_d <= 0;
      st_busy_q <= 0; st_done_q <= 0; st_err_q <= 0; st_errcode_q <= 4'd0;
      src_q <= 0; dst_q <= 0; xcnt_q <= 0; ycnt_q <= 0;
      spitch_q <= 0; dpitch_q <= 0; ctrl_q <= 0;
    end else begin
      if (abort_pulse && (st_busy_q || eng != ENG_IDLE)) begin
        eng          <= ENG_IDLE;
        st_busy_q    <= 1'b0;
        st_err_q     <= 1'b1;
        st_errcode_q <= 4'd3;                       // ABORT
      end else begin
        case (eng)
          ENG_IDLE: begin
            if (go_pulse) begin
              st_done_q    <= 1'b0;
              st_err_q     <= 1'b0;
              st_errcode_q <= 4'd0;
              if ((src_q[1:0] != 2'b00) || (dst_q[1:0] != 2'b00)) begin
                st_err_q     <= 1'b1;               // 对齐错:不启动
                st_errcode_q <= 4'd1;
              end else if (xcnt_q == 0 || ycnt_q == 0) begin
                st_err_q     <= 1'b1;
                st_errcode_q <= 4'd1;
              end else begin
                st_busy_q <= 1'b1;
                cur_s     <= src_q;
                cur_d     <= dst_q;
                x_left    <= xcnt_q;
                y_left    <= ycnt_q;
                sp_eff    <= (spitch_q != 0) ? spitch_q : xcnt_q * 4;
                dp_eff    <= (dpitch_q != 0) ? dpitch_q : xcnt_q * 4;
                fix_s     <= ctrl_q[2];
                fix_d     <= ctrl_q[3];
                eng       <= ENG_RD;
              end
            end
          end
          ENG_RD: begin
            if (rd_fire) begin
              if (rd_resp.resp != amechip_pkg::AXI_OKAY) begin
                eng          <= ENG_IDLE;
                st_busy_q    <= 1'b0;
                st_err_q     <= 1'b1;
                st_errcode_q <= 4'd2;               // 总线错
              end else begin
                wr_data_q <= rd_resp.rdata;
                eng       <= ENG_WR;
              end
            end
          end
          ENG_WR: begin
            if (wr_fire) begin
              if (wr_resp.resp != amechip_pkg::AXI_OKAY) begin
                eng          <= ENG_IDLE;
                st_busy_q    <= 1'b0;
                st_err_q     <= 1'b1;
                st_errcode_q <= 4'd2;
              end else begin
                cur_s  <= fix_s ? cur_s : cur_s + 4;
                cur_d  <= fix_d ? cur_d : cur_d + 4;
                x_left <= x_left - 1;
                if (x_left == 32'd1) begin
                  if (y_left == 32'd1) begin
                    eng       <= ENG_IDLE;
                    st_busy_q <= 1'b0;
                    st_done_q <= 1'b1;              // 完成
                  end else begin
                    y_left <= y_left - 1;
                    x_left <= xcnt_q;
                    cur_s  <= fix_s ? cur_s : cur_s + sp_eff - (xcnt_q - 1) * 4;
                    cur_d  <= fix_d ? cur_d : cur_d + dp_eff - (xcnt_q - 1) * 4;
                    eng    <= ENG_RD;
                  end
                end else begin
                  eng <= ENG_RD;
                end
              end
            end
          end
          default: eng <= ENG_IDLE;
        endcase
      end

      if (req_fire) begin
        if (wr_en) begin
          if (!st_busy_q) begin
            case (aoff)
              amechip_pkg::DMA_SRC_OFF[4:0]:    src_q    <= csr_req.wdata;
              amechip_pkg::DMA_DST_OFF[4:0]:    dst_q    <= csr_req.wdata;
              amechip_pkg::DMA_XCNT_OFF[4:0]:   xcnt_q   <= csr_req.wdata;
              amechip_pkg::DMA_YCNT_OFF[4:0]:   ycnt_q   <= csr_req.wdata;
              amechip_pkg::DMA_SPITCH_OFF[4:0]: spitch_q <= csr_req.wdata;
              amechip_pkg::DMA_DPITCH_OFF[4:0]: dpitch_q <= csr_req.wdata;
              amechip_pkg::DMA_CTRL_OFF[4:0]:   ctrl_q[3:1] <= csr_req.wdata[3:1];
              amechip_pkg::DMA_STATUS_OFF[4:0]: begin      // W1C
                if (csr_req.wdata[1]) st_done_q <= 1'b0;
                if (csr_req.wdata[2]) st_err_q  <= 1'b0;
              end
              default: ;
            endcase
          end else if (aoff == amechip_pkg::DMA_STATUS_OFF[4:0]) begin
            if (csr_req.wdata[1]) st_done_q <= 1'b0;     // DONE/ERR 的 W1C 随时可清
            if (csr_req.wdata[2]) st_err_q  <= 1'b0;
          end
        end
      end
    end
  end

  logic        resp_vld_q;
  logic [31:0] resp_dat_q;
  logic [1:0]  resp_err_q;

  logic [31:0] rd_data_c;
  always @* begin
    case (aoff)
      amechip_pkg::DMA_SRC_OFF[4:0]:    rd_data_c = src_q;
      amechip_pkg::DMA_DST_OFF[4:0]:    rd_data_c = dst_q;
      amechip_pkg::DMA_XCNT_OFF[4:0]:   rd_data_c = xcnt_q;
      amechip_pkg::DMA_YCNT_OFF[4:0]:   rd_data_c = ycnt_q;
      amechip_pkg::DMA_SPITCH_OFF[4:0]: rd_data_c = spitch_q;
      amechip_pkg::DMA_DPITCH_OFF[4:0]: rd_data_c = dpitch_q;
      amechip_pkg::DMA_CTRL_OFF[4:0]:   rd_data_c = ctrl_q & 32'hFFFF_FFFE; // GO 读 0
      amechip_pkg::DMA_STATUS_OFF[4:0]: rd_data_c = {24'd0, st_errcode_q, 1'b0,
                                            st_err_q, st_done_q, st_busy_q};
      default:                          rd_data_c = 32'd0;
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      resp_vld_q <= 1'b0; resp_dat_q <= 32'd0; resp_err_q <= 2'b00;
    end else begin
      resp_vld_q <= 1'b0; resp_dat_q <= 32'd0; resp_err_q <= 2'b00;
      if (req_fire) begin
        resp_vld_q <= 1'b1;
        if (!wr_en) resp_dat_q <= rd_data_c;
      end
    end
  end

  assign csr_resp.valid = resp_vld_q;
  assign csr_resp.rdata = resp_dat_q;
  assign csr_resp.resp  = resp_err_q;

  assign busy_o     = st_busy_q;
  assign evt_done_o = done_pulse && ctrl_q[4];
  assign evt_err_o  = err_pulse  && ctrl_q[4];

endmodule
