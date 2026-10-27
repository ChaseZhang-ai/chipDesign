# -----------------------------------------------------------------------------
# pnr_macro_place.tcl — AME-Chip 宏手工摆放(P4A,POST_MACRO_PLACE 钩子)
#
# RTLMP 的结果被本文件覆盖:三颗 sky130_sram_1rw1r_128x256_8(1141.72 × 632.475)
# 一字排开放在 die 底部,上方留 std cell 区。布局:
#
#   [OCRAM 4KB]  [WBUF 1KB]  [XBUF 1KB]      ← 宏行(y = Y0)
#   ──────────── std cell 区(上/下条带)────
#
#   * OCRAM(左)靠近 MEM 侧,WBUF/XBUF(中/右)靠近 AME 侧,减少跨 die 走线;
#   * 宏间距 GAP=16 µm,供宏引脚(met1/2/3 小 patch,多在左/下边缘)垂直通道;
#   * 宏行下留 100 µm 条带,宏上方为其余 std cell 区(条带高度由 DIE_AREA 定)。
#
# 实例路径(综合网表固定层级,filelist_macro.f 的 g_macro generate 块):
#   u_mem.u_core.u_ocram.u_ram.g_macro.u_macro
#   u_ame.u_core.u_wbuf.g_macro.u_macro
#   u_ame.u_core.u_xbuf.g_macro.u_macro
# -----------------------------------------------------------------------------

lassign [split $::env(DIE_AREA)] dx1 dy1 dx2 dy2
lassign [split $::env(CORE_AREA)] cx1 cy1 cx2 cy2
set GAP   16.0
set Y0    [expr {$cy1 + 96.0}]
set X0    [expr {$cx1 + 4.0}]
set MW    1141.72   ;# 宏宽
set MH    632.475   ;# 宏高

proc ame_fix_macro {name x y orient} {
  set inst [[ord::get_db_block] findInst $name]
  if {$inst == "NULL"} {
    error "ame_fix_macro: instance not found: $name"
  }
  # RTLMP 已把宏摆好并 LOCKED;先解锁再覆盖坐标
  $inst setPlacementStatus NONE
  place_macro -macro_name $name -location [list $x $y] -orientation $orient
  $inst setPlacementStatus FIRM
  puts "ame_fix_macro: $name @ ($x, $y) $orient"
}

# RTLMP 已把宏摆好并 LOCKED;先全部解锁(否则 place_macro 会与
# RTLMP 残留位置判重叠),再逐颗覆盖坐标
set _macro_names [list \
    u_mem.u_core.u_ocram.u_ram.g_macro.u_macro \
    u_ame.u_core.u_wbuf.g_macro.u_macro \
    u_ame.u_core.u_xbuf.g_macro.u_macro]
foreach n $_macro_names {
  set _i [[ord::get_db_block] findInst $n]
  if {$_i == "NULL"} {
    error "pnr_macro_place: instance not found: $n"
  }
  $_i setPlacementStatus NONE
}

set x $X0
foreach n $_macro_names {
  ame_fix_macro $n $x $Y0 R0
  set x [expr {$x + $MW + $GAP}]
}

# 报告宏区范围(写进日志供报告引用)
set macro_right [expr {$X0 + 3*$MW + 2*$GAP}]
puts "ame_macro_row: x = $X0 .. $macro_right, y = $Y0 .. [expr {$Y0+$MH}]"

# 删除 RTLMP 遗留的整列 blockage(每宏一列 maxD=0,y 覆盖半个 core)——
# GPL 会把它们当作硬阻挡生成 dummy gcell(实测 1.24 mm²),把 std 可用区
# 压缩到 0.35 mm²,造成 GPL-0301 假阳性(实际 free ≈1.55 mm² 足够 1.09 mm²)。
set _blks [[ord::get_db_block] getBlockages]
puts "ame_blockages: removing [llength $_blks] rtlmp blockages"
foreach b $_blks {
  odb::dbBlockage_destroy $b
}

report_design_area
