# AME-Chip v0.1 Final Report (FINAL_REPORT)

> English translation of docs/FINAL_REPORT.md (Chinese original retained in repo history).

> Version: v0.1 tapeout candidate | Date: 2026-10-27 | Session: P5 wrap-up
> Status: **Sign-off checklist FAIL=0 (PASS 34 / NA 7), tapeout-ready**
> (`reports/TAPEOUT_CHECKLIST.md`, P4B3 final).
> Metrics appendix: `reports/FINAL_METRICS.md` (per-item traceability); bug ledger: `reports/FINAL_BUGS.md`.

---

## 1. Executive summary

AME-Chip is an RV32IM + AME INT8 matrix-coprocessor SoC (sky130hd, decode-dedicated, weights/KV resident off-chip and streamed over XMEM) targeting transformer autoregressive decode. Starting from workload profiling on 2026-10-23, the project passed through contract freeze (P1B), five parallel RTL tracks (P2A–P2E), three independent verification tracks (P3A–P3D) plus two RTL-freeze patch sessions (P1BXB v0.2 / P1BXC v0.3), formal backend implementation (P4A/P4A2/P4A3/P4A4), and three sign-off rounds (P4B/P4B2/P4B3), completing final delivery on 2026-10-27:

- **Deliverables**: GDS (158.0 MB) + CDL + SDF + netlist + SPEF/DEF/SDC; delivery variant `p4a4fix` (fingerprints: gds `d0ed37fc` / cdl `40217dd1` / sdf `d4318f81` / v `49d30b2f`).
- **Sign-off basis**: 94.78 MHz operating point (10.551 ns, WNS +0.40, all green) / fmax 98.52 MHz capability ceiling / die 4.524 mm² (instances 3.455 mm²) / power 241.8 mW (sign-off activity basis) / 15.3 tok s⁻¹, 15.76 mJ/token / TT single corner only.
- **Sign-off evidence: all five classes complete and independently recomputed**: geometry (KLayout DRC 0 outside macros, TritonRoute 0), connectivity (macro binding 1263/1263 + GDS↔DEF 1:1 + 885/885 valid pin contacts), timing (setup/hold/fmax independently recomputed on both bases), power (IR < 0.5 mV), function (**gate-level pruned decode: 46-byte md5 identical to RTL, 156,948 cycles cycle-for-cycle**).
- **Two tapeout-grade BLOCKERs eliminated along the way**: boot ROM content regression (P4B-01, cured at root by ROM freeze + md5 guardrail) and SRAM macro concatenation bit-order reversal (P4B2-05②, an OpenROAD read_verilog implicit bit-order-binding trap, cured at root by explicit per-bit connections + a static binding gate); the write-path X (P4B2-05①) was diagnosed as a gate-level X-pessimism artifact, with discriminating experiments proving no silicon functional impact; the XINIT basis was closed out in place.
- **Metric attainment**: functionality fully achieved; "max speed" (15.3 tok s⁻¹) and "low cost" (4.524 mm² vs the 3 mm² cap) each carry quantified, already-attributed gaps (§5); all root causes and residual work are captured in the v2 roadmap (§8).

## 2. Delivery baseline and freeze points

| Item | Value |
|---|---|
| RTL | v0.3 (P1BX-C freeze, 2026-10-26; read-only throughout) |
| boot ROM | P3D loader frozen image, md5 `aae6ac28bbdaa6bc1f9348f3a8c8ba79` (all three copies identical; `syn/amechip/scripts/check_boot_hex.sh` rollback guardrail) |
| Top-level contract | `rtl/interfaces/amechip_top_ports.sv`, XMEM_DW=16, 73 logic pins (≤80 pad budget) |
| SRAM macros | sky130_sram_1rw1r_128x256_8 ×3 (lib/lef/v/gds/sp, TT corner only; macro .v/LEF are the non-reversed sources — proven by the P4A4 four-point matrix) |
| Platform | ORFS sky130hd (OpenROAD acb9ccc / yosys 0.70+ / klayout 0.30) |
| Verification baseline | P3D e2e (tb/soc, Verilator, 18.6M cycles, 3 tokens bit-exact) + P3A 74/74 + P3C 46.9M assertions, 0 mismatches |
| Sign-off checklist | `reports/TAPEOUT_CHECKLIST.md` (P4B3 final): PASS 34 / FAIL 0 / NA 7 (⚠️ 3) |

## 3. Architecture (summary; full text in docs/ARCH_SPEC.md)

```text
                     ┌──────────────────────── amechip_top ───────────────────────┐
 clk_i/rst_ni ──────►│ CLK/RST synchronizer (rst_ni async in, 2FF sync release)   │
                     │   ┌──────────────┐  ame_coproc_if (EX bypass) ┌─────────┐  │
                     │   │ CPU RV32IM   │◄──────────────────────────►│  AME    │  │
                     │   │ 5-stage pipe │      resp (2/3 cycles)     │ INT8    │  │
                     │   └──┬────┬──────┘                            │ GEMV    │  │
                     │      │irq │ AXI4-Lite (M0)                    │ 16 lane │  │
                     │      ▼    ▼   ┌─AXI4-Lite xbar (RR per slave)─┘ WBUF/   │  │
                     │  ┌──────────────┤ 4 masters: CPU/DMA_RD/      │ XBUF    │  │
                     │  │ OC SRAM 4KB  │ DMA_WR/KV_CTRL; 9 slaves:   │ Y32/YQ  │  │
                     │  │ BOOT ROM 2KB │ OCSRAM/BOOTROM/SYS/INTC/    └────┬────┘  │
                     │  │ SYS CSR/INTC │ UART/DMA_CSR/AME/KV_CSR/MEMC     │       │
                     │  │ UART TX/RX   │  ┌─────────┐ ┌─────────┐    ┌────┬────┐  │
                     │  └──────────────┘  │ DMA 2D  │ │ KV_CTRL │    │ MEMC    │  │
                     │                    │ RD+WR   │ │APPEND/  │    │XMEM ctrl│  │
                     │                    └─────────┘ │READ/SICE│    └────┬────┘  │
                     └─────────────────┴────────────┴─────────────────────┼───────┘
                                            XMEM external bus: A[22:0] DQ_I/O[15:0]
                                            CE#/OE#/WE#/CLK/WAIT#
```

- **CPU**: RV32IM five-stage, control flow only; elementwise ops (LN/GELU/softmax/residual) execute on the scalar path (architecture ruling: with bandwidth as the binding constraint, SIMD is not worth the area — ARCH_SPEC §9.2).
- **AME**: 16-lane × K time-multiplexed INT8 GEMV array (16 MAC/cycle), WBUF/XBUF as separate 4KB SRAM macros; requant is purely fixed-point per-channel (y_q = clip((y_int32×M)>>S)); all tensor math goes into the AME.
- **Memory subsystem**: 4-master × 9-slave AXI4-Lite xbar; a 2D DMA engine streams weights/activations tile by tile; the KV controller's APPEND/READ/TRANSPOSE manages the 128 KiB off-chip KV cache; MEMC bridges the 16-bit XMEM; OC SRAM 4KB program + BOOT ROM 2KB.
- Backend: three 128x256_8 SRAM macros (OC RAM + WBUF + XBUF), single clock domain, 73 logic pins.

## 4. As-signed-off metrics table (every number traceable to FINAL_METRICS.md §1–§7)

| Metric | Value | Traceability (report §) |
|---|---|---|
| Sign-off frequency | **94.78 MHz (10.551 ns)**, WNS +0.40 / TNS 0 / 0 violations | P4B3 §5; P4A3 §0 |
| Capability ceiling fmax | 98.52 MHz (10.150 ns, zero margin, 1 endpoint) | P4B3 §5; P4A4 §6 |
| hold / skew | +0.30 all clear / 0.49 | P4B3 §5 |
| 100 MHz sprint | misses by only **7 endpoints at −0.55 ns** (single family y1_q[17]→p_u_q, archived P4A2/P4A3) | P4A3 §4; P4B2 §6.2 |
| die / instance area | **4.524 mm² / 3.455 mm²** (p4a3fin 3.449, util 77%) | P4A3 §5.1; P4A4 §6 |
| Power | **241.8 mW** (sign-off basis; p4a4fix re-measurement 251 mW, same magnitude) | P4A3 §5.1; P4A4 §6 |
| Per-step decode | **6,178,210 cycles/token** (65.19 ms) | P3D §4.1; P4A §3.4 |
| Energy / throughput | **15.76 mJ/token; 15.3 tok/s** (15.9 @fmax; 19.4 @120 extrapolated on the same basis) | P4A3 §5.1; P4A §3.4 |
| IR drop | VDD 0.334 / VSS 0.466 mV | P4A4 §6 |
| DRC | TritonRoute 0; KLayout 0 outside macros (inside macros waived per macro library) | P4A §4; P4B3 §6 |
| LVS (pin-level, three layers) | binding 1263/1263 + GDS↔DEF 1:1 + 885/885 valid pin contacts, 100% | P4B3 §4 |
| Gate-level equivalence | 46-byte md5 `9d4c5358…` = RTL / 156,948 cycles, cycle-for-cycle (+XINIT basis ⚠️) | P4B3 §3 |
| Checklist | PASS 34 / FAIL 0 / NA 7 | TAPEOUT_CHECKLIST |

## 5. Attainment analysis (vs docs/WORKLOAD.md roofline)

**Functionality: fully achieved.** RTL end-to-end 3/3 tokens, 25/25 GEMV bit-exact, KV 131,072 B byte-exact (P3D §3); gate-level netlist matches RTL byte-for-byte across 46 bytes / 156,948 cycles (P4B3 §3); ISA/golden/contract three-way machine checks all green (check_isa 15/15, etc.).

**"Max speed": roofline not reached; root cause identified — architecture ruling + implementation overhead, not bandwidth/compute saturation.**

| Basis | Cycles/token | tok/s@120 | Source |
|---|---|---|---|
| Roofline ideal (256 MAC/cycle + 1.9 MiB weights on-chip) | 7,680 | 15,625 | WORKLOAD §6 |
| Architecture-ruling basis (16 MAC/cycle + XMEM streaming) | bandwidth wall ≈1.0 M | ≈119 | ARCH_SPEC §9.1/§9.2 |
| **Measured** | **6,178,210** | **19.4** | P3D §4.1 |

- The roofline's 15,625 tok/s premise (weights resident on-chip) was **deliberately rejected** at contract time: 1.9 MiB of on-chip SRAM is ≥390 mm², two orders of magnitude over the 3 mm² cap (ARCH_SPEC §9.2) — the roofline is an architectural ceiling, not this chip's target.
- The applicable prediction is the ≈119 tok/s bandwidth wall: the measured value is **16%** of it, and the cycle count is **6.7×** the pure-dataflow lower bound (0.92 M, P3D §4.1). Root cause = CPU per-tile control overhead + DMA/KV waiting (DMA BUSY 32.5%, XMEM ACT 17%, AME duty only 4.1% vs 11% predicted) — these are **microkernel scheduling and control-path overheads**; the RTL/bus datapath itself is defect-free (46.9M protocol assertions, 0 mismatches), and v2 can recover most of the gap via microkernel optimization / a wider XMEM / pipeline overlap (§8④).
- The frequency shortfall compounds this: at 94.78 MHz, tok/s drops from 19.4 (120 MHz basis) to 15.3.

**"Low cost": 51% over the cap (die basis); all four attributions are verifiable (P4A §3.1, upheld across two review rounds).** ① Macro word-width strategy correction (WBUF/XBUF cannot use 64x256_8; all three macros use 128x256_8) +0.605 mm²; ② the 3 mm² figure is a core-basis cap, and the die reserved no pad-ring band (core 4.486 mm²); ③ timing repair re-consumed ≈0.20 mm²; ④ routing-channel bloat / unusable areas (util 77%). The macro-based direction itself was proven (P4A0: flop-based storage 4.658 mm² → macros 2.166 + std 1.283), but the "P4A0 prediction of core ≈2.57 mm², 3 mm² within reach" did not materialize — die basis + pad ring + repair re-consumption are the main gap.

## 6. Quality and residual risk

The full bug ledger is in `reports/FINAL_BUGS.md`: 24 issue reports, ~120 items; apart from those explicitly handed over to v2/P5/upstream, all are fixed/closed/waived. The four designated archived items (P4B-01, P4B2-05, P3B scr_kvrow, P4A-04/14) and the P1BX-D ruling (not adopted, moved to v2) are all on record.

**Top-3 residual risks (tapeout informed-consent items):**

1. **Single-corner (TT) sign-off**: both the std-cell and SRAM-macro libraries contain only TT_1p8V_25C; multi-corner (PVT corner) timing/power coverage is beyond current capability; in addition, 329 residual max_slew violations remain (worst −0.25, a converging family). Timing margins at the low/high-temperature silicon corners are unverified (P4READY §1, CHECKLIST §4 NA).
2. **Gate-level equivalence carries the +XINIT basis**: the only genuinely pathogenic surface (memc queue slots without a reset → gate-level X-pessimism) was proven harmless to silicon function by a discriminating experiment, but formal equivalence was not completed (284 miters stalled on macro black-box induction); netlist functional correctness rests primarily on "gate-sim byte-for-byte identity + static binding 1263/1263 + pin-level LVS"; the P1BX-D hardening was ruled out by decision (rerun cost ~2 days vs a benefit limited to a cleaner gate-sim basis), and this basis is carried long-term (FINAL_BUGS §2).
3. **LVS is pin-level three-layer equivalence, not full flatten**: full-flatten KLayout LVS did not converge after >4.5 h and remains unproven; macro-internal geometry-vs-electrical consistency relies on the macro-library deliverables, and top-level interconnect consistency is guaranteed by the L1/L2/L3 + single-ODB export chain (P4B3 §4, CHECKLIST §3 NA).

## 7. Reproduction guide (zero-to-GDS one-command path)

**One command**: `bash scripts/release_check.sh --quick` (~5 min: lint + guardrails + quick TB + delivery-fingerprint/report consistency checks) or `--full` (adds the full ORFS flow through GDS, ~4.5–5 h). Step by step:

| Step | Content | Command | Expected time | Basis |
|---|---|---|---|---|
| 0 | Environment precheck | built in (iverilog/verilator/yosys/openroad/klayout/orfs) | seconds | docs/ENV.md |
| 1 | boot ROM guardrail | `syn/amechip/scripts/check_boot_hex.sh` | seconds | P4A2 §1.2 |
| 2 | Contract/RTL lint | `lint_interfaces.sh`, `mem_lint.sh`, `check_isa.py`, `soc_check_ports.py` | ~10 s | P3D §1.3 |
| 3 | Quick TB (golden e2e) | `scripts/vfrd_run_all.sh` (Verilator, 3 tokens bit-exact + exception injection) | ~2 min | P3D §7 |
| 4 | ORFS synthesis | `make DESIGN_CONFIG=$ROOT/syn/amechip/config.mk …` (ABC_AREA=0) | ~10 min | P4A3 §6 |
| 5 | Floorplan/CTS + PDN gating | same make (after 3_5, `check_pdn_gate.sh` dual-green gate) | ~50 min | P4A §2; P4A-09 |
| 6 | Route/finish | `route_supervisor_p4a4fix.sh` supervision (resumable; the bit-order binding gate blocks on any FAIL) | ~2.5 h | P4A2/P4A3 supervision plan; P4A4 §3 |
| 7 | Binding static check | `p4a4_macro_binding_check.py` (golden reference vs 6_final.v/cdl) | ~1 min | P4A4 §4 |
| 8 | Sign-off STA, three bases | `run_p4a4fix_sta_chain.sh <fmax_period>` | ~10 min | P4A3 §4; P4B2 §6 |
| 9 | KLayout DRC + GDS export | platform lydrc + `drc_macro_filter.py` classification | ~35 min | P4A §4/§7 |
| 10 | Gate-level pruned regression | `p4a4fix_gate_decode_check.sh` (46 bytes == RTL, +XINIT) | ~1 h | P4B3 §3 |
| 11 | Report consistency | built in (checklist FAIL=0, delivery fingerprints, metric-table anchors) | seconds | this report |

> Field-verified parameters: P4A3 full flow 3.2 h (synth 10 min + fp/cts ~50 min + route ~2.5 h + finish ~7 min); long-running WSL jobs must run under a supervisor script (lesson learned after twice being killed by system reboots, P4A-15). DRC/LVS decks, macro platform, and gate-sim model library paths: see docs/ENV.md and P4READY §1/§3.

## 8. v2 roadmap (on the true ledger)

1. **Timing sprint to 100 MHz**: currently 94.78 MHz. Gap archive: p4a3fin recorded **7 endpoints at −0.55 ns** (P4A3 §4, re-verified in P4B2 §6.2); the sign-off delivery netlist p4a4fix re-measured the same family at only **−0.15 ns** (release_check S7 chain recomputation). It is a single `y1_q[17]→p_u_q` family (AME request queue load, a single-source 16-bit cone); P4A3 §4.2 already recommended adding a pipeline stage on this path (direct expected payoff, KPI cost <0.001%/token). If achieved: tok/s 16.2 (+6%); 120 MHz would need one more stage on the same family.
2. **Area convergence**: the target is back to the 3 mm² core basis — SRAM macro re-selection (smaller capacity / composed word width for WBUF/XBUF), timing buffer trimming (after v2's added stage, repair demand drops), and a floorplan rework reserving the pad-ring band. Ceiling ledger: macros 2.166 + std ~1.0 + pad ring — a 3 mm² die is theoretically reachable but requires a fresh routability iteration.
3. **Sign-off enhancement**: full-flatten LVS (rerun when budget allows; the >4.5 h lesson is on record), multi-corner sign-off (requires generating multi-corner libs), SDF back-simulation (requires an SDF-capable simulator), and **layered formal equivalence** (284 miters already built, stalled on SRAM macro black-box induction — blackbox abstraction at macro boundaries / adopt SymbiYosys, P4B §4).
4. **Performance and feature extensions**: prefill support (T=16 is a natural GEMM, arithmetic intensity 9.05 MAC/B), 32×32 array (parameters reserved, AME_M/N ∈ 8/16/32), microkernel scheduling optimization (eliminating DMA waits, tile overlap, SIMD elementwise) — AME duty 4.1% → predicted 11%+ is the largest remaining performance pool; ISA v2 (ld.x offset widening and the rest of the T1–T11 pending-ruling cluster).
5. **Flow lessons archived** (already hardened into assets; required reading before reuse):
   - **SRAM macro bit order**: the OpenROAD `read_verilog` concatenation × liberty member-order positional-pairing trap (`VerilogReader.cc makeNamedInstPins`) — any design containing multi-bit-port macros has them reversed wholesale under a liberty-first flow; the fix = explicit per-bit connections before import + a static binding gate (`p4a4_bitblast_macro_conns.py` + `p4a4_macro_binding_check.py`) as double guardrails.
   - **ABC_AREA recipe deviation** (P4A3-01): on this design, abc_area grew cell count +39% and regressed area; config.mk now hard-codes ABC_AREA=0 with forensic comments; the variant netlist (p4a3rtl03) is barred from use.
   - **make hex rollback guardrail** (P4B-01/P4B-06): ROM freeze + `check_boot_hex.sh` (on mismatch, restore first, then exit non-zero).
   - Also: PSM gating must be placed after 3_5 (P4A-09), supervisor scripts for long jobs (P4A-15), and "implementation constraints must be stricter than sign-off constraints" (P4A2 §3.1 p4a3 lesson).
6. **Optional hardening and closeout**: P1BX-D queue-slot reset / xmem_a_o output registering (eliminates the XINIT basis; requires a full-chain rerun, ~2 days); three injection-style gate-level regressions (XMEM wait injection / UART error frames / CPU exceptions — TB paths already prepared in P4B3, each needing a new scenario plus hours-scale simulation); layered formal equivalence (same as ③); upstream report of the OpenSTA concatenation-import defect (makeNamedInstPins positional pairing).

## 9. Reference index

- Checklist: `reports/TAPEOUT_CHECKLIST.md` (P4B3 final, FAIL=0)
- Metrics appendix: `reports/FINAL_METRICS.md`; bug ledger: `reports/FINAL_BUGS.md`
- Phase reports: P3A/P3B (+PERF)/P3C/P3D (W3), P4A0/P4A/P4A2/P4A3/P4A4 (W4), P4B/P4B2/P4B3 (sign-off), P4READY (pre-check)
- Issue reports: `reports/issues/` (24 reports); contracts: `docs/ARCH_SPEC.md`, `AME_ISA.md`, `GOLDEN_SPEC.md`, `CONTRACT_PATCH_LOG.md`; profiling: `docs/WORKLOAD.md`; environment: `docs/ENV.md`
- Delivery: `pnr/amechip/results/sky130hd/amechip/p4a4fix/` (fingerprints in FINAL_METRICS §6)
- Self-check script: `scripts/release_check.sh`
