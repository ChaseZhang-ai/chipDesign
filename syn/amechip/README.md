# syn/amechip — AME-Chip 整芯片综合与 P&R 资产(P4A0 探针 → P4A 正式后端)

本目录是 ORFS 树外的 `DESIGN_CONFIG`,**不改 ORFS 自带 design/platform 文件**。
详见 `reports/P4A0_REPORT.md`(探针)与 `reports/P4A_REPORT.md`(正式后端)。

## 快速用法

```bash
cd ~/tools/openroad-flow-scripts/flow
source ../env.sh

# P4A 正式流程(宏化 + 全流程到 GDS):
make DESIGN_CONFIG=/home/zcz/verda/autoDecodeChip/syn/amechip/config.mk \
     WORK_HOME=/home/zcz/verda/autoDecodeChip/pnr/amechip \
     FLOW_VARIANT=p4a1 <target>        # target=synth/floorplan/place/cts/route/finish/...

# 对照综合(时序驱动 ABC 脚本):
make ... FLOW_VARIANT=p4atd ABC_AREA=0 synth

# flop 存储原版对照(P1BX-B 口径):
make ... FLOW_VARIANT=p4a_flop AME_SRAM_MACRO=0 synth

# 综合后 STA(自动识别宏化网表并加载宏 lib):
bash /home/zcz/verda/autoDecodeChip/syn/amechip/scripts/run_sta.sh \
     /home/zcz/verda/autoDecodeChip/pnr/amechip p4a1
```

产物在 `pnr/amechip/{logs,reports,results,objects}/sky130hd/amechip/<variant>/`。

## 关键约定

| 项 | 值/做法 |
|---|---|
| 真模块宏 | `VERILOG_DEFINES = -D AMECHIP_REAL_CPU/AME/MEM/BOOTROM -D AMECHIP_BOOTROM_CONST`(**不可省**) |
| 语言前端 | `SYNTH_HDL_FRONTEND=slang` + `--single-unit --allow-use-before-declare` |
| 存储位宽上限 | `SYNTH_MEMORY_MAX_BITS=262144` |
| SDC | 120 MHz + 10% margin = 7.576 ns;IO 延迟/XMEM 生成时钟/复位 false path |
| 源文件 | `filelist.f`(flop 原版)/ `filelist_macro.f`(宏化版,`AME_SRAM_MACRO=1` 默认) |
| SRAM 宏 | OC SRAM 4KB 与 WBUF/XBUF 各 1 颗 `sky130_sram_1rw1r_128x256_8`(**策略修正**:P4A0 策略表的 64x256_8 字宽仅 64b,无法一拍读 16B 行,见 `rtl_macro/ame_buf_rf.sv` 头注) |
| BOOT ROM | 不用 SRAM;常量 `$readmemh` mux 树(`rtl/soc/boot/boot_rom.sv` + `AMECHIP_BOOTROM_CONST`) |
| 宏电源 | **衍生 LEF**(`rtl_macro/..._p4a.lef`,met4 电源条引脚)+ `pdn_macro_fix.tcl`
| |   (POST_PDN_TCL)画条/焊盘精准 via3/孤儿轨道清理;详见 `gen_macro_lef.py` 头注与 P4A_REPORT §2 |
| 宏摆放 | `pnr_macro_place.tcl`(POST_MACRO_PLACE 钩子,覆盖 RTLMP):三宏一字排开 die 底部 |
| 报告 | `sta_top20.tcl` / `sta_blocks.tcl` / `sta_detail.tcl`,用 OpenSTA `> file` 重定向 |
| SDF | `scripts/export_sdf.sh`(ORFS 默认不产 SDF;读 6_final.odb + 6_final.spef 后 write_sdf) |
| 出图 | `scripts/gds_png.py`(klayout -b,整芯片 + 区域 PNG) |

## 目录

```text
config.mk                  ORFS DESIGN_CONFIG(AME_SRAM_MACRO 开关)
filelist.f                 flop 存储源清单(对照口径)
filelist_macro.f           宏化源清单(P4A 终版)
constraints/amechip_top.sdc
rtl_macro/                 宏化包装(sram_behav/ame_buf_rf 宏分支 + 宏黑盒声明)
rtl_variants/              XMEM_DW=32 面积评估变体(不参与整芯片)
pdn_amechip.tcl            平台 PDN 包装(补宏电源连接)
pnr_macro_place.tcl        宏手工摆放(POST_MACRO_PLACE 钩子)
scripts/
  filelist.sh              展开 filelist(.f/_macro.f)
  run_sta.sh               对 1_synth 跑 STA(自动加载宏 lib)
  sta_top20.tcl            全芯片 top-20/violators/DRC
  sta_blocks.tcl           按模块分组
  sta_detail.tcl           MAC/requant/buffer 细分
  export_sdf.sh/.tcl       终版 SDF 导出(P4B 反标)
  gds_png.py               KLayout 批量出图
```

## 坑位速查

1. SDC `set_driving_cell -pin X`(不是 `Y`)。
2. 复位分发必须 false path(`-to *RESET_B/*SET_B`、`-from *u_cr.sync_ff*`),否则 5.5k fanout 的 recovery 路径占满 top-20。
3. 改 SDC 后手动 `cp syn/amechip/constraints/amechip_top.sdc <RESULTS_DIR>/1_2_yosys.sdc`(或跑完整 `make synth`)。
4. boot_rom 常量 hex 与 mem_ss_top 的 `BOOT_INIT` 用绝对路径;仓库迁移时同步。
5. **宏的 .v 功能模型严禁放进综合 filelist**(内部 mem 数组会被综合成 flop,宏化失效);.v 仅 P4B 门仿用。黑盒端口骨架在 `rtl_macro/sram_macros_bb.sv`。
6. yosys `synth` 默认 flatten,按模块面积需独立模块综合。
7. RTL 的 REAL 槽位包装层已由 P1BX-B 正式化进 `rtl/soc/`(原 `syn/amechip/rtl_shim/` 已于 P4A 移除——filelist 不再引用,属死文件)。
