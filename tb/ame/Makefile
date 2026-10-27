# tb/ame/Makefile — AME 单元验证(P2B)
#
#   make gen          生成 golden 用例(python,51 组)
#   make run          iverilog 全量回归(默认几何 16×16)
#   make run8         8×8 参数化构建回归
#   make vrun         verilator 全量回归(16×16)
#   make proto        协议定向 + 吞吐计数器证据(iverilog)
#   make lint         双 lint(AME RTL)
#   make all = lint + gen + run + proto
#   make clean

ROOT    := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../..)
RTL     := $(ROOT)/rtl
INCS    := -I$(RTL) -I$(RTL)/interfaces
AMESRC  := $(RTL)/ame/ame_core.sv $(RTL)/ame/ame_ctrl.sv $(RTL)/ame/ame_array.sv \
           $(RTL)/ame/ame_buf_rf.sv $(RTL)/ame/ame_requant.sv $(RTL)/ame/ame_rqtab.sv
TB      := $(ROOT)/tb/ame
WORK    := $(TB)/work
GEOM    := m16n16

VLOG    := iverilog -g2012
VVP     := vvp

.PHONY: all gen run run8 vrun proto lint clean

all: lint gen run proto

lint:
	$(VLOG) $(INCS) -t null $(AMESRC)
	verilator --lint-only --top-module ame_core $(INCS) $(AMESRC)
	@echo "LINT PASS"

gen:
	python3 $(ROOT)/scripts/ame_golden_tb.py --work $(WORK)
	@# 8×8 几何用例(run8 用)
	python3 $(ROOT)/scripts/ame_golden_tb.py --work $(WORK) --m 8 --n 8

$(WORK)/sim16: $(TB)/tb_ame_golden.sv $(AMESRC)
	mkdir -p $(WORK)
	$(VLOG) $(INCS) -o $@ $(TB)/tb_ame_golden.sv $(AMESRC)

run: gen $(WORK)/sim16
	@pass=0; failn=0; \
	for c in $$(ls $(WORK)/$(GEOM)); do \
	  if $(VVP) $(WORK)/sim16 +case=$$c +ops=$(WORK)/$(GEOM)/$$c/ops.hex \
	       | tee $(WORK)/$(GEOM)/$$c/run.log | grep -q "GOLDEN RESULT: PASS"; then \
	    pass=$$((pass+1)); \
	  else \
	    failn=$$((failn+1)); echo "FAIL-CASE $$c"; \
	  fi; \
	done; \
	echo "=================================================="; \
	echo "GOLDEN REGRESSION (iverilog $(GEOM)): PASS=$$pass FAIL=$$failn"; \
	test $$failn -eq 0

run8: gen $(WORK)/sim8
	@pass=0; failn=0; \
	for c in $$(ls $(WORK)/m8n8); do \
	  [ -d $(WORK)/m8n8/$$c ] || continue; \
	  if $(VVP) $(WORK)/sim8 +case=$$c +ops=$(WORK)/m8n8/$$c/ops.hex \
	       | grep -q "GOLDEN RESULT: PASS"; then \
	    pass=$$((pass+1)); \
	  else \
	    failn=$$((failn+1)); echo "FAIL-CASE $$c"; \
	  fi; \
	done; \
	echo "GOLDEN REGRESSION (iverilog m8n8): PASS=$$pass FAIL=$$failn"; \
	test $$failn -eq 0

$(WORK)/sim8: $(TB)/tb_ame_golden.sv $(AMESRC)
	mkdir -p $(WORK)
	$(VLOG) $(INCS) -D AME_TB_M=8 -D AME_TB_N=8 -o $@ \
	  $(TB)/tb_ame_golden.sv $(AMESRC)

$(WORK)/vsim: $(TB)/tb_ame_golden.sv $(AMESRC)
	verilator --binary --top-module tb_ame_golden -j 4 -Wno-INITIALDLY -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC $(INCS) \
	  -o $(abspath $(WORK)/vsim) $(TB)/tb_ame_golden.sv $(AMESRC)

vrun: gen $(WORK)/vsim
	@pass=0; failn=0; \
	for c in $$(ls $(WORK)/$(GEOM)); do \
	  if $(WORK)/vsim +case=$$c +ops=$(WORK)/$(GEOM)/$$c/ops.hex \
	       | grep -q "GOLDEN RESULT: PASS"; then \
	    pass=$$((pass+1)); \
	  else \
	    failn=$$((failn+1)); echo "FAIL-CASE $$c"; \
	  fi; \
	done; \
	echo "GOLDEN REGRESSION (verilator $(GEOM)): PASS=$$pass FAIL=$$failn"; \
	test $$failn -eq 0

$(WORK)/proto_sim: $(TB)/tb_ame_proto.sv $(AMESRC)
	$(VLOG) $(INCS) -o $@ $(TB)/tb_ame_proto.sv $(AMESRC)

proto: gen $(WORK)/proto_sim
	$(VVP) $(WORK)/proto_sim | tee $(WORK)/proto.log
	@grep -q "PROTO RESULT: PASS" $(WORK)/proto.log

clean:
	rm -rf $(WORK)
