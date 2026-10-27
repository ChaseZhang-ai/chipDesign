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

module tb_verify_full;

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
  integer dumped    = 0;
  integer cnt_mac   = 0;
  integer cnt_busy  = 0;
  integer cnt_idle  = 0;
  integer op_idx    = 0;

  always @(negedge clk) begin
    if (rst_ni) begin
      if (dbg_mac_en) cnt_mac  = cnt_mac  + 1;
      if (!dbg_idle)  cnt_busy = cnt_busy + 1;
      if (dbg_idle)   cnt_idle = cnt_idle + 1;
    end
  end

  string case_name;
  string gid_name;
  integer dump_fd;

  task report_mismatch(input [8*40-1:0] what, input [31:0] exp, input [31:0] act);
    begin
      fails = fails + 1;
      if (fails <= 20)
        $display("MISMATCH %0s %0s op#%0d %0s exp=%08h act=%08h",
                 case_name, gid_name, op_idx, what, exp, act);
    end
  endtask

  reg tight = 1'b0;
  reg [15:0] lfsr = 16'hC3A5;
  function [15:0] lfsr_next;
    begin
      lfsr_next = {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
      lfsr      = lfsr_next;
    end
  endfunction

  reg [31:0] rd_data;
  reg        rd_err;

  task cp_op_c(input [31:0] instr, rs1, rs2,
               input chk_data, input [31:0] exp_data,
               input chk_err, input exp_err);
    integer stall;
    reg accepted;
    begin
      if (!tight) repeat (lfsr_next() % 3) @(negedge clk);
      @(negedge clk);
      u_cp.req_valid = 1'b1;
      u_cp.req_instr = instr;
      u_cp.req_rs1   = rs1;
      u_cp.req_rs2   = rs2;
      accepted = 1'b0;
      if ((instr[14:12] == 3'h6) && (instr[31:25] == 7'h07) && chk_err && !exp_err) begin
        @(negedge clk);
        u_cp.req_valid = 1'b0;
        checks = checks + 1;
        if (u_cp.resp_valid !== 1'b0)
          report_mismatch("resp_valid_stq_w1", 32'h0, {31'b0, u_cp.resp_valid});
        @(negedge clk);
        checks = checks + 1;
        if (u_cp.resp_valid !== 1'b0)
          report_mismatch("resp_valid_stq_w2", 32'h0, {31'b0, u_cp.resp_valid});
        @(negedge clk);
        accepted = 1'b1;
        checks = checks + 1;
        rd_data = u_cp.resp_data;
        rd_err  = u_cp.resp_err;
        if (u_cp.resp_valid !== 1'b1)
          report_mismatch("resp_valid", 32'h1, {31'b0, u_cp.resp_valid});
        if (chk_data && (u_cp.resp_data !== exp_data))
          report_mismatch("resp_data", exp_data, u_cp.resp_data);
        if (chk_err && (u_cp.resp_err !== exp_err))
          report_mismatch("resp_err", {31'b0, exp_err}, {31'b0, u_cp.resp_err});
        @(negedge clk);
        checks = checks + 1;
        if (u_cp.resp_valid !== 1'b0)
          report_mismatch("resp_pulse", 32'h0, {31'b0, u_cp.resp_valid});
      end else begin
      @(negedge clk);
      if (u_cp.resp_valid === 1'b1) begin
        accepted = 1'b1;
      end else begin
        stall = 0;
        while ((u_cp.req_ready !== 1'b1) && stall < 500000) begin
          @(negedge clk);
          stall = stall + 1;
        end
        if (stall < 500000) begin
          accepted = 1'b1;
          @(negedge clk);
        end
      end
      u_cp.req_valid = 1'b0;
      if (!accepted) begin
        $display("TIMEOUT %0s %0s op#%0d cp 反压超时 instr=%08h",
                 case_name, gid_name, op_idx, instr);
        fails = fails + 1;
      end else begin
        checks = checks + 1;
        rd_data = u_cp.resp_data;
        rd_err  = u_cp.resp_err;
        if (u_cp.resp_valid !== 1'b1)
          report_mismatch("resp_valid", 32'h1, {31'b0, u_cp.resp_valid});
        if (chk_data && (u_cp.resp_data !== exp_data))
          report_mismatch("resp_data", exp_data, u_cp.resp_data);
        if (chk_err && (u_cp.resp_err !== exp_err))
          report_mismatch("resp_err", {31'b0, exp_err}, {31'b0, u_cp.resp_err});
        @(negedge clk);
        checks = checks + 1;
        if (u_cp.resp_valid !== 1'b0)
          report_mismatch("resp_pulse", 32'h0, {31'b0, u_cp.resp_valid});
      end
      end
    end
  endtask

  task cp_op(input [31:0] instr, rs1, rs2);
    begin
      cp_op_c(instr, rs1, rs2, 1'b0, 32'h0, 1'b1, 1'b0);
    end
  endtask

  task bus_wr(input [31:0] addr, data, input [3:0] wstrb, input exp_err);
    begin
      if (!tight) repeat (lfsr_next() % 2) @(negedge clk);
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

  reg [31:0] bus_rdata;
  reg        bus_rerr;

  task bus_rd_c(input [31:0] addr, input chk, input [31:0] exp_data, input exp_err);
    begin
      if (!tight) repeat (lfsr_next() % 2) @(negedge clk);
      @(negedge clk);
      u_bus.req_valid <= 1'b1;
      u_bus.req_write <= 1'b0;
      u_bus.req_addr  <= addr;
      u_bus.req_wdata <= 32'h0;
      u_bus.req_wstrb <= 4'h0;
      @(negedge clk);            // T+1.5
      u_bus.req_valid <= 1'b0;
      if ((addr[11:0] >= 12'h880) && (addr[11:0] < 12'h8A0))
        repeat (2) @(negedge clk);
      @(negedge clk);
      checks = checks + 1;
      bus_rdata = u_bus.resp_rdata;
      bus_rerr  = u_bus.resp_err;
      if (u_bus.resp_valid !== 1'b1)
        report_mismatch("bus_resp_valid", 32'h1, {31'b0, u_bus.resp_valid});
      if (chk) begin
        if (u_bus.resp_rdata !== exp_data)
          report_mismatch("bus_rd_data", exp_data, u_bus.resp_rdata);
        if (u_bus.resp_err !== exp_err)
          report_mismatch("bus_rd_err", {31'b0, exp_err}, {31'b0, u_bus.resp_err});
      end
      @(negedge clk);
      checks = checks + 1;
      if (u_bus.resp_valid !== 1'b0)
        report_mismatch("bus_resp_pulse", 32'h0, {31'b0, u_bus.resp_valid});
    end
  endtask

  task bus_rd(input [31:0] addr, input [31:0] exp_data, input exp_err);
    begin
      bus_rd_c(addr, 1'b1, exp_data, exp_err);
    end
  endtask

  task dump_read(input f, input [31:0] li, input [31:0] gn, input chk, input [31:0] exp);
    reg [31:0] enc;
    reg [31:0] d;
    begin
      if (f == 32'd0) enc = (7'h06 << 25) | (3'h5 << 12) | 32'h0B; // st.y
      else            enc = (7'h07 << 25) | (3'h6 << 12) | 32'h0B; // st.q
      cp_op_c(enc, li, 32'h0, chk, exp, 1'b1, 1'b0);
      d = rd_data;
      if (dump_fd) begin
        dumped = dumped + 1;
        if (f == 32'd0)
          $fdisplay(dump_fd, "GOLD %0s %0s y_int32 %0d %08x", case_name, gid_name, gn, d);
        else
          $fdisplay(dump_fd, "GOLD %0s %0s y_q8 %0d %02x", case_name, gid_name, gn, d & 32'hFF);
      end
    end
  endtask

  task poll_ready(input [31:0] bitpos, input [31:0] maxc);
    integer n;
    reg [31:0] v;
    begin
      n = 0;
      bus_rd_c(32'h2000_1000 + 32'h08C0, 1'b0, 32'h0, 1'b0);
      v = bus_rdata;
      while ((((v >> bitpos) & 32'h1) !== 32'h1) && n < maxc) begin
        bus_rd_c(32'h2000_1000 + 32'h08C0, 1'b0, 32'h0, 1'b0);
        v = bus_rdata;
        n = n + 1;
      end
      checks = checks + 1;
      if (((v >> bitpos) & 32'h1) !== 32'h1) begin
        report_mismatch("poll_ready_timeout", bitpos, v);
      end
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
    #500_000_000;
    $display("GLOBAL TIMEOUT case=%0s %0s", case_name, gid_name);
    $display("VERIFY RESULT: FAIL");
    $finish;
  end

  reg [8*256-1:0] line_r;
  string line;
  reg [8*128-1:0] ops_file;
  reg [8*128-1:0] dump_file;
  integer fd, code;
  reg [31:0] f0, f1, f2, f3, f4, f5, f6;

  initial begin
    if (!$value$plusargs("case=%s", case_name))
      case_name = "unknown";
    if (!$value$plusargs("gid=%s", gid_name))
      gid_name = "G00";
    if (!$value$plusargs("ops=%s", ops_file)) begin
      $display("缺少 +ops=<file>");
      $display("VERIFY RESULT: FAIL");
      $finish;
    end
    if ($test$plusargs("tight"))
      tight = 1'b1;
    if (!$value$plusargs("dump=%s", dump_file))
      dump_file = "";
    if (dump_file != 0)
      dump_fd = $fopen(dump_file, "w");
    else
      dump_fd = 0;
    wait (rst_ni === 1'b1);
    @(posedge clk);

    fd = $fopen(ops_file, "r");
    if (fd == 0) begin
      $display("无法打开 ops 文件: %0s", ops_file);
      $display("VERIFY RESULT: FAIL");
      $finish;
    end

    while ($fgets(line_r, fd) != 0) begin
      line = $sformatf("%0s", line_r);
      code = $sscanf(line, "%h %h %h %h %h %h %h", f0, f1, f2, f3, f4, f5, f6);
      if (code > 0 && (f0 < 32'hA)) begin
        op_idx   = op_idx + 1;
        ops_done = ops_done + 1;
        case (f0)
          32'h0: cp_op(f1, f2, f3);
          32'h1: bus_wr(f1, f2, f3[3:0], f4[0]);
          32'h2: bus_rd(f1, f2, f3[0]);
          32'h3: cp_op_c(f1, f2, f3, 1'b1, f4, 1'b1, f5[0]);
          32'h4: begin
            if (code >= 5) dump_read(f1, f2, f3, 1'b1, f4);
            else           dump_read(f1, f2, f3, 1'b0, 32'h0);
          end
          32'h5: repeat (f1) @(negedge clk);
          32'h6: poll_ready(f1, f2);
          32'h7: begin
            bus_rd_c(32'h2000_1000 + 32'h08C0, 1'b0, 32'h0, 1'b0);
            checks = checks + 1;
            if ((bus_rdata & f1) !== f2)
              report_mismatch("status_mask", f2, bus_rdata & f1);
          end
          32'h8: bus_rd_c(f1, 1'b0, 32'h0, 1'b0);
          32'h9: begin
            $display("PERF-SNAP case=%0s %0s tag=op#%0d mac=%0d busy=%0d idle=%0d duty=%0d/1000",
                     case_name, gid_name, op_idx, cnt_mac, cnt_busy, cnt_idle,
                     (cnt_busy > 0) ? (cnt_mac * 1000) / cnt_busy : 0);
            cnt_mac  = 0;
            cnt_busy = 0;
            cnt_idle = 0;
          end
          default: begin
            $display("未知 op 类型 %0h @%0d", f0, op_idx);
            fails = fails + 1;
          end
        endcase
      end
    end
    $fclose(fd);
    if (dump_fd != 0)
      $fclose(dump_fd);

    $display("PERF case=%0s %0s ops=%0d checks=%0d dumped=%0d fail=%0d mac=%0d busy=%0d idle=%0d",
             case_name, gid_name, ops_done, checks, dumped, fails,
             cnt_mac, cnt_busy, cnt_idle);
    if (fails == 0)
      $display("VERIFY RESULT: PASS");
    else
      $display("VERIFY RESULT: FAIL");
    $finish;
  end

endmodule
