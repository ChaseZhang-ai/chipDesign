
module stub_sram #(
  parameter int unsigned DEPTH_WORDS = 1024            // 4KB
) (
  input  logic                  clk,
  input  logic                  rst_n,

  input  soc_pkg::soc_req_t     bus_req,
  output soc_pkg::soc_resp_t    bus_resp
);

  logic [31:0] mem [0:DEPTH_WORDS-1];

  logic        resp_vld_q;
  logic [31:0] resp_dat_q;
  logic [1:0]  resp_err_q;

  wire       req_fire = bus_req.valid && !resp_vld_q;
  wire [9:0] widx     = bus_req.addr[11:2];

  string sram_hex_path;
  initial begin
    if ($value$plusargs("SRAM_HEX=%s", sram_hex_path)) begin
      $readmemh(sram_hex_path, mem);
      $display("[stub_sram] preloaded %0s", sram_hex_path);
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      resp_vld_q <= 1'b0;
      resp_dat_q <= 32'd0;
      resp_err_q <= 2'b00;
    end else begin
      resp_vld_q <= 1'b0;
      resp_err_q <= 2'b00;
      if (req_fire) begin
        resp_vld_q <= 1'b1;
        if (bus_req.write) begin
          if (bus_req.wstrb[0]) mem[widx][7:0]   <= bus_req.wdata[7:0];
          if (bus_req.wstrb[1]) mem[widx][15:8]  <= bus_req.wdata[15:8];
          if (bus_req.wstrb[2]) mem[widx][23:16] <= bus_req.wdata[23:16];
          if (bus_req.wstrb[3]) mem[widx][31:24] <= bus_req.wdata[31:24];
        end else begin
          resp_dat_q <= mem[widx];
        end
      end
    end
  end

  assign bus_resp.valid = resp_vld_q;
  assign bus_resp.rdata = resp_dat_q;
  assign bus_resp.resp  = resp_err_q;

endmodule
