#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# ame_synth_est.sh — AME 面积/时序粗估(P2B)
#
# yosys synth(通用工艺,门数数量级)+ sky130hd liberty 下的 abc 时序检查
# (120 MHz → 8.33 ns 周期)。仅 AME 核心(ame_core),不含 pad/时钟树。
# 注:yosys 前端对 rtl/amechip_pkg.sv(冻结契约)的 return 表达式解析有缺陷,
#     综合前生成语义等价的预处理副本置于 tb/ame/work/syn/inc(仅综合用)。
# 用法: bash scripts/ame_synth_est.sh
# -----------------------------------------------------------------------------
set -eu

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$HOME/tools/openroad-flow-scripts/flows/platforms/sky130hd/sky130hd_tt.lib"
if [ ! -f "$LIB" ]; then
  LIB="$HOME/tools/openroad-flow-scripts/tools/OpenROAD/test/sky130hd/sky130hd_tt.lib"
fi

SRC="rtl/ame/ame_core.sv rtl/ame/ame_ctrl.sv rtl/ame/ame_array.sv \
     rtl/ame/ame_buf_rf.sv rtl/ame/ame_requant.sv rtl/ame/ame_rqtab.sv"
OUT="$ROOT/tb/ame/work/syn"

cd "$ROOT"
mkdir -p "$OUT/inc"

python3 - <<'PYEOF'
import re
src = open("rtl/amechip_pkg.sv").read()
m = re.search(r"function automatic logic \[31:0\] kv_off.*?endfunction", src, re.S)
one = (
"  function automatic logic [31:0] kv_off (\n"
"    input logic        layer,\n"
"    input logic        k_v,\n"
"    input logic [1:0]  head,\n"
"    input logic [8:0]  pos,\n"
"    input logic [5:0]  byte_idx\n"
"  );\n"
"    logic [31:0] t_l, t_kv, t_h, t_p;\n"
"    t_l  = layer ? 32'h0002_0000 : 32'h0000_0000;\n"
"    t_kv = k_v   ? 32'h0001_0000 : 32'h0000_0000;\n"
"    t_h  = 32'h0000_4000 * {30'h0, head};\n"
"    t_p  = 32'd64 * {23'h0, pos};\n"
"    kv_off = t_l + t_kv + t_h + t_p + {26'h0, byte_idx};\n"
"  endfunction")
two_re = re.search(r"function automatic logic \[31:0\] w_layer_off.*?endfunction", src, re.S)
cases = re.findall(r"(4'd\d+|default):\s*return (32'h[0-9A-Fa-f_]+);", two_re.group(0))
lines = ["  function automatic logic [31:0] w_layer_off (input logic [3:0] idx);",
         "    case (idx)"]
for sel, val in cases:
    lines.append("      %s: w_layer_off = %s;" % (sel, val))
lines.append("    endcase")
lines.append("  endfunction")
out = src.replace(m.group(0), one).replace(two_re.group(0), "\n".join(lines))
open("tb/ame/work/syn/inc/amechip_pkg.sv", "w").write(out)
PYEOF
PKGFLAG="-I $OUT/inc"

echo "== [1/3] 通用 synth(面积数量级)==="
yosys -p "
read_verilog -sv $PKGFLAG -Irtl -Irtl/interfaces $SRC;
hierarchy -top ame_core;
synth -top ame_core -flatten;
stat" > "$OUT/synth_generic.log" 2>&1
grep -a "Number of cells" "$OUT/synth_generic.log"
grep -aE "^ +\\\$" "$OUT/synth_generic.log" | sort -k2 -n -r | head -12

echo "== [2/3] sky130hd 映射 + abc @8.33ns(120MHz)==="
if [ -f "$LIB" ]; then
  yosys -p "
read_verilog -sv $PKGFLAG -Irtl -Irtl/interfaces $SRC;
hierarchy -top ame_core;
synth -top ame_core -flatten;
dfflibmap -liberty $LIB;
abc -liberty $LIB -D 8333;
setundef -zero;
splitnets -ports;
clean;
write_verilog -noattr $OUT/ame_core_mapped.v;
stat -liberty $LIB" > "$OUT/synth_sky130hd.log" 2>&1
  grep -a "Chip area for module" "$OUT/synth_sky130hd.log"
  grep -aE "ABC: .*(Delay|results)" -A 6 "$OUT/synth_sky130hd.log" | head -12
  grep -aE "^ +sky130_fd_sc_" "$OUT/synth_sky130hd.log" | sort -k2 -n -r | head -10
else
  echo "sky130hd liberty 未找到,跳过映射"
fi

echo "== [3/3] 关键路径逻辑深度参考 =="
yosys -p "
read_verilog -sv $PKGFLAG -Irtl -Irtl/interfaces $SRC;
hierarchy -top ame_core;
synth -top ame_core -flatten;
aigmap;
ltp" > "$OUT/ltp.log" 2>&1
grep -a "Longest topological path" -A 3 "$OUT/ltp.log" | head -6

echo "== [4/4] OpenROAD STA @8.333ns(映射后网表)==="
if [ -x "$HOME/tools/openroad-flow-scripts/tools/install/OpenROAD/bin/openroad" ] && [ -f "$OUT/ame_core_mapped.v" ]; then
  "$HOME/tools/openroad-flow-scripts/tools/install/OpenROAD/bin/openroad" -no_init -exit > "$OUT/sta.log" 2>&1 <<EOFSTA
read_liberty $LIB
read_verilog $OUT/ame_core_mapped.v
link_design ame_core
create_clock -name clk_i -period 8.333 {clk_i}
set_input_delay 0.0 -clock clk_i *
set_output_delay 0.0 -clock clk_i *
report_worst_slack -max
report_checks -path_delay max -group_count 3 -format summary
EOFSTA
  grep -aE "worst slack|max|VIOLATED|MET" "$OUT/sta.log" | head -10
else
  echo "openroad 或映射网表缺失,跳过 STA"
fi

echo "完成:日志见 tb/ame/work/syn/"
