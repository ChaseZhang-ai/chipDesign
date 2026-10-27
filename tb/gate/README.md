# tb/gate/ — P4B 门级后仿环境

## 交付物

| 文件 | 说明 |
|---|---|
| `tb_gate_boot.sv` | 门级/RTL 共用 TB(boot 场景):UART 逐字节捕获 + 顶层输出 X 看门狗 |
| `tb_gate_decode.sv` | P4B2 裁剪 decode 场景 TB(boot TB 派生,IDLE_CYC=90000 覆盖 loader 拷贝静默期) |
| `p4b2_decode.s` | P4B2 裁剪主程序(boot 跳转标记 + 1 次 x 装载 DMA + 1 次权重流 DMA + tile0 GEMV + st.q×16 UART 十六进制输出) |
| `p4b2_gen_scene.py` | P4B2 场景生成(汇编 + XMEM 稀疏镜像 `build/p4b2_scene.hex`) |
| `p4b2_sta_check.tcl` | P4B2 STA 独立复核(lib→odb→sdc→setRC→SPEF→重建时钟;10.551ns/10ns 双口径) |
| `gds_census.py` | KLayout -b 无 GUI GDS 普查(图层/单元/宏实例)+ PIL 截图 |
| `build/` | 编译/运行产物与日志(vvp、编译警告日志、UART 二进制流、equiv 尝试日志) |

## 门级仿真调用(实测可复现)

```bash
M=/home/zcz/.volare/volare/sky130/versions/c6d73a35f524070e85faff4a6a9eef49553ebc2b/sky130A/libs.ref/sky130_fd_sc_hd/verilog
RAM=$HOME/tools/openroad-flow-scripts/flow/platforms/sky130ram/sky130_sram_1rw1r_128x256_8
N=/home/zcz/verda/autoDecodeChip/pnr/amechip/results/sky130hd/amechip/p4a3fin/6_final.v

# boot 场景
iverilog -g2012 -DFUNCTIONAL -s tb_gate_boot -o build/gate_boot.vvp \
  $N $M/sky130_fd_sc_hd.v $M/primitives.v $RAM/sky130_sram_1rw1r_128x256_8.v tb_gate_boot.sv
cd build && vvp gate_boot.vvp +UART_BIN=uart_gate.bin

# P4B2 裁剪 decode 场景(先生成镜像)
python3 tb/gate/p4b2_gen_scene.py
iverilog -g2012 -DFUNCTIONAL -s tb_gate_decode -o build/p4b2_gate.vvp \
  $N $M/sky130_fd_sc_hd.v $M/primitives.v $RAM/sky130_sram_1rw1r_128x256_8.v tb_gate_decode.sv
cd build && vvp p4b2_gate.vvp +UART_BIN=uart_p4b2_gate.bin +XMEM_HEX=p4b2_scene.hex
```

要点(P4READY 预检结论的修正与补充):
- **调用顺序**:网表在前,后跟 `sky130_fd_sc_hd.v`、`primitives.v`,SRAM 宏 `.v` 随后,最后 TB;`-s` 指定 TB 顶层。
- **必须加 `-DFUNCTIONAL`**:不加时选中库文件的 timing 变体(notifier + `*_delayed`
  信号由 `$setuphold/$recrem/$width` 驱动),iverilog 不支持时序检查
  (620 条 "Timing checks are not supported" 警告),delayed 信号恒 X,
  仿真全 X 无输出(证据:`build/gate_compile_timing_variant.log` + 首次运行)。
  `-DFUNCTIONAL` 分支不含 specify → **本工具链上 SDF 反标不可行**(既无
  反标目标,timing 变体又功能失效),时序覆盖由 STA 签核承担。
- 网表无电源引脚(ORFS 惯例),`-DFUNCTIONAL` 变体端口表不含 VPWR/VGND,直接匹配。
- "Choosing typ expression" 为无害警告(零延迟口径)。
- 速度参考:33 万门网表,boot 场景 4458 周期 ≈ 84 s(iverilog 单线程)。
  全量 P3D e2e ≈ 1860 万周期 → iverilog 门级不可行;Verilator 不支持
  sky130 门级(单元模型 specify/UDP 语义)。
- **RTL 参照编译坑(P4B2-01)**:REAL 槽位必须用 `rtl/soc/amechip_{cpu,ame,mem}.sv`
  (其 BOOT_INIT = 冻结 hex 绝对路径常量);`tb/soc/verify_p3d_slots.sv` 的
  BOOT_INIT 是相对 make 工作目录的 `"p3d_boot.hex"`,直接用会导致 ROM 读失败全 X。
  文件清单可用 `strings <vvp> | grep '"rtl/'` 从首轮 vvp 提取核对。
- **TB 静默阈值**:loader 4KB 拷贝全程 ~5.6 万拍无 UART 输出,IDLE_CYC 必须
  ≥90000(boot TB 的 2000 会把拷贝中途当停机收尾,P4B2-02)。

## RTL 参照运行(同一 TB)

```bash
# 文件清单 = strings rtl_boot.vvp 提取(REAL 包装,见上 P4B2-01 条)
iverilog -g2012 -s tb_gate_decode -o build/p4b2_rtl.vvp <RTL 清单> tb/gate/tb_gate_decode.sv \
  -Irtl -Irtl/cpu -Irtl/ame -Irtl/mem -Irtl/soc -Irtl/interfaces \
  -DAMECHIP_REAL_CPU -DAMECHIP_REAL_AME -DAMECHIP_REAL_MEM -DAMECHIP_REAL_BOOTROM
cd build && vvp p4b2_rtl.vvp +UART_BIN=uart_p4b2_rtl.bin +XMEM_HEX=p4b2_scene.hex
```

## 实测结果

### P4B 首轮(2026-10-25,p4a2 网表)

- 门级与 RTL UART 流**逐字节一致**(md5 `65acb9ccf498524e2139e81a124201b5`,
  17 字节 "AME-CHIP BOOT OK\n"),且周期数同为 4458。
- X 扫描:复位释放后除 `xmem_a_o` 外全部顶层输出即刻已知;`xmem_a_o` 空闲期
  为 X(CE/OE 恒无效,首笔 XMEM 访问装载地址后消除),RTL 侧为 0(寄存器
  有复位语义被综合丢弃)——无复位 flop 风险实例,详见 P4B 报告 §3。
- **boot ROM 内容发现**:网表烤入的 ROM = 旧版 `boot.s`("AME-CHIP BOOT OK" +
  wfi 停机,无程序装载),与 P1BX-B e2e 基线用的 P3D loader("P3D BOOT OK" +
  4KB 拷贝跳转)不一致 → 门级全场景(GEMV/e2e)在当前网表上不可达,
  见 `reports/issues/P4B.md` P4B-01。

### P4B2(2026-10-27,p4a3fin 网表)

- boot 段横幅 = "P3D BOOT OK\n"(12 B),与 P1BX-C 基线逐字节一致 → **P4B-01 关闭**
  (ROM md5 三处一致 = `aae6ac28bbdaa6bc1f9348f3a8c8ba79`)。
- **裁剪 decode 场景:三份门级口径(原始 6_final.v / 拼接反转补偿
  `p4b2_6final_concatfix.v` / yosys `1_2_yosys.v`)全部在 loader 4KB 拷贝后
  崩溃(13 B 后全 X,150,048 拍),RTL 46 B / 156,948 拍全对** → 门级 SRAM 写数据
  通路缺陷(`wdata[15:0]`≡X)+ P&R 网表/ODB/GDS 宏拼接端口位序反转
  (ODB 直查实证,p4a2 同签名)→ **P4B2-05(BLOCKER),详见
  `reports/P4B2_REPORT.md` §4 与 `reports/issues/P4B2.md`**。
- STA 独立复核:`p4b2_sta_check.tcl` → 10.551ns WNS +0.000/TNS 0/hold +0.270;
  10ns 存档 −0.55/7 端点(全 p_u_q 族)复核一致。

## P4B3 补充(2026-10-27):写通路根因定位 + XINIT 门仿口径

P4B2-05b(门级写通路 `wdata[15:0]≡X`)根因定案:**memc 读/写队列槽(rq_addr/wq_addr,
RTL 无复位)的 X 经 yosys 重构的 xmem_a_o AND-OR 锥非选通项泄露到首半字地址位
(xmem_a_o[1] 在 S_R0 拍恒 X)→ TB 器件模型以 X 索引读 pmem → pdo_q=X → hw0_q=X →
r_data 低半 X**。force 实验(强制队列槽为已知值后引脚逐拍恢复正确)证明网表函数与
RTL 一致——纯 X-悲观仿真伪影,非功能缺陷。处置 = 门仿 `+XINIT`(上电初值注入,
模拟硅上电);RTL 加固建议(队列槽复位)上报 P1BX-D。

| 文件 | 说明 |
|---|---|
| `tb_p4b3_probe.sv` | memc 层次探针 TB(引脚+指针口径;`-DRTLREF` 切 RTL 层次名;+PROBE_MAX_CYC/+TRACE) |
| `p4b3_gen_probes.py` | 从网表验证并生成 `p4b3_gate_probes.vh`(345 层次引用)+ `p4b3_xinit.vh`(184 force) |
| `p4b3_rtl_probes.vh` | RTL 侧同名探针 |
| `tb_p4b3_yosys.sv` | 最小复现(yosys 纯网表口径,+WQ_FORCE 判别实验) |
| `p4b3_sram_model_probe.v` | 仪器化 SRAM 模型(功能与 ORFS 原版一致,写事务记账) |
| `tb_p4b3_gate.sv` | **门级签核用精简 TB** = tb_gate_decode + `+XINIT` 初值注入 |
| `p4b3_sta_check.tcl` | STA 独立复核(p4a4fix,10.551ns/10.150ns 双口径) |
| `p4b3_lvs_pinlevel.py` | 分层/引脚级 LVS 等效(宏黑盒:L2 GDS↔DEF 放置 + L3 逐引脚布线接触 + 网表死网期望口径) |

门级签核调用(46 字节判据):

```bash
iverilog -g2012 -DFUNCTIONAL -s tb_gate_decode -o build/p4b3_gatelean.vvp \
  $N $M/sky130_fd_sc_hd.v $M/primitives.v p4b3_sram_model_probe.v tb_p4b3_gate.sv
cd build && vvp p4b3_gatelean.vvp +UART_BIN=uart_p4b3_xinit.bin \
  +XMEM_HEX=p4b2_scene.hex +XINIT
cmp uart_p4b3_xinit.bin uart_p4b2_rtl.bin   # 须逐字节一致(46 B)
```
