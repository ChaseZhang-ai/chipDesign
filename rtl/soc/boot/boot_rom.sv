
module boot_rom #(
  parameter int unsigned DEPTH_WORDS = 512,                 // 2KB
  parameter              HEX_PATH    = "../rtl/soc/boot/boot.hex"
) (
  input  logic               clk,
  input  logic               rst_n,
  input  soc_pkg::soc_req_t  bus_req,
  output soc_pkg::soc_resp_t bus_resp
);

  logic [31:0] mem [0:DEPTH_WORDS-1];

  logic        resp_vld_q;
  logic [31:0] resp_dat_q;
  logic [1:0]  resp_err_q;

  wire        req_fire = bus_req.valid && !resp_vld_q;
  wire [8:0]  ridx     = bus_req.addr[10:2];

`ifdef AMECHIP_BOOTROM_CONST
`ifndef AMECHIP_BOOTROM_HEX
 `define AMECHIP_BOOTROM_HEX "/home/zcz/verda/autoDecodeChip/rtl/soc/boot/boot.hex"
`endif
  initial $readmemh(`AMECHIP_BOOTROM_HEX, mem);
`else
  string p;
  initial begin
    p = HEX_PATH;
    if ($value$plusargs("BOOT_HEX=%s", p)) begin
      $display("[boot_rom] HEX overridden by plusarg: %0s", p);
    end
    $readmemh(p, mem);
    $display("[boot_rom] loaded %0s (%0d words)", p, DEPTH_WORDS);
  end
`endif

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
