#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# check_pdn_gate.sh — P4A PDN 门控: 在给定 ODB(建议 3_5 详细布局后)跑
# check_power_grid(VDD+VSS), 错误写文件并分类汇总, 全绿退出 0。
#
# 用法: bash check_pdn_gate.sh <odb 路径> <输出前缀>
# 产出: <前缀>.psm.log      完整输出
#       <前缀>.shorts       短路明细(violation type: Shorts 段)
#       <前缀>.unconnected  未连通明细
#       <前缀>.summary      一行式汇总(进报告)
# -----------------------------------------------------------------------------
set -eu
ODB="${1:?usage: check_pdn_gate.sh <odb> <prefix>}"
PRE="${2:?usage: check_pdn_gate.sh <odb> <prefix>}"

ORFS="$HOME/tools/openroad-flow-scripts"
# shellcheck disable=SC1090
source "$ORFS/env.sh" >/dev/null 2>&1 || true

cat > /tmp/ame_gate.tcl <<EOF
read_db $ODB
foreach net {VDD VSS} {
  puts "=== GATE check_power_grid \$net ==="
  if {[catch {check_power_grid -net \$net} err]} {
    puts "GATE_FAIL \$net"
  } else {
    puts "GATE_OK \$net"
  }
}
EOF
openroad -no_init -exit /tmp/ame_gate.tcl > "$PRE.psm.log" 2>&1 || true

ok=0
for net in VDD VSS; do
  if grep -q "GATE_OK $net" "$PRE.psm.log"; then
    echo "$net: OK" >> "$PRE.summary"
  else
    echo "$net: FAIL ($(grep -c 'PSM-0043' "$PRE.psm.log") shorts, $(grep -c 'PSM-0038' "$PRE.psm.log") unconn shapes, $(grep -c 'PSM-0039' "$PRE.psm.log") unconn insts)" >> "$PRE.summary"
    ok=1
  fi
done
grep -B0 -A0 'PSM-0043' "$PRE.psm.log" > "$PRE.shorts" || true
grep 'PSM-0038\|PSM-0039' "$PRE.psm.log" > "$PRE.unconnected" || true
cat "$PRE.summary"
exit $ok
