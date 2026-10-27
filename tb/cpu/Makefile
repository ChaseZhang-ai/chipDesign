# -----------------------------------------------------------------------------
# tb/cpu/Makefile — RV32IM 核(P2A)回归:定向 + 随机差分,iverilog + verilator
#
#   make asm      生成全部 hex
#   make ref      生成全部 ISS 参考轨迹
#   make run      全量回归(汇编 → ISS → 双模拟器 → 差分),全绿退出 0
#   make area     yosys 面积粗估(FF/门数,报告到 stdout)
#   make clean
# -----------------------------------------------------------------------------

ROOT    := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../..)
SCRIPTS := $(ROOT)/scripts
OUT     := $(ROOT)/tb/cpu/out
GEN     := $(ROOT)/tb/cpu/gen

PYTHON  ?= python3

RTL_PKG  = $(ROOT)/rtl/amechip_pkg.sv
RTL_IF   = $(ROOT)/rtl/interfaces/ame_coproc_if.sv $(ROOT)/rtl/interfaces/axi_lite_if.sv $(ROOT)/rtl/interfaces/clk_rst_if.sv
RTL_CPU  = $(ROOT)/rtl/cpu/amecpu_pkg.sv $(ROOT)/rtl/cpu/cpu_regfile.sv $(ROOT)/rtl/cpu/cpu_alu.sv $(ROOT)/rtl/cpu/cpu_muldiv.sv $(ROOT)/rtl/cpu/cpu_csr.sv $(ROOT)/rtl/cpu/cpu_axi_bridge.sv $(ROOT)/rtl/cpu/ame_cpu.sv
TB_ALL   = $(ROOT)/tb/cpu/tb_ame_model.sv $(ROOT)/tb/cpu/tb_amecpu.sv
INC      = -I$(ROOT)/rtl -I$(ROOT)/rtl/interfaces -I$(ROOT)/tb/cpu

# 定向测试(t_irq 为 TB 定向用例,不做 ISS 差分)
DIRECTED := t_alu t_muldiv t_mem t_branch t_stall t_ame t_csr t_handshake t_smoke
NODIFF   := t_irq
RAND_SEEDS := 1 2 3 4

IV_SIM  := $(OUT)/iv_sim
VL_SIM  := $(OUT)/vl_obj/Vtb_amecpu

YOSYS   := $(HOME)/tools/openroad-flow-scripts/tools/install/yosys/bin/yosys
YOSYS   := $(if $(wildcard $(YOSYS)),$(YOSYS),yosys)

.PHONY: all asm ref run lint area clean
.DEFAULT_GOAL := run

all: run

# ---- 汇编 ----
DIRECTED_HEX := $(patsubst %,$(ROOT)/tb/cpu/hex/%.hex,$(DIRECTED) $(NODIFF))
RAND_HEX     := $(foreach s,$(RAND_SEEDS),$(GEN)/s00$(s)/prog.hex)

$(ROOT)/tb/cpu/hex/%.hex: $(ROOT)/tb/cpu/asm/%.s $(SCRIPTS)/cpu_asm.py
	$(PYTHON) $(SCRIPTS)/cpu_asm.py $< -o $@ -l $(OUT)/$*.lst

$(GEN)/s%00/prog.hex: ;

asm: $(DIRECTED_HEX) rand_asm

rand_asm:
	for s in $(RAND_SEEDS); do \
	  $(PYTHON) $(SCRIPTS)/cpu_gen_random.py --seed $$s --blocks 260 \
	    --out-dir $(GEN)/s00$$s || exit 1; \
	done

# ---- ISS 参考 ----
ref: $(DIRECTED_HEX) rand_asm
	for t in $(DIRECTED); do \
	  $(PYTHON) $(SCRIPTS)/cpu_iss.py $(ROOT)/tb/cpu/hex/$$t.hex \
	    -o $(OUT)/$$t.ref.trace || exit 1; \
	done
	for s in $(RAND_SEEDS); do :; done   # gen 已带 trace_ref.txt

# ---- 模拟器 ----
$(IV_SIM): $(RTL_PKG) $(RTL_IF) $(RTL_CPU) $(TB_ALL)
	iverilog -g2012 -o $@ $(INC) $(RTL_PKG) $(RTL_IF) $(RTL_CPU) $(TB_ALL) 2>&1 | grep -v "sorry" || true

$(VL_SIM): $(RTL_PKG) $(RTL_IF) $(RTL_CPU) $(TB_ALL)
	verilator --binary --timing -Wno-fatal -j 4 --Mdir $(OUT)/vl_obj \
	  +incdir+$(ROOT)/rtl +incdir+$(ROOT)/rtl/interfaces +incdir+$(ROOT)/tb/cpu \
	  --top-module tb_amecpu $(RTL_PKG) $(RTL_IF) $(RTL_CPU) $(TB_ALL)

# ---- 运行 ----
run: $(IV_SIM) $(VL_SIM) asm ref
	@rm -f $(OUT)/summary.txt
	@pass=0; fail=0; \
	for t in $(DIRECTED) $(NODIFF); do \
	  for simv in "iv:$(IV_SIM)" "vl:$(VL_SIM)"; do \
	    s=$${simv%%:*}; bin=$${simv#*:}; \
	    stall=20; \
	    [ "$$t" = "t_handshake" ] && stall=70; \
	    extra=""; \
	    [ "$$t" = "t_irq" ] && extra="+IRQAT=300"; \
	    if $$bin +HEX=$(ROOT)/tb/cpu/hex/$$t.hex +TRACE=$(OUT)/$$t.$$s.trace \
	       +MAXCYC=1000000 +STALLPCT=$$stall +SEED=$$s $$extra > $(OUT)/$$t.$$s.log 2>&1 \
	       && grep -q "^PASS" $(OUT)/$$t.$$s.log; then st=ok; else st=FAIL; fi; \
	    if [ "$$st" = ok ] && echo "$(DIRECTED)" | grep -qw "$$t"; then \
	      if $(PYTHON) $(SCRIPTS)/cpu_diff.py $(OUT)/$$t.ref.trace $(OUT)/$$t.$$s.trace \
	         >> $(OUT)/$$t.$$s.log 2>&1; then st=ok; else st=FAIL; fi; \
	    fi; \
	    if [ "$$st" = ok ]; then pass=$$((pass+1)); echo "  [ok]   $$t ($$s)" | tee -a $(OUT)/summary.txt; \
	    else fail=$$((fail+1)); echo "  [FAIL] $$t ($$s)" | tee -a $(OUT)/summary.txt; fi; \
	  done; \
	done; \
	for s in $(RAND_SEEDS); do \
	  for simv in "iv:$(IV_SIM)" "vl:$(VL_SIM)"; do \
	    s2=$${simv%%:*}; bin=$${simv#*:}; \
	    if $$bin +HEX=$(GEN)/s00$$s/prog.hex +TRACE=$(OUT)/rand$$s.$$s2.trace \
	       +MAXCYC=2000000 +STALLPCT=30 +SEED=$$s > $(OUT)/rand$$s.$$s2.log 2>&1 \
	       && grep -q "^PASS" $(OUT)/rand$$s.$$s2.log \
	       && $(PYTHON) $(SCRIPTS)/cpu_diff.py $(GEN)/s00$$s/trace_ref.txt $(OUT)/rand$$s.$$s2.trace \
	          >> $(OUT)/rand$$s.$$s2.log 2>&1; then \
	      pass=$$((pass+1)); n=$$(wc -l < $(GEN)/s00$$s/trace_ref.txt); \
	      echo "  [ok]   rand s00$$s ($$s2, $$n instrs)" | tee -a $(OUT)/summary.txt; \
	    else \
	      fail=$$((fail+1)); echo "  [FAIL] rand s00$$s ($$s2)" | tee -a $(OUT)/summary.txt; \
	    fi; \
	  done; \
	done; \
	echo "=================================="; \
	echo "  TOTAL: pass=$$pass fail=$$fail" | tee -a $(OUT)/summary.txt; \
	[ "$$fail" = 0 ]

# ---- lint(仅 RTL,不含 TB) ----
lint:
	iverilog -g2012 -t null $(INC) $(RTL_PKG) $(RTL_IF) $(RTL_CPU) 2>&1 | grep -v sorry; \
	verilator --lint-only -Wno-fatal -Wno-DECLFILENAME -Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL \
	  +incdir+$(ROOT)/rtl +incdir+$(ROOT)/rtl/interfaces \
	  --top-module ame_cpu $(RTL_PKG) $(RTL_IF) $(RTL_CPU)

# ---- 面积粗估(yosys 0.70 前端限制的绕行见 scripts/cpu_area_synth.py) ----
area:
	$(PYTHON) $(SCRIPTS)/cpu_area_synth.py -o $(OUT)/yosys_area.rpt

clean:
	rm -rf $(OUT)/vl_obj $(IV_SIM) $(OUT)/*.trace $(OUT)/*.log $(OUT)/summary.txt $(OUT)/*.lst
	rm -rf $(GEN)
