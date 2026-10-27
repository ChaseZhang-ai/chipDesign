# -----------------------------------------------------------------------------
# tb/mem/Makefile — P2C 存储子系统回归(iverilog 仿真 + verilator lint)
#
# 目标:
#   make all        = lint + golden + run(全量)
#   make lint       = 双 lint(rtl/mem 逐顶层 + TB 编译)  ← verilator/iverilog 全绿
#   make golden     = 生成 KV python golden 激励/期望文件
#   make run        = 运行 tb_xbar / tb_dma / tb_kv(B) / tb_kv(A)
#   make clean
#
# 说明:
#   - 功能运行以 iverilog;verilator 以 --lint-only 全量检查(RTL+TB 编译通过)。
#   - tb_kv 后端 A 全量场景仿真时长约 15-20 分钟(4M 半字 PSRAM 模型),
#     可用 make run-kv-b(默认必跑)替代;后端 B 为 KV 语义验收主证据。
# -----------------------------------------------------------------------------
ROOT    := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../..)
PKG     := $(ROOT)/rtl/amechip_pkg.sv
RTL     := $(ROOT)/rtl/mem
IFDIR   := $(ROOT)/rtl/interfaces
TB      := $(ROOT)/tb/mem
GOLDEN  := $(ROOT)/models/kv_golden
INC     := -I$(ROOT)/rtl -I$(IFDIR) -I$(TB)
IVERILOG:= iverilog -g2012
VERILATOR:= verilator --lint-only --timing -Wno-TIMESCALEMOD -I$(ROOT)/rtl -I$(IFDIR) -I$(TB)
# TB 为测试代码:允许位宽扩展/截断等非功能告警;RTL 检查保持严格
VERILATOR_TB:= $(VERILATOR) -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-UNUSEDSIGNAL \
               -Wno-UNUSEDPARAM -Wno-CASEINCOMPLETE -Wno-DECLFILENAME \
               -Wno-BLKANDNBLK -Wno-LATCH -Wno-COMBDLY -Wno-MULTIDRIVEN
RTLF    := $(PKG) $(wildcard $(RTL)/*.sv)
TBF     := $(TB)/tb_stubs.sv
OUT     := $(ROOT)/build/tb_mem

FILES_XBAR := $(RTLF) $(TBF) $(TB)/tb_xbar.sv
FILES_DMA  := $(RTLF) $(TBF) $(TB)/tb_dma.sv
FILES_KV   := $(RTLF) $(TBF) $(TB)/tb_kv.sv

# 判定:输出含 "TB_xxx: PASS"
RUNCHECK = grep -q "$(1): PASS" $(2) && echo "$(1): PASS" || \
           (echo "$(1): FAIL"; tail -20 $(2); exit 1)

.PHONY: all lint golden run run-xbar run-dma run-kv-b run-kv-a clean help

all: lint golden run

help:
	@sed -n '2,20p' $(MAKEFILE_LIST)

$(OUT):
	@mkdir -p $(OUT)

# ---------------------------------------------------------------- 双 lint
lint: $(OUT)
	@echo "== iverilog 构建(3 个 TB) =="
	@$(IVERILOG) -o $(OUT)/tb_xbar.vvp $(INC) $(FILES_XBAR) 2>&1 | grep -Ei "error" && exit 1 || true
	@$(IVERILOG) -o $(OUT)/tb_dma.vvp  $(INC) $(FILES_DMA)  2>&1 | grep -Ei "error" && exit 1 || true
	@$(IVERILOG) -o $(OUT)/tb_kv_b.vvp -DKV_BB $(INC) $(FILES_KV) 2>&1 | grep -Ei "error" && exit 1 || true
	@$(IVERILOG) -o $(OUT)/tb_kv_a.vvp $(INC) $(FILES_KV)  2>&1 | grep -Ei "error" && exit 1 || true
	@echo "  iverilog: PASS"
	@echo "== verilator lint(rtl/mem 逐顶层)== "
	@for top in axi_xbar axi_mem_slave axi_decerr_slave axi_xbar_port \
	            dma_engine memc_xmem kv_ctrl kv_backend_sram kv_backend_axi \
	            mem_ss_top; do \
	  $(VERILATOR) --top-module $$top $(RTLF) > /dev/null 2> $(OUT)/vl.log || \
	    { echo "  verilator($$top): FAIL"; cat $(OUT)/vl.log; exit 1; }; \
	done
	@echo "  verilator(rtl/mem): PASS"
	@echo "== verilator lint(TB:tb_xbar/tb_dma/tb_kv 后端 A/B)=="
	@$(VERILATOR_TB) --top-module tb_xbar $(FILES_XBAR) > /dev/null 2> $(OUT)/vl.log || \
	  { echo "  verilator(tb_xbar): FAIL"; head -10 $(OUT)/vl.log; exit 1; }
	@$(VERILATOR_TB) --top-module tb_dma $(FILES_DMA) > /dev/null 2> $(OUT)/vl.log || \
	  { echo "  verilator(tb_dma): FAIL"; head -10 $(OUT)/vl.log; exit 1; }
	@$(VERILATOR_TB) --top-module tb_kv $(FILES_KV) > /dev/null 2> $(OUT)/vl.log || \
	  { echo "  verilator(tb_kv): FAIL"; head -10 $(OUT)/vl.log; exit 1; }
	@echo "  verilator(TB): PASS"
	@echo "LINT: ALL GREEN"

# ---------------------------------------------------------------- golden
golden:
	@cd $(ROOT) && python3 scripts/mem_kv_golden.py
	@cp $(TB)/boot_rom.memh $(GOLDEN)/a/ 2>/dev/null || true
	@cp $(TB)/boot_rom.memh $(GOLDEN)/b/ 2>/dev/null || true
	@echo "GOLDEN: generated"

# ---------------------------------------------------------------- run
run: run-xbar run-dma run-kv-b
	@echo "RUN: ALL PASS(tb_xbar/tb_dma/tb_kv-B); 可另跑 make run-kv-a"

run-xbar: $(OUT) golden
	@cp $(TB)/boot_rom.memh $(OUT)/
	@cd $(OUT) && vvp $(OUT)/tb_xbar.vvp > tb_xbar.log 2>&1; \
	  $(call RUNCHECK,TB_XBAR,tb_xbar.log)
	@grep -E "\[fair\] CPU" $(OUT)/tb_xbar.log | tail -1

run-dma: $(OUT) golden
	@cp $(TB)/boot_rom.memh $(OUT)/
	@cd $(OUT) && vvp $(OUT)/tb_dma.vvp > tb_dma.log 2>&1; \
	  $(call RUNCHECK,TB_DMA,tb_dma.log)
	@grep -E "^\[perf\]" $(OUT)/tb_dma.log

run-kv-b: $(OUT) golden
	@cd $(GOLDEN)/b && vvp $(OUT)/tb_kv_b.vvp > tb_kv_b.log 2>&1; \
	  $(call RUNCHECK,TB_KV,tb_kv_b.log)
	@python3 $(ROOT)/scripts/mem_kv_golden.py --compare-dir $(GOLDEN)/b

# 全量后端 A(XMEM)场景:仿真约 15-20 分钟
run-kv-a: $(OUT) golden
	@cd $(GOLDEN)/a && vvp $(OUT)/tb_kv_a.vvp > tb_kv_a.log 2>&1; \
	  $(call RUNCHECK,TB_KV,tb_kv_a.log)
	@python3 $(ROOT)/scripts/mem_kv_golden.py --compare-dir $(GOLDEN)/a

clean:
	@rm -rf $(OUT)
