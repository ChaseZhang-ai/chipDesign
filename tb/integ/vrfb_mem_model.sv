
`ifndef _AMECHIP_PKG_SV
 `include "amechip_pkg.sv"
`endif
`ifndef _SOC_PKG_SV
 `include "soc_pkg.sv"
`endif

module vrfb_mem_model (
  input logic clk,
  input logic rst_n,
  input  soc_pkg::soc_req_t  bus_req,
  output soc_pkg::soc_resp_t bus_resp,
  input  logic dump_i,

  input  logic [31:0] f_addr,
  input  logic [31:0] f_waddr,
  input  logic        f_we,
  input  logic [31:0] f_wdata,
  input  logic [3:0]  f_wstrb,
  output logic [31:0] f_rdata,
  output logic [1:0]  f_resp          // 0=OKAY 1=SLVERR 2=DECERR(仅编码用)
);

  localparam int SRAM_WORDS = 1024;

  `ifndef SYNTHESIS
  reg msdbg;
  initial msdbg = $test$plusargs("YDBG");
  always @(posedge clk) begin
    if (msdbg) begin
      for (int w = 0; w < 20; w++)
        if (f_we && f_waddr == 32'h810 + 4*w)
          $display("[MSW] t=%0t +0x%0x <= %08h", $time, 32'h810+4*w, f_wdata);
    end
  end
  `endif
  localparam int ROM_WORDS  = 512;

  logic [31:0] sram [0:SRAM_WORDS-1];
  logic [31:0] rom  [0:ROM_WORDS-1];

  logic        req_d;
  logic        rsp_v_q;
  logic [31:0] rsp_d_q;
  logic [1:0]  rsp_r_q;

  wire [31:0] a        = bus_req.addr;
  wire        in_sram  = (a <= amechip_pkg::A_OCSRAM_END);
  wire        in_rom   = (a >= amechip_pkg::A_BOOTROM_BASE) && (a <= amechip_pkg::A_BOOTROM_END);
  wire [9:0]  sw       = a[11:2];
  wire [8:0]  rw       = a[10:2];
  wire [1:0]  blane    = a[1:0];

  logic [31:0] wv;   // 字节写在时钟块内做(见下)

  wire        f_in_rom = (f_addr >= amechip_pkg::A_BOOTROM_BASE) && (f_addr <= amechip_pkg::A_BOOTROM_END);
  wire        f_in_sram = (f_addr <= amechip_pkg::A_OCSRAM_END);
  always_comb begin
    f_rdata = 32'd0;
    f_resp  = 2'b00;
    if (f_in_sram)      f_rdata = sram[f_addr[11:2]];
    else if (f_in_rom)  f_rdata = rom[f_addr[10:2]];
    else                f_resp  = 2'b11;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
    end else if (f_we && (f_waddr <= amechip_pkg::A_OCSRAM_END) && (f_wstrb != 4'd0)) begin
      if (f_wstrb[0]) sram[f_waddr[11:2]][7:0]   <= f_wdata[7:0];
      if (f_wstrb[1]) sram[f_waddr[11:2]][15:8]  <= f_wdata[15:8];
      if (f_wstrb[2]) sram[f_waddr[11:2]][23:16] <= f_wdata[23:16];
      if (f_wstrb[3]) sram[f_waddr[11:2]][31:24] <= f_wdata[31:24];
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rsp_v_q <= 1'b0;
      rsp_d_q <= 32'd0;
      rsp_r_q <= 2'b00;
      req_d   <= 1'b0;
    end else begin
      req_d   <= bus_req.valid;
      rsp_v_q <= 1'b0;
      if (bus_req.valid && !req_d) begin
        rsp_v_q <= 1'b1;
        if (in_sram) begin
          if (bus_req.write) begin
            wv = sram[sw];
            if (bus_req.wstrb[0]) wv[7:0]   = bus_req.wdata[7:0];
            if (bus_req.wstrb[1]) wv[15:8]  = bus_req.wdata[15:8];
            if (bus_req.wstrb[2]) wv[23:16] = bus_req.wdata[23:16];
            if (bus_req.wstrb[3]) wv[31:24] = bus_req.wdata[31:24];
            if (bus_req.wstrb != 4'd0) sram[sw] <= wv;
            rsp_r_q <= amechip_pkg::AXI_OKAY;
            rsp_d_q <= 32'd0;
          end else begin
            rsp_r_q <= amechip_pkg::AXI_OKAY;
            rsp_d_q <= sram[sw];
          end
        end else if (in_rom && !bus_req.write) begin
          rsp_r_q <= amechip_pkg::AXI_OKAY;
          rsp_d_q <= rom[rw];
        end else if (in_rom) begin
          rsp_r_q <= amechip_pkg::AXI_SLVERR;   // ROM 写
          rsp_d_q <= 32'd0;
        end else begin
          rsp_r_q <= amechip_pkg::AXI_DECERR;   // 保留区
          rsp_d_q <= 32'd0;
        end
      end
    end
  end

  assign bus_resp.valid = rsp_v_q;
  assign bus_resp.rdata = rsp_d_q;
  assign bus_resp.resp  = rsp_r_q;

  integer      i;
  reg [1023:0] FNAME_SRAM, FNAME_BOOT;

  initial begin
    for (i = 0; i < SRAM_WORDS; i++) sram[i] = 32'd0;
    for (i = 0; i < ROM_WORDS; i++)  rom[i]  = 32'd0;
    if ($value$plusargs("SRAM_HEX=%s", FNAME_SRAM)) $readmemh(FNAME_SRAM, sram);
    if ($value$plusargs("BOOT_HEX=%s", FNAME_BOOT)) $readmemh(FNAME_BOOT, rom);
  end

endmodule
