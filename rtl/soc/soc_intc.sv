
module soc_intc (
  input  logic               clk,
  input  logic               rst_n,

  input  soc_pkg::soc_req_t  bus_req,
  output soc_pkg::soc_resp_t bus_resp,

  input  logic               lvl_uart_tx_i,
  input  logic               lvl_uart_rx_i,
  input  logic               evt_dma_done_i,
  input  logic               evt_dma_err_i,
  input  logic               evt_ame_done_i,
  input  logic               evt_ame_err_i,
  input  logic               evt_kv_done_i,
  input  logic               evt_kv_err_i,
  input  logic               evt_buserr_i,
  input  logic               soft_set_i,
  input  logic               soft_clear_i,

  output logic               irq_o
);

  logic [31:0] en_q;
  logic [31:0] pend_latch_q;
  logic        resp_vld_q;
  logic [31:0] resp_dat_q;
  logic [1:0]  resp_err_q;

  logic [31:0] pending_c;
  always @* begin
    pending_c       = pend_latch_q;
    pending_c[0]    = lvl_uart_tx_i;
    pending_c[1]    = lvl_uart_rx_i;
  end

  wire       req_fire = bus_req.valid && !resp_vld_q;
  wire [4:0] aoff     = bus_req.addr[4:0];
  wire       wr_en    = req_fire && bus_req.write;

  logic [31:0] rd_data_c;
  always @* begin
    case (aoff)
      amechip_pkg::INTC_EN_OFF[4:0]:     rd_data_c = en_q;
      amechip_pkg::INTC_PEND_OFF[4:0]:   rd_data_c = pending_c;
      amechip_pkg::INTC_CLEAR_OFF[4:0]:  rd_data_c = 32'd0;
      amechip_pkg::INTC_SET_OFF[4:0]:    rd_data_c = 32'd0;
      default:                           rd_data_c = 32'd0;
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      en_q          <= 32'd0;
      pend_latch_q  <= 32'd0;
      resp_vld_q    <= 1'b0;
      resp_dat_q    <= 32'd0;
      resp_err_q    <= 2'b00;
    end else begin
      resp_vld_q <= 1'b0;
      resp_dat_q <= 32'd0;
      resp_err_q <= 2'b00;

      if (evt_dma_done_i) pend_latch_q[amechip_pkg::IRQ_DMA_DONE] <= 1'b1;
      if (evt_dma_err_i)  pend_latch_q[amechip_pkg::IRQ_DMA_ERR]  <= 1'b1;
      if (evt_ame_done_i) pend_latch_q[amechip_pkg::IRQ_AME_DONE] <= 1'b1;
      if (evt_ame_err_i)  pend_latch_q[amechip_pkg::IRQ_AME_ERR]  <= 1'b1;
      if (evt_kv_done_i)  pend_latch_q[amechip_pkg::IRQ_KV_DONE]  <= 1'b1;
      if (evt_kv_err_i)   pend_latch_q[amechip_pkg::IRQ_KV_ERR]   <= 1'b1;
      if (evt_buserr_i)   pend_latch_q[amechip_pkg::IRQ_BUSERR]   <= 1'b1;
      if (soft_set_i)     pend_latch_q[amechip_pkg::IRQ_SOFT]     <= 1'b1;
      if (soft_clear_i)   pend_latch_q[amechip_pkg::IRQ_SOFT]     <= 1'b0;

      if (req_fire && wr_en) begin
        case (aoff)
          amechip_pkg::INTC_EN_OFF[4:0]:    en_q <= bus_req.wdata;
          amechip_pkg::INTC_CLEAR_OFF[4:0]: begin
            pend_latch_q <= pend_latch_q & ~bus_req.wdata;
          end
          amechip_pkg::INTC_SET_OFF[4:0]:   pend_latch_q <= pend_latch_q | bus_req.wdata;
          default:                          resp_err_q <= amechip_pkg::AXI_SLVERR;
        endcase
      end
      if (req_fire) begin
        resp_vld_q <= 1'b1;
        if (!bus_req.write) resp_dat_q <= rd_data_c;
      end
    end
  end

  assign bus_resp.valid = resp_vld_q;
  assign bus_resp.rdata = resp_dat_q;
  assign bus_resp.resp  = resp_err_q;

  assign irq_o = |(en_q & pending_c);

endmodule
