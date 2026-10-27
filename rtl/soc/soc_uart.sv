
module soc_uart #(
  parameter int unsigned FIFO_DEPTH = amechip_pkg::UART_FIFO_DEPTH, // 16
  parameter int unsigned DIV_RESET  = amechip_pkg::UART_DIV_RESET   // 1042
) (
  input  logic                  clk,
  input  logic                  rst_n,

  input  soc_pkg::soc_req_t     bus_req,
  output soc_pkg::soc_resp_t    bus_resp,

  output logic                  tx_o,
  input  logic                  rx_i,

  output logic                  irq_tx_o,
  output logic                  irq_rx_o
);

  logic [31:0] div_q;
  logic [7:0]  ctrl_q;
  logic        stat_ovrun_q;
  wire  [3:0]  tx_wm = ctrl_q[7:4];

  logic        resp_vld_q;
  logic [31:0] resp_dat_q;
  logic [1:0]  resp_err_q;

  logic [7:0]  tfifo [0:FIFO_DEPTH-1];
  logic [4:0]  tcount;
  logic [3:0]  twptr, trptr;
  wire  tx_full  = (tcount == FIFO_DEPTH);
  wire  tx_empty = (tcount == 0);

  logic [9:0]  tx_shift;
  logic [3:0]  tx_bitcnt;
  logic [31:0] tx_baudcnt;
  logic        tx_busy;
  wire  tx_pop      = !tx_empty && !tx_busy;
  wire  tx_push_req = bus_req.valid && !resp_vld_q && bus_req.write
                   && bus_req.addr[4:0] == amechip_pkg::UART_TXDATA_OFF[4:0];
  wire  tx_push     = tx_push_req && (tcount + {{4{1'b0}}, tx_pop} < FIFO_DEPTH);
  wire  tx_ovrun    = tx_push_req && !tx_push;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      tcount <= 5'd0; twptr <= 4'd0; trptr <= 4'd0;
      tx_shift <= 10'h3FF; tx_bitcnt <= 4'd0; tx_baudcnt <= 32'd0; tx_busy <= 1'b0;
    end else begin
      if (tx_push) begin
        tfifo[twptr] <= bus_req.wdata[7:0];
        twptr <= twptr + 4'd1;
      end
      if (tx_ovrun) begin
        stat_ovrun_q <= 1'b1;
      end
      if (tx_pop) begin
        trptr  <= trptr + 4'd1;
        tcount <= tcount + {{4{1'b0}}, tx_push} - {{4{1'b0}}, 1'b1};
      end else if (tx_push) begin
        tcount <= tcount + 5'd1;
      end
      if (tx_pop) begin
        tx_shift   <= {1'b1, tfifo[trptr], 1'b0};
        tx_busy    <= 1'b1;
        tx_bitcnt  <= 4'd0;
        tx_baudcnt <= 32'd0;
      end else if (tx_busy && div_q != 0) begin
        if (tx_baudcnt == div_q - 1) begin
          tx_baudcnt <= 32'd0;
          tx_shift   <= {1'b1, tx_shift[9:1]};
          if (tx_bitcnt == 4'd9) tx_busy <= 1'b0;
          else                   tx_bitcnt <= tx_bitcnt + 4'd1;
        end else begin
          tx_baudcnt <= tx_baudcnt + 32'd1;
        end
      end
    end
  end

  assign tx_o = tx_busy ? tx_shift[0] : 1'b1;

  logic [1:0] rx_sync;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) rx_sync <= 2'b11;
    else        rx_sync <= {rx_sync[0], rx_i};
  end
  wire rx_in = rx_sync[1];

  typedef enum logic [1:0] { RX_IDLE, RX_START, RX_DATA, RX_STOP } rx_state_e;
  rx_state_e   rx_state;
  logic [31:0] rx_baudcnt;
  logic [2:0]  rx_bitcnt;
  logic [7:0]  rx_shift;

  logic [7:0]  rfifo [0:FIFO_DEPTH-1];
  logic [4:0]  rcount;
  logic [3:0]  rwptr, rrptr;
  wire  rx_full = (rcount == FIFO_DEPTH);
  wire  rx_pop  = bus_req.valid && !resp_vld_q && !bus_req.write
               && bus_req.addr[4:0] == amechip_pkg::UART_RXDATA_OFF[4:0]
               && rcount != 0;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rcount <= 5'd0; rwptr <= 4'd0; rrptr <= 4'd0;
      rx_state <= RX_IDLE; rx_baudcnt <= 32'd0; rx_bitcnt <= 3'd0; rx_shift <= 8'd0;
    end else begin
      if (rx_pop) begin
        rrptr  <= rrptr + 4'd1;
        rcount <= rcount - 5'd1;
      end
      if (div_q != 0) begin
        case (rx_state)
          RX_IDLE: begin
            rx_baudcnt <= 32'd0;
            if (!rx_in) rx_state <= RX_START;
          end
          RX_START: begin
            if (rx_baudcnt >= (div_q >> 1) - 1) begin
              rx_baudcnt <= 32'd0;
              if (!rx_in) begin
                rx_state  <= RX_DATA;
                rx_bitcnt <= 3'd0;
              end else begin
                rx_state <= RX_IDLE;
              end
            end else begin
              rx_baudcnt <= rx_baudcnt + 32'd1;
            end
          end
          RX_DATA: begin
            if (rx_baudcnt >= div_q - 1) begin
              rx_baudcnt <= 32'd0;
              rx_shift   <= {rx_in, rx_shift[7:1]};
              if (rx_bitcnt == 3'd7) rx_state <= RX_STOP;
              else                   rx_bitcnt <= rx_bitcnt + 3'd1;
            end else begin
              rx_baudcnt <= rx_baudcnt + 32'd1;
            end
          end
          RX_STOP: begin
            if (rx_baudcnt >= div_q - 1) begin
              rx_baudcnt <= 32'd0;
              if (!rx_pop) begin
                if (!rx_full) begin
                  rfifo[rwptr] <= rx_shift;
                  rwptr        <= rwptr + 4'd1;
                  rcount       <= rcount + 5'd1;
                end else begin
                  stat_ovrun_q <= 1'b1;
                end
              end
              rx_state <= RX_IDLE;
            end else begin
              rx_baudcnt <= rx_baudcnt + 32'd1;
            end
          end
          default: rx_state <= RX_IDLE;
        endcase
      end
    end
  end

  wire       req_fire = bus_req.valid && !resp_vld_q;
  wire [4:0] aoff     = bus_req.addr[4:0];
  wire       wr_en    = req_fire && bus_req.write;

  logic [31:0] rd_data_c;
  always @* begin
    rd_data_c = 32'd0;
    case (aoff)
      amechip_pkg::UART_RXDATA_OFF[4:0]: rd_data_c = {rcount != 0, rfifo[rrptr]};
      amechip_pkg::UART_DIV_OFF[4:0]:    rd_data_c = div_q;
      amechip_pkg::UART_CTRL_OFF[4:0]:   rd_data_c = {24'd0, ctrl_q};
      amechip_pkg::UART_STAT_OFF[4:0]:   rd_data_c = {13'd0, tx_full,
                                             stat_ovrun_q, tx_busy, 3'd0,
                                             rcount[4:0], 3'd0, tcount[4:0]};
      default:                           rd_data_c = 32'd0;
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      div_q  <= 32'(DIV_RESET);
      ctrl_q <= 8'h40;
      stat_ovrun_q <= 1'b0;
      resp_vld_q <= 1'b0;
      resp_dat_q <= 32'd0;
      resp_err_q <= 2'b00;
    end else begin
      resp_vld_q <= 1'b0;
      resp_dat_q <= 32'd0;
      resp_err_q <= 2'b00;
      if (wr_en && aoff == amechip_pkg::UART_EVCLR_OFF[4:0] && bus_req.wdata[17]) begin
        stat_ovrun_q <= 1'b0;          // W1C
      end
      if (req_fire) begin
        resp_vld_q <= 1'b1;
        if (bus_req.write) begin
          case (aoff)
            amechip_pkg::UART_DIV_OFF[4:0]:  div_q  <= bus_req.wdata;
            amechip_pkg::UART_CTRL_OFF[4:0]: ctrl_q <= bus_req.wdata[7:0];
            amechip_pkg::UART_TXDATA_OFF[4:0],
            amechip_pkg::UART_EVCLR_OFF[4:0]: ;
            default:                         resp_err_q <= amechip_pkg::AXI_SLVERR;
          endcase
        end else begin
          resp_dat_q <= rd_data_c;
          if (aoff == amechip_pkg::UART_TXDATA_OFF[4:0] || aoff == amechip_pkg::UART_EVCLR_OFF[4:0])
            resp_err_q <= amechip_pkg::AXI_SLVERR;
        end
      end
    end
  end

  assign bus_resp.valid = resp_vld_q;
  assign bus_resp.rdata = resp_dat_q;
  assign bus_resp.resp  = resp_err_q;

  assign irq_tx_o = ctrl_q[0] && (tcount < {1'b0, tx_wm});
  assign irq_rx_o = ctrl_q[1] && (rcount != 0);

endmodule
