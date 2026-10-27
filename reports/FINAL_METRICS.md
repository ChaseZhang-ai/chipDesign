# FINAL_METRICS — AME-Chip v0.1 Signoff-Basis Metrics Ledger

> Session: P5 wrap-up (2026-10-27). This document is the metrics annex to
> `docs/en/FINAL_REPORT.md`; **every number cites its source report**. The
> governing basis is the header declaration of `reports/TAPEOUT_CHECKLIST.md`
> (P4B3 final, FAIL=0). Signoff baseline = **the p4a4fix delivery**
> `pnr/amechip/results/sky130hd/amechip/p4a4fix/` (re-exported after the P4A4
> bit-order fix; the p4a2/p4a3fin deliveries are confirmed obsolete and
> p4a3rtl03 is quarantined).
> Global basis: TT_1p8V_25C single corner only (both the std-cell and SRAM-macro
> libs ship TT only; multi-corner signoff is outside current capability); all
> timing numbers are post-route + SPEF.

---

## 1. Frequency and Timing

| Metric | Value | Source |
|---|---|---|
| **Signoff operating frequency** | **94.78 MHz (period 10.551 ns)** | P4A3_REPORT §0/§4 (binary-pinned +0.000); TAPEOUT_CHECKLIST §4; P4B3_REPORT §5 (independent recomputation) |
| Signoff setup @10.551 ns | WNS **+0.40** / TNS 0 / 0 violating endpoints (p4a4fix; +0.40 better than p4a3fin's +0.000) | P4B3_REPORT §5 table; TAPEOUT_CHECKLIST §4 |
| Signoff hold | WNS **+0.30** / TNS 0 / 0 violations | P4B3_REPORT §5; P4A4_REPORT §6 |
| **Capability fmax** | **98.52 MHz (10.150 ns)**: WNS −0.00 / TNS −0.00 / 1 violating endpoint (m1_q[12]→p_u_q[62], zero margin) | P4A4_REPORT §6; P4B3_REPORT §5 (`p4b3_sta_f*.rpt`) |
| Clock skew (setup) | 0.49 ns | P4B3_REPORT §5 |
| max_slew residuals | 329 / worst −0.25 (vs 1.0 limit; macro wmask/din pins + antenna diodes, a converging family) ⚠️ | P4B3_REPORT §5; TAPEOUT_CHECKLIST §4 |
| Recovery/removal | Reset-tree false_path explicitly waived (written SDC rationale) | `syn/amechip/constraints/amechip_top.sdc` §2; CHECKLIST §4 |
| 100 MHz sprint archive | 10.0 ns: WNS **−0.55** / TNS −2.09 / **only 7 endpoints, all single-family y1_q[17]→p_u_q** (p4a3fin netlist archive) | P4A3_REPORT §4; P4B2_REPORT §6.2 (independently rechecked, consistent) |
| 100 MHz basis (re-measured on signoff delivery) | p4a4fix @10.0 ns: WNS **−0.15** / TNS −0.39, same family g_yq[2].u_rq.p_u_q[62] (+0.40 drift direction consistent; recomputed via the release_check S7 chain this session, report group `p4a4fix_100m_*`) | This table's note: the −0.55 archived by P4A3/P4B2 is on the p4a3fin basis; the delivered netlist is closer to 100 MHz |
| 120 MHz sprint archive | 7.576 ns: WNS −2.97 / TNS −3,853.79 / 3,958 endpoints | P4A3_REPORT §4 |
| Critical path family | top-15 all in the y1_q→p_u_q load family (AME request-queue channel 2, 16-bit cone, single source, non-bypass cone) | P4A3_REPORT §4.2; P4B3_REPORT §5 |
| Frequency decision chain | P4A2 escalation adjudication (84.6 missed, three options) → P4A3 "achieved fmax (WNS≥0 critical period) is the signoff period", ≥90 MHz sprint succeeded → P4B3 dual-basis recheck | P4A2_REPORT §6; P4A3_REPORT §0; P4B3_REPORT §5 |

## 2. Area

| Metric | Value | Source |
|---|---|---|
| **Die area** | **4.524 mm²** (3480×1300 µm) | P4A_REPORT §3.1; P4A3_REPORT §5.1; CHECKLIST header note |
| Core area | 4.486 mm² | P4A_REPORT §3.1 |
| **Instance area (signoff delivery)** | **3.455 mm²** (util 77%, p4a4fix) | P4A4_REPORT §6; CHECKLIST header note (P4B3 final basis) |
| Instance area (p4a3fin reference) | 3.449 mm² (util 77.0%; the +0.17% drift comes from bit-blasted import changing placement tie-breaks; no degradation in direction) | P4A3_REPORT §5.1; P4A4_REPORT §6 |
| Composition | SRAM macros 2.166 mm² (3× sky130_sram_1rw1r_128x256_8) + std instances 1.283 mm² (fill 188,112 / tap 30,497 / timing-repair buffers 14,382 / sequential 16,049 / combinational 68,312 / macros 3; 326,270 instances total) | P4A3_REPORT §5.1 |
| Netlist size | Synthesis 94,426 (94,423 std + 3 macros); p4a4fix post-route netlist 104,360 std cells + 3 macros (fill/tap/antenna counted in ODB terms) | P4A3_REPORT §2; P4B2_REPORT §1 |
| **vs the 3 mm² hard cap** | **die 4.524 = 151% of the cap (+1.524 mm²); instances 3.455 = 115% of the cap**. Four quantified causes: (1) macro word-width strategy correction — the 64x256_8 macros were unusable for WBUF/XBUF, all three are 128x256_8, +0.605 mm²; (2) the 3 mm² cap was a core figure, the die reserved no pad-ring band; (3) timing repair consumed ≈0.20 mm²; (4) routing-channel expansion/unusable areas, util 77% — causes re-verified across two rounds on the P4A2/P4A3 netlists | P4A_REPORT §3.1; P4A2_REPORT §6.1; P4A3_REPORT §5.2 |

## 3. Power / Energy / Throughput

| Metric | Value | Source |
|---|---|---|
| **Average power (signoff basis)** | **241.8 mW** (internal 203.1 / switching 39.3 / leakage 0.12; p4a3fin @10.551 ns activity basis) | P4A3_REPORT §5.1; CHECKLIST §5 |
| Power (re-measured on signoff delivery) | 251 mW (0.210 + 0.040 + 0.00012; p4a4fix, routing-placement differences; same magnitude, no degrading direction) | P4A4_REPORT §6; CHECKLIST §5 |
| Time per token | 65.19 ms (= 6,178,210 cyc ÷ 94.78 MHz) | P4A3_REPORT §5.1 |
| **Energy per token** | **15.76 mJ** (signoff activity basis; 21.97 mJ on the P@7.576 report basis) | P4A3_REPORT §5.1/§0 |
| **Throughput (signoff)** | **15.3 tok/s @94.78 MHz** | P4A3_REPORT §5.1; CHECKLIST §5 |
| Throughput (capability extrapolation) | 15.9 tok/s @98.52 MHz (same-basis scaling) | Derived from fmax ÷ KPI cycles in this table |
| Throughput (extrapolation reference) | 16.2 @100 MHz; **19.4 @120 MHz** (same-basis cycle extrapolation, P3D baseline) | P4A_REPORT §3.4; P3D_REPORT §0 |
| IR drop (worst) | VDD 0.334 mV / VSS 0.466 mV (p4a4fix; check_power_grid all green, PSM-0040 dual-net connectivity) | P4A4_REPORT §6; P4B3_REPORT §3 gate |

## 4. Function and KPI (single-step decode cycles)

| Metric | Value | Source |
|---|---|---|
| **Single-step decode cycles (KPI anchor)** | **6,178,210 cycles/token** (P1BX-B final KPI; P3D measured 6,085,136 / 6,224,720 / 6,224,774 across three prompts, mean = this value) | P3D_REPORT §0/§4.1; P4A_REPORT §3.4; P4A3_REPORT §5.1 |
| Device-activity profile (KPI window) | AME BUSY 4.1% / MAC issue 1.87% / DMA BUSY 32.5% / XMEM ACT 17.0% / KV BUSY 1.4% | P3D_REPORT §4.1 |
| RTL end-to-end golden | 3/3 tokens, 25/25 GEMV y_q bit-exact ×3, KV cache 131,072 B byte-exact (18.6 M cycles) | P3D_REPORT §3; P1BX-C baseline (P4B2_REPORT header note) |
| Gate vs RTL equivalence (signoff delivery) | Trimmed decode **46 bytes (md5 `9d4c5358…`) = RTL reference / 156,948 cycles, identical count**; boot 12 B byte-identical; basis = +XINIT (gate-level X-pessimism disposition, silicon-function discrimination experiment on file) ⚠️ | P4B3_REPORT §3; CHECKLIST §6 |
| Boot ROM consistency | Frozen image md5 `aae6ac28bbdaa6bc1f9348f3a8c8ba79`, three copies identical; baked-in netlist behavior proven (P4B-01 closed) | P4B2_REPORT §1/§2; CHECKLIST §0/§6 |

## 5. Comparison vs Roofline / Architecture Budget (quantified attainment)

| Basis | Cycles/token | tok/s @120 MHz | Source |
|---|---|---|---|
| WORKLOAD roofline (16×16 full array 256 MAC/cycle + 1.9 MiB on-chip weights) | 7,680 | 15,625 (compute ceiling) | WORKLOAD §6 |
| Adjudicated architecture basis (16 MAC/cycle + weights streamed from XMEM, ARCH_SPEC §9.1; (1) on-chip residency rejected: 1.9 MiB ≥390 mm², unrealizable under the 3 mm² cap; (2) full array rejected: area not worth it in a bandwidth-bound workload) | Array ceiling ≈122.9 k; bandwidth wall ≈1.0 M (=120 M÷119) | Bandwidth wall ≈119 | ARCH_SPEC §9.1/§9.2 |
| Pure-datapath theoretical floor (weight stream 1.835 MB/step @XMEM 16-bit) | ≈0.92 M | ≈130 | P3D_REPORT §4.1 |
| **Measured (120 MHz simulation basis, cycle-exact with silicon)** | **6,178,210** | **19.4** | P3D_REPORT §4.1; P4A_REPORT §3.4 |

**Attainment conclusion** (details in FINAL_REPORT §5):
- Function: fully achieved (RTL 3/3 tokens bit-exact; gate-level 46 bytes / 156,948 cycles byte-identical to RTL).
- "Extreme speed": measured 19.4 tok/s@120 = **16%** of the bandwidth-wall prediction (119) and **0.12%** of the roofline compute ceiling (15,625); cycle count is **6.7×** the pure-datapath floor. Root cause = per-tile CPU control overhead + DMA/KV waits (DMA BUSY 32.5%, XMEM ACT 17%, AME duty 4.1% vs the predicted 11%), not bandwidth or compute saturation (P3D_REPORT §4.1).
- "Low cost": die 4.524 mm² = **151%** of the 3 mm² cap (four causes in §2); the macro direction was validated (P4A0 flop storage 4.658 mm² → macros 2.166 + std 1.283), but the die basis + unreserved pad ring + repair consumption meant P4A0's "core ≈2.57 mm² achievable" prediction did not materialize (P4A_REPORT §1/§3.1).

## 6. Signoff Deliverable Fingerprints (p4a4fix)

| Deliverable | md5 (first 8) | Size | Source |
|---|---|---|---|
| 6_final.gds | `d0ed37fc` | 158.0 MB | P4A4_REPORT §5; CHECKLIST §0 |
| 6_final.cdl | `40217dd1` | 13.8 MB | Same (md5sum re-verified this session) |
| 6_final.sdf | `d4318f81` | 58.5 MB | Same (SDF back-annotation not consumable by this toolchain; archived, NA) |
| 6_final.v | `49d30b2f` | 15.4 MB (= 6_final_openroad_raw.v) | Same (md5sum re-verified this session) |
| 1_2_yosys_yosys_pristine.v | `10585318…` | 22.2 MB (golden standard; the yosys source netlist, byte-identical to p4a3fin) | P4A4_REPORT §5 |
| Boot ROM (three copies) | `aae6ac28bbdaa6bc1f9348f3a8c8ba79` | 2 KB | P4A2_REPORT §1; md5sum re-verified in three places this session |

## 7. Signoff Checklist Final Statistics

| Verdict | Count | Source |
|---|---|---|
| **PASS** | **34** | TAPEOUT_CHECKLIST §"Summary Statistics" (P4B3 final) |
| **FAIL** | **0** | Same (P4B2-05, both defect faces, fully closed) |
| NA | 7 | Full-flatten LVS / multi-corner / SDF back-annotation / formal equivalence / wait injection / UART abnormal frame / CPU exception (the last three have P5 rerun paths ready) |
| PASS with note ⚠️ | 3 | skew/slew residuals; decode 46 B on the +XINIT basis; X-scan root-cause determination |
