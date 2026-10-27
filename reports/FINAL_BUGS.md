# FINAL_BUGS — AME-Chip v0.1 Bug Ledger (Archive Edition)

> Session: P5 wrap-up (2026-10-27). Aggregates all 24 issue files under
> `reports/issues/` plus the cross-closure records from the stage reports.
> Status vocabulary: **fixed** (RTL/TB/flow repaired and regressed), **closed**
> (adjudicated / re-verified / waived with rationale), **waived / basis** (capability
> boundary or written waiver), **handed to v2 / P5 / upstream** (not handled in this
> release; destination noted). Original issue text always governs; this document only
> aggregates status and never rewrites any issue description. Final anchor:
> `reports/TAPEOUT_CHECKLIST.md` (P4B3), FAIL=0.

---

## 1. The Four Designated Archive Closures (P5 wrap-up mandate, evidence chains on file)

| # | Item | Closure disposition | Evidence chain |
|---|---|---|---|
| 1 | **P4B-01** (boot ROM content regression: netlist/GDS baked in the old boot.s image ≠ P1BX-B baseline; P4B judged "current GDS must not tape out") | **Fixed + closed**: repaired by P4A2 (ROM freeze), unlocked by P4B2, finally verified by P4B3 | P4A2 froze the P3D loader (md5 `aae6ac28…`, three copies identical) + `check_boot_hex.sh` md5 guard (hooked into make hex; regression-injection experiment tested both directions) → P4A3 re-synthesized with the frozen ROM (p4a3fin) → P4B2 §2 gate-level banner "P3D BOOT OK\n" byte-identical to baseline → P4B3 re-ran PASS on p4a4fix (`uart_p4b3_boot.bin` md5 `3bcbbda4…`). issues/P4B.md (P4B-01/P4B-06), P4A2_REPORT §1, P4B2_REPORT §2, P4B3_REPORT §3 |
| 2 | **P4B2-05** (BLOCKER, two defect faces: (1) gate-level write path `wdata[15:0]≡X`; (2) SRAM-macro concatenated-port bit order reversed across delivery netlist/ODB/GDS/CDL — tapeout class) | **Fixed + closed on both faces**: (2) repaired by P4A4; (1) characterized and disposed by P4B3; P4B3 re-verified both | **(2)**: root cause = OpenROAD/OpenSTA `read_verilog` concatenation × liberty member-order positional pairing (`VerilogReader.cc makeNamedInstPins`); fix = per-bit explicit connections before import (`p4a4_bitblast_macro_conns.py`) + full-chain re-export (p4a4fix) + a binding gate; **P4B3 independent recheck: positive control 1263/1263 bits (6_final.v + 6_final.cdl dual basis) + negative control (p4a3fin) 1728 mismatches reproducing the exact reversal signature + a 21-bit independent spot check + pin-level LVS (L1/L2/L3)**. **(1)**: root cause = gate-sim X-pessimism artifact (memc queue slots without resets; X leaked through the yosys AND-OR cone into `xmem_a_o[1]`); the force experiment proved the netlist matches RTL cycle-by-cycle in a fully-known state (no synthesis miscompile, **silicon function intact**); disposition = gate sims on `+XINIT` (silicon power-up semantics) → **46-byte md5 `9d4c5358…` identical to the RTL reference / 156,948 cycles identical / X-scan zero X throughout**. P4A4_REPORT §1–§4, P4B3_REPORT §1–§3, CHECKLIST §"BLOCKER zeroing record" |
| 3 | **P3B B2 / P1BXC-05** (vrfb integration-TB decode SCR channel-4 scr_kvrow mismatch: d01/d03 off by 1 byte, d02 by 4 bytes, got constantly 0x1137) | **Archived closed (TB defect, not RTL)**: located by P1BX-B | P1BXB C8 disposition: mismatches concentrate in the scr_kvrow region — **the vrfb integration TB's XMEM fast-path read is anomalous (lbu reads from XMEM returned stale OCSRAM fast-path values), not an RTL defect**; the real P3D e2e on the same data passed 3/3 tokens bit-exact (independent-TB cross validation); P1BXC-05 further proved the full-v0.2-baseline failure signature was bit-identical (unrelated to that round's changes). The signoff environment (tb/soc e2e) is unaffected. Archived as a known vrfb-TB issue; no longer an RTL release blocker. issues/P1BXB.md C8, issues/P1BXC.md P1BXC-05, P3B_REPORT |
| 4 | **P4A-04 / P4A-14** (timing-structure escalations under the no-RTL-change discipline: P4A-04 = CPU AXI-bridge FSM chain −11.48 ns; P4A-14 = s1_rel→requant parameter load −3.928 ns) | **Escalations archived; fixed and closed by RTL v0.3; the residual timing sprint moved to the v2 roadmap** | Disposition of both escalations = lead adjudication N authorizing RTL v0.3 (P1BXC) → P1BXC-01 (CPU request register + resp-in-flight window gate) / P1BXC-02 (requant input capture stage) fixed them; 1_synth re-measure showed the old paths structurally gone; P4A3 signed off at RTL v0.3's achieved **94.78 MHz** (these two escalations were exactly the root fixes behind 84.6→94.78). issues/P4A.md (originals kept as "escalated, no-RTL-change", not rewritten), issues/P1BXC.md P1BXC-01/02, P4A3_REPORT §4.1. The residual critical family after v0.3, y1_q→p_u_q (100 MHz short by 7 endpoints, −0.55), is v2 roadmap item (1) |

## 2. P1BX-D Adjudication Record (designated archive)

**P1BX-D (RTL hardening: reset the `memc_xmem` read/write queue slots `rq_addr`/`wq_addr`, or register the `xmem_a_o` outputs; origin = issues/P4B3.md leftover 1 / P4B2-05b disposition (2))**

- **Adjudication: not adopted; moved to the v2 roadmap (optional hardening item).**
- Rationale: (1) the discrimination experiment proved silicon function is intact — the only leaking bit is `xmem_a_o[1]`, which is constantly 0 under the 4B-aligned protocol, and the force experiment proved the netlist matches RTL cycle-by-cycle in a fully-known state (no synthesis miscompile); (2) the XINIT basis (injecting the protocol-constant bits [1:0], exactly covering the only leak) already achieved checklist FAIL=0, with the 46-byte/156,948-cycle gate equivalence standing; (3) adopting it requires re-running synthesis → P&R → full-chain re-signoff (about two days), for a benefit limited to a "cleaner" gate-sim basis with no silicon-function gain.
- Consequence: the gate-level signoff permanently carries the `+XINIT` basis (noted in CHECKLIST ⚠️); if v2 does an RTL revision it can implement this then and retire the basis.

## 3. Full Ledger (by issue file; status per original text + cross-closures)

### W1 Contract and profiling (P1A/P1B/P1BXA)
| Item | Summary | Status |
|---|---|---|
| P1A 1.1–1.3 | torch export / tpu-mlir input / op parsing | Resolved (legacy exporter + opset17; direct npz production; 62/62, 60/60 PASSED) |
| P1A §4/§5 | scalar-RISC bottleneck note; gitignore/models in repo | Recorded / left to owner (open, not a defect) |
| P1B self-check 1–8 | KV pitch / ISA samples / TRANSPOSE / DMA pitch / guard / storage accounting / golden alignment | Fixed (before contract freeze) |
| P1B self-check 9 / R1–R7 | architecture-dispute adjudications; K-major weight blobs; XMEM bandwidth; OC SRAM; TRANSPOSE difficulty; group FSM; iverilog warnings | Adjudicated not-adopted / passed downstream / closed (R2 closed by adjudication J, R3 by adjudication K, R4 closed by P3C backstop) |
| P1BXA X1–X6 | contract-maintenance patch (adjudications A–H) | Implemented (5/5 green); X1 SLVERR enhancement deferred to P2C follow-up (recorded) |
| P1BXA T1–T11 | pending-adjudication clusters (throughput basis / st.y out-of-range / ld.x 9-bit offset / immediate syntax / UART OVERRUN etc.) | Held pending → **handed to v2 (ISA v2 / contract v2 topics)** |

### W2 five sessions (P2A–P2E)
| Item | Summary | Status |
|---|---|---|
| P2A-I1/I2 | ISA sample typo; yosys 0.70 pkg parsing | Fixed (P1BXA adjudications F/H) |
| P2A-I3/I4 | interface-port workaround; throughput-basis clarification | Worked around / pending adjudication (→v2) |
| P2A add. 1–10 | ten CPU micro-architecture defects (fetch/WB/write-through/muldiv/CSR etc.) | Fixed (within P2A session) |
| P2B I-1/I-4/I-6/I-7 | Y32/YQ out-of-region; cfg samples; comments; requant pipeline | Fixed (adjudications A/F; comments; adjudication G) |
| P2B I-2/I-3/I-5/I-8 | st.y out-of-range semantics; repeated exe; ld.x offset; illegal-field acceptance | Basis recorded + pending adjudication (→v2 T2/T3/T4/T5) |
| P2C-1/2/3/5 | SLICE field widths; Y32/YQ routing; kv_sram_if backend B; SLVERR reachability | Fixed / adjudicated final / documented / recorded |
| P2C-4 | DMA PITCH annotation | Pending adjudication (→v2 T6) |
| P2D #1/#2/#4 | cfg sample contradiction; rd write-back set; Y32/YQ out-of-region | Fixed (adjudications E/F/A) |
| P2D #3/#5/#6 | immediate syntax; UART OVERRUN; st.y cfg shadow | Current disposition + pending adjudication (→v2 T7/T8/T2) |
| P2E 4.1–4.5 | five pitfalls in the self-written golden reference | Handled (74/74 ALL GREEN) |
| P2E §6 | L2 fixed-point / SRAM init / multi-step golden | Handed to v2 / on demand |

### W3 verification (P3A–P3D)
| Item | Summary | Status |
|---|---|---|
| P3A-01/02/03 | verilator idle false-green; ld.w before cfg; G20 variant key | Fixed (P1BXB C10/C6/D4; verilator 51/51 true replay) |
| P3B A1–A10/B1/C1–C3 | TB/program-side defects + g24 requant boundary | Fixed (B1 = P1BXB C7); C1 recorded (contract finalized) |
| **P3B B2 (decode SCR ch4)** | **scr_kvrow mismatch** | **Archived closed (TB fast-path anomaly, not RTL — see §1.3)** |
| P3C-1/2 | DMA ABORT ARVALID; memc read-prefetch stale slot (=P3D-07, 46 hits in 1 M cycles of silent corruption) | Fixed (P1BXB C5/C1; repro converted to a regression gate) |
| P3C-3 | SLICE compatible encoding | Closed by contract finalization (P1BXB C11) |
| P3D-01/02/07/08 | CPU stale fetch; DMA DONE missed; MEMC read pre-drive; unaligned reads (four blockers) | Fixed (P1BXB C2/C3/C1/C4; P3D patch removed, RTL properly fixed) |
| P3D-03/04/05/09/10 | KV events; boot-ROM redundancy; bases; chaining; build_hex truncation | Fixed (P1BXB C12/C13/A1A2C14/C9) |
| P3D-06 | verification microkernel 3.4 KB > production 2 KB budget | Recorded, **handed to P5/v2** (trimmed-version recheck) |

### P1BX patch sessions (v0.2/v0.3 freeze patches)
| Item | Summary | Status |
|---|---|---|
| P1BXB A1–A8/D1–D4 | P1BX-A migration handoff + doc follow-through | Fixed / verified |
| P1BXB B1/B2/B8 | AME window / MAC x→Y / WBUF-XBUF pre-conversion (timing) | Fixed (STA all MET) |
| P1BXB B3–B7 | five structural timing escalations | Escalated → converged in P4A measurements or closed by P1BXC (see §1.4); B7 macro-ization executed by P4A |
| P1BXB B9–B13 | slot wrappers / boot_rom initial / flow pitfalls / CPU optimization / XMEM_DW | Fixed / closed (adjudication J) |
| P1BXB C1–C14 | P3-series RTL proper fixes (see P3D/P3C rows) | Fixed (except C8 → §1.3) |
| P1BXB E1–E6 | adjudications I–M landing | All landed |
| P1BXC-01/02 | CPU→AME load / requant parameter load (the P4A-04/14 fixes) | Closed (v0.3; old paths structurally gone) |
| P1BXC-03/04 | resp-consumption ownership; minstret double defect | Closed |
| P1BXC-05 | vrfb scr_kvrow (stock issue) | Archived closed (see §1.3) |
| P1BXC-06 | tb/soc make all + smoke1 banner (P4A2-02) | Closed |
| P1BXC-07 | DMA rd_x→xmem_a_o third structural floor (11.05 ns predicted) | Escalation archived: measured need ≈8.73 ns, predicted floor did not materialize; the 94.78 MHz signoff landed better than predicted (P4A3 §4.2) |

### W4 backend (P4A/P4A0/P4A2/P4A3/P4A4)
| Item | Summary | Status |
|---|---|---|
| P4A0 I-1~I-8 | eight probe timing/area upper bounds | All disposed (B1/B2 fixed; B3–B6 see §1.4; I-7/I-8 macro-ization executed by P4A; prediction-vs-measurement in P4A_REPORT §1) |
| P4A0 I-9~I-13 | slot wrappers / boot initial / flow pitfalls / CPU optimization / DW=32 | Fixed / closed |
| P4A-01 | macro word-width policy (P4A0 accounting error; WBUF/XBUF cannot use 64x256_8) | Fixed (three 128x256_8; area cost in cause (1)) |
| P4A-02/03/03R | RTLMP blockage; PDN macro grid; met3-met4 scheme falsified | Handled / cured (derived LEF + precise via3; 3_5 gate dual-green) |
| **P4A-04** | **CPU AXI-bridge FSM chain −11.48 ns (no-RTL-change escalation)** | **Archived: fixed by P1BXC-01; residual to v2 (see §1.4)** |
| P4A-05/06/08/09/11/15 | records/experience (model competition; LEF annotation; PSM gate 3_5; blockage pitfalls; WSL-restart supervision) | Recorded / codified (check_pdn_gate.sh; route_supervisor) |
| P4A-07/07R | macro LEF 516 overlapping power-pin pairs | Concluded (LEF mislabel; no GDS short; connected components disjoint) |
| P4A-10/13/13R | in-macro DRC exemption basis; the "53k macro-external" false alarm | Waiver finalized / retracted (P4A-13R: classifier defect; **macro-external is truly 0**) |
| P4A-12 | in-macro met4 vdd strap short risk | Avoided (power straps y≥52; v2 full-flow rerun green) |
| **P4A-14** | **s1_rel→p_u_q −3.928 ns (no-RTL-change escalation)** | **Archived: fixed by P1BXC-02; residual to v2 (see §1.4)** |
| P4A2-01 | 84.6 MHz missed (frozen-ROM fmax 82.69) | Escalated → closed by P4A3 under the "achieved-fmax signoff" basis (94.78 MHz) |
| P4A2-02 | smoke1 banner would always FAIL | Closed (P1BXC-06) |
| P4A2-03/05/07 | basis/methodology records | Recorded, closed |
| P4A2-04 | STA-0511 (get_pins hierarchical pattern) | Closed (sta_final.tcl v2, two-stage pattern) |
| P4A2-06 | CDL export ODB-0287 | Closed (masters-merged-file method) |
| **P4A3-01** | **config.mk ABC_AREA=1 recipe deviation (p4a3rtl03 cells +39%, area worse)** | **Closed**: reverted to ABC_AREA=0 + forensic comments; p4a3rtl03 archived and quarantined; p4a3fin re-synthesized with the correct recipe (lesson in v2 roadmap item (5)) |
| P4A4-01 | the bit-order reversal fix proper | Closed (= P4B2-05(2), see §1.2) |
| P4A4-02/03/05 | delivery .v basis; supervisor dependency; race | Closed (method codified) |
| P4A4-04 | write-path X (independent-defect escalation) | Closed (= P4B2-05(1), see §1.2) |

### W4.5/W4.9 signoff (P4B/P4B2/P4B3/P4READY)
| Item | Summary | Status |
|---|---|---|
| P4READY ISSUE-1 | std-cell behavioral models missing | Resolved (volare PDK sky130_fd_sc_hd.v + primitives.v) |
| P4READY ISSUE-2/3 | TT single corner; SDF not a default product | Basis waived (NA, capability boundary); SDF produced and archived (NA) |
| **P4B-01** | boot ROM regression | **Fixed + closed (see §1.1)** |
| P4B-02 | xmem_a_o idle X | Recorded → P4B3 characterized as the same X-pessimism exposure, eliminated after XINIT ("all outputs known from cyc 21"); hardening = P1BX-D (see §2) |
| P4B-03 | hold report empty / STA-0511 | Closed (P4A2-04) |
| P4B-04 | SDF back-annotation not executable | Recorded (NA, toolchain limit) |
| P4B-05 | formal equivalence incomplete (284 miters stuck at macro black boxes) | Recorded, **handed to v2/P5** (hierarchical equivalence; substitute evidence upgraded to 46 B + 156,948 cycles) |
| P4B-06 | make hex accidental boot.hex overwrite | Closed (with P4B-01, md5 guard) |
| P4B2-01/02 | RTL-reference wrapper pitfalls; TB silence threshold | Closed |
| P4B2-03 | gate X-scan x_after_known>0 | Closed (kept the P4B-02 record; zeroed after P4B3 XINIT) |
| P4B2-04 | LVS reference-netlist assembly basis | Closed (method recorded) |
| **P4B2-05** | **BLOCKER, two defect faces** | **Fixed + closed on both faces (see §1.2)** |
| P4B2-06 | copy-segment transient X | Merged into P4B2-05, closed with it |
| P4B3-01/02/03 | probe basis; KLayout API pitfalls; XINIT first version pinned addresses | Closed (recorded / method / corrected) |
| P4B3 leftovers 2/3 | full-flatten LVS; three injection-class gate regressions | **Handed to P5/v2 (see §5)** |

## 4. Waivers and Bases (carried by the signoff; not defects)

| Item | Basis | Rationale |
|---|---|---|
| In-macro DRC violations | The platform deck has no OpenRAM s8rf2 device rules; in-macro items (463,809, p4a4fix) are waived per the macro library deliverables; **macro-external 0** | P4A-10/P4A-13R; CHECKLIST §2 |
| STA recovery/removal | Reset-tree false_path explicit waiver (written SDC rationale) | CHECKLIST §4 |
| TT single corner only | Lib capability boundary; multi-corner signoff NA | CHECKLIST §4; P4READY §1 |
| 329 max_slew residuals | A converging family (macro wmask/din pins + antenna diodes), worst −0.25, archived ⚠️ | P4B3 §5 |
| Gate signoff +XINIT basis | Gate-level X-pessimism disposition (silicon power-up semantics); carried long-term unless P1BX-D is adopted | CHECKLIST §6; §2 of this file |
| LVS pin-level three-layer equivalent | L1 binding 1263/1263 + L2 GDS↔DEF 1:1 + L3 885 valid pins 100% contact, in lieu of full flatten (which did not converge in >4.5 h; optional) | CHECKLIST §3; P4B3 §4 |

## 5. Handoff List (where open items go)

**To the v2 roadmap** (details in FINAL_REPORT §8):
(1) timing sprint to 100 MHz (7 endpoints −0.55, single y1_q→p_u_q family, P4A3 sprint archive); (2) area convergence;
(3) full-flatten LVS / multi-corner / SDF back-annotation / hierarchical formal equivalence; (4) prefill / 32×32 / microkernel scheduling;
(5) flow lessons (SRAM macro bit order, ABC_AREA recipe, make hex guard); (6) optional hardening
(P1BX-D queue-slot resets, three injection-class gate regressions, OpenSTA upstream report).

**To upstream tools** (recommend reporting; this project has dual guard rails in place):
- OpenROAD/OpenSTA `read_verilog` concatenation × liberty member-order positional pairing
  (`VerilogReader.cc makeNamedInstPins`, P4A4-01/P4B3 leftover 4);
- OpenRAM LEF power-pin extraction mislabel (P4A-07R); ORFS RTLMP blockage false positive (P4A-02);
- sky130hd platform PDN macro grid not connected to met3 (P4A-03R).

**Still pending adjudication (contract v2 topics)**: P1BXA T1–T11 (T4 = ld.x 9-bit offset ISA v2 widening, etc.).

**To post-P5 follow-ups (non-blocking for tapeout)**: P3D-06 production-microkernel 2 KB budget trim recheck;
P1A §5 gitignore/models-in-repo decision (partially handled by this session's curation commits).
