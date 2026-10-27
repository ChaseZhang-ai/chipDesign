
`ifndef _AMECHIP_PKG_SV
 `include "amechip_pkg.sv"
`endif
`ifndef _SOC_PKG_SV
 `include "soc_pkg.sv"
`endif

module vrfb_xmem_model (
  input logic clk,
  input logic rst_n,
  input  soc_pkg::soc_req_t  bus_req,
  output soc_pkg::soc_resp_t bus_resp,
  input  logic dump_i
);

  localparam int WORDS = 2 * 1024 * 1024;   // 8 MB

  logic [31:0] mem [0:WORDS-1];

  reg [1023:0] FNAME_XMEM, FNAME_DUMP;
  integer      DUMP_BASE_W, DUMP_WORDS;
  integer      i;

  logic        req_d, pend_q;
  logic [1:0]  cnt_q;
  logic        wr_q;
  logic [31:0] addr_q, wdata_q;
  logic [3:0]  strb_q;
  logic        rsp_v_q;
  logic [31:0] rsp_d_q;
  logic [31:0] wv;
  wire [22:0]  wa = bus_req.addr[22:0] >> 2;
  wire [22:0]  ra = addr_q[22:0] >> 2;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pend_q  <= 1'b0;
      cnt_q   <= 2'd0;
      rsp_v_q <= 1'b0;
      rsp_d_q <= 32'd0;
      wr_q    <= 1'b0;
      addr_q  <= 32'd0;
      wdata_q <= 32'd0;
      strb_q  <= 4'd0;
    end else begin
      req_d   <= bus_req.valid;
      rsp_v_q <= 1'b0;
      if (bus_req.valid && !req_d) begin
        pend_q  <= 1'b1;
        cnt_q   <= 2'd0;
        wr_q    <= bus_req.write;
        addr_q  <= bus_req.addr;
        wdata_q <= bus_req.wdata;
        strb_q  <= bus_req.wstrb;
        if (bus_req.write) begin
          wv = mem[wa];
          if (bus_req.wstrb[0]) wv[7:0]   = bus_req.wdata[7:0];
          if (bus_req.wstrb[1]) wv[15:8]  = bus_req.wdata[15:8];
          if (bus_req.wstrb[2]) wv[23:16] = bus_req.wdata[23:16];
          if (bus_req.wstrb[3]) wv[31:24] = bus_req.wdata[31:24];
          mem[wa] <= wv;
        end
      end else if (pend_q) begin
        if (cnt_q == 2'd0) begin
          cnt_q <= 2'd1;
        end else begin
          pend_q  <= 1'b0;
          rsp_v_q <= 1'b1;
          rsp_d_q <= wr_q ? 32'd0 : mem[ra];
        end
      end
    end
  end

  assign bus_resp.valid = rsp_v_q;
  assign bus_resp.rdata = rsp_d_q;
  assign bus_resp.resp  = amechip_pkg::AXI_OKAY;

  logic dump_d;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) dump_d <= 1'b0;
    else dump_d <= dump_i;
  end

  integer fd, k;
  initial begin
    if (!$value$plusargs("SCR_DUMP=%s", FNAME_DUMP)) FNAME_DUMP = "";
    if (!$value$plusargs("SCR_BASE_W=%d", DUMP_BASE_W)) DUMP_BASE_W = 32'h00120000;
    if (!$value$plusargs("SCR_WORDS=%d", DUMP_WORDS)) DUMP_WORDS = 0;
    for (i = 0; i < 2048; i = i + 1) mem[i] = 32'd0;
    for (i = 0; i < 16384; i = i + 1) mem[DUMP_BASE_W + i] = 32'd0;
    if ($value$plusargs("XMEM_HEX=%s", FNAME_XMEM)) $readmemh(FNAME_XMEM, mem);
  end

  always @(posedge clk) begin
    if (dump_i && !dump_d && DUMP_WORDS > 0) begin
      fd = $fopen(FNAME_DUMP, "w");
      for (k = 0; k < DUMP_WORDS; k = k + 1)
        $fwrite(fd, "%08X\n", mem[DUMP_BASE_W + k]);
      $fclose(fd);
      $display("[vrfb_xmem] dumped %0d words @word%0d -> %0s",
               DUMP_WORDS, DUMP_BASE_W, FNAME_DUMP);
    end
  end

endmodule
