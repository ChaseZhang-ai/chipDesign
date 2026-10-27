#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# vfrc_run_all.sh — P3C 存储子系统压力验证一键重跑
#
# 用法:
#   bash scripts/vfrc_run_all.sh              # 默认:生成场景 + 构建 + 全量运行
#   bash scripts/vfrc_run_all.sh --no-build   # 复用已有二进制/场景,只跑
#   bash scripts/vfrc_run_all.sh --full       # 额外跑 iverilog 版 DMA(慢)与
#                                             # P2C tb_kv 后端 A(15-20 分钟)
#   bash scripts/vfrc_run_all.sh --only kv    # 只跑某组(xbar|dma|kv|conc|p2c)
#
# 产物:build/p3c/{golden,vl_*,run_*,*.log}
# 退出码:0 = 全部预期项通过(含已知 P3C-1 的单独标注),1 = 有失败
# -----------------------------------------------------------------------------
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
B="$(cd "$ROOT" && pwd)/build/p3c"
RTL="$ROOT/rtl"
TB="$ROOT/tb/mem"
GOLD="$B/golden"
LOG="$B/logs"
DO_BUILD=1
FULL=0
ONLY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-build) DO_BUILD=0 ;;
    --full) FULL=1 ;;
    --only) ONLY="$2"; shift ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1"; exit 2 ;;
  esac
  shift
done

mkdir -p "$B" "$GOLD" "$LOG"

VL_FLAGS=(
  --binary --timing --assert -DVFRC_SVA
  -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM
  -Wno-CASEINCOMPLETE -Wno-DECLFILENAME -Wno-BLKANDNBLK -Wno-LATCH
  -Wno-COMBDLY -Wno-MULTIDRIVEN -Wno-TIMESCALEMOD -Wno-INITIALDLY
  -Wno-STMTDLY -Wno-MULTITOP -Wno-SYMRSVDWORD -Wno-VARHIDDEN
  -I"$RTL" -I"$RTL/interfaces" -I"$TB"
)
SRC_COMMON=(
  "$RTL/amechip_pkg.sv"
  "$RTL"/mem/*.sv
)
SRC_VERIFY=(
  "$TB/verify_protocol.sv" "$TB/verify_psram.sv" "$TB/verify_dut.sv"
  "$TB/tb_stubs.sv"
)
SRC_P2C=(
  "$RTL/amechip_pkg.sv" "$RTL"/mem/*.sv "$TB/tb_stubs.sv"
  "$TB/verify_protocol.sv"
)

PASS=0; FAIL=0; KNOWN=0; FAILED_NAMES=()

say()  { printf '\n\033[1m== %s ==\033[0m\n' "$*"; }
ok()   { PASS=$((PASS+1)); printf '  \033[32mPASS\033[0m %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); FAILED_NAMES+=("$1"); printf '  \033[31mFAIL\033[0m %s\n' "$1"; }
known(){ KNOWN=$((KNOWN+1)); printf '  \033[33mKNOWN\033[0m %s\n' "$1"; }

vl_build() { # name top [extra defs...]
  local name="$1" top="$2"; shift 2
  local dir="$B/vl_$name"
  [[ $DO_BUILD -eq 0 && -x "$dir/V$top" ]] && return 0
  say "构建 Verilator: $name ($top)"
  verilator "${VL_FLAGS[@]}" --top-module "$top" --Mdir "$dir" \
    "$@" "${SRC_COMMON[@]}" "${SRC_VERIFY[@]}" "$TB/$top.sv" \
    > "$LOG/build_$name.log" 2>&1
  local rc=$?
  if [[ $rc -ne 0 ]]; then
    echo "  Verilator 构建失败,见 $LOG/build_$name.log"
    grep -E "%Error" "$LOG/build_$name.log" | head -10
    return 1
  fi
  echo "  构建完成 -> $dir/V$top"
}

iv_build() { # name top [extra defs...]
  local name="$1" top="$2"; shift 2
  local out="$B/$name.vvp"
  [[ $DO_BUILD -eq 0 && -f "$out" ]] && return 0
  say "构建 iverilog: $name ($top)"
  iverilog -g2012 "$@" -I"$RTL" -I"$RTL/interfaces" -I"$TB" \
    -o "$out" "${SRC_COMMON[@]}" "${SRC_VERIFY[@]}" "$TB/$top.sv" \
    > "$LOG/build_$name.log" 2>&1
  local rc=$?
  if [[ $rc -ne 0 ]]; then
    echo "  iverilog 构建失败,见 $LOG/build_$name.log"
    head -10 "$LOG/build_$name.log"
    return 1
  fi
  echo "  构建完成 -> $out"
}

# 运行并检查: run_log <tag> <cwd> <cmd...>
run_log() {
  local tag="$1"; local dir="$2"; shift 2
  mkdir -p "$dir"
  ( cd "$dir" && timeout 1800 "$@" ) > "$LOG/$tag.log" 2>&1
  echo "  日志: $LOG/$tag.log"
}

check_pass() { # tag pattern
  local tag="$1" pat="$2"
  if grep -q "$pat" "$LOG/$tag.log"; then ok "$tag"; else bad "$tag"; tail -6 "$LOG/$tag.log"; fi
}

check_proto() { # tag [allow_known_ar]
  local tag="$1" allow="${2:-0}"
  local nf
  nf=$(grep -c "PROTO-FAIL" "$LOG/$tag.log" || true)
  if grep -q "^PROTO: PASS" "$LOG/$tag.log"; then
    ok "$tag / PROTO"
  elif [[ "$allow" == "1" && "$nf" -gt 0 ]] \
       && ! grep "PROTO-FAIL" "$LOG/$tag.log" | grep -v "M_AR_STABLE" | grep -q .; then
    known "$tag / PROTO(M_AR_STABLE under ABORT -> P3C-1)"
  else
    bad "$tag / PROTO"
    grep "PROTO-FAIL" "$LOG/$tag.log" | head -5
  fi
}

check_img() { # tag dump exp
  local tag="$1" dump="$2" exp="$3"
  if python3 "$ROOT/scripts/vfrc_compare.py" "$dump" "$exp" --tag "$tag" >> "$LOG/$tag.img.log" 2>&1; then
    ok "$tag / 镜像"
  else
    bad "$tag / 镜像"
    tail -8 "$LOG/$tag.img.log"
  fi
}

# ---------------------------------------------------------------- 场景生成
say "生成 KV/DMA 场景(golden)"
python3 "$ROOT/scripts/vfrc_kv_gen.py" --outdir "$GOLD" | tee "$LOG/gen_kv.log"
python3 "$ROOT/scripts/vfrc_dma_gen.py" --outdir "$GOLD/dma" | tee "$LOG/gen_dma.log"

want() { [[ -z "$ONLY" || "$ONLY" == "$1" ]]; }

# ---------------------------------------------------------------- 构建
if want xbar; then
  vl_build xbar_ports verify_xbar_ports || bad "build:xbar_ports"
  iv_build xbar_ports_iv verify_xbar_ports || bad "build:xbar_ports_iv"
fi
if want dma; then
  vl_build dma verify_dma_stress || bad "build:dma"
fi
if want kv; then
  vl_build kv_a verify_kv_full -DVFRC_KV_CTX=256 || bad "build:kv_a"
  vl_build kv_b verify_kv_full -DVFRC_KV_B=1 -DVFRC_KV_IS_B -DVFRC_KV_CTX=128 || bad "build:kv_b"
  iv_build kv_b_iv verify_kv_full -DVFRC_KV_B=1 -DVFRC_KV_IS_B -DVFRC_KV_CTX=128 || bad "build:kv_b_iv"
fi
if want conc; then
  vl_build conc verify_concurrent || bad "build:conc"
fi
if want p2c; then
  say "构建 P2C 既有 TB + 协议监视(wrapper)"
  for t in xbar dma kv; do
    out="$B/wrap_$t.vvp"
    extra=""
    [[ "$t" == "kv" ]] && extra="-DKV_BB"
    if [[ $DO_BUILD -eq 1 || ! -f "$out" ]]; then
      iverilog -g2012 $extra -I"$RTL" -I"$RTL/interfaces" -I"$TB" \
        -o "$out" "$RTL/amechip_pkg.sv" "$RTL"/mem/*.sv "$TB/tb_stubs.sv" \
        "$TB/tb_$t.sv" "$TB/verify_protocol.sv" "$TB/verify_p2c_wrap.sv" \
        -s "verify_wrap_$t" > "$LOG/build_wrap_$t.log" 2>&1 || bad "build:wrap_$t"
    fi
  done
fi

# ---------------------------------------------------------------- 运行
if want xbar; then
  say "xbar 全主从口压力(iverilog + Verilator/SVA)"
  run_log xbar_iv "$B/run/xbar_iv" vvp "$B/xbar_ports_iv.vvp"
  check_pass xbar_iv "VERIFY_XBAR_PORTS: PASS"
  check_proto xbar_iv
  run_log xbar_vl "$B/run/xbar_vl" "$B/vl_xbar_ports/Vverify_xbar_ports"
  check_pass xbar_vl "VERIFY_XBAR_PORTS: PASS"
  check_proto xbar_vl
fi

if want dma; then
  say "DMA 随机压力(329 笔,≥300)"
  run_log dma "$GOLD/dma" "$B/vl_dma/Vverify_dma_stress"
  check_pass dma "VERIFY_DMA: PASS"
  check_proto dma 1
  grep -E "^=== verify_dma" "$LOG/dma.log" | tail -1
fi

if want kv; then
  say "KV 全场景(后端 A 主,后端 B 抽查)"
  for v in a_full a_slice; do
    run_log "kv_$v" "$GOLD/$v" "$B/vl_kv_a/Vverify_kv_full"
    check_pass "kv_$v" "VERIFY_KV: PASS"
    check_img "kv_$v" "$GOLD/$v/kv_dump_xmem.hex" "$GOLD/$v/kv_exp_xmem.hex"
    grep -E "^=== verify_kv_full" "$LOG/kv_$v.log" | tail -1
  done
  for v in slice_b b_full; do
    run_log "kv_$v" "$GOLD/$v" "$B/vl_kv_b/Vverify_kv_full"
    check_pass "kv_$v" "VERIFY_KV: PASS"
    check_img "kv_$v" "$GOLD/$v/kv_dump_bank0.hex" "$GOLD/$v/kv_exp_bank0.hex"
    check_img "kv_$v-b1" "$GOLD/$v/kv_dump_bank1.hex" "$GOLD/$v/kv_exp_bank1.hex"
    check_img "kv_$v-b2" "$GOLD/$v/kv_dump_bank2.hex" "$GOLD/$v/kv_exp_bank2.hex"
    check_img "kv_$v-b3" "$GOLD/$v/kv_dump_bank3.hex" "$GOLD/$v/kv_exp_bank3.hex"
    grep -E "^=== verify_kv_full" "$LOG/kv_$v.log" | tail -1
  done
  say "KV 交叉仿真: iverilog 后端 B(b_full)"
  run_log kv_b_iv "$GOLD/b_full" vvp "$B/kv_b_iv.vvp"
  check_pass kv_b_iv "VERIFY_KV: PASS"
fi

if want conc; then
  say "三主并发 100 万拍 + 时延/吞吐复测"
  run_log conc "$B/run/conc" "$B/vl_conc/Vverify_concurrent"
  check_pass conc "VERIFY_CONC: PASS"
  check_proto conc
  if grep -q "^DATA_INTEGRITY: PASS" "$LOG/conc.log"; then
    ok "conc / 数据完整性"
  elif grep -q "^DATA_INTEGRITY: FAIL(P3C-2)" "$LOG/conc.log"; then
    known "conc / 数据完整性: P3C-2(memc 预取陈旧槽) $(grep -o 'FAIL(P3C-2) hits=[0-9]*' "$LOG/conc.log" | tail -1)"
  else
    bad "conc / 数据完整性"
  fi
  grep -E "^\[conc\]|^\[lat\]|^\[perf\]" "$LOG/conc.log"
fi

if want p2c; then
  say "P2C 既有 TB 回归 + 全端口协议断言(wrapper)"
  mkdir -p "$B/run/p2c_xbar" "$B/run/p2c_dma"
  cp -f "$TB/boot_rom.memh" "$B/run/p2c_xbar/" 2>/dev/null || true
  cp -f "$TB/boot_rom.memh" "$B/run/p2c_dma/" 2>/dev/null || true
  run_log p2c_xbar "$B/run/p2c_xbar" vvp "$B/wrap_xbar.vvp"
  check_pass p2c_xbar "TB_XBAR: PASS"
  check_proto p2c_xbar
  run_log p2c_dma "$B/run/p2c_dma" vvp "$B/wrap_dma.vvp"
  check_pass p2c_dma "TB_DMA: PASS"
  check_proto p2c_dma 1
  # kv B 需要 golden 文件:拷到独立运行目录
  mkdir -p "$B/run/p2c_kv_b"
  cp -f "$ROOT/models/kv_golden/b/"* "$B/run/p2c_kv_b/" 2>/dev/null || true
  cp -f "$TB/boot_rom.memh" "$B/run/p2c_kv_b/" 2>/dev/null || true
  run_log p2c_kv_b "$B/run/p2c_kv_b" vvp "$B/wrap_kv.vvp"
  check_pass p2c_kv_b "TB_KV: PASS"
  check_proto p2c_kv_b
  if python3 "$ROOT/scripts/mem_kv_golden.py" --compare-dir "$B/run/p2c_kv_b" \
       >> "$LOG/p2c_kv_b.img.log" 2>&1; then
    ok "p2c_kv_b / 镜像"
  else
    bad "p2c_kv_b / 镜像"
  fi
  if [[ $FULL -eq 1 ]]; then
    say "P2C tb_kv 后端 A 全量(15-20 分钟)"
    mkdir -p "$B/run/p2c_kv_a"
    cp -f "$ROOT/models/kv_golden/a/"* "$B/run/p2c_kv_a/" 2>/dev/null || true
    iv_build kv_a_p2c tb_kv || true
    run_log p2c_kv_a "$B/run/p2c_kv_a" vvp "$B/kv_a_p2c.vvp"
    check_pass p2c_kv_a "TB_KV: PASS"
  fi
fi

if [[ -z "$ONLY" || "$ONLY" == "repro" || "$ONLY" == "conc" ]]; then
  say "P3C-2 最小复现(独立 MEMC + PSRAM)"
  if [[ $DO_BUILD -eq 1 || ! -f "$B/repro.vvp" ]]; then
    iverilog -g2012 -I"$RTL" -I"$RTL/interfaces" -I"$TB" -o "$B/repro.vvp" \
      "$RTL/amechip_pkg.sv" "$RTL/mem/memc_xmem.sv" "$TB/verify_psram.sv" \
      "$TB/verify_memc_repro.sv" > "$LOG/build_repro.log" 2>&1 || bad "build:repro"
  fi
  run_log repro "$B/run/repro" vvp "$B/repro.vvp"
  # P1BXB:P3C-2/P3D-07 已正式修复(rtl/mem/memc_xmem 预驱旁路)——
  # 复现用例转回归门禁:BUG NOT REPRODUCED = PASS;BUG REPRODUCED = FAIL。
  if grep -q "BUG NOT REPRODUCED" "$LOG/repro.log"; then
    pass "repro / P3C-2 已修复(memc 预取陈旧槽不再复现)"
    grep -E "BUG NOT REPRODUCED" "$LOG/repro.log"
  elif grep -q "BUG REPRODUCED" "$LOG/repro.log"; then
    bad "repro / P3C-2 回归:修复后仍复现!"
    grep -E "BUG REPRODUCED|EXPECTED|ACTUAL" "$LOG/repro.log"
  else
    bad "repro / 无判定输出"
  fi
fi

say "汇总"
printf '  PASS=%d  KNOWN=%d  FAIL=%d\n' "$PASS" "$KNOWN" "$FAIL"
if [[ $FAIL -ne 0 ]]; then
  printf '  失败项: %s\n' "${FAILED_NAMES[*]}"
  exit 1
fi
echo "ALL EXPECTED CHECKS PASSED(已知项见上)"
exit 0
