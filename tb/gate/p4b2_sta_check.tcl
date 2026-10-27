# -----------------------------------------------------------------------------
# p4b2_sta_check.tcl — P4B2 STA 独立复核(P4B2 会话,只读 pnr/ 产物)
#
# 方法(独立于 P4A3 报告,直接从 p4a3fin 交付物重算):
#   read_db(6_final.odb)→ read_sdc(6_final.sdc,声明 7.576)→ 平台 setRC
#   → set_propagated_clock → read_spef(6_final.spef)
#   → create_clock 重建 clk_i 至目标周期(无 -add 即替换)→ 出报告。
# 口径:与 P4A3 签核一致(uncertainty 0.15 setup / 0.05 hold 来自 6_final.sdc)。
# 报告:tb/gate/build/p4b2_sta_{p,10}.rpt(p=10.551 签核口径,10=100MHz 冲刺口径)
# -----------------------------------------------------------------------------
set ROOT /home/zcz/verda/autoDecodeChip
set R $ROOT/pnr/amechip/results/sky130hd/amechip/p4a3fin
set PLAT $env(HOME)/tools/openroad-flow-scripts/flow/platforms/sky130hd
set OUT $ROOT/tb/gate/build

read_liberty $PLAT/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
read_liberty $env(HOME)/tools/openroad-flow-scripts/flow/platforms/sky130ram/sky130_sram_1rw1r_128x256_8/sky130_sram_1rw1r_128x256_8_TT_1p8V_25C.lib
read_db $R/6_final.odb
read_sdc $R/6_final.sdc
source $PLAT/setRC.tcl
set_propagated_clock [all_clocks]
puts "P4B2 reading SPEF..."
read_spef $R/6_final.spef
puts "P4B2 SPEF loaded"

proc run_period {period tag} {
  set OUT /home/zcz/verda/autoDecodeChip/tb/gate/build
  puts "P4B2 ===== rebuild clk_i @ $period ns ($tag) ====="
  create_clock -name clk_i -period $period [get_ports {clk_i}]
  set f [open $OUT/p4b2_sta_$tag.rpt w]

  puts $f "#### P4B2 independent STA recheck — period $period ns ($tag)"
  puts $f "#### clk_i rebuilt: period=$period ns; uncertainty 0.15 setup / 0.05 hold (from 6_final.sdc)"
  close $f

  report_worst_slack -max >> $OUT/p4b2_sta_$tag.rpt
  report_worst_slack -min >> $OUT/p4b2_sta_$tag.rpt
  report_tns -max >> $OUT/p4b2_sta_$tag.rpt
  report_tns -min >> $OUT/p4b2_sta_$tag.rpt

  # setup top15
  set f [open $OUT/p4b2_sta_${tag}_top.rpt w]
  puts $f "#### setup top15 @ $period"
  close $f
  report_checks -path_delay max -group_path_count 15 -format full_clock_expanded \
    >> $OUT/p4b2_sta_${tag}_top.rpt

  # hold top10
  set f [open $OUT/p4b2_sta_${tag}_hold.rpt w]
  puts $f "#### hold top10 @ $period"
  close $f
  report_checks -path_delay min -group_path_count 10 -format full_clock_expanded \
    >> $OUT/p4b2_sta_${tag}_hold.rpt

  # violating endpoints (setup): count Startpoint lines
  set f [open $OUT/p4b2_sta_${tag}_viol.rpt w]
  puts $f "#### setup violating paths (slack_max -1e-4) @ $period"
  close $f
  report_checks -path_delay max -slack_max -0.0001 -group_path_count 500 \
    -format short >> $OUT/p4b2_sta_${tag}_viol.rpt

  # slew / cap / fanout residue
  report_check_types -max_slew -max_capacitance -max_fanout -violators \
    >> $OUT/p4b2_sta_$tag.rpt

  # clock skew
  report_clock_skew -setup >> $OUT/p4b2_sta_$tag.rpt
  puts "P4B2 ===== done $tag ====="
}

run_period 10.551 p
run_period 10.0 q
puts "P4B2 STA RECHECK COMPLETE"
