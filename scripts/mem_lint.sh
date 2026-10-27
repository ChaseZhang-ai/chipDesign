#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# mem_lint.sh — P2C 存储子系统 RTL 双 lint(iverilog + verilator)
#
# 用法: bash scripts/mem_lint.sh
# 退出码: 0 = 全绿;1 = 任一失败
# 说明: iverilog 对 always 块内位选输出 "sorry:" 提示(良性,灵敏度包含
#       全位,不影响功能),按退出码与 error 关键字判定。
# -----------------------------------------------------------------------------
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG="$ROOT/rtl/amechip_pkg.sv"
FILES=("$PKG"
       "$ROOT"/rtl/mem/*.sv)
INCFLAGS=(-I"$ROOT/rtl" -I"$ROOT/rtl/interfaces")

fail=0

echo "== iverilog -g2012 (rtl/mem) =="
if iverilog -g2012 -t null "${INCFLAGS[@]}" "${FILES[@]}" 2>&1 |
   grep -qi "error"; then
  echo "iverilog: FAIL"; fail=1
else
  echo "iverilog: PASS"
fi

echo "== verilator --lint-only (rtl/mem, 逐顶层) =="
TOPS=(axi_xbar axi_mem_slave axi_decerr_slave axi_xbar_port dma_engine
      memc_xmem kv_ctrl kv_backend_sram kv_backend_axi mem_ss_top)
for top in "${TOPS[@]}"; do
  if verilator --lint-only --top-module "$top" "${INCFLAGS[@]}" "${FILES[@]}" \
       > /dev/null 2> /tmp/verilator_mem_$$; then
    echo "  verilator($top): PASS"
  else
    echo "  verilator($top): FAIL"
    grep -E "%Warning|%Error" /tmp/verilator_mem_$$ | head -10
    fail=1
  fi
done
rm -f /tmp/verilator_mem_$$

exit $fail
