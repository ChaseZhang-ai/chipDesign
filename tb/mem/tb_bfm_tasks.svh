// -----------------------------------------------------------------------------
// tb_bfm_tasks.svh — AXI4-Lite 主设备 BFM 任务(TB include 用,P2C)
//
// 使用方式:在 TB 顶层 module 内 `include;要求先声明:
//   logic clk; int errors;
//   与 mem_ss_top CPU 口相连的信号(前缀 c_):
//     c_aw_valid/c_aw_ready/c_aw_addr, c_w_valid/c_w_ready/c_w_data/c_w_strb,
//     c_b_valid/c_b_ready/c_b_resp, c_ar_valid/c_ar_ready/c_ar_addr,
//     c_r_valid/c_r_ready/c_r_data/c_r_resp
// 约定:负沿驱动、正沿采样;协议监视器(稳定性/对齐)含在本文件。
// -----------------------------------------------------------------------------
// (每个任务用自动局部循环标志,避免嵌套任务共享状态)

// 错误计数与报告
int   bfm_errors;
int   bfm_checks;

task automatic bfm_fail(input string msg);
  begin
    $display("[FAIL] %0t %s", $time, msg);
    bfm_errors = bfm_errors + 1;
  end
endtask

task automatic bfm_check_eq(input string what, input logic [31:0] got,
                            input logic [31:0] exp);
  begin
    bfm_checks = bfm_checks + 1;
    if (got !== exp) begin
      $display("[FAIL] %0t %s: got=%08h exp=%08h", $time, what, got, exp);
      bfm_errors = bfm_errors + 1;
    end else begin
      $display("[ ok ] %0t %s = %08h", $time, what, got);
    end
  end
endtask

// ---------------------------------------------------------------- 写(B 等响应)
task automatic axi_write(input logic [31:0] addr, input logic [31:0] data,
                         input logic [1:0] exp_resp = 2'b00);
  logic ldone;
  begin
    @(negedge clk);
    c_aw_valid = 1'b1; c_w_valid = 1'b1;
    c_aw_addr  = addr; c_w_data  = data; c_w_strb = 4'hF;
    ldone = 1'b0;
    while (!ldone) begin
      @(posedge clk);
      if (c_aw_ready === 1'b1 && c_w_ready === 1'b1) ldone = 1'b1;
    end
    @(negedge clk);
    c_aw_valid = 1'b0; c_w_valid = 1'b0;
    c_b_ready  = 1'b1;
    ldone = 1'b0;
    while (!ldone) begin
      @(posedge clk);
      if (c_b_valid === 1'b1) ldone = 1'b1;
    end
    bfm_checks = bfm_checks + 1;
    if (c_b_resp !== exp_resp) begin
      $display("[FAIL] %0t axi_write(%08h): resp=%b exp=%b",
               $time, addr, c_b_resp, exp_resp);
      bfm_errors = bfm_errors + 1;
    end
    @(negedge clk);
    c_b_ready = 1'b0;
  end
endtask

// ---------------------------------------------------------------- 读
task automatic axi_read(input logic [31:0] addr, output logic [31:0] data,
                        input logic [1:0] exp_resp = 2'b00);
  logic ldone;
  begin
    @(negedge clk);
    c_ar_valid = 1'b1; c_ar_addr = addr;
    c_aw_valid = 1'b0; c_w_valid = 1'b0;
    ldone = 1'b0;
    while (!ldone) begin
      @(posedge clk);
      if (c_ar_ready === 1'b1) ldone = 1'b1;
    end
    @(negedge clk);
    c_ar_valid = 1'b0;
    c_r_ready  = 1'b1;
    ldone = 1'b0;
    while (!ldone) begin
      @(posedge clk);
      if (c_r_valid === 1'b1) ldone = 1'b1;
    end
    data = c_r_data;
    bfm_checks = bfm_checks + 1;
    if (c_r_resp !== exp_resp) begin
      $display("[FAIL] %0t axi_read(%08h): resp=%b exp=%b",
               $time, addr, c_r_resp, exp_resp);
      bfm_errors = bfm_errors + 1;
    end
    @(negedge clk);
    c_r_ready = 1'b0;
  end
endtask

task automatic axi_read_check(input string what, input logic [31:0] addr,
                              input logic [31:0] exp,
                              input logic [1:0] exp_resp = 2'b00);
  logic [31:0] d;
  begin
    axi_read(addr, d, exp_resp);
    bfm_check_eq(what, d, exp);
  end
endtask

// ---------------------------------------------------------------- CPU 读延迟测量
int   lat_cycles;
int   lat_max;
task automatic axi_read_lat(input logic [31:0] addr, output logic [31:0] data);
  int n;
  logic ldone;
  begin
    @(negedge clk);
    c_ar_valid = 1'b1; c_ar_addr = addr;
    c_aw_valid = 1'b0; c_w_valid = 1'b0;
    n = 0;
    ldone = 1'b0;
    while (!ldone) begin
      @(posedge clk);
      n = n + 1;
      if (c_ar_ready === 1'b1) ldone = 1'b1;
    end
    lat_cycles = n; // 从置 valid 到 AR 被接受(排队时延)
    @(negedge clk);
    c_ar_valid = 1'b0;
    c_r_ready  = 1'b1;
    ldone = 1'b0;
    while (!ldone) begin
      @(posedge clk);
      n = n + 1;
      if (c_r_valid === 1'b1) ldone = 1'b1;
    end
    data = c_r_data;
    @(negedge clk);
    c_r_ready = 1'b0;
    lat_cycles = n;
    if (n > lat_max) lat_max = n;
  end
endtask

// ---------------------------------------------------------------- DMA 辅助
task automatic dma_cfg(input logic [31:0] src, input logic [31:0] dst,
                       input logic [31:0] xcnt, input logic [31:0] ycnt,
                       input logic [31:0] sp, input logic [31:0] dp,
                       input logic [31:0] ctrl);
  begin
    axi_write(amechip_pkg::A_DMA_BASE + amechip_pkg::DMA_SRC_OFF,    src);
    axi_write(amechip_pkg::A_DMA_BASE + amechip_pkg::DMA_DST_OFF,    dst);
    axi_write(amechip_pkg::A_DMA_BASE + amechip_pkg::DMA_XCNT_OFF,   xcnt);
    axi_write(amechip_pkg::A_DMA_BASE + amechip_pkg::DMA_YCNT_OFF,   ycnt);
    axi_write(amechip_pkg::A_DMA_BASE + amechip_pkg::DMA_SPITCH_OFF, sp);
    axi_write(amechip_pkg::A_DMA_BASE + amechip_pkg::DMA_DPITCH_OFF, dp);
    axi_write(amechip_pkg::A_DMA_BASE + amechip_pkg::DMA_CTRL_OFF,   ctrl);
  end
endtask

// GO = CTRL[0];IRQ_EN = CTRL[4];SRC_FIX=[2];DST_FIX=[3]
task automatic dma_go(input bit irq_en = 1'b0);
  begin
    axi_write(amechip_pkg::A_DMA_BASE + amechip_pkg::DMA_CTRL_OFF,
              32'h1 | (irq_en ? 32'h10 : 32'h0));
  end
endtask

task automatic dma_wait(output logic [31:0] status);
  int guard;
  logic [31:0] s;
  logic ldone;
  begin
    guard = 0;
    ldone = 1'b0;
    s     = 32'hFFFF_FFFF;
    while (!ldone) begin
      axi_read(amechip_pkg::A_DMA_BASE + amechip_pkg::DMA_STATUS_OFF, s);
      if (s[0] == 1'b0) ldone = 1'b1;
      guard = guard + 1;
      if (guard > 200000) begin
        bfm_fail("dma_wait: 超时");
        s     = 32'hFFFF_FFFF;
        ldone = 1'b1;
      end
    end
    status = s;
    $display("[bfm] dma_wait polls=%0d final=%08h", guard, s);
  end
endtask

// ---------------------------------------------------------------- KV 辅助
task automatic kv_cfg(input logic [31:0] ctrl, input logic [31:0] layer,
                      input logic [31:0] head, input logic [31:0] pos,
                      input logic [31:0] count, input logic [31:0] src,
                      input logic [31:0] dst, input logic [31:0] pitch,
                      input logic [31:0] slice);
  begin
    axi_write(amechip_pkg::A_KV_BASE + amechip_pkg::KV_LAYER_OFF, layer);
    axi_write(amechip_pkg::A_KV_BASE + amechip_pkg::KV_HEAD_OFF,  head);
    axi_write(amechip_pkg::A_KV_BASE + amechip_pkg::KV_POS_OFF,   pos);
    axi_write(amechip_pkg::A_KV_BASE + amechip_pkg::KV_COUNT_OFF, count);
    axi_write(amechip_pkg::A_KV_BASE + amechip_pkg::KV_SRC_OFF,   src);
    axi_write(amechip_pkg::A_KV_BASE + amechip_pkg::KV_DST_OFF,   dst);
    axi_write(amechip_pkg::A_KV_BASE + amechip_pkg::KV_PITCH_OFF, pitch);
    axi_write(amechip_pkg::A_KV_BASE + amechip_pkg::KV_SLICE_OFF, slice);
    axi_write(amechip_pkg::A_KV_BASE + amechip_pkg::KV_CTRL_OFF,  ctrl);
  end
endtask

task automatic kv_go(input logic [2:0] mode, input bit transpose,
                     input bit irq_en = 1'b0);
  begin
    axi_write(amechip_pkg::A_KV_BASE + amechip_pkg::KV_CTRL_OFF,
              32'h0000_0100 | (transpose ? 32'h10 : 32'h0)
                            | (irq_en ? 32'h8 : 32'h0) | {29'b0, mode});
  end
endtask

task automatic kv_wait(output logic [31:0] status);
  int guard;
  logic [31:0] s;
  logic ldone;
  begin
    guard = 0;
    ldone = 1'b0;
    s     = 32'hFFFF_FFFF;
    while (!ldone) begin
      axi_read(amechip_pkg::A_KV_BASE + amechip_pkg::KV_STATUS_OFF, s);
      if (s[0] == 1'b0) ldone = 1'b1;
      guard = guard + 1;
      if (guard > 2000000) begin
        bfm_fail("kv_wait: 超时");
        s     = 32'hFFFF_FFFF;
        ldone = 1'b1;
      end
    end
    status = s;
    $display("[bfm] kv_wait polls=%0d final=%08h", guard, s);
  end
endtask

// ---------------------------------------------------------------- 协议监视器
logic       mon_aw_vq, mon_w_vq, mon_ar_vq;
logic [31:0] mon_aw_aq, mon_w_dq, mon_ar_aq;
logic       mon_b_vq, mon_r_vq;
logic [1:0] mon_b_rq, mon_r_rq;
logic [31:0] mon_r_dq;

always @(posedge clk) begin
  if (!rst_n) begin
    mon_aw_vq <= 1'b0; mon_w_vq <= 1'b0; mon_ar_vq <= 1'b0;
    mon_b_vq <= 1'b0;  mon_r_vq <= 1'b0;
    mon_aw_aq <= '0; mon_w_dq <= '0; mon_ar_aq <= '0;
    mon_b_rq <= '0;  mon_r_rq <= '0; mon_r_dq <= '0;
  end else begin
    // 主→从 payload 稳定性:valid 保持且未 ready 时不得变化
    if (mon_aw_vq && !c_aw_ready && c_aw_valid &&
        (c_aw_addr !== mon_aw_aq))
      bfm_fail("协议: AW payload 在 ready 前变化");
    if (mon_w_vq && !c_w_ready && c_w_valid && (c_w_data !== mon_w_dq))
      bfm_fail("协议: W payload 在 ready 前变化");
    if (mon_ar_vq && !c_ar_ready && c_ar_valid &&
        (c_ar_addr !== mon_ar_aq))
      bfm_fail("协议: AR payload 在 ready 前变化");
    // 从→主响应稳定性
    if (mon_b_vq && !c_b_ready && c_b_valid && (c_b_resp !== mon_b_rq))
      bfm_fail("协议: B resp 在 ready 前变化");
    if (mon_r_vq && !c_r_ready && c_r_valid &&
        ((c_r_data !== mon_r_dq) || (c_r_resp !== mon_r_rq)))
      bfm_fail("协议: R payload 在 ready 前变化");
    // 字对齐(AXI-Lite 32-bit 单拍约定)
    if (c_aw_valid && c_aw_ready && c_aw_addr[1:0] !== 2'b00)
      bfm_fail("协议: AW 地址非字对齐");
    if (c_ar_valid && c_ar_ready && c_ar_addr[1:0] !== 2'b00)
      bfm_fail("协议: AR 地址非字对齐");
    // 空闲期不得有 valid-without-request 的悬空响应
    mon_aw_vq <= c_aw_valid; mon_aw_aq <= c_aw_addr;
    mon_w_vq  <= c_w_valid;  mon_w_dq  <= c_w_data;
    mon_ar_vq <= c_ar_valid; mon_ar_aq <= c_ar_addr;
    mon_b_vq  <= c_b_valid;  mon_b_rq  <= c_b_resp;
    mon_r_vq  <= c_r_valid;  mon_r_rq  <= c_r_resp; mon_r_dq <= c_r_data;
  end
end
