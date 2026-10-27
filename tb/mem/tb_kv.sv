`timescale 1ns/1ps
`include "amechip_pkg.sv"

`ifdef KV_BB
 `define KV_BACKEND_B_VAL 1'b1
 `define KV_CTX_VAL 128
`else
 `define KV_BACKEND_B_VAL 1'b0
 `define KV_CTX_VAL 256
`endif

module tb_kv;

  logic clk = 1'b0;
  logic rst_n;
  always #5 clk = ~clk;

  logic        c_aw_valid, c_aw_ready; logic [31:0] c_aw_addr;
  logic        c_w_valid, c_w_ready;   logic [31:0] c_w_data; logic [3:0] c_w_strb;
  logic        c_b_valid, c_b_ready;   logic [1:0] c_b_resp;
  logic        c_ar_valid, c_ar_ready; logic [31:0] c_ar_addr;
  logic        c_r_valid, c_r_ready;   logic [31:0] c_r_data; logic [1:0] c_r_resp;

  logic [22:0] xa; logic [15:0] xdi, xdo;
  logic xce, xoe, xwe;
  logic irq_dma_done, irq_dma_err, irq_kv_done, irq_kv_err, soft_pulse, irq_line;
  logic dump_req;

  logic sys_aw_valid_o, sys_aw_ready_i;  logic [31:0] sys_aw_addr_o;
  logic sys_w_valid_o,  sys_w_ready_i;   logic [31:0] sys_w_data_o; logic [3:0] sys_w_strb_o;
  logic sys_b_valid_i,  sys_b_ready_o;   logic [1:0]  sys_b_resp_i;
  logic sys_ar_valid_o, sys_ar_ready_i;  logic [31:0] sys_ar_addr_o;
  logic sys_r_valid_i,  sys_r_ready_o;   logic [31:0] sys_r_data_i; logic [1:0] sys_r_resp_i;
  logic intc_aw_valid_o, intc_aw_ready_i; logic [31:0] intc_aw_addr_o;
  logic intc_w_valid_o,  intc_w_ready_i;  logic [31:0] intc_w_data_o; logic [3:0] intc_w_strb_o;
  logic intc_b_valid_i,  intc_b_ready_o;  logic [1:0]  intc_b_resp_i;
  logic intc_ar_valid_o, intc_ar_ready_i; logic [31:0] intc_ar_addr_o;
  logic intc_r_valid_i,  intc_r_ready_o;  logic [31:0] intc_r_data_i; logic [1:0] intc_r_resp_i;
  logic uart_aw_valid_o, uart_aw_ready_i; logic [31:0] uart_aw_addr_o;
  logic uart_w_valid_o,  uart_w_ready_i;  logic [31:0] uart_w_data_o; logic [3:0] uart_w_strb_o;
  logic uart_b_valid_i,  uart_b_ready_o;  logic [1:0]  uart_b_resp_i;
  logic uart_ar_valid_o, uart_ar_ready_i; logic [31:0] uart_ar_addr_o;
  logic uart_r_valid_i,  uart_r_ready_o;  logic [31:0] uart_r_data_i; logic [1:0] uart_r_resp_i;
  logic ame_aw_valid_o, ame_aw_ready_i;  logic [31:0] ame_aw_addr_o;
  logic ame_w_valid_o,  ame_w_ready_i;   logic [31:0] ame_w_data_o; logic [3:0] ame_w_strb_o;
  logic ame_b_valid_i,  ame_b_ready_o;   logic [1:0]  ame_b_resp_i;
  logic ame_ar_valid_o, ame_ar_ready_i;  logic [31:0] ame_ar_addr_o;
  logic ame_r_valid_i,  ame_r_ready_o;   logic [31:0] ame_r_data_i; logic [1:0] ame_r_resp_i;

  mem_ss_top #(
    .OC_SRAM_KB   (4),
    .BOOT_ROM_KB  (2),
    .BOOT_INIT    ("boot_rom.memh"),
    .KV_BACKEND_B (`KV_BACKEND_B_VAL),
    .KV_CTX       (`KV_CTX_VAL)
  ) dut (
    .clk_i(clk), .rst_ni(rst_n),
    .cpu_aw_valid_i(c_aw_valid), .cpu_aw_ready_o(c_aw_ready), .cpu_aw_addr_i(c_aw_addr),
    .cpu_w_valid_i(c_w_valid), .cpu_w_ready_o(c_w_ready), .cpu_w_data_i(c_w_data),
    .cpu_w_strb_i(c_w_strb),
    .cpu_b_valid_o(c_b_valid), .cpu_b_ready_i(c_b_ready), .cpu_b_resp_o(c_b_resp),
    .cpu_ar_valid_i(c_ar_valid), .cpu_ar_ready_o(c_ar_ready), .cpu_ar_addr_i(c_ar_addr),
    .cpu_r_valid_o(c_r_valid), .cpu_r_ready_i(c_r_ready), .cpu_r_data_o(c_r_data),
    .cpu_r_resp_o(c_r_resp),
    .sys_aw_valid_o(sys_aw_valid_o), .sys_aw_ready_i(sys_aw_ready_i), .sys_aw_addr_o(sys_aw_addr_o),
    .sys_w_valid_o(sys_w_valid_o), .sys_w_ready_i(sys_w_ready_i), .sys_w_data_o(sys_w_data_o),
    .sys_w_strb_o(sys_w_strb_o),
    .sys_b_valid_i(sys_b_valid_i), .sys_b_ready_o(sys_b_ready_o), .sys_b_resp_i(sys_b_resp_i),
    .sys_ar_valid_o(sys_ar_valid_o), .sys_ar_ready_i(sys_ar_ready_i), .sys_ar_addr_o(sys_ar_addr_o),
    .sys_r_valid_i(sys_r_valid_i), .sys_r_ready_o(sys_r_ready_o), .sys_r_data_i(sys_r_data_i),
    .sys_r_resp_i(sys_r_resp_i),
    .intc_aw_valid_o(intc_aw_valid_o), .intc_aw_ready_i(intc_aw_ready_i), .intc_aw_addr_o(intc_aw_addr_o),
    .intc_w_valid_o(intc_w_valid_o), .intc_w_ready_i(intc_w_ready_i), .intc_w_data_o(intc_w_data_o),
    .intc_w_strb_o(intc_w_strb_o),
    .intc_b_valid_i(intc_b_valid_i), .intc_b_ready_o(intc_b_ready_o), .intc_b_resp_i(intc_b_resp_i),
    .intc_ar_valid_o(intc_ar_valid_o), .intc_ar_ready_i(intc_ar_ready_i), .intc_ar_addr_o(intc_ar_addr_o),
    .intc_r_valid_i(intc_r_valid_i), .intc_r_ready_o(intc_r_ready_o), .intc_r_data_i(intc_r_data_i),
    .intc_r_resp_i(intc_r_resp_i),
    .uart_aw_valid_o(uart_aw_valid_o), .uart_aw_ready_i(uart_aw_ready_i), .uart_aw_addr_o(uart_aw_addr_o),
    .uart_w_valid_o(uart_w_valid_o), .uart_w_ready_i(uart_w_ready_i), .uart_w_data_o(uart_w_data_o),
    .uart_w_strb_o(uart_w_strb_o),
    .uart_b_valid_i(uart_b_valid_i), .uart_b_ready_o(uart_b_ready_o), .uart_b_resp_i(uart_b_resp_i),
    .uart_ar_valid_o(uart_ar_valid_o), .uart_ar_ready_i(uart_ar_ready_i), .uart_ar_addr_o(uart_ar_addr_o),
    .uart_r_valid_i(uart_r_valid_i), .uart_r_ready_o(uart_r_ready_o), .uart_r_data_i(uart_r_data_i),
    .uart_r_resp_i(uart_r_resp_i),
    .ame_aw_valid_o(ame_aw_valid_o), .ame_aw_ready_i(ame_aw_ready_i), .ame_aw_addr_o(ame_aw_addr_o),
    .ame_w_valid_o(ame_w_valid_o), .ame_w_ready_i(ame_w_ready_i), .ame_w_data_o(ame_w_data_o),
    .ame_w_strb_o(ame_w_strb_o),
    .ame_b_valid_i(ame_b_valid_i), .ame_b_ready_o(ame_b_ready_o), .ame_b_resp_i(ame_b_resp_i),
    .ame_ar_valid_o(ame_ar_valid_o), .ame_ar_ready_i(ame_ar_ready_i), .ame_ar_addr_o(ame_ar_addr_o),
    .ame_r_valid_i(ame_r_valid_i), .ame_r_ready_o(ame_r_ready_o), .ame_r_data_i(ame_r_data_i),
    .ame_r_resp_i(ame_r_resp_i),
    .xmem_clk_o(), .xmem_a_o(xa), .xmem_di_i(xdo), .xmem_do_o(xdi),
    .xmem_ce_no(xce), .xmem_oe_no(xoe), .xmem_we_no(xwe), .xmem_wait_i(1'b0),
    .irq_dma_done_o(irq_dma_done), .irq_dma_err_o(irq_dma_err),
    .irq_kv_done_o(irq_kv_done), .irq_kv_err_o(irq_kv_err)
  );

  tb_sys_stub u_sys (.clk_i(clk), .rst_ni(rst_n),
    .aw_valid_i(sys_aw_valid_o), .aw_ready_o(sys_aw_ready_i), .aw_addr_i(sys_aw_addr_o),
    .w_valid_i(sys_w_valid_o), .w_ready_o(sys_w_ready_i), .w_data_i(sys_w_data_o),
    .w_strb_i(sys_w_strb_o),
    .b_valid_o(sys_b_valid_i), .b_ready_i(sys_b_ready_o), .b_resp_o(sys_b_resp_i),
    .ar_valid_i(sys_ar_valid_o), .ar_ready_o(sys_ar_ready_i), .ar_addr_i(sys_ar_addr_o),
    .r_valid_o(sys_r_valid_i), .r_ready_i(sys_r_ready_o), .r_data_o(sys_r_data_i),
    .r_resp_o(sys_r_resp_i), .soft_irq_pulse_o(soft_pulse));

  tb_intc_stub u_intc (.clk_i(clk), .rst_ni(rst_n),
    .aw_valid_i(intc_aw_valid_o), .aw_ready_o(intc_aw_ready_i), .aw_addr_i(intc_aw_addr_o),
    .w_valid_i(intc_w_valid_o), .w_ready_o(intc_w_ready_i), .w_data_i(intc_w_data_o),
    .w_strb_i(intc_w_strb_o),
    .b_valid_o(intc_b_valid_i), .b_ready_i(intc_b_ready_o), .b_resp_o(intc_b_resp_i),
    .ar_valid_i(intc_ar_valid_o), .ar_ready_o(intc_ar_ready_i), .ar_addr_i(intc_ar_addr_o),
    .r_valid_o(intc_r_valid_i), .r_ready_i(intc_r_ready_o), .r_data_o(intc_r_data_i),
    .r_resp_o(intc_r_resp_i),
    .irq_dma_done_i(irq_dma_done), .irq_dma_err_i(irq_dma_err),
    .irq_kv_done_i(irq_kv_done), .irq_kv_err_i(irq_kv_err),
    .irq_soft_i(soft_pulse), .irq_o(irq_line));

  tb_uart_stub u_uart (.clk_i(clk), .rst_ni(rst_n),
    .aw_valid_i(uart_aw_valid_o), .aw_ready_o(uart_aw_ready_i), .aw_addr_i(uart_aw_addr_o),
    .w_valid_i(uart_w_valid_o), .w_ready_o(uart_w_ready_i), .w_data_i(uart_w_data_o),
    .w_strb_i(uart_w_strb_o),
    .b_valid_o(uart_b_valid_i), .b_ready_i(uart_b_ready_o), .b_resp_o(uart_b_resp_i),
    .ar_valid_i(uart_ar_valid_o), .ar_ready_o(uart_ar_ready_i), .ar_addr_i(uart_ar_addr_o),
    .r_valid_o(uart_r_valid_i), .r_ready_i(uart_r_ready_o), .r_data_o(uart_r_data_i),
    .r_resp_o(uart_r_resp_i));

  tb_ame_stub u_ame (.clk_i(clk), .rst_ni(rst_n),
    .aw_valid_i(ame_aw_valid_o), .aw_ready_o(ame_aw_ready_i), .aw_addr_i(ame_aw_addr_o),
    .w_valid_i(ame_w_valid_o), .w_ready_o(ame_w_ready_i), .w_data_i(ame_w_data_o),
    .w_strb_i(ame_w_strb_o),
    .b_valid_o(ame_b_valid_i), .b_ready_i(ame_b_ready_o), .b_resp_o(ame_b_resp_i),
    .ar_valid_i(ame_ar_valid_o), .ar_ready_o(ame_ar_ready_i), .ar_addr_i(ame_ar_addr_o),
    .r_valid_o(ame_r_valid_i), .r_ready_i(ame_r_ready_o), .r_data_o(ame_r_data_i),
    .r_resp_o(ame_r_resp_i));

  tb_xmem_psram u_psram (.clk_i(clk), .a_i(xa), .di_i(xdi), .do_o(xdo),
    .ce_ni(xce), .oe_ni(xoe), .we_ni(xwe), .dump_req_i(dump_req));

  `include "tb_bfm_tasks.svh"

`ifndef KV_BB
  int dbg_br;
  logic dbg_brarm;
  always @(negedge clk) begin
    if (!rst_n) begin dbg_br = 0; dbg_brarm = 1'b0; end
    else begin
      if ($test$plusargs("dbgbr") && dut.u_kvc.st_q == 4'd5) dbg_brarm <= 1'b1;
      if ($test$plusargs("dbgbr") && dbg_brarm && dbg_br < 24) begin
        $display("[br %0d] cs=%b busy=%b bst=%0d done=%b err=%b axi_arv=%b axi_arr=%b axi_a=%h axi_rv=%b rdata_q=%08h",
          dbg_br, dut.g_kv_a.u_kvbe.bp_cs_i[0], dut.g_kv_a.u_kvbe.st_q != 2'd0,
          dut.g_kv_a.u_kvbe.st_q, dut.g_kv_a.u_kvbe.bp_done_o,
          dut.g_kv_a.u_kvbe.bp_err_o, dut.g_kv_a.u_kvbe.m_ar_valid_o,
          dut.g_kv_a.u_kvbe.m_ar_ready_i, dut.g_kv_a.u_kvbe.m_ar_addr_o,
          dut.g_kv_a.u_kvbe.m_r_valid_i, dut.g_kv_a.u_kvbe.rdata_q);
        dbg_br = dbg_br + 1;
      end
    end
  end
`endif

  always @(posedge clk) begin
    if (rst_n && $test$plusargs("dbg388go") && dut.u_kvc.csr_w_accept &&
        ($time > 4560000000) && ($time < 4590000000))
      $display("[csrw] t=%0t off=%0d dat=%h go_fire=%b go_bad=%b go_ok=%b go_mode=%0d tr=%b head=%0d pos=%0d cnt=%0d slice=%h",
        $time, dut.u_kvc.w_off, dut.u_kvc.w_dat, dut.u_kvc.go_fire,
        dut.u_kvc.go_bad, dut.u_kvc.go_ok, dut.u_kvc.go_mode, dut.u_kvc.go_tr,
        dut.u_kvc.reg_head, dut.u_kvc.reg_pos, dut.u_kvc.reg_count,
        dut.u_kvc.reg_slice);
  end

  int dbg_app;
  logic dbg_armapp;
  always @(negedge clk) begin
    if (!rst_n) begin dbg_app = 0; dbg_armapp = 1'b0; end
    else begin
      if ($test$plusargs("dbgapp") && dut.u_kvc.bp_op_q == 3'd1 && dut.u_kvc.bp_run_q)
        dbg_armapp <= 1'b1;
      if ($test$plusargs("dbgapp") && dbg_armapp && dbg_app < 40) begin
        $display("[app %0d] cs=%b we=%b addr=%0d idx=%0d posq=%0d done=%b gap=%b wdata=%08h",
          dbg_app, dut.u_kvc.bp_cs_o[0], dut.u_kvc.bp_we_o[0],
          dut.u_kvc.bp_addr_o[10:0], dut.u_kvc.bp_idx_q, dut.u_kvc.bp_pos_q,
          dut.u_kvc.bp_done_i, dut.u_kvc.bp_gap_q, dut.u_kvc.bp_wdata_o[31:0]);
        dbg_app = dbg_app + 1;
      end
    end
  end

  int dbg_rd5;
  logic dbg_arm5;
  always @(negedge clk) begin
    if (!rst_n) begin dbg_rd5 = 0; dbg_arm5 = 1'b0; end
    else begin
      if ($test$plusargs("dbgrd5") && dut.u_kvc.st_q == 4'd5) dbg_arm5 <= 1'b1;
      if ($test$plusargs("dbgrd5") && dbg_arm5 && dbg_rd5 < 8 &&
          dut.u_kvc.bp_run_q) begin
        $display("[bp5 %0d] cs=%b we=%b addr=%0d idx=%0d done=%b rdata_bank=%08h op=%0d",
          dbg_rd5, dut.u_kvc.bp_cs_o[0], dut.u_kvc.bp_we_o[0],
          dut.u_kvc.bp_addr_o[10:0], dut.u_kvc.bp_idx_q, dut.u_kvc.bp_done_i,
          dut.u_kvc.bp_rdata_bank, dut.u_kvc.bp_op_q);
        dbg_rd5 = dbg_rd5 + 1;
      end
    end
  end

`ifndef KV_BB
  int dbg_a;
  logic dbg_aarm;
  always @(negedge clk) begin
    if (!rst_n) begin dbg_a = 0; dbg_aarm = 1'b0; end
    else begin
      if ($test$plusargs("dbga") && dut.u_kvc.st_q == 4'd6) dbg_aarm <= 1'b1;
      if ($test$plusargs("dbga") && dbg_aarm && dbg_a < 10) begin
        $display("[A %0d] st=%0d ph=%b busy=%b pend=%b cur=%h s=%h | slot_a=%h slot_d=%08h | lb=%08h,%08h,%08h,%08h",
          dbg_a, dut.u_kvc.st_q, dut.u_kvc.wr_ph_q, dut.u_kvc.buswr_busy_q,
          dut.u_kvc.buswr_pend_q, dut.u_kvc.buswr_cur_q, dut.u_kvc.buswr_s_q,
          dut.u_kvc.wr_slot_addr_q, dut.u_kvc.wr_slot_data_q,
          dut.u_kvc.line_buf[0 +: 32], dut.u_kvc.line_buf[32 +: 32],
          dut.u_kvc.line_buf[64 +: 32], dut.u_kvc.line_buf[96 +: 32]);
        dbg_a = dbg_a + 1;
      end
    end
  end
`endif

  int dbg_cc;
  logic dbg_trig;
  always @(negedge clk) begin
    if (!rst_n) begin dbg_cc = 0; dbg_trig = 1'b0; end
    else begin
      if ($test$plusargs("dbgcyc") && dut.u_kvc.buswr_start && !dbg_trig)
        dbg_trig <= 1'b1;
      if ($test$plusargs("dbgcyc") && dbg_trig && dbg_cc < 14) begin
        $display("[cyc %0d] cur=%08h s=%08h e=%08h req=%b acc=%b addr=%08h data=%08h l=%02x/%02x/%02x/%02x",
          dbg_cc, dut.u_kvc.buswr_cur_q, dut.u_kvc.buswr_s_q, dut.u_kvc.buswr_e_q,
          dut.u_kvc.ib_wr_req, dut.u_kvc.ib_wr_acc,
          dut.u_kvc.ib_wr_addr, dut.u_kvc.wr_slot_data_q,
          dut.u_kvc.lane0[7:0], dut.u_kvc.lane1[7:0],
          dut.u_kvc.lane2[7:0], dut.u_kvc.lane3[7:0]);
        $display("        b0=%0d i0=%b off=%0d cur6=%0d s6=%0d lb_w0=%08h lb_w1=%08h",
          dut.u_kvc.lane_b0, dut.u_kvc.lane_i0, dut.u_kvc.buswr_off_q,
          dut.u_kvc.buswr_cur_q[5:0], dut.u_kvc.buswr_s_q[5:0],
          dut.u_kvc.line_buf[0 +: 32], dut.u_kvc.line_buf[32 +: 32]);
        dbg_cc = dbg_cc + 1;
      end
    end
  end

  int dbg_bwr;
  logic dbg_arm;
  always @(posedge clk) begin
    if (!rst_n) begin dbg_bwr = 0; dbg_arm = 1'b0; end
    else begin
      if (dut.u_kvc.csr_w_accept && dut.u_kvc.w_off == 4'h0 && dut.u_kvc.w_dat[8])
        dbg_arm <= 1'b1;
      if ($test$plusargs("dbgwr") && dbg_arm && dbg_bwr < 8 &&
          dut.u_kvc.m_aw_valid_o && dut.u_kvc.m_aw_ready_i) begin
        $display("[kww %0d] addr=%08h data=%08h strb=%b cur_q=%08h s_q=%08h e_q=%08h | l0=%02x l1=%02x l2=%02x l3=%02x ibdata=%08h",
          dbg_bwr, dut.u_kvc.m_aw_addr_o, dut.u_kvc.m_w_data_o, dut.u_kvc.m_w_strb_o,
          dut.u_kvc.buswr_cur_q, dut.u_kvc.buswr_s_q, dut.u_kvc.buswr_e_q,
          dut.u_kvc.lane0[7:0], dut.u_kvc.lane1[7:0],
          dut.u_kvc.lane2[7:0], dut.u_kvc.lane3[7:0], dut.u_kvc.wr_slot_data_q, dut.u_kvc.wr_ph_q);
        dbg_bwr = dbg_bwr + 1;
      end
    end
  end

  int dbg_wr_cnt;
  always @(posedge clk) begin
    if (!rst_n) dbg_wr_cnt = 0;
    else if ($test$plusargs("dbgkb2") && dbg_wr_cnt < 24) begin
      if (dut.u_kvc.bp_run_q && dut.u_kvc.bp_we_o[0] && dut.u_kvc.bp_op_q == 3'd1) begin
        $display("[bpw %0d] addr=%0d wdata=%08h idx=%0d | lb0=%08h lb1=%08h lb2=%08h lb3=%08h",
          dbg_wr_cnt, dut.u_kvc.bp_addr_o[10:0], dut.u_kvc.bp_wdata_o[31:0],
          dut.u_kvc.bp_idx_q,
          dut.u_kvc.line_buf[0 +: 32], dut.u_kvc.line_buf[32 +: 32],
          dut.u_kvc.line_buf[64 +: 32], dut.u_kvc.line_buf[96 +: 32]);
        dbg_wr_cnt = dbg_wr_cnt + 1;
      end
    end
  end

  int dbg_rd_cnt;
  always @(posedge clk) begin
    if (!rst_n) dbg_rd_cnt = 0;
    else if ($test$plusargs("dbgkb") && dbg_rd_cnt < 40) begin
      if (dut.u_kvc.ib_rd_acc) begin
        $display("[kbrd %0d] acc addr=%08h", dbg_rd_cnt, dut.u_kvc.m_ar_addr_o);
      end
      if (dut.u_kvc.ib_r_take) begin
        $display("[kbrd %0d] rdata=%08h", dbg_rd_cnt, dut.u_kvc.m_r_data_i);
        dbg_rd_cnt = dbg_rd_cnt + 1;
      end
    end
  end

  localparam int unsigned MAXCMD = 1024;
  localparam int unsigned MAXEXP = 40000;
  localparam int unsigned MAXSRC = 32768;
  localparam int unsigned NLAYERS = (`KV_CTX_VAL >= 256) ? 2 : 1;

  logic [31:0] cmds [0:MAXCMD*16-1];
  logic [31:0] expd [0:MAXEXP-1];
  logic [31:0] srcw [0:MAXSRC-1];
  int ncmd, nexp, nsrc, exp_ptr;
  int nops_run, nread_ops, nmis;

  task automatic load_files();
    begin
      for (int i = 0; i < MAXCMD*16; i++) cmds[i] = 32'h0;
      for (int i = 0; i < MAXEXP; i++)    expd[i]  = 32'h0;
      for (int i = 0; i < MAXSRC; i++)    srcw[i]  = 32'h0;
      $readmemh("kv_cmds.hex", cmds);
      $readmemh("kv_exp.hex", expd);
      $readmemh("kv_src.hex", srcw);
    end
  endtask

  task automatic run_ops();
    logic [31:0] w0, ctrl;
    logic [2:0]  mode;
    logic        tr, irq, exp_err;
    logic [3:0]  exp_code;
    logic [31:0] st, d;
    int unsigned rbw;
    begin
      exp_ptr = 0; nops_run = 0; nread_ops = 0; nmis = 0;
      for (int c = 0; c < ncmd; c++) begin
        w0       = cmds[c*16 + 0];
        mode     = w0[2:0];
        tr       = w0[4];
        irq      = w0[5];
        exp_err  = w0[7];
        exp_code = w0[11:8];
        rbw      = cmds[c*16 + 9];
        if ((w0 === 32'hx) || (mode > 3'd5)) begin
          if (w0 === 32'hx || w0 === 32'h0) begin
            if (c > 0) c = ncmd; // 结束
          end
        end else begin
          nops_run = nops_run + 1;
          if ($test$plusargs("dbgpre") && c >= 386 && c <= 392) begin
            logic [31:0] pre0;
            axi_read(amechip_pkg::A_KV_BASE + amechip_pkg::KV_STATUS_OFF, pre0);
            $display("[dbgpre] cmd#%0d pre-status=%08h", c, pre0);
          end
          kv_cfg(32'h0, cmds[c*16+1], cmds[c*16+2], cmds[c*16+3],
                 cmds[c*16+4], cmds[c*16+5], cmds[c*16+6],
                 cmds[c*16+7], cmds[c*16+8]);
          kv_go(mode, tr, irq);
          if ($test$plusargs("dbg388") && c == 388) begin
            logic [31:0] pre;
            axi_read(amechip_pkg::A_KV_BASE + amechip_pkg::KV_STATUS_OFF, pre);
            $display("[dbg388] pre-status=%08h", pre);
          end
          if ($test$plusargs("dbg388") && c == 388)
            $display("[dbg388] head=%0d pos=%0d cnt=%0d slice=%h layer=%h ctrl=%h | go_fire=%b go_bad=%b go_ok=%b",
              dut.u_kvc.reg_head, dut.u_kvc.reg_pos, dut.u_kvc.reg_count,
              dut.u_kvc.reg_slice, dut.u_kvc.reg_layer, dut.u_kvc.reg_ctrl,
              dut.u_kvc.go_fire, dut.u_kvc.go_bad, dut.u_kvc.go_ok);
          kv_wait(st);
          if (exp_err) begin
            if (st[2] !== 1'b1 || st[7:4] !== exp_code) begin
              $display("[FAIL] cmd#%0d mode=%0d: 期望 ERR=%0d code=%0d,得 st=%08h",
                       c, mode, exp_err, exp_code, st);
              nmis = nmis + 1;
            end
          end else begin
            if (st[1] !== 1'b1 || st[2] !== 1'b0) begin
              $display("[FAIL] cmd#%0d mode=%0d: 期望 DONE,得 st=%08h", c, mode, st);
              nmis = nmis + 1;
            end
            if ((mode == 3'd3 || mode == 3'd4) && rbw > 0) begin
              nread_ops = nread_ops + 1;
              for (int i = 0; i < rbw; i++) begin
                axi_read(cmds[c*16+6] + 4*i, d);
                if (d !== expd[exp_ptr + i]) begin
                  if (nmis < 20 || ($test$plusargs("dumpread") && c == 132))
                    $display("[FAIL] cmd#%0d(mode %0d) word[%0d] @%08h got=%08h exp=%08h",
                             c, mode, i, cmds[c*16+6] + 4*i, d, expd[exp_ptr + i]);
                  nmis = nmis + 1;
                end
              end
              exp_ptr = exp_ptr + rbw;
            end
          end
          axi_write(amechip_pkg::A_KV_BASE + amechip_pkg::KV_STATUS_OFF, 32'h6);
          if ($test$plusargs("dump132") && c == 132)
            $writememh("ocram_after132.hex", dut.u_ocram.u_ram.mem);
        end
      end
    end
  endtask

  initial begin
    rst_n = 1'b0;
    c_aw_valid = 0; c_w_valid = 0; c_ar_valid = 0; c_b_ready = 0; c_r_ready = 0;
    c_aw_addr = '0; c_w_data = '0; c_w_strb = '0; c_ar_addr = '0;
    dump_req = 1'b0;
    load_files();
    ncmd = 0;
    for (int c = 0; c < MAXCMD; c++) begin
      if (cmds[c*16] !== 32'hx && !(cmds[c*16] === 32'h0 &&
          cmds[c*16+1] === 32'h0 && cmds[c*16+6] === 32'h0 &&
          cmds[c*16+4] === 32'h0)) ncmd = c + 1;
    end
    $display("[tb_kv] 命令数 = %0d", ncmd);
    if (ncmd == 0) begin
      $display("[FAIL] tb_kv: 未找到 kv_cmds.hex(请在 golden 目录运行)");
      $display("TB_KV: FAIL");
      $finish;
    end

    repeat (5) @(posedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);

    for (int la = 0; la < NLAYERS; la++) begin
      for (int i = 0; i < 16384; i++) begin
        if (srcw[la*16384 + i] !== 32'hx)
          axi_write(32'h4048_0000 + la*32'h20000 + 4*i, srcw[la*16384 + i]);
      end
    end
    $display("[tb_kv] 源数据预载完成  srcw[0]=%08h srcw[1]=%08h", srcw[0], srcw[1]);
    begin
      logic [31:0] d0;
      axi_read(32'h4048_0000, d0);
      $display("[tb_kv] XMEM@40480000 = %08h (srcw[0]=%08h)", d0, srcw[0]);
    end

    run_ops();

    @(negedge clk);
    $writememh("ocram_dump.hex", dut.u_ocram.u_ram.mem);
`ifdef KV_BB
    $writememh("kv_dump_bank0.hex", dut.g_kv_b.u_kvbe.g_bank[0].u_bank.mem);
    $writememh("kv_dump_bank1.hex", dut.g_kv_b.u_kvbe.g_bank[1].u_bank.mem);
    $writememh("kv_dump_bank2.hex", dut.g_kv_b.u_kvbe.g_bank[2].u_bank.mem);
    $writememh("kv_dump_bank3.hex", dut.g_kv_b.u_kvbe.g_bank[3].u_bank.mem);
    $display("[tb_kv] bank 镜像转储完成");
`else
    dump_req = 1'b1;
    @(negedge clk);
    dump_req = 1'b0;
`endif
    repeat (2) @(posedge clk);

    $display("=== tb_kv: ops=%0d read_ops=%0d exp_words=%0d mismatches=%0d ===",
             nops_run, nread_ops, exp_ptr, nmis);
    if (nmis == 0) $display("TB_KV: PASS");
    else           $display("TB_KV: FAIL");
    $finish;
  end

  initial begin
    #200_000_000;
    $display("[FAIL] tb_kv 全局超时");
    $display("TB_KV: FAIL");
    $finish;
  end

endmodule
