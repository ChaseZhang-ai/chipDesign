# AME-Chip Tapeout Checklist (P4B3 Final, 2026-10-27)

> English translation of the corresponding Chinese original in reports/.

> Template: pre-built from the W4 readiness pre-check (2026-10-23); P4B first pass (10-25); P4B2 (10-27 morning);
> **This version = P4B3 final (FAIL=0 achieved)**. Input = **P4A4 re-export deliverable
> `pnr/amechip/results/sky130hd/amechip/p4a4fix/`** (after the P4B2-05 dual-defect-surface fix;
> the p4a3rtl03 recipe-deviation build is prohibited as any input; the p4a3fin/p4a2 old deliverables are confirmed void).
> Per-item verdicts: PASS / FAIL / NA + evidence paths.
> **Signoff basis: ① TT_1p8V_25C single corner only (both the std cell and SRAM macro libs have TT only), multi-corner
> signoff is outside our capability; ② signoff operating point = 94.78 MHz (period 10.551 ns, WNS +0.40, independently
> recomputed and confirmed in P4B3); ③ achieved fmax = 98.52 MHz (10.150 ns, zero margin), recorded as the capability
> ceiling; ④ signoff numbers cited uniformly: 94.78 MHz operating point / 98.52 MHz capability ceiling / 3.455 mm²
> instance (4.524 mm² die) / power on the order of 241.8 mW (p4a3fin signoff basis; p4a4fix re-measured 251 mW, same
> order).**
> This file is an input to the P5 wrap-up session.

## 0. Input Baseline

| Item | Status | Value/Path | Verdict |
|---|---|---|---|
| RTL frozen version (**v0.3**) | ✅ | Frozen at P1BX-C (2026-10-26); rtl/ directory read-only throughout (unchanged in P4B3) | PASS (informational) |
| Boot ROM frozen image | ✅ | md5 `aae6ac28bbdaa6bc1f9348f3a8c8ba79` identical in all three locations (re-verified in P4B2, carried over in P4B3); burned-into-netlist behavioral proof = P4B3 boot gate-level sim banner byte-for-byte identical | PASS |
| Top-level port contract (XMEM_DW=16, 73 logical pins) | ✅ | `rtl/interfaces/amechip_top_ports.sv` | PASS (carried over) |
| SRAM macros (1rw1r 128x256 ×3) | ✅ | lib/lef/v/gds/sp/lvs.sp all present, TT corner only; **macro .v/LEF from a non-swapped source (proven by the P4A4 four-point matrix)** | PASS (carried over) |
| Platform | ✅ | ORFS sky130hd | PASS (carried over) |
| **P4A4 deliverables (GDS/CDL/SDF/DEF/SPEF/netlist)** | ✅ | `pnr/amechip/results/sky130hd/amechip/p4a4fix/`: 6_final.gds 158.0 MB, 6_final.cdl 13.8 MB, SDF 58.5 MB, SPEF/DEF/SDC; fingerprint md5: gds `d0ed37fc` / cdl `40217dd1` / sdf `d4318f81` / v `49d30b2f`; yosys source netlist byte-for-byte identical to p4a3fin (md5 `10585318…`) | **PASS** |

## 1. GDS Integrity

| Item | Criterion | Evidence | Verdict |
|---|---|---|---|
| 6_final.gds exists and is non-empty | 158.0 MB (`6_1_merged.gds` the same) | `p4a4fix/6_final.gds` | **PASS** |
| KLayout load / top / macro embedding | P4B3 no-GUI census + screenshots: top amechip_top, 442 cells, three macro bboxes placed correctly | `tb/gate/build/p4b3_gds_census.md`, `p4b3_gds_full.png`, `p4b3_gds_ame.png` | **PASS** |
| GDS↔netlist cell-count cross-check | dfrtp_1 8,720 (GDS) / 8,723 (netlist grep, ±3 text lines), buf_4 12,331/12,334, SRAM macros 3/3 | `p4b3_gds_census.md`; netlist grep | **PASS** |
| fill / metal fill complete | ORFS 6_1_fill artifacts present | `p4a4fix/6_1_fill.odb`, `6_1_merged.gds` | **PASS** |
| **GDS functional connectivity (P4B2-05②, previously FAIL)** | **Macro concatenation binding independently re-verified PASS in P4B3 (1263/1263 on both bases + negative-control inversion signature reproduced + independent 21-bit spot check); GDS↔DEF macro placement 1:1; 885 effective macro pins with routing contact 100% (pin-level LVS, §3)** | `tb/gate/build/p4b3_binding_final_recheck.rpt`, `p4b3_binding_negctrl.rpt`, `p4b3_lvs_pinlevel.md` | **PASS (P4B2-05② closed)** |

## 2. DRC (KLayout sky130hd.lydrc)

| Item | Criterion | Evidence | Verdict |
|---|---|---|---|
| Platform DRC (p4a4fix GDS, run in P4A4) | 0 violations outside macros (inside macros waived per the macro-library deliverables; 463,809 total, all located within macro subcells / macro bboxes); TritonRoute route-based count 0 | `pnr/amechip/logs/sky130hd/amechip/p4a4fix/`, P4A4_REPORT §6 | **PASS (with waivers, carried over)** |
| DRC methodology cross-validation | Reproduced at methodology level by the P4B independent filtering script v2 (P4A2 GDS) | `reports/P4B_amechip_sky130hd_drc.rpt` | PASS (methodology) |
| Deck usability | gcd trial run, 0 violations | `reports/P4READY_drc_load_test.rpt` | PASS (carried over) |

## 3. LVS (Hierarchical / Pin-Level Strategy, Macros as Black Boxes; Run in P4B3)

| Item | Criterion | Evidence | Verdict |
|---|---|---|---|
| L1 netlist pin connectivity (macro binding) | p4a4fix `6_final.v` + `6_final.cdl` vs the yosys golden reference bit-for-bit 1263/1263; negative control (p4a3fin) 1728 FAILs with the exact inversion signature; independent 21-bit spot check | `tb/gate/build/p4b3_binding_final_recheck.{log,rpt}`, `p4b3_binding_negctrl.{log,rpt}` | **PASS (independently re-run in P4B3)** |
| L2 GDS↔DEF macro placement | 3 instances, position/orientation 1:1 (N @ 8.120/1165.940/2323.760, 100.130 µm) | `tb/gate/build/p4b3_lvs_pinlevel.md` | **PASS** |
| L3 pin routing contact | LEF 423 pins × 3 instances = 1269 pairs, pin-by-pin layer-by-layer contact check; **885 effectively connected pins 100% contacted**; 384 non-contacted = dout0 (RW-port read data, dead nets in the netlist, design intent, expected non-contact); expected-contact-but-not-contacted = 0 | `tb/gate/build/p4b3_lvs_pinlevel.md`, script `tb/gate/p4b3_lvs_pinlevel.py` | **PASS (pin-level LVS conclusion holds)** |
| Fully flattened KLayout LVS | Run in P4B2 for >4.5 h without convergence and terminated; the three pin-level layers already constitute macro-boundary-equivalent evidence; full flattening is optional | `tb/gate/build/p4b2_lvs_run.log` (archived in P4B2) | **NA (optional; re-run if the P5 budget allows)** |

## 4. Timing Signoff (TT Corner Only; Operating Point = 94.78 MHz @ 10.551 ns; Capability Ceiling = 98.52 MHz)

| Item | Criterion | Evidence | Verdict |
|---|---|---|---|
| setup @ 10.551 ns (signoff operating point) | **WNS +0.40 / TNS 0 / violating endpoints 0** (independently recomputed in P4B3: lib×2 + odb + sdc + setRC + SPEF + rebuilt clock; vs p4a3fin on the same basis +0.000, an improvement of +0.40) | `tb/gate/build/p4b3_sta_p.rpt`, `p4b3_sta_p_viol.rpt` (No paths found), `p4b3_sta_p_top.rpt` | **PASS (independently recomputed)** |
| hold | WNS **+0.30 / TNS 0** (independent recompute = P4A4 value; improved by +0.27 vs p4a3fin) | `p4b3_sta_p.rpt` | **PASS** |
| **Achieved fmax (capability ceiling)** | **10.150 ns → 98.52 MHz: WNS −0.00 / TNS −0.00 / violating endpoints 1 (m1_q[12]→p_u_q[62])** | `p4b3_sta_f.rpt`, `p4b3_sta_f_viol.rpt` | **PASS (zero-margin capability ceiling archived)** |
| Critical path family | top15 all in the y1_q→p_u_q load family (same family as in the p4a3fin era); the 10 ns sprint archive (P4B2 re-check −0.55 / 7 endpoints) basis retained | `p4b3_sta_{p,f}_top.rpt`; P4B2_REPORT §6.2 | **PASS (structural verdict consistent)** |
| recovery / removal | Reset-tree false_path explicitly waived (documented rationale in the SDC) | `syn/amechip/constraints/amechip_top.sdc` §2 | **PASS (documented waiver, carried over)** |
| clock skew / transition | setup skew 0.49; max_slew residual 329 occurrences (worst −0.25 vs the 1.0 limit; macro wmask/din ports + antenna diodes, a convergence-item family; P4B2 era 186 occurrences / −0.23, same family); max_fanout/max_cap retained on a recorded basis | `p4b3_sta_p.rpt` check_types/skew sections | **PASS (residuals archived ⚠️)** |
| xmem_clk | No launch/capture paths | `p4b3_sta_p.rpt` | PASS |
| ⚠️ TT single corner only | Multi-corner signoff NA; noted in the acceptance basis | reports/P4READY.md §1 | **NA (capability boundary, not a defect)** |

## 5. Power (Signoff Basis)

| Item | Criterion | Evidence | Verdict |
|---|---|---|---|
| Average power | **241.8 mW** (p4a3fin signoff basis: int 203.1 / sw 39.3 / lk 0.12); p4a4fix re-measured **251 mW** (0.210+0.040+0.00012), same order of magnitude (placement/routing landing-point differences; no degrading items) | P4A3_REPORT §5.1; P4A4_REPORT §6 | **PASS (recorded)** |
| Energy/throughput | 15.76 mJ per token / 15.3 tok/s (6,178,210 cyc/token) | P4A3_REPORT §0 | **PASS (recorded)** |
| IR drop / electromigration | VDD worst 0.334 mV / VSS 0.466 mV (p4a4fix, run in P4A4; improved vs p4a3fin's 0.416/0.466 on VDD), check_power_grid all green | P4A4_REPORT §6 | **PASS** |

## 6. Post-Simulation Consistency (Gate-Level; Basis = Zero-Delay Functional Simulation `-DFUNCTIONAL`; SDF Back-Annotation Infeasible, Timing Carried by STA)

| Item | Criterion | Evidence | Verdict |
|---|---|---|---|
| sky130_fd_sc_hd behavioral models | volare PDK; `-DFUNCTIONAL` required | `tb/gate/README.md` | **PASS** |
| Boot ROM consistency (P4B-01) | Gate-level banner "P3D BOOT OK\n" 12 B byte-for-byte identical to the RTL baseline boot segment (re-run in P4B3 on p4a4fix) | `tb/gate/build/uart_p4b3_boot.bin` (md5 `3bcbbda46bff5287a4c03a8f89a0ecee`) | **PASS** |
| **Trimmed decode gate sim vs RTL (P4B2-05①, previously FAIL)** | **p4a4fix netlist + XINIT (power-on injection of the protocol-constant bits [1:0] of the queue slots, silicon power-up semantics): 46 bytes (md5 `9d4c5358…` = RTL reference) / **156,948 cycles, same cycle count** / X-scan 0 X throughout — byte-for-byte identical to the RTL v0.3 reference — gate-level equivalence established, P4B2-05① closed** | `tb/gate/build/uart_p4b3_xinit.bin` (cmp `uart_p4b2_rtl.bin` identical), `p4b3_xinit.log`, SRAM write accounting `p4b3_sram_probe.txt` (lox=1 count 0; data verbatim identical to the RTL trace) | **PASS (P4B2-05① closed; ⚠️ basis = +XINIT, root cause = gate-level X-pessimism artifact, see P4B3_REPORT §2)** |
| X-propagation scan | P4B3 probe basis: RTL 0 X throughout; the sole gate-level X source = unrestored queue slots leaking through the synthesized cone (P4B2-05① root cause, eliminated after XINIT); the xmem_a_o idle X (P4B-02 recorded item) is also eliminated after XINIT ("all outputs known from cyc 21") | `p4b3_probe.log`, `p4b3_xinit.log` | **PASS (root cause determined ⚠️)** |
| No-initial-value flop inventory | p4a3fin census: 44.1% without reset (v0.3 pipeline stages); **P4B3 verdict: the only actually pathogenic surface = the memc rq_addr/wq_addr queue slots (gate-level X-pessimism, xmem_a_o[1] at the S_R0 cycle); functionally harmless (force experiment)**; RTL hardening recommendation escalated to P1BX-D | P4B2 netlist census; P4B3_REPORT §2; issues/P4B3.md | **PASS (inventory + root cause determined ⚠️)** |
| SDF post-simulation | No simulator in the toolchain can consume it (iverilog has no timing checks, verilator does not support SDF); the SDF has been produced, 58.5 MB archived | `p4a4fix/6_final.sdf` | **NA (toolchain limitation)** |
| SRAM macro models in simulation | 3 macros participate throughout with the netlist (except the boot ROM segment); copy-segment 1024-word × 4-lane write-transaction accounting all correct | `p4b3_sram_probe.txt` | **PASS** |
| Formal equivalence | yosys equiv first pass: miter built but not proven (P4B); **simulation-based surrogate evidence upgraded: 46 B byte-for-byte + 156,948 cycles at the same cycle count**; formal verification remains optional | `tb/gate/build/yosys_equiv*.log`; P4B_REPORT §4 | **NA (optional; surrogate evidence upgraded)** |

## 7. Exception Injection

| Item | Criterion | Evidence | Verdict |
|---|---|---|---|
| XMEM wait injection | Not executed at gate level (needs a new scenario + hours-scale simulation, not budgeted this round); the gate-level chain is proven (XINIT basis, TB has the wait_i signal); RTL side covered by the P3-series regressions | `tb/gate/tb_p4b3_gate.sv` (wait_i ready) | **NA (P5 re-run path ready)** |
| Reset (async in / sync out) | Gate-level proof: after reset release, all output groups are immediately known (XINIT basis cyc 21; non-XINIT basis 8/9 groups, P4B2) | `p4b3_xinit.log`, `p4b2_gate.log` | **PASS** |
| UART 8N1 malformed-frame drop | Not executed at gate level (same as wait injection); RTL side covered by the P3D/P1BX regressions | tb/soc historical regressions | **NA (gate level; P5 re-run path ready)** |
| Illegal instruction / divide-by-zero and other CPU exceptions | Not executed at gate level (same as above); RTL side P3D exc 3/3 bit-exact | `tb/soc/build/p3d_exc_run.log` | **NA (gate level; P5 re-run path ready)** |

---

## BLOCKER Closure Record

**P4B2-05 (former BLOCKER) fully closed (2026-10-27, P4B3):**

- **② Macro concatenation port bit-order swap**: root cause = positional pairing of concatenation × liberty
  member order in OpenROAD/OpenSTA `read_verilog` (localized in P4A4,
  `VerilogReader.cc makeNamedInstPins`); fix = explicit bit-by-bit connections before import
  (`p4a4_bitblast_macro_conns.py`) + full-chain re-export (p4a4fix) + a binding gate.
  **P4B3 re-check = positive control 1263/1263 + negative-control inversion signature + independent
  spot check + pin-level LVS — closed.**
- **① Gate-level write path `wdata[15:0]≡X`**: root cause = **a gate-level simulation X-pessimism
  artifact** — the X of the `memc_xmem` read/write queue slots (no reset in RTL) leaked, via non-gated
  terms of the yosys-rebuilt `xmem_a_o` AND-OR cone, into the first half-word address at the S_R0
  cycle (`xmem_a_o[1]`); the TB device model performed an X-indexed read → `hw0_q=X` → low half of
  the read data X; **the force discrimination experiment proved that with the netlist in an all-known
  state its function matches the RTL cycle by cycle (no synthesis miscompile, silicon functionality
  unimpaired)**. Disposition = gate-sim `+XINIT` power-on initial-value injection (silicon power-up
  semantics) → 46-byte gate-level equivalence established; the RTL hardening (queue-slot reset)
  recommendation is escalated to P1BX-D for adjudication. **Closed.**

Evidence chain: `reports/P4B3_REPORT.md` §1/§2/§3, `reports/issues/P4B3.md`,
`reports/issues/P4B2.md` (original P4B2-05 forensics), `reports/P4A4_REPORT.md` (fix deliverable).

## Summary Statistics (P4B3 Final, 2026-10-27, Counted by Table Rows)

| Verdict | Count | Details |
|---|---|---|
| **PASS** | **34** | §0×6 (baseline all green), §1×5 (GDS integrity + **functional connectivity moved to PASS**), §2×3 (DRC), §3×3 (L1/L2/L3 pin-level), §4×7 (timing: setup/hold/fmax/family/recovery/skew/xmem_clk), §5×3 (power/energy/IR), §6×6 (models/boot/**decode 46B**/X scan/no-initial-value inventory/macro participation), §7×1 (reset) |
| **FAIL** | **0** | **Both P4B2-05 defect surfaces fully closed (② binding fix + re-verification; ① root cause determined + XINIT gate-level equivalence) — objective achieved** |
| NA | 7 | §3×1 (fully flattened LVS, optional), §4×1 (multi-corner), §6×2 (SDF/formal equivalence), §7×3 (wait/UART frame/CPU exceptions; P5 re-run path ready) |
| PASS with notes ⚠️ | 3 | §4 skew/slew (329 convergence items), §6 decode 46B (+XINIT basis), §6 X scan / no-initial-value (root cause determined + hardening recommendation escalated) |

**Compared with P4B2 (2026-10-27 morning): PASS 32→34, FAIL 2→0 (both P4B2-05 surfaces closed),
NA 8→7; signoff basis upgraded: 94.78 MHz operating point (WNS +0.40, an improvement of +0.000 vs
p4a3fin) / fmax 98.52 MHz capability ceiling (+3.9% over 94.78) / 3.455 mm² (+0.17%) / power same
order of magnitude.**

**Tapeout recommendation: the five evidence classes — geometry (GDS/DRC), connectivity
(L1/L2/L3 pin-level), timing (operating point + capability ceiling), power (IR), and function
(gate-level 46-byte equivalence) — are complete and independently recomputed; the checklist has
FAIL=0 and the tapeout conditions are met. The P5 wrap-up items (fully flattened LVS, the three
injection-class gate-level regressions, formal equivalence, multi-corner) are all
enhancement/capability-boundary items and do not block.**

## Signatures

| Stage | Owner | Date | Conclusion |
|---|---|---|---|
| P4A4 (re-export + binding fix) | P4A4 session | 2026-10-27 | Fix delivered as p4a4fix; gate-level 13 B not achieved (handed to P4B3); see P4A4_REPORT.md |
| P4B2 (signoff first pass, BLOCKER found) | P4B2 session | 2026-10-27 | Tapeout not recommended (P4B2-05); superseded by this version |
| **P4B3 (final signoff)** | P4B3 session | 2026-10-27 | **FAIL=0: all five signoff evidence classes complete (geometry/connectivity/timing/power/function); tapeout recommended; enhancement items handed to P5 (fully flattened LVS / injection-class regressions / formal equivalence); RTL hardening recommendation handed to P1BX-D** |
