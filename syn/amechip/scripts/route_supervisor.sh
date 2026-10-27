#!/bin/bash
# route_supervisor.sh — 监护 route+finish 链(WSL 会重启, make 从缓存步骤续跑)
R=/home/zcz/verda/autoDecodeChip/pnr/amechip/results/sky130hd/amechip/p4a2
LOG=/tmp/p4a2_route_supervisor.log
cd /home/zcz/tools/openroad-flow-scripts/flow
source ../env.sh >/dev/null 2>&1
for i in $(seq 1 40); do
  if [ -f "$R/6_final.gds" ] && [ -f "$R/6_final.spef" ]; then
    echo "$(date +%H:%M:%S) DONE" >> $LOG; exit 0
  fi
  echo "$(date +%H:%M:%S) attempt $i start" >> $LOG
  make DESIGN_CONFIG=/home/zcz/verda/autoDecodeChip/syn/amechip/config.mk \
       WORK_HOME=/home/zcz/verda/autoDecodeChip/pnr/amechip \
       FLOW_VARIANT=p4a2 ABC_AREA=0 "RTLMP_ARGS=-target_util 0.95" route finish >> $LOG 2>&1
  echo "$(date +%H:%M:%S) attempt $i exit=$?" >> $LOG
  sleep 20
done
