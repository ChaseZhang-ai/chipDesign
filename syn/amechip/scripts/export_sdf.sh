#!/usr/bin/env bash
# export_sdf.sh — 从 ORFS 终版 6_final 导出 SDF(P4A 任务 5)
# 用法: bash export_sdf.sh <result_dir> <sdf_out>
set -eu
RESULT_DIR="${1:?usage: export_sdf.sh <result_dir> <sdf_out>}"
SDF_OUT="${2:?usage: export_sdf.sh <result_dir> <sdf_out>}"
FLOW="$HOME/tools/openroad-flow-scripts/flow"
cd "$FLOW"
# shellcheck disable=SC1091
source ../env.sh >/dev/null 2>&1 || true
export AME_RESULT_DIR="$RESULT_DIR"
export AME_SDF_OUT="$SDF_OUT"
openroad -exit /home/zcz/verda/autoDecodeChip/syn/amechip/scripts/export_sdf.tcl
