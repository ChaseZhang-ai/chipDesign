#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""cpu_area_synth.py — ame_cpu 的 yosys 面积粗估(P2A)

yosys 0.70 的 read_verilog -sv 不支持模块内 package import,也解析不了
amechip_pkg.sv 的多行 return 表达式。本脚本生成"综合专用"的临时扁平副本
(包常量展开为文件级 localparam、去掉 import、折叠/剔除未用函数),
**不改动任何源文件**,然后调用 yosys synth -top ame_cpu; stat 输出
触发器/门数量级。正式综合由 P4A 用可综合子集处理(见 reports/issues/P2A.md)。

用法: python3 scripts/cpu_area_synth.py [-o report.txt]
"""

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

YOSYS_CANDIDATES = [
    os.path.expanduser("~/tools/openroad-flow-scripts/tools/install/yosys/bin/yosys"),
    shutil.which("yosys") or "",
]
RTL_FILES = [
    "rtl/amechip_pkg.sv",
    "rtl/cpu/amecpu_pkg.sv",
    "rtl/cpu/cpu_regfile.sv",
    "rtl/cpu/cpu_alu.sv",
    "rtl/cpu/cpu_muldiv.sv",
    "rtl/cpu/cpu_csr.sv",
    "rtl/cpu/cpu_axi_bridge.sv",
    "rtl/cpu/ame_cpu.sv",
]


def flatten_packages(text):
    """包定义 → 文件级 localparam/type;`pkg::` 限定名去掉;import 去掉。"""
    m = re.search(r"package\s+\w+;(.*?)endpackage", text, flags=re.S)
    if m is None:
        text = re.sub(r"^\s*import\s+\w+_pkg::\*;\s*$", "", text, flags=re.M)
        return text.replace("amechip_pkg::", "").replace("amecpu_pkg::", "")
    body = m.group(1)
    body = re.sub(r"^\s*localparam\s+int\s+unsigned\s+", "localparam int unsigned ", body, flags=re.M)
    flat = "// ---- 由 cpu_area_synth.py 从 package 展开(仅综合评估用) ----\n" + body
    text = re.sub(r"\s*package\s+\w+;.*?endpackage", "\n" + flat + "\n", text, flags=re.S)
    text = re.sub(r"^\s*import\s+\w+_pkg::\*;\s*$", "", text, flags=re.M)
    text = text.replace("amechip_pkg::", "").replace("amecpu_pkg::", "")
    return text


def fold_returns(text):
    """多行 return 折叠为单行;yosys 需 begin/end 与函数名赋值风格。"""
    lines = text.split("\n")
    out, i = [], 0
    while i < len(lines):
        ln = lines[i]
        if ln.strip().startswith("return ("):
            buf = [ln.strip()]
            while not buf[-1].endswith(";"):
                i += 1
                buf.append(lines[i].strip())
            out.append("    " + " ".join(buf))
        else:
            out.append(ln)
        i += 1
    return "\n".join(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-o", "--out", default=None)
    args = ap.parse_args()

    yosys = next((y for y in YOSYS_CANDIDATES if y and os.path.exists(y)), None)
    if not yosys:
        print("cpu_area_synth: yosys not found", file=sys.stderr)
        return 1

    tmp = tempfile.mkdtemp(prefix="amecpu_synth_")
    for f in RTL_FILES:
        src = os.path.join(ROOT, f)
        dst = os.path.join(tmp, os.path.basename(f))
        text = open(src, encoding="utf-8").read()
        text = flatten_packages(text)
        text = fold_returns(text)
        open(dst, "w", encoding="utf-8").write(text)

    pkg = os.path.join(tmp, "amechip_pkg.sv")
    t = open(pkg, encoding="utf-8").read()
    t = re.sub(r"  function automatic logic \[31:0\] kv_off \(.*?  endfunction\n", "", t, flags=re.S)
    t = re.sub(r"  function automatic logic \[31:0\] w_layer_off \(.*?  endfunction\n", "", t, flags=re.S)
    open(pkg, "w", encoding="utf-8").write(t)

    files = " ".join(os.path.join(tmp, os.path.basename(f)) for f in RTL_FILES)
    cmd = [yosys, "-p",
           f"read_verilog -sv {files}; hierarchy -top ame_cpu; synth -top ame_cpu; stat"]
    r = subprocess.run(cmd, capture_output=True, text=True)
    sys.stdout.write(r.stdout[-6000:])
    if r.returncode:
        sys.stderr.write(r.stderr[-2000:])
        return 1
    if args.out:
        open(args.out, "w", encoding="utf-8").write(r.stdout)
        print(f"cpu_area_synth: report -> {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
