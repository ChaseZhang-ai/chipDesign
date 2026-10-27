# -----------------------------------------------------------------------------
# sta_detail.tcl — AME/CPU 细分路径(P4A0)
# 目的:全芯片 top-N 被 AME 窗口地址→响应路径占满;这里把 MAC lane、
# WBUF/XBUF 宽行读、总线读、requant 分开量化。
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

set c_array [get_cells -hierarchical -filter {name =~ *u_array*}]
set c_y     [get_cells -hierarchical -filter {name =~ *u_array*y_rdata_o*}]
set c_tile  [get_cells -hierarchical -filter {name =~ *u_array*tile_q*}]
set c_xq    [get_cells -hierarchical -filter {name =~ *u_array*x_q*}]
set c_wbuf  [get_cells -hierarchical -filter {name =~ *u_wbuf*}]
set c_xbuf  [get_cells -hierarchical -filter {name =~ *u_xbuf*}]
set c_resp  [get_cells -hierarchical -filter {name =~ *u_ame*bus_resp*}]
set c_cpu   [get_cells -hierarchical -filter {name =~ *u_cpu*}]

# MAC lane: tile/x 寄存器 → Y 累加器
report_checks -from $c_tile -to $c_array -path_delay max -group_path_count 20 -endpoint_path_count 20 -fields $rf -format full_clock_expanded -digits 3 > $reports_dir/p4a0_detail_mac_tile_to_y.rpt
report_checks -from $c_xq   -to $c_array -path_delay max -group_path_count 20 -endpoint_path_count 20 -fields $rf -format full_clock_expanded -digits 3 > $reports_dir/p4a0_detail_mac_x_to_y.rpt
# WBUF/XBUF 宽行读 → tile/x 写入
report_checks -from $c_wbuf -to $c_array -path_delay max -group_path_count 20 -endpoint_path_count 20 -fields $rf -format full_clock_expanded -digits 3 > $reports_dir/p4a0_detail_wbuf_rowread.rpt
report_checks -from $c_xbuf -to $c_array -path_delay max -group_path_count 20 -endpoint_path_count 20 -fields $rf -format full_clock_expanded -digits 3 > $reports_dir/p4a0_detail_xbuf_rowread.rpt
# buffer 总线 32-bit 读 → AME 响应
report_checks -from $c_wbuf -to $c_resp -path_delay max -group_path_count 20 -endpoint_path_count 20 -fields $rf -format full_clock_expanded -digits 3 > $reports_dir/p4a0_detail_wbuf_busread.rpt
report_checks -from $c_xbuf -to $c_resp -path_delay max -group_path_count 20 -endpoint_path_count 20 -fields $rf -format full_clock_expanded -digits 3 > $reports_dir/p4a0_detail_xbuf_busread.rpt
# requant: Y → 响应
report_checks -from $c_y -to $c_resp -path_delay max -group_path_count 20 -endpoint_path_count 20 -fields $rf -format full_clock_expanded -digits 3 > $reports_dir/p4a0_detail_requant.rpt
# CPU: 到 AME 请求/总线请求
report_checks -to [get_cells -hierarchical -filter {name =~ *u_cpu*ame_req*}] -path_delay max -group_path_count 20 -endpoint_path_count 20 -fields $rf -format full_clock_expanded -digits 3 > $reports_dir/p4a0_detail_cpu_ame_req.rpt
set c_cpu_bus [get_cells -hierarchical -filter {name =~ *u_cpu*ax_*}]
if { [llength $c_cpu_bus] > 0 } {
  report_checks -to $c_cpu_bus -path_delay max -group_path_count 20 -endpoint_path_count 20 -fields $rf -format full_clock_expanded -digits 3 > $reports_dir/p4a0_detail_cpu_bus_req.rpt
}
puts "== detail reports done =="
