# -----------------------------------------------------------------------------
# extract_pdn_facts.tcl — 从已完成 PDN 的 ODB 提取 PDN 事实表(供 gen_macro_lef.py)
#
# 输出(文本, 每行一条):
#   STRAP met4 <net> <x1> <y1> <x2> <y2>   垂直 met4 strap(分段去重)
#   STRAP met5 <net> <x1> <y1> <x2> <y2>   水平 met5 strap
#   RAIL  <net> <x1> <y1> <x2> <y2>        met1 followpin 轨道段
#   MACRO <inst> <ox> <oy> <x1> <y1> <x2> <y2> <orient>
#   BLOCKVIA <name>
#
# 用法: openroad -no_init -exit extract_pdn_facts.tcl
#   (ODB 路径在下方 ODB 变量里改, 或用环境变量 AME_FACTS_ODB)
# -----------------------------------------------------------------------------
set odb_path [expr {[info exists ::env(AME_FACTS_ODB)] ? $::env(AME_FACTS_ODB) :
    "/home/zcz/verda/autoDecodeChip/pnr/amechip/results/sky130hd/amechip/p4atd/2_4_floorplan_pdn.odb"}]
set out_path [expr {[info exists ::env(AME_FACTS_OUT)] ? $::env(AME_FACTS_OUT) :
    "/tmp/pdn_facts.txt"}]

read_db $odb_path
set block [ord::get_db_block]
proc um {v} { return [expr {$v/1000.0}] }
set fh [open $out_path w]

foreach net [$block getNets] {
  set nname [$net getName]
  if {$nname ne "VDD" && $nname ne "VSS"} { continue }
  foreach layer {met4 met5} {
    array unset seen
    foreach sw [$net getSWires] {
      foreach box [$sw getWires] {
        if {[$box isVia]} { continue }
        set tl [$box getTechLayer]
        if {$tl eq "NULL" || [$tl getName] ne $layer} { continue }
        set x1 [um [$box xMin]]; set y1 [um [$box yMin]]
        set x2 [um [$box xMax]]; set y2 [um [$box yMax]]
        if {$layer eq "met4" && ($y2-$y1) <= ($x2-$x1)} { continue }
        if {$layer eq "met5" && ($x2-$x1) <= ($y2-$y1)} { continue }
        set key "$x1 $y1 $x2 $y2"
        if {![info exists seen($key)]} {
          set seen($key) 1
          puts $fh "STRAP $layer $nname $x1 $y1 $x2 $y2"
        }
      }
    }
  }
}
foreach net [$block getNets] {
  set nname [$net getName]
  if {$nname ne "VDD" && $nname ne "VSS"} { continue }
  foreach sw [$net getSWires] {
    foreach box [$sw getWires] {
      if {[$box isVia]} { continue }
      set tl [$box getTechLayer]
      if {$tl eq "NULL" || [$tl getName] ne "met1"} { continue }
      set x1 [um [$box xMin]]; set y1 [um [$box yMin]]
      set x2 [um [$box xMax]]; set y2 [um [$box yMax]]
      if {($x2-$x1) <= ($y2-$y1)} { continue }
      puts $fh "RAIL $nname $x1 $y1 $x2 $y2"
    }
  }
}
foreach iname {u_mem.u_core.u_ocram.u_ram.g_macro.u_macro \
               u_ame.u_core.u_wbuf.g_macro.u_macro \
               u_ame.u_core.u_xbuf.g_macro.u_macro} {
  set inst [$block findInst $iname]
  if {$inst eq "NULL"} { continue }
  set bb [$inst getBBox]
  puts $fh "MACRO $iname [um [$bb xMin]] [um [$bb yMin]] [um [$bb xMin]] [um [$bb yMin]] [um [$bb xMax]] [um [$bb yMax]] [$inst getOrient]"
}
foreach via [$block getVias] {
  puts $fh "BLOCKVIA [$via getName]"
}
close $fh
puts "extract_pdn_facts: wrote $out_path"
