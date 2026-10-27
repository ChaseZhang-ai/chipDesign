`timescale 1ns/1ps
`include "amechip_pkg.sv"

module verify_concurrent;

`ifndef VFRC_CONC_TARGET
  localparam longint TARGET_CYC = 1_000_000;
`else
  localparam longint TARGET_CYC = `VFRC_CONC_TARGET;
`endif

  logic clk = 1'b0;
  logic rst_n;
  always #5 clk = ~clk;

  logic        c_aw_valid, c_aw_ready; logic [31:0] c_aw_addr;
  logic        c_w_valid, c_w_ready;   logic [31:0] c_w_data; logic [3:0] c_w_strb;
  logic        c_b_valid, c_b_ready;   logic [1:0]  c_b_resp;
  logic        c_ar_valid, c_ar_ready; logic [31:0] c_ar_addr;
  logic        c_r_valid, c_r_ready;   logic [31:0] c_r_data; logic [1:0] c_r_resp;
  logic        irq_line;

  verify_dut #(.KV_BACKEND_B(1'b0), .KV_CTX(256)) u_dut (
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

  longint cyc_cnt;
  int errors, checks, data_err;
  longint cpu_ops, dma_ops, dma_words, kv_ops, kv_rows;
  longint last_cpu, last_dma, last_kv;
  int     win_idx;
  longint t_start;

  wire dut_dma_busy = u_dut.u_mem.u_dma.busy_q;
  wire dut_kv_busy  = u_dut.u_mem.u_kvc.busy_q;

  always @(posedge clk) cyc_cnt <= cyc_cnt + 1;

  task automatic fail(input string msg);
    errors = errors + 1;
    if (errors <= 30) $display("[FAIL] %0t %s", $time, msg);
  endtask

  function automatic logic [31:0] word_of(input logic [31:0] a);
    word_of = (a[31:2] * 32'h9E37_79B9) + 32'h7F4A_7C15;
  endfunction

  task automatic cpu_read_lat(input logic [31:0] addr, output logic [31:0] data);
    int n;
    begin : body
      @(negedge clk);
      c_aw_valid = 1'b0; c_w_valid = 1'b0;
      c_ar_valid = 1'b1; c_ar_addr = addr;
      n = 0;
      @(posedge clk); n = n + 1;
      while (!c_ar_ready) begin @(posedge clk); n = n + 1; end
      @(negedge clk);
      c_ar_valid = 1'b0; c_r_ready = 1'b0;
      forever begin
        @(negedge clk);
        if (c_r_valid) begin
          data = c_r_data;
          c_r_ready = 1'b1;
          @(posedge clk); n = n + 1;
          @(negedge clk); c_r_ready = 1'b0;
          lat_cycles = n;
          if (n > lat_max) lat_max = n;
          disable body;
        end
      end
    end
  endtask

  task automatic one_iteration(input int it, inout int k);
    logic [31:0] st, d;
    int guard;
    begin
      case (it % 3)
        0: begin
          dma_cfg(32'h4002_0000, 32'h2000_1000, 32'd512, 32'd1, 0, 0, 32'h10);
          dma_words = dma_words + 512;
        end
        1: begin
          dma_cfg(32'h4002_0000, 32'h0000_0000, 32'd512, 32'd1, 0, 0, 32'h10);
          dma_words = dma_words + 512;
        end
        default: begin
          dma_cfg(32'h4002_0000, 32'h4030_0000, 32'd256, 32'd1, 0, 0, 32'h10);
          dma_words = dma_words + 256;
        end
      endcase
      dma_go(1'b1);
      dma_ops = dma_ops + 1;

      case (it % 6)
        0, 1, 2: begin
          kv_cfg(32'h0, (it / 6) % 2, 32'h0, (it * 3) % 128, 32'h1,
                 32'h4048_0000 + (((it * 3) % 128) * 512), 32'h0, 32'h0, 32'h0);
          kv_go(amechip_pkg::KV_MODE_APPEND_KV8, 1'b0, 1'b1);
          kv_rows = kv_rows + 4;
        end
        3: begin
          kv_cfg(32'h0, (it / 6) % 2, 32'h0, ((it / 6) % 8) * 16, 32'd16,
                 32'h0, 32'h0000_0900, 32'h0,
                 (16 & 63) | ((16 & 63) << 6));
          kv_go(amechip_pkg::KV_MODE_READ_V, 1'b1, 1'b1);
          kv_rows = kv_rows + 16;
        end
        4: begin
          kv_cfg(32'h0, (it / 6) % 2, 32'h1, ((it / 6) % 8) * 16, 32'd16,
                 32'h0, 32'h0000_0900, 32'd16, (16 & 63) | ((16 & 63) << 6));
          kv_go(amechip_pkg::KV_MODE_READ_K, 1'b0, 1'b1);
          kv_rows = kv_rows + 16;
        end
        default: begin
          kv_cfg(32'h0, 0, 32'h0, 32'd0, 32'd16, 32'h0, 32'h0, 32'h0, 32'h0);
          kv_go(amechip_pkg::KV_MODE_CLEAR, 1'b0, 1'b1);
          kv_rows = kv_rows + 16;
        end
      endcase
      kv_ops = kv_ops + 1;

      for (int j = 0; j < 200 && cyc_cnt < TARGET_CYC; j++) begin
        axi_write(32'h0000_0800 + 4 * (k % 64), 32'hC000_0000 + k);
        axi_read(32'h0000_0800 + 4 * (k % 64), d);
        checks = checks + 1;
        if (d !== (32'hC000_0000 + k))
          fail($sformatf("CPU OCSRAM 读 got=%08h exp=%08h", d, 32'hC000_0000 + k));
        cpu_read_lat(32'h4010_0000 + 4 * (k % 64), d);
        checks = checks + 1;
        if (d !== word_of(32'h4010_0000 + 4 * (k % 64))) begin
          data_err = data_err + 1;
          if (data_err <= 8)
            $display("[DATA] %0t CPU XMEM 读 got=%08h exp=%08h (P3C-2 形态: 低半字错误)",
                     $time, d, word_of(32'h4010_0000 + 4 * (k % 64)));
        end
        cpu_ops = cpu_ops + 1;
        k = k + 1;
      end

      repeat (3) @(posedge clk);
      guard = 0;
      while ((dut_dma_busy || dut_kv_busy) && guard < 200_000) begin
        @(posedge clk);
        guard = guard + 1;
      end
      if (guard >= 200_000)
        fail($sformatf("iteration %0d 引擎 200k 拍未排空(疑似死锁)", it));

      axi_read(amechip_pkg::A_DMA_BASE + amechip_pkg::DMA_STATUS_OFF, st);
      checks = checks + 1;
      if (st[1] !== 1'b1 || st[2] !== 1'b0)
        fail($sformatf("并发 DMA 状态 %08h(iteration %0d)", st, it));
      axi_write(amechip_pkg::A_DMA_BASE + amechip_pkg::DMA_STATUS_OFF, 32'h6);
      axi_read(amechip_pkg::A_KV_BASE + amechip_pkg::KV_STATUS_OFF, st);
      checks = checks + 1;
      if (st[1] !== 1'b1 || st[2] !== 1'b0)
        fail($sformatf("并发 KV 状态 %08h(iteration %0d)", st, it));
      axi_write(amechip_pkg::A_KV_BASE + amechip_pkg::KV_STATUS_OFF, 32'h6);
    end
  endtask

  task automatic progress_monitor();
    begin
      last_cpu = 0; last_dma = 0; last_kv = 0; win_idx = 0;
      while (cyc_cnt < TARGET_CYC) begin
        repeat (100_000) @(posedge clk);
        if (cyc_cnt < TARGET_CYC) begin
          if (win_idx >= 2) begin
            if (cpu_ops == last_cpu) fail($sformatf("窗口 %0d: CPU 无进展", win_idx));
            if (dma_ops == last_dma) fail($sformatf("窗口 %0d: DMA 无进展", win_idx));
            if (kv_ops  == last_kv ) fail($sformatf("窗口 %0d: KV 无进展", win_idx));
          end
          $display("[conc] window %0d @cyc=%0d cpu=%0d dma=%0d kv=%0d (d_cpu=%0d d_dma=%0d d_kv=%0d) lat_max=%0d",
                   win_idx, cyc_cnt, cpu_ops, dma_ops, kv_ops,
                   cpu_ops - last_cpu, dma_ops - last_dma, kv_ops - last_kv, lat_max);
          last_cpu = cpu_ops; last_dma = dma_ops; last_kv = kv_ops;
          win_idx = win_idx + 1;
        end
      end
    end
  endtask

  task automatic latency_phase();
    logic [31:0] st, d;
    begin
      $display("[lat] P2C fairness 同口径:CPU 96 次背靠背读 XMEM + DMA XMEM->XMEM(512 字,DMA 读流全程重叠) + KV CLEAR 256 行");
      dma_cfg(32'h4002_0000, 32'h4003_0000, 32'd512, 32'd1, 0, 0, 32'h10);
      kv_cfg(32'h0, 32'h0, 32'h1, 32'd0, 32'd256, 32'h0, 32'h0, 32'h0, 32'h0);
      lat_max = 0;
      dma_go(1'b1);
      kv_go(amechip_pkg::KV_MODE_CLEAR, 1'b0, 1'b1);
      for (int i = 0; i < 96; i++) begin
        cpu_read_lat(32'h4002_0000, d);
      end
      repeat (3) @(posedge clk);
      while (dut_dma_busy || dut_kv_busy) @(posedge clk);
      axi_read(amechip_pkg::A_DMA_BASE + amechip_pkg::DMA_STATUS_OFF, st);
      checks = checks + 1;
      if (st[1] !== 1'b1 || st[2] !== 1'b0) fail("延迟专项 DMA 状态异常");
      axi_write(amechip_pkg::A_DMA_BASE + amechip_pkg::DMA_STATUS_OFF, 32'h6);
      axi_read(amechip_pkg::A_KV_BASE + amechip_pkg::KV_STATUS_OFF, st);
      checks = checks + 1;
      if (st[1] !== 1'b1 || st[2] !== 1'b0) fail("延迟专项 KV 状态异常");
      axi_write(amechip_pkg::A_KV_BASE + amechip_pkg::KV_STATUS_OFF, 32'h6);
      $display("[lat] CPU 最坏读延迟 = %0d 拍(P2C 实测 29)", lat_max);
      if (lat_max > 40) fail($sformatf("CPU 最坏读延迟 %0d > 40", lat_max));
    end
  endtask

  task automatic dma_run_measure(input logic [31:0] src, dst,
                                 input logic [31:0] xcnt, ycnt,
                                 input logic [31:0] sp, dp,
                                 output longint cycles,
                                 output logic [31:0] st);
    longint t0;
    begin
      dma_cfg(src, dst, xcnt, ycnt, sp, dp, 32'h0);
      t0 = cyc_cnt;
      dma_go(1'b0);
      @(posedge clk); @(posedge clk);
      while (dut_dma_busy) @(posedge clk);
      cycles = cyc_cnt - t0;
      axi_read(amechip_pkg::A_DMA_BASE + amechip_pkg::DMA_STATUS_OFF, st);
      axi_write(amechip_pkg::A_DMA_BASE + amechip_pkg::DMA_STATUS_OFF, 32'h6);
    end
  endtask

  task automatic throughput_phase();
    logic [31:0] st;
    longint cyc;
    int unsigned n;
    real mbps;
    begin
      n = 256;
      for (int i = 0; i < 256; i++) begin
        u_dut.u_psram.poke_addr(32'h4002_0000 + 4*i, 32'hA000_0000 + i);
        u_dut.u_psram.poke_addr(32'h4003_0000 + 4*i, 32'hB000_0000 + i);
      end

      dma_run_measure(32'h4002_0000, 32'h0000_0000, n[31:0], 32'd1, 0, 0, cyc, st);
      mbps = real'(n) * 4.0 * 120.0 / real'(cyc);
      $display("[perf] XMEM->OCSRAM    %0d words: %0d cyc = %.2f cyc/word = %.1f MB/s (P2C 2.04/235.4)",
               n, cyc, real'(cyc)/real'(n), mbps);

      dma_run_measure(32'h4002_0000, 32'h2000_1000, n[31:0], 32'd1, 0, 0, cyc, st);
      mbps = real'(n) * 4.0 * 120.0 / real'(cyc);
      $display("[perf] XMEM->AME WBUF   %0d words: %0d cyc = %.2f cyc/word = %.1f MB/s (P2C 2.04/235.4)",
               n, cyc, real'(cyc)/real'(n), mbps);

      dma_run_measure(32'h0000_0000, 32'h0000_0400, n[31:0], 32'd1, 0, 0, cyc, st);
      mbps = real'(n) * 4.0 * 120.0 / real'(cyc);
      $display("[perf] OCSRAM->OCSRAM  %0d words: %0d cyc = %.2f cyc/word = %.1f MB/s (P2C 4.02/119.4)",
               n, cyc, real'(cyc)/real'(n), mbps);

      dma_run_measure(32'h4002_0000, 32'h4003_0000, n[31:0], 32'd1, 0, 0, cyc, st);
      mbps = real'(n) * 4.0 * 120.0 / real'(cyc);
      $display("[perf] XMEM->XMEM     %0d words: %0d cyc = %.2f cyc/word = %.1f MB/s (P2C 6.02/79.7)",
               n, cyc, real'(cyc)/real'(n), mbps);

      checks = checks + 1;
      if (st[1] !== 1'b1 || st[2] !== 1'b0) fail("吞吐测量 DMA 状态异常");
    end
  endtask

  int kk;
  initial begin
    rst_n = 1'b0;
    c_aw_valid = 0; c_w_valid = 0; c_ar_valid = 0;
    c_b_ready = 0;  c_r_ready = 0;
    c_aw_addr = '0; c_w_data = '0; c_w_strb = '0; c_ar_addr = '0;
    errors = 0; checks = 0; data_err = 0; cyc_cnt = 0; t_start = 0;
    cpu_ops = 0; dma_ops = 0; dma_words = 0; kv_ops = 0; kv_rows = 0;
    lat_max = 0; kk = 0;

    repeat (5) @(posedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);

    for (int i = 0; i < 64; i++)
      u_dut.u_psram.poke_addr(32'h4010_0000 + 4*i, word_of(32'h4010_0000 + 4*i));
    for (int i = 0; i < 16384; i++)
      u_dut.u_psram.poke_addr(32'h4048_0000 + 4*i, word_of(32'h4048_0000 + 4*i));
    for (int i = 0; i < 32'h20000; i++)
      u_dut.u_psram.mem[32'h0020_0000 + i] = 16'h0;

    t_start = cyc_cnt;
    $display("[conc] 开始三主并发:目标 %0d 拍", TARGET_CYC);

    fork
      begin : driver
        int it;
        it = 0;
        while (cyc_cnt < TARGET_CYC) begin
          one_iteration(it, kk);
          it = it + 1;
        end
        $display("[conc] driver 结束 @cyc=%0d iterations=%0d", cyc_cnt, it);
      end
      progress_monitor();
    join

    repeat (20) @(posedge clk);
    $display("[conc] 并发阶段结束: cycles=%0d cpu_ops=%0d dma_ops=%0d dma_words=%0d kv_ops=%0d kv_rows=%0d data_err=%0d",
             cyc_cnt - t_start, cpu_ops, dma_ops, dma_words, kv_ops, kv_rows, data_err);

    latency_phase();
    throughput_phase();

    checks = checks + 3;
    if (cpu_ops < 1000) fail($sformatf("CPU 进展过少: %0d", cpu_ops));
    if (dma_ops < 20)   fail($sformatf("DMA 进展过少: %0d", dma_ops));
    if (kv_ops  < 20)   fail($sformatf("KV 进展过少: %0d", kv_ops));

    $display("=== verify_concurrent: cycles=%0d cpu_ops=%0d dma_ops=%0d dma_words=%0d kv_ops=%0d kv_rows=%0d checks=%0d errors=%0d data_err=%0d ===",
             cyc_cnt - t_start, cpu_ops, dma_ops, dma_words, kv_ops, kv_rows,
             checks, errors + bfm_errors, data_err);
    if (data_err == 0) $display("DATA_INTEGRITY: PASS");
    else               $display("DATA_INTEGRITY: FAIL(P3C-2) hits=%0d", data_err);
    if (errors == 0 && bfm_errors == 0) $display("VERIFY_CONC: PASS");
    else                                $display("VERIFY_CONC: FAIL");
    $finish;
  end

  initial begin
    #5_000_000_000;
    $display("[FAIL] verify_concurrent 全局超时");
    $display("VERIFY_CONC: FAIL");
    $finish;
  end

endmodule
