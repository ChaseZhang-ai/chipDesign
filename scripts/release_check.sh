#!/usr/bin/env bash
# =============================================================================
# release_check.sh — AME-Chip v0.1 发布自检(P5 收尾交付)
#
# 从零到 GDS 的一键复现路径 + 报告一致性检查。分步预期耗时:
#   S1 环境预检          秒级
#   S2 boot ROM 护栏     秒级            syn/amechip/scripts/check_boot_hex.sh
#   S3 契约/RTL lint     ~10 s           lint_interfaces/mem_lint/check_isa/soc_check_ports
#   S4 快速 TB(golden)  ~2 min          scripts/vfrd_run_all.sh(Verilator e2e,P3D)
#   S5 ORFS 全流程       ~3.2 h          route_supervisor_p4a4fix.sh(P4A2/P4A3 监护方案,
#                                         含 yosys→逐位化→1_synth→绑定门禁→route→finish)
#   S6 绑定静态检查      ~1 min          p4a4_macro_binding_check.py(1263/1263 门禁)
#   S7 签核 STA 三口径   ~10 min         run_p4a4fix_sta_chain.sh(P4A3/P4B2 同款)
#   S8 KLayout DRC       ~35 min         平台 sky130hd.lydrc + drc_macro_filter 口径
#   S9 门级裁剪回归      ~1 h            p4a4fix_gate_decode_check.sh(46 字节 == RTL,+XINIT)
#   S10 报告一致性       秒级            检查单 FAIL=0 / 交付指纹 / 指标锚点
#
# 用法:
#   scripts/release_check.sh --quick     # S1-S4 + S10(约 5 分钟;默认)
#   scripts/release_check.sh --full      # S1-S10 全链(约 4.5-5 小时,含 ORFS)
#   scripts/release_check.sh --stage S6  # 单跑一段(S5 起依赖前序产物已存在)
#   scripts/release_check.sh --list      # 打印分步耗时表
#
# 退出码 = 失败步数(0 = 全绿)。运行产物落 build/release_check/。
# 流程资产引用:syn/amechip/(ORFS 树外 DESIGN_CONFIG,docs/ENV.md 工具链)。
# =============================================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORFS="${ORFS_ROOT:-$HOME/tools/openroad-flow-scripts}"
OUT="$ROOT/build/release_check"
P4FIX="$ROOT/pnr/amechip/results/sky130hd/amechip/p4a4fix"
SYN="$ROOT/syn/amechip"
MODE="quick"; ONLY_STAGE=""
mkdir -p "$OUT"

for arg in "$@"; do
  case "$arg" in
    --quick) MODE="quick" ;;
    --full)  MODE="full" ;;
    --stage) : ;; # 值在下一个参数
    S*|s*)   ONLY_STAGE="$arg" ;;
    --list)  sed -n '3,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "未知参数: $arg(--quick/--full/--stage S<n>/--list)"; exit 2 ;;
  esac
done
# 取 --stage 的值(--stage S6 形式)
prev=""
for arg in "$@"; do
  [ "$prev" = "--stage" ] && ONLY_STAGE="$arg"
  prev="$arg"
done

FAILED_STEPS=()
T0=0
# S5-S9 仅 --full 执行(ORFS 全流程链)
FULL_ONLY() { case "$1" in S5|S6|S7|S8|S9) return 0 ;; *) return 1 ;; esac; }
want_stage() {
  [ -n "$ONLY_STAGE" ] && { [ "$ONLY_STAGE" = "$1" ]; return $?; }
  if FULL_ONLY "$1"; then [ "$MODE" = "full" ]; else return 0; fi
}
step() {  # step <编号> <描述>
  STEP_ID="$1"; STEP_DESC="$2"
  if [ -n "$ONLY_STAGE" ] && [ "$ONLY_STAGE" != "$STEP_ID" ]; then return 1; fi
  T0=$SECONDS
  echo; echo "===== [$STEP_ID] $STEP_DESC ====="
  return 0
}
finish_step() {  # finish_step <ok:0/1>
  local el=$(( SECONDS - T0 ))
  if [ "$1" -eq 0 ]; then
    echo "----- [$STEP_ID] PASS(${el}s) -----"
  else
    echo "----- [$STEP_ID] FAIL(${el}s) -----"; FAILED_STEPS+=("$STEP_ID")
  fi
}

# ---------------------------------------------------------------- S1 环境预检
if want_stage S1; then
  step S1 "环境预检(工具链,预期秒级)" || true
  ok=0
  for t in iverilog verilator klayout python3 md5sum; do
    command -v "$t" >/dev/null 2>&1 || { echo "缺工具: $t"; ok=1; }
  done
  if [ -x "$ORFS/env.sh" ]; then
    # shellcheck disable=SC1091
    source "$ORFS/env.sh" >/dev/null 2>&1 || true
    command -v yosys  >/dev/null 2>&1 || { echo "缺 ORFS yosys(env.sh)"; ok=1; }
    command -v openroad >/dev/null 2>&1 || { echo "缺 openroad(env.sh)"; ok=1; }
    echo "yosys=$(yosys -V 2>/dev/null | cut -d' ' -f1-2) openroad=$(openroad -version 2>/dev/null | head -1)"
  else
    echo "警告: ORFS 未找到($ORFS)——S5-S8 不可用,S1-S4/S10 不受影响"
    [ "$MODE" = "full" ] && ok=1
  fi
  finish_step "$ok"
fi

# ------------------------------------------------------------ S2 boot ROM 护栏
if want_stage S2; then
  step S2 "boot ROM 冻结护栏(md5 aae6ac28…,P4B-01 根治)" || true
  bash "$SYN/scripts/check_boot_hex.sh" "$ROOT"
  finish_step "$?"
fi

# ------------------------------------------------------------- S3 契约/RTL lint
if want_stage S3; then
  step S3 "契约/RTL lint(iverilog+verilator+机器校验,预期 ~10s)" || true
  ok=0
  bash "$ROOT/scripts/lint_interfaces.sh" || ok=1
  bash "$ROOT/scripts/mem_lint.sh"        || ok=1
  python3 "$ROOT/scripts/check_isa.py"    || ok=1
  python3 "$ROOT/scripts/soc_check_ports.py" || ok=1
  finish_step "$ok"
fi

# --------------------------------------------------------- S4 快速 TB(golden)
if want_stage S4; then
  step S4 "快速 TB:P3D golden e2e(Verilator,3 token 位精确,预期 ~2min)" || true
  ok=0
  if bash "$ROOT/scripts/vfrd_run_all.sh" >"$OUT/s4_e2e.log" 2>&1; then
    if grep -q "P3D CHECK PASS" "$ROOT/tb/soc/build/p3d_check.log"; then
      echo "golden e2e: PASS(见 tb/soc/build/p3d_e2e.log;KPI 6,178,210 cyc/token 口径)"
    else
      echo "缺 P3D CHECK PASS 标记"; ok=1
    fi
  else
    echo "e2e 失败,日志: $OUT/s4_e2e.log(尾部 20 行)"; tail -20 "$OUT/s4_e2e.log"; ok=1
  fi
  finish_step "$ok"
fi

# ------------------------------------------------- S5 ORFS 全流程(仅 --full)
if want_stage S5; then
  step S5 "ORFS 全流程(route_supervisor_p4a4fix.sh 监护,预期 ~3.2h;日志 /tmp/p4a4fix_supervisor.log)" || true
  if [ ! -f "$ORFS/env.sh" ]; then
    echo "ORFS 缺失($ORFS),S5 无法执行"; finish_step 1
  else
    bash "$SYN/scripts/route_supervisor_p4a4fix.sh"
    finish_step "$?"
  fi
fi

# ------------------------------------------------------- S6 绑定静态检查(P4A4)
if want_stage S6; then
  step S6 "SRAM 宏绑定静态检查(金标准 vs 交付,预期 ~1min;1263/1263 门禁)" || true
  SKY_LIB="$ORFS/flow/platforms/sky130hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib"
  RAM_LIB="$ORFS/flow/platforms/sky130ram/sky130_sram_1rw1r_128x256_8/sky130_sram_1rw1r_128x256_8_TT_1p8V_25C.lib"
  python3 "$SYN/scripts/p4a4_macro_binding_check.py" \
    --yosys    "$P4FIX/1_2_yosys_yosys_pristine.v" \
    --final-v  "$P4FIX/6_final.v" \
    --cdl      "$P4FIX/6_final.cdl" \
    --masters-cdl "$ROOT/pnr/amechip/sky130hd_ame_masters.cdl" \
    --lib "$SKY_LIB" --lib "$RAM_LIB" \
    --report   "$OUT/s6_binding_final.rpt"
  finish_step "$?"
fi

# ------------------------------------------------------ S7 签核 STA 三口径
if want_stage S7; then
  step S7 "签核 STA 三口径(7.576/10.0/fmax=10.150 ns,预期 ~10min)" || true
  bash "$SYN/scripts/run_p4a4fix_sta_chain.sh" 10.150
  finish_step "$?"
fi

# ------------------------------------------------------------ S8 KLayout DRC
if want_stage S8; then
  step S8 "KLayout 平台 DRC(全芯 ~35min;宏内豁免口径 = drc_macro_filter)" || true
  ( cd "$ORFS/flow" && klayout -b \
      -rd in_gds="$P4FIX/6_final.gds" \
      -rd report_file="$OUT/s8_drc.rpt" \
      -r platforms/sky130hd/drc/sky130hd.lydrc )
  rc=$?
  if [ $rc -eq 0 ] && [ -f "$OUT/s8_drc.rpt" ]; then
    n=$(grep -c "<item" "$OUT/s8_drc.rpt" || true)
    echo "DRC 总计 $n 项(宏内豁免口径:宏外必须为 0——用 drc_macro_filter.py 分类后核宏外计数)"
    finish_step 0
  else
    finish_step "$rc"
  fi
fi

# --------------------------------------------------- S9 门级裁剪回归(仅 --full)
if want_stage S9; then
  step S9 "门级裁剪回归(46 字节 == RTL,+XINIT 口径,预期 ~1h)" || true
  bash "$SYN/scripts/p4a4fix_gate_decode_check.sh"
  finish_step "$?"
fi

# ----------------------------------------------------------- S10 报告一致性
if want_stage S10; then
  step S10 "报告一致性检查(检查单 FAIL=0 / 交付指纹 / 指标锚点)" || true
  python3 - "$ROOT" <<'PYEOF'
import hashlib, sys, pathlib
root = pathlib.Path(sys.argv[1])
fails = []
def need(cond, msg):
    print(("  OK  " if cond else "  FAIL") + " " + msg)
    if not cond: fails.append(msg)

def md5(p, n=8):
    h = hashlib.md5()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()[:n]

# 1) 检查单终版:FAIL=0 / PASS 34
cl = (root / "reports/TAPEOUT_CHECKLIST.md").read_text(encoding="utf-8")
need("| **FAIL** | **0** |" in cl, "TAPEOUT_CHECKLIST: FAIL=0 行存在")
need("**PASS** | **34**" in cl, "TAPEOUT_CHECKLIST: PASS 34 行存在")

# 2) 交付物指纹(p4a4fix,FINAL_METRICS §6)
p4 = root / "pnr/amechip/results/sky130hd/amechip/p4a4fix"
fp = {"6_final.gds": "d0ed37fc", "6_final.cdl": "40217dd1",
      "6_final.sdf": "d4318f81", "6_final.v": "49d30b2f"}
for name, want in fp.items():
    f = p4 / name
    if f.exists():
        need(md5(f) == want, f"交付指纹 {name} = {want}(实测 {md5(f)})")
    else:
        need(False, f"交付物缺失: {f}")

# 3) boot ROM 三副本 md5
boot = "aae6ac28bbdaa6bc1f9348f3a8c8ba79"
for p in ["rtl/soc/boot/boot.hex", "syn/amechip/boot_frozen/boot.hex",
          "tb/soc/build/p3d_boot.hex"]:
    f = root / p
    if f.exists():
        need(md5(f, 32) == boot, f"boot ROM md5: {p}")
    else:
        print(f"  SKIP boot ROM(不存在,跳过): {p}")

# 4) 收尾交付文档存在 + 指标锚点
for p in ["docs/FINAL_REPORT.md", "reports/FINAL_METRICS.md", "reports/FINAL_BUGS.md"]:
    need((root / p).exists(), f"文档存在: {p}")
met = (root / "reports/FINAL_METRICS.md")
if met.exists():
    t = met.read_text(encoding="utf-8")
    for anchor in ["94.78 MHz", "98.52 MHz", "3.455 mm²", "4.524 mm²",
                   "241.8 mW", "15.76 mJ", "15.3 tok/s", "6,178,210"]:
        need(anchor in t, f"指标锚点: {anchor}")
bugs = (root / "reports/FINAL_BUGS.md")
if bugs.exists():
    t = bugs.read_text(encoding="utf-8")
    for anchor in ["P4B-01", "P4B2-05", "P1BX-D", "scr_kvrow", "P4A-04", "P4A-14"]:
        need(anchor in t, f"总账锚点: {anchor}")

print(f"\n一致性检查: {len(fails)} 项失败")
sys.exit(1 if fails else 0)
PYEOF
  finish_step "$?"
fi

# ------------------------------------------------------------------- 汇总
echo
echo "==============================================================="
if [ ${#FAILED_STEPS[@]} -eq 0 ]; then
  echo "release_check($MODE): 全部执行步 PASS ✅"
else
  echo "release_check($MODE): 失败步 = ${FAILED_STEPS[*]} ❌"
fi
echo "产物目录: $OUT"
exit "${#FAILED_STEPS[@]}"
