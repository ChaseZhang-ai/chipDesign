# -----------------------------------------------------------------------------
# export_sdf.tcl — 从 ORFS 终版 6_final 导出 SDF(P4A 任务 5)
#
# ORFS 默认不产 SDF(P4READY §4.1 已核实);P4B 时序反标门仿必需。
# 用法(在 flow/ 目录,env.sh 已 source):
#   openroad -exit syn/amechip/scripts/export_sdf.tcl
# 环境变量(由 export_sdf.sh 传入):
#   AME_RESULT_DIR  — ORFS results/<plat>/<design>/<variant>/ 目录
#   AME_SDF_OUT     — 输出 SDF 路径
# -----------------------------------------------------------------------------
foreach lib [list $::env(HOME)/tools/openroad-flow-scripts/flow/platforms/sky130hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib \
              $::env(HOME)/tools/openroad-flow-scripts/flow/platforms/sky130ram/sky130_sram_1rw1r_128x256_8/sky130_sram_1rw1r_128x256_8_TT_1p8V_25C.lib] {
  read_liberty $lib
}
read_db $::env(AME_RESULT_DIR)/6_final.odb

# RC:6_report 步已用 OpenRCX 抽取(6_final.spef),读入后再写 SDF 保证延迟含真实寄生
read_spef $::env(AME_RESULT_DIR)/6_final.spef

write_sdf -divider / $::env(AME_SDF_OUT)

puts "SDF written: $::env(AME_SDF_OUT)"
