# -----------------------------------------------------------------------------
# amechip_top.sdc — 整芯片统一约束(P4A0;P1BX-B 后直接复用)
#
# 口径:
#   - 单时钟域 clk_i;目标 120 MHz(= 8.3333 ns),外加 10% 余量 → 7.576 ns。
#   - IO 延迟为**占位保守值**(无板级/PSRAM 数据手册):UART/GPIO/IRQ 1.5 ns,
#     XMEM 同步 PSRAM 2.0 ns。P4A 拿到器件时序后只改本文件 §3/§4 两组数字。
#   - 端口名/方向/宽度 = rtl/interfaces/amechip_top_ports.sv(冻结契约)。
#   - 无异步跨时钟域;rst_ni 为异步复位,设为 false path。
# -----------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# 1) 时钟
# ---------------------------------------------------------------------------
create_clock -name clk_i -period 7.576 [get_ports clk_i]
set_clock_uncertainty -setup 0.150 [get_clock clk_i]
set_clock_uncertainty -hold  0.050 [get_clock clk_i]
set_clock_transition 0.050 [get_clock clk_i]

# XMEM 输出时钟 = clk_i 直通(同步 PSRAM 器件时钟)
create_generated_clock -name xmem_clk -source [get_ports clk_i] \
  -divide_by 1 [get_ports xmem_clk_o]

# ---------------------------------------------------------------------------
# 2) 复位
# ---------------------------------------------------------------------------
set_false_path -from [get_ports rst_ni]
# 复位同步器属于异步复位路径;同步释放链已在 RTL 内,STA 按 false path 处理
set_false_path -from [get_ports rst_ni] -to [all_registers]
# 片内复位分发(同步器输出 → 数千个 RESET_B/SET_B)是复位树,不是数据路径;
# 综合阶段无 CTS/缓冲,若不禁用会以巨大 fanout 的 recovery 检查淹没真实关键路径。
# P4A CTS 后应单独约束复位树,但不要把它混进数据路径 top-N。
set_false_path -to [get_pins -hierarchical *RESET_B]
set_false_path -to [get_pins -hierarchical *SET_B]
# 复位同步器输出(rst_int)同时被部分逻辑当同步条件使用,零缓冲下 fanout≈5.5k,
# 会以 100+ ns 的假路径占据 top-N。复位分发整体不参与本次数据路径排序。
set_false_path -from [get_cells -hierarchical *u_cr.sync_ff*]

# ---------------------------------------------------------------------------
# 3) 输入约束
# ---------------------------------------------------------------------------
set_input_delay 1.500 -clock clk_i [get_ports {uart_rx_i gpio_i[*]}]
set_input_delay 2.000 -clock xmem_clk [get_ports {xmem_di_i[*] xmem_wait_i}]

# 输入驱动强度(占位:相当于一级 sky130hd buf)
set_driving_cell -lib_cell sky130_fd_sc_hd__buf_1 -pin X \
  [get_ports {uart_rx_i gpio_i[*] xmem_di_i[*] xmem_wait_i}]

# ---------------------------------------------------------------------------
# 4) 输出约束
# ---------------------------------------------------------------------------
set_output_delay 1.500 -clock clk_i [get_ports {uart_tx_o gpio_o[*] irq_o}]
set_output_delay 2.000 -clock xmem_clk \
  [get_ports {xmem_a_o[*] xmem_do_o[*] xmem_ce_no xmem_oe_no xmem_we_no}]

# 输出负载(占位:约 20 fF;P4A 按 pad/板级电容修订)
set_load 0.020 [get_ports {uart_tx_o gpio_o[*] irq_o xmem_a_o[*] xmem_do_o[*] \
                            xmem_ce_no xmem_oe_no xmem_we_no}]

# xmem_clk_o 是时钟输出,不作为数据路径
set_false_path -from [get_clocks clk_i] -to [get_ports xmem_clk_o]

# ---------------------------------------------------------------------------
# 5) 设计规则(仅在综合阶段做温和约束;P4A 可在 P&R 收紧)
# ---------------------------------------------------------------------------
set_max_transition 1.000 [current_design]
set_max_fanout   32     [current_design]

# ---------------------------------------------------------------------------
# 6) 不检查的路径
# ---------------------------------------------------------------------------
# boot_rom 在 P4A0 的 shim 中为死逻辑(mem_ss_top 内部已有 ROM),不影响时序
# 但仍保留;不额外设 false path,避免掩盖真实集成问题。
