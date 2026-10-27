# -----------------------------------------------------------------------------
# pdn_amechip.tcl — AME-Chip PDN 包装(P4A, 第 3 版)
#
# 平台 sky130hd/pdn.tcl 的 add_global_connection 只匹配 VPWR/VGND/VDD/VSS,
# 而 sky130ram 宏的电源引脚是小写 vdd/gnd(LEF 已核实)。
# 顺序:必须**先注册**宏电源连接再 source 平台——平台文件里的 global_connect
# 会应用所有已注册连接;文件尾部再补一次 global_connect 兜底。
#
# v3 变更(P4A 第 3 轮迭代, 根治 PSM-0069):
#   删除 v2 加在宏网格上的 add_pdn_connect met3/met4——该宏的电源引脚是
#   3358/2992 个 0.49um met3 焊盘(两网交错散布), pdn 的 connect 会按格点在
#   宏上方生成整片 via3 阵列: 落在空处的 met3 包围金属成孤岛(PSM Unconnected
#   上万), 落在异网焊盘上即 VDD-VSS 短路(前两轮 516x3 处 Shorts 的根因)。
#   宏供电改由 POST_PDN_TCL(scripts/pdn_macro_fix.tcl)按衍生 LEF 的 met4
#   电源条 + 焊盘精准 via3 完成(见 gen_macro_lef.py 头注)。宏网格保持平台
#   默认(仅 met4-met5 缝合)。
# -----------------------------------------------------------------------------

add_global_connection -net {VDD} -inst_pattern {.*} -pin_pattern {^vdd$} -power
add_global_connection -net {VSS} -inst_pattern {.*} -pin_pattern {^gnd$} -ground

source $::env(PLATFORM_DIR)/pdn.tcl

# 须在网格定义之后调用(只作用于已存在的 grid), pdngen 由 ORFS 在本文件
# source 完后执行: 宏左翼 ~2um followpin 残段修复不了, 放宽为 PDN-0178 警告,
# 残段由 POST_PDN_TCL 删除并 blockage。
pdn::allow_repair_channels 1

global_connect
