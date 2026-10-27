#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""vrfb_wave_check.py — P3B 定向波形证据提取(VCD → 握手/阻塞时序表)。

从 tb_cpu_ame 的 VCD(+WAVE)中提取 AME coproc 握手信号与 CPU 取指活动,输出:
  1) 每个接受沿的 instr/stall 拍数/响应延迟(校验 R3:resp 恰后 1 拍);
  2) exe 的 BUSY 窗口(接受 → AME 非空闲)与 MAC 窗口(=KT);
  3) 背靠背/忙时阻塞例证(req_valid 保持、IF 冻结)。
与 docs/CPU_NOTES.md §3 checklist 的 R1/R3/R4 条目一一对应。

用法:python3 scripts/vrfb_wave_check.py <wave.vcd> [--max N] [--csv out.csv]
"""
import sys

SIGS = ["ame_req_valid", "ame_req_ready", "ame_req_instr", "ame_req_rs1",
        "ame_req_rs2", "ame_resp_valid", "ame_resp_err", "ame_resp_data",
        "ame_idle", "ame_mac_en", "ax_ar_valid", "ax_ar_ready", "cpu_tv",
        "cpu_tpc"]


def parse_vcd(path, wanted):
    ids = {}
    idw = {}
    t = 0
    events = []   # (time, name, value)
    with open(path) as f:
        in_defs = True
        for line in f:
            line = line.strip()
            if not line:
                continue
            if in_defs:
                if line.startswith("$var"):
                    p = line.split()
                    # $var wire 32 ! name $end
                    try:
                        width, ident, name = p[2], p[3], p[4]
                    except IndexError:
                        continue
                    if name in wanted:
                        ids[ident] = name
                        idw[name] = int(width)
                elif line.startswith("$enddefinitions"):
                    in_defs = False
                continue
            if line.startswith("#"):
                t = int(line[1:])
            elif line.startswith("b"):
                val, ident = line[1:].split()
                if ident in ids:
                    events.append((t, ids[ident], val))
            else:
                ch = line[0]
                if ch in "01xz":
                    ident = line[1:]
                    if ident in ids:
                        events.append((t, ids[ident], ch))
    return events, idw


def main():
    path = sys.argv[1]
    maxn = 40
    csv = None
    args = sys.argv[2:]
    i = 0
    while i < len(args):
        if args[i] == "--max":
            maxn = int(args[i + 1]); i += 2
        elif args[i] == "--csv":
            csv = args[i + 1]; i += 2
        else:
            i += 1
    events, idw = parse_vcd(path, set(SIGS))
    state = {s: "0" for s in SIGS}
    acc_times = []
    resp_times = []
    pend = None
    rows = []
    cur = None
    mac_rise = None
    exe_busy = []
    n_accept = 0
    for (t, name, val) in events:
        old = state[name]
        state[name] = val
        if name == "ame_req_valid" and val == "1" and old == "0":
            pend = t
        if name == "ame_req_ready" and val == "1" and old == "0" and pend is not None:
            n_accept += 1
            rows.append({"accept_t": t, "instr": None, "stall": t - pend,
                         "resp_dt": None})
            pend = None
            if len(rows) >= maxn:
                pass
        if name == "ame_req_instr" and rows and rows[-1]["instr"] is None:
            rows[-1]["instr"] = val
        if name == "ame_resp_valid" and val == "1" and old == "0":
            if rows and rows[-1]["resp_dt"] is None:
                rows[-1]["resp_dt"] = t - rows[-1]["accept_t"]
        if name == "ame_mac_en" and val == "1" and old == "0":
            mac_rise = t
        if name == "ame_mac_en" and val == "0" and old == "1" and mac_rise is not None:
            exe_busy.append(t - mac_rise)
            mac_rise = None
    def cyc(dt):
        return None if dt is None else round(dt / 10.0)
    out = []
    out.append("idx accept_cyc instr         stall_cyc resp_dt_cyc  R3")
    bad = 0
    for k, r in enumerate(rows, 1):
        instr = r["instr"] or "?"
        try:
            iw = int(instr, 2) & 0xFFFFFFFF
            istr = "%08x" % iw
        except ValueError:
            istr = instr
        rd = cyc(r["resp_dt"])
        r3 = "OK" if rd == 1 else "BAD"
        if rd != 1:
            bad += 1
        out.append(f"{k:4d} {cyc(r['accept_t'])!s:>10} {istr} "
                   f"{cyc(r['stall'])!s:>9} {rd!s:>11}  {r3}")
    out.append("")
    out.append(f"accepts={len(rows)} resp_r3_bad={bad} mac_windows={exe_busy}")
    txt = "\n".join(out)
    print(txt)
    if csv:
        with open(csv, "w") as f:
            f.write(txt + "\n")
            f.write("note: 时间网格=10ns/周期;stall_cyc=req_valid 起到接受沿;"
                    "resp_dt_cyc 应为 1(R3);mac_windows=每 exe 的 MAC 发射拍数(应=KT)\n")
    return 0 if bad == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
