`ifndef _AMECHIP_PKG_SV
 `include "amechip_pkg.sv"
`endif
`include "ame_coproc_if.sv"
`include "ame_dma_if.sv"

`ifndef AME_TB_M
 `define AME_TB_M amechip_pkg::AME_M_DEF
`endif
`ifndef AME_TB_N
 `define AME_TB_N amechip_pkg::AME_N_DEF
`endif

module tb_ame_golden;

  import amechip_pkg::*;

  localparam int unsigned M_PARAM = `AME_TB_M;
  localparam int unsigned N_PARAM = `AME_TB_N;

  logic clk = 1'b0;
  logic rst_ni = 1'b0;
  always #5 clk = ~clk;

  ame_coproc_if u_cp (.clk(clk), .rst_n(rst_ni));
  ame_dma_if     u_bus(.clk(clk), .rst_n(rst_ni));

  logic irq_done, irq_err;
  logic dbg_mac_en, dbg_idle;

  ame_core #(
    .AME_M(M_PARAM),
    .AME_N(N_PARAM)
  ) dut (
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

  integer checks    = 0;
  integer fails     = 0;
  integer ops_done  = 0;
  integer mac_cycles  = 0;
  integer busy_cycles = 0;
  integer total_cycles = 0;
  integer op_idx     = 0;

  always @(posedge clk) begin
    if (rst_ni) begin
      total_cycles <= total_cycles + 1;
      if (dbg_mac_en) mac_cycles  <= mac_cycles + 1;
      if (!dbg_idle)  busy_cycles <= busy_cycles + 1;
    end
  end

  reg [15:0] lfsr = 16'hACE1;
  function [15:0] lfsr_next;
    begin
      lfsr_next = {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
      lfsr      = lfsr_next;
    end
  endfunction

  reg [8*128-1:0] case_name;
  reg [8*32-1:0]  what_s;
  task report_mismatch(input [8*32-1:0] what, input [31:0] exp, input [31:0] act);
    begin
      fails = fails + 1;
      if (fails <= 10)
        $display("MISMATCH %0s op#%0d %0s exp=%08h act=%08h",
                 case_name, op_idx, what, exp, act);
    end
  endtask

  task cp_op(input [31:0] instr, rs1, rs2, exp_data, input exp_err);
    integer stall;
    reg     is_stq;
    begin
      repeat (lfsr_next() % 3) @(posedge clk);
      @(negedge clk);
      u_cp.req_valid <= 1'b1;
      u_cp.req_instr <= instr;
      u_cp.req_rs1   <= rs1;
      u_cp.req_rs2   <= rs2;
      is_stq = (instr[14:12] == 3'h6) && (instr[31:25] == 7'h07) && !exp_err;
      @(negedge clk);
      if (op_idx == 92)
        $display("DBG92 poll1 t=%0t resp=%b ready=%b | stq=%b", $time,
                 u_cp.resp_valid, u_cp.req_ready, is_stq);
      if (op_idx == 1)
        $display("DBG1 poll1 t=%0t resp=%b ready=%b valid=%b instr=%h", $time,
                 u_cp.resp_valid, u_cp.req_ready, u_cp.req_valid, instr);
      if (is_stq) begin
        u_cp.req_valid <= 1'b0;
        checks = checks + 1;
        if (u_cp.resp_valid !== 1'b0)
          report_mismatch("resp_valid_stq_w1", 32'h0, {31'b0, u_cp.resp_valid});
        @(negedge clk);
        checks = checks + 1;
        if (u_cp.resp_valid !== 1'b0)
          report_mismatch("resp_valid_stq_w2", 32'h0, {31'b0, u_cp.resp_valid});
        @(negedge clk);
        checks = checks + 1;
        if (u_cp.resp_valid !== 1'b1)
          report_mismatch("resp_valid", 32'h1, {31'b0, u_cp.resp_valid});
        if (u_cp.resp_data !== exp_data)
          report_mismatch("resp_data", exp_data, u_cp.resp_data);
        if (u_cp.resp_err !== exp_err)
          report_mismatch("resp_err", {31'b0, exp_err}, {31'b0, u_cp.resp_err});
        @(negedge clk);
        checks = checks + 1;
        if (u_cp.resp_valid !== 1'b0)
          report_mismatch("resp_valid_pulse", 32'h0, {31'b0, u_cp.resp_valid});
      end else if (u_cp.resp_valid === 1'b1) begin
        u_cp.req_valid <= 1'b0;
        checks = checks + 1;
        if (u_cp.resp_data !== exp_data)
          report_mismatch("resp_data", exp_data, u_cp.resp_data);
        if (u_cp.resp_err !== exp_err)
          report_mismatch("resp_err", {31'b0, exp_err}, {31'b0, u_cp.resp_err});
        @(negedge clk);
        checks = checks + 1;
        if (u_cp.resp_valid !== 1'b0)
          report_mismatch("resp_valid_pulse", 32'h0, {31'b0, u_cp.resp_valid});
      end else begin
        stall = 0;
        while ((u_cp.req_ready !== 1'b1) && stall < 200000) begin
          stall = stall + 1;
          @(negedge clk);
        end
        if (stall >= 200000) begin
          u_cp.req_valid <= 1'b0;
          $display("TIMEOUT %0s op#%0d cp 反压超时", case_name, op_idx);
          fails = fails + 1;
        end else begin
          @(negedge clk);
          u_cp.req_valid <= 1'b0;
          checks = checks + 1;
          if (u_cp.resp_valid !== 1'b1)
            report_mismatch("resp_valid", 32'h1, {31'b0, u_cp.resp_valid});
          if (u_cp.resp_data !== exp_data)
            report_mismatch("resp_data", exp_data, u_cp.resp_data);
          if (u_cp.resp_err !== exp_err)
            report_mismatch("resp_err", {31'b0, exp_err}, {31'b0, u_cp.resp_err});
          @(negedge clk);
          checks = checks + 1;
          if (u_cp.resp_valid !== 1'b0)
            report_mismatch("resp_valid_pulse", 32'h0, {31'b0, u_cp.resp_valid});
        end
      end
    end
  endtask

  task bus_wr(input [31:0] addr, data, input [3:0] wstrb, input exp_err);
    begin
      repeat (lfsr_next() % 2) @(posedge clk);
      @(negedge clk);
      u_bus.req_valid <= 1'b1;
      u_bus.req_write <= 1'b1;
      u_bus.req_addr  <= addr;
      u_bus.req_wdata <= data;
      u_bus.req_wstrb <= wstrb;
      @(negedge clk);
      u_bus.req_valid <= 1'b0;
      checks = checks + 1;
      if (u_bus.resp_valid !== 1'b1)
        report_mismatch("bus_resp_valid", 32'h1, {31'b0, u_bus.resp_valid});
      if (u_bus.resp_err !== exp_err)
        report_mismatch("bus_wr_err", {31'b0, exp_err}, {31'b0, u_bus.resp_err});
      @(negedge clk);
      checks = checks + 1;
      if (u_bus.resp_valid !== 1'b0)
        report_mismatch("bus_resp_pulse", 32'h0, {31'b0, u_bus.resp_valid});
    end
  endtask

  task bus_rd(input [31:0] addr, input [31:0] exp_data, input exp_err);
    begin
      repeat (lfsr_next() % 2) @(posedge clk);
      @(negedge clk);
      u_bus.req_valid <= 1'b1;
      u_bus.req_write <= 1'b0;
      u_bus.req_addr  <= addr;
      u_bus.req_wdata <= 32'h0;
      u_bus.req_wstrb <= 4'h0;
      @(negedge clk);
      u_bus.req_valid <= 1'b0;
      if ((addr[11:0] >= 12'h880) && (addr[11:0] < 12'h8A0))
        repeat (2) @(negedge clk);
      @(negedge clk);
      checks = checks + 1;
      if (u_bus.resp_valid !== 1'b1)
        report_mismatch("bus_resp_valid", 32'h1, {31'b0, u_bus.resp_valid});
      if (u_bus.resp_rdata !== exp_data)
        report_mismatch("bus_rd_data", exp_data, u_bus.resp_rdata);
      if (u_bus.resp_err !== exp_err)
        report_mismatch("bus_rd_err", {31'b0, exp_err}, {31'b0, u_bus.resp_err});
      @(negedge clk);
      checks = checks + 1;
      if (u_bus.resp_valid !== 1'b0)
        report_mismatch("bus_resp_pulse", 32'h0, {31'b0, u_bus.resp_valid});
    end
  endtask

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
  end

  initial begin
    #200_000_000;
    $display("GLOBAL TIMEOUT case=%0s", case_name);
    $display("GOLDEN RESULT: FAIL");
    $finish;
  end

  reg [8*256-1:0] line;
  reg [8*128-1:0] ops_file;
  string          line_s;
  integer fd, code;
  reg [31:0] f0, f1, f2, f3, f4, f5;

  initial begin
    if (!$value$plusargs("case=%s", case_name))
      case_name = "unknown";
    if (!$value$plusargs("ops=%s", ops_file)) begin
      $display("缺少 +ops=<file>");
      $display("GOLDEN RESULT: FAIL");
      $finish;
    end
    wait (rst_ni === 1'b1);
    @(posedge clk);

    fd = $fopen(ops_file, "r");
    if (fd == 0) begin
      $display("无法打开 ops 文件: %0s", ops_file);
      $display("GOLDEN RESULT: FAIL");
      $finish;
    end

    while ($fgets(line, fd) != 0) begin
      line_s = $sformatf("%0s", line);
      code = $sscanf(line_s, "%h %h %h %h %h %h", f0, f1, f2, f3, f4, f5);
      if (code == 6) begin
        op_idx    = op_idx + 1;
        ops_done  = ops_done + 1;
        case (f0)
          32'h0: cp_op(f1, f2, f3, f4, f5[0]);
          32'h1: bus_wr(f1, f2, f3[3:0], f4[0]);
          32'h2: bus_rd(f1, f2, f3[0]);
          default: begin
            $display("未知 op 类型 %0h @%0d", f0, op_idx);
            fails = fails + 1;
          end
        endcase
      end
    end
    $fclose(fd);

    if (ops_done == 0) begin
      $display("GOLDEN RESULT: FAIL (ops=0:回放空转,检查解析/文件)");
      $finish;
    end

    $display("PERF case=%0s ops=%0d checks=%0d fail=%0d mac_cycles=%0d busy_cycles=%0d total_cycles=%0d",
             case_name, ops_done, checks, fails, mac_cycles, busy_cycles,
             total_cycles);
    if (fails == 0)
      $display("GOLDEN RESULT: PASS");
    else
      $display("GOLDEN RESULT: FAIL");
    $finish;
  end

endmodule
