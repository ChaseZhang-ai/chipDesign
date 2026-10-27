# AME-Chip — Agent-Driven Design Process

This document summarizes **how** the chip was built: an orchestrated multi-session AI-agent flow, run by a human lead who read every session report and issued every adjudication. The complete session-by-session Chinese working record is in the git history and local archive (`PLAN_AND_PROMPTS.md`, not part of this public snapshot).

## The Method

**Contract-first parallelism.** Before any RTL was written, one session produced a frozen contract set — `docs/ARCH_SPEC.md` (architecture, address map, pin list), `docs/AME_ISA.md` (custom instruction encodings), `docs/GOLDEN_SPEC.md` (bit-exact numeric protocol), and `rtl/amechip_pkg.sv` + `rtl/interfaces/`. Every downstream session (5 RTL sessions in parallel, then 4 verification sessions, then backend) worked against this frozen contract. Disputes were never silently fixed: any session that found a contract inconsistency filed it in `reports/issues/` and waited for an explicit lead adjudication, which was then recorded in `docs/CONTRACT_PATCH_LOG.md` and propagated to all consumers.

**Bit-exact golden discipline.** A 74-case INT8 golden dataset (5.2 M MACs, covering extremes, remainders, and the full e2e chain) was generated against a written numeric protocol, independently re-verified by a third party, and consumed by RTL sims, random-stress campaigns, and gate sims alike. Every "correct" claim in this project traces to that dataset or to a byte-exact cross-check against it.

**Verification as a separate agent, never self-signoff.** Module authors built their own TBs, but every wave of verification was executed by a *different* session whose only deliverable was evidence — including three independent re-derivations of the golden results. This caught 30+ real defects, including two tapeout-class bugs in the flow itself:

1. **Boot-ROM regression (P4B-01)** — a late `make hex` run silently reverted the boot image; the gate-level netlist booted to a halt. Caught by byte-comparing gate-level UART output against the RTL baseline. Fixed, then protected with an md5 guard rail on the generator.
2. **OpenROAD `read_verilog` bus-ordering defect (P4B2-05)** — OpenROAD's Verilog reader pairs concatenation elements positionally against liberty bus-member order, silently reversing every multi-bit SRAM-macro connection in the netlist, ODB, and GDS. Caught because gate-level SRAM writes were half-X while RTL was clean; root-caused to the OpenROAD importer (not to RTL, not to the macro); fixed with per-bit explicit connections plus a mandatory static binding check (1263/1263 bits, with negative controls reproducing the exact reversal signature) now hard-gated in the flow. Upstream report recommended.

**Bounded iteration.** Frequency and area trade-offs were settled by explicit lead decisions with recorded rationale (contract §9.2, adjudications A–N): e.g., 16 MAC/cycle time-sharing over a systolic array (bandwidth-bound workload), 1 KB buffer apertures, bias-first saturation order, 2-beat requant response, and a hard stop after the third backend round. The final backend run signed off at whatever the process achieved (94.78 MHz), with the 100 MHz near-miss archived instead of chased.

## Wave History

| Wave | Sessions | Outcome |
|---|---|---|
| W0 | environment | ORFS built from source; gcd flow green; toolchain documented |
| W1 | workload profile ∥ architecture contract | miniGPT decode profile (1.97 M MACs/step); frozen contract set |
| W2 | CPU ∥ AME ∥ memory ∥ SoC top ∥ golden dataset | all modules delivered with unit TBs green; 74-case golden released |
| W3 | AME verify ∥ CPU×AME ∥ memory stress ∥ full-chip e2e | AME 74/74 bit-exact; 31/35→all green after patches; e2e 3/3 tokens |
| W3.5 | contract patch ∥ RTL patch wave 1 | contract v2; v0.2 RTL: all known defects closed, full regression green |
| W4/W4.5/W4.9 | backend ∥ signoff (three rounds) | GDS; two tapeout-class flow bugs found & fixed; final signoff FAIL=0 |
| W5 | final report | metrics ledger, reproducibility script, tag `v0.1-tapeout-candidate` |

## Where the Time Went (honest accounting)

The architecture's own performance model predicted a bandwidth wall near 119 tokens/s. The shipped system reaches 15.3 tokens/s (94.78 MHz) — limited not by the engine (AME duty 4.1%) but by per-tile CPU control and DMA waits. That gap is the single biggest v2 lever (kernel scheduling / prefill mode), followed by the 100 MHz frequency sprint and area convergence. All three are quantified in `reports/en/FINAL_METRICS.md` and `docs/en/FINAL_REPORT.md`.
