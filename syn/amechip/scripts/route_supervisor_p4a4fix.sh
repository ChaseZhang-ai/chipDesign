#!/bin/bash
# route_supervisor_p4a4fix.sh — P4A4 修复版交付链(P4B2-05 SRAM 宏位序反转修复)
#
# 序列:yosys(SYNTH_USE_SYN)→ 逐位化改写(留 pristine 存档)→ synth_odb →
#       绑定门禁(checker,FAIL 即中止)→ route finish(断点续跑)→
#       终局交付后处理(6_final.v 逐位化 + final/CDL 门禁,由 export 脚本单独跑)
# 配方与 p4a3fin 完全一致(ABC_AREA=0 / RTLMP target_util 0.95 / ROM md5 护栏)。
R=/home/zcz/verda/autoDecodeChip/pnr/amechip/results/sky130hd/amechip/p4a4fix
RP=/home/zcz/verda/autoDecodeChip/pnr/amechip/reports
SYN=/home/zcz/verda/autoDecodeChip/syn/amechip
LOG=/tmp/p4a4fix_supervisor.log
GATE1=$RP/sky130hd/amechip/p4a4fix_binding_synth.rpt
GATE2=$RP/sky130hd/amechip/p4a4fix_binding_final.rpt
OPENROAD_BIN=/home/zcz/tools/openroad-flow-scripts/tools/install/OpenROAD/bin/openroad

cd /home/zcz/tools/openroad-flow-scripts/flow
source ../env.sh >/dev/null 2>&1
export RTLMP_ARGS="-target_util 0.95"

log() { echo "$(date +%H:%M:%S) $*" >> "$LOG"; }

if [ ! -f "$R/1_2_yosys.v" ]; then
  log "stage A: yosys (1_2_yosys.v 文件目标,自动含 canonicalize 链)"
  make DESIGN_CONFIG=$SYN/config.mk WORK_HOME=/home/zcz/verda/autoDecodeChip/pnr/amechip \
       FLOW_VARIANT=p4a4fix ABC_AREA=0 "$R/1_2_yosys.v" >> "$LOG" 2>&1 \
    || { log "yosys FAILED"; exit 1; }
fi

if [ ! -f "$R/1_2_yosys_yosys_pristine.v" ]; then
  log "stage B: bitblast in place (pristine archived)"
  cp "$R/1_2_yosys.v" "$R/1_2_yosys_yosys_pristine.v"
  python3 $SYN/scripts/p4a4_bitblast_macro_conns.py "$R/1_2_yosys.v" --order msb_first \
    >> "$LOG" 2>&1 || { log "bitblast FAILED"; exit 1; }
fi

if [ ! -f "$R/1_synth.odb" ]; then
  log "stage C: synth_odb (1_synth.odb 文件目标,自动含 1_2_yosys.sdc)"
  make DESIGN_CONFIG=$SYN/config.mk WORK_HOME=/home/zcz/verda/autoDecodeChip/pnr/amechip \
       FLOW_VARIANT=p4a4fix ABC_AREA=0 "$R/1_synth.odb" >> "$LOG" 2>&1 \
    || { log "synth_odb FAILED"; exit 1; }
fi

if [ ! -f "$GATE1" ]; then
  log "stage C2: binding gate @1_synth"
  python3 $SYN/scripts/p4a4_macro_binding_check.py \
    --yosys "$R/1_2_yosys_yosys_pristine.v" --odb "$R/1_synth.odb" \
    --openroad "$OPENROAD_BIN" \
    --report "$GATE1" >> "$LOG" 2>&1
  rc=$?
  [ $rc -ne 0 ] && { log "BINDING GATE FAILED rc=$rc — 阻止后续布线"; exit 1; }
  log "binding gate @1_synth PASS"
fi

if [ ! -f "$R/6_final.gds" ] || [ ! -f "$R/6_final.spef" ]; then
  log "stage D: route finish (loop)"
  for i in $(seq 1 40); do
    if [ -f "$R/6_final.gds" ] && [ -f "$R/6_final.spef" ]; then break; fi
    make DESIGN_CONFIG=$SYN/config.mk WORK_HOME=/home/zcz/verda/autoDecodeChip/pnr/amechip \
         FLOW_VARIANT=p4a4fix ABC_AREA=0 route finish >> "$LOG" 2>&1
    log "route attempt $i exit=$?"
    if [ -f "$R/6_final.gds" ] && [ -f "$R/6_final.spef" ]; then break; fi
    sleep 20
  done
fi

if [ -f "$R/6_final.gds" ] && [ -f "$R/6_final.spef" ]; then
  log "route DONE"
else
  log "route INCOMPLETE after loop"
fi

if [ -f "$R/6_final.v" ] && [ ! -f "$GATE2" ]; then
  log "stage E0: write CDL from 6_final.odb"
  if [ ! -f "$R/6_final.cdl" ]; then
    ORFS=/home/zcz/tools/openroad-flow-scripts
    CDLTCL=/tmp/p4a4fix_write_cdl.tcl
    cat > "$CDLTCL" <<EOF
read_db $R/6_final.odb
write_cdl -masters /home/zcz/verda/autoDecodeChip/pnr/amechip/sky130hd_ame_masters.cdl $R/6_final.cdl
puts CDL_OK
EOF
    $ORFS/tools/install/OpenROAD/bin/openroad -no_init -exit "$CDLTCL" >> "$LOG" 2>&1 \
      || { log "write_cdl FAILED"; exit 1; }
  fi
  log "stage E: binding gate @final(交付 6_final.v 保持 OpenROAD 原始标准拼接文本)"
  # 实测 write_verilog 输出为标准 MSB-first 拼接,ODB 正确时交付文本即为 IEEE 正确;
  # 且 .port[bit](net) 位选语法 iverilog 不支持,故交付网表不做逐位化。
  cp "$R/6_final.v" "$R/6_final_openroad_raw.v"
  python3 $SYN/scripts/p4a4_macro_binding_check.py \
    --yosys "$R/1_2_yosys_yosys_pristine.v" --final-v "$R/6_final.v" \
    --cdl "$R/6_final.cdl" --masters-cdl /home/zcz/verda/autoDecodeChip/pnr/amechip/sky130hd_ame_masters.cdl \
    --lib /home/zcz/tools/openroad-flow-scripts/flow/platforms/sky130hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib \
    --openroad "$OPENROAD_BIN" \
    --report "$GATE2" >> "$LOG" 2>&1 \
    && log "binding gate @final PASS" || log "BINDING GATE @final FAILED(检查 $GATE2)"
fi
log "supervisor exit"
