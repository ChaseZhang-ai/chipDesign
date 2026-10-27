# P4B3 Report — Final Signoff: P4B2-05 Fully Closed (Write-Path Root Cause Determined + Gate-Level Equivalence Established + Pin-Level LVS + STA Re-verification)

> English translation of the corresponding Chinese original in reports/.

> Session basis: input = **P4A4 re-export deliverable `pnr/amechip/results/sky130hd/amechip/p4a4fix/`**
> (after the bit-level macro-binding fix; p4a3rtl03 and p4a3fin prohibited as inputs). Baseline = RTL v0.3 frozen sources +
> the P4B2-archived RTL reference `tb/gate/build/uart_p4b2_rtl.bin` (46 B, md5
> `9d4c535813bbcbb14e6c4ce501c2f4b3`). Discipline: rtl/, pnr/, syn/ read-only; this session writes only
> tb/gate/, reports/P4B3_*.md, reports/TAPEOUT_CHECKLIST.md, reports/issues/P4B3.md.
> **Signoff basis: 94.78 MHz operating point (10.551 ns, WNS +0.40) / fmax 98.52 MHz (10.150 ns,
> zero margin) recorded as the capability ceiling / 3.455 mm² instance (4.524 mm² die) / power on the order of 241.8 mW
> (p4a3fin signoff basis; p4a4fix re-measured 251 mW, same order) / TT_1p8V_25C single corner only.**

## 0. TL;DR

| Item | P4B2 Legacy | **P4B3 Final** |
|---|---|---|
| P4B2-05② (macro concatenation bit-order swap) | BLOCKER, pending re-verification | **Re-verified, closed**: check script independently re-run, positive control **1263/1263 PASS** (dual basis: 6_final.v + 6_final.cdl), negative control (p4a3fin) **1728 FAILs with the exact inversion signature**, independent manual spot check of 21 bits with 20 direct hits (+1 case of constant-net naming difference, consistent with the script's constant-folding basis); golden-reference md5 identical on both sides |
| P4B2-05① (gate-level write path `wdata[15:0]≡X`) | Root cause unknown | **Root cause determined (§2): gate-level simulation X-pessimism artifact** — the X of the memc read/write queue slots (no reset in RTL) leaked, via non-gated terms of the yosys-rebuilt `xmem_a_o` AND-OR cone, into the first half-word address; the force experiment proved that with the netlist in an all-known state its function matches the RTL cycle by cycle, **not an RTL/synthesis functional defect**; fixed in place on the TB side with `+XINIT` (silicon power-up semantics) |
| Gate-level vs RTL equivalence (P4B2-05 blocker) | Not established | **Established**: boot 12 B byte-for-byte identical + trimmed decode **46 B / 156,948 cycles byte-for-byte identical to the RTL reference** (XINIT basis, §3) |
| LVS | NA (fully flattened >4.5 h without convergence) | **Hierarchical / pin-level three-layer equivalence PASS** (§4): L1 netlist 1263/1263 + L2 GDS↔DEF placement 1:1 + L3 885 effective pins routing contact 100% (dout0 ×384 dead nets expected); full flattening left to P5 as optional |
| STA | P4A4 self-reported | **Independently re-verified, consistent** (§5): 10.551 ns WNS +0.40 / TNS 0 / 0 violations / hold +0.30; fmax 10.150 ns WNS −0.00 single endpoint (same family y1_q→p_u_q); skew 0.49 |
| Checklist | PASS 32 / FAIL 2 (P4B2-05) | **PASS 39 / FAIL 0 / NA 8 (of which 3 gate-level injection-class items note a re-run path) — FAIL=0 achieved** (§checklist) |

## 1. Task 3: Static Bit-Order Re-verification (P4B2-05② Closed)

Method = running the P4A4 check script `syn/amechip/scripts/p4a4_macro_binding_check.py` (independent session,
independent process) + an independent manual spot check (self-built parsing/back-trace, a different code path
from the script).

| Experiment | Material | Result |
|---|---|---|
| Positive control (final deliverable) | p4a4fix `1_2_yosys_yosys_pristine.v` vs `6_final.v` + `6_final.cdl` (with the liberty pass-through table, 63 cells) | **PASS 1263/1263 bits, 100% on both bases** (`tb/gate/build/p4b3_binding_final_recheck.{log,rpt}`) |
| Negative control (pre-fix deliverable) | p4a3fin `1_2_yosys.v` (md5 = p4a4fix pristine ✓) vs its `6_final.v` + `6_final.cdl` | **1728 FAILs, exact inversion signature**: `din0[0]→wdata[31]`, `din0[127]→wdata[0]`, `addr0[5]→addr[6]` (should be addr[9]), `wmask0[15]→wmask[0]` (`tb/gate/build/p4b3_binding_negctrl.{log,rpt}`) |
| Independent manual spot check | 3 macros × 21 key bits of din0/addr0/wmask0/dout (including the historically swapped bits din0[0]/[127], addr0[5], wmask0[15], dout1[127]) | **20 bits direct hits** (6_final.v back-trace = golden reference); 1 bit (wbuf addr0[7]) back-trace stops at constant net `net2`, a different name for the same constant as the golden yosys constant net `_086705_` (covered by the script's constant-folding basis; the positive control already included this bit) |
| Dynamic corroboration | Gate-sim SRAM write probe: din0 high half = original high half of the program words (e.g. `0x0001`, `0x1000`, not the bit-swapped `0x8000`) | Binding polarity confirmed at functional level |

**Conclusion: the P4A4 fix is genuinely effective; the p4a4fix deliverable has no bit swap; P4B2-05② closed.**

## 2. Task 1: Write-Path Root-Cause Localization (P4B2-05① Determined)

### 2.1 Symptom Reproduction and X-Propagation Chain (Probe by Level, p4a4fix Netlist)

Probe TB `tb/gate/tb_p4b3_probe.sv` (345 memc internal hierarchical reference points, yosys flat escaped names;
RTL comparison basis `-DRTLREF`). 63,000-cycle window (covering the loader 4 KB copy segment):

| Observation point | Gate level (p4a4fix) | RTL comparison |
|---|---|---|
| `xmem_a_o` at the S_R0 cycle (first half-word address drive) | **bit1 = X, 1024/1024 occurrences** (`a_x=1024`); S_R1 cycle (+2 address) clean | Always clean (`a_x=0`) |
| Queue head register `rq_addr[rq_rp]` | **Always clean** (`rqh_x=0`) — the X is not at the register source | Clean |
| Device model read index `pmem[a[22:1]]` | **X index 1024/1024** (`idx_x=1024`); still X when hitting the already-loaded region (`pmem_x=0`, i.e. the X comes from the index, not the data) | 0 |
| `di` (=pdo_q) at the S_R1 cycle | **X 1024/1024** | 0 |
| `hw0_q` (latched on the R1→RV edge = low half of word) | **X** (`hw0_x=2042`) | 0 |
| OC-RAM write din0 (replicated ×4) | `{correct high half, X}` (e.g. `0x0001xxxx`, `0x1000xxxx`) | All correct |
| UART | 13 B (banner + garbage bytes) crash | 46 B all correct |

**Propagation chain: xmem_a_o[1] = X at the S_R0 cycle → the TB device model reads pmem with an X index →
pdo_q=X → on the R1→RV edge `hw0_q <= xmem_di_i` latches X → `r_data_o={xmem_di_i, hw0_q}` low half X →
CPU load low half X → sw stores into OC-RAM → program-word low half corrupted → garbage instruction fetch
after the jump → 13-byte crash.**

### 2.2 X Injection Gate (Netlist Cone Localization)

`xmem_a_o` is in RTL an `always_comb` case-output mux (fully assigned in every state). After yosys synthesis
it is rebuilt into an AND-OR cone (`a221o` cells, 3-product-term OR): **at the S_R0 cycle the read pre-drive
term (`mux4` selecting `rq_addr[rp+1]`, the next slot before the P3D-07 bypass) and the write-head term
(`wq_addr` mux) are not fully gated by the state** (the enable `net33615` measured =1 at the R0 cycle) —
the X of the unwritten slot enters the OR via `X & 1 = X`, and `X | correct value = X` overwhelms the correct
term. The affected bit = bit1 (a per-bit optimization difference; the other bits / other terms have different
gating structures and are therefore clean).

The yosys pure netlist (`1_2_yosys_yosys_pristine.v`, md5 identical to the p4a3fin source) **reproduces the
same signature** (`tb_p4b3_yosys.sv`: pin1=X at the R0 cycle; still X after all rq slots have been cleanly
written, consistent with the ever-X unwritten slots of `wq_addr`) — the defect already exists in the synthesis
output and is unrelated to the OpenROAD import (and once again independent of the binding issue).

### 2.3 Discriminating Experiment: Does Synthesis Miscompile? (Key)

`+WQ_FORCE=1`: at t=1700 cycles force `wq_addr[*][1]=1` (an **incorrect but known** value). Thereafter all
S_R0-cycle pins = **correct values** (bit1=0 for 0x014/0x018/0x01c/0x020), S_R1 = a2 correct, and `hw0_q`
recovers correct data — **with the netlist in an all-known register state, its function matches the RTL cycle
by cycle; synthesis does not miscompile; the X is purely simulation pessimism of an unrestored state**. At
silicon power-up the flops necessarily have definite values, so **silicon functionality is unaffected**; the
affected surface = gate-level simulation signoff (in read-only scenarios an unrestored state never clears
its X).

### 2.4 Minimal Reproduction

`tb/gate/tb_p4b3_yosys.sv` (yosys pure-netlist basis, ~2 minutes):

```bash
iverilog -g2012 -DFUNCTIONAL -s tb_p4b3_yosys -o p4b3_yosys.vvp \
  p4a4fix/1_2_yosys_yosys_pristine.v sky130_fd_sc_hd.v primitives.v \
  sky130_sram_1rw1r_128x256_8.v tb_p4b3_yosys.sv
vvp p4b3_yosys.vvp +XMEM_HEX=p4b2_scene.hex          # R0-cycle pin1=X reproduction
vvp p4b3_yosys.vvp +XMEM_HEX=p4b2_scene.hex +WQ_FORCE=1  # X disappears once forced known (discrimination)
```

### 2.5 Disposition (Two-Track)

1. **TB-side in-place fix (this session, permitted by discipline)**: `tb/gate/tb_p4b3_gate.sv` adds
   `+XINIT` on top of the standard `tb_gate_decode.sv` (for the 8 queue slots, force only **bit[1:0]** —
   always 0 by the 4B-aligned protocol, which happens to cover the sole leaking bit bit1; address bits
   [22:2] keep the real register values and the push function is unaffected; the list is generated by
   `p4b3_gen_probes.py` into `p4b3_xinit.vh`).
   Lesson recorded (issues/P4B3.md P4B3-03): the first version forced all slots, pinning the read address
   to 0 (the copy degenerated to all word0, 12-byte hang), since corrected. Early 2500-cycle verification:
   the gate-level trace matches the RTL comparison cycle by cycle, X counts all zero.
2. **RTL hardening recommendation escalated to P1BX-D (owner adjudicates; this session does not change
   RTL)**: resetting the `rq_addr`/`wq_addr` slots of `memc_xmem` (or registering the `xmem_a_o` output)
   would eliminate this class of X-pessimism exposure; if adopted, synthesis → P&R → full-chain re-signoff
   must be re-run; if not adopted, the gate-level signoff permanently carries the `+XINIT` basis
   (already closed loop).

## 3. Task 2: Gate-Level Functional Regression (p4a4fix Netlist)

| Scenario | Criterion | Result |
|---|---|---|
| boot (banner) | 12 B = "P3D BOOT OK\n", byte-for-byte identical to the RTL baseline boot segment | **PASS** (`uart_p4b3_boot.bin` = 12 B, cmp identical, md5 `3bcbbda46bff5287a4c03a8f89a0ecee`) |
| Trimmed decode (full chain) | 46 B / 156,948 cycles == RTL v0.3 output | **PASS**: `uart_p4b3_xinit2.bin` md5 `9d4c535813bbcbb14e6c4ce501c2f4b3` = RTL reference `uart_p4b2_rtl.bin` **md5 exactly identical** (46 B: `P3D BOOT OK\nD` + 32 hex + `\n`); **total 156,948 cycles = same cycle count as RTL** (protocol timing identical cycle by cycle); X-scan: `first_x=-1 / all_known=21 / x_after_known=0` (9 top-level output groups 0 X throughout); SRAM write accounting 1031 lines all clean (`lox=1` count 0, ocram 256 rows × 4 lanes all written, data including the mirror zero-fill) |

Gate-sim materials: `tb/gate/build/` (compile logs / vvp / UART bins / SRAM write accounting; the original
P4A4 13-byte evidence is in `pnr/amechip/logs/sky130hd/amechip/p4a4fix_gatesim/`). **The P4B2-05 regression
criterion ("trimmed scenario 46 B == RTL means pass") is met → the full P4B2-05 case (①+②) is closed.**

### 3.1 XINIT-Basis X-Scan (All Scenarios, `tb/gate/build/p4b3_xinit2.log`)

From reset release, **all 9 top-level output groups are known from cyc 21 onward with 0 X throughout**
(`x_after_known=0`) — the xmem_a_o idle X of the non-XINIT basis (P4B-02 recorded item) is eliminated as
well (its source = the X of the same unrestored queue slot leaking through the pin cone). For comparison:
the original P4A4 basis crashed at 13 bytes with an X-scan of ~90k cycles of X
(`pnr/amechip/logs/sky130hd/amechip/p4a4fix_gatesim/p4a4fix_gate.log`).

## 4. Task 4: LVS (Hierarchical / Pin-Level Strategy, Macros as Black Boxes)

Method (responding to the point that "macro pin mapping is exactly the sensitive spot for the bit-order
problem", and to the lesson of full flattening failing to converge in >4.5 h):
`tb/gate/p4b3_lvs_pinlevel.py` (KLayout -b), three layers of evidence:

| Layer | Content | Result |
|---|---|---|
| L1 netlist pin connectivity | 6_final.v ↔ 6_final.cdl, macro by macro, bit by bit (cdl basis of the binding check) | **PASS 1263/1263** (§1) |
| L2 physical placement consistency | 6_final.def 3 macro instances (position/orientation) ↔ 6_final.gds top-level instances 1:1 | **PASS** (`(8.120,100.130)/(1165.940,100.130)/(2323.760,100.130) µm, all N`) |
| L3 pin routing contact | LEF 423 pins × 3 instances = 1269 pairs; per-pin layer geometry → absolute coordinates; top-level routing (same-layer raw shapes + VIA-cell contact patches) contact check; **netlist expectation basis**: a pin net appearing ≥3 times escaped (declaration + macro + consumer) = should be contacted, <3 = dead net, expected not contacted | **PASS: 885 effectively connected pins 100% contacted; the 384 non-contacted are all dout0 (the 3 macros' RW-port read data, dead nets in the netlist, design intent)**; expected-contact-but-not-contacted = **0** |

Scope statement: L3 proves "every effective macro pin has physical routing contact"; net-name consistency
is guaranteed by L1 and the single-database ODB→DEF/GDS export chain. **The fully flattened KLayout LVS =
optional, left to P5** (budget and convergence to be determined; the >4.5 h lesson is on record).
Evidence: `tb/gate/build/p4b3_lvs_pinlevel.md`, script `tb/gate/p4b3_lvs_pinlevel.py`.

## 5. Task 5: Independent STA Re-verification (p4a4fix; Method = Same as p4b2_sta_check.tcl)

`tb/gate/p4b3_sta_check.tcl` (lib TT×2 → read_db 6_final.odb → read_sdc →
setRC → propagated clock → read_spef → rebuilt clock; recomputed in an independent session):

| Item | P4A4 Claimed | **P4B3 Independent Recompute** | Verdict |
|---|---|---|---|
| 10.551 ns (94.78 MHz signoff operating point) setup | WNS +0.40 / TNS 0 | **+0.40 / 0.00, violating endpoints 0** (`report_checks -slack_max` = No paths found) | ✓ |
| 10.551 ns hold | +0.30 / TNS 0 | **+0.30 / 0.00** | ✓ |
| 10.150 ns (fmax capability ceiling) | WNS −0.00 / TNS −0.00 | **−0.00 / −0.00**, violating endpoints 1 (m1_q[12]→p_u_q[62]) | ✓ (1/10.150 = **98.52 MHz**) |
| Critical family | y1_q→p_u_q family | top15 all the same family (family structure consistent with the p4a3fin era) | ✓ |
| skew | ~0.50 | **0.49** (setup) | ✓ |
| max_slew residual | — (P4B2 era 186 occurrences / worst −0.23) | **329 occurrences / worst −0.25** (same-family convergence items: macro wmask/din ports + antenna diodes; recorded basis) | Recorded |
| xmem_clk | no launch/capture | same | ✓ |

**Conclusion: both the 94.78 MHz (10.551 ns, +0.40) signoff operating point and the fmax 98.52 MHz
(10.150 ns, zero margin) capability ceiling are independently recomputed and confirmed.**
Evidence: `tb/gate/build/p4b3_sta_{p,f}*.rpt`, `p4b3_sta_run.log`.

## 6. GDS Integrity Supplementary Check (P4B3)

- `6_final.gds` 158.0 MB (`6_1_merged.gds` the same); top amechip_top, 442 cell definitions;
  KLayout no-GUI load + screenshots (`tb/gate/build/p4b3_gds_census.md`,
  `p4b3_gds_full.png`, `p4b3_gds_ame.png`; the three macro bboxes are placed correctly).
- GDS↔netlist cell-count cross-check: dfrtp_1 8,720 (GDS top-level recursive) / 8,723 (netlist grep,
  including a 3-line declaration/net textual difference), buf_4 12,331/12,334, SRAM macros 3/3 — same
  methodology as P4B2.
- KLayout DRC (run in P4A4): 0 violations outside macros; TritonRoute 0 — carried over.

## 7. Residual Items and Handover to P5

1. **RTL hardening (optional)**: reset the `memc_xmem` queue slots / register the `xmem_a_o` output →
   P1BX-D adjudicates (if adopted, the XINIT basis is no longer needed, at the cost of re-running
   synthesis → P&R → full-chain re-signoff).
2. **Fully flattened KLayout LVS**: optional; re-run when the budget allows (the three pin-level layers
   already PASS).
3. **Three full gate-level regression items** (XMEM wait injection / UART malformed frames / CPU
   exceptions): the gate-level chain is proven (XINIT basis, TB has wait_i); each needs a new scenario +
   hours-scale simulation, not scheduled this round, stays NA; re-run paths are written into the checklist.
4. The upstream defect report (OpenSTA read_verilog concatenation × member order) is recommended for
   submission to OpenROAD.
5. SDF post-simulation: remains NA due to the toolchain limitation (timing coverage is carried by STA
   signoff).
6. Formal equivalence (yosys equiv): simulation consistency evidence has been upgraded to 46 B
   byte-for-byte + 156,948 cycles at the same cycle count; formal verification remains optional.

## Appendix: Evidence File Index

- Root cause: `tb/gate/build/p4b3_probe.log` (63k-cycle X counts), `p4b3_gate_trace.txt`,
  `p4b3_rtl.log`/`p4b3_rtl_trace.txt` (RTL comparison), `cone2/p4b3_cone_trace.txt` (bit1 cone),
  `cone2/p4b3_yosys_trace.txt` (yosys reproduction + force discrimination), `cone2/yosys_run4.log`
- Gate-level regression: `p4b3_boot.log`/`uart_p4b3_boot.bin`, `p4b3_xinit.log`/`uart_p4b3_xinit.bin`,
  `p4b3_sram_probe.txt` (write-transaction accounting), compile logs `p4b3_*_compile.log`
- Binding: `p4b3_binding_final_recheck.{log,rpt}`, `p4b3_binding_negctrl.{log,rpt}`
- STA: `p4b3_sta_{p,f}{,_top,_hold,_viol}.rpt`, `p4b3_sta_run.log`
- LVS: `p4b3_lvs_pinlevel.md` (+ script `tb/gate/p4b3_lvs_pinlevel.py`)
- GDS: `p4b3_gds_census.md`, `p4b3_gds_full.png`, `p4b3_gds_ame.png`
- Deliverable fingerprints (p4a4fix): `6_final.gds` d0ed37fc / `6_final.cdl` 40217dd1 /
  `6_final.sdf` d4318f81 / `6_final.v` 49d30b2f (P4A4_REPORT §5; deliverables unchanged this round)
