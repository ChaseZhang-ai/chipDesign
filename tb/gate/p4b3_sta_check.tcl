# -----------------------------------------------------------------------------
# p4b3_sta_check.tcl — P4B3 STA 独立复核(p4a4fix 交付物,方法 = p4b2_sta_check.tcl 同款)
#
# 口径:P4A4 新签核 = 10.551 ns(94.78 MHz,+0.40 ns 裕量)+ 实达 fmax = 10.150 ns
# (98.52 MHz,零裕量能力上限)。uncertainty 0.15 setup / 0.05 hold(随 6_final.sdc)。
# 报告:tb/gate/build/p4b3_sta_{p,f}*.rpt
# -----------------------------------------------------------------------------
set ROOT /home/zcz/verda/autoDecodeChip
set R $ROOT/pnr/amechip/results/sky130hd/amechip/p4a4fix
set PLAT $env(HOME)/tools/openroad-flow-scripts/flow/platforms/sky130hd
set OUT $ROOT/tb/gate/build

read_liberty $PLAT/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
read_liberty $env(HOME)/tools/openroad-flow-scripts/flow/platforms/sky130ram/sky130_sram_1rw1r_128x256_8/sky130_sram_1rw1r_128x256_8_TT_1p8V_25C.lib
read_db $R/6_final.odb
read_sdc $R/6_final.sdc
source $PLAT/setRC.tcl
set_propagated_clock [all_clocks]
puts "P4B3 reading SPEF..."
read_spef $R/6_final.spef
puts "P4B3 SPEF loaded"

proc run_period {period tag} {
  set OUT /home/zcz/verda/autoDecodeChip/tb/gate/build
  puts "P4B3 ===== rebuild clk_i @ $period ns ($tag) ====="
  create_clock -name clk_i -period $period [get_ports {clk_i}]
  set f [open $OUT/p4b3_sta_$tag.rpt w]
  puts $f "#### P4B3 independent STA recheck (p4a4fix) — period $period ns ($tag)"
  puts $f "#### clk_i rebuilt: period=$period ns; uncertainty 0.15 setup / 0.05 hold (from 6_final.sdc)"
  close $f

  report_worst_slack -max >> $OUT/p4b3_sta_$tag.rpt
  report_worst_slack -min >> $OUT/p4b3_sta_$tag.rpt
  report_tns -max >> $OUT/p4b3_sta_$tag.rpt
  report_tns -min >> $OUT/p4b3_sta_$tag.rpt

  set f [open $OUT/p4b3_sta_${tag}_top.rpt w]
  puts $f "#### setup top15 @ $period"
  close $f
  report_checks -path_delay max -group_path_count 15 -format full_clock_expanded \
    >> $OUT/p4b3_sta_${tag}_top.rpt

  set f [open $OUT/p4b3_sta_${tag}_hold.rpt w]
  puts $f "#### hold top10 @ $period"
  close $f
  report_checks -path_delay min -group_path_count 10 -format full_clock_expanded \
    >> $OUT/p4b3_sta_${tag}_hold.rpt

  set f [open $OUT/p4b3_sta_${tag}_viol.rpt w]
  puts $f "#### setup violating paths (slack_max -1e-4) @ $period"
  close $f
  report_checks -path_delay max -slack_max -0.0001 -group_path_count 500 \
    -format short >> $OUT/p4b3_sta_${tag}_viol.rpt

  report_check_types -max_slew -max_capacitance -max_fanout -violators \
    >> $OUT/p4b3_sta_$tag.rpt
  report_clock_skew -setup >> $OUT/p4b3_sta_$tag.rpt
  puts "P4B3 ===== done $tag ====="
}

run_period 10.551 p
run_period 10.150 f
puts "P4B3 STA RECHECK COMPLETE"
