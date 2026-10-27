
module soc_syscsr (
  input  logic               clk,
  input  logic               rst_n,

  input  soc_pkg::soc_req_t  bus_req,
  output soc_pkg::soc_resp_t bus_resp,

  input  logic               cpu_wfi_i,
  input  logic               ame_busy_i,
  input  logic               dma_busy_i,
  input  logic               kv_busy_i,

  output logic               soft_set_o,
  output logic               soft_clear_o
);

  logic [31:0] scratch0_q, scratch1_q;
  logic        resp_vld_q;
  logic [31:0] resp_dat_q;
  logic [1:0]  resp_err_q;

  wire       req_fire = bus_req.valid && !resp_vld_q;
  wire [4:0] aoff     = bus_req.addr[4:0];
  wire       wr_en    = req_fire && bus_req.write;

  logic [31:0] rd_data_c;
  always @* begin
    case (aoff)
      amechip_pkg::SYS_ID_OFF[4:0]:   rd_data_c = amechip_pkg::SYS_ID_VAL;
      amechip_pkg::SYS_VER_OFF[4:0]:  rd_data_c = amechip_pkg::SYS_VER_VAL;
      amechip_pkg::SYS_STAT_OFF[4:0]: rd_data_c = {28'd0, kv_busy_i, dma_busy_i,
                                          ame_busy_i, cpu_wfi_i};
      amechip_pkg::SYS_SCR0_OFF[4:0]: rd_data_c = scratch0_q;
      amechip_pkg::SYS_SCR1_OFF[4:0]: rd_data_c = scratch1_q;
      default:                        rd_data_c = 32'd0;
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      scratch0_q <= 32'd0;
      scratch1_q <= 32'd0;
      resp_vld_q <= 1'b0;
      resp_dat_q <= 32'd0;
      resp_err_q <= 2'b00;
    end else begin
      resp_vld_q   <= 1'b0;
      resp_dat_q   <= 32'd0;
      resp_err_q   <= 2'b00;
      soft_set_o   <= 1'b0;
      soft_clear_o <= 1'b0;
      if (req_fire) begin
        resp_vld_q <= 1'b1;
        if (bus_req.write) begin
          case (aoff)
            amechip_pkg::SYS_SCR0_OFF[4:0]:       scratch0_q <= bus_req.wdata;
            amechip_pkg::SYS_SCR1_OFF[4:0]:       scratch1_q <= bus_req.wdata;
            amechip_pkg::SYS_SIRQ_SET_OFF[4:0]:   soft_set_o   <= |bus_req.wdata;  // W1S
            amechip_pkg::SYS_SIRQ_CLEAR_OFF[4:0]: soft_clear_o <= |bus_req.wdata;  // W1C
            default:                              resp_err_q <= amechip_pkg::AXI_SLVERR;
          endcase
        end else begin
          resp_dat_q <= rd_data_c;
          case (aoff)
            amechip_pkg::SYS_SCR0_OFF[4:0],
            amechip_pkg::SYS_SCR1_OFF[4:0],
            amechip_pkg::SYS_SIRQ_SET_OFF[4:0],
            amechip_pkg::SYS_SIRQ_CLEAR_OFF[4:0]: resp_err_q <= amechip_pkg::AXI_SLVERR;
            default: ;
          endcase
        end
      end
    end
  end

  assign bus_resp.valid = resp_vld_q;
  assign bus_resp.rdata = resp_dat_q;
  assign bus_resp.resp  = resp_err_q;

endmodule
