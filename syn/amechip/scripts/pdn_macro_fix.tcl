# -----------------------------------------------------------------------------
# pdn_macro_fix.tcl — AME-Chip 宏供电 + 孤儿轨道修复(P4A, POST_PDN_TCL)
#
# 由 pdn_amechip.tcl 之后的 ORFS pdn.tcl 在 pdngen 完成后 source 本文件。
# 依赖 syn/amechip/scripts/pdn_macro_fix_data.tcl(gen_macro_lef.py 生成)。
#
# 做三件事:
#  1. 宏电源条: 每颗 sky130_sram_1rw1r_128x256_8 实例按 master 坐标列画 met4
#     电源条(与衍生 LEF 的 vdd/gnd 引脚形状一致), 并:
#       - 条下每个同网 met3 焊盘中心放 via3(tech via M3M4_PR; met3 包围
#         0.38x0.32 完全在 0.49 焊盘内, 不会碰异网焊盘);
#       - 条与同网 met5 strap 交叉处放 via4 接入顶层电网。
#  2. 孤儿轨道拯救: 宏 halo 把 followpin 轨道切成残段, 宏带内残段上方可能没有
#     同网 met4 strap(宏间隙/两翼), 既连不上电网(PSM Unconnected)也养不了单元。
#     对有空间的残段区补一条 met4 mini-strap + via4 + 轨道过孔栈;
#     对放不下的残段区(如宏左翼 ~2um): 删残段轨道 + 删区内 tapcell + 放
#     placement blockage(区内不再摆单元, 无需供电)。
#  3. 汇总报告(写日志)。
#
# 坐标单位: odb DBU(本工艺 1000/um); 数据文件里的 pad/列坐标为 um(master 坐标)。
# -----------------------------------------------------------------------------

set DATA [file join [file dirname [info script]] pdn_macro_fix_data.tcl]
source $DATA

set block [ord::get_db_block]
set tech [$block getTech]
set dbu [$block getDefUnits]
set m1 [$tech findLayer met1]
set m3 [$tech findLayer met3]
set m4 [$tech findLayer met4]
set m5 [$tech findLayer met5]

proc um2dbu {v} { return [expr {int(round($v * 1000.0))}] }

# ---- 工具: 在网上建特殊金属矩形 ----
proc ame_add_rect {net layer x1 y1 x2 y2} {
  set swires [$net getSWires]
  set sw [lindex $swires 0]
  if {$sw eq "" || $sw eq "NULL"} {
    set sw [odb::dbSWire_create $net "NONE"]
  }
  return [odb::dbSBox_create $sw $layer $x1 $y1 $x2 $y2 "STRIPE"]
}
proc ame_add_techvia {net via x y} {
  set sw [lindex [$net getSWires] 0]
  odb::dbSBox_create $sw $via $x $y "STRIPE"
}
proc ame_add_blockvia {net via x y} {
  set sw [lindex [$net getSWires] 0]
  odb::dbSBox_create $sw $via $x $y "STRIPE"
}

# ---- 按层对挑 pdn 已生成的块 via(rail x strap 交叉栈) ----
array set AME_STK {}
foreach via [$block getVias] {
  set bl [[$via getBottomLayer] getName]
  set tl [[$via getTopLayer] getName]
  set key "$bl>$tl"
  if {![info exists AME_STK($key)]} {
    set AME_STK($key) [$via getName]
  } else {
    # 优先 1600_480(strap x rail 尺寸族)
    if {[string match "*1600_480*" [$via getName]]} {
      set AME_STK($key) [$via getName]
    }
  }
}
foreach need {{met1>met2} {met2>met3} {met3>met4} {met4>met5}} {
  set k [lindex $need 0]
  if {![info exists AME_STK($k)]} {
    error "pdn_macro_fix: 缺少块 via $k"
  }
}
puts "pdn_macro_fix: 栈 via: met1>met2=$AME_STK(met1>met2) met2>met3=$AME_STK(met2>met3) met3>met4=$AME_STK(met3>met4) met4>met5=$AME_STK(met4>met5)"

set via_pad [[$tech findVia M3M4_PR] getName]
set via_pad_obj [$tech findVia M3M4_PR]
if {$via_pad_obj eq "NULL"} { error "pdn_macro_fix: tech via M3M4_PR 不存在" }

# ---- 收集 met5 同网水平 strap y 区间 ----
proc ame_met5_bands {net m5} {
  set bands {}
  foreach sw [$net getSWires] {
    foreach box [$sw getWires] {
      if {[$box isVia]} { continue }
      set tl [$box getTechLayer]
      if {$tl eq "NULL" || $tl ne $m5} { continue }
      lappend bands [list [$box yMin] [$box yMax]]
    }
  }
  return $bands
}
set M5BAND(VDD) [ame_met5_bands [$block findNet VDD] $m5]
set M5BAND(VSS) [ame_met5_bands [$block findNet VSS] $m5]
puts "pdn_macro_fix: met5 straps VDD=[llength $M5BAND(VDD)] VSS=[llength $M5BAND(VSS)]"

# ---- 1. 宏电源条 ----
set MW 1141.72
set MH 632.475
set ame_macros {}
foreach inst [$block getInsts] {
  if {[[$inst getMaster] getName] eq "sky130_sram_1rw1r_128x256_8"} {
    lappend ame_macros $inst
  }
}
puts "pdn_macro_fix: SRAM 实例数 [llength $ame_macros]"
set n_strap 0; set n_via3 0; set n_via4 0
foreach inst $ame_macros {
  set bb [$inst getBBox]
  set ox [$bb xMin]; set oy [$bb yMin]
  set orient [$inst getOrient]
  if {$orient ne "R0"} {
    error "pdn_macro_fix: 宏 [[$inst getName]] 方位 $orient 非 R0, 坐标变换需扩展"
  }
  foreach {pin netname} {vdd VDD gnd VSS} {
    set net [$block findNet $netname]
    foreach c $AME_COLS($pin) {
      # met4 电源条(y>=52: 避开宏内部 met4 vdd 底带 y 3..47.05, 防 gnd 条与之短路)
      set x1 [expr {$ox + [um2dbu $c] - 800}]
      set x2 [expr {$ox + [um2dbu $c] + 800}]
      set y1s [expr {$oy + [um2dbu 52.0]}]
      ame_add_rect $net $m4 $x1 $y1s $x2 [expr {$oy + [um2dbu $MH]}]
      incr n_strap
      # 条下同网焊盘打 via3(master 坐标 -> die 坐标)
      foreach pad $AME_PADS($pin) {
        lassign $pad px1 py1 px2 py2
        set pcx [expr {($px1 + $px2) / 2.0}]
        if {abs($pcx - $c) <= 0.635 && $py1 >= 52.0} {
          set pcy [expr {($py1 + $py2) / 2.0}]
          ame_add_techvia $net $via_pad_obj [expr {$ox + [um2dbu $pcx]}] [expr {$oy + [um2dbu $pcy]}]
          incr n_via3
        }
      }
      # 与同网 met5 交叉放 via4
      set cx_s [expr {($x1 + $x2) / 2}]
      foreach band $M5BAND($netname) {
        lassign $band by1 by2
        set cy [expr {($by1 + $by2) / 2}]
        if {$cy >= $y1s && $cy <= $oy + [um2dbu $MH]} {
          set bv [$block findVia $AME_STK(met4>met5)]
          ame_add_blockvia $net $bv $cx_s $cy
          incr n_via4
        }
      }
    }
  }
}
puts "pdn_macro_fix: 宏电源条 $n_strap 条, via3(焊盘) $n_via3, via4 $n_via4"

# ---- 2. 孤儿轨道拯救 ----
# met4 同网 x 区间(垂直, 含上面新画的)
proc ame_met4_xbands {net m4} {
  set bands {}
  foreach sw [$net getSWires] {
    foreach box [$sw getWires] {
      if {[$box isVia]} { continue }
      set tl [$box getTechLayer]
      if {$tl eq "NULL" || $tl ne $m4} { continue }
      if {[$box yMax] - [$box yMin] <= [$box xMax] - [$box xMin]} { continue }
      lappend bands [list [$box xMin] [$box xMax] [$box yMin] [$box yMax]]
    }
  }
  return $bands
}
set M4(VDD) [ame_met4_xbands [$block findNet VDD] $m4]
set M4(VSS) [ame_met4_xbands [$block findNet VSS] $m4]

proc ame_covered {x1 x2 bands} {
  foreach b $bands {
    # 只认可靠的大宽度 strap 覆盖(>=1.2um); pdn channel-repair 的窄条(0.4um)
    # 常常打不满 via 栈, 不能当作已连通
    if {[lindex $b 1] - [lindex $b 0] < 1200} { continue }
    if {[lindex $b 0] < $x2 && [lindex $b 1] > $x1} { return 1 }
  }
  return 0
}

# 收集孤儿轨道段(按 net)
set orphans(VDD) {}; set orphans(VSS) {}
foreach {netname} {VDD VSS} {
  set net [$block findNet $netname]
  foreach sw [$net getSWires] {
    foreach box [$sw getWires] {
      if {[$box isVia]} { continue }
      set tl [$box getTechLayer]
      if {$tl eq "NULL" || $tl ne $m1} { continue }
      if {[$box xMax] - [$box xMin] <= [$box yMax] - [$box yMin]} { continue }
      if {![ame_covered [$box xMin] [$box xMax] $M4($netname)]} {
        lappend orphans($netname) $box
      }
    }
  }
}
puts "pdn_macro_fix: 孤儿轨道 VDD=[llength $orphans(VDD)] VSS=[llength $orphans(VSS)]"

# 按 (net, x 区间) 聚组; 再把两组(不同 net)按 x 重叠合并为"区域"
array set grp {}
foreach {netname} {VDD VSS} {
  foreach box $orphans($netname) {
    set key "$netname [$box xMin] [$box xMax]"
    if {![info exists grp($key)]} { set grp($key) [list 0 0 0] }
    lassign $grp($key) ylo yhi n
    if {$n == 0} {
      set grp($key) [list [$box yMin] [$box yMax] 1]
    } else {
      set ylo [expr {min($ylo, [$box yMin])}]
      set yhi [expr {max($yhi, [$box yMax])}]
      set grp($key) [list $ylo $yhi [expr {$n+1}]]
    }
  }
}
set regions {}
foreach key [array names grp] {
  lassign $key netname x1 x2
  lassign $grp($key) ylo yhi n
  lappend regions [list $x1 $x2 $ylo $yhi $netname $n]
}

# 区域合并: x 区间重叠(不同 net 也合并, 因为要统一决策)
set merged 1
while {$merged} {
  set merged 0
  set out {}
  foreach r $regions {
    set placed 0
    set newout {}
    foreach o $out {
      if {!$placed && [lindex $r 0] <= [lindex $o 1] && [lindex $o 0] <= [lindex $r 1]} {
        # 重叠: 扩展 o (区域代表 x 联合, net 集合与轨道数累加, y 取并)
        set o [list [expr {min([lindex $o 0],[lindex $r 0])}] [expr {max([lindex $o 1],[lindex $r 1])}] \
                    [expr {min([lindex $o 2],[lindex $r 2])}] [expr {max([lindex $o 3],[lindex $r 3])}] \
                    "[lindex $o 4]+[lindex $r 4]" [expr {[lindex $o 5]+[lindex $r 5]}]]
        lappend newout $o
        set placed 1
        set merged 1
      } else {
        lappend newout $o
      }
    }
    if {!$placed} { lappend newout $r }
    set out $newout
  }
  set regions $out
}
puts "pdn_macro_fix: 孤儿区域 [llength $regions] 个"

set n_rescue_strap 0; set n_rescue_stack 0; set n_del_rail 0; set n_blk 0

# 在区域 [rx1,rx2] 内为 netname 找 mini-strap 中心 x(避开异网 met4 ±1.25mm-db、
# 已选中心 ±4.05);找不到返回 ""。纯规划, 不画图。
proc ame_find_strap_x {netname rx1 rx2 placed_x M4name} {
  upvar 1 $M4name M4
  set opp [expr {$netname eq "VDD" ? "VSS" : "VDD"}]
  set cx0 [expr {($rx1 + $rx2) / 2}]
  for {set delta 0} {$delta <= [expr {$rx2 - $rx1}]} {set delta [expr {$delta + 5}]} {
    foreach sign {1 -1} {
      set cx [expr {$cx0 + $sign * $delta}]
      if {$cx - 800 < $rx1 || $cx + 800 > $rx2} { continue }
      set good 1
      foreach b $M4($opp) {
        if {[lindex $b 0] < $cx + 1250 && [lindex $b 1] > $cx - 1250} { set good 0; break }
      }
      if {$good} {
        foreach px $placed_x {
          if {abs($px - $cx) < 4050} { set good 0; break }
        }
      }
      if {$good} { return $cx }
    }
  }
  return ""
}

foreach r $regions {
  lassign $r rx1 rx2 ry1 ry2 netnames nrails
  set nets [lsort -unique [split $netnames +]]
  # ---- 阶段 1: 规划(所有网都要有位置才动手, 否则整区走删除路径) ----
  set plan {}
  set fail 0
  foreach netname $nets {
    set cx [ame_find_strap_x $netname $rx1 $rx2 [dict values $plan] M4]
    if {$cx eq ""} {
      set fail 1
      break
    }
    dict set plan $netname $cx
  }
  # ---- 阶段 2: 提交 ----
  if {!$fail} {
    dict for {netname cx} $plan {
      set net [$block findNet $netname]
      ame_add_rect $net $m4 [expr {$cx - 800}] $ry1 [expr {$cx + 800}] $ry2
      incr n_rescue_strap
      foreach band $M5BAND($netname) {
        lassign $band by1 by2
        set cy [expr {($by1 + $by2) / 2}]
        if {$cy >= $ry1 && $cy <= $ry2} {
          set bv [$block findVia $AME_STK(met4>met5)]
          ame_add_blockvia $net $bv $cx $cy
          incr n_rescue_stack
        }
      }
      # 每条同网孤儿轨道放 met1->met4 栈
      foreach box $orphans($netname) {
        set ry [expr {([$box yMin] + [$box yMax]) / 2}]
        if {[$box xMin] < $rx2 && [$box xMax] > $rx1} {
          foreach k {met1>met2 met2>met3 met3>met4} {
            set bv [$block findVia $AME_STK($k)]
            ame_add_blockvia $net $bv $cx $ry
          }
          incr n_rescue_stack
        }
      }
    }
    puts "pdn_macro_fix: 区域 ([expr {$rx1/1000.0}],[expr {$ry1/1000.0}])-([expr {$rx2/1000.0}],[expr {$ry2/1000.0}]) nets=$netnames 补条供电"
  } else {
    puts "pdn_macro_fix: 区域 ([expr {$rx1/1000.0}],[expr {$ry1/1000.0}])-([expr {$rx2/1000.0}],[expr {$ry2/1000.0}]) nets=$netnames 无法全部供电, 清空条带+blockage"
    # 扩一点边, 把 pdn channel-repair 的残件(补丁/窄条/via)一并清掉
    set ex1 [expr {$rx1 - 1200}]; set ex2 [expr {$rx2 + 1400}]
    set ey1 [expr {$ry1 - 600}];  set ey2 [expr {$ry2 + 600}]
    foreach netname {VDD VSS} {
      set net [$block findNet $netname]
      set todel {}
      foreach sw [$net getSWires] {
        foreach box [$sw getWires] {
          set bx1 [$box xMin]; set by1 [$box yMin]
          set bx2 [$box xMax]; set by2 [$box yMax]
          if {$bx1 >= $ex2 || $bx2 <= $ex1 || $by1 >= $ey2 || $by2 <= $ey1} { continue }
          if {[$box isVia]} {
            lappend todel $box
          } else {
            # 保留 met5 水平干线(横贯全图的顶层网), 其余(轨道残段/修复补丁/窄条)删
            set _lay ""
            set _tl [$box getTechLayer]
            if {$_tl ne "NULL"} { set _lay [$_tl getName] }
            if {$_lay ne "met5"} { lappend todel $box }
          }
        }
      }
      foreach box $todel {
        odb::dbSBox_destroy $box
        incr n_del_rail
      }
    }
    # 删区内的物理单元(tapcell); 设计单元由 blockage 挡在区外(3_5 详细布局遵守)
    foreach inst [$block getInsts] {
      set bb [$inst getBBox]
      if {[$bb xMin] >= $ex1 && [$bb xMax] <= $ex2 && [$bb yMin] >= $ey1 && [$bb yMax] <= $ey2} {
        if {[string match "TAP_*" [$inst getName]]} {
          odb::dbInst_destroy $inst
        }
      }
    }
    if {[catch {create_blockage -region [list [expr {$ex1/1000.0}] [expr {$ey1/1000.0}] \
                                              [expr {$ex2/1000.0}] [expr {$ey2/1000.0}]]} blkerr]} {
      error "pdn_macro_fix: create_blockage 失败: $blkerr"
    }
    incr n_blk
  }
}
puts "pdn_macro_fix: 拯救 mini-strap $n_rescue_strap 条, 栈 via $n_rescue_stack, 删轨道 $n_del_rail, blockage $n_blk"
