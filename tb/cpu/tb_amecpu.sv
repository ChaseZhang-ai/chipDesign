`timescale 1ns/1ps
`ifndef _AMECHIP_PKG_SV
 `include "amechip_pkg.sv"
`endif
`ifndef _AMECPU_PKG_SV
 `include "amecpu_pkg.sv"
`endif

module tb_amecpu;

  import amechip_pkg::*;
  import amecpu_pkg::*;

  logic clk = 1'b0;
  always #5 clk = ~clk;

  logic rst_ni = 1'b0;

  clk_rst_if u_cr();
  assign u_cr.clk   = clk;
  assign u_cr.rst_ni = rst_ni;

  reg [2047:0] hexfile;
  reg [2047:0] tracefile;
  integer      maxcyc;
  integer      stallpct;
  integer      seed;
  logic        void_instr;
  reg [14:0]   seed15;

  initial begin
    if (!$value$plusargs("HEX=%s", hexfile)) begin
      $display("TB FAIL: missing +HEX=");
      $finish;
    end
    if (!$value$plusargs("TRACE=%s", tracefile)) begin
      $display("TB FAIL: missing +TRACE=");
      $finish;
    end
    if (!$value$plusargs("MAXCYC=%d", maxcyc)) maxcyc = 500000;
    if (!$value$plusargs("STALLPCT=%d", stallpct)) stallpct = 25;
    if (!$value$plusargs("SEED=%d", seed)) seed = 1;
  end

  logic [31:0] mem [0:32767];

  wire [31:0] ax_aw_addr, ax_w_data, ax_ar_addr, ax_r_data;
  wire [3:0]  ax_w_strb;
  wire        ax_aw_valid, ax_w_valid, ax_ar_valid, ax_r_valid;
  wire [1:0]  ax_b_resp, ax_r_resp;
  wire        ax_b_valid, ax_r_valid_w;
  logic        ax_aw_ready = 1'b1, ax_w_ready = 1'b1, ax_ar_ready = 1'b1;
  logic        ax_b_ready, ax_r_ready;

  logic        r_valid_q = 1'b0;
  logic [31:0] r_data_q;
  logic [1:0]  r_resp_q;
  logic        b_valid_q = 1'b0;
  logic [1:0]  b_resp_q;

  wire ar_fire = ax_ar_valid && ax_ar_ready;
  wire aw_fire = ax_aw_valid && ax_aw_ready;
  wire w_fire  = ax_w_valid  && ax_w_ready;

  wire mem_hit = (ax_ar_addr[31:17] == 15'h0);

  always_ff @(posedge clk) begin
    r_valid_q <= ar_fire;
    if (ar_fire) begin
      r_data_q <= mem_hit ? mem[ax_ar_addr[16:2]] : 32'h0;
      r_resp_q <= mem_hit ? 2'b00 : 2'b10;           // SLVERR
    end
  end

  assign ax_r_valid = r_valid_q;
  assign ax_r_data  = r_data_q;
  assign ax_r_resp  = r_resp_q;

  always_ff @(posedge clk) begin
    b_valid_q <= aw_fire && w_fire;
    if (aw_fire && w_fire) begin
      b_resp_q <= (ax_aw_addr[31:17] == 15'h0) ? 2'b00 : 2'b10;
      if (ax_aw_addr[31:17] == 15'h0) begin
        if (ax_w_strb[0]) mem[ax_aw_addr[16:2]][7:0]   <= ax_w_data[7:0];
        if (ax_w_strb[1]) mem[ax_aw_addr[16:2]][15:8]  <= ax_w_data[15:8];
        if (ax_w_strb[2]) mem[ax_aw_addr[16:2]][23:16] <= ax_w_data[23:16];
        if (ax_w_strb[3]) mem[ax_aw_addr[16:2]][31:24] <= ax_w_data[31:24];
      end
    end
  end
  assign ax_b_valid = b_valid_q;
  assign ax_b_resp  = b_resp_q;

  logic        ame_req_valid, ame_req_ready;
  logic [31:0] ame_req_instr, ame_req_rs1, ame_req_rs2, ame_resp_data;
  logic        ame_resp_valid, ame_resp_err;

  logic        irq;
  logic        halt, wfi, bus_err;
  logic        trace_valid;
  logic [31:0] trace_pc, trace_instr, trace_wdata;
  logic [4:0]  trace_rd;
  logic [1:0]  trace_flag;

  logic [14:0] lfsr;
  logic        xstall;
  wire [6:0]   stall_thr = (stallpct * 127) / 100;
  always_ff @(posedge clk or negedge u_cr.rst_n) begin
    if (!u_cr.rst_n) lfsr <= 15'h0001;
    else lfsr <= {lfsr[13:0], lfsr[14] ^ lfsr[12]};
  end
  assign xstall = (stallpct > 0) && ({1'b0, lfsr[6:0]} < {1'b0, stall_thr});

  tb_ame_model #(.AME_M(16), .AME_N(16)) u_ame (
    .clk_i      (clk),
    .rst_ni     (u_cr.rst_n),
    .req_valid  (ame_req_valid),
    .req_instr  (ame_req_instr),
    .req_rs1    (ame_req_rs1),
    .req_rs2    (ame_req_rs2),
    .req_ready  (ame_req_ready),
    .resp_valid (ame_resp_valid),
    .resp_data  (ame_resp_data),
    .resp_err   (ame_resp_err),
    .xstall_i   (xstall)
  );

  ame_cpu dut (
    .clk_i         (clk),
    .rst_ni        (u_cr.rst_n),
    .ax_aw_addr    (ax_aw_addr),
    .ax_aw_valid   (ax_aw_valid),
    .ax_aw_ready   (ax_aw_ready),
    .ax_w_data     (ax_w_data),
    .ax_w_strb     (ax_w_strb),
    .ax_w_valid    (ax_w_valid),
    .ax_w_ready    (ax_w_ready),
    .ax_b_resp     (ax_b_resp),
    .ax_b_valid    (ax_b_valid),
    .ax_b_ready    (ax_b_ready),
    .ax_ar_addr    (ax_ar_addr),
    .ax_ar_valid   (ax_ar_valid),
    .ax_ar_ready   (ax_ar_ready),
    .ax_r_data     (ax_r_data),
    .ax_r_resp     (ax_r_resp),
    .ax_r_valid    (ax_r_valid),
    .ax_r_ready    (ax_r_ready),
    .ame_req_valid (ame_req_valid),
    .ame_req_instr (ame_req_instr),
    .ame_req_rs1   (ame_req_rs1),
    .ame_req_rs2   (ame_req_rs2),
    .ame_req_ready (ame_req_ready),
    .ame_resp_valid(ame_resp_valid),
    .ame_resp_data (ame_resp_data),
    .ame_resp_err  (ame_resp_err),
    .irq_i         (irq),
    .halt_o        (halt),
    .wfi_o         (wfi),
    .bus_err_o     (bus_err),
    .trace_valid_o (trace_valid),
    .trace_pc_o    (trace_pc),
    .trace_instr_o (trace_instr),
    .trace_rd_o    (trace_rd),
    .trace_wdata_o (trace_wdata),
    .trace_flag_o  (trace_flag)
  );

  integer fdt;
  integer irqat;
  integer j;
  initial begin
    irq    = 1'b0;
    maxcyc = 500000;
    stallpct = 25;
    seed   = 1;
    irqat  = 0;
    if (!$value$plusargs("HEX=%s", hexfile)) begin
      $display("TB FAIL: missing +HEX=");
      $finish;
    end
    if (!$value$plusargs("TRACE=%s", tracefile)) begin
      $display("TB FAIL: missing +TRACE=");
      $finish;
    end
    void_instr = $value$plusargs("MAXCYC=%d", maxcyc);
    void_instr = $value$plusargs("STALLPCT=%d", stallpct);
    void_instr = $value$plusargs("SEED=%d", seed);
    void_instr = $value$plusargs("IRQAT=%d", irqat);
    seed15 = seed[14:0];
    if (seed15 == 15'h0) seed15 = 15'h0001;
    lfsr = seed15;
    fdt = $fopen(tracefile, "w");
    if (fdt == 0) begin
      $display("TB FAIL: cannot open trace file");
      $finish;
    end
    for (j = 0; j < 32768; j = j + 1) mem[j] = 32'h0;
    $readmemh(hexfile, mem);
    repeat (8) @(posedge clk);
    rst_ni = 1'b1;
    if (irqat != 0) begin
      repeat (irqat) @(posedge clk);
      irq = 1'b1;
      repeat (20) @(posedge clk);
      irq = 1'b0;
    end
  end

  integer n_commit = 0;
  always @(posedge clk) begin
    if (trace_valid && u_cr.rst_n) begin
      $fdisplay(fdt, "%08x %08x %02x %08x %1x",
                trace_pc, trace_instr, trace_rd, trace_wdata, trace_flag);
      n_commit <= n_commit + 1;
    end
  end

  logic        prev_vnr = 1'b0;
  logic [31:0] prev_instr = 32'h0, prev_rs1 = 32'h0, prev_rs2 = 32'h0;
  logic        resp_expect_q = 1'b0;
  integer      n_err = 0;

  task tb_error(input [2047:0] msg);
    begin
      $display("TB FAIL: %0s (cyc=%0d pc=%08x)", msg, cyc, trace_pc);
      n_err = n_err + 1;
      $fclose(fdt);
      $finish;
    end
  endtask

  always @(posedge clk) begin
    if (u_cr.rst_n) begin
      if (prev_vnr) begin
        if (!ame_req_valid)                 tb_error("AME req_valid deasserted before ready");
        if (ame_req_instr !== prev_instr)   tb_error("AME req_instr unstable during stall");
        if (ame_req_rs1   !== prev_rs1)     tb_error("AME req_rs1 unstable during stall");
        if (ame_req_rs2   !== prev_rs2)     tb_error("AME req_rs2 unstable during stall");
      end
      if (ame_resp_valid !== resp_expect_q)
        tb_error("AME resp_valid not exactly 1 cycle after accept");
      if (ame_resp_valid && (^ame_resp_data === 1'bx))
        tb_error("AME resp_data is X");

      prev_vnr      <= ame_req_valid && !ame_req_ready;
      prev_instr    <= ame_req_instr;
      prev_rs1      <= ame_req_rs1;
      prev_rs2      <= ame_req_rs2;
      resp_expect_q <= ame_req_valid && ame_req_ready;
    end
  end

  always @(posedge clk) begin
    if (u_cr.rst_n) begin
      if (ax_ar_valid && (^ax_ar_addr === 1'bx)) tb_error("AXI ar_addr is X");
      if (ax_aw_valid && (^ax_aw_addr === 1'bx)) tb_error("AXI aw_addr is X");
    end
  end

  integer cyc = 0;
  always @(posedge clk) cyc <= cyc + 1;

  always @(posedge clk) begin
    if (u_cr.rst_n && cyc > maxcyc) begin
      $display("TB FAIL: watchdog timeout (cyc=%0d, commits=%0d)", cyc, n_commit);
      $fclose(fdt);
      $finish;
    end
  end

  always @(posedge clk) begin
    if (halt) begin
      repeat (4) @(posedge clk);
      $fclose(fdt);
      if (mem[16'h7FFC] === 32'h0000_600D) begin
        $display("TB: self-check magic OK (0x600D)");
      end else begin
        $display("TB NOTE: self-check magic missing (mem[0x7FFC]=%08x)", mem[16'h7FFC]);
      end
      $display("TB: cycles=%0d commits=%0d IPC=%0d.%03d",
               cyc, n_commit, n_commit / (cyc > 0 ? cyc : 1),
               (n_commit * 1000) / (cyc > 0 ? cyc : 1));
      if (n_err != 0) begin
        $display("TB FAIL: %0d protocol errors", n_err);
        $finish;
      end
      $display("PASS");
      $finish;
    end
  end

endmodule
