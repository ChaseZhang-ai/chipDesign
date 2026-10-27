`ifndef _AXI2SOC_BRIDGE_SV
`define _AXI2SOC_BRIDGE_SV

module axi2soc_bridge (
  input  logic clk,
  input  logic rst_n,

  input  logic        s_aw_valid_i,
  output logic        s_aw_ready_o,
  input  logic [31:0] s_aw_addr_i,
  input  logic        s_w_valid_i,
  output logic        s_w_ready_o,
  input  logic [31:0] s_w_data_i,
  input  logic [3:0]  s_w_strb_i,
  output logic        s_b_valid_o,
  input  logic        s_b_ready_i,
  output logic [1:0]  s_b_resp_o,
  input  logic        s_ar_valid_i,
  output logic        s_ar_ready_o,
  input  logic [31:0] s_ar_addr_i,
  output logic        s_r_valid_o,
  input  logic        s_r_ready_i,
  output logic [31:0] s_r_data_o,
  output logic [1:0]  s_r_resp_o,

  output soc_pkg::soc_req_t  req_o,
  input  soc_pkg::soc_resp_t resp_i
);

  typedef enum logic [2:0] {
    S_IDLE = 3'd0,
    S_WREQ = 3'd1,
    S_RREQ = 3'd2,
    S_RESP = 3'd3
  } state_e;

  state_e      state_q;
  logic        wr_q;
  logic [31:0] addr_q, wdata_q;
  logic [3:0]  strb_q;
  logic [31:0] rdata_q;
  logic [1:0]  resp_q;
  logic        b_vld_q, r_vld_q;

  logic        aw_l_q, w_l_q;
  logic [31:0] aw_addr_l_q, w_data_l_q;
  logic [3:0]  w_strb_l_q;

  wire         idle, aw_ok, w_ok;
  wire [31:0]  aw_addr_n, w_data_n;
  wire [3:0]   w_strb_n;

  assign idle     = (state_q == S_IDLE);
  assign aw_ok    = aw_l_q || (s_aw_valid_i && s_aw_ready_o);
  assign w_ok     = w_l_q  || (s_w_valid_i  && s_w_ready_o);
  assign aw_addr_n = aw_l_q ? aw_addr_l_q : s_aw_addr_i;
  assign w_data_n  = w_l_q  ? w_data_l_q  : s_w_data_i;
  assign w_strb_n  = w_l_q  ? w_strb_l_q  : s_w_strb_i;

  assign s_aw_ready_o = idle && !aw_l_q;
  assign s_w_ready_o  = idle && !w_l_q;
  assign s_ar_ready_o = idle;

  assign s_b_valid_o = b_vld_q;
  assign s_b_resp_o  = resp_q;
  assign s_r_valid_o = r_vld_q;
  assign s_r_data_o  = rdata_q;
  assign s_r_resp_o  = resp_q;

  assign req_o.valid = (state_q == S_WREQ) || (state_q == S_RREQ);
  assign req_o.write = wr_q;
  assign req_o.addr  = addr_q;
  assign req_o.wdata = wdata_q;
  assign req_o.wstrb = strb_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q     <= S_IDLE;
      wr_q        <= 1'b0;
      addr_q      <= 32'd0;
      wdata_q     <= 32'd0;
      strb_q      <= 4'd0;
      rdata_q     <= 32'd0;
      resp_q      <= 2'b00;
      b_vld_q     <= 1'b0;
      r_vld_q     <= 1'b0;
      aw_l_q      <= 1'b0;
      w_l_q       <= 1'b0;
      aw_addr_l_q <= 32'd0;
      w_data_l_q  <= 32'd0;
      w_strb_l_q  <= 4'd0;
    end else begin
      if (s_aw_valid_i && s_aw_ready_o) begin
        aw_l_q      <= 1'b1;
        aw_addr_l_q <= s_aw_addr_i;
      end
      if (s_w_valid_i && s_w_ready_o) begin
        w_l_q      <= 1'b1;
        w_data_l_q <= s_w_data_i;
        w_strb_l_q <= s_w_strb_i;
      end

      case (state_q)
        S_IDLE: begin
          if (aw_ok && w_ok) begin
            wr_q     <= 1'b1;
            addr_q   <= aw_addr_n;
            wdata_q  <= w_data_n;
            strb_q   <= w_strb_n;
            aw_l_q   <= 1'b0;
            w_l_q    <= 1'b0;
            state_q  <= S_WREQ;
          end else if (s_ar_valid_i && s_ar_ready_o) begin
            wr_q     <= 1'b0;
            addr_q   <= s_ar_addr_i;
            wdata_q  <= 32'd0;
            strb_q   <= 4'd0;
            state_q  <= S_RREQ;
          end
        end
        S_WREQ: begin
          if (resp_i.valid) begin
            resp_q  <= resp_i.resp;
            b_vld_q <= 1'b1;
            state_q <= S_RESP;
          end
        end
        S_RREQ: begin
          if (resp_i.valid) begin
            rdata_q <= resp_i.rdata;
            resp_q  <= resp_i.resp;
            r_vld_q <= 1'b1;
            state_q <= S_RESP;
          end
        end
        S_RESP: begin
          if (b_vld_q && s_b_ready_i) begin
            b_vld_q <= 1'b0;
            state_q <= S_IDLE;
          end else if (r_vld_q && s_r_ready_i) begin
            r_vld_q <= 1'b0;
            state_q <= S_IDLE;
          end
        end
        default: state_q <= S_IDLE;
      endcase
    end
  end

endmodule

`endif // _AXI2SOC_BRIDGE_SV
