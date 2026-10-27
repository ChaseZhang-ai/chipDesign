#!/bin/bash
# p4a4 三口径签核 STA 链(11.82 签核 / 12.093 实测fmax / 7.576 实现口径副本)
source /home/zcz/tools/openroad-flow-scripts/env.sh >/dev/null 2>&1
PLATFORM_DIR=/home/zcz/tools/openroad-flow-scripts/flow/platforms/sky130hd
export PLATFORM_DIR
export RESULTS_DIR=/home/zcz/verda/autoDecodeChip/pnr/amechip/results/sky130hd/amechip/p4a4
export REPORTS_DIR=/home/zcz/verda/autoDecodeChip/pnr/amechip/reports/sky130hd/amechip/p4a4
export LIB_FILES="$PLATFORM_DIR/lib/sky130_fd_sc_hd__tt_025C_1v80.lib $PLATFORM_DIR/../sky130ram/sky130_sram_1rw1r_128x256_8/sky130_sram_1rw1r_128x256_8_TT_1p8V_25C.lib"
TCL=/home/zcz/verda/autoDecodeChip/syn/amechip/scripts/sta_final.tcl
cd /home/zcz/tools/openroad-flow-scripts/flow
AME_RPT_PREFIX=p4a4_signoff AME_SIGNOFF_PERIOD=11.820 openroad -no_init -exit $TCL > /tmp/p4a4_sta_1182.log 2>&1
echo "signoff exit=$?"
AME_RPT_PREFIX=p4a4_fmax82p7 AME_SIGNOFF_PERIOD=12.093 openroad -no_init -exit $TCL > /tmp/p4a4_sta_fmax.log 2>&1
echo "fmax82p7 exit=$?"
AME_RPT_PREFIX=p4a4_sdc7576 AME_SIGNOFF_PERIOD=7.576 openroad -no_init -exit $TCL > /tmp/p4a4_sta_7576.log 2>&1
echo "sdc7576 exit=$?"
echo ALL_STA_DONE
