`timescale 1ns/1ps
`include "amechip_pkg.sv"

module verify_memc_repro;

  logic clk = 1'b0;
  logic rst_n;
  always #5 clk = ~clk;

  logic        aw_valid, aw_ready; logic [31:0] aw_addr;
  logic        w_valid, w_ready;   logic [31:0] w_data; logic [3:0] w_strb;
  logic        b_valid, b_ready;   logic [1:0]  b_resp;
  logic        ar_valid, ar_ready; logic [31:0] ar_addr;
  logic        r_valid, r_ready;   logic [31:0] r_data; logic [1:0] r_resp;

  logic          xclk;
  logic [22:0]   xa;
  logic [15:0]   xdi, xdo;
  logic          xce, xoe, xwe;

  memc_xmem u_memc (
    .clk_i(clk), .rst_ni(rst_n),
    .aw_valid_i(aw_valid), .aw_ready_o(aw_ready), .aw_addr_i(aw_addr),
    .w_valid_i(w_valid), .w_ready_o(w_ready), .w_data_i(w_data),
    .w_strb_i(w_strb),
    .b_valid_o(b_valid), .b_ready_i(b_ready), .b_resp_o(b_resp),
    .ar_valid_i(ar_valid), .ar_ready_o(ar_ready), .ar_addr_i(ar_addr),
    .r_valid_o(r_valid), .r_ready_i(r_ready), .r_data_o(r_data),
    .r_resp_o(r_resp),
    .xmem_clk_o(xclk), .xmem_a_o(xa), .xmem_di_i(xdi), .xmem_do_o(xdo),
    .xmem_ce_no(xce), .xmem_oe_no(xoe), .xmem_we_no(xwe),
    .xmem_wait_i(1'b0)
  );

  verify_psram u_psram (
    .clk_i(clk), .a_i(xa), .di_i(xdo), .do_o(xdi),
    .ce_ni(xce), .oe_ni(xoe), .we_ni(xwe)
  );

  localparam logic [31:0] C1 = 32'h0000_0100;
  localparam logic [31:0] C2 = 32'h0000_0200;
  localparam logic [31:0] C3 = 32'h0000_0300;
  localparam logic [31:0] A  = 32'h0000_0400;
  localparam logic [31:0] B  = 32'h0000_0500;

  localparam logic [31:0] V_C1 = 32'h1111_2222;
  localparam logic [31:0] V_C2 = 32'h3333_4444;
  localparam logic [31:0] V_C3 = 32'h5555_6666;
  localparam logic [31:0] V_A  = 32'h7777_8888;
  localparam logic [31:0] V_B  = 32'h9999_AAAA;

  int          rcv_n;
  logic [31:0] rcv [0:7];
  always @(posedge clk) begin
    if (rst_n && r_valid && r_ready) begin
      rcv[rcv_n] = r_data;
      rcv_n = rcv_n + 1;
    end
  end
  assign r_ready = 1'b1;

  task automatic issue_read(input logic [31:0] addr);
    begin
      @(negedge clk);
      ar_valid = 1'b1; ar_addr = addr;
      @(posedge clk);
      while (!ar_ready) @(posedge clk);
      @(negedge clk);
      ar_valid = 1'b0;
    end
  endtask

  task automatic wait_rcv(input int n, input int timeout_cyc);
    int g;
    begin
      g = 0;
      while (rcv_n < n && g < timeout_cyc) begin
        @(posedge clk);
        g = g + 1;
      end
      if (rcv_n < n) $display("[repro] 超时: 只收到 %0d 笔 R(期望 %0d)", rcv_n, n);
    end
  endtask

  initial begin
    rst_n = 1'b0;
    aw_valid = 0; w_valid = 0; b_ready = 1; ar_valid = 0;
    aw_addr = '0; w_data = '0; w_strb = '0; ar_addr = '0;
    rcv_n = 0;

    u_psram.poke_addr(C1, V_C1);
    u_psram.poke_addr(C2, V_C2);
    u_psram.poke_addr(C3, V_C3);
    u_psram.poke_addr(A,  V_A);
    u_psram.poke_addr(B,  V_B);

    repeat (5) @(posedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);

    issue_read(C1); wait_rcv(1, 1000);
    issue_read(C2); wait_rcv(2, 1000);
    issue_read(C3); wait_rcv(3, 1000);
    $display("[repro] C1=%08h (exp %08h) C2=%08h C3=%08h",
             rcv[0], V_C1, rcv[1], rcv[2]);

    issue_read(A);

    begin : push_b
      int g;
      g = 0;
      while (g < 1000) begin
        @(negedge clk);
        if (u_memc.st_q == 3'd6) begin // S_RV
          ar_valid = 1'b1; ar_addr = B;
          @(posedge clk);            // 同一沿:pop A + push B
          @(negedge clk);
          ar_valid = 1'b0;
          $display("[repro] 已在 S_RV 拍推入读 B(槽 0 旧值 = C1=%08h)", C1);
          disable push_b;
        end
        g = g + 1;
      end
      $display("[repro] 未命中 S_RV 窗口");
    end

    wait_rcv(5, 2000);

    $display("[repro] A got=%08h exp=%08h", rcv[3], V_A);
    $display("[repro] B got=%08h exp=%08h", rcv[4], V_B);
    if (rcv[4] === V_B) begin
      $display("BUG NOT REPRODUCED (B 正确)");
    end else begin
      $display("EXPECTED (B) = %08h", V_B);
      $display("ACTUAL   (B) = %08h", rcv[4]);
      if ((rcv[4][15:0] === V_C1[15:0]) && (rcv[4][31:16] === V_B[31:16]))
        $display("BUG REPRODUCED: 低半字来自陈旧槽 C1 (prefetch stale slot)");
      else
        $display("BUG REPRODUCED(形态: 低半字错误/高半字正确)");
    end
    $finish;
  end

  initial begin
    #2_000_000;
    $display("[repro] 超时退出");
    $finish;
  end

endmodule
