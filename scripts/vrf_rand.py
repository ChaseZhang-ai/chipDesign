#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""vrf_rand.py — P3A 随机压力场景生成与执行(≥500 组,第三方独立模型)

重点覆盖 P2B 未深入的交错场景(任务书第 3 条):
  * ld.w/ld.x 与 exe 交叠(§5 乒乓节奏:算 t 片时装 t+1 片)
  * sync 随机位置插入
  * st.y/st.q 交替、乱序与重复读(含片外 lane、未配置通道)
  * Y32 预置 bias 后续累(bias_first 口径,模型逐步 SAT32)
  * cfg/qcfg 中途切换(KT 余数切换、M/S 运行期改写后续 st.q 生效)
  * 双 tile 组轮换(乒乓)

期望值由本文件的独立整数模型(python)逐条计算并内联到 ops 流(op 3/4 带
期望字段),tb/ame/verify_full.sv 在仿真内逐位判罚——生成器与 RTL/对拍器
三方互相独立。每批文件末尾有一段 §5 稳态 duty 测量(PERF-SNAP 快照括起),
与基线 duty=88.9%@KT=16 直接对比。

用法:
  python3 scripts/vrf_rand.py emit  [--n 520] [--per-batch 20] [--seed 20261023]
  python3 scripts/vrf_rand.py run   [--jobs 8]
退出码:run 模式全部 PASS 且 duty 劣化 ≤2pp → 0。
"""
import argparse
import concurrent.futures as fut
import glob
import json
import os
import random
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORK = os.path.join(ROOT, "tb", "ame", "work", "vrf", "rand")

A_AME_BASE = 0x2000_1000
WBUF_WIN = A_AME_BASE + 0x0000
XBUF_WIN = A_AME_BASE + 0x0400
Y32_WIN = A_AME_BASE + 0x0800
YQ_WIN = A_AME_BASE + 0x0880
STATUS_WIN = A_AME_BASE + 0x08C0
WBUF_DEPTH = 1024
XBUF_DEPTH = 1024

I32MIN, I32MAX = -(1 << 31), (1 << 31) - 1
M64 = (1 << 64) - 1


def sat32(v):
    return I32MIN if v < I32MIN else (I32MAX if v > I32MAX else v)


def to_s64(v):
    v &= M64
    return v - (1 << 64) if (v >> 63) & 1 else v


def s8(v):
    """原始字节 → int8 有符号。"""
    return v - 256 if v >= 128 else v


def requant(y, m, s, rnd):
    """GOLDEN_SPEC §2.2(S=0 未配置域:与 RTL 一致钳为移 0 无舍入)。"""
    prod = to_s64(int(y) * int(m & 0xFFFF_FFFF))
    sh = s if s >= 1 else 0
    if rnd and s >= 1:
        prod = to_s64(prod + (1 << (s - 1)))
    v = prod >> sh
    return max(-128, min(127, v))


class Model:
    """连续追踪一批场景的硬件可见状态(跨场景不清,模型与流同构)。"""

    def __init__(self):
        self.wbuf = bytearray(WBUF_DEPTH)
        self.xbuf = bytearray(XBUF_DEPTH)
        self.tile = {0: {}, 1: {}}   # g -> {(n,k): byte}
        self.xreg = {0: [0] * 16, 1: [0] * 16}
        self.Y = [0] * 16
        self.rq = [[0, 0, 0] for _ in range(32)]
        self.cfg = (0, 0)             # N_eff, KT
        self.mac_cycles = 0

    def do_cfg(self, n, kt):
        self.cfg = (n, kt)

    def do_qcfg(self, ch, m, s, r):
        self.rq[ch] = [m, s, r]

    def wr_wbuf(self, addr_rel, data, wstrb):
        base = addr_rel % WBUF_DEPTH
        for i in range(4):
            if wstrb & (1 << i):
                self.wbuf[(base + i) % WBUF_DEPTH] = (data >> (8 * i)) & 0xFF

    def wr_xbuf(self, addr_rel, data, wstrb):
        base = addr_rel % XBUF_DEPTH
        for i in range(4):
            if wstrb & (1 << i):
                self.xbuf[(base + i) % XBUF_DEPTH] = (data >> (8 * i)) & 0xFF

    def do_ldw(self, region, tsel):
        base = (region * 256) % WBUF_DEPTH
        n_eff, kt = self.cfg
        for n in range(n_eff):
            for k in range(kt):
                self.tile[tsel][(n, k)] = s8(self.wbuf[(base + n * kt + k) % WBUF_DEPTH])

    def do_ldx(self, off, xsel):
        for k in range(16):
            self.xreg[xsel][k] = s8(self.xbuf[(off + k) % XBUF_DEPTH])

    def do_exe(self, tsel, is_f):
        if is_f:
            self.Y = [0] * 16
        n_eff, kt = self.cfg
        for k in range(kt):
            xk = self.xreg[tsel][k]
            for n in range(n_eff):
                self.Y[n] = sat32(self.Y[n] + self.tile[tsel].get((n, k), 0) * xk)
        self.mac_cycles += kt

    def st_y(self, i):
        return self.Y[i]

    def st_q(self, i):
        m, s, r = self.rq[i]
        return requant(self.Y[i], m, s, r)

    def yq_word(self, w):
        q = [self.st_q(4 * w + j) if 4 * w + j < 16 else 0 for j in range(4)]
        return (q[0] & 0xFF) | (q[1] & 0xFF) << 8 | (q[2] & 0xFF) << 16 | (q[3] & 0xFF) << 24


class Ops:
    def __init__(self):
        self.lines = []
        self.n_mac_exp = 0

    def cp(self, instr, rs1, rs2):
        self.lines.append(f"0 {instr:08X} {rs1 & 0xFFFFFFFF:08X} {rs2 & 0xFFFFFFFF:08X}")

    def cp_chk(self, instr, rs1, rs2, exp_data, exp_err):
        self.lines.append(f"3 {instr:08X} {rs1 & 0xFFFFFFFF:08X} {rs2 & 0xFFFFFFFF:08X} "
                          f"{exp_data & 0xFFFFFFFF:08X} {int(exp_err)}")

    def wr(self, addr, data, wstrb=0xF, exp_err=0):
        self.lines.append(f"1 {addr:08X} {data & 0xFFFFFFFF:08X} {wstrb:02X} {int(exp_err)}")

    def rd(self, addr, exp_data, exp_err=0):
        self.lines.append(f"2 {addr:08X} {exp_data & 0xFFFFFFFF:08X} {int(exp_err)}")

    def dump_chk(self, f, li, gn, exp):
        self.lines.append(f"4 {int(f)} {li & 0xFFFFFFFF:08X} {gn & 0xFFFFFFFF:08X} "
                          f"{int(exp) & 0xFFFFFFFF:08X}")

    def wait(self, n):
        self.lines.append(f"5 {n:08X}")

    def snap(self, tag):
        self.lines.append(f"9 {tag:08X}")

    def text(self):
        return "\n".join(self.lines) + "\n"


def enc_cfg(n, kt):
    return (((n & 0x1F) | ((kt & 0x3F) << 5)) << 20) | 0x0B


def enc_qcfg(n):
    return (0x01 << 25) | (0x01 << 12) | ((n & 0x1F) << 7) | 0x0B


def enc_ldw(region, tsel):
    return (0x02 << 25) | (0x02 << 12) | 0x0B, ((region & 3) | ((tsel & 1) << 2)), 0


def enc_ldx(off, xsel):
    return (0x03 << 25) | (0x03 << 12) | 0x0B, ((off & 0x1FF) | ((xsel & 1) << 9)), 0


def enc_exe(tsel, is_f):
    f7 = 0x05 if is_f else 0x04
    return (f7 << 25) | (0x04 << 12) | 0x0B, (tsel & 1), 0


def enc_sync():
    return (0x08 << 25) | (0x07 << 12) | 0x0B


def enc_st(f, i):
    f7 = 0x06 if f == 0 else 0x07
    f3 = 0x05 if f == 0 else 0x06
    return (f7 << 25) | (f3 << 12) | 0x0B, (i & 0x1F), 0


def emit_bytes(ow, byte_addr, data):
    idx = 0
    while idx < len(data):
        cur = byte_addr + idx
        wa = cur & ~3
        lane = cur & 3
        n = min(4 - lane, len(data) - idx)
        ow.wr(wa, int.from_bytes(data[idx:idx + n], "little"), ((1 << n) - 1) << lane)
        idx += n


def rand_ms(rng):
    m = rng.choice([0, 1, 2, 3, 0x7FFF_FFFF, 0xFFFF_FFFF,
                    rng.randrange(0, 1 << 31), rng.randrange(0, 1 << 32)])
    s = rng.choice([1, 2, 3, 4, 8, 15, 16, 31, 32, 33, 47, 63])
    return m, s, rng.randrange(2)


def gen_scenario(ow: Ops, mdl: Model, rng, idx):
    """一条随机 GEMV 场景(含交错事件),模型同步推进并内联期望。"""
    n_eff = rng.choice([1, 2, 3, 7, 15, 16])
    K = rng.choice([7, 13, 16, 17, 31, 32, 48, 64, 97, 128, 200, 256,
                    300, 512, 513, 640, 768, 1024])
    kt = rng.choice([16, 16, 16, 16, 8, 4])
    bias_mode = rng.random() < 0.4
    style = rng.choice(["seq", "ovl", "ovl"])
    sync_p = rng.choice([0.0, 0.15, 0.3])
    mid_qcfg = rng.random() < 0.35

    W = [[rng.randrange(-128, 128) for _ in range(K)] for _ in range(n_eff)]
    x = [rng.randrange(-128, 128) for _ in range(K)]
    bias = [rng.choice([0, 0, rng.randrange(-1 << 30, 1 << 30),
                        I32MAX - rng.randrange(0, 4096),
                        I32MIN + rng.randrange(0, 4096)])
            for _ in range(n_eff)] if bias_mode else None

    ms = [rand_ms(rng) for _ in range(n_eff)]
    for i in range(n_eff):
        m, s, r = ms[i]
        ow.cp(enc_qcfg(i), m & 0xFFFF_FFFF, (s & 0x3F) | (r << 6))
        mdl.do_qcfg(i, m, s, r)

    ts = (K + kt - 1) // kt
    kts = [min(kt, K - t * kt) for t in range(ts)]
    ow.cp(enc_cfg(n_eff, kts[0]), 0, 0)
    mdl.do_cfg(n_eff, kts[0])

    if bias is not None:
        for i in range(n_eff):
            ow.wr(Y32_WIN + 4 * i, bias[i] & 0xFFFFFFFF)
            mdl.Y[i] = sat32(bias[i])
        first_is_f = False
    else:
        first_is_f = True

    x_full_done = [False]

    def prep_tile(t, tsel):
        """写 WBUF region + (必要时 x) + ld.w/ld.x,模型同步。"""
        k0 = t * kt
        kt_t = kts[t]
        region = t % 4
        region_base = (region * 256) % WBUF_DEPTH
        blob = b"".join(bytes(v & 0xFF for v in W[ni][k0:k0 + kt_t])
                        for ni in range(n_eff))
        emit_bytes(ow, WBUF_WIN + region_base, blob)
        for i, b in enumerate(blob):
            mdl.wbuf[(region_base + i) % WBUF_DEPTH] = b
        if k0 <= 0x1FF:
            if not x_full_done[0]:
                emit_bytes(ow, XBUF_WIN, bytes(v & 0xFF for v in x))
                for i, b in enumerate(x):
                    mdl.xbuf[i % XBUF_DEPTH] = b & 0xFF
                x_full_done[0] = True
            i_, r1, r2 = enc_ldx(k0, tsel)
        else:
            sl = bytes(v & 0xFF for v in x[k0:k0 + kt_t])
            emit_bytes(ow, XBUF_WIN, sl)
            for i, b in enumerate(sl):
                mdl.xbuf[i % XBUF_DEPTH] = b
            i_, r1, r2 = enc_ldx(0, tsel)
        ow.cp(i_, r1, r2)
        mdl.do_ldx(r1 & 0x1FF, tsel)
        i_, r1, r2 = enc_ldw(region, tsel)
        ow.cp(i_, r1, r2)
        mdl.do_ldw(region, tsel)

    cur_kt = kts[0]
    for t in range(ts):
        if kts[t] != cur_kt:
            ow.cp(enc_cfg(n_eff, kts[t]), 0, 0)
            mdl.do_cfg(n_eff, kts[t])
            cur_kt = kts[t]
        tsel = t % 2
        if rng.random() < sync_p:
            ow.cp(enc_sync(), 0, 0)
        if mid_qcfg and t == ts // 2 and n_eff > 0:
            ch = rng.randrange(n_eff)
            m, s, r = rand_ms(rng)
            ow.cp(enc_qcfg(ch), m & 0xFFFFFFFF, (s & 0x3F) | (r << 6))
            mdl.do_qcfg(ch, m, s, r)
        prep_tile(t, tsel)
        if style == "ovl" and t + 1 < ts:
            nxt = t + 1
            if kts[nxt] != cur_kt:
                ow.cp(enc_cfg(n_eff, kts[nxt]), 0, 0)
                mdl.do_cfg(n_eff, kts[nxt])
                cur_kt = kts[nxt]
            prep_tile(nxt, nxt % 2)
        ow.cp(*enc_exe(tsel, is_f=(t == 0 and first_is_f)))
        mdl.do_exe(tsel, is_f=(t == 0 and first_is_f))

    ow.cp(enc_sync(), 0, 0)

    reads = []
    for i in range(n_eff):
        reads += [(0, i), (1, i)]
    if rng.random() < 0.5 and n_eff < 16:
        reads.append((0, rng.randrange(n_eff, 16)))
    reads *= 2
    rng.shuffle(reads)
    for f, i in reads:
        exp = mdl.st_y(i) if f == 0 else mdl.st_q(i)
        ow.cp_chk(*enc_st(f, i), exp, 0)
    for w in range(4):
        ow.rd(YQ_WIN + 4 * w, mdl.yq_word(w))
    for i in rng.sample(range(16), k=min(4, 16)):
        ow.rd(Y32_WIN + 4 * i, mdl.Y[i] & 0xFFFFFFFF)


def gen_duty_section(ow: Ops, mdl: Model, rng):
    """duty 测量(P2B proto T8 完全同口径):逐 exe 窗口。
    每次:[ld.w; ld.x; sync; SNAP(z); exe; sync; SNAP(r)]。
    sync 保证快照点处于 IDLE,故 r 窗口里 mac=KT、busy=KT+2(BUSY 时长),
    duty = KT/(KT+2) = 888/1000@KT=16,可直接与基线对比。
    """
    pat = [bytes(rng.randrange(-128, 128) & 0xFF for _ in range(256)) for _ in range(2)]
    xv = [bytes(rng.randrange(-128, 128) & 0xFF for _ in range(16)) for _ in range(2)]
    ow.cp(enc_cfg(16, 16), 0, 0)
    mdl.do_cfg(16, 16)
    for g in range(2):
        emit_bytes(ow, WBUF_WIN + 256 * g, pat[g])
        for i, b in enumerate(pat[g]):
            mdl.wbuf[256 * g + i] = b
        emit_bytes(ow, XBUF_WIN + 16 * g, xv[g])
        for i, b in enumerate(xv[g]):
            mdl.xbuf[16 * g + i] = b
    KT = 16
    mac0 = mdl.mac_cycles
    for t in range(8):
        g = t % 2
        ow.cp(*enc_ldw(g, g))
        mdl.do_ldw(g, g)
        ow.cp(*enc_ldx(16 * g, g))
        mdl.do_ldx(16 * g, g)
        ow.cp(enc_sync(), 0, 0)
        ow.snap(0x7A000000 | t)          # tag='z'+idx
        ow.cp(*enc_exe(g, is_f=(t == 0)))
        mdl.do_exe(g, is_f=(t == 0))
        ow.cp(enc_sync(), 0, 0)
        ow.snap(0x72000000 | t)          # tag='r'+idx
    return mac0, 8 * (KT + 2)


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)

    pe = sub.add_parser("emit")
    pe.add_argument("--n", type=int, default=520)
    pe.add_argument("--per-batch", type=int, default=20)
    pe.add_argument("--seed", type=int, default=20261023)
    pe.add_argument("--out", default=WORK)

    pr = sub.add_parser("run")
    pr.add_argument("--jobs", type=int, default=8)
    pr.add_argument("--workdir", default=WORK)

    args = ap.parse_args()
    if args.cmd == "emit":
        os.makedirs(args.out, exist_ok=True)
        rng = random.Random(args.seed)
        meta = []
        nb = (args.n + args.per_batch - 1) // args.per_batch
        mac_at_batch = 0
        for b in range(nb):
            mdl = Model()
            ow = Ops()
            cnt = 0
            scen_in_batch = 0
            while cnt < args.n and scen_in_batch < args.per_batch:
                idx = b * args.per_batch + scen_in_batch
                gen_scenario(ow, mdl, rng, idx)
                scen_in_batch += 1
                cnt += 1
            path = os.path.join(args.out, f"batch_{b:02d}.ops")
            with open(path, "w") as f:
                f.write(ow.text())
            dow = Ops()
            mac0, busy_exp = gen_duty_section(dow, mdl, rng)
            dpath = os.path.join(args.out, f"duty_{b:02d}.ops")
            with open(dpath, "w") as f:
                f.write(dow.text())
            meta.append(dict(batch=b, scenarios=scen_in_batch, file=os.path.basename(path),
                             duty_file=os.path.basename(dpath),
                             duty_mac0=mac0, duty_mac=mdl.mac_cycles - mac0,
                             duty_busy_exp=busy_exp))
            mac_at_batch = mdl.mac_cycles
        with open(os.path.join(args.out, "manifest.json"), "w") as f:
            json.dump(dict(n_total=cnt, batches=meta, seed=args.seed,
                           model_mac_total=mdl.mac_cycles), f, indent=1)
        print(f"vrf_rand emit: {cnt} 场景 → {nb} 批 → {args.out}(模型累计 MAC 相 {mdl.mac_cycles} 拍)")
        return 0

    # ---- run ----
    exe = os.path.join(args.workdir, "vsim")
    if not os.path.exists(exe):
        cmd = ["verilator", "--binary", "--top-module", "tb_verify_full", "-j", "4",
               "-Wno-INITIALDLY", "-Wno-WIDTHEXPAND", "-Wno-WIDTHTRUNC",
               "--Mdir", os.path.join(args.workdir, "obj_dir"),
               "-I" + os.path.join(ROOT, "rtl"), "-I" + os.path.join(ROOT, "rtl", "interfaces"),
               os.path.join(ROOT, "tb", "ame", "verify_full.sv")] + \
              [os.path.join(ROOT, "rtl", "ame", f) for f in
               ("ame_core.sv", "ame_ctrl.sv", "ame_array.sv", "ame_buf_rf.sv",
                "ame_requant.sv", "ame_rqtab.sv")] + \
              ["-o", exe]
        r = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
        if r.returncode != 0:
            print(r.stdout + r.stderr, file=sys.stderr)
            return 2
    man = json.load(open(os.path.join(args.workdir, "manifest.json")))
    duty_all = []

    def one(binfo):
        path = os.path.join(args.workdir, binfo["file"])
        dumpf = path.replace(".ops", ".gold")
        logf = path.replace(".ops", ".log")
        with open(logf, "w") as lf:
            subprocess.run([exe, "+ops=" + path, "+dump=" + dumpf,
                            "+case=rand", f"+gid=b{binfo['batch']:02d}"],
                           cwd=ROOT, stdout=lf, stderr=subprocess.STDOUT, timeout=3600)
        dpath = os.path.join(args.workdir, binfo["duty_file"])
        dlogf = dpath.replace(".ops", ".log")
        with open(dlogf, "w") as lf:
            subprocess.run([exe, "+ops=" + dpath, "+dump=" + dpath.replace(".ops", ".gold"),
                            "+case=duty", f"+gid=b{binfo['batch']:02d}", "+tight"],
                           cwd=ROOT, stdout=lf, stderr=subprocess.STDOUT, timeout=3600)
        snaps = []
        ok = False
        for ln in open(dlogf):
            m = re.match(r"PERF-SNAP .*tag=op#(\d+) mac=(\d+) busy=(\d+) idle=(\d+) duty=(\d+)/1000", ln)
            if m:
                snaps.append(dict(mac=int(m.group(2)), busy=int(m.group(3)),
                                  idle=int(m.group(4)), duty=int(m.group(5))))
            if "VERIFY RESULT: PASS" in ln:
                ok = True
        for ln in open(logf):
            if "VERIFY RESULT: PASS" in ln:
                pass
            elif "MISMATCH" in ln or "TIMEOUT" in ln:
                ok = False
        if "VERIFY RESULT: PASS" not in open(logf).read():
            ok = False
        mm = re.search(r"PERF case=\S+ \S+ ops=(\d+) checks=(\d+) dumped=(\d+) fail=(\d+)", open(logf).read())
        return binfo, ok, snaps, (mm.groups() if mm else None), logf

    fails = 0
    with fut.ThreadPoolExecutor(max_workers=args.jobs) as ex:
        for binfo, ok, snaps, mm, logf in ex.map(one, man["batches"]):
            duty = None
            wins = [(snaps[i]["mac"], snaps[i]["busy"]) for i in range(1, len(snaps), 2)]
            if wins:
                wd = [(m * 1000) // b if b else 0 for m, b in wins]
                mac = sum(m for m, _ in wins)
                busy = sum(b for _, b in wins)
                duty = min(wd)
                duty_all.append((binfo["batch"], mac, busy, duty))
            stat = "PASS" if ok else "FAIL"
            if not ok:
                fails += 1
            print((f"  batch_{binfo['batch']:02d}: {stat} ops={mm[0] if mm else '?'} "
                   f"checks={mm[1] if mm else '?'} fail={mm[3] if mm else '?'} "
                   f"duty_min={duty}/1000 windows={len(wins)}")
                  if duty is not None else
                  f"  batch_{binfo['batch']:02d}: {stat} (无 duty 快照)")
            if not ok:
                print(f"    log: {logf}")

    if duty_all:
        duty_min = min(d for _, _, _, d in duty_all)
        duty_avg = sum(d for _, _, _, d in duty_all) // len(duty_all)
        mac_sum = sum(m for _, m, _, _ in duty_all)
        busy_sum = sum(b for _, _, b, _ in duty_all)
        print(f"duty: min={duty_min}/1000 avg={duty_avg}/1000(mac={mac_sum} busy={busy_sum},"
              f"基线 888/1000,劣化阈值 868)")
        degraded = duty_min < 868
    else:
        print("duty: 无测量!")
        degraded = True
    print(f"===== vrf_rand run: {'PASS' if (fails == 0 and not degraded) else 'FAIL'} "
          f"({len(man['batches'])} 批,fail 批数 {fails}) =====")
    return 0 if (fails == 0 and not degraded) else 1


if __name__ == "__main__":
    raise SystemExit(main())
