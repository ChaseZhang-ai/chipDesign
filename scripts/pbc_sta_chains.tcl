# -----------------------------------------------------------------------------
# pbc_sta_chains.tcl — 裁决 N 两条结构地板链的针对性 STA(P4A3 前置复测)
# 口径:1_synth 网表 + 1_synth.sdc(7.576 ns = 120 MHz 预算),与 P4A0
#       sta_detail.tcl 同法(-from/-to 过滤,post-synth 估计线负载)。
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

# 链1(v0.2):trace_rd_o →(旁路比较/选择)→ ame_req_* → AME 译码/选择 → u_rq_stq.p_u_q
# 链1(v0.3):请求寄存器 amreq_*_q → AME 译码/选择 → requant 输入捕获级
set c_trace [get_cells -hierarchical -filter {name =~ *trace_rd_o*}]
set c_amreq [get_cells -hierarchical -filter {name =~ *u_cpu.u_core.ame_req_*}]
set c_amreq2 [get_cells -hierarchical -filter {name =~ *u_cpu.u_core.ame_req_rs*}]
set c_stq_p [get_cells -hierarchical -filter {name =~ *u_rq_stq*p_u_q*}]
set c_stq_i [get_cells -hierarchical -filter {name =~ *u_rq_stq*y1_q*}]
set c_gyq_p [get_cells -hierarchical -filter {name =~ *g_yq*u_rq*p_u_q*}]
set c_gyq_i [get_cells -hierarchical -filter {name =~ *g_yq*u_rq*y1_q*}]
set c_s1rel [get_cells -hierarchical -filter {name =~ *s1_rel*}]

proc rep {fname from to} {
  set reports_dir $::env(REPORTS_DIR)
  set rf {slew cap input_pins fanout}
  set fh [open "$reports_dir/$fname" w]
  puts $fh "P4A3RTL03 chain report: $fname"
  close $fh
  if {[llength $from] == 0 || [llength $to] == 0} {
    set fh [open "$reports_dir/$fname" a]
    puts $fh "EMPTY PIN SET (from=[llength $from] to=[llength $to])"
    close $fh
    return
  }
  report_checks -from $from -to $to -path_delay max \
    -group_path_count 8 -endpoint_path_count 8 -fields $rf \
    -format full_clock_expanded -digits 3 >> $reports_dir/$fname
}

rep p4a3rtl03_chain1_oldpath_trace2stq.rpt $c_trace $c_stq_p
rep p4a3rtl03_chain1_newpath_amreq2stq.rpt $c_amreq $c_stq_p
rep p4a3rtl03_chain1_newpath_amreq2stq_inreg.rpt $c_amreq $c_stq_i
rep p4a3rtl03_chain1_mulleg.rpt $c_stq_i $c_stq_p
rep p4a3rtl03_chain2_s1rel2gyq_pu.rpt $c_s1rel $c_gyq_p
rep p4a3rtl03_chain2_s1rel2gyq_inreg.rpt $c_s1rel $c_gyq_i
puts "PBC chain reports done"
