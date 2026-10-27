//       +EXPECT=... +DUMP=p3d
`timescale 1ns/1ps

module verify_p3d_psram #(
  parameter int unsigned A_BITS = 23
) (
  input  logic              clk_i,
  input  logic [A_BITS-1:0] a_i,
  input  logic [15:0]       di_i,
  output logic [15:0]       do_o,
  input  logic              ce_ni,
  input  logic              oe_ni,
  input  logic              we_ni
);
  localparam int unsigned NW = 1 << (A_BITS - 1);
  logic [15:0] mem [0:NW-1];
  logic [15:0] do_q;

  always_ff @(posedge clk_i) begin
    if (!ce_ni) begin
      if (!we_ni) mem[a_i[A_BITS-1:1]] <= di_i;
      if (!oe_ni) do_q <= mem[a_i[A_BITS-1:1]];
    end
  end
  assign do_o = do_q;

  reg [1023:0] fname;
  initial begin
    do_q = 16'h0000;
    if ($value$plusargs("XMEM_HEX=%s", fname)) begin
      $readmemh(fname, mem);
      $display("[p3d_psram] loaded %0s", fname);
    end else begin
      $display("[p3d_psram] WARN: no +XMEM_HEX; XMEM is X");
    end
  end

  task automatic poke_hw(input longint unsigned idx, input logic [15:0] v);
    mem[idx] = v;
  endtask
  function automatic logic [15:0] peek_hw(input longint unsigned idx);
    peek_hw = mem[idx];
  endfunction
  task automatic poke_addr(input logic [31:0] a, input logic [31:0] v);
    mem[longint'(a & ((1 << A_BITS) - 1)) >> 1]     = v[15:0];
    mem[(longint'(a & ((1 << A_BITS) - 1)) >> 1)+1] = v[31:16];
  endtask
  function automatic logic [31:0] peek_addr(input logic [31:0] a);
    peek_addr = {mem[(longint'(a & ((1 << A_BITS) - 1)) >> 1)+1],
                 mem[longint'(a & ((1 << A_BITS) - 1)) >> 1]};
  endfunction
endmodule

module verify_soc_e2e;

  localparam int BIT_CYC = 13;             // UART DIV(与微内核一致)
  localparam real CLKP = 10.0;             // 100 MHz(周期数口径与频率无关)
  localparam int MAX_CYC = 40_000_000;     // 看门狗

  logic clk = 1'b0;
  logic rst_ni = 1'b0;
  logic uart_tx;
  logic irq;
  logic [3:0] gpio;
  logic [15:0] xmem_di;
  logic [22:0] xmem_a;
  logic [15:0] xmem_do;
  logic xmem_ce_n, xmem_oe_n, xmem_we_n, xmem_clk;

  always #(CLKP/2.0) clk = ~clk;

  amechip_top dut (
    .clk_i(clk), .rst_ni(rst_ni),
    .uart_tx_o(uart_tx), .uart_rx_i(1'b1),
    .xmem_clk_o(xmem_clk), .xmem_a_o(xmem_a),
    .xmem_di_i(xmem_di), .xmem_do_o(xmem_do),
    .xmem_ce_no(xmem_ce_n), .xmem_oe_no(xmem_oe_n), .xmem_we_no(xmem_we_n),
    .xmem_wait_i(1'b0),
    .gpio_i(4'h0), .gpio_o(gpio), .irq_o(irq)
  );

  verify_p3d_psram u_psram (
    .clk_i(clk), .a_i(xmem_a), .di_i(xmem_do), .do_o(xmem_di),
    .ce_ni(xmem_ce_n), .oe_ni(xmem_oe_n), .we_ni(xmem_we_n)
  );

  longint unsigned cyc_total;
  longint unsigned cyc_ame_busy, cyc_mac, cyc_dma_busy, cyc_xmem_act, cyc_kv_busy;
  always_ff @(posedge clk) begin
    if (!rst_ni) begin
      cyc_total <= 0; cyc_ame_busy <= 0; cyc_mac <= 0;
      cyc_dma_busy <= 0; cyc_xmem_act <= 0; cyc_kv_busy <= 0;
    end else begin
      cyc_total <= cyc_total + 1;
      if (gpio[1])          cyc_ame_busy <= cyc_ame_busy + 1;   // AME busy
      if (dut.u_ame.u_core.dbg_mac_en_o) cyc_mac <= cyc_mac + 1;
      if (dut.u_mem.u_mem_ss.u_dma.busy_q) cyc_dma_busy <= cyc_dma_busy + 1;
      if (!xmem_ce_n)       cyc_xmem_act <= cyc_xmem_act + 1;
      if (dut.u_mem.u_mem_ss.u_kvc.busy_q) cyc_kv_busy <= cyc_kv_busy + 1;
    end
  end

  logic [7:0] rx_byte;
  integer     nbytes;
  logic [7:0] rx_all [0:65535];

  task automatic recv_byte(output logic [7:0] b);
    integer i;
    begin
      @(negedge uart_tx);
      #(BIT_CYC * CLKP / 2.0);
      for (i = 0; i < 8; i++) begin
        #(BIT_CYC * CLKP);
        b[i] = uart_tx;
      end
      #(BIT_CYC * CLKP);
    end
  endtask

  initial begin : uart_rx_proc
    nbytes = 0;
    forever begin
      recv_byte(rx_byte);
      if (nbytes < 65536) rx_all[nbytes] = rx_byte;
      nbytes = nbytes + 1;
      if (rx_byte == 8'h0A) line_cnt = line_cnt + 1;
      $write("%c", rx_byte);
      $fflush();
    end
  end

  logic en_trace, en_ins, en_bus, en_wave;
  initial begin
    en_trace = $test$plusargs("TRACE");
    en_ins   = $test$plusargs("TRACEINSTR");
    en_bus   = $test$plusargs("TRACEBUS");
    en_wave  = $test$plusargs("WAVE");
  end

  integer      e_prompts;
  integer      line_cnt;
  longint      t0;
  logic [1023:0] dump_prefix;
  logic        boot_only;
  logic        do_dump;

  task automatic dump_hex(input string fn, input longint unsigned base_b, input int nwords);
    integer fd, i;
    logic [31:0] v;
    begin
      fd = $fopen(fn, "w");
      for (i = 0; i < nwords; i = i + 1) begin
        v = u_psram.peek_addr(32'(base_b) + 32'(i*4));
        $fwrite(fd, "%08X\n", v);
      end
      $fclose(fd);
      $display("[p3d_tb] dumped %0s (%0d words) base=0x%08X", fn, nwords, base_b);
    end
  endtask

  integer errs;
  initial begin
    errs = 0; line_cnt = 0;
    if (!$value$plusargs("EPROMPTS=%d", e_prompts)) e_prompts = 3;
    boot_only = $test$plusargs("BOOT_ONLY");
    dump_prefix = "p3d";
    if ($value$plusargs("DUMP=%s", dump_prefix)) do_dump = 1'b1; else do_dump = 1'b0;

    $display("[p3d_tb] reset");
    rst_ni = 1'b0;
    repeat (20) @(posedge clk);
    rst_ni = 1'b1;
    t0 = cyc_total;

    while (!(dut.u_cpu.u_core.halt_o === 1'b1 || (boot_only && line_cnt >= 1)) &&
           cyc_total < MAX_CYC) @(posedge clk);
    if (dut.u_cpu.u_core.halt_o === 1'b1 || (boot_only && line_cnt >= 1)) begin
      $display("[p3d_tb] done observed @cycle %0d (halt=%b lines=%0d)",
               cyc_total, dut.u_cpu.u_core.halt_o, line_cnt);
    end else begin
      $display("[p3d_tb] FATAL: TIMEOUT after %0d cycles, %0d UART bytes", MAX_CYC, nbytes);
      errs = errs + 1;
    end

    repeat (2000) @(posedge clk);   // 让 UART TX FIFO 排空

    $display("\n[p3d_tb] ---- UART (%0d bytes) ----", nbytes);
    for (int i = 0; i < nbytes; i = i + 1) $write("%c", rx_all[i]);
    $write("\n");

    if (boot_only) begin
      if (nbytes >= 8) $display("P3D BOOT PASS");
      else begin $display("P3D BOOT FAIL"); errs = errs + 1; end
    end

    if (do_dump) begin
      for (int p = 0; p < e_prompts; p = p + 1) begin
        dump_hex($sformatf("%0s_yq_p%0d.hex", dump_prefix, p),
                 64'h0000_0000_4060_0000 + longint'(p) * 64'h10000 + 64'h1000, 2560);
        dump_hex($sformatf("%0s_y32_p%0d.hex", dump_prefix, p),
                 64'h0000_0000_4060_0000 + longint'(p) * 64'h10000 + 64'h4000, 8192);
      end
      dump_hex($sformatf("%0s_kv.hex", dump_prefix), 64'h0000_0000_4040_0000, 65536);
      dump_hex($sformatf("%0s_exc.hex", dump_prefix), 64'h0000_0000_406F_0000, 16);
    end

    $display("[p3d_tb] cycles: total=%0d ame_busy=%0d mac=%0d dma_busy=%0d xmem_act=%0d kv_busy=%0d",
             cyc_total, cyc_ame_busy, cyc_mac, cyc_dma_busy, cyc_xmem_act, cyc_kv_busy);
    $display("[p3d_tb] util: AME_BUSY=%0.2f%% MAC=%0.2f%% DMA_BUSY=%0.2f%% XMEM_ACT=%0.2f%% KV_BUSY=%0.2f%%",
             100.0 * cyc_ame_busy / cyc_total, 100.0 * cyc_mac / cyc_total,
             100.0 * cyc_dma_busy / cyc_total, 100.0 * cyc_xmem_act / cyc_total,
             100.0 * cyc_kv_busy / cyc_total);

    $display("P3D SOC E2E %s (%0d errors)", (errs == 0) ? "PASS" : "FAIL", errs);
    $finish;
  end

  logic en_tile;
  initial en_tile = $test$plusargs("DUMPTILE");
  integer wb_dumped = 0, tile_dumped = 0, dfd, ii, jj;
  always @(posedge clk) begin
    if (en_tile && !wb_dumped && dut.u_ame_coproc.req_valid && dut.u_ame_coproc.req_ready &&
        dut.u_ame_coproc.req_instr[6:0] == 7'h0b &&
        dut.u_ame_coproc.req_instr[14:12] == 3'b010) begin
      dfd = $fopen("p3d_wbuf0.hex", "w");
      for (ii = 0; ii < 256; ii = ii + 1)
        $fwrite(dfd, "%02X\n", dut.u_ame.u_core.u_wbuf.mem[ii]);
      $fclose(dfd);
      dfd = $fopen("p3d_xbuf0.hex", "w");
      for (ii = 0; ii < 256; ii = ii + 1)
        $fwrite(dfd, "%02X\n", dut.u_ame.u_core.u_xbuf.mem[ii]);
      $fclose(dfd);
      wb_dumped = 1;
    end
    if (en_tile && !tile_dumped && dut.u_ame_coproc.req_valid && dut.u_ame_coproc.req_ready &&
        dut.u_ame_coproc.req_instr[6:0] == 7'h0b &&
        dut.u_ame_coproc.req_instr[14:12] == 3'b100) begin
      dfd = $fopen("p3d_tile0.hex", "w");
      for (ii = 0; ii < 16; ii = ii + 1)
        for (jj = 0; jj < 16; jj = jj + 1)
          $fwrite(dfd, "%02X\n", dut.u_ame.u_core.u_array.tile_q[0][ii][jj]);
      $fclose(dfd);
      dfd = $fopen("p3d_xreg0.hex", "w");
      for (ii = 0; ii < 16; ii = ii + 1)
        $fwrite(dfd, "%02X\n", dut.u_ame.u_core.u_array.x_q[0][ii]);
      $fclose(dfd);
      tile_dumped = 1;
    end
  end

  logic en_memc; initial en_memc = $test$plusargs("TRACEMEMC");
  integer nmemc = 0;
  always @(posedge clk) begin
    if (en_memc && nmemc < 40 &&
        ((dut.u_mem.u_mem_ss.u_memc.ar_valid_i &&
          dut.u_mem.u_mem_ss.u_memc.ar_addr_i >= 32'h4052_0180 && dut.u_mem.u_mem_ss.u_memc.ar_addr_i < 32'h4052_01C0) ||
         (dut.u_mem.u_mem_ss.u_memc.r_valid_o &&
          dut.u_mem.u_mem_ss.u_memc.r_head_a >= 23'h52_0180 && dut.u_mem.u_mem_ss.u_memc.r_head_a < 23'h52_01C0))) begin
      $display("[p3d_memc] t=%0t arv=%b ara=%08x rv=%b st=%0d head=%06x hw0=%04x di=%04x rd=%08x mem=%04x/%04x",
               $time,
               dut.u_mem.u_mem_ss.u_memc.ar_valid_i,
               dut.u_mem.u_mem_ss.u_memc.ar_addr_i,
               dut.u_mem.u_mem_ss.u_memc.r_valid_o,
               dut.u_mem.u_mem_ss.u_memc.st_q,
               dut.u_mem.u_mem_ss.u_memc.r_head_a,
               dut.u_mem.u_mem_ss.u_memc.hw0_q,
               dut.u_mem.u_mem_ss.u_memc.xmem_di_i,
               dut.u_mem.u_mem_ss.u_memc.r_data_o,
               u_psram.mem[23'h29_00C0], u_psram.mem[23'h29_00C1]);
      nmemc = nmemc + 1;
    end
  end

  logic en_lay, en_desc;
  initial begin en_lay = $test$plusargs("TRACELAY"); en_desc = $test$plusargs("TRACEDESC"); end
  integer nlay = 0, ndesc = 0;
  always @(posedge clk) begin
    if (en_lay && rst_ni && dut.u_cpu.u_core.trace_valid_o && nlay < 80 &&
        (dut.u_cpu.u_core.trace_pc_o == 32'h1b0 || dut.u_cpu.u_core.trace_pc_o == 32'h2bc)) begin
      $display("[p3d_lay] %0s pc=%08x cyc=%0d",
               (dut.u_cpu.u_core.trace_pc_o == 32'h1b0) ? "do_layer" : "gemv_w",
               dut.u_cpu.u_core.trace_pc_o, cyc_total);
      nlay = nlay + 1;
    end
    if (en_desc && rst_ni && ndesc < 200 && dut.u_cpu.u_core.dm_rvalid &&
        dut.u_cpu.u_core.dm_addr >= 32'h4052_0100 && dut.u_cpu.u_core.dm_addr < 32'h4052_0200) begin
      $display("[p3d_desc] t=%0t a=%08x rd=%08x", $time,
               dut.u_cpu.u_core.dm_addr, dut.u_cpu.u_core.dm_rdata);
      ndesc = ndesc + 1;
    end
  end

  integer name_req = 0;
  always @(posedge clk) begin
    if (rst_ni && dut.u_ame_coproc.req_valid && dut.u_ame_coproc.req_ready && name_req < 400) begin
      $display("[ame_req] i=%08x rs1=%08x rs2=%08x", dut.u_ame_coproc.req_instr,
               dut.u_ame_coproc.req_rs1, dut.u_ame_coproc.req_rs2);
      name_req = name_req + 1;
    end
    if (rst_ni && dut.u_ame_coproc.resp_valid && name_req < 400)
      $display("[ame_rsp] d=%08x e=%b", dut.u_ame_coproc.resp_data, dut.u_ame_coproc.resp_err);
  end

  integer natt = 0;
  always @(posedge clk) begin
    if (en_ins && rst_ni && dut.u_cpu.u_core.trace_valid_o &&
        dut.u_cpu.u_core.trace_pc_o >= 32'h778 && dut.u_cpu.u_core.trace_pc_o < 32'h9C8 &&
        natt < 300) begin
      $display("[p3d_att] pc=%08x instr=%08x rd=%0d wd=%08x fl=%b",
               dut.u_cpu.u_core.trace_pc_o, dut.u_cpu.u_core.trace_instr_o,
               dut.u_cpu.u_core.trace_rd_o, dut.u_cpu.u_core.trace_wdata_o,
               dut.u_cpu.u_core.trace_flag_o);
      natt = natt + 1;
    end
  end

  logic en_kvr; initial en_kvr = $test$plusargs("TRACEKVR");
  integer nkvr = 0, nkvd = 0;
  always @(posedge clk) begin
    if (en_kvr && rst_ni && dut.u_mem.u_mem_ss.u_kvc.busy_q &&
        dut.u_mem.u_mem_ss.u_kvc.m_ar_valid_o && dut.u_mem.u_mem_ss.u_kvc.m_ar_ready_i &&
        nkvr < 20) begin
      $display("[p3d_kvr] t=%0t ar=%08x", $time, dut.u_mem.u_mem_ss.u_kvc.m_ar_addr_o);
      nkvr = nkvr + 1;
    end
    if (en_kvr && rst_ni && dut.u_mem.u_mem_ss.u_kvc.m_r_valid_i && nkvd < 20) begin
      $display("[p3d_kvd] t=%0t rd=%08x", $time, dut.u_mem.u_mem_ss.u_kvc.m_r_data_i);
      nkvd = nkvd + 1;
    end
  end

  logic en_kvw; initial en_kvw = $test$plusargs("TRACEKVW");
  integer nkvw = 0;
  always @(posedge clk) begin
    if (en_kvw && rst_ni && nkvw < 40 && dut.u_mem.u_mem_ss.u_kvc.busy_q &&
        dut.u_mem.u_mem_ss.u_memc.aw_valid_i) begin
      $display("[p3d_kvw] t=%0t aw=%08x wd=%08x", $time,
               dut.u_mem.u_mem_ss.u_memc.aw_addr_i,
               dut.u_mem.u_mem_ss.u_memc.w_data_i);
      nkvw = nkvw + 1;
    end
  end

  logic kverr_d = 1'b0;
  always @(posedge clk) begin
    kverr_d <= dut.u_mem.u_mem_ss.u_kvc.err_q;
    if (rst_ni && dut.u_mem.u_mem_ss.u_kvc.err_q && !kverr_d)
      $display("[p3d_kverr] t=%0t code=%0d", $time, dut.u_mem.u_mem_ss.u_kvc.errcode_q);
  end

  logic en_kvdump; initial en_kvdump = $test$plusargs("KVDUMP");
  logic kv0_dumped = 1'b0;
  logic en_x1; initial en_x1 = $test$plusargs("DUMPX1");
  integer x1_state = 0;
  always @(posedge clk) begin
    if (en_x1) begin
      if (x1_state == 0 && dut.u_mem.u_mem_ss.u_dma.reg_src == 32'h4052_1700 &&
          dut.u_mem.u_mem_ss.u_dma.busy_q) x1_state <= 1;
      else if (x1_state == 1 && !dut.u_mem.u_mem_ss.u_dma.busy_q) begin
        dfd = $fopen("p3d_xbuf_p1g13.hex", "w");
        for (ii = 0; ii < 256; ii = ii + 1)
          $fwrite(dfd, "%02X\n", dut.u_ame.u_core.u_xbuf.mem[ii]);
        $fclose(dfd);
        x1_state <= 2;
      end
    end
  end

  logic [31:0] s0_prev = 32'h0;
  logic [31:0] s1_prev = 32'h0;
  always @(posedge clk) begin
    if (rst_ni) begin
      if (dut.u_sys.scratch0_q !== s0_prev) begin
        if (dut.u_sys.scratch0_q[31:28] == 4'hA)
          $display("[p3d_mark] S %0d cyc=%0d ame=%0d mac=%0d dma=%0d xmem=%0d kv=%0d",
                   dut.u_sys.scratch0_q[1:0], cyc_total, cyc_ame_busy, cyc_mac,
                   cyc_dma_busy, cyc_xmem_act, cyc_kv_busy);
        s0_prev <= dut.u_sys.scratch0_q;
      end
      if (dut.u_sys.scratch1_q !== s1_prev) begin
        if (dut.u_sys.scratch1_q[31:28] == 4'hB) begin
          $display("[p3d_mark] E %0d cyc=%0d ame=%0d mac=%0d dma=%0d xmem=%0d kv=%0d",
                   dut.u_sys.scratch1_q[1:0], cyc_total, cyc_ame_busy, cyc_mac,
                   cyc_dma_busy, cyc_xmem_act, cyc_kv_busy);
          if (en_kvdump && !kv0_dumped && dut.u_sys.scratch1_q[1:0] == 2'd0) begin
            kv0_dumped <= 1'b1;
            dump_hex("p3d_kv_p0.hex", 64'h0000_0000_4040_0000, 65536);
            dump_hex("p3d_kvnew_p0.hex", 64'h0000_0000_4050_5000, 128);
          end
        end
        else if (dut.u_sys.scratch1_q != 32'h0)
          $display("[p3d_tok] %0d", dut.u_sys.scratch1_q);
        s1_prev <= dut.u_sys.scratch1_q;
      end
    end
  end

  integer nbus = 0;
  logic   bus_req_d = 1'b0;
  always @(posedge clk) begin
    bus_req_d <= dut.u_cpu.bus_req.valid;
    if (en_bus && rst_ni && nbus < 60 &&
        dut.u_cpu.bus_req.addr[31:16] == 16'h2000 &&
        dut.u_cpu.bus_req.addr[15:12] == 4'h3 &&
        (dut.u_cpu.bus_req.valid || dut.u_cpu.bus_resp.valid)) begin
      $display("[p3d_bus] t=%0t req v=%b w=%b a=%08x d=%08x | rsp v=%b d=%08x e=%b",
               $time,
               dut.u_cpu.bus_req.valid, dut.u_cpu.bus_req.write,
               dut.u_cpu.bus_req.addr, dut.u_cpu.bus_req.wdata,
               dut.u_cpu.bus_resp.valid, dut.u_cpu.bus_resp.rdata,
               dut.u_cpu.bus_resp.resp);
      nbus = nbus + 1;
    end
  end

  integer ndm = 0;
  always @(posedge clk) begin
    if (en_bus && rst_ni && ndm < 200 &&
        ((dut.u_cpu.u_core.dm_req_valid && !dut.u_cpu.u_core.dm_we &&
          dut.u_cpu.u_core.dm_addr[31:28] == 4'h2) ||
         (dut.u_cpu.u_core.dm_rvalid && dut.u_cpu.u_core.dm_addr[31:28] == 4'h2))) begin
      $display("[p3d_dm] t=%0t reqv=%b we=%b a=%08x wd=%08x | rv=%b rd=%08x err=%b",
               $time, dut.u_cpu.u_core.dm_req_valid, dut.u_cpu.u_core.dm_we,
               dut.u_cpu.u_core.dm_addr, dut.u_cpu.u_core.dm_wdata,
               dut.u_cpu.u_core.dm_rvalid, dut.u_cpu.u_core.dm_rdata,
               dut.u_cpu.u_core.dm_err);
      ndm = ndm + 1;
    end
  end

  integer tinstr = 0;
  always @(posedge clk) begin
    if (en_ins && rst_ni && dut.u_cpu.u_core.trace_valid_o &&
        dut.u_cpu.u_core.trace_pc_o < 32'h1000 && tinstr < 5000) begin
      $display("[p3d_ins] pc=%08x instr=%08x rd=%0d wd=%08x fl=%b",
               dut.u_cpu.u_core.trace_pc_o, dut.u_cpu.u_core.trace_instr_o,
               dut.u_cpu.u_core.trace_rd_o, dut.u_cpu.u_core.trace_wdata_o,
               dut.u_cpu.u_core.trace_flag_o);
      tinstr = tinstr + 1;
    end
  end

  initial begin
    if (en_trace) begin
      forever begin
        repeat (20000) @(posedge clk);
        $display("[p3d_dbg] t=%0t cyc=%0d pc=%08x dma=%b src=%08x dst=%08x xc=%0d yc=%0d rd_y=%0d wr_y=%0d fifo=%0d err=%b disc=%b st=%b",
                 $time, cyc_total, dut.u_cpu.u_core.pc_q,
                 dut.u_mem.u_mem_ss.u_dma.busy_q,
                 dut.u_mem.u_mem_ss.u_dma.reg_src, dut.u_mem.u_mem_ss.u_dma.reg_dst,
                 dut.u_mem.u_mem_ss.u_dma.reg_xcnt, dut.u_mem.u_mem_ss.u_dma.reg_ycnt,
                 dut.u_mem.u_mem_ss.u_dma.rd_y, dut.u_mem.u_mem_ss.u_dma.wr_y,
                 dut.u_mem.u_mem_ss.u_dma.fifo_cnt,
                 dut.u_mem.u_mem_ss.u_dma.err_q, dut.u_mem.u_mem_ss.u_dma.discard_q,
                 dut.u_mem.u_mem_ss.u_dma.busy_q);
        $display("[p3d_cpu] stall=%b lduse=%b amew=%b mulw=%b memb=%b idexv=%b idexpc=%08x idexi=%08x ifv=%b exmv=%b fetchinfl=%b dmv=%b dma=%08x dmrv=%b",
                 dut.u_cpu.u_core.stall, dut.u_cpu.u_core.ex_stall_loaduse,
                 dut.u_cpu.u_core.ame_waiting, dut.u_cpu.u_core.mul_waiting,
                 dut.u_cpu.u_core.mem_busy, dut.u_cpu.u_core.idex_valid,
                 dut.u_cpu.u_core.idex_pc, dut.u_cpu.u_core.idex_instr,
                 dut.u_cpu.u_core.if_id_valid_q, dut.u_cpu.u_core.exmem_valid,
                 dut.u_cpu.u_core.fetch_infl_q, dut.u_cpu.u_core.dm_req_valid,
                 dut.u_cpu.u_core.dm_addr, dut.u_cpu.u_core.dm_rvalid);
        $display("[p3d_ame] busy=%b idle=%b rdy=%b err=%b macbusy=%b phase=%0d wld=%b xld=%b wldn=%0d cfgne=%0d kvbusy=%b kvst=%b",
                 dut.u_ame.u_core.st_busy, dut.u_ame.u_core.idle, dut.u_ame.u_core.st_rdy,
                 dut.u_ame.u_core.st_err, dut.u_ame.u_core.u_ctrl.mac_busy_q,
                 dut.u_ame.u_core.u_ctrl.mac_phase_q, dut.u_ame.u_core.u_ctrl.wld_active_q,
                 dut.u_ame.u_core.u_ctrl.xld_active_q, dut.u_ame.u_core.u_ctrl.wld_n_q,
                 dut.u_ame.u_core.u_ctrl.cfg_n_eff_q,
                 dut.u_mem.u_mem_ss.u_kvc.busy_q, dut.u_mem.u_mem_ss.u_kvc.st_q);
        $display("[p3d_mem] psram[0..3]=%04x %04x %04x %04x ocram[0..2]=%08x %08x %08x",
                 u_psram.mem[0], u_psram.mem[1], u_psram.mem[2], u_psram.mem[3],
                 dut.u_mem.u_mem_ss.u_ocram.u_ram.mem[0],
                 dut.u_mem.u_mem_ss.u_ocram.u_ram.mem[1],
                 dut.u_mem.u_mem_ss.u_ocram.u_ram.mem[2]);
        $display("[p3d_dmax] rdx=%0d rdy=%0d wrx=%0d wry=%0d fifo=%0d rinfl=%0d winfl=%0d sxc=%0d syc=%0d done=%b busy=%b",
                 dut.u_mem.u_mem_ss.u_dma.rd_x, dut.u_mem.u_mem_ss.u_dma.rd_y,
                 dut.u_mem.u_mem_ss.u_dma.wr_x, dut.u_mem.u_mem_ss.u_dma.wr_y,
                 dut.u_mem.u_mem_ss.u_dma.fifo_cnt,
                 dut.u_mem.u_mem_ss.u_dma.rd_inflight,
                 dut.u_mem.u_mem_ss.u_dma.wr_inflight,
                 dut.u_mem.u_mem_ss.u_dma.s_xcnt, dut.u_mem.u_mem_ss.u_dma.s_ycnt,
                 dut.u_mem.u_mem_ss.u_dma.done_q, dut.u_mem.u_mem_ss.u_dma.busy_q);
        $display("[p3d_csr] cpu_ar=%08x av=%b rv=%b rd=%08x | dma done=%b busy=%b ra=%0d rdata=%08x",
                 dut.u_cpu.u_core.ax_ar_addr, dut.u_cpu.u_core.ax_ar_valid,
                 dut.u_cpu.u_core.ax_r_valid, dut.u_cpu.u_core.ax_r_data,
                 dut.u_mem.u_mem_ss.u_dma.done_q, dut.u_mem.u_mem_ss.u_dma.busy_q,
                 dut.u_mem.u_mem_ss.u_dma.csr_raddr_q,
                 dut.u_mem.u_mem_ss.u_dma.csr_r_data_o);
      end
    end
  end

  initial begin
    if (en_wave) begin
      $dumpfile("p3d_soc.vcd");
      $dumpvars(0, verify_soc_e2e);
    end
  end

endmodule
