#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# vrf_run_all.sh — P3A AME 第三方全量验证一键重跑
#
#   bash scripts/vrf_run_all.sh [--quick]
#
# 步骤:
#   1. P2B 基线回归(lint/gen/run/run8/vrun/proto)
#   2. 全量 74 组 golden 对拍(verilator 全量 + iverilog 抽样 15 组)
#   3. 三方独立抽验(纯 python 重算 vs npz vs RTL dump)
#   4. 随机压力 520 场景(26 批,含 duty 测量)+ 边界专项 + ld.w-pre-cfg 偏差复现
#
# --quick:跳过步骤 1 的 P2B 基线(仅重跑 2–4)。
# 退出码:全部通过 0;任一失败 1(偏差复现 repro_ldw_precfg 不计入门禁)。
# -----------------------------------------------------------------------------
set -u
cd "$(dirname "$0")/.."
ROOT=$(pwd)
LOG=$ROOT/tb/ame/work/vrf/run_all.log
mkdir -p "$(dirname "$LOG")"
: > "$LOG"
QUICK=0
[ "${1:-}" = "--quick" ] && QUICK=1

fail=0
say() { echo "$@" | tee -a "$LOG"; }

say "===== P3A AME 第三方全量验证 $(date -u +%FT%TZ) ====="

if [ "$QUICK" -eq 0 ]; then
  say "--- [1/4] P2B 基线回归(lint/gen/run/run8/vrun/proto) ---"
  if make -C tb/ame lint gen run run8 vrun proto >>"$LOG" 2>&1; then
    say "P2B 基线: PASS"
  else
    say "P2B 基线: FAIL(见 $LOG)"; fail=1
  fi
else
  say "--- [1/4] 基线回归: 跳过(--quick) ---"
fi

say "--- [2/4] 全量 74 组 golden 对拍 ---"
if python3 scripts/vrf_run_full.py --regen --sim both --jobs 8 2>&1 | tee -a "$LOG" | tail -3; then
  :
fi
if grep -q "vrf_run_full: PASS" "$LOG"; then say "74 组对拍: PASS"; else say "74 组对拍: FAIL"; fail=1; fi

say "--- [3/4] 三方独立抽验 ---"
if python3 scripts/vrf_third_check.py 2>&1 | tee -a "$LOG" | tail -2; then
  :
fi
if grep -q "三方独立抽验: PASS" "$LOG"; then say "三方抽验: PASS"; else say "三方抽验: FAIL"; fail=1; fi

say "--- [4/4] 随机压力 520 场景 + 边界专项 ---"
python3 scripts/vrf_rand.py emit --n 520 --per-batch 20 >>"$LOG" 2>&1
rm -f tb/ame/work/vrf/rand/vsim
if python3 scripts/vrf_rand.py run --jobs 8 2>&1 | tee -a "$LOG" | tail -3; then
  :
fi
if grep -q "vrf_rand run: PASS" "$LOG"; then say "随机压力: PASS"; else say "随机压力: FAIL"; fail=1; fi

python3 scripts/vrf_bound_gen.py >>"$LOG" 2>&1
VSIM=$ROOT/tb/ame/work/vrf/full/vsim
if [ -x "$VSIM" ]; then
  out=$("$VSIM" +ops="$ROOT/tb/ame/work/vrf/bound/bound_main.ops" \
        +dump="$ROOT/tb/ame/work/vrf/bound/bound_main.gold" +case=bound +gid=main 2>&1)
  echo "$out" >>"$LOG"
  if echo "$out" | grep -q "VERIFY RESULT: PASS"; then say "边界专项: PASS"; else say "边界专项: FAIL"; fail=1; fi
  # ISA 偏差复现(仅取证,不计入门禁):预期装载 64 拍 > AME_M=16
  out2=$("$VSIM" +ops="$ROOT/tb/ame/work/vrf/bound/repro_ldw_precfg.ops" \
         +dump=/tmp/repro_ldw_precfg.gold +case=repro +gid=ldwprecfg 2>&1)
  echo "$out2" >>"$LOG"
  echo "$out2" | grep -E "PERF|RESULT" | sed 's/^/  [repro] /' | tee -a "$LOG"
fi

say "===== 结果: $([ "$fail" -eq 0 ] && echo PASS || echo FAIL) (日志 $LOG) ====="
exit "$fail"
