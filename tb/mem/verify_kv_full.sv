`timescale 1ns/1ps
`include "amechip_pkg.sv"

`ifndef VFRC_KV_B
 `define VFRC_KV_B 0
`endif
`ifndef VFRC_KV_CTX
 `define VFRC_KV_CTX 256
`endif
`ifndef VFRC_KV_MAXCMD
 `define VFRC_KV_MAXCMD 8192
`endif
`ifndef VFRC_KV_MAXEXP
 `define VFRC_KV_MAXEXP 240000
`endif
`ifndef VFRC_KV_MAXSRC
 `define VFRC_KV_MAXSRC 40000
`endif

module verify_kv_full;

  localparam logic [31:0] SRC_BASE = 32'h4048_0000;
  localparam logic [31:0] DST_BASE = 32'h0000_0800;
  localparam int unsigned  KV_HW_BASE = 32'h0020_0000; // 0x4040_0000 的器件半字索引

  logic clk = 1'b0;
  logic rst_n;
  always #5 clk = ~clk;

  logic        c_aw_valid, c_aw_ready; logic [31:0] c_aw_addr;
  logic        c_w_valid, c_w_ready;   logic [31:0] c_w_data; logic [3:0] c_w_strb;
  logic        c_b_valid, c_b_ready;   logic [1:0]  c_b_resp;
  logic        c_ar_valid, c_ar_ready; logic [31:0] c_ar_addr;
  logic        c_r_valid, c_r_ready;   logic [31:0] c_r_data; logic [1:0] c_r_resp;
  logic        irq_line;

  verify_dut #(
    .KV_BACKEND_B (`VFRC_KV_B != 0),
    .KV_CTX       (`VFRC_KV_CTX)
  ) u_dut (
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

  localparam int unsigned MAXCMD = `VFRC_KV_MAXCMD;
  localparam int unsigned MAXEXP = `VFRC_KV_MAXEXP;
  localparam int unsigned MAXSRC = `VFRC_KV_MAXSRC;

  logic [31:0] cmds [0:MAXCMD*16-1];
  logic [31:0] expd [0:MAXEXP-1];
  logic [31:0] srcw [0:MAXSRC-1];

  logic [31:0] counts [0:2];
  int ncmd, nexp, nsrc, exp_ptr;
  int nops_run, nread_ops, nmis, nerr_ops, nchecks;
  longint t_start, t_run;

  task automatic load_files();
    begin
      for (int i = 0; i < MAXCMD*16; i++) cmds[i] = 32'hxxxx_xxxx;
      for (int i = 0; i < MAXEXP; i++)    expd[i]  = 32'hxxxx_xxxx;
      for (int i = 0; i < MAXSRC; i++)    srcw[i]  = 32'hxxxx_xxxx;
      $readmemh("kv_cmds.hex", cmds);
      $readmemh("kv_exp_dst.hex", expd);
      $readmemh("kv_src.hex", srcw);
      for (int i = 0; i < 3; i++) counts[i] = 32'h0;
      $readmemh("kv_counts.hex", counts);
    end
  endtask

  function automatic logic [31:0] ocram_peek(input logic [31:0] byte_addr);
    ocram_peek = u_dut.u_mem.u_ocram.u_ram.mem[byte_addr[11:2]];
  endfunction

  task automatic ocram_poke(input logic [31:0] byte_addr, input logic [31:0] v);
    u_dut.u_mem.u_ocram.u_ram.mem[byte_addr[11:2]] = v;
  endtask

  task automatic zero_storage();
    begin
`ifdef VFRC_KV_IS_B
      $display("[kv] 清零 4 个 bank(4 x %0d 字)", `VFRC_KV_CTX * 32);
      for (int i = 0; i < `VFRC_KV_CTX * 32; i++) begin
        u_dut.u_mem.g_kv_b.u_kvbe.g_bank[0].u_bank.mem[i] = '0;
        u_dut.u_mem.g_kv_b.u_kvbe.g_bank[1].u_bank.mem[i] = '0;
        u_dut.u_mem.g_kv_b.u_kvbe.g_bank[2].u_bank.mem[i] = '0;
        u_dut.u_mem.g_kv_b.u_kvbe.g_bank[3].u_bank.mem[i] = '0;
      end
`else
      $display("[kv] 清零 XMEM KV 区(0x4040_0000..0x4043_FFFF)");
      for (int i = 0; i < 32'h20000; i++)
        u_dut.u_psram.mem[KV_HW_BASE + i] = 16'h0;
`endif
    end
  endtask

  task automatic run_ops();
    logic [31:0] w0, ctrl, st, d;
    logic [2:0]  mode;
    logic        tr, exp_err;
    logic [3:0]  exp_code;
    int unsigned rbw;
    begin
      exp_ptr = 0; nops_run = 0; nread_ops = 0; nmis = 0; nerr_ops = 0;
      nchecks = 0;
      for (int c = 0; c < ncmd; c++) begin
        w0       = cmds[c*16 + 0];
        mode     = w0[2:0];
        tr       = w0[4];
        exp_err  = w0[7];
        exp_code = w0[11:8];
        rbw      = cmds[c*16 + 9];
        nops_run = nops_run + 1;

        if (w0[16] && rbw > 0) begin
          for (int i = 0; i < int'(rbw) + 1; i++)
            ocram_poke(32'h0000_0800 + 4*i, 32'h0);
        end

        kv_cfg(32'h0, cmds[c*16+1], cmds[c*16+2], cmds[c*16+3],
               cmds[c*16+4], cmds[c*16+5], cmds[c*16+6],
               cmds[c*16+7], cmds[c*16+8]);
        kv_go(mode, tr, 1'b0);
        kv_wait(st);

        if (exp_err) begin
          nerr_ops = nerr_ops + 1;
          nchecks = nchecks + 1;
          if (st[2] !== 1'b1 || st[7:4] !== exp_code || st[1] !== 1'b0) begin
            nmis = nmis + 1;
            if (nmis <= 20)
              $display("[FAIL] op#%0d mode=%0d 错误路径: exp ERR=1 code=%0d, got %08h",
                       c, mode, exp_code, st);
          end
        end else begin
          nchecks = nchecks + 1;
          if (st[1] !== 1'b1 || st[2] !== 1'b0) begin
            nmis = nmis + 1;
            if (nmis <= 20)
              $display("[FAIL] op#%0d mode=%0d 期望 DONE, got %08h", c, mode, st);
          end
          if ((mode == 3'd3 || mode == 3'd4) && rbw > 0) begin
            nread_ops = nread_ops + 1;
            for (int i = 0; i < int'(rbw); i++) begin
              d = ocram_peek(32'h0000_0800 + 4*i);
              nchecks = nchecks + 1;
              if (d !== expd[exp_ptr + i]) begin
                nmis = nmis + 1;
                if (nmis <= 20)
                  $display("[FAIL] op#%0d(mode %0d tr=%b dd=%0d dl=%0d) word[%0d] got=%08h exp=%08h",
                           c, mode, tr, cmds[c*16+8] & 63,
                           ((cmds[c*16+8] >> 6) & 63) == 0 ? 64 : ((cmds[c*16+8] >> 6) & 63),
                           i, d, expd[exp_ptr + i]);
              end
            end
            d = ocram_peek(32'h0000_0800 + 4*rbw);
            nchecks = nchecks + 1;
            if (d !== 32'h0 && nmis <= 20) begin
              nmis = nmis + 1;
              $display("[FAIL] op#%0d 越界写: DST[%0d]=%08h (期望 0)", c, rbw, d);
            end
            exp_ptr = exp_ptr + int'(rbw);
          end
        end

        axi_write(amechip_pkg::A_KV_BASE + amechip_pkg::KV_STATUS_OFF, 32'h6);
        if ((c % 500) == 0)
          $display("[kv] progress op=%0d/%0d read_ops=%0d mis=%0d t=%0t",
                   c, ncmd, nread_ops, nmis, $time);
      end
    end
  endtask

  task automatic dump_storage();
    begin
`ifdef VFRC_KV_IS_B
      $writememh("kv_dump_bank0.hex", u_dut.u_mem.g_kv_b.u_kvbe.g_bank[0].u_bank.mem);
      $writememh("kv_dump_bank1.hex", u_dut.u_mem.g_kv_b.u_kvbe.g_bank[1].u_bank.mem);
      $writememh("kv_dump_bank2.hex", u_dut.u_mem.g_kv_b.u_kvbe.g_bank[2].u_bank.mem);
      $writememh("kv_dump_bank3.hex", u_dut.u_mem.g_kv_b.u_kvbe.g_bank[3].u_bank.mem);
      $display("[kv] bank 转储完成");
`else
      u_dut.u_psram.dump_hw_range("kv_dump_xmem.hex", KV_HW_BASE, 32'h20000);
      $display("[kv] XMEM KV 区转储完成(131072 半字)");
`endif
    end
  endtask

  initial begin
    rst_n = 1'b0;
    c_aw_valid = 0; c_w_valid = 0; c_ar_valid = 0;
    c_b_ready = 0;  c_r_ready = 0;
    c_aw_addr = '0; c_w_data = '0; c_w_strb = '0; c_ar_addr = '0;

    load_files();
    ncmd = int'(counts[0]);
    nexp = int'(counts[1]);
    nsrc = int'(counts[2]);
    $display("[kv] cmds=%0d exp_words=%0d src_words=%0d backend=%0s ctx=%0d",
             ncmd, nexp, nsrc, `VFRC_KV_B ? "B" : "A", `VFRC_KV_CTX);
    if (ncmd == 0) begin
      $display("[FAIL] 未找到 kv_cmds.hex(请在场景目录运行)");
      $display("VERIFY_KV: FAIL");
      $finish;
    end

    repeat (5) @(posedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);

    t_start = $time;
    for (int i = 0; i < nsrc; i++)
      u_dut.u_psram.poke_addr(SRC_BASE + 4*i, srcw[i]);
    zero_storage();

    run_ops();
    dump_storage();
    t_run = $time - t_start;

    $display("=== verify_kv_full: ops=%0d read_ops=%0d err_ops=%0d checks=%0d mismatches=%0d ===",
             nops_run, nread_ops, nerr_ops, nchecks, nmis);
    $display("[kv] 运行周期 = %0d", t_run / 10);
    if (nmis == 0 && nops_run == ncmd) $display("VERIFY_KV: PASS");
    else                               $display("VERIFY_KV: FAIL");
    $finish;
  end

  initial begin
    #1_000_000_000; // 1 s 仿真时间看门狗
    $display("[FAIL] verify_kv_full 全局超时");
    $display("VERIFY_KV: FAIL");
    $finish;
  end

endmodule
