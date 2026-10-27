# -----------------------------------------------------------------------------
# syn/amechip/config.mk — AME-Chip 整芯片综合配置(ORFS DESIGN_CONFIG)
#
# 用法(ORFS 树外运行,不写 ORFS 自带 design/ 目录):
#   cd ~/tools/openroad-flow-scripts/flow
#   source ../env.sh
#   make DESIGN_CONFIG=/home/zcz/verda/autoDecodeChip/syn/amechip/config.mk \
#        WORK_HOME=/home/zcz/verda/autoDecodeChip/pnr/amechip \
#        FLOW_VARIANT=p4a0 synth
#
# 关键:必须启用四个 AMECHIP_REAL_* 宏,否则综合的是 stub(结果无意义)。
#       P1BX-B 后直接复用本文件(RTL 路径不变,shim 若已上游可删对应行)。
# -----------------------------------------------------------------------------

export DESIGN_NAME = amechip_top
export PLATFORM    = sky130hd
export DESIGN_NICKNAME = amechip

# 本文件所在目录与仓库根(不依赖调用者 cwd)
AME_SYN_DIR := $(patsubst %/,%,$(dir $(lastword $(MAKEFILE_LIST))))
AME_ROOT    := $(abspath $(AME_SYN_DIR)/../..)

# ---- 源文件 ----
# 用 filelist 保持顺序(package 在前),展开为绝对路径。
# AME_SRAM_MACRO=1(P4A 终版,P&R/GDS 流程)用 filelist_macro.f:
#   OC SRAM 4KB / WBUF / XBUF → sky130_sram_1rw1r_128x256_8;
#   =0 用 filelist.f(flop 存储原版,与 P1BX-B 基线口径一致,供对照)。
AME_SRAM_MACRO ?= 1
ifeq ($(AME_SRAM_MACRO),1)
export VERILOG_FILES = $(shell bash $(AME_SYN_DIR)/scripts/filelist.sh $(AME_ROOT) macro)
else
export VERILOG_FILES = $(shell bash $(AME_SYN_DIR)/scripts/filelist.sh $(AME_ROOT))
endif
export VERILOG_INCLUDE_DIRS = $(AME_ROOT)/rtl $(AME_ROOT)/rtl/interfaces $(AME_ROOT)/rtl/soc

# ---- 真模块宏(不可省) ----
export VERILOG_DEFINES = -D AMECHIP_REAL_CPU -D AMECHIP_REAL_AME -D AMECHIP_REAL_MEM -D AMECHIP_REAL_BOOTROM -D AMECHIP_BOOTROM_CONST

# ---- 语言前端 ----
# yosys 自带 read_verilog 不支持 function 内 return(soc_pkg / pkg 风格),
# 故用 slang;--single-unit 让 `include 守卫跨文件生效(否则 package 重复定义),
# --allow-use-before-declare 兼容 CPU 里"连续赋值引用后声明信号"的写法。
export SYNTH_HDL_FRONTEND = slang
# boot_rom 的仿真专用 initial 已由 syn/amechip/rtl_shim/boot_rom.sv 替换为
# 常量 $readmemh;mem_ss_top 的 BOOT_INIT 参数也指向同一 hex,故不再需要
# --ignore-initial(ROM 会被综合成常量 mux 树,而不是 16k 触发器)。
export SYNTH_SLANG_ARGS   = --single-unit --allow-use-before-declare

# ---- SDC ----
# P4A2 裁决:签核频率 84.6 MHz(11.82 ns),不再追 120/100。实现约束保持首轮
# 7.576 ns(amechip_top.sdc)不变:首轮以 7.576 猛压实现,把结构路径磨到
# ~11.82 ns 地板(fmax 84.60);p4a3 实验(实现约束=11.82)证明在签核频率上
# 实现会因估计/真实延迟缺口丢 ~0.5 ns(fmax 80.89),见 reports/P4A2_REPORT.md。
# 签核 STA 用 amechip_top_84p6.sdc 口径(sta_final.tcl AME_SIGNOFF_PERIOD=11.820),
# 7.576 口径报告副本按任务要求归档。
export SDC_FILE = $(AME_SYN_DIR)/constraints/amechip_top.sdc

# ---- 综合选项 ----
# 片内 SRAM/ROM 为行为级数组(OC 4KB / ROM 2KB),默认 4096 bit 上限会挡住流程;
# 本设计不需要 mock large memories,直接放宽到 256 Kbit(Yosys 映射为 FF+MUX)。
export SYNTH_MEMORY_MAX_BITS = 262144
export SYNTH_MOCK_LARGE_MEMORIES = 0
# P4A3 复核:abc_speed.script(ABC_AREA=0)才是 P4A2 全部签核 variant
# (p4a2/p4a3/p4a4/p4a5)的实际配方(见各自 1_2_yosys.log 的 abc -script 行);
# ABC_AREA=1(abc_area.script, map -B 0.9)在 v0.3 RTL 上把 ROM mux 树摊成
# nand2 门汤:cell 96.8k→134.8k(+39%)且面积反增 +1.25%(p4a3rtl03 实测)。
# speed 脚本的 &nf/&if -g 能识别 mux4,面积/面积-cell 双优,时序由 OpenROAD STA 报告。
export ABC_AREA = 0
export SWAP_ARITH_OPERATORS = 0
export SYNTH_HIERARCHICAL = 0
export SYNTH_OPT_HIER = 0
# 不自动插时钟门控(契约单时钟,先保持与 P2B 面积口径可比)
export INFER_CLKGATES = 0

# ---- 物理(P4A 正式 P&R;显式 die,宏行布局见 pnr_macro_place.tcl) ----
# p4a1 实测:std cell 1.061 mm² + 3 宏 2.166 mm²(1141.72×632.475 ×3 一字排开)。
# die 3468×1100 = 3.815 mm²:宏行底部 + 上方/下方 std 条带,目标密度 ~0.65。
# 超出 3 mm² 硬上限的原因与量化见 reports/P4A_REPORT.md(宏字宽策略修正)。
ifeq ($(AME_SRAM_MACRO),1)
export DIE_AREA  = 0 0 3480 1300
export CORE_AREA = 4 4 3476 1296
export PLACE_DENSITY = 0.60
else
export CORE_UTILIZATION = 45
export PLACE_DENSITY = 0.55
endif
export TNS_END_PERCENT = 100

# ---- P4A: SRAM 宏(AME_SRAM_MACRO=1 时启用) ----
# 本机 ORFS 自带 OpenRAM 预生成宏(非下载):
#   $(HOME)/tools/openroad-flow-scripts/flow/platforms/sky130ram
# 策略修正(详见 syn/amechip/rtl_macro/ame_buf_rf.sv 头注与 reports/P4A_REPORT.md):
#   P4A0 策略表的 64x256_8"半用"方案不可行(字宽 64b < 16B 行读),WBUF/XBUF
#   与 OC SRAM 均用 128x256_8(WBUF/XBUF 半用,1KB/4KB)。
ifeq ($(AME_SRAM_MACRO),1)
SRAM_DIR := $(HOME)/tools/openroad-flow-scripts/flow/platforms/sky130ram
SRAM_128 := $(SRAM_DIR)/sky130_sram_1rw1r_128x256_8/sky130_sram_1rw1r_128x256_8
# 衍生 LEF(P4A): vdd/gnd 改声明为 met4 电源条(microwatt RAM512 形态), 配套
# POST_PDN_TCL 画条+焊盘 via3。原版 LEF 电源引脚是 6351 个交错 met3 小焊盘,
# 与平台 macro grid 和 PSM 全形状连通检查均不兼容(P4A 前两轮 PSM-0069 根因)。
# 重建方法见 scripts/gen_macro_lef.py(facts 表来自 scripts/extract_pdn_facts.tcl);
# 改 DIE_AREA/CORE_AREA/pdn.tcl 后需重建。
AME_DERIVED_LEF := $(AME_SYN_DIR)/rtl_macro/sky130_sram_1rw1r_128x256_8_p4a.lef
export ADDITIONAL_LEFS += $(AME_DERIVED_LEF)
export ADDITIONAL_LIBS += $(SRAM_128)_TT_1p8V_25C.lib
export ADDITIONAL_GDS  += $(SRAM_128).gds
# 宏电源引脚是小写 vdd/gnd,平台 pdn 只连 VPWR/VGND/VDD/VSS —— 用本项目的
# pdn_amechip.tcl 包一层(先注册宏电源连接, 再 source 平台)。
export PDN_TCL = $(AME_SYN_DIR)/pdn_amechip.tcl
# pdngen 后: 画宏 met4 电源条 + 焊盘 via3 + 孤儿轨道拯救(见 scripts/ 头注)
export POST_PDN_TCL = $(AME_SYN_DIR)/scripts/pdn_macro_fix.tcl
# 宏摆放在 POST_MACRO_PLACE_TCL 中手工固定(策略:OCRAM 左列下、WBUF 左列上、
# XBUF 右列竖放;见 pnr_macro_place.tcl),RTLMP 结果被其覆盖。
export POST_MACRO_PLACE_TCL = $(AME_SYN_DIR)/pnr_macro_place.tcl
endif

# ---- 报告 ----
export REPORT_CLOCK_SKEW = 1

# ---- P4A2 时序加压(仅 p4a5)----
# ROM 冻结重映射后 p4a4 fmax 82.69(地板 12.09 ns),距 84.6 差 0.27 ns;
# 以 SETUP_SLACK_MARGIN=0.5 加压 resizer/grt repair(-setup_margin)夺回,
# 仅对 p4a5 生效,p4a2/p4a4 复现不受影响。依据:post-CTS WNS ≈ post-route
# WNS(±0.3,p4a2/p4a4 校准),CTS 站可作廉价 A/B 判据。
ifeq ($(FLOW_VARIANT),p4a5)
export SETUP_SLACK_MARGIN = 0.5
endif
