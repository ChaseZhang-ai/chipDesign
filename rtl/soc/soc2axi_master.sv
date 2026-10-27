`ifndef _SOC2AXI_MASTER_SV
`define _SOC2AXI_MASTER_SV

module soc2axi_master (
  input  logic               clk,
  input  logic               rst_n,

  input  soc_pkg::soc_req_t  req_i,
  output soc_pkg::soc_resp_t resp_o,

  output logic        aw_valid_o,
  input  logic        aw_ready_i,
  output logic [31:0] aw_addr_o,
  output logic        w_valid_o,
  input  logic        w_ready_i,
  output logic [31:0] w_data_o,
  output logic [3:0]  w_strb_o,
  input  logic        b_valid_i,
  output logic        b_ready_o,
  input  logic [1:0]  b_resp_i,
  output logic        ar_valid_o,
  input  logic        ar_ready_i,
  output logic [31:0] ar_addr_o,
  input  logic        r_valid_i,
  output logic        r_ready_o,
  input  logic [31:0] r_data_i,
  input  logic [1:0]  r_resp_i
);

  typedef enum logic [2:0] {
    S_IDLE  = 3'd0,
    S_WR    = 3'd1,
    S_WB    = 3'd2,
    S_AR    = 3'd3,
    S_R     = 3'd4,
    S_RESP  = 3'd5,
    S_GAP   = 3'd6
  } state_e;

  state_e      state_q;
  logic        wr_q;
  logic [31:0] addr_q, wdata_q;
  logic [3:0]  strb_q;
  logic        aw_done_q, w_done_q;
  logic [31:0] rdata_q;
  logic [1:0]  resp_q;
  logic        resp_vld_q;

  assign resp_o.valid = resp_vld_q;
  assign resp_o.rdata = rdata_q;
  assign resp_o.resp  = resp_q;

  always_comb begin
    aw_valid_o = 1'b0;
    w_valid_o  = 1'b0;
    ar_valid_o = 1'b0;
    b_ready_o  = 1'b0;
    r_ready_o  = 1'b0;
    unique case (state_q)
      S_WR: begin
        aw_valid_o = ~aw_done_q;
        w_valid_o  = ~w_done_q;
        if (aw_done_q && w_done_q) begin
        end
      end
      S_WB: b_ready_o = 1'b1;
      S_AR: ar_valid_o = 1'b1;
      S_R:  r_ready_o  = 1'b1;
      default: ;
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q    <= S_IDLE;
      wr_q       <= 1'b0;
      addr_q     <= 32'd0;
      wdata_q    <= 32'd0;
      strb_q     <= 4'd0;
      aw_done_q  <= 1'b0;
      w_done_q   <= 1'b0;
      rdata_q    <= 32'd0;
      resp_q     <= 2'b00;
      resp_vld_q <= 1'b0;
    end else begin
      resp_vld_q <= 1'b0;
      unique case (state_q)
        S_IDLE: begin
          if (req_i.valid) begin
            wr_q      <= req_i.write;
            addr_q    <= req_i.addr;
            wdata_q   <= req_i.wdata;
            strb_q    <= req_i.wstrb;
            aw_done_q <= 1'b0;
            w_done_q  <= 1'b0;
            state_q   <= req_i.write ? S_WR : S_AR;
          end
        end
        S_WR: begin
          if (aw_ready_i) aw_done_q <= 1'b1;
          if (w_ready_i)  w_done_q  <= 1'b1;
          if ((aw_done_q || aw_ready_i) && (w_done_q || w_ready_i)) begin
            state_q <= S_WB;
          end
        end
        S_WB: begin
          if (b_valid_i) begin
            resp_q     <= b_resp_i;
            resp_vld_q <= 1'b1;
            state_q    <= S_RESP;
          end
        end
        S_AR: begin
          if (ar_ready_i) state_q <= S_R;
        end
        S_R: begin
          if (r_valid_i) begin
            rdata_q    <= r_data_i;
            resp_q     <= r_resp_i;
            resp_vld_q <= 1'b1;
            state_q    <= S_RESP;
          end
        end
        S_RESP: state_q <= S_GAP;
        S_GAP: begin
          if (!req_i.valid) state_q <= S_IDLE;
        end
        default: state_q <= S_IDLE;
      endcase
    end
  end

  assign aw_addr_o = addr_q;
  assign ar_addr_o = addr_q;
  assign w_data_o  = wdata_q;
  assign w_strb_o  = strb_q;

endmodule

`endif // _SOC2AXI_MASTER_SV
