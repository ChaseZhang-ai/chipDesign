#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# run_sta.sh — 对已完成的 1_synth 结果跑 OpenROAD STA(P4A0;P1BX-B 后复用)
#
# 前置:已执行 ORFS synth(产物 1_synth.odb/1_synth.sdc 在 WORK_HOME 下)。
# 用法:
#   bash syn/amechip/scripts/run_sta.sh [WORK_HOME] [FLOW_VARIANT]
# 默认 WORK_HOME=$REPO/pnr/amechip, FLOW_VARIANT=p4a0。
# -----------------------------------------------------------------------------
set -eu

REPO="$(cd "$(dirname "$0")/../../.." && pwd)"
WORK_HOME="${1:-$REPO/pnr/amechip}"
VARIANT="${2:-p4a0}"
ORFS="$HOME/tools/openroad-flow-scripts"

# shellcheck disable=SC1090
source "$ORFS/env.sh" >/dev/null 2>&1

export PLATFORM_DIR="$ORFS/flow/platforms/sky130hd"
export RESULTS_DIR="$WORK_HOME/results/sky130hd/amechip/$VARIANT"
export REPORTS_DIR="$WORK_HOME/reports/sky130hd/amechip/$VARIANT"
export LIB_FILES="$PLATFORM_DIR/lib/sky130_fd_sc_hd__tt_025C_1v80.lib"

# 宏化网表(任务 L):追加 sky130ram 宏 .lib(仅 TT 单角,P4READY §1)
if grep -q "sky130_sram_1rw1r" "$RESULTS_DIR/1_2_yosys.v" 2>/dev/null; then
  export LIB_FILES="$LIB_FILES $HOME/tools/openroad-flow-scripts/flow/platforms/sky130ram/sky130_sram_1rw1r_128x256_8/sky130_sram_1rw1r_128x256_8_TT_1p8V_25C.lib"
fi

if [ ! -f "$RESULTS_DIR/1_synth.odb" ]; then
  echo "ERROR: $RESULTS_DIR/1_synth.odb 不存在;先跑 ORFS synth" >&2
  exit 1
fi

openroad -exit "$REPO/syn/amechip/scripts/sta_top20.tcl"
