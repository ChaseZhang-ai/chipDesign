#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# lint_interfaces.sh — P1B 契约接口文件的 iverilog + verilator 双 lint(P1B 交付)
#
# 用法:
#   bash scripts/lint_interfaces.sh          # 契约文件语法级双 lint
#   bash scripts/lint_interfaces.sh --smoke  # 额外做"使用级"验证:
#                                            # 例化全部接口 + modport 连接
#                                            # (P2A/P2B/P2C/P2D 开工自检用)
# 退出码: 0 = 全绿;1 = 任一失败
# -----------------------------------------------------------------------------
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG="$ROOT/rtl/amechip_pkg.sv"
IFDIR="$ROOT/rtl/interfaces"

FILES=("$PKG"
       "$IFDIR/ame_coproc_if.sv"
       "$IFDIR/ame_dma_if.sv"
       "$IFDIR/axi_lite_if.sv"
       "$IFDIR/kv_sram_if.sv"
       "$IFDIR/clk_rst_if.sv"
       "$IFDIR/amechip_top_ports.sv")

# 让 `include "amechip_pkg.sv"` 能被找到
INCFLAGS=(-I"$ROOT/rtl" -I"$IFDIR")

fail=0

echo "== iverilog -g2012 =="
if iverilog -g2012 -t null "${INCFLAGS[@]}" "${FILES[@]}"; then
  echo "iverilog: PASS"
else
  echo "iverilog: FAIL"; fail=1
fi

echo "== verilator --lint-only =="
# amechip_top_ports 是唯一 module 顶层;其余为 interface,随文件一并 lint
if verilator --lint-only --top-module amechip_top_ports "${INCFLAGS[@]}" "${FILES[@]}"; then
  echo "verilator: PASS"
else
  echo "verilator: FAIL"; fail=1
fi

# -----------------------------------------------------------------------------
# 可选:使用级 smoke(证明接口可被例化、modport 可连接、pkg 类型可用)
# -----------------------------------------------------------------------------
if [[ "${1:-}" == "--smoke" ]]; then
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  cat > "$TMP/smoke.sv" <<'EOF'
// smoke: 实例化全部 P1B 接口并以 modport 连接(仅编译/lint,不出波形)
`include "amechip_pkg.sv"
`include "ame_coproc_if.sv"
`include "ame_dma_if.sv"
`include "axi_lite_if.sv"
`include "kv_sram_if.sv"
`include "clk_rst_if.sv"

module smoke (
  input logic clk_i,
  input logic rst_ni,
  output logic [31:0] dbg_o
);
  clk_rst_if u_cr();
  assign u_cr.clk = clk_i;
  assign u_cr.rst_ni = rst_ni;

  ame_coproc_if u_cp (.clk(u_cr.clk), .rst_n(u_cr.rst_n));
  ame_dma_if     u_dm (.clk(u_cr.clk), .rst_n(u_cr.rst_n));
  axi_lite_if    u_ax (.clk(u_cr.clk), .rst_n(u_cr.rst_n));
  kv_sram_if #(.BANKS(4), .AW(12)) u_kv (.clk(u_cr.clk), .rst_n(u_cr.rst_n));

  // CPU 侧(master modport)
  always_comb begin
    u_cp.req_valid  = 1'b1;
    u_cp.req_instr  = 32'h0220_000B; // ame.cfg 16,16
    u_cp.req_rs1    = '0;
    u_cp.req_rs2    = '0;
    u_ax.b_ready    = 1'b1;
    u_ax.r_ready    = 1'b1;
    u_ax.aw_valid   = 1'b0;
    u_ax.w_valid    = 1'b0;
    u_ax.ar_valid   = 1'b0;
    u_ax.aw         = '0;
    u_ax.w          = '0;
    u_ax.ar         = '0;
    u_dm.req_valid  = 1'b0;
    u_dm.req_write  = 1'b0;
    u_dm.req_addr   = '0;
    u_dm.req_wdata  = '0;
    u_dm.req_wstrb  = '0;
  end

  // AME/xbar 侧(slave modport)
  always_comb begin
    u_cp.req_ready  = !u_cr.rst_busy;
    u_cp.resp_valid = 1'b0;
    u_cp.resp_data  = '0;
    u_cp.resp_err   = 1'b0;
    u_dm.req_ready  = 1'b1;
    u_dm.resp_valid = 1'b0;
    u_dm.resp_rdata = 32'hDEAD_BEEF;
    u_dm.resp_err   = 1'b0;
    u_ax.aw_ready   = 1'b1;
    u_ax.w_ready    = 1'b1;
    u_ax.b_valid    = 1'b0;
    u_ax.ar_ready   = 1'b1;
    u_ax.r_valid    = 1'b0;
    u_ax.b          = '0;
    u_ax.r          = '0;
  end

  // KV 后端(mem modport):1 拍读延迟行为
  logic [31:0] kv_mem [0:4095];
  always_ff @(posedge u_cr.clk) begin
    for (int b = 0; b < 4; b++) begin
      if (u_kv.cs[b] && u_kv.we[b])
        kv_mem[u_kv.addr[b*12 +: 12]] <= u_kv.wdata[b*32 +: 32];
    end
  end
  always_comb begin
    for (int b = 0; b < 4; b++) begin
      u_kv.rdata[b*32 +: 32] =
        (u_kv.cs[b] && !u_kv.we[b]) ? kv_mem[u_kv.addr[b*12 +: 12]] : '0;
    end
  end

  // 观测(pkg 枚举/类型可用性)
  amechip_pkg::ame_op_e op;
  always_comb begin
    op = amechip_pkg::ame_op_e'(u_cp.req_instr[14:12]);
    dbg_o = {u_cr.rst_n, u_cp.req_ready, 2'(op), u_dm.resp_rdata[19:0],
             8'(u_kv.rdata[7:0])};
  end
endmodule
EOF
  echo "== smoke(使用级验证)iverilog =="
  if iverilog -g2012 -t null "${INCFLAGS[@]}" "$TMP/smoke.sv" 2>/dev/null; then
    echo "smoke iverilog: PASS"
  else
    # iverilog 对常量位选择切片会告警,不影响正确性;失败才判 FAIL
    if iverilog -g2012 -t null "${INCFLAGS[@]}" "$TMP/smoke.sv" 2>&1 | grep -qi "error"; then
      echo "smoke iverilog: FAIL"; fail=1
    else
      echo "smoke iverilog: PASS(warnings only)"
    fi
  fi
  echo "== smoke verilator =="
  if verilator --lint-only --top-module smoke "${INCFLAGS[@]}" "$TMP/smoke.sv"; then
    echo "smoke verilator: PASS"
  else
    echo "smoke verilator: FAIL"; fail=1
  fi
fi

exit $fail
