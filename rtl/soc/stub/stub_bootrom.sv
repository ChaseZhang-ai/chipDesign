
module stub_bootrom #(
  parameter int unsigned DEPTH_WORDS = 512             // 2KB
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
  wire [8:0] ridx     = bus_req.addr[10:2];

  string boot_hex_path;
  initial begin
    if ($value$plusargs("BOOT_HEX=%s", boot_hex_path)) begin
      $readmemh(boot_hex_path, mem);
      $display("[stub_bootrom] preloaded %0s", boot_hex_path);
    end else begin
      $display("[stub_bootrom] WARNING: no +BOOT_HEX given, ROM reads as 0");
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
          resp_err_q <= amechip_pkg::AXI_SLVERR;   // ROM 只读
        end else begin
          resp_dat_q <= mem[ridx];
        end
      end
    end
  end

  assign bus_resp.valid = resp_vld_q;
  assign bus_resp.rdata = resp_dat_q;
  assign bus_resp.resp  = resp_err_q;

endmodule
