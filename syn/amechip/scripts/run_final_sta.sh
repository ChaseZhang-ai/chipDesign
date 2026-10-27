#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# run_final_sta.sh — P4A 终版签核分析入口
# 用法: bash run_final_sta.sh [WORK_HOME] [VARIANT]
# -----------------------------------------------------------------------------
set -eu
REPO="$(cd "$(dirname "$0")/../../.." && pwd)"
WORK_HOME="${1:-$REPO/pnr/amechip}"
VARIANT="${2:-p4a2}"
ORFS="$HOME/tools/openroad-flow-scripts"
# shellcheck disable=SC1090
source "$ORFS/env.sh" >/dev/null 2>&1
export PLATFORM_DIR="$ORFS/flow/platforms/sky130hd"
export RESULTS_DIR="$WORK_HOME/results/sky130hd/amechip/$VARIANT"
export REPORTS_DIR="$WORK_HOME/reports/sky130hd/amechip/$VARIANT"
export LIB_FILES="$PLATFORM_DIR/lib/sky130_fd_sc_hd__tt_025C_1v80.lib \
  $ORFS/flow/platforms/sky130ram/sky130_sram_1rw1r_128x256_8/sky130_sram_1rw1r_128x256_8_TT_1p8V_25C.lib"
openroad -no_init -exit "$REPO/syn/amechip/scripts/sta_final.tcl"
