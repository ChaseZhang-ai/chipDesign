#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# check_pdn.sh — PDN 生成后立刻做电源连通性检查(P4A 教训:第一轮 PDN 的宏电源
# 悬空问题在 2_4 就已产生,却陪跑 4.5h 布线到 6_report 的 PSM-0069 才暴露。
# check_power_grid 不依赖信号布线,2_4 完成即可单独跑,几分钟出结果。)
#
# 用法: bash check_pdn.sh <odb 路径> [VDD 网名] [VSS 网名]
# -----------------------------------------------------------------------------
set -eu
ODB="${1:?usage: check_pdn.sh <odb> [pwr] [gnd]}"
PWR="${2:-VDD}"
GND="${3:-VSS}"

ORFS="$HOME/tools/openroad-flow-scripts"
# shellcheck disable=SC1090
source "$ORFS/env.sh" >/dev/null 2>&1 || true

openroad -no_init -exit <<EOF 2>&1
read_db $ODB
puts "=== check_power_grid $PWR ==="
if {[catch {check_power_grid -net $PWR} err]} { puts "PWR_CHECK_FAIL $PWR: \$err"; exit 1 }
puts "=== check_power_grid $GND ==="
if {[catch {check_power_grid -net $GND} err]} { puts "PWR_CHECK_FAIL $GND: \$err"; exit 1 }
puts "PWR_CHECK_OK"
EOF
