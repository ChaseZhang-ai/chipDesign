`ifndef _AMECHIP_PKG_SV
 `include "amechip_pkg.sv"
`endif

module cpu_axi_bridge (
  input  logic        clk_i,
  input  logic        rst_ni,

  input  logic        if_req_valid_i,
  input  logic [31:0] if_addr_i,
  output logic        if_grant_o,
  output logic        if_rvalid_o,
  output logic [31:0] if_rdata_o,
  output logic        if_err_o,

  input  logic        dm_req_valid_i,
  input  logic        dm_we_i,
  input  logic [31:0] dm_addr_i,
  input  logic [31:0] dm_wdata_i,
  input  logic [3:0]  dm_wstrb_i,
  output logic        dm_grant_o,
  output logic        dm_rvalid_o,
  output logic [31:0] dm_rdata_o,
  output logic        dm_err_o,

  output logic [31:0] ax_aw_addr,
  output logic        ax_aw_valid,
  input  logic         ax_aw_ready,
  output logic [31:0] ax_w_data,
  output logic [3:0]  ax_w_strb,
  output logic        ax_w_valid,
  input  logic         ax_w_ready,
  input  logic [1:0]  ax_b_resp,
  input  logic        ax_b_valid,
  output logic        ax_b_ready,
  output logic [31:0] ax_ar_addr,
  output logic        ax_ar_valid,
  input  logic         ax_ar_ready,
  input  logic [31:0] ax_r_data,
  input  logic [1:0]  ax_r_resp,
  input  logic        ax_r_valid,
  output logic        ax_r_ready
);

  localparam logic [1:0] AXI_OKAY = 2'b00;

  localparam logic [1:0] RD_NONE = 2'd0, RD_IF = 2'd1, RD_DM = 2'd2;
  localparam logic [1:0] W_IDLE = 2'd0, W_AWDONE = 2'd1, W_WDONE = 2'd2, W_OUT = 2'd3;

  logic [1:0] rd_src_q;
  logic [1:0] wr_q;

  wire dm_rd_req = dm_req_valid_i && !dm_we_i;
  wire dm_wr_req = dm_req_valid_i &&  dm_we_i;

  wire can_ar     = (rd_src_q == RD_NONE) && (wr_q == W_IDLE) && rst_ni;
  wire ar_pick_dm = dm_rd_req && can_ar;
  wire ar_pick_if = !ar_pick_dm && !dm_req_valid_i && if_req_valid_i && can_ar;
  wire ar_fire    = (ar_pick_dm || ar_pick_if) && ax_ar_ready;

  assign ax_ar_valid = ar_pick_dm || ar_pick_if;
  assign ax_ar_addr = ar_pick_dm ? {dm_addr_i[31:2], 2'b00} : if_addr_i;

  assign if_grant_o = ar_pick_if && ar_fire;

  wire aw_fire = ax_aw_valid && ax_aw_ready;
  wire w_fire  = ax_w_valid  && ax_w_ready;
  wire wr_fire = (aw_fire && w_fire)
               || (aw_fire && (wr_q == W_WDONE))
               || (w_fire  && (wr_q == W_AWDONE));

  assign ax_aw_valid = dm_wr_req && ((wr_q == W_IDLE) || (wr_q == W_WDONE)) && rst_ni;
  assign ax_aw_addr  = {dm_addr_i[31:2], 2'b00};   // P3D-08:写地址对齐(同读)
  assign ax_w_valid  = dm_wr_req && ((wr_q == W_IDLE) || (wr_q == W_AWDONE)) && rst_ni;
  assign ax_w_data   = dm_wdata_i;
  assign ax_w_strb   = dm_wstrb_i;

  assign ax_b_ready  = 1'b1;
  wire   b_fire      = ax_b_valid && ax_b_ready;

  assign dm_grant_o  = (ar_pick_dm && ar_fire) || wr_fire;

  assign ax_r_ready = 1'b1;
  wire   rd_fire    = ax_r_valid && ax_r_ready;
  wire [1:0] rd_src_now = ar_fire ? (ar_pick_dm ? RD_DM : RD_IF) : rd_src_q;

  assign if_rvalid_o = rd_fire && (rd_src_now == RD_IF);
  assign if_rdata_o  = ax_r_data;
  assign if_err_o    = rd_fire && (rd_src_now == RD_IF) && (ax_r_resp != AXI_OKAY);

  assign dm_rvalid_o = rd_fire && (rd_src_now == RD_DM);
  assign dm_rdata_o  = ax_r_data;
  assign dm_err_o    = (rd_fire && (rd_src_now == RD_DM) && (ax_r_resp != AXI_OKAY))
                     || (b_fire && (ax_b_resp != AXI_OKAY));

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rd_src_q <= RD_NONE;
      wr_q     <= W_IDLE;
    end else begin
      if (ar_fire)      rd_src_q <= ar_pick_dm ? RD_DM : RD_IF;
      else if (rd_fire) rd_src_q <= RD_NONE;

      if (b_fire) begin
        wr_q <= W_IDLE;
      end else begin
        case (wr_q)
          W_IDLE: begin
            if (aw_fire && w_fire)      wr_q <= W_OUT;
            else if (aw_fire)           wr_q <= W_AWDONE;
            else if (w_fire)            wr_q <= W_WDONE;
          end
          W_AWDONE: if (w_fire)  wr_q <= W_OUT;
          W_WDONE:  if (aw_fire) wr_q <= W_OUT;
          default: ;
        endcase
      end
    end
  end

endmodule
