
module stub_memc (
  input  logic               clk,
  input  logic               rst_n,
  input  soc_pkg::soc_req_t  bus_req,
  output soc_pkg::soc_resp_t bus_resp,

  output logic               xmem_clk_o,
  output logic [22:0]        xmem_a_o,
  input  logic [15:0]        xmem_di_i,
  output logic [15:0]        xmem_do_o,
  output logic               xmem_ce_no,
  output logic               xmem_oe_no,
  output logic               xmem_we_no,
  input  logic               xmem_wait_i
);

  logic        resp_vld_q;
  logic [1:0]  resp_err_q;

  wire req_fire = bus_req.valid && !resp_vld_q;

  assign xmem_clk_o = clk;
  assign xmem_a_o   = 23'd0;
  assign xmem_do_o  = 16'd0;
  assign xmem_ce_no = 1'b1;
  assign xmem_oe_no = 1'b1;
  assign xmem_we_no = 1'b1;
  wire unused_di    = |xmem_di_i;
  wire unused_wait  = xmem_wait_i;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      resp_vld_q <= 1'b0;
      resp_err_q <= 2'b00;
    end else begin
      resp_vld_q <= 1'b0;
      resp_err_q <= 2'b00;
      if (req_fire) begin
        resp_vld_q <= 1'b1;
        resp_err_q <= amechip_pkg::AXI_DECERR;
      end
    end
  end

  assign bus_resp.valid = resp_vld_q;
  assign bus_resp.rdata = 32'd0;
  assign bus_resp.resp  = resp_err_q;

endmodule
