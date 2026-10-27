#!/bin/bash
# run_p4a3fin_sta_chain.sh — P4A3 三口径签核 STA 链(7.576 冲刺存档 / 10ns=100MHz / 实达 fmax)
# 用法: bash run_p4a3fin_sta_chain.sh <fmax_period_ns>
# 产出: p4a3fin_sdc7576_* / p4a3fin_100m_* / p4a3fin_fmax_* 报告组
set -eu
FMAX_P="${1:?usage: run_p4a3fin_sta_chain.sh <fmax_period_ns>}"
source /home/zcz/tools/openroad-flow-scripts/env.sh >/dev/null 2>&1
PLATFORM_DIR=/home/zcz/tools/openroad-flow-scripts/flow/platforms/sky130hd
export PLATFORM_DIR
export RESULTS_DIR=/home/zcz/verda/autoDecodeChip/pnr/amechip/results/sky130hd/amechip/p4a3fin
export REPORTS_DIR=/home/zcz/verda/autoDecodeChip/pnr/amechip/reports/sky130hd/amechip/p4a3fin
export LIB_FILES="$PLATFORM_DIR/lib/sky130_fd_sc_hd__tt_025C_1v80.lib $PLATFORM_DIR/../sky130ram/sky130_sram_1rw1r_128x256_8/sky130_sram_1rw1r_128x256_8_TT_1p8V_25C.lib"
TCL=/home/zcz/verda/autoDecodeChip/syn/amechip/scripts/sta_final.tcl
cd /home/zcz/tools/openroad-flow-scripts/flow
AME_RPT_PREFIX=p4a3fin_sdc7576 AME_SIGNOFF_PERIOD=7.576 openroad -no_init -exit $TCL > /tmp/p4a3fin_sta_7576.log 2>&1
echo "sdc7576 exit=$?"
AME_RPT_PREFIX=p4a3fin_100m AME_SIGNOFF_PERIOD=10.0 openroad -no_init -exit $TCL > /tmp/p4a3fin_sta_10ns.log 2>&1
echo "100m exit=$?"
AME_RPT_PREFIX=p4a3fin_fmax AME_SIGNOFF_PERIOD=$FMAX_P openroad -no_init -exit $TCL > /tmp/p4a3fin_sta_fmax.log 2>&1
echo "fmax($FMAX_P) exit=$?"
echo ALL_STA_DONE
