`ifndef _AMECHIP_PKG_SV
 `include "amechip_pkg.sv"
`endif

module kv_backend_axi #(
  parameter int unsigned BANKS   = amechip_pkg::KV_BANKS_DEF,
  parameter int unsigned BPAW    = amechip_pkg::KV_BANK_AW,
  parameter logic [31:0] KV_BASE = 32'h4040_0000 // = A_XMEM_BASE + XM_KV_OFF
) (
  input  logic clk_i,
  input  logic rst_ni,

  input  logic [BANKS-1:0]      bp_cs_i,
  input  logic [BANKS-1:0]      bp_we_i,
  input  logic [BANKS*BPAW-1:0] bp_addr_i,
  input  logic [BANKS*32-1:0]   bp_wdata_i,
  output logic [BANKS*32-1:0]   bp_rdata_o,
  input  logic                  bp_layer_i,
  input  logic                  bp_kvt_i,
  output logic                  bp_done_o,
  output logic                  bp_err_o,
  output logic                  bp_ready_o,

  output logic        m_ar_valid_o,
  input  logic        m_ar_ready_i,
  output logic [31:0] m_ar_addr_o,
  input  logic        m_r_valid_i,
  output logic        m_r_ready_o,
  input  logic [31:0] m_r_data_i,
  input  logic [1:0]  m_r_resp_i,
  output logic        m_aw_valid_o,
  input  logic        m_aw_ready_i,
  output logic [31:0] m_aw_addr_o,
  output logic        m_w_valid_o,
  input  logic        m_w_ready_i,
  output logic [31:0] m_w_data_o,
  output logic [3:0]  m_w_strb_o,
  input  logic        m_b_valid_i,
  output logic        m_b_ready_o,
  input  logic [1:0]  m_b_resp_i
);

  localparam logic [1:0] S_IDLE = 2'd0, S_WR = 2'd1, S_RD = 2'd2;

  logic [1:0]  st_q;
  logic        is_wr_q, lay_q, kvt_q;
  logic [1:0]  bank_q;
  logic [BPAW-1:0] waddr_q;
  logic [31:0] wdata_q, rdata_q;
  logic        done_q, err_q;
  logic        ar_sent_q, wr_sent_q;
  logic        cs_any_q;

  wire cs_any = |bp_cs_i;
  wire cs_rise = cs_any && !cs_any_q;

  logic [BANKS-1:0] cs_enc;
  always_comb begin
    cs_enc = bp_cs_i;
    for (int b = BANKS - 2; b >= 0; b--) begin
      if (cs_enc[b+1]) cs_enc[b] = 1'b0;
    end
  end
  logic [1:0] cs_bank;
  always_comb begin
    case (cs_enc)
      4'b0010: cs_bank = 2'd1;
      4'b0100: cs_bank = 2'd2;
      4'b1000: cs_bank = 2'd3;
      default: cs_bank = 2'd0;
    endcase
  end
  logic [BPAW-1:0] cs_waddr;
  logic [31:0]     cs_wdata;
  always_comb begin
    cs_waddr = '0;
    cs_wdata = '0;
    for (int b = 0; b < BANKS; b++) begin
      if (cs_enc[b]) begin
        cs_waddr = bp_addr_i[b*BPAW +: BPAW];
        cs_wdata = bp_wdata_i[b*32 +: 32];
      end
    end
  end

  logic [31:0] waddr_ext;
  always_comb begin
    waddr_ext           = '0;
    waddr_ext[BPAW-1:0] = waddr_q;
  end
  wire [31:0] axi_addr = KV_BASE
                       + {14'b0, lay_q,  17'b0}
                       + {15'b0, kvt_q,  16'b0}
                       + {16'b0, bank_q, 14'b0}
                       + (waddr_ext << 2);

  wire ar_acc = (st_q == S_RD) && m_ar_valid_o && m_ar_ready_i;
  wire aw_acc = (st_q == S_WR) && m_aw_valid_o && m_aw_ready_i &&
                m_w_valid_o && m_w_ready_i;
  wire r_take = (st_q == S_RD) && m_r_valid_i && m_r_ready_o;
  wire b_take = (st_q == S_WR) && m_b_valid_i && m_b_ready_o;

  assign m_ar_valid_o = (st_q == S_RD) && !ar_sent_q;
  assign m_ar_addr_o  = axi_addr;
  assign m_r_ready_o  = 1'b1;
  assign m_aw_valid_o = (st_q == S_WR) && !wr_sent_q;
  assign m_aw_addr_o  = axi_addr;
  assign m_w_valid_o  = (st_q == S_WR) && !wr_sent_q;
  assign m_w_data_o   = wdata_q;
  assign m_w_strb_o   = 4'b1111;
  assign m_b_ready_o  = 1'b1;

  assign bp_done_o = done_q;
  assign bp_err_o  = err_q;
  assign bp_ready_o = (st_q == S_IDLE);

  for (genvar b = 0; b < BANKS; b++) begin : g_rd
    assign bp_rdata_o[b*32 +: 32] =
        ((BANKS)'(b) == (BANKS)'(bank_q)) ? rdata_q : 32'b0;
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      st_q <= S_IDLE; is_wr_q <= 1'b0; lay_q <= 1'b0; kvt_q <= 1'b0;
      bank_q <= '0; waddr_q <= '0; wdata_q <= '0; rdata_q <= '0;
      done_q <= 1'b0; err_q <= 1'b0; ar_sent_q <= 1'b0; wr_sent_q <= 1'b0;
      cs_any_q <= 1'b0;
    end else begin
      done_q <= 1'b0;
      err_q  <= 1'b0;
      cs_any_q <= cs_any;
      case (st_q)
        S_IDLE: begin
          if (cs_rise) begin
            is_wr_q <= bp_we_i[cs_bank];
            lay_q   <= bp_layer_i;
            kvt_q   <= bp_kvt_i;
            bank_q  <= cs_bank;
            waddr_q <= cs_waddr;
            wdata_q <= cs_wdata;
            ar_sent_q <= 1'b0;
            wr_sent_q <= 1'b0;
            st_q    <= bp_we_i[cs_bank] ? S_WR : S_RD;
          end
        end
        S_WR: begin
          if (aw_acc) wr_sent_q <= 1'b1;
          if (b_take) begin
            done_q <= 1'b1;
            err_q  <= (m_b_resp_i != amechip_pkg::AXI_OKAY);
            st_q   <= S_IDLE;
          end
        end
        S_RD: begin
          if (ar_acc) ar_sent_q <= 1'b1;
          if (r_take) begin
            rdata_q <= m_r_data_i;
            done_q  <= 1'b1;
            err_q   <= (m_r_resp_i != amechip_pkg::AXI_OKAY);
            st_q    <= S_IDLE;
          end
        end
        default: st_q <= S_IDLE;
      endcase
    end
  end

endmodule
