# -----------------------------------------------------------------------------
# filelist_macro.f — amechip_top 综合源文件清单(P4A 宏化版,任务 L)
#
# 与 filelist.f 的差异(SRAM 宏化):
#   * rtl/mem/sram_behav.sv  → syn/amechip/rtl_macro/sram_behav.sv
#     (宏分支:OC SRAM 4KB→sky130_sram_1rw1r_128x256_8;BOOT ROM/KV 保持 flop 分支)
#   * rtl/ame/ame_buf_rf.sv  → syn/amechip/rtl_macro/ame_buf_rf.sv
#     (WBUF/XBUF→sky130_sram_1rw1r_128x256_8;策略修正见该文件头:64x256_8
#      字宽仅 64b,无法一拍读 16B 行,不能按 P4A0 策略表映射)
#   * 新增 rtl_macro/sram_macros_bb.sv(宏黑盒端口骨架;时序/物理由
#     config.mk 的 ADDITIONAL_LIBS/LEFS/GDS 提供)
# 其余与 filelist.f 完全一致(package 在前、不含 stub、rtl/soc 正式包装层、
# BOOT ROM 常量树)。相对路径均相对仓库根 /home/zcz/verda/autoDecodeChip。
# -----------------------------------------------------------------------------
rtl/amechip_pkg.sv
rtl/soc/soc_pkg.sv
rtl/cpu/amecpu_pkg.sv

rtl/interfaces/axi_lite_if.sv
rtl/interfaces/clk_rst_if.sv
rtl/interfaces/ame_coproc_if.sv
rtl/interfaces/ame_dma_if.sv
rtl/interfaces/kv_sram_if.sv

rtl/soc/soc_rr_mux4.sv
rtl/soc/soc_intc.sv
rtl/soc/boot/boot_rom.sv
rtl/soc/soc_syscsr.sv
rtl/soc/soc_uart.sv

rtl/cpu/cpu_alu.sv
rtl/cpu/cpu_muldiv.sv
rtl/cpu/cpu_regfile.sv
rtl/cpu/cpu_csr.sv
rtl/cpu/cpu_axi_bridge.sv
rtl/cpu/ame_cpu.sv

rtl/ame/ame_rqtab.sv
rtl/ame/ame_requant.sv
rtl/ame/ame_array.sv
syn/amechip/rtl_macro/ame_buf_rf.sv
rtl/ame/ame_ctrl.sv
rtl/ame/ame_core.sv

syn/amechip/rtl_macro/sram_macros_bb.sv
syn/amechip/rtl_macro/sram_behav.sv
rtl/mem/axi_mem_slave.sv
rtl/mem/axi_decerr_slave.sv
rtl/mem/axi_xbar_port.sv
rtl/mem/axi_xbar.sv
rtl/mem/memc_xmem.sv
rtl/mem/kv_backend_sram.sv
rtl/mem/kv_backend_axi.sv
rtl/mem/kv_ctrl.sv
rtl/mem/dma_engine.sv
rtl/mem/mem_ss_top.sv

# ---- REAL 槽位包装层(P1BX-B 正式化) ----
rtl/soc/soc2axi_master.sv
rtl/soc/axi2soc_bridge.sv
rtl/soc/amechip_cpu.sv
rtl/soc/amechip_ame.sv
rtl/soc/amechip_mem.sv

rtl/soc/amechip_top.sv
