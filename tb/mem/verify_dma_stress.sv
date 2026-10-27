`timescale 1ns/1ps
`include "amechip_pkg.sv"

module verify_dma_stress;

  localparam int MAXOPS   = 512;
  localparam int MAXWORDS = 60000;
  localparam int MAXPRE   = 60000;
  localparam int MAXFIN   = 40000;

  logic clk = 1'b0;
  logic rst_n;
  always #5 clk = ~clk;

  logic        c_aw_valid, c_aw_ready; logic [31:0] c_aw_addr;
  logic        c_w_valid, c_w_ready;   logic [31:0] c_w_data; logic [3:0] c_w_strb;
  logic        c_b_valid, c_b_ready;   logic [1:0]  c_b_resp;
  logic        c_ar_valid, c_ar_ready; logic [31:0] c_ar_addr;
  logic        c_r_valid, c_r_ready;   logic [31:0] c_r_data; logic [1:0] c_r_resp;
  logic        irq_line;

  verify_dut #(.KV_BACKEND_B(1'b1), .KV_CTX(128)) u_dut (
    .clk_i(clk), .rst_ni(rst_n),
    .cpu_aw_valid_i(c_aw_valid), .cpu_aw_ready_o(c_aw_ready),
    .cpu_aw_addr_i(c_aw_addr),
    .cpu_w_valid_i(c_w_valid), .cpu_w_ready_o(c_w_ready),
    .cpu_w_data_i(c_w_data), .cpu_w_strb_i(c_w_strb),
    .cpu_b_valid_o(c_b_valid), .cpu_b_ready_i(c_b_ready), .cpu_b_resp_o(c_b_resp),
    .cpu_ar_valid_i(c_ar_valid), .cpu_ar_ready_o(c_ar_ready),
    .cpu_ar_addr_i(c_ar_addr),
    .cpu_r_valid_o(c_r_valid), .cpu_r_ready_i(c_r_ready),
    .cpu_r_data_o(c_r_data), .cpu_r_resp_o(c_r_resp),
    .irq_line_o(irq_line)
  );

  `include "tb_bfm_tasks.svh"

  logic [31:0] ops  [0:MAXOPS*16-1];
  logic [31:0] rda  [0:MAXWORDS-1];
  logic [31:0] rdd  [0:MAXWORDS-1];
  logic [31:0] wra  [0:MAXWORDS-1];
  logic [31:0] wrd  [0:MAXWORDS-1];
  logic [31:0] prea [0:MAXPRE-1];
  logic [31:0] pred [0:MAXPRE-1];
  logic [31:0] fina [0:MAXFIN-1];
  logic [31:0] find [0:MAXFIN-1];
  logic [31:0] counts [0:4];

  int nops, nrd, nwr, npre, nfinal;
  int rd_ptr, rdd_ptr, wr_ptr;
  int stream_en;
  int errors, checks;
  int nclean, nerr, nconc, nwords;
  longint cyc_cnt;
  logic [31:0] got_final;

  always @(posedge clk) cyc_cnt <= cyc_cnt + 1;

  function automatic logic [31:0] word_of(input logic [31:0] a);
    word_of = (a[31:2] * 32'h9E37_79B9) + 32'h7F4A_7C15;
  endfunction

  task automatic fail(input string msg);
    errors = errors + 1;
    if (errors <= 40) $display("[FAIL] %0t %s", $time, msg);
  endtask

  task automatic peek_any(input logic [31:0] a, output logic [31:0] d);
    logic [1:0] rsp;
    begin : body
      @(negedge clk);
      c_aw_valid = 1'b0; c_w_valid = 1'b0;
      c_ar_valid = 1'b1; c_ar_addr = a; c_r_ready = 1'b0;
      @(posedge clk);
      while (!c_ar_ready) @(posedge clk);
      @(negedge clk);
      c_ar_valid = 1'b0;
      forever begin
        @(negedge clk);
        if (c_r_valid) begin
          d = c_r_data; rsp = c_r_resp;
          c_r_ready = 1'b1;
          @(negedge clk);
          c_r_ready = 1'b0;
          checks = checks + 1;
          if (rsp !== 2'b00) fail($sformatf("回读 @%08h resp=%b", a, rsp));
          disable body;
        end
      end
    end
  endtask

  task automatic load_files();
    begin
      for (int i = 0; i < MAXOPS*16; i++) ops[i] = '0;
      for (int i = 0; i < MAXWORDS; i++) begin
        rda[i] = '0; rdd[i] = '0; wra[i] = '0; wrd[i] = '0;
      end
      for (int i = 0; i < MAXPRE; i++) begin prea[i] = '0; pred[i] = '0; end
      for (int i = 0; i < MAXFIN; i++) begin fina[i] = '0; find[i] = '0; end
      for (int i = 0; i < 5; i++) counts[i] = '0;
      $readmemh("dma_ops.hex", ops);
      $readmemh("dma_rd_addr.hex", rda);
      $readmemh("dma_rd_data.hex", rdd);
      $readmemh("dma_wr_addr.hex", wra);
      $readmemh("dma_wr_data.hex", wrd);
      $readmemh("dma_pre_addr.hex", prea);
      $readmemh("dma_pre_data.hex", pred);
      $readmemh("dma_final_addr.hex", fina);
      $readmemh("dma_final_data.hex", find);
      $readmemh("dma_counts.hex", counts);
      nops   = int'(counts[0]);
      nrd    = int'(counts[1]);
      nwr    = int'(counts[2]);
      npre   = int'(counts[3]);
      nfinal = int'(counts[4]);
    end
  endtask

  wire dut_rd_ar_fire = u_dut.u_mem.u_dma.rd_ar_valid_o &&
                        u_dut.u_mem.u_dma.rd_ar_ready_i;
  wire dut_rd_r_fire  = u_dut.u_mem.u_dma.rd_r_valid_i &&
                        u_dut.u_mem.u_dma.rd_r_ready_o;
  wire dut_wr_fire    = u_dut.u_mem.u_dma.wr_aw_valid_o &&
                        u_dut.u_mem.u_dma.wr_aw_ready_i &&
                        u_dut.u_mem.u_dma.wr_w_valid_o &&
                        u_dut.u_mem.u_dma.wr_w_ready_i;
  wire [31:0] dut_rd_ar_addr = u_dut.u_mem.u_dma.rd_ar_addr_o;
  wire [31:0] dut_rd_r_data  = u_dut.u_mem.u_dma.rd_r_data_i;
  wire [31:0] dut_wr_aw_addr = u_dut.u_mem.u_dma.wr_aw_addr_o;
  wire [31:0] dut_wr_w_data  = u_dut.u_mem.u_dma.wr_w_data_o;
  wire [3:0]  dut_wr_w_strb  = u_dut.u_mem.u_dma.wr_w_strb_o;
  wire        dut_busy       = u_dut.u_mem.u_dma.busy_q;

  always @(posedge clk) begin
    if (rst_n && stream_en) begin
      if (dut_rd_ar_fire) begin
        checks = checks + 1;
        if (rd_ptr >= nrd) fail("DMA 读地址流超出期望");
        else if (dut_rd_ar_addr !== rda[rd_ptr])
          fail($sformatf("DMA RD addr[%0d] got=%08h exp=%08h",
               rd_ptr, dut_rd_ar_addr, rda[rd_ptr]));
        rd_ptr = rd_ptr + 1;
      end
      if (dut_rd_r_fire) begin
        checks = checks + 1;
        if (rdd_ptr >= nrd) fail("DMA 读数据流超出期望");
        else if (dut_rd_r_data !== rdd[rdd_ptr])
          fail($sformatf("DMA RD data[%0d] got=%08h exp=%08h",
               rdd_ptr, dut_rd_r_data, rdd[rdd_ptr]));
        rdd_ptr = rdd_ptr + 1;
      end
      if (dut_wr_fire) begin
        checks = checks + 1;
        if (wr_ptr >= nwr) fail("DMA 写流超出期望");
        else begin
          if (dut_wr_aw_addr !== wra[wr_ptr])
            fail($sformatf("DMA WR addr[%0d] got=%08h exp=%08h",
                 wr_ptr, dut_wr_aw_addr, wra[wr_ptr]));
          if (dut_wr_w_data !== wrd[wr_ptr])
            fail($sformatf("DMA WR data[%0d] got=%08h exp=%08h",
                 wr_ptr, dut_wr_w_data, wrd[wr_ptr]));
          if (dut_wr_w_strb !== 4'hF) fail("DMA WR strb != F");
        end
        wr_ptr = wr_ptr + 1;
      end
    end
  end

  task automatic wait_dma_busy_clear();
    int guard;
    begin
      @(posedge clk); @(posedge clk);
      guard = 0;
      while (dut_busy && guard < 20_000_000) begin
        @(posedge clk);
        guard = guard + 1;
      end
      if (guard >= 20_000_000) fail("DMA BUSY 超时(疑似死锁)");
    end
  endtask

  task automatic read_dma_status(output logic [31:0] st);
    begin
      axi_read(amechip_pkg::A_DMA_BASE + amechip_pkg::DMA_STATUS_OFF, st);
    end
  endtask

  task automatic cpu_traffic(input int n);
    logic [31:0] d, exp;
    begin
      for (int i = 0; i < n; i++) begin
        axi_write(32'h0000_0800 + 4 * (i % 64), 32'hBEEF_0000 + i);
        peek_any(32'h0000_0800 + 4 * (i % 64), d);
        checks = checks + 1;
        if (d !== (32'hBEEF_0000 + i))
          fail($sformatf("CPU 并发 OCSRAM 读回 got=%08h exp=%08h", d, 32'hBEEF_0000 + i));
        peek_any(32'h4010_0000 + 4 * (i % 64), d);
        exp = word_of(32'h4010_0000 + 4 * (i % 64));
        checks = checks + 1;
        if (d !== exp)
          fail($sformatf("CPU 并发 XMEM 读 got=%08h exp=%08h", d, exp));
      end
    end
  endtask

  task automatic run_op(input int c);
    logic [31:0] w0, st, pend;
    logic [31:0] src, dst, xc, yc, sp, dp;
    int ab;
    bit irq, sfix, dfix, exp_err, chk_stream, busy_ign, conc;
    logic [3:0] exp_code;
    int rd0, wr0;
    begin
      w0 = ops[c*16 + 0];
      irq        = w0[0];
      sfix       = w0[1];
      dfix       = w0[2];
      exp_err    = w0[3];
      exp_code   = w0[7:4];
      chk_stream = w0[8];
      busy_ign   = w0[10];
      conc       = w0[11];
      src = ops[c*16+1]; dst = ops[c*16+2];
      xc  = ops[c*16+3]; yc  = ops[c*16+4];
      sp  = ops[c*16+5]; dp  = ops[c*16+6];
      ab  = int'(ops[c*16+7]);

      stream_en = chk_stream ? 1 : 0;
      rd0 = rd_ptr; wr0 = wr_ptr;

      dma_cfg(src, dst, xc, yc, sp, dp,
              (irq ? 32'h10 : 32'h0) | (sfix ? 32'h4 : 32'h0) |
              (dfix ? 32'h8 : 32'h0));
      dma_go(irq);

      if (busy_ign) begin
        while (!dut_busy) @(posedge clk);
        repeat (50) @(posedge clk);
        axi_write(amechip_pkg::A_DMA_BASE + amechip_pkg::DMA_SRC_OFF, 32'hDEAD_0000);
        axi_write(amechip_pkg::A_DMA_BASE + amechip_pkg::DMA_XCNT_OFF, 32'h1);
        axi_write(amechip_pkg::A_DMA_BASE + amechip_pkg::DMA_CTRL_OFF, 32'h11);
        wait_dma_busy_clear();
        read_dma_status(st);
      end else if (ab > 0) begin
        while (!dut_busy) @(posedge clk);
        repeat (ab) @(posedge clk);
        axi_write(amechip_pkg::A_DMA_BASE + amechip_pkg::DMA_CTRL_OFF, 32'h2); // ABORT
        wait_dma_busy_clear();
        read_dma_status(st);
      end else if (conc) begin
        nconc = nconc + 1;
        fork
          cpu_traffic(16);
          wait_dma_busy_clear();
        join
        read_dma_status(st);
      end else begin
        wait_dma_busy_clear();
        read_dma_status(st);
      end

      if (exp_err) begin
        nerr = nerr + 1;
        checks = checks + 1;
        if (st[2] !== 1'b1 || st[7:4] !== exp_code || st[1] !== 1'b0)
          fail($sformatf("op#%0d 错误路径 exp ERR=1 code=%0d got=%08h",
               c, exp_code, st));
        if (!chk_stream && !busy_ign && ab == 0 && exp_code == 4'd1) begin
          checks = checks + 1;
          if (rd_ptr != rd0 || wr_ptr != wr0)
            fail($sformatf("op#%0d 参数错误却产生总线事务", c));
        end
      end else begin
        nclean = nclean + 1;
        checks = checks + 1;
        if (st[1] !== 1'b1 || st[2] !== 1'b0)
          fail($sformatf("op#%0d 期望 DONE got=%08h", c, st));
      end

      if (irq) begin
        axi_read(32'h1000_1004, pend);
        checks = checks + 1;
        if (exp_err) begin
          if (pend[3] !== 1'b1)
            fail($sformatf("op#%0d 错误未触发 DMA_ERR 中断 pend=%08h", c, pend));
          axi_write(32'h1000_1008, 32'h8);
        end else begin
          if (pend[2] !== 1'b1)
            fail($sformatf("op#%0d 完成未触发 DMA_DONE 中断 pend=%08h", c, pend));
          axi_write(32'h1000_1008, 32'h4);
        end
      end

      axi_write(amechip_pkg::A_DMA_BASE + amechip_pkg::DMA_STATUS_OFF, 32'h6);
    end
  endtask

  initial begin
    rst_n = 1'b0;
    c_aw_valid = 0; c_w_valid = 0; c_ar_valid = 0;
    c_b_ready = 0;  c_r_ready = 0;
    c_aw_addr = '0; c_w_data = '0; c_w_strb = '0; c_ar_addr = '0;
    errors = 0; checks = 0; cyc_cnt = 0;
    nclean = 0; nerr = 0; nconc = 0; nwords = 0;
    rd_ptr = 0; rdd_ptr = 0; wr_ptr = 0; stream_en = 0;

    load_files();
    $display("[dma] ops=%0d read_words=%0d write_words=%0d preload=%0d final=%0d",
             nops, nrd, nwr, npre, nfinal);
    if (nops == 0) begin
      $display("[FAIL] 未找到 dma_ops.hex");
      $display("VERIFY_DMA: FAIL");
      $finish;
    end

    repeat (5) @(posedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);
    axi_write(32'h1000_1008, 32'hFFFF_FFFF); // 清 INTC pending

    for (int i = 0; i < npre; i++)
      u_dut.u_psram.poke_addr(prea[i], pred[i]);
    $display("[dma] 预载 %0d 字完成", npre);

    for (int c = 0; c < nops; c++) begin
      run_op(c);
      if ((c % 40) == 0)
        $display("[dma] progress op=%0d/%0d rd=%0d wr=%0d err=%0d t=%0t",
                 c, nops, rd_ptr, wr_ptr, errors, $time);
    end

    checks = checks + 1;
    if (rd_ptr != nrd)  fail($sformatf("读地址流计数 %0d != %0d", rd_ptr, nrd));
    checks = checks + 1;
    if (rdd_ptr != nrd) fail($sformatf("读数据流计数 %0d != %0d", rdd_ptr, nrd));
    checks = checks + 1;
    if (wr_ptr != nwr)  fail($sformatf("写流计数 %0d != %0d", wr_ptr, nwr));
    nwords = wr_ptr;

    for (int i = 0; i < nfinal; i++) begin
      peek_any(fina[i], got_final);
      checks = checks + 1;
      if (got_final !== find[i]) begin
        fail($sformatf("final[%0d] @%08h got=%08h exp=%08h",
             i, fina[i], got_final, find[i]));
      end
    end

    $display("=== verify_dma_stress: ops=%0d clean=%0d err=%0d concurrent=%0d words=%0d checks=%0d errors=%0d ===",
             nops, nclean, nerr, nconc, nwords, checks, errors + bfm_errors);
    if (errors == 0 && bfm_errors == 0) $display("VERIFY_DMA: PASS");
    else                                $display("VERIFY_DMA: FAIL");
    $finish;
  end

  initial begin
    #2_000_000_000;
    $display("[FAIL] verify_dma_stress 全局超时");
    $display("VERIFY_DMA: FAIL");
    $finish;
  end

endmodule
