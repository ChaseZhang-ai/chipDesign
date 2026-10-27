# -----------------------------------------------------------------------------
# sta_blocks.tcl — 按模块分组的关键路径(P4A0;P1BX-B 后复用)
#
# 全芯片 top-N 会被"行为级存储器→FF 阵列"的巨大 fanout 假路径占满
# (例如 OCRAM 1024 个 flop 共享一个 mux 选择,零缓冲下 40 ns)。本脚本按
# 模块分组报告,把逻辑路径与存储阵列扇出分开。
#
# 注:OpenSTA report_checks 原生支持 "> file" 重定向,故不需要 tee。
# -----------------------------------------------------------------------------

set results_dir $::env(RESULTS_DIR)
set reports_dir $::env(REPORTS_DIR)

if { [info exists ::env(LIB_FILES)] && $::env(LIB_FILES) ne "" } {
  foreach lib $::env(LIB_FILES) { read_liberty $lib }
} else {
  read_liberty $::env(PLATFORM_DIR)/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
}
read_db $results_dir/1_synth.odb
read_sdc $results_dir/1_synth.sdc

set rf {slew cap input_pins fanout}

# ---- AME(含 buffer/array/requant 终点) ----
set cells_ame [get_cells -hierarchical -filter {name =~ *u_ame*}]
report_checks -path_delay max -to $cells_ame -group_path_count 20 \
  -endpoint_path_count 20 -fields $rf -format full_clock_expanded -digits 3 \
  > $reports_dir/p4a0_paths_ame.rpt

# ---- Y 寄存器 → AME 输出(requant 链) ----
set cells_y [get_cells -hierarchical -filter {name =~ *u_array*y_rdata_o*}]
report_checks -path_delay max -from $cells_y -group_path_count 20 \
  -endpoint_path_count 20 -fields $rf -format full_clock_expanded -digits 3 \
  > $reports_dir/p4a0_paths_y_requant.rpt

# ---- CPU ----
set cells_cpu [get_cells -hierarchical -filter {name =~ *u_cpu*}]
report_checks -path_delay max -to $cells_cpu -group_path_count 20 \
  -endpoint_path_count 20 -fields $rf -format full_clock_expanded -digits 3 \
  > $reports_dir/p4a0_paths_cpu.rpt

# ---- 存储控制逻辑(排除 OCRAM/BOOTROM/FIFO 存储阵列终点) ----
set cells_mem [get_cells -hierarchical -filter {name =~ *u_mem* && name !~ *u_ocram* && name !~ *u_bootrom* && name !~ *fifo_mem*}]
report_checks -path_delay max -to $cells_mem -group_path_count 20 \
  -endpoint_path_count 20 -fields $rf -format full_clock_expanded -digits 3 \
  > $reports_dir/p4a0_paths_memctrl.rpt

# ---- 主要控制器 ----
foreach {tag pat} {
  xbar  *u_xbar*
  dma   *u_dma*
  kv    *u_kvc*
  memc  *u_memc*
  uart  *u_uart*
  sys   *u_sys*
  intc  *u_intc*
} {
  set cells_x [get_cells -hierarchical -filter "name =~ $pat"]
  if { [llength $cells_x] > 0 } {
    report_checks -path_delay max -to $cells_x -group_path_count 20 \
      -endpoint_path_count 20 -fields $rf -format full_clock_expanded -digits 3 \
      > $reports_dir/p4a0_paths_${tag}.rpt
  }
}

puts "== block reports done =="
