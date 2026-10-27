
`timescale 1ns/1ps

module tb_smoke_2;

  localparam int    BIT_CYC = 13;
  localparam real   CLKP    = 10.0;
  localparam int    NBOOT   = 17;   // "AME-CHIP BOOT OK\n"
  localparam int    NDEMO   = 49;   // 16 × "xx " + '\n'
  localparam int    NTOTAL  = NBOOT + NDEMO;

  logic       clk = 1'b0;
  logic       rst_ni = 1'b0;
  logic       uart_tx;
  logic       irq;
  logic [3:0] gpio;

  always #(CLKP/2.0) clk = ~clk;

  amechip_top dut (
    .clk_i      (clk),
    .rst_ni     (rst_ni),
    .uart_tx_o  (uart_tx),
    .uart_rx_i  (1'b1),
    .xmem_clk_o (),
    .xmem_a_o   (),
    .xmem_di_i  (16'h0),
    .xmem_do_o  (),
    .xmem_ce_no (),
    .xmem_oe_no (),
    .xmem_we_no (),
    .xmem_wait_i(1'b0),
    .gpio_i     (4'h0),
    .gpio_o     (gpio),
    .irq_o      (irq)
  );

  task automatic recv_byte (output logic [7:0] b);
    integer i;
    begin
      @(negedge uart_tx);
      #(BIT_CYC * CLKP / 2.0);
      if (uart_tx !== 1'b0) $display("[TB] WARN: start bit != 0");
      for (i = 0; i < 8; i++) begin
        #(BIT_CYC * CLKP);
        b[i] = uart_tx;
      end
      #(BIT_CYC * CLKP);
    end
  endtask

  logic [7:0] exp [0:NTOTAL-1];
  logic [7:0] got [0:NTOTAL-1];
  logic [7:0] b;
  integer     k, errs;
  integer     cycle_cnt;

  initial begin
    exp[ 0]=8'h41; exp[ 1]=8'h4D; exp[ 2]=8'h45; exp[ 3]=8'h2D; exp[ 4]=8'h43;
    exp[ 5]=8'h48; exp[ 6]=8'h49; exp[ 7]=8'h50; exp[ 8]=8'h20; exp[ 9]=8'h42;
    exp[10]=8'h4F; exp[11]=8'h4F; exp[12]=8'h54; exp[13]=8'h20; exp[14]=8'h4F;
    exp[15]=8'h4B; exp[16]=8'h0A;
    exp[17]=8'h32; exp[18]=8'h31; exp[19]=8'h20; exp[20]=8'h30; exp[21]=8'h37;
    exp[22]=8'h20; exp[23]=8'h64; exp[24]=8'h66; exp[25]=8'h20; exp[26]=8'h66;
    exp[27]=8'h64; exp[28]=8'h20; exp[29]=8'h30; exp[30]=8'h36; exp[31]=8'h20;
    exp[32]=8'h65; exp[33]=8'h63; exp[34]=8'h20; exp[35]=8'h30; exp[36]=8'h61;
    exp[37]=8'h20; exp[38]=8'h32; exp[39]=8'h31; exp[40]=8'h20; exp[41]=8'h30;
    exp[42]=8'h37; exp[43]=8'h20; exp[44]=8'h64; exp[45]=8'h66; exp[46]=8'h20;
    exp[47]=8'h66; exp[48]=8'h64; exp[49]=8'h20; exp[50]=8'h30; exp[51]=8'h36;
    exp[52]=8'h20; exp[53]=8'h65; exp[54]=8'h63; exp[55]=8'h20; exp[56]=8'h30;
    exp[57]=8'h61; exp[58]=8'h20; exp[59]=8'h32; exp[60]=8'h31; exp[61]=8'h20;
    exp[62]=8'h30; exp[63]=8'h37; exp[64]=8'h20; exp[65]=8'h0A;
  end

  initial begin
    cycle_cnt = 0;
    repeat (600000) begin
      @(posedge clk);
      cycle_cnt = cycle_cnt + 1;
    end
    $display("[TB] TIMEOUT: %0d cycles, got %0d/%0d bytes", cycle_cnt, k, NTOTAL);
    $display("SMOKE2 FAIL");
    $finish;
  end

  initial begin
    $display("[TB] smoke_2: stub_cpu+stub_ame 总线级微内核(demo_decode.s)");
    rst_ni = 1'b0;
    repeat (10) @(posedge clk);
    rst_ni = 1'b1;

    for (k = 0; k < NTOTAL; k = k + 1) begin
      recv_byte(b);
      got[k] = b;
    end

    errs = 0;
    for (k = 0; k < NTOTAL; k = k + 1) begin
      if (got[k] !== exp[k]) begin
        $display("[TB] MISMATCH [%0d]: got=%02x exp=%02x", k, got[k], exp[k]);
        errs = errs + 1;
      end
    end

    $write("[TB] UART: ");
    for (k = 0; k < NTOTAL; k = k + 1) $write("%c", got[k]);
    $write("\n");

    repeat (2000) @(posedge clk);
    if (gpio[0] !== 1'b1)
      $display("[TB] WARN: CPU 未进入 WFI (gpio=%b)", gpio);

    if (errs == 0) begin
      $display("[TB] boot 字符串 + GEMV 16 通道 requant 结果逐字节一致; irq=%b gpio=%b",
               irq, gpio);
      $display("SMOKE2 PASS");
    end else begin
      $display("SMOKE2 FAIL (%0d mismatches)", errs);
    end
    $finish;
  end

  initial begin
    if ($test$plusargs("WAVE")) begin
      $dumpfile("smoke2.vcd");
      $dumpvars(0, tb_smoke_2);
    end
  end

endmodule
