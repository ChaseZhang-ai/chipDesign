# -----------------------------------------------------------------------------
# sta_top20.tcl — 综合后关键路径 top-20(P4A0;P1BX-B 后直接复用)
#
# 用法(推荐用 run_sta.sh,自动设置 ORFS 环境):
#   bash syn/amechip/scripts/run_sta.sh
#
# 口径:1_synth.odb(post-synth,未布局布线,估计线负载)。数字用于**逻辑深度
# 与风险排序**,最终签核在 P4A 布局布线后重跑同一脚本。
# 注:OpenSTA 的 report_checks 原生支持 "> file" / ">> file" 重定向。
# -----------------------------------------------------------------------------

set results_dir $::env(RESULTS_DIR)
set reports_dir $::env(REPORTS_DIR)
file mkdir $reports_dir

# liberty 不在 odb 里,必须先读(否则 STA-2141 No liberty libraries found)
if { [info exists ::env(LIB_FILES)] && $::env(LIB_FILES) ne "" } {
  foreach lib $::env(LIB_FILES) { read_liberty $lib }
} else {
  read_liberty $::env(PLATFORM_DIR)/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
}
read_db $results_dir/1_synth.odb
read_sdc $results_dir/1_synth.sdc

puts "== clocks =="
report_clock_properties
catch { report_clock_min_period }

puts "== summary =="
catch { report_worst_slack -max }
catch { report_tns -max }
catch { report_wns -max }
report_design_area

set rf {slew cap input_pins fanout}

set f $reports_dir/p4a0_top20_setup.rpt
set fh [open $f w]
puts $fh "=============================================================="
puts $fh " P4A0 post-synth setup critical paths (worst 20, per path group)"
puts $fh " SDC: [get_property [get_clocks clk_i] period] ns, sky130hd tt 1v80 25C (P4A2 起签核口径 11.82 ns = 84.6 MHz)"
puts $fh " NOTE: pre-placement, estimated/zero wire load"
puts $fh "=============================================================="
close $fh

report_checks -path_delay max -group_path_count 20 -endpoint_path_count 20 \
  -fields $rf -format full_clock_expanded -digits 3 >> $f

# 只列违反当前 SDC 周期的路径
report_checks -path_delay max -slack_max 0 -group_path_count 50 \
  -fields $rf -format full_clock_expanded -digits 3 \
  > $reports_dir/p4a0_violators.rpt

# 未约束路径(检查 IO 约束是否漏网)
if { [catch {
  report_checks -unconstrained -path_delay max -group_path_count 20 -digits 3 \
    > $reports_dir/p4a0_unconstrained.rpt
} rv] } {
  set fh [open $reports_dir/p4a0_unconstrained.rpt w]
  puts $fh "report_checks -unconstrained unavailable: $rv"
  close $fh
}

# 设计规则违例
if { [catch {
  report_check_types -max_slew -max_capacitance -max_fanout -violators \
    > $reports_dir/p4a0_drc_summary.rpt
} rv] } {
  set fh [open $reports_dir/p4a0_drc_summary.rpt w]
  puts $fh "report_check_types unavailable: $rv"
  close $fh
}

# 时钟(综合后为理想时钟,仅记录)
if { [catch { report_clock_skew > $reports_dir/p4a0_clock_skew.rpt } rv] } {
  set fh [open $reports_dir/p4a0_clock_skew.rpt w]
  puts $fh "report_clock_skew unavailable: $rv"
  close $fh
}

puts "== done: $reports_dir =="
