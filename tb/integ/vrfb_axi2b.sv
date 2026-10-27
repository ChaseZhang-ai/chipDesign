
`ifndef _AMECHIP_PKG_SV
 `include "amechip_pkg.sv"
`endif
`ifndef _SOC_PKG_SV
 `include "soc_pkg.sv"
`endif

module vrfb_axi2b (
  input logic clk,
  input logic rst_n,

  input  logic [31:0] ax_aw_addr,
  input  logic        ax_aw_valid,
  output logic        ax_aw_ready,
  input  logic [31:0] ax_w_data,
  input  logic [3:0]  ax_w_strb,
  input  logic        ax_w_valid,
  output logic        ax_w_ready,
  output logic [1:0]  ax_b_resp,
  output logic        ax_b_valid,
  input  logic        ax_b_ready,
  input  logic [31:0] ax_ar_addr,
  input  logic        ax_ar_valid,
  output logic        ax_ar_ready,
  output logic [31:0] ax_r_data,
  output logic [1:0]  ax_r_resp,
  output logic        ax_r_valid,
  input  logic        ax_r_ready,

  output soc_pkg::soc_req_t  bus_req,
  input  soc_pkg::soc_resp_t bus_resp,

  output logic [31:0] f_addr,
  output logic [31:0] f_waddr,
  output logic        f_we,
  output logic [31:0] f_wdata,
  output logic [3:0]  f_wstrb,
  input  logic [31:0] f_rdata,
  input  logic [1:0]  f_resp
);

  reg DBG;
  initial if ($test$plusargs("DBG")) DBG = 1'b1; else DBG = 1'b0;

  function automatic logic is_local(input logic [31:0] a);
    is_local = (a <= amechip_pkg::A_OCSRAM_END) ||
               ((a >= amechip_pkg::A_BOOTROM_BASE) && (a <= amechip_pkg::A_BOOTROM_END));
  endfunction

  function automatic logic is_rom(input logic [31:0] a);
    is_rom = (a >= amechip_pkg::A_BOOTROM_BASE) && (a <= amechip_pkg::A_BOOTROM_END);
  endfunction

  assign ax_aw_ready = 1'b1;
  assign ax_w_ready  = 1'b1;
  assign ax_ar_ready = 1'b1;

  localparam logic [1:0] R_IDLE = 2'd0, R_FAST = 2'd1, R_REQ = 2'd2, R_RSP = 2'd3;
  logic [1:0]  rst_q;
  logic        rd_local_q;
  logic [31:0] rd_addr_q, rd_data_q;
  logic [1:0]  rd_resp_q;

  localparam logic [2:0] W_IDLE = 3'd0, W_FASTB = 3'd1, W_REQ = 3'd2, W_RSP = 3'd3,
                         W_B = 3'd4, W_GAP = 3'd5;
  logic [2:0]  wst_q;
  logic        aw_got_q, w_got_q;
  logic [31:0] w_addr_q, w_data_q;
  logic [3:0]  w_strb_q;
  logic [1:0]  wr_resp_q;

  assign f_addr  = (rst_q == R_IDLE) ? ax_ar_addr : rd_addr_q;
  assign f_waddr = ax_aw_addr;
  assign f_we    = (wst_q == W_IDLE) && ax_aw_valid && ax_w_valid && !aw_got_q &&
                   is_local(ax_aw_addr);
  assign f_wdata = ax_w_data;
  assign f_wstrb = ax_w_strb;

  assign ax_r_valid = (rst_q == R_FAST) || (rst_q == R_RSP);
  assign ax_r_data  = (rst_q == R_FAST) ? f_rdata : rd_data_q;
  assign ax_r_resp  = (rst_q == R_FAST) ? f_resp  : rd_resp_q;
  assign ax_b_valid = (wst_q == W_FASTB) || (wst_q == W_B);
  assign ax_b_resp  = wr_resp_q;

  assign bus_req.valid = (rst_q == R_REQ) || (wst_q == W_REQ);
  assign bus_req.write = (wst_q == W_REQ);
  assign bus_req.addr  = (wst_q == W_REQ) ? w_addr_q : rd_addr_q;
  assign bus_req.wdata = w_data_q;
  assign bus_req.wstrb = w_strb_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rst_q <= R_IDLE;
      rd_local_q <= 1'b0;
      rd_addr_q <= 32'd0;
      rd_data_q <= 32'd0;
      rd_resp_q <= 2'b00;
    end else begin
      case (rst_q)
        R_IDLE: begin
          if (ax_ar_valid && ax_ar_ready) begin
            rd_addr_q  <= ax_ar_addr;
            rd_local_q <= is_local(ax_ar_addr);
            rst_q      <= is_local(ax_ar_addr) ? R_FAST : R_REQ;
            if (DBG) $display("[AXI2B] rd accept addr=%08h", ax_ar_addr);
          end
        end
        R_FAST: begin
          if (DBG) $display("[AXI2B] rd fast rsp addr=%08h data=%08h", rd_addr_q, f_rdata);
          if (ax_r_ready) rst_q <= R_IDLE;
        end
        R_REQ: begin
          if (bus_resp.valid) begin
            rd_data_q <= bus_resp.rdata;
            rd_resp_q <= bus_resp.resp;
            rst_q     <= R_RSP;
          end
        end
        R_RSP: begin
          if (ax_r_ready) rst_q <= R_IDLE;
        end
        default: rst_q <= R_IDLE;
      endcase
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wst_q <= W_IDLE;
      aw_got_q <= 1'b0;
      w_got_q  <= 1'b0;
      w_addr_q <= 32'd0;
      w_data_q <= 32'd0;
      w_strb_q <= 4'd0;
      wr_resp_q <= 2'b00;
    end else begin
      if (ax_aw_valid) begin
        w_addr_q <= ax_aw_addr;
        aw_got_q <= 1'b1;
      end
      if (ax_w_valid) begin
        w_data_q <= ax_w_data;
        w_strb_q <= ax_w_strb;
        w_got_q  <= 1'b1;
      end

      if (DBG && (ax_aw_valid || ax_w_valid || wst_q != W_IDLE || bus_resp.valid))
        $display("[AXI2B-W] st=%0d aw_v=%b w_v=%b aw_got=%b w_got=%b busresp=%b out_addr=%08h",
                 wst_q, ax_aw_valid, ax_w_valid, aw_got_q, w_got_q, bus_resp.valid, w_addr_q);
      case (wst_q)
        W_IDLE: begin
          if (aw_got_q && w_got_q) begin
            if (DBG) $display("[AXI2B] wr start addr=%08h data=%08h strb=%b",
                              w_addr_q, w_data_q, w_strb_q);
            aw_got_q <= 1'b0;
            w_got_q  <= 1'b0;
            if (is_local(w_addr_q)) begin
              wr_resp_q <= is_rom(w_addr_q) ? amechip_pkg::AXI_SLVERR
                                            : amechip_pkg::AXI_OKAY;
              wst_q <= W_FASTB;
            end else begin
              wst_q <= W_REQ;
            end
          end
        end
        W_FASTB: begin
          if (ax_b_ready) wst_q <= W_IDLE;
        end
        W_REQ: begin
          if (bus_resp.valid) begin
            wr_resp_q <= bus_resp.resp;
            wst_q     <= W_B;
          end
        end
        W_B: begin
          if (ax_b_ready) wst_q <= W_GAP;
        end
        W_GAP: begin
          wst_q <= W_IDLE;         // ≥1 空拍(捕获标志由 W_IDLE 消费时清零,
        end
        default: wst_q <= W_IDLE;
      endcase
    end
  end

endmodule
