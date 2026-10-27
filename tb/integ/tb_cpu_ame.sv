
`timescale 1ns/1ps

`ifndef _AMECHIP_PKG_SV
 `include "amechip_pkg.sv"
`endif
`ifndef _SOC_PKG_SV
 `include "soc_pkg.sv"
`endif

module tb_cpu_ame;

  localparam real CLKP    = 10.0;
  localparam int  BIT_CYC = 13;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  always #(CLKP/2.0) clk = ~clk;

  wire        uart_tx, irq_int;
  wire        cpu_halt, cpu_wfi, cpu_buserr;
  wire        cpu_tv;
  wire [31:0] cpu_tpc, cpu_tinstr, cpu_twdata;
  wire [4:0]  cpu_trd;
  wire [1:0]  cpu_tflag;

  wire [31:0] ax_aw_addr, ax_w_data, ax_ar_addr, ax_r_data;
  wire        ax_aw_valid, ax_aw_ready, ax_w_valid, ax_w_ready;
  wire        ax_b_valid, ax_b_ready, ax_ar_valid, ax_ar_ready;
  wire        ax_r_valid, ax_r_ready;
  wire [3:0]  ax_w_strb;
  wire [1:0]  ax_b_resp, ax_r_resp;

  wire        ame_req_valid, ame_req_ready, ame_resp_valid, ame_resp_err;
  wire [31:0] ame_req_instr, ame_req_rs1, ame_req_rs2, ame_resp_data;

  ame_cpu u_cpu (
    .clk_i          (clk),
    .rst_ni         (rst_n),
    .ax_aw_addr     (ax_aw_addr),
    .ax_aw_valid    (ax_aw_valid),
    .ax_aw_ready    (ax_aw_ready),
    .ax_w_data      (ax_w_data),
    .ax_w_strb      (ax_w_strb),
    .ax_w_valid     (ax_w_valid),
    .ax_w_ready     (ax_w_ready),
    .ax_b_resp      (ax_b_resp),
    .ax_b_valid     (ax_b_valid),
    .ax_b_ready     (ax_b_ready),
    .ax_ar_addr     (ax_ar_addr),
    .ax_ar_valid    (ax_ar_valid),
    .ax_ar_ready    (ax_ar_ready),
    .ax_r_data      (ax_r_data),
    .ax_r_resp      (ax_r_resp),
    .ax_r_valid     (ax_r_valid),
    .ax_r_ready     (ax_r_ready),
    .ame_req_valid  (ame_req_valid),
    .ame_req_instr  (ame_req_instr),
    .ame_req_rs1    (ame_req_rs1),
    .ame_req_rs2    (ame_req_rs2),
    .ame_req_ready  (ame_req_ready),
    .ame_resp_valid (ame_resp_valid),
    .ame_resp_data  (ame_resp_data),
    .ame_resp_err   (ame_resp_err),
    .irq_i          (irq_int),
    .halt_o         (cpu_halt),
    .wfi_o          (cpu_wfi),
    .bus_err_o      (cpu_buserr),
    .trace_valid_o  (cpu_tv),
    .trace_pc_o     (cpu_tpc),
    .trace_instr_o  (cpu_tinstr),
    .trace_rd_o     (cpu_trd),
    .trace_wdata_o  (cpu_twdata),
    .trace_flag_o   (cpu_tflag)
  );

  wire        ame_irq_done, ame_irq_err, ame_mac_en, ame_idle;
  wire        ame_busy = ~ame_idle;
  wire        awin_v, awin_ready, awin_wr, awin_rv, awin_err;
  wire [31:0] awin_addr, awin_wdata, awin_rdata;
  wire [3:0]  awin_strb;

  ame_core u_ame (
    .clk_i            (clk),
    .rst_ni           (rst_n),
    .cp_req_valid_i   (ame_req_valid),
    .cp_req_instr_i   (ame_req_instr),
    .cp_req_rs1_i     (ame_req_rs1),
    .cp_req_rs2_i     (ame_req_rs2),
    .cp_req_ready_o   (ame_req_ready),
    .cp_resp_valid_o  (ame_resp_valid),
    .cp_resp_data_o   (ame_resp_data),
    .cp_resp_err_o    (ame_resp_err),
    .bus_req_valid_i  (awin_v),
    .bus_req_write_i  (awin_wr),
    .bus_req_addr_i   (awin_addr),
    .bus_req_wdata_i  (awin_wdata),
    .bus_req_wstrb_i  (awin_strb),
    .bus_req_ready_o  (awin_ready),
    .bus_resp_valid_o (awin_rv),
    .bus_resp_rdata_o (awin_rdata),
    .bus_resp_err_o   (awin_err),
    .irq_done_o       (ame_irq_done),
    .irq_err_o        (ame_irq_err),
    .dbg_mac_en_o     (ame_mac_en),
    .dbg_idle_o       (ame_idle)
  );

  soc_pkg::soc_req_t  cpu_req, dma_req, kv_req;
  soc_pkg::soc_resp_t cpu_rsp, dma_rsp, kv_rsp;

  wire [31:0] f_addr, f_waddr, f_rdata, f_wdata;
  wire        f_we;
  wire [3:0]  f_wstrb;
  wire [1:0]  f_resp;

  vrfb_axi2b u_axi2b (
    .clk(clk), .rst_n(rst_n),
    .ax_aw_addr(ax_aw_addr), .ax_aw_valid(ax_aw_valid), .ax_aw_ready(ax_aw_ready),
    .ax_w_data(ax_w_data), .ax_w_strb(ax_w_strb), .ax_w_valid(ax_w_valid),
    .ax_w_ready(ax_w_ready),
    .ax_b_resp(ax_b_resp), .ax_b_valid(ax_b_valid), .ax_b_ready(ax_b_ready),
    .ax_ar_addr(ax_ar_addr), .ax_ar_valid(ax_ar_valid), .ax_ar_ready(ax_ar_ready),
    .ax_r_data(ax_r_data), .ax_r_resp(ax_r_resp), .ax_r_valid(ax_r_valid),
    .ax_r_ready(ax_r_ready),
    .bus_req(cpu_req), .bus_resp(cpu_rsp),
    .f_addr(f_addr), .f_waddr(f_waddr), .f_we(f_we), .f_wdata(f_wdata), .f_wstrb(f_wstrb),
    .f_rdata(f_rdata), .f_resp(f_resp)
  );

  soc_pkg::soc_req_t  s0_req, s1_req, s2_req, s3_req, s4_req, s5_req, s6_req, s7_req;
  soc_pkg::soc_resp_t s0_rsp, s1_rsp, s2_rsp, s3_rsp, s4_rsp, s5_rsp, s6_rsp, s7_rsp;

  wire dbg_en = DBG;
  vrfb_xbar u_xbar (
    .clk(clk), .rst_n(rst_n), .dbg_i(dbg_en),
    .m0_req(cpu_req), .m0_resp(cpu_rsp),
    .m1_req(dma_req), .m1_resp(dma_rsp),
    .m2_req(kv_req),  .m2_resp(kv_rsp),
    .s0_req(s0_req), .s0_resp(s0_rsp),
    .s1_req(s1_req), .s1_resp(s1_rsp),
    .s2_req(s2_req), .s2_resp(s2_rsp),
    .s3_req(s3_req), .s3_resp(s3_rsp),
    .s4_req(s4_req), .s4_resp(s4_rsp),
    .s5_req(s5_req), .s5_resp(s5_rsp),
    .s6_req(s6_req), .s6_resp(s6_rsp),
    .s7_req(s7_req), .s7_resp(s7_rsp)
  );

  logic dump_pulse = 1'b0;

  vrfb_mem_model u_mem (
    .clk(clk), .rst_n(rst_n),
    .bus_req(s0_req), .bus_resp(s0_rsp),
    .dump_i(dump_pulse),
    .f_addr(f_addr), .f_waddr(f_waddr), .f_we(f_we), .f_wdata(f_wdata), .f_wstrb(f_wstrb),
    .f_rdata(f_rdata), .f_resp(f_resp)
  );

  wire uart_irq_tx, uart_irq_rx, soft_set, soft_clear;

  soc_syscsr u_sys (
    .clk(clk), .rst_n(rst_n),
    .bus_req(s1_req), .bus_resp(s1_rsp),
    .cpu_wfi_i(cpu_wfi), .ame_busy_i(ame_busy),
    .dma_busy_i(dma_busy), .kv_busy_i(kv_busy),
    .soft_set_o(soft_set), .soft_clear_o(soft_clear)
  );

  soc_intc u_intc (
    .clk(clk), .rst_n(rst_n),
    .bus_req(s2_req), .bus_resp(s2_rsp),
    .lvl_uart_tx_i(uart_irq_tx), .lvl_uart_rx_i(uart_irq_rx),
    .evt_dma_done_i(dma_done_evt), .evt_dma_err_i(dma_err_evt),
    .evt_ame_done_i(ame_irq_done), .evt_ame_err_i(ame_irq_err),
    .evt_kv_done_i(kv_done_evt), .evt_kv_err_i(kv_err_evt),
    .evt_buserr_i(cpu_buserr),
    .soft_set_i(soft_set), .soft_clear_i(soft_clear),
    .irq_o(irq_int)
  );

  soc_uart u_uart (
    .clk(clk), .rst_n(rst_n),
    .bus_req(s3_req), .bus_resp(s3_rsp),
    .tx_o(uart_tx), .rx_i(1'b1),
    .irq_tx_o(uart_irq_tx), .irq_rx_o(uart_irq_rx)
  );

  wire dma_busy, dma_done_evt, dma_err_evt;
  vrfb_dma_model u_dma (
    .clk(clk), .rst_n(rst_n),
    .bus_req(s4_req), .bus_resp(s4_rsp),
    .m_req(dma_req), .m_resp(dma_rsp),
    .evt_done_o(dma_done_evt), .evt_err_o(dma_err_evt), .busy_o(dma_busy)
  );

  assign awin_v     = s5_req.valid;
  assign awin_wr    = s5_req.write;
  assign awin_addr  = s5_req.addr;
  assign awin_wdata = s5_req.wdata;
  assign awin_strb  = s5_req.wstrb;
  assign s5_rsp.valid = awin_rv;
  assign s5_rsp.rdata = awin_rdata;
  assign s5_rsp.resp  = awin_err ? amechip_pkg::AXI_SLVERR : amechip_pkg::AXI_OKAY;

  wire kv_busy, kv_done_evt, kv_err_evt;
  vrfb_kv_model u_kv (
    .clk(clk), .rst_n(rst_n),
    .bus_req(s6_req), .bus_resp(s6_rsp),
    .m_req(kv_req), .m_resp(kv_rsp),
    .dump_i(dump_pulse),
    .evt_done_o(kv_done_evt), .evt_err_o(kv_err_evt), .busy_o(kv_busy)
  );

  vrfb_xmem_model u_xmem (
    .clk(clk), .rst_n(rst_n),
    .bus_req(s7_req), .bus_resp(s7_rsp),
    .dump_i(dump_pulse)
  );

  logic s3v_q;
  always @(posedge clk) begin
    if (DBG && (s3_req.valid || s3_rsp.valid || (s3v_q && !s3_req.valid)))
      $display("[U3] t=%0t req_v=%b wr=%b addr=%08h wdata=%08h resp_v=%b rdata=%08h",
               $time, s3_req.valid, s3_req.write, s3_req.addr, s3_req.wdata,
               s3_rsp.valid, s3_rsp.rdata);
    s3v_q <= s3_req.valid;
  end

  always @(posedge clk) begin
    if (DBG && s0_req.valid && s0_req.write && s0_req.addr < 32'h1000)
      $display("[U0] t=%0t wr addr=%08h data=%08h strb=%b",
               $time, s0_req.addr, s0_req.wdata, s0_req.wstrb);
  end

  always @(posedge clk) begin
    if (rst_n && (cyc % 200000) == 0)
      $display("[HB] cyc=%0d pc=%08h instr=%08h ame_v=%b rdy=%b ame_busy=%0d dma_busy=%0d kv_busy=%0d",
               cyc, cpu_tpc, cpu_tinstr, ame_req_valid, ame_req_ready,
               perf_ame_busy, perf_dma_busy, perf_kv_busy);
  end

  reg WDBG;
  integer WC0, WC1;
  initial begin
    if ($test$plusargs("WDBG")) WDBG = 1'b1; else WDBG = 1'b0;
    if (!$value$plusargs("WC0=%d", WC0)) WC0 = 0;
    if (!$value$plusargs("WC1=%d", WC1)) WC1 = 0;
  end
  always @(posedge clk) begin
    if (WDBG && cyc >= WC0 && cyc <= WC1)
      $display("[W] cyc=%0d v=%b rdy=%b err=%b idle=%b tset=%b xset=%b wact=%b xact=%b instr=%08h rs1=%08h",
               cyc, ame_req_valid, ame_req_ready, ame_resp_err, ame_idle,
               {u_ame.u_ctrl.tset_q[1], u_ame.u_ctrl.tset_q[0]},
               {u_ame.u_ctrl.xset_q[1], u_ame.u_ctrl.xset_q[0]},
               u_ame.u_ctrl.wld_active_q, u_ame.u_ctrl.xld_active_q,
               ame_req_instr, ame_req_rs1);
  end

  reg SDBG;
  initial if ($test$plusargs("SDBG")) SDBG = 1'b1; else SDBG = 1'b0;
  logic [31:0] st_instr_q, st_start;
  logic        st_act;
  always @(posedge clk) begin
    if (ame_req_valid && !ame_req_ready && !st_act) begin
      st_act <= 1'b1; st_start <= cyc; st_instr_q <= ame_req_instr;
    end
    if (st_act && (cyc - st_start) == 50)
      $display("[STALL-LONG] cyc=%0d instr=%08h sel=%08h idle=%b", cyc, st_instr_q,
               ame_req_rs1, ame_idle);
    if (st_act && (ame_req_ready || !ame_req_valid)) begin
      if (SDBG && (cyc - st_start) >= 8)
        $display("[STALL] cyc=%0d instr=%08h sel=%08h cyc_stall=%0d",
                 cyc, st_instr_q, ame_req_rs1, cyc - st_start);
      st_act <= 1'b0;
    end
  end

  reg QDBG;
  initial if ($test$plusargs("QDBG")) QDBG = 1'b1; else QDBG = 1'b0;
  always @(posedge clk) begin
    if (QDBG && ame_req_valid && ame_req_ready &&
        (ame_req_instr[6:0] == 7'h0B) && (ame_req_instr[14:12] == 3'h1))
      $display("[QCFG] cyc=%0d ch=%0d M=%0d rs2=%08h", cyc,
               ame_req_instr[11:7], ame_req_rs1, ame_req_rs2);
  end

  reg TDBG;
  initial if ($test$plusargs("TILEDBG")) TDBG = 1'b1; else TDBG = 1'b0;
  always @(posedge clk) begin
    if (TDBG && ame_req_valid && ame_req_ready &&
        (ame_req_instr[6:0] == 7'h0B) && (ame_req_instr[14:12] == 3'h2)) begin
      $write("[TILE] cyc=%0d ld.w sel=%0d row12:", cyc, ame_req_rs1[2]);
      for (int kk = 0; kk < 16; kk = kk + 1)
        $write(" %02x", u_ame.u_array.tile_q[ame_req_rs1[2]][12][kk]);
      $write("\n");
    end
    if (TDBG && ame_req_valid && ame_req_ready &&
        (ame_req_instr[6:0] == 7'h0B) && (ame_req_instr[14:12] == 3'h4)) begin
      $write("[XREG] cyc=%0d exe sel=%0d x:", cyc, ame_req_rs1[0]);
      for (int kk = 0; kk < 16; kk = kk + 1)
        $write(" %02x", u_ame.u_array.x_q[ame_req_rs1[0]][kk]);
      $write(" | t12:");
      for (int kk = 0; kk < 16; kk = kk + 1)
        $write(" %02x", u_ame.u_array.tile_q[ame_req_rs1[0]][12][kk]);
      $write(" | y12=%08x\n", u_ame.u_array.y_q[12]);
    end
  end

  always @(posedge clk) begin
    if (DBG && (s6_req.valid || s6_rsp.valid))
      $display("[U6] t=%0t req_v=%b wr=%b addr=%08h wdata=%08h resp_v=%b rdata=%08h",
               $time, s6_req.valid, s6_req.write, s6_req.addr, s6_req.wdata,
               s6_rsp.valid, s6_rsp.rdata);
    if (DBG && kv_err_evt) $display("[EVT] kv_err @%0t", $time);
    if (DBG && kv_done_evt) $display("[EVT] kv_done @%0t", $time);
    if (DBG && dma_err_evt) $display("[EVT] dma_err @%0t", $time);
    if (DBG && cpu_buserr) $display("[EVT] cpu_buserr @%0t", $time);
    if (DBG && (s2_req.valid || s2_rsp.valid))
      $display("[U2-INTC] t=%0t req_v=%b wr=%b addr=%08h wdata=%08h rdata=%08h",
               $time, s2_req.valid, s2_req.write, s2_req.addr, s2_req.wdata, s2_rsp.rdata);
  end

  always @(posedge clk) begin
    if (DBG && (s5_req.valid || s5_rsp.valid))
      $display("[U5] t=%0t req_v=%b wr=%b addr=%08h wdata=%08h strb=%b resp_v=%b rdata=%08h",
               $time, s5_req.valid, s5_req.write, s5_req.addr, s5_req.wdata,
               s5_req.wstrb, s5_rsp.valid, s5_rsp.rdata);
  end

  always @(posedge clk) begin
    if (DBG && (s4_req.valid || s4_rsp.valid))
      $display("[U4] t=%0t req_v=%b wr=%b addr=%08h wdata=%08h resp_v=%b rdata=%08h",
               $time, s4_req.valid, s4_req.write, s4_req.addr, s4_req.wdata,
               s4_rsp.valid, s4_rsp.rdata);
  end

  reg DBG;
  initial if ($test$plusargs("DBG")) DBG = 1'b1; else DBG = 1'b0;
  integer TW0, TW1;
  initial begin
    if (!$value$plusargs("TW0=%d", TW0)) TW0 = 0;
    if (!$value$plusargs("TW1=%d", TW1)) TW1 = 0;
  end
  always @(posedge clk) begin
    if (DBG && cpu_tv && (TW1 == 0 || (cyc >= TW0 && cyc <= TW1)))
      $display("[TRACE] cyc=%0d pc=%08h instr=%08h rd=x%0d wd=%08h fl=%b",
               cyc, cpu_tpc, cpu_tinstr, cpu_trd, cpu_twdata, cpu_tflag);
  end

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

  logic [7:0] dbg_b [0:8191];
  int         dbg_n;

  always @(posedge clk) ;
  initial begin : dbg_rx
    logic [7:0] bd;
    dbg_n = 0;
    forever begin
      recv_byte(bd);
      dbg_b[dbg_n] = bd;
      dbg_n = dbg_n + 1;
    end
  end

  logic        req_v_d, acc_d, held_q, busy_d;
  logic [31:0] held_instr, held_rs1, held_rs2, req_start_cyc, busy_start, stall_last, stall_max;
  logic [31:0] acc_instr_q, acc_rs1_q, acc_rs2_q;
  logic [5:0]  cfg_kt, exe_kt;
  logic        cfg_pend;
  logic [31:0] cfg_imm_q;
  logic        idle_d, mac_d, mac_run;
  logic [31:0] exe_acc_cyc, mac_start, mac_last_dur, mon_exe_dur;
  int          mon_mac_ok, mon_mac_bad;
  logic        exe_pending;
  logic [31:0] cyc;
  int          mon_accept, mon_resp, mon_err, mon_resp_bad, mon_stab_bad;
  reg          acc_stq_c, acc_stq_d1, acc_stq_d2, acc_stq_d3;
  int          mon_exe_ok, mon_exe_bad, mon_merged, mon_done;
  int          mon_stall_cfg, mon_stall_qcfg, mon_stall_ld, mon_stall_exe, mon_stall_st, mon_stall_sync;
  int          perf_retired, perf_ar, perf_aw, perf_ame_busy, perf_mac, perf_dma_busy, perf_kv_busy, perf_cpu_bus;

  wire [6:0]  mon_opc    = ame_req_instr[6:0];
  wire [2:0]  mon_f3     = ame_req_instr[14:12];
  wire [6:0]  mon_f7     = ame_req_instr[31:25];
  wire        mon_is_exe = (mon_opc == 7'h0B) && (mon_f3 == 3'h4) &&
                           ((mon_f7 == 7'h04) || (mon_f7 == 7'h05));

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      cyc <= 0;
      req_v_d <= 1'b0; acc_d <= 1'b0; held_q <= 1'b0; busy_d <= 1'b0;
      cfg_kt <= 0; exe_kt <= 0; exe_pending <= 1'b0;
      cfg_pend <= 1'b0; cfg_imm_q <= 0;
      idle_d <= 1'b1; exe_acc_cyc <= 0; mac_d <= 1'b0; mac_run <= 1'b0;
      mac_start <= 0; mac_last_dur <= 0; mon_exe_dur <= 0;
      mon_mac_ok <= 0; mon_mac_bad <= 0;
      acc_instr_q <= 0; acc_rs1_q <= 0; acc_rs2_q <= 0;
      mon_accept <= 0; mon_resp <= 0; mon_err <= 0; mon_resp_bad <= 0; mon_stab_bad <= 0;
      acc_stq_c <= 0; acc_stq_d1 <= 0; acc_stq_d2 <= 0; acc_stq_d3 <= 0;
      mon_exe_ok <= 0; mon_exe_bad <= 0; mon_merged <= 0; mon_done <= 0;
      mon_stall_cfg <= 0; mon_stall_qcfg <= 0; mon_stall_ld <= 0;
      mon_stall_exe <= 0; mon_stall_st <= 0; mon_stall_sync <= 0;
      perf_retired <= 0; perf_ar <= 0; perf_aw <= 0; perf_ame_busy <= 0;
      perf_mac <= 0; perf_dma_busy <= 0; perf_kv_busy <= 0; perf_cpu_bus <= 0;
      stall_last <= 0; stall_max <= 0;
    end else begin
      cyc     <= cyc + 1;
      req_v_d <= ame_req_valid;
      acc_d   <= (ame_req_valid && ame_req_ready);
      acc_stq_c <= (ame_req_valid && ame_req_ready)
                   && (ame_req_instr[14:12] == 3'h6)
                   && (ame_req_instr[31:25] == 7'h07)
                   && (ame_req_rs1[31:5] == 27'd0)
                   && (ame_req_rs1[4:0] < 5'd16);

      if (ame_req_valid && !ame_req_ready) begin
        if (held_q && ((ame_req_instr !== held_instr) ||
                       (ame_req_rs1   !== held_rs1)   ||
                       (ame_req_rs2   !== held_rs2)))
          mon_stab_bad <= mon_stab_bad + 1;
        held_q    <= 1'b1;
        held_instr <= ame_req_instr;
        held_rs1   <= ame_req_rs1;
        held_rs2   <= ame_req_rs2;
      end else begin
        held_q <= 1'b0;
      end

      acc_stq_d1 <= acc_stq_c;
      acc_stq_d2 <= acc_stq_d1;
      acc_stq_d3 <= acc_stq_d2;
      if (ame_resp_valid && acc_stq_c && !acc_stq_d1)
        mon_resp_bad <= mon_resp_bad + 1;
      if (ame_resp_valid && !acc_d && !acc_stq_d2)
        mon_resp_bad <= mon_resp_bad + 1;
      if (ame_resp_valid && cfg_pend) begin
        if (!ame_resp_err &&
            (cfg_imm_q[11:10] == 2'b00) && (cfg_imm_q[4:0] != 0) &&
            (cfg_imm_q[9:5] != 0) && (cfg_imm_q[4:0] <= 16) && (cfg_imm_q[9:5] <= 16))
          cfg_kt <= cfg_imm_q[9:5];
        cfg_pend <= 1'b0;
      end
      if (ame_resp_valid && ame_resp_err && DBG)
        $display("[MON] AME ERR instr=%08h opc=%02h f3=%0d f7=%02h rs1=%08h rs2=%08h",
                 acc_instr_q, acc_instr_q[6:0], acc_instr_q[14:12],
                 acc_instr_q[31:25], acc_rs1_q, acc_rs2_q);
      if (ame_req_valid && !req_v_d) req_start_cyc <= cyc;
      if (ame_resp_valid) begin
        mon_resp <= mon_resp + 1;
        if (ame_resp_err) mon_err <= mon_err + 1;
      end

      if (ame_resp_valid && acc_d) ;
      if (ame_req_valid && ame_req_ready) begin
        acc_instr_q <= ame_req_instr;
        acc_rs1_q   <= ame_req_rs1;
        acc_rs2_q   <= ame_req_rs2;
        mon_accept <= mon_accept + 1;
        stall_last <= cyc - req_start_cyc;
        if ((cyc - req_start_cyc) > stall_max) stall_max <= cyc - req_start_cyc;
        if (mon_opc == 7'h0B) begin
          case (mon_f3)
            3'h0: mon_stall_cfg  <= mon_stall_cfg  + int'(cyc - req_start_cyc);
            3'h1: mon_stall_qcfg <= mon_stall_qcfg + int'(cyc - req_start_cyc);
            3'h2: mon_stall_ld   <= mon_stall_ld   + int'(cyc - req_start_cyc);
            3'h3: mon_stall_ld   <= mon_stall_ld   + int'(cyc - req_start_cyc);
            3'h4: mon_stall_exe  <= mon_stall_exe  + int'(cyc - req_start_cyc);
            3'h5: mon_stall_st   <= mon_stall_st   + int'(cyc - req_start_cyc);
            3'h6: mon_stall_st   <= mon_stall_st   + int'(cyc - req_start_cyc);
            3'h7: mon_stall_sync <= mon_stall_sync + int'(cyc - req_start_cyc);
            default: ;
          endcase
        end
        if (mon_is_exe) begin
          if (!ame_busy) begin
          end
        end
        if ((mon_opc == 7'h0B) && (mon_f3 == 3'h0)) begin
          cfg_pend <= 1'b1;
          cfg_imm_q <= ame_req_instr[31:20];
        end
      end

      if (ame_req_valid && ame_req_ready && mon_is_exe) begin
        exe_pending    <= 1'b1;
        exe_acc_cyc    <= cyc;
        exe_kt         <= cfg_kt;
      end
      if (ame_mac_en && !mac_d) begin mac_start <= cyc; mac_run <= 1; end
      if (mac_run && !ame_mac_en) begin
        mac_last_dur <= cyc - mac_start;
        mac_run <= 0;
        if ((cyc - mac_start) == {26'd0, exe_kt}) mon_mac_ok <= mon_mac_ok + 1;
        else begin
          mon_mac_bad <= mon_mac_bad + 1;
          $display("[MON] MAC window=%0d exp=%0d", cyc - mac_start, exe_kt);
        end
      end
      if (ame_idle && !idle_d && exe_pending) begin
        if ((cyc - exe_acc_cyc) == {26'd0, exe_kt} + 32'd3) begin
          mon_exe_ok <= mon_exe_ok + 1;
          mon_exe_dur <= cyc - exe_acc_cyc;
        end else begin
          mon_exe_bad <= mon_exe_bad + 1;
          $display("[MON] exe accept->IDLE=%0d exp=%0d (accept cyc=%0d)",
                   cyc - exe_acc_cyc, exe_kt + 3, exe_acc_cyc);
        end
        exe_pending <= 1'b0;
      end
      idle_d <= ame_idle;
      mac_d <= ame_mac_en;

      if (ame_irq_done) mon_done <= mon_done + 1;

      if (cpu_tv)            perf_retired  <= perf_retired + 1;
      if (ax_ar_valid && ax_ar_ready) perf_ar <= perf_ar + 1;
      if (ax_aw_valid && ax_aw_ready) perf_aw <= perf_aw + 1;
      if (ame_busy)          perf_ame_busy <= perf_ame_busy + 1;
      if (ame_mac_en)        perf_mac      <= perf_mac + 1;
      if (dma_busy)          perf_dma_busy <= perf_dma_busy + 1;
      if (kv_busy)           perf_kv_busy  <= perf_kv_busy + 1;
      if (cpu_req.valid)     perf_cpu_bus  <= perf_cpu_bus + 1;
    end
  end

  logic [7:0]  exp_b [0:8191];
  logic [7:0]  got_b [0:8191];
  reg [1023:0] F_EXP, F_SRAM, F_BOOT, F_XMEM, F_KV, F_SCRD, F_KVD;
  integer      NEXP, MAXCYC, k, errs;
  integer      SCR_BASE_W, SCR_WORDS;
  logic [7:0]  b;

  initial begin
    if (!$value$plusargs("NEXP=%d", NEXP))          NEXP = 0;
    if (!$value$plusargs("MAXCYC=%d", MAXCYC))      MAXCYC = 30000000;
    if (!$value$plusargs("SCR_BASE_W=%d", SCR_BASE_W)) SCR_BASE_W = 0;
    if (!$value$plusargs("SCR_WORDS=%d", SCR_WORDS))   SCR_WORDS = 0;
    if (!$value$plusargs("EXP_UART=%s", F_EXP) || F_EXP == "") NEXP = 0;
    else $readmemh(F_EXP, exp_b);
    if (!$value$plusargs("SRAM_HEX=%s", F_SRAM)) F_SRAM = "";
    if (!$value$plusargs("BOOT_HEX=%s", F_BOOT)) F_BOOT = "";
    if (!$value$plusargs("XMEM_HEX=%s", F_XMEM)) F_XMEM = "";
    if (!$value$plusargs("KV_HEX=%s",   F_KV))   F_KV   = "";
    if (!$value$plusargs("SCR_DUMP=%s", F_SCRD)) F_SCRD = "";
    if (!$value$plusargs("KV_DUMP=%s",  F_KVD))  F_KVD  = "";

    $display("[TB] tb_cpu_ame: NEXP=%0d MAXCYC=%0d", NEXP, MAXCYC);
    repeat (10) @(posedge clk);
    rst_n <= 1'b1;

    for (k = 0; k < NEXP; k = k + 1) begin
      recv_byte(b);
      got_b[k] = b;
    end
    repeat (500) @(posedge clk);

    errs = 0;
    for (k = 0; k < NEXP; k = k + 1) begin
      if (got_b[k] !== exp_b[k]) begin
        if (errs < 12) $display("[TB] UART MISMATCH [%0d]: got=%02x exp=%02x", k, got_b[k], exp_b[k]);
        errs = errs + 1;
      end
    end
    if (NEXP > 0) begin
      $write("[TB] UART cmp: ");
      for (k = 0; k < NEXP; k = k + 1) $write("%c", got_b[k]);
      $write("\n");
    end
    $display("[TB] UART actual bytes: %0d", dbg_n);
    $write("[TB] UART raw: ");
    for (k = 0; k < dbg_n; k = k + 1) $write("%c", dbg_b[k]);
    $write("\n");

    @(posedge clk);
    dump_pulse <= 1'b1;
    @(posedge clk);
    dump_pulse <= 1'b0;
    repeat (20) @(posedge clk);

    $display("AME_MON accept=%0d resp=%0d err=%0d resp_bad=%0d stab_bad=%0d exe_busy_ok=%0d exe_busy_bad=%0d mac_ok=%0d mac_bad=%0d exe_win=%0d mac_win=%0d done=%0d",
             mon_accept, mon_resp, mon_err, mon_resp_bad, mon_stab_bad,
             mon_exe_ok, mon_exe_bad, mon_mac_ok, mon_mac_bad,
             mon_exe_dur, mac_last_dur, mon_done);
    $display("AME_STALL cfg=%0d qcfg=%0d ld=%0d exe=%0d st=%0d sync=%0d max=%0d",
             mon_stall_cfg, mon_stall_qcfg, mon_stall_ld, mon_stall_exe,
             mon_stall_st, mon_stall_sync, stall_max);
    $display("PERF cyc=%0d retired=%0d ar=%0d aw=%0d ame_busy=%0d mac=%0d macs=%0d dma_busy=%0d kv_busy=%0d cpu_bus=%0d",
             cyc, perf_retired, perf_ar, perf_aw, perf_ame_busy, perf_mac,
             perf_mac * amechip_pkg::AME_N_DEF, perf_dma_busy, perf_kv_busy, perf_cpu_bus);

    if (errs == 0 && mon_resp_bad == 0 && mon_stab_bad == 0 && mon_exe_bad == 0)
      $display("P3B PASS");
    else
      $display("P3B FAIL uart_errs=%0d resp_bad=%0d stab_bad=%0d exe_bad=%0d",
               errs, mon_resp_bad, mon_stab_bad, mon_exe_bad);
    @(posedge clk);
    $finish;
  end

  initial begin
    repeat (MAXCYC + 100) @(posedge clk);
    $display("[TB] TIMEOUT cyc=%0d max=%0d", cyc, MAXCYC);
    $display("[TB] UART actual bytes: %0d (expect %0d)", dbg_n, NEXP);
    $write("[TB] UART raw: ");
    for (k = 0; k < dbg_n; k = k + 1) $write("%c", dbg_b[k]);
    $write("\n");
    $write("[TB] UART hex: ");
    for (k = 0; k < dbg_n; k = k + 1) $write("%02x", dbg_b[k]);
    $write("\n");
    $display("PERF cyc=%0d retired=%0d ar=%0d aw=%0d ame_busy=%0d mac=%0d macs=%0d dma_busy=%0d kv_busy=%0d cpu_bus=%0d",
             cyc, perf_retired, perf_ar, perf_aw, perf_ame_busy, perf_mac,
             perf_mac * amechip_pkg::AME_N_DEF, perf_dma_busy, perf_kv_busy, perf_cpu_bus);
    $display("P3B FAIL timeout");
    $finish;
  end

  initial begin
    if ($test$plusargs("WAVE")) begin
      $dumpfile("tb_cpu_ame.vcd");
      $dumpvars(0, tb_cpu_ame);
    end
  end

endmodule
