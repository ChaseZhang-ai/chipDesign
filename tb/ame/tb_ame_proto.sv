`ifndef _AMECHIP_PKG_SV
 `include "amechip_pkg.sv"
`endif
`include "ame_coproc_if.sv"
`include "ame_dma_if.sv"

module tb_ame_proto;

  import amechip_pkg::*;

  logic clk = 1'b0;
  logic rst_ni = 1'b0;
  always #5 clk = ~clk;

  ame_coproc_if u_cp (.clk(clk), .rst_n(rst_ni));
  ame_dma_if     u_bus(.clk(clk), .rst_n(rst_ni));

  logic irq_done, irq_err, dbg_mac_en, dbg_idle;

  ame_core dut (
    .clk_i          (clk),
    .rst_ni         (rst_ni),
    .cp_req_valid_i (u_cp.req_valid),
    .cp_req_instr_i (u_cp.req_instr),
    .cp_req_rs1_i   (u_cp.req_rs1),
    .cp_req_rs2_i   (u_cp.req_rs2),
    .cp_req_ready_o (u_cp.req_ready),
    .cp_resp_valid_o(u_cp.resp_valid),
    .cp_resp_data_o (u_cp.resp_data),
    .cp_resp_err_o  (u_cp.resp_err),
    .bus_req_valid_i(u_bus.req_valid),
    .bus_req_write_i(u_bus.req_write),
    .bus_req_addr_i (u_bus.req_addr),
    .bus_req_wdata_i(u_bus.req_wdata),
    .bus_req_wstrb_i(u_bus.req_wstrb),
    .bus_req_ready_o(u_bus.req_ready),
    .bus_resp_valid_o(u_bus.resp_valid),
    .bus_resp_rdata_o(u_bus.resp_rdata),
    .bus_resp_err_o (u_bus.resp_err),
    .irq_done_o     (irq_done),
    .irq_err_o      (irq_err),
    .dbg_mac_en_o   (dbg_mac_en),
    .dbg_idle_o     (dbg_idle)
  );

  integer fails = 0;
  integer t, kt;

  task fail_check(input [8*64-1:0] name);
    begin
      fails = fails + 1;
      $display("PROTO-FAIL %0s (t=%0t)", name, $time);
    end
  endtask

  reg [31:0] st_data;
  reg        st_err;
  integer    st_stall;
  reg        hung;

  task cp_op(input [31:0] instr, rs1, rs2);
    begin
      hung = 1'b0;
      @(negedge clk);
      u_cp.req_valid <= 1'b1;
      u_cp.req_instr <= instr;
      u_cp.req_rs1   <= rs1;
      u_cp.req_rs2   <= rs2;
      st_stall = 0;
      @(posedge clk);
      while (!(u_cp.req_valid === 1'b1 && u_cp.req_ready === 1'b1) &&
             st_stall < 100000) begin
        st_stall = st_stall + 1;
        @(posedge clk);
      end
      if (st_stall >= 100000) begin
        hung = 1'b1;
        $display("DEADLOCK instr=%h rs1=%h t=%0t", instr, rs1, $time);
        fail_check("cp_deadlock");
      end
      u_cp.req_valid <= 1'b0;
      @(posedge clk);
      if (u_cp.resp_valid !== 1'b1) fail_check("resp_not_plus1");
      st_data = u_cp.resp_data;
      st_err  = u_cp.resp_err;
      @(posedge clk);
      if (u_cp.resp_valid !== 1'b0) fail_check("resp_not_single");
    end
  endtask

  reg [31:0] bus_rdata_last;
  reg        bus_err_last;

  task bus_wr(input [31:0] addr, data, input [3:0] wstrb);
    begin
      @(negedge clk);
      u_bus.req_valid <= 1'b1;
      u_bus.req_write <= 1'b1;
      u_bus.req_addr  <= addr;
      u_bus.req_wdata <= data;
      u_bus.req_wstrb <= wstrb;
      @(posedge clk);
      u_bus.req_valid <= 1'b0;
      @(posedge clk);
      bus_err_last   = u_bus.resp_err;
      bus_rdata_last = u_bus.resp_rdata;
      @(posedge clk);
    end
  endtask

  task bus_rd(input [31:0] addr);
    begin
      @(negedge clk);
      u_bus.req_valid <= 1'b1;
      u_bus.req_write <= 1'b0;
      u_bus.req_addr  <= addr;
      @(posedge clk);
      u_bus.req_valid <= 1'b0;
      @(posedge clk);
      @(posedge clk);
      bus_rdata_last = u_bus.resp_rdata;
      bus_err_last   = u_bus.resp_err;
      @(posedge clk);
    end
  endtask

  localparam logic [31:0] BASE    = 32'h2000_1000;
  localparam logic [31:0] CP_CFG  = 32'h2100_000B;                        // cfg 16,16
  localparam logic [31:0] CP_LDW  = (7'h02 << 25) | (3'h2 << 12) | 32'h0B;
  localparam logic [31:0] CP_LDX  = (7'h03 << 25) | (3'h3 << 12) | 32'h0B;
  localparam logic [31:0] CP_EXEF = 32'h0A00_400B;
  localparam logic [31:0] CP_EXE  = 32'h0800_400B;
  localparam logic [31:0] CP_SYNC = (7'h08 << 25) | (3'h7 << 12) | 32'h0B;

  integer m_busy, m_mac;
  task exe_and_measure(input [31:0] instr);
    begin
      @(negedge clk);
      u_cp.req_valid <= 1'b1;
      u_cp.req_instr <= instr;
      u_cp.req_rs1   <= 32'h0;
      u_cp.req_rs2   <= 32'h0;
      @(posedge clk);
      while (!(u_cp.req_valid === 1'b1 && u_cp.req_ready === 1'b1))
        @(posedge clk);
      u_cp.req_valid <= 1'b0;
      m_busy = 0;
      m_mac  = 0;
      @(posedge clk);
      while (dbg_idle === 1'b0) begin
        if (dbg_mac_en) m_mac = m_mac + 1;
        m_busy = m_busy + 1;
        @(posedge clk);
      end
    end
  endtask

  integer ld_cycles, gap, accept0_t, accept1_t;
  integer sum_mac, sum_busy;

  initial begin
    u_cp.req_valid  = 1'b0;
    u_cp.req_instr  = 32'h0;
    u_cp.req_rs1    = 32'h0;
    u_cp.req_rs2    = 32'h0;
    u_bus.req_valid = 1'b0;
    u_bus.req_write = 1'b0;
    u_bus.req_addr  = 32'h0;
    u_bus.req_wdata = 32'h0;
    u_bus.req_wstrb = 4'h0;
    repeat (8) @(posedge clk);
    rst_ni = 1'b1;
    @(posedge clk);
    kt = 16;

    $display("SECTION T1 复位状态");
    bus_rd(BASE + 32'h08C0);
    if (bus_rdata_last !== 32'h0) fail_check("T1_status_reset");
    cp_op((6'h05 << 25) | (3'h4 << 12) | 32'h0B, 32'h2, 0); // rs1[1]=1 非法
    if (st_err !== 1'b1 || hung) fail_check("T1_badfield_exe_err");

    $display("SECTION T2 cfg/qcfg");
    cp_op(CP_CFG, 0, 0);
    if (st_err !== 1'b0) fail_check("T2_cfg_err");
    cp_op((7'h01 << 25) | (3'h1 << 12) | 32'h0B, 32'h0001_0000, 6'd16);
    for (t = 0; t < 64; t = t + 1)
      bus_wr(BASE + t*4, 32'h0101_0101, 4'hF);
    for (t = 0; t < 4; t = t + 1)
      bus_wr(BASE + 32'h0400 + t*4, 32'h0101_0101, 4'hF);

    $display("SECTION T9 ld.w");
    cp_op(CP_LDW, 5'd0, 0);
    ld_cycles = 0;
    bus_rd(BASE + 32'h08C0);
    if (bus_rdata_last[2] !== 1'b0) fail_check("T9_w0rdy_during_load");
    while (bus_rdata_last[2] !== 1'b1 && ld_cycles < 100) begin
      bus_rd(BASE + 32'h08C0);
      ld_cycles = ld_cycles + 1;
    end
    if (ld_cycles > 16) fail_check("T9_ldw_too_long");
    cp_op(CP_LDX, 0, 0);

    $display("SECTION T3 BUSY");
    exe_and_measure(CP_EXEF);
    if (m_busy !== kt + 2) fail_check("T3_busy_len");
    if (m_mac  !== kt)     fail_check("T3_mac_len");

    $display("SECTION T4 sync");
    cp_op(CP_LDW, 5'd1, 0);      // 重装 g0
    cp_op(CP_LDX, 0, 0);
    @(negedge clk);
    u_cp.req_valid <= 1'b1;
    u_cp.req_instr <= CP_EXEF;
    @(posedge clk);
    while (!(u_cp.req_valid === 1'b1 && u_cp.req_ready === 1'b1)) @(posedge clk);
    u_cp.req_valid <= 1'b0;
    @(negedge clk);
    u_cp.req_valid <= 1'b1;
    u_cp.req_instr <= CP_SYNC;
    t = 0;
    @(posedge clk);
    while (!(u_cp.req_valid === 1'b1 && u_cp.req_ready === 1'b1) && t < 1000) begin
      if (dbg_idle !== 1'b0) fail_check("T4_sync_stall_state");
      t = t + 1;
      @(posedge clk);
    end
    if (t < kt) fail_check("T4_sync_no_backpressure");
    u_cp.req_valid <= 1'b0;
    @(posedge clk);
    if (u_cp.resp_valid !== 1'b1) fail_check("T4_sync_resp");
    if (dbg_idle !== 1'b1) fail_check("T4_busy_after_sync");

    $display("SECTION T6 cfg");
    cp_op(CP_LDW, 5'd1, 0);
    cp_op(CP_LDX, 0, 0);
    @(negedge clk);
    u_cp.req_valid <= 1'b1;
    u_cp.req_instr <= CP_EXEF;
    u_cp.req_rs1   <= 32'h0;
    u_cp.req_rs2   <= 32'h0;
    @(posedge clk);
    while (!(u_cp.req_valid === 1'b1 && u_cp.req_ready === 1'b1)) @(posedge clk);
    u_cp.req_valid <= 1'b0;
    @(negedge clk);
    u_cp.req_valid <= 1'b1;
    u_cp.req_instr <= CP_CFG;
    u_cp.req_rs1   <= 32'h0;
    u_cp.req_rs2   <= 32'h0;
    t = 0;
    @(posedge clk);
    while (!(u_cp.req_valid === 1'b1 && u_cp.req_ready === 1'b1) && t < 1000) begin
      t = t + 1;
      @(posedge clk);
    end
    if (t < kt) fail_check("T6_cfg_no_backpressure");
    u_cp.req_valid <= 1'b0;
    @(posedge clk);
    @(posedge clk);

    $display("SECTION T5 背靠背");
    cp_op(CP_LDW, 5'd0, 0);
    cp_op(CP_LDX, 0, 0);
    cp_op(CP_LDW, 5'd1 | (1 << 2), 0);
    cp_op(CP_LDX, 5'd16 | (1 << 9), 0);
    @(negedge clk);
    u_cp.req_valid <= 1'b1;
    u_cp.req_instr <= CP_EXEF;    // exef g0
    u_cp.req_rs1   <= 32'h0;
    u_cp.req_rs2   <= 32'h0;
    @(posedge clk);
    t = 0;
    while (!(u_cp.req_valid === 1'b1 && u_cp.req_ready === 1'b1) && t < 200) begin
      t = t + 1;
      @(posedge clk);
    end
    if (t >= 200) begin
      $display("T5 exef g0 stall: idle=%b wld=%b xld=%b tset0=%0d xset0=%0d tset1=%0d xset1=%0d cfg_n=%0d cfg_kt=%0d",
        dut.dbg_idle_o, dut.u_ctrl.wld_active_q, dut.u_ctrl.xld_active_q,
        dut.u_ctrl.tset_q[0], dut.u_ctrl.xset_q[0],
        dut.u_ctrl.tset_q[1], dut.u_ctrl.xset_q[1],
        dut.u_ctrl.cfg_n_eff_q, dut.u_ctrl.cfg_kt_q);
      fail_check("T5_exef_stall");
    end
    accept0_t = $time;
    u_cp.req_valid <= 1'b0;
    @(negedge clk);
    u_cp.req_valid <= 1'b1;
    u_cp.req_instr <= CP_EXE;     // exe g1:应恰在 BUSY 下降后接受
    u_cp.req_rs1   <= 32'h1;      // tsel=1
    u_cp.req_rs2   <= 32'h0;
    @(posedge clk);
    t = 0;
    while (!(u_cp.req_valid === 1'b1 && u_cp.req_ready === 1'b1) && t < 200) begin
      t = t + 1;
      @(posedge clk);
    end
    if (t >= 200) begin
      $display("T5 exe g1 stall: idle=%b tset1=%0d xset1=%0d",
        dut.dbg_idle_o, dut.u_ctrl.tset_q[1], dut.u_ctrl.xset_q[1]);
      fail_check("T5_exe_stall");
    end
    accept1_t = $time;
    u_cp.req_valid <= 1'b0;
    gap = (accept1_t - accept0_t) / 10;
    $display("T5 gap=%0d (期望 %0d = KT+3)", gap, kt + 3);
    $display("  dbg: t=%0t idle=%b macbusy=%b tset0=%0d xset0=%0d tset1=%0d xset1=%0d",
      $time, dut.dbg_idle_o, dut.u_ctrl.mac_busy_q, dut.u_ctrl.tset_q[0], dut.u_ctrl.xset_q[0],
      dut.u_ctrl.tset_q[1], dut.u_ctrl.xset_q[1]);
    if (gap !== kt + 3) fail_check("T5_b2b_gap");
    @(posedge clk);

    $display("SECTION T8 吞吐");
    sum_mac  = 0;
    sum_busy = 0;
    for (t = 0; t < 8; t = t + 1) begin
      cp_op(CP_LDW, 5'd0, 0);
      cp_op(CP_LDX, 0, 0);
      exe_and_measure(CP_EXEF);
      sum_mac  = sum_mac  + m_mac;
      sum_busy = sum_busy + m_busy;
    end
    $display("PERF-EXE exe_count=8 kt=%0d mac_cycles=%0d busy_cycles=%0d duty=%0d/1000 mac_rate_during_mac=%0d MAC/cycle (AME_N=%0d)",
             kt, sum_mac, sum_busy,
             (sum_mac * 1000) / sum_busy, 16, 16);
    if (sum_mac  !== 8 * kt)     fail_check("T8_mac_total");
    if (sum_busy !== 8 * (kt+2)) fail_check("T8_busy_total");

    $display("SECTION T7 DONE");
    bus_rd(BASE + 32'h08C0);
    if (bus_rdata_last[1] !== 1'b1) fail_check("T7_done_flag");
    if (irq_done !== 1'b0) fail_check("T7_irqen_default_off");
    bus_wr(BASE + 32'h08C4, 32'h1, 4'hF);
    if (irq_done !== 1'b1) fail_check("T7_irq_done_level");
    bus_wr(BASE + 32'h08C8, 32'h1, 4'hF);
    if (irq_done !== 1'b0) fail_check("T7_evclear_done");
    bus_wr(BASE + 32'h0880, 32'h0, 4'hF);   // YQ 写 → SLVERR(裁决 A 后经总线可达)
    if (bus_err_last !== 1'b1) fail_check("T7_yq_wr_slverr");
    bus_rd(BASE + 32'h08C0);
    if (bus_rdata_last[7] !== 1'b1) fail_check("T7_err_sticky");
    bus_wr(BASE + 32'h08C4, 32'h2, 4'hF);
    if (irq_err !== 1'b1) fail_check("T7_irq_err_level");
    bus_wr(BASE + 32'h08C8, 32'h2, 4'hF);
    if (irq_err !== 1'b0) fail_check("T7_evclear_err");

    if (fails == 0) $display("PROTO RESULT: PASS");
    else            $display("PROTO RESULT: FAIL");
    $finish;
  end

  initial begin
    #50_000_000;
    $display("PROTO TIMEOUT");
    $display("PROTO RESULT: FAIL");
    $finish;
  end

endmodule
