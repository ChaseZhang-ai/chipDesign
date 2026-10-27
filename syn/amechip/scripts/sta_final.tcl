# -----------------------------------------------------------------------------
# sta_final.tcl — 终版签核分析(读 6_final.odb + spef)——P4A2 v2
#
# P4A2 修复(问题 P4B-03 / STA-0511):
#   1) ctrl 过滤改用扁平实例名锚定正确的 glob(yosys flatten 后名字用 '.' 连接,
#      形如 u_cpu.ax_ar_ready;旧写法 "u_cpu.*/*" 的 '/' 段不存在 → get_pins 空集
#      → STA-0511);"a|b" 也不是 get_pins 的合法多 pattern 写法(应空格分隔);
#      空集时跳过并显式记 0 paths,不再报错。
#   2) hold 独立报告:top 路径(无 slack 过滤,正裕量也列出)+ 违例路径
#      (-slack_max 0,违例计数;全清时为空)+ summary 内 report_tns -min /
#      worst_slack -min——hold TNS/违例计数不再依赖 6_finish.rpt。
#
# 用法: 见 run_final_sta.sh(设置环境变量后调用本文件)
# 环境变量:
#   RESULTS_DIR / REPORTS_DIR / LIB_FILES   必备(run_final_sta.sh 已设)
#   AME_RPT_PREFIX       报告文件前缀(默认 p4a_final)
#   AME_SIGNOFF_PERIOD   设置后把 clk_i 重建为该周期 ns(信息性对照口径;
#                        流程 SDC 已是签核周期时不要设)
# 产出(REPORTS_DIR 下): <pre>_summary.rpt / <pre>_top20.rpt /
#   <pre>_hold_top.rpt / <pre>_hold_viol.rpt / <pre>_ctrl_{cpu,uart,dma,kv}.rpt
# -----------------------------------------------------------------------------
set results_dir $::env(RESULTS_DIR)
set reports_dir $::env(REPORTS_DIR)
set pre "p4a_final"
if {[info exists ::env(AME_RPT_PREFIX)]} { set pre $::env(AME_RPT_PREFIX) }
file mkdir $reports_dir

foreach lib $::env(LIB_FILES) { read_liberty $lib }
read_db $results_dir/6_final.odb
read_sdc $results_dir/6_final.sdc
# 寄生:优先 spef
if {[file exists $results_dir/6_final.spef]} {
  read_spef $results_dir/6_final.spef
}

# 信息性对照口径:重建 clk_i 周期(签核周期之外的口径,如 7.576 ns 存档对照)
set period_override 0
if {[info exists ::env(AME_SIGNOFF_PERIOD)]} {
  set p $::env(AME_SIGNOFF_PERIOD)
  create_clock -name clk_i -period $p [get_ports clk_i]
  set_clock_uncertainty -setup 0.150 [get_clock clk_i]
  set_clock_uncertainty -hold  0.050 [get_clock clk_i]
  set_clock_transition 0.050 [get_clock clk_i]
  set period_override 1
  puts "== clk_i rebuilt at period $p ns (对照口径) =="
}

# summary:顺序重定向(OpenSTA 原生 > / >>),文件各段之间无通道写混用
report_clock_properties > [file join $reports_dir ${pre}_summary.rpt]
if {$period_override} {
  set fh [open [file join $reports_dir ${pre}_summary.rpt] a]
  puts $fh "== NOTE: clk_i rebuilt at $p ns (AME_SIGNOFF_PERIOD 对照口径) =="
  close $fh
}
report_worst_slack -max >> [file join $reports_dir ${pre}_summary.rpt]
report_tns -max >> [file join $reports_dir ${pre}_summary.rpt]
report_wns -max >> [file join $reports_dir ${pre}_summary.rpt]
report_worst_slack -min >> [file join $reports_dir ${pre}_summary.rpt]
report_tns -min >> [file join $reports_dir ${pre}_summary.rpt]
report_power >> [file join $reports_dir ${pre}_summary.rpt]

# top-20 setup
report_checks -path_delay max -format full_clock_expanded \
  -digits 3 -group_count 20 > [file join $reports_dir ${pre}_top20.rpt]

# hold top 路径(无 slack 过滤——正裕量也列出,证明 hold 全清且有余量)
report_checks -path_delay min -format full_clock_expanded \
  -digits 3 -group_count 50 > [file join $reports_dir ${pre}_hold_top.rpt]

# hold 违例路径(独立违例计数;hold 全清时该文件为空 = 0 条)
report_checks -path_delay min -format full_clock_expanded \
  -digits 3 -group_count 50 -slack_max 0 > [file join $reports_dir ${pre}_hold_viol.rpt]

# 控制路径复判(P4A0 口径)
# 实测语义(本 OpenSTA):get_pins 的 '*' 不跨层级分隔符 '/',钉名是独立段,
# 故必须用两段式 pattern '<实例 glob>/*';多 pattern 用 Tcl list 空格分隔。
# (P4B-03/STA-0511 的真正根因:旧脚本 'a|b' 拼出单个非法 pattern → 空集)
array set CTRL {
  cpu   {u_cpu.*/*}
  uart  {u_uart.*/*}
  dma   {*u_dma.*/*}
  kv    {*u_kvc.*/* *u_memc.*/*}
}
foreach {k pat} [array get CTRL] {
  set f [file join $reports_dir ${pre}_ctrl_$k.rpt]
  # 本 OpenSTA 的 get_pins 只接受零或一个位置参数,逐 pattern 收集
  set objs {}
  foreach onep $pat {
    set objs [concat $objs [get_pins -quiet $onep]]
  }
  if {[llength $objs] == 0} {
    set fh [open $f w]
    puts $fh "0 paths: filter '$pat' matched no pins (命名核对 6_final.v)"
    close $fh
    puts "ctrl $k: filter '$pat' -> 0 pins, skipped"
    continue
  }
  report_checks -path_delay max -format full_clock_expanded -digits 3 \
    -through $objs -group_count 10 > $f
}
puts "reports written to $reports_dir (prefix $pre)"
