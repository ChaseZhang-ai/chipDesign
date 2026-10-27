#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""golden_reader.py — AME RTL 验证对接面：npz golden → $readmemh .mem / SV dump 比对。

读 models/golden/manifest.json 与各 case.npz（键名见 docs/GOLDEN_SPEC.md §6），
提供四个子命令：

  emit       生成 $readmemh 的 .mem 文件（可按 case/gemv 过滤，见 §7 格式）
  dump       从 npz 生成"金标 dump"文件（TB bring-up 用，格式同 compare 输入）
  compare    终判比对：读 SV TB $fdisplay dump 文件 vs npz，输出 PASS/FAIL + 首错误位置
  selfcheck  纯 python 整数独立重算全部 y_int32/y_q8 并与 npz 逐位比对
             （本文件自带第三份协议实现，不依赖生成器/复算器代码——GOLDEN_SPEC §9）

SV TB dump 约定（每行一个 token，`#`/`//` 注释与空行忽略）：

    GOLD <case> <gemv> <field> <index> <hex>

    <case>   case 名（unit_gemv / e2e_step_T8 / corner / rand20）
    <gemv>   gemv 编号，如 G06（也接受 06 / gemv06）
    <field>  y_q8（2 位 hex）| y_int32（8 位 hex）
    <index>  十进制通道号 n
    <hex>    大写/小写均可，二补码

  TB 侧示例：
      $fdisplay(fd, "GOLD %s %s y_q8 %0d %02x", CASE, GID, n, dut_y_q);
      $fdisplay(fd, "GOLD %s %s y_int32 %0d %08x", CASE, GID, n, dut_y_int32);

.mem 格式（GOLDEN_SPEC §7，全部大写 hex、无 @addr、允许 // 注释）：
  权重 ROM  <gemv>_w.mem            主镜像：tile16（N,K 均 16 整除时，否则 rowmajor），
                                    另发 <gemv>_w_rowmajor.mem 与 _w_tile16/_w_tile32（可整除时）；
                                    4×int8 小端打包 32-bit 字，每行 1 字 8 hex，
                                    首行注释 // layout=... path=... N= K= words=[ pad_bytes=]
  激活/输出 <gemv>_x.mem / _y_q.mem       每行 2 hex（int8 二补码）
  期望值    <gemv>_y_int32.mem            每行 8 hex（int32 二补码）
  bias      <gemv>_b_int32.mem            每行 8 hex
  寄存器    <gemv>_regs_m.mem / _regs_s.mem  8 / 2 hex（uint32/uint8，按通道 n 升序）

用法示例：
  python tb/ame/golden_reader.py emit --case unit_gemv --gemv G01
  python tb/ame/golden_reader.py emit                     # 全部 case
  python tb/ame/golden_reader.py dump --case e2e_step_T8 --out /tmp/gold.txt
  python tb/ame/golden_reader.py compare --dump tb_dump.txt
  python tb/ame/golden_reader.py selfcheck --case corner

退出码：emit/dump/selfcheck 失败或 compare 不通过 → 1。
"""
import argparse
import fnmatch
import json
import os
import sys

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DEFAULT_ROOT = os.path.join(ROOT, "models", "golden")
I32MIN, I32MAX = -(1 << 31), (1 << 31) - 1
FIELDS = {"y_q8": 2, "y_q": 2, "yq": 2, "y_int32": 8, "y32": 8}



def sat32(v):
    return I32MIN if v < I32MIN else (I32MAX if v > I32MAX else v)


def gemv_py(w_rows, x, bias):
    """纯 python GEMV：k 升序逐步 SAT32 + bias_last。"""
    out = []
    for ni, row in enumerate(w_rows):
        acc = 0
        for wv, xv in zip(row, x):
            acc = sat32(acc + wv * xv)
        out.append(sat32(acc + bias[ni]))
    return out


def requant_py(y, m, s):
    prod = (y * m) & ((1 << 64) - 1)
    if prod >> 63:
        prod -= 1 << 64
    return max(-128, min(127, (prod + (1 << (s - 1))) >> s))



def load_all(root, case=None, gemv=None):
    with open(os.path.join(root, "manifest.json")) as f:
        manifest = json.load(f)
    sel = {}
    for name, info in manifest["cases"].items():
        if case and not fnmatch.fnmatch(name, case):
            continue
        z = np.load(os.path.join(root, info["npz"]))
        entries = []
        for e in info["gemvs"]:
            if gemv and not gemv_match(e["id"], gemv):
                continue
            entries.append(e)
        if entries:
            sel[name] = {"z": z, "gemvs": entries, "info": info}
    return manifest, sel


def gemv_match(gid, pattern):
    g = gid.lower()
    p = pattern.lower().lstrip("g")
    if p.startswith("emv"):                      # "gemv06"
        p = p[3:]
    return g[1:] == p or g == p


def norm_gid(gid):
    return gid if gid.upper().startswith("G") else "G" + gid



def tile_linear(w_q8, t):
    n, k = w_q8.shape
    assert n % t == 0 and k % t == 0, f"tile{t} 需 {n}x{k} 被 {t} 整除"
    v = w_q8.reshape(n // t, t, k // t, t).transpose(0, 2, 1, 3)
    return v.reshape(-1).tolist()


def pack_words(stream):
    bs = list(stream)
    pad = (-len(bs)) % 4
    bs += [0] * pad
    words = [((bs[i] & 0xFF) | (bs[i + 1] & 0xFF) << 8 | (bs[i + 2] & 0xFF) << 16
              | (bs[i + 3] & 0xFF) << 24) for i in range(0, len(bs), 4)]
    return words, pad


def write_lines(path, lines, header=None):
    with open(path, "w") as f:
        if header:
            f.write(f"// {header}\n")
        f.write("\n".join(lines) + "\n")


def h8(v):
    return f"{int(v) & 0xFFFFFFFF:08X}"


def h2(v):
    return f"{int(v) & 0xFF:02X}"


def emit_weight(z, e, outdir, primary, extra_layouts, index):
    w = z[e["keys"]["w"]]
    n, k = w.shape
    g = e["npz_prefix"].split(".")[-1]           # gemv01
    path_name = e.get("path") or f"{e['kind']}:{e['id']}"
    layouts = {}
    if "rowmajor" in extra_layouts or primary == "rowmajor":
        layouts["rowmajor"] = w.reshape(-1).tolist()
    for t, tag in ((16, "tile16"), (32, "tile32")):
        if tag in extra_layouts and n % t == 0 and k % t == 0:
            layouts[tag] = tile_linear(w, t)
    if primary == "auto":
        primary_layout = "tile16" if "tile16" in layouts else "rowmajor"
    else:
        primary_layout = primary
        assert primary_layout in layouts, f"主布局 {primary} 不可用（整除性/未请求）"
    for lay, stream in layouts.items():
        words, pad = pack_words(stream)
        fname = f"{g}_w.mem" if lay == primary_layout else f"{g}_w_{lay}.mem"
        write_lines(os.path.join(outdir, fname), [h8(v) for v in words],
                    header=f"layout={lay} path={path_name} N={n} K={k} words={len(words)}"
                           + (f" pad_bytes={pad}" if pad else ""))
        index.append({"file": fname, "kind": "weight", "layout": lay,
                      "words": len(words), "pad_bytes": pad})
    return layouts


def emit_case(name, entry_set, outdir, primary, extra_layouts):
    os.makedirs(outdir, exist_ok=True)
    z = entry_set["z"]
    index = []
    for e in entry_set["gemvs"]:
        g = e["npz_prefix"].split(".")[-1]
        pre = e["npz_prefix"]
        emit_weight(z, e, outdir, primary, extra_layouts, index)
        for key, fname, fmt in [
                (e["keys"]["xin"], f"{g}_x.mem", h2),
                (e["keys"]["y_q8"], f"{g}_y_q.mem", h2),
                (e["keys"]["y_int32"], f"{g}_y_int32.mem", h8),
                (e["keys"]["b"], f"{g}_b_int32.mem", h8),
                (e["keys"]["rq_m"], f"{g}_regs_m.mem", h8),
                (e["keys"]["rq_s"], f"{g}_regs_s.mem", h2)]:
            arr = z[key].reshape(-1)
            write_lines(os.path.join(outdir, fname), [fmt(v) for v in arr],
                        header=f"case={name} {key} len={len(arr)}")
            index.append({"file": fname, "kind": key, "lines": len(arr)})
        print(f"  [{name}] {g}: N={e['N']} K={e['K']} → {g}_{{w,x,b_int32,y_int32,y_q,regs_m,regs_s}}.mem")
    with open(os.path.join(outdir, "mem_index.json"), "w") as f:
        json.dump({"case": name, "outdir": os.path.relpath(outdir, ROOT),
                   "files": index}, f, indent=2)
    return len(index)


# ---------------------------------------------------------------- dump / compare

def dump_gold(root, sel, out_path):
    lines = ["# AME golden dump v1 — GOLD <case> <gemv> <field> <index> <hex>"]
    for name, entry_set in sel.items():
        z = entry_set["z"]
        for e in entry_set["gemvs"]:
            gid = e["id"]
            yq = z[e["keys"]["y_q8"]]
            y32 = z[e["keys"]["y_int32"]]
            for n in range(len(yq)):
                lines.append(f"GOLD {name} {gid} y_q8 {n} {h2(yq[n])}")
            for n in range(len(y32)):
                lines.append(f"GOLD {name} {gid} y_int32 {n} {h8(y32[n])}")
    with open(out_path, "w") as f:
        f.write("\n".join(lines) + "\n")
    print(f"dump 写出 {len(lines) - 1} 行 → {out_path}")


def parse_dump(path):
    got = {}          # (case, gid_norm, field) -> {index: value_int}
    order = []
    unknown = []
    with open(path) as f:
        for ln, raw in enumerate(f, 1):
            s = raw.strip()
            if not s or s.startswith("#") or s.startswith("//"):
                continue
            parts = s.split()
            if parts[0] != "GOLD" or len(parts) != 6:
                unknown.append((ln, s))
                continue
            _, case, gid, field, idx, hexv = parts
            if field not in FIELDS:
                unknown.append((ln, s))
                continue
            gid_n = norm_gid(gid)
            key = (case, gid_n, "y_q8" if field in ("y_q8", "y_q", "yq") else "y_int32")
            if key not in got:
                got[key] = {}
                order.append(key)
            got[key][int(idx)] = int(hexv, 16)
    return got, order, unknown


def to_signed(v, bits):
    return v - (1 << bits) if v >= (1 << (bits - 1)) else v


def compare(root, sel, dump_path, only_case=None):
    got, order, unknown = parse_dump(dump_path)
    n_ok = n_bad = n_missing = 0
    first_err = None
    checked_keys = set()
    for name, entry_set in sel.items():
        if only_case and not fnmatch.fnmatch(name, only_case):
            continue
        z = entry_set["z"]
        for e in entry_set["gemvs"]:
            gid = e["id"]
            for field, arr_key, bits in (("y_q8", e["keys"]["y_q8"], 8),
                                         ("y_int32", e["keys"]["y_int32"], 32)):
                key = (name, gid, field)
                checked_keys.add(key)
                exp = z[arr_key]
                if field == "y_int32":
                    yfk = arr_key.replace(".y.int32", ".yfirst.int32")
                    if yfk in z:
                        exp = z[yfk]
                act_map = got.get(key)
                if act_map is None:
                    n_missing += len(exp)
                    continue
                for n in range(len(exp)):
                    if n not in act_map:
                        n_missing += 1
                        continue
                    ev = int(exp[n])
                    av = to_signed(act_map[n], bits)
                    if av == ev:
                        n_ok += 1
                    else:
                        n_bad += 1
                        if first_err is None:
                            first_err = (name, gid, field, n, ev, av)
    for key, m in got.items():
        if key not in checked_keys:
            for idx in m:
                n_bad += 1
                if first_err is None:
                    first_err = (key[0], key[1], key[2], idx, None, to_signed(m[idx], 32))
    for ln, s in unknown:
        print(f"  WARN 无法解析的 dump 行 {ln}: {s!r}")

    if first_err:
        name, gid, field, n, ev, av = first_err
        width = 2 if field == "y_q8" else 8
        mask = (1 << (width * 4)) - 1
        key = f"{name}/{gid}/{field}" if ev is not None else f"{name}/{gid}/{field}(多余条目)"
        print(f"MISMATCH {key} {n} exp={'<none>' if ev is None else format(ev & mask, f'0{width}X')}"
              f" act={format(av & mask, f'0{width}X')}")
    print(f"compare: OK={n_ok} MISMATCH={n_bad} MISSING(金标有而 dump 无)={n_missing}")
    if n_bad == 0 and n_missing == 0 and unknown == []:
        print(f"COMPARE RESULT: PASS ({n_ok} 点逐位一致)")
        return 0
    print("COMPARE RESULT: FAIL")
    return 1



def selfcheck(root, sel):
    n_ok = n_bad = 0
    for name, entry_set in sel.items():
        z = entry_set["z"]
        for e in entry_set["gemvs"]:
            gid = e["id"]
            w = z[e["keys"]["w"]].astype(int).tolist()
            x = z[e["keys"]["xin"]].astype(int).tolist()
            b = z[e["keys"]["b"]].astype(int).tolist()
            m = z[e["keys"]["rq_m"]].astype(int).tolist()
            s = z[e["keys"]["rq_s"]].astype(int).tolist()
            y32_exp = z[e["keys"]["y_int32"]].astype(int).tolist()
            yq_exp = z[e["keys"]["y_q8"]].astype(int).tolist()
            y32 = gemv_py(w, x, b)
            yq = [requant_py(y, mm, ss) for y, mm, ss in zip(y32, m, s)]
            if y32 == y32_exp and yq == yq_exp:
                n_ok += 1
            else:
                n_bad += 1
                for n in range(len(y32)):
                    if y32[n] != y32_exp[n]:
                        print(f"  FAIL {name}/{gid} ch{n}: y32 exp={y32_exp[n]:08X} act={y32[n]:08X}")
                        break
                for n in range(len(yq)):
                    if yq[n] != yq_exp[n]:
                        print(f"  FAIL {name}/{gid} ch{n}: yq exp={yq_exp[n]:02X} act={yq[n]:02X}")
                        break
        print(f"  [{name}] 纯 python 重算: {sum(1 for _ in entry_set['gemvs'])} 条 GEMV")
    print(f"SELFCHECK RESULT: {'PASS' if n_bad == 0 else 'FAIL'} ({n_ok} OK / {n_bad} FAIL, 纯 python 整数实现)")
    return 0 if n_bad == 0 else 1


# ---------------------------------------------------------------- main

def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    sub = ap.add_subparsers(dest="cmd", required=True)

    def common(p):
        p.add_argument("--root", default=DEFAULT_ROOT)
        p.add_argument("--case", default=None, help="case 名（支持 fnmatch）")
        p.add_argument("--gemv", default=None, help="gemv 编号 G06 / 06 / gemv06（支持 fnmatch）")

    p = sub.add_parser("emit", help="npz → $readmemh .mem")
    common(p)
    p.add_argument("--outdir", default=None, help="默认 models/golden/<case>/")
    p.add_argument("--primary", default="auto", choices=["auto", "tile16", "tile32", "rowmajor"])
    p.add_argument("--layouts", default="rowmajor,tile16,tile32",
                   help="权重镜像布局集合（受整除性约束）")

    p = sub.add_parser("dump", help="生成金标 dump 文件")
    common(p)
    p.add_argument("--out", required=True)

    p = sub.add_parser("compare", help="SV dump vs npz 终判比对")
    common(p)
    p.add_argument("--dump", required=True)

    p = sub.add_parser("selfcheck", help="纯 python 独立重算比对")
    common(p)

    args = ap.parse_args()
    manifest, sel = load_all(args.root, args.case, args.gemv)
    if not sel:
        print("没有匹配的 case/gemv", file=sys.stderr)
        return 1
    if args.cmd == "emit":
        layouts = [x.strip() for x in args.layouts.split(",") if x.strip()]
        total = 0
        for name, es in sel.items():
            outdir = args.outdir or os.path.join(args.root, name)
            total += emit_case(name, es, outdir, args.primary, layouts)
        print(f"emit 完成：{total} 个文件（索引 mem_index.json）")
        return 0
    if args.cmd == "dump":
        dump_gold(args.root, sel, args.out)
        return 0
    if args.cmd == "compare":
        return compare(args.root, sel, args.dump, args.case)
    if args.cmd == "selfcheck":
        return selfcheck(args.root, sel)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
