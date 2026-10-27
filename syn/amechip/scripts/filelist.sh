#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# filelist.sh — 把 syn/amechip/filelist.f 展开成 ORFS VERILOG_FILES 参数
# 用法: filelist.sh <repo_root> [macro]
#   无第 2 参         → filelist.f(flop 存储原版)
#   第 2 参 = macro   → filelist_macro.f(SRAM 宏化版,P4A 任务 L)
# 输出:空格分隔的绝对路径(单行)
# -----------------------------------------------------------------------------
set -eu
ROOT="${1:?usage: filelist.sh <repo_root> [macro]}"
MODE="${2:-}"
DIR="$(cd "$(dirname "$0")/.." && pwd)"
case "$MODE" in
  "")     FL="$DIR/filelist.f" ;;
  macro)  FL="$DIR/filelist_macro.f" ;;
  *) echo "unknown mode: $MODE (expect '' or 'macro')" >&2; exit 2 ;;
esac
grep -vE '^[[:space:]]*(#|$)' "$FL" | sed "s|^|$ROOT/|" | tr '\n' ' '
