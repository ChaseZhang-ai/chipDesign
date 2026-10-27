# -----------------------------------------------------------------------------
# filelist.f — amechip_top 综合源文件清单(W4/P4A0)
#
# 顺序:三个 package 先读;其后接口与 RTL;最后是 REAL 槽位包装层。
# 关键:只列**真模块**,不列 rtl/soc/stub/*(由 AMECHIP_REAL_* 宏禁用);
#       rtl/soc 的包装层提供 amechip_top 期望的 amechip_cpu/amechip_ame/amechip_mem
#       槽位(P1BX-B 起为 rtl/ 正式成员,ORFS 直接综合,不再依赖 syn/ 外挂 shim)。
#       boot_rom.sv 以 AMECHIP_BOOTROM_CONST 常量路径综合(config.mk 注入);
#       仿真路径(+BOOT_HEX)由同一模块的 `ifndef 分支承载。
# 相对路径均相对仓库根 /home/zcz/verda/autoDecodeChip。
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
rtl/ame/ame_buf_rf.sv
rtl/ame/ame_ctrl.sv
rtl/ame/ame_core.sv

rtl/mem/sram_behav.sv
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

# ---- REAL 槽位包装层(P1BX-B 正式化,原 syn/rtl_shim 已删除依赖) ----
rtl/soc/soc2axi_master.sv
rtl/soc/axi2soc_bridge.sv
rtl/soc/amechip_cpu.sv
rtl/soc/amechip_ame.sv
rtl/soc/amechip_mem.sv

rtl/soc/amechip_top.sv
