# -----------------------------------------------------------------------------
# sta_viol_evidence.tcl — P4A3 违例端点取证(旧 82 端点结构不复现判据)
#
# 读 6_final.odb + spef,按 AME_SIGNOFF_PERIOD 重建 clk_i,输出:
#   <pre>_viol_slack.rpt   全部 setup 违例路径 slack_only 清单(端点普查用)
#   <pre>_viol_top.rpt     最差 10 条 full_clock_expanded(结构判读用)
#   <pre>_viol_puq.rpt     -through p_u_q 端点的路径(旧族专项复查;空=不复现)
#   <pre>_viol_mtvec.rpt   -through mtvec 端点的路径(同上)
# 环境变量:RESULTS_DIR / REPORTS_DIR / LIB_FILES / AME_RPT_PREFIX / AME_SIGNOFF_PERIOD
# -----------------------------------------------------------------------------
set results_dir $::env(RESULTS_DIR)
set reports_dir $::env(REPORTS_DIR)
set pre "viol"
if {[info exists ::env(AME_RPT_PREFIX)]} { set pre $::env(AME_RPT_PREFIX) }
file mkdir $reports_dir

foreach lib $::env(LIB_FILES) { read_liberty $lib }
read_db $results_dir/6_final.odb
read_sdc $results_dir/6_final.sdc
if {[file exists $results_dir/6_final.spef]} { read_spef $results_dir/6_final.spef }

set p $::env(AME_SIGNOFF_PERIOD)
create_clock -name clk_i -period $p [get_ports clk_i]
set_clock_uncertainty -setup 0.150 [get_clock clk_i]
set_clock_uncertainty -hold  0.050 [get_clock clk_i]
set_clock_transition 0.050 [get_clock clk_i]
puts "== evidence @ period $p ns =="

report_checks -path_delay max -slack_max 0 -group_count 1000 \
  -format slack_only -digits 3 > [file join $reports_dir ${pre}_viol_slack.rpt]

report_checks -path_delay max -format full_clock_expanded \
  -digits 3 -group_count 10 > [file join $reports_dir ${pre}_viol_top.rpt]

# 旧 82 端点族专项:p_u_q / mtvec_q 装载锥(flatten 后实例名 '.' 连接,两段式 pattern)
foreach {tag pat} {puq {*p_u_q*/*} mtvec {*mtvec*/*}} {
  set objs {}
  foreach onep $pat { set objs [concat $objs [get_pins -quiet $onep]] }
  set f [file join $reports_dir ${pre}_viol_${tag}.rpt]
  if {[llength $objs] == 0} {
    set fh [open $f w]; puts $fh "0 pins matched pattern '$pat'"; close $fh
    continue
  }
  report_checks -path_delay max -format short -digits 3 \
    -through $objs -group_count 20 > $f
}
puts "evidence reports written (prefix $pre)"
