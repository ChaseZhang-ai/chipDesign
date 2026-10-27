# =============================================================================
# tb/soc/Makefile — AME-Chip SoC 冒烟(P2D)
#
#   make hex          生成 boot.hex / boot_jump.hex / demo.hex(build_hex.py)
#   make smoke1       全 stub boot 冒烟(UART = "AME-CHIP BOOT OK")
#   make smoke2       stub_cpu+stub_ame 总线级微内核(boot 跳转 + demo GEMV)
#   make run          hex + smoke1 + smoke2(全绿 = W2 验收 b/c)
#   make demo-switch  切换宏机制演示(stub↔real 槽位各跑一遍,验收 d)
#   make lint         iverilog -t null + verilator --lint-only(RTL)
#   make port-check   amechip_top 端口 ⇄ 契约逐项核对(验收 a)
#   make all          run + lint + port-check + demo-switch
#   make clean
# =============================================================================

ROOT   := ../..
BUILD  := build
SIM    := iverilog
VFLAGS := -g2012

PKG      := $(ROOT)/rtl/amechip_pkg.sv
IFACES   := $(ROOT)/rtl/interfaces/ame_coproc_if.sv \
            $(ROOT)/rtl/interfaces/ame_dma_if.sv \
            $(ROOT)/rtl/interfaces/axi_lite_if.sv \
            $(ROOT)/rtl/interfaces/clk_rst_if.sv \
            $(ROOT)/rtl/interfaces/kv_sram_if.sv
SOC_RTL  := $(ROOT)/rtl/soc/soc_pkg.sv \
            $(ROOT)/rtl/soc/soc_uart.sv \
            $(ROOT)/rtl/soc/soc_syscsr.sv \
            $(ROOT)/rtl/soc/soc_intc.sv \
            $(ROOT)/rtl/soc/soc_rr_mux4.sv \
            $(ROOT)/rtl/soc/boot/boot_rom.sv \
            $(ROOT)/rtl/soc/stub/stub_sram.sv \
            $(ROOT)/rtl/soc/stub/stub_bootrom.sv \
            $(ROOT)/rtl/soc/stub/stub_xbar.sv \
            $(ROOT)/rtl/soc/stub/stub_dma.sv \
            $(ROOT)/rtl/soc/stub/stub_kvcsr.sv \
            $(ROOT)/rtl/soc/stub/stub_memc.sv \
            $(ROOT)/rtl/soc/stub/stub_ame.sv \
            $(ROOT)/rtl/soc/stub/stub_cpu.sv \
            $(ROOT)/rtl/soc/stub/stub_mem.sv \
            $(ROOT)/rtl/soc/amechip_top.sv
RTL_ALL  := $(PKG) $(IFACES) $(SOC_RTL)

# 注意:vvp 在 $(BUILD) 目录内运行,plusarg 路径相对 build/
# BOOT_HEX_STD 有两个解析语境:vvp plusargs 在 build/ 内运行(三级 ../..),
# 而 make 目标从 tb/soc/ 解析(两级 ../..)——后者曾误用三级路径,导致 make
# 永远找不到目标而反复重跑 build_hex.py + 护栏(P4A2-02 追记修复)。
BOOT_HEX_STD   := ../../../rtl/soc/boot/boot.hex        # vvp 用(build/ 内)
BOOT_HEX_STD_MK := ../../rtl/soc/boot/boot.hex          # make 目标用
BOOT_HEX_JUMP  := $(BUILD)/boot_jump.hex                # build_hex.py 的实际输出位置
DEMO_HEX      := $(BUILD)/demo.hex

.PHONY: all run hex smoke1 smoke2 demo-switch lint port-check clean

all: run lint port-check demo-switch
run: hex smoke1 smoke2

# ---- 程序镜像 ----------------------------------------------------------------
hex: $(BOOT_HEX_STD_MK) $(BOOT_HEX_JUMP) $(DEMO_HEX)

# P4A2 ROM 冻结护栏(裁决 P4B-01/P4B-06): build_hex.py boot 会从 boot.s 重装
# 旧停机镜像,生成后必须与冻结镜像(syn/amechip/boot_frozen/boot.hex,P3D loader)
# md5 一致;不一致则恢复冻结镜像并报错中止,防止再次静默回退。
$(BOOT_HEX_STD_MK) $(BOOT_HEX_JUMP):
	python3 $(ROOT)/scripts/build_hex.py boot
	bash $(ROOT)/syn/amechip/scripts/check_boot_hex.sh $(realpath $(ROOT))

$(DEMO_HEX) $(BUILD)/demo.map:
	python3 $(ROOT)/scripts/build_hex.py demo

# ---- smoke -------------------------------------------------------------------
# -s 指定根模块:iverilog 否则会把未实例化的模块(如 boot_rom)当根跑 initial
$(BUILD)/smoke1.vvp: $(RTL_ALL) tb_smoke_1.sv | $(BUILD)
	$(SIM) $(VFLAGS) -s tb_smoke_1 -o $@ $(RTL_ALL) tb_smoke_1.sv

$(BUILD)/smoke2.vvp: $(RTL_ALL) tb_smoke_2.sv | $(BUILD)
	$(SIM) $(VFLAGS) -s tb_smoke_2 -o $@ $(RTL_ALL) tb_smoke_2.sv

$(BUILD):
	mkdir -p $(BUILD)

smoke1: $(BUILD)/smoke1.vvp
	cd $(BUILD) && vvp smoke1.vvp +BOOT_HEX=$(BOOT_HEX_STD) | tee smoke1.log
	@grep -q "SMOKE1 PASS" $(BUILD)/smoke1.log && echo "== smoke1 PASS ==" || \
	  (echo "== smoke1 FAILED =="; exit 1)

smoke2: $(BUILD)/smoke2.vvp
	cd $(BUILD) && vvp smoke2.vvp +BOOT_HEX=boot_jump.hex +SRAM_HEX=demo.hex | tee smoke2.log
	@grep -q "SMOKE2 PASS" $(BUILD)/smoke2.log && echo "== smoke2 PASS ==" || \
	  (echo "== smoke2 FAILED =="; exit 1)

# ---- 切换宏机制演示(验收 d) ---------------------------------------------------
# rtl/cpu、rtl/ame、rtl/mem 目前为空 → 真 P2A/P2B/P2C 未就绪,用 tb/soc/fake_real
# 占位模块演示:宏翻转例化、端口对接、smoke 仍绿(证据 = 各槽位 $display 标记)。
# BOOTROM 为第 4 个演示槽位:默认 stub(TB 传 +BOOT_HEX),REAL 时换 boot_rom
# (参数默认路径自加载,仍可被 +BOOT_HEX 覆盖)。
demo-switch: demo-switch-stubboot demo-switch-real

# ① 默认(全 stub)即 stub_bootrom 槽位:确认标记存在且 smoke 绿
demo-switch-stubboot: smoke1
	@grep -q "stub_bootrom" $(BUILD)/smoke1.log && \
	 echo "== demo-switch: stub_bootrom 槽位 PASS ==" || \
	 (echo "== demo-switch: stub_bootrom FAILED =="; exit 1)

# ② 四个契约槽位整体切换:fake_real(CPU/AME/MEM)+ 真 boot_rom,smoke 仍绿
demo-switch-real: $(BUILD)/smoke1_real.vvp
	cd $(BUILD) && vvp smoke1_real.vvp +BOOT_HEX=$(BOOT_HEX_STD) | tee smoke1_real.log
	@grep -q "SMOKE1 PASS" $(BUILD)/smoke1_real.log && \
	 grep -q "REAL-CPU 槽位" $(BUILD)/smoke1_real.log && \
	 grep -q "REAL-AME 槽位" $(BUILD)/smoke1_real.log && \
	 grep -q "REAL-MEM 槽位" $(BUILD)/smoke1_real.log && \
	 grep -q "\[boot_rom\] loaded" $(BUILD)/smoke1_real.log && \
	 echo "== demo-switch: REAL_CPU/AME/MEM/BOOTROM 槽位 PASS ==" || \
	 (echo "== demo-switch: REAL 槽位 FAILED =="; exit 1)

$(BUILD)/smoke1_real.vvp: $(RTL_ALL) tb_smoke_1.sv \
		fake_real/fake_real_cpu.sv fake_real/fake_real_ame.sv fake_real/fake_real_mem.sv | $(BUILD)
	$(SIM) $(VFLAGS) -s tb_smoke_1 -D AMECHIP_REAL_CPU -D AMECHIP_REAL_AME \
	  -D AMECHIP_REAL_MEM -D AMECHIP_REAL_BOOTROM \
	  -o $@ $(RTL_ALL) fake_real/fake_real_cpu.sv fake_real/fake_real_ame.sv \
	  fake_real/fake_real_mem.sv tb_smoke_1.sv

# ---- lint / 端口核对 ----------------------------------------------------------
lint:
	$(SIM) $(VFLAGS) -t null $(RTL_ALL) && echo "== iverilog lint OK =="
	verilator --lint-only -Wno-fatal --top-module amechip_top $(RTL_ALL) \
	  && echo "== verilator lint OK =="

port-check:
	python3 $(ROOT)/scripts/soc_check_ports.py

clean:
	rm -rf $(BUILD)

# =============================================================================
# P3D — 全 real 槽位端到端集成仿真(verify_ 前缀交付物)
#   make e2e         生成 golden 场景 + 汇编微内核 + 跑 3 prompt decode
#   make e2e-boot    仅集成冒烟(REAL 槽位 + boot ROM 打印)
#   make e2e-lint    整颗芯片 iverilog + verilator 双 lint(REAL 槽位)
# =============================================================================
PYTHON ?= $(shell command -v ~/venvs/tpu-mlir/bin/python 2>/dev/null || echo python3)
RTL_CPU := $(ROOT)/rtl/cpu/amecpu_pkg.sv \
           $(ROOT)/rtl/cpu/cpu_regfile.sv $(ROOT)/rtl/cpu/cpu_alu.sv \
           $(ROOT)/rtl/cpu/cpu_muldiv.sv $(ROOT)/rtl/cpu/cpu_csr.sv \
           $(ROOT)/rtl/cpu/cpu_axi_bridge.sv $(ROOT)/rtl/cpu/ame_cpu.sv
RTL_AME := $(ROOT)/rtl/ame/ame_buf_rf.sv $(ROOT)/rtl/ame/ame_array.sv \
           $(ROOT)/rtl/ame/ame_rqtab.sv $(ROOT)/rtl/ame/ame_requant.sv \
           $(ROOT)/rtl/ame/ame_ctrl.sv $(ROOT)/rtl/ame/ame_core.sv
RTL_MEM := $(ROOT)/rtl/mem/sram_behav.sv $(ROOT)/rtl/mem/axi_mem_slave.sv \
           $(ROOT)/rtl/mem/axi_decerr_slave.sv $(ROOT)/rtl/mem/axi_xbar_port.sv \
           $(ROOT)/rtl/mem/axi_xbar.sv $(ROOT)/rtl/mem/dma_engine.sv \
           $(ROOT)/rtl/mem/kv_backend_axi.sv $(ROOT)/rtl/mem/kv_backend_sram.sv \
           $(ROOT)/rtl/mem/kv_ctrl.sv $(ROOT)/rtl/mem/memc_xmem.sv \
           $(ROOT)/rtl/mem/mem_ss_top.sv
RTL_SLOTS := $(ROOT)/tb/soc/verify_p3d_slots.sv
RTL_E2E   := $(PKG) $(IFACES) $(RTL_CPU) $(RTL_AME) $(RTL_MEM) \
             $(ROOT)/rtl/soc/soc_pkg.sv $(ROOT)/rtl/soc/soc_uart.sv \
             $(ROOT)/rtl/soc/soc_syscsr.sv $(ROOT)/rtl/soc/soc_intc.sv \
             $(ROOT)/rtl/soc/boot/boot_rom.sv $(ROOT)/rtl/soc/amechip_top.sv
REAL_DEFS := -DAMECHIP_REAL_CPU -DAMECHIP_REAL_AME -DAMECHIP_REAL_MEM \
             -DAMECHIP_REAL_BOOTROM
INC       := -I$(ROOT)/rtl -I$(ROOT)/rtl/cpu -I$(ROOT)/rtl/ame \
             -I$(ROOT)/rtl/mem -I$(ROOT)/rtl/soc -I$(ROOT)/rtl/interfaces

$(BUILD)/soc_e2e.vvp: $(RTL_E2E) $(RTL_SLOTS) verify_soc_e2e.sv | $(BUILD)
	$(SIM) $(VFLAGS) $(INC) $(REAL_DEFS) -s verify_soc_e2e -o $@ \
	  $(RTL_E2E) $(RTL_SLOTS) verify_soc_e2e.sv

$(BUILD)/p3d_boot.hex: verify_p3d_boot.s | $(BUILD)
	python3 $(ROOT)/scripts/build_hex.py asm -o $@ --base 0x00010000 \
	  --rom-bytes 2048 --text-limit 2048 --data-limit 2048 $<
	@echo "== p3d_boot.hex =="

e2e-boot: $(BUILD)/soc_e2e.vvp $(BOOT_HEX_STD)
	cp $(BOOT_HEX_STD) $(BUILD)/p3d_boot.hex
	cd $(BUILD) && vvp soc_e2e.vvp +BOOT_ONLY +BOOT_HEX=../../../rtl/soc/boot/boot.hex \
	  | tee p3d_boot.log
	@grep -q "P3D BOOT PASS" $(BUILD)/p3d_boot.log && echo "== e2e boot PASS ==" || \
	  (echo "== e2e boot FAILED =="; exit 1)

$(BUILD)/p3d_scene.hex $(BUILD)/p3d_golden.npz $(BUILD)/p3d_exc_scene.hex: $(ROOT)/scripts/vfrd_golden.py \
		verify_p3d_decode.s verify_p3d_exc.s verify_p3d_exc_main.s
	$(PYTHON) $(ROOT)/scripts/vfrd_golden.py gen --out $(BUILD)

# Verilator 全芯片仿真(比 iverilog 快 ~300x);仿真用 memc 补丁见
# tb/soc/verify_p3d_memc_patch.sv 与 reports/issues/P3D.md P3D-07。
verilator-build:
	./verilator_build.sh

e2e: verilator-build $(BUILD)/p3d_boot.hex $(BUILD)/p3d_scene.hex $(BUILD)/p3d_exc_scene.hex
	cd $(BUILD) && ../obj_dir/vsoc_e2e +KVDUMP +XMEM_HEX=p3d_scene.hex \
	  +BOOT_HEX=../../../rtl/soc/boot/boot.hex +EPROMPTS=3 +DUMP=p3d > p3d_e2e.log 2>&1
	cd $(BUILD) && ../obj_dir/vsoc_e2e +XMEM_HEX=p3d_exc_scene.hex \
	  +BOOT_HEX=../../../rtl/soc/boot/boot.hex +EPROMPTS=0 +DUMP=p3d_exc > p3d_exc_run.log 2>&1
	$(PYTHON) $(ROOT)/scripts/vfrd_golden.py check --work $(BUILD)
	@grep -q "P3D CHECK PASS" $(BUILD)/p3d_check.log && echo "== e2e PASS ==" || \
	  (echo "== e2e FAILED =="; exit 1)

e2e-exc: verilator-build $(BUILD)/p3d_boot.hex $(BUILD)/p3d_exc_scene.hex
	cd $(BUILD) && ../obj_dir/vsoc_e2e +XMEM_HEX=p3d_exc_scene.hex \
	  +BOOT_HEX=../../../rtl/soc/boot/boot.hex +EPROMPTS=0 +DUMP=p3d_exc > p3d_exc_run.log 2>&1
	@head -1 $(BUILD)/p3d_exc_exc.hex | grep -qi e0c0de01 && echo "== exception PASS ==" || \
	  (echo "== exception FAILED =="; exit 1)

e2e-lint:
	$(SIM) $(VFLAGS) $(INC) $(REAL_DEFS) -t null $(RTL_E2E) $(RTL_SLOTS) \
	  && echo "== iverilog REAL lint OK =="
	verilator --lint-only -Wno-fatal $(INC) $(REAL_DEFS) \
	  --top-module amechip_top $(RTL_E2E) $(RTL_SLOTS) \
	  && echo "== verilator REAL lint OK =="
