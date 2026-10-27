#!/bin/bash
# route_supervisor_p4a3.sh — P4A2 复跑监护(WSL 会重启, make 从缓存步骤自动续跑)
# 与首轮 route_supervisor.sh 同方案,variant 换 p4a3(ROM 冻结 + 84.6MHz SDC)。
R=/home/zcz/verda/autoDecodeChip/pnr/amechip/results/sky130hd/amechip/p4a3
LOG=/tmp/p4a3_route_supervisor.log
cd /home/zcz/tools/openroad-flow-scripts/flow
source ../env.sh >/dev/null 2>&1
for i in $(seq 1 40); do
  if [ -f "$R/6_final.gds" ] && [ -f "$R/6_final.spef" ]; then
    echo "$(date +%H:%M:%S) DONE" >> $LOG; exit 0
  fi
  echo "$(date +%H:%M:%S) attempt $i start" >> $LOG
  make DESIGN_CONFIG=/home/zcz/verda/autoDecodeChip/syn/amechip/config.mk \
       WORK_HOME=/home/zcz/verda/autoDecodeChip/pnr/amechip \
       FLOW_VARIANT=p4a3 ABC_AREA=0 "RTLMP_ARGS=-target_util 0.95" route finish >> $LOG 2>&1
  echo "$(date +%H:%M:%S) attempt $i exit=$?" >> $LOG
  sleep 20
done
