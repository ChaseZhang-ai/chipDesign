#!/usr/bin/env bash
# P3D: build the full-chip e2e TB with Verilator (REAL slots).
# P1BX-B:verify_p3d_memc_patch.sv 仿真规避已删除——P3C-2/P3D-07 的正式修复
# 已落入 rtl/mem/memc_xmem.sv(读预取陈旧槽旁路),直接以 rtl/ 为准。
set -euo pipefail
cd "$(dirname "$0")"
R=../../rtl
verilator --binary --timing -Wno-fatal -j 4 --top-module verify_soc_e2e \
  -I$R -I$R/cpu -I$R/ame -I$R/mem -I$R/soc -I$R/interfaces \
  -DAMECHIP_REAL_CPU -DAMECHIP_REAL_AME -DAMECHIP_REAL_MEM -DAMECHIP_REAL_BOOTROM \
  -o vsoc_e2e \
  $R/amechip_pkg.sv $R/interfaces/ame_coproc_if.sv $R/interfaces/ame_dma_if.sv \
  $R/interfaces/axi_lite_if.sv $R/interfaces/clk_rst_if.sv $R/interfaces/kv_sram_if.sv \
  $R/cpu/amecpu_pkg.sv $R/cpu/cpu_regfile.sv $R/cpu/cpu_alu.sv $R/cpu/cpu_muldiv.sv \
  $R/cpu/cpu_csr.sv $R/cpu/cpu_axi_bridge.sv $R/cpu/ame_cpu.sv \
  $R/ame/ame_buf_rf.sv $R/ame/ame_array.sv $R/ame/ame_rqtab.sv $R/ame/ame_requant.sv \
  $R/ame/ame_ctrl.sv $R/ame/ame_core.sv \
  $R/mem/sram_behav.sv $R/mem/axi_mem_slave.sv $R/mem/axi_decerr_slave.sv \
  $R/mem/axi_xbar_port.sv $R/mem/axi_xbar.sv $R/mem/dma_engine.sv \
  $R/mem/kv_backend_axi.sv $R/mem/kv_backend_sram.sv $R/mem/kv_ctrl.sv \
  $R/mem/memc_xmem.sv $R/mem/mem_ss_top.sv \
  $R/soc/soc_pkg.sv $R/soc/soc_uart.sv $R/soc/soc_syscsr.sv $R/soc/soc_intc.sv \
  $R/soc/boot/boot_rom.sv $R/soc/amechip_top.sv \
  verify_p3d_slots.sv verify_soc_e2e.sv
