
module stub_kvcsr (
  input  logic               clk,
  input  logic               rst_n,
  input  soc_pkg::soc_req_t  bus_req,
  output soc_pkg::soc_resp_t bus_resp
);

  logic [31:0] regs [0:9];   // CTRL LAYER HEAD POS COUNT SRC DST PITCH STATUS SLICE
  logic        resp_vld_q;
  logic [31:0] resp_dat_q;
  logic [1:0]  resp_err_q;

  wire        req_fire = bus_req.valid && !resp_vld_q;
  wire [3:0]  widx     = bus_req.addr[5:2];
  wire        in_range = (widx <= 4'd9);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < 10; i++) regs[i] <= 32'd0;
      resp_vld_q <= 1'b0; resp_dat_q <= 32'd0; resp_err_q <= 2'b00;
    end else begin
      resp_vld_q <= 1'b0; resp_dat_q <= 32'd0; resp_err_q <= 2'b00;
      if (req_fire) begin
        resp_vld_q <= 1'b1;
        if (bus_req.write) begin
          if (in_range) regs[widx] <= bus_req.wdata;
          else          resp_err_q <= amechip_pkg::AXI_SLVERR;
        end else begin
          resp_dat_q <= in_range ? regs[widx] : 32'd0;
          if (!in_range) resp_err_q <= amechip_pkg::AXI_SLVERR;
        end
      end
    end
  end

  assign bus_resp.valid = resp_vld_q;
  assign bus_resp.rdata = resp_dat_q;
  assign bus_resp.resp  = resp_err_q;

endmodule
