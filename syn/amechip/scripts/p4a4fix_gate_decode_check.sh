#!/bin/bash
# p4a4fix_gate_decode_check.sh — P4A4 修复网表门级裁剪场景自验(P4B2-05 回归判据)
# 用 p4a4fix 的 6_final.v(逐位化后)跑 tb/gate 的 p4b2_decode 场景,
# UART 46 字节须与 RTL 参照 uart_p4b2_rtl.bin 逐字节一致。
# 只读引用 tb/gate(TB 与场景镜像),产物全部落 pnr/amechip/logs/.../p4a4fix_gatesim/。
set -eu
R=/home/zcz/verda/autoDecodeChip/pnr/amechip/results/sky130hd/amechip/p4a4fix
OUT=/home/zcz/verda/autoDecodeChip/pnr/amechip/logs/sky130hd/amechip/p4a4fix_gatesim
REF=/home/zcz/verda/autoDecodeChip/tb/gate/build/uart_p4b2_rtl.bin
TB=/home/zcz/verda/autoDecodeChip/tb/gate
M=/home/zcz/.volare/volare/sky130/versions/c6d73a35f524070e85faff4a6a9eef49553ebc2b/sky130A/libs.ref/sky130_fd_sc_hd/verilog
RAM=$HOME/tools/openroad-flow-scripts/flow/platforms/sky130ram/sky130_sram_1rw1r_128x256_8
N=$R/6_final.v

mkdir -p "$OUT"
cd "$TB"
iverilog -g2012 -DFUNCTIONAL -s tb_gate_decode -o "$OUT/p4a4fix_gate.vvp" \
  "$N" "$M/sky130_fd_sc_hd.v" "$M/primitives.v" "$RAM/sky130_sram_1rw1r_128x256_8.v" \
  tb_gate_decode.sv > "$OUT/compile.log" 2>&1
cd "$OUT"
vvp p4a4fix_gate.vvp +UART_BIN=uart_p4a4fix_gate.bin +XMEM_HEX="$TB/build/p4b2_scene.hex" \
  > p4a4fix_gate.log 2>&1

if cmp -s uart_p4a4fix_gate.bin "$REF"; then
  echo "GATESIM PASS: 46 字节与 RTL 参照逐字节一致"
  echo "P4A4FIX_GATESIM_PASS" >> p4a4fix_gate.log
  exit 0
else
  echo "GATESIM FAIL: UART 输出与 RTL 参照不一致"
  echo "gate:"; xxd uart_p4a4fix_gate.bin | head -4
  echo "rtl ref:"; xxd "$REF" | head -4
  exit 1
fi
