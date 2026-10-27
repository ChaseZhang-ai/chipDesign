#!/usr/bin/env python3
"""AME-Chip decode 工作负载画像: 从 ONNX(数值源) + TPU-MLIR(交叉核对) 统计
每个算子的类型/形状/MAC 数/访存字节, 汇总单步 decode 总计算量、算术强度、
roofline 吞吐与带宽需求、KV-cache 访存模式。

用法(在 venv 下):
  python scripts/wl_profile.py                       # 默认画像 decode 图 + roofline
  python scripts/wl_profile.py --both                # 额外画像 prefill 图做对比
输出 markdown 到 stdout, docs/WORKLOAD.md 中全部数字由本脚本复算。

成本模型(与 docs/WORKLOAD.md §2 一致, 改这里即改文档口径):
  MAC 计数: Gemm/MatMul -> prod(batch)*M*K*N
  ALU 计数(非矩阵算子, 由标量 RISC/elementwise 单元执行):
    LayerNormalization=10/elem, Softmax=6/elem, Erf=10/elem,
    Add/Mul/Sub/Div=1/elem, 数据搬运类(Reshape/Transpose/Slice/...) = 0
  字节: fp32=4B/elem; INT8 投影 = 权重(dim>=2 浮点 initializer)1B/elem,
        浮点激活 1B/elem; 一维参数(bias/gamma/beta)按 INT32 累加侧 4B/elem 不变。
Roofline 模型:
  峰值 MAC/s = N^2 * f (N x N INT8 MAC 阵列, GEMV 按 K-切分映射可近满利用);
  权重片外流式时每 MAC 需 1 B 权重 -> 带宽需求 = N^2 * f B/s;
  片上权重 SRAM 命中时只受算力约束。
"""
import argparse
import os
from collections import Counter, defaultdict

import onnx
from onnx import shape_inference, numpy_helper

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODELS = os.path.join(ROOT, "models")

FREQ_MHZ = 120
ARRAYS = [16, 32]
AXI_BITS = [64, 128, 256, 512, 1024, 2048]
CTX_FULL = 128
CTX_SWEEP = [16, 64, 127]
DTYPE_SIZE = {1: 4, 2: 1, 3: 1, 4: 2, 5: 2, 6: 4, 7: 8, 9: 1, 10: 2, 11: 8, 12: 4}

OP2TOP = {
    "Gemm": "MatMul", "MatMul": "MatMul", "LayerNormalization": "LayerNorm",
    "Softmax": "Softmax", "Erf": "GELU", "Add": "Add", "Mul": "Mul*/Add*",
    "Div": "MulConst", "Transpose": "Permute", "Reshape": "Reshape",
    "Split": "Slice", "Concat": "Concat", "Gather": "Slice/Weight",
    "Squeeze": "Squeeze", "Unsqueeze": "Unsqueeze",
}

ALU_PER_ELEM = {"LayerNormalization": 10, "Softmax": 6, "Erf": 10,
                "Add": 1, "Mul": 1, "Div": 1, "Sub": 1}

KV_PAT = ("k_cache", "v_cache", "k_new", "v_new")

def load_shapes(model):
    shapes, dtypes = {}, {}

    def add(vi):
        if vi.type.tensor_type.HasField("shape") and vi.type.tensor_type.shape.dim:
            shapes[vi.name] = [d.dim_value for d in vi.type.tensor_type.shape.dim]
        dtypes[vi.name] = vi.type.tensor_type.elem_type

    for vi in list(model.graph.value_info) + list(model.graph.input) \
            + list(model.graph.output):
        add(vi)
    return shapes, dtypes


def numel(shape):
    n = 1
    for d in shape:
        n *= d
    return n


def profile_model(path):
    model = onnx.load(path)
    model = shape_inference.infer_shapes(model)
    shapes, dtypes = load_shapes(model)
    inits = {i.name: i for i in model.graph.initializer}
    prod = {o: n for n in model.graph.node for o in n.output}
    const_outs = {o for n in model.graph.node if n.op_type == "Constant"
                  for o in n.output}

    def resolve(name):
        for _ in range(16):
            p = prod.get(name)
            if p is None or p.op_type != "Identity":
                return name
            name = p.input[0]
        return name

    def is_const(name):
        r = resolve(name)
        return r in inits or r in const_outs

    def tensor_shape(name):
        r = resolve(name)
        if r in inits:
            return list(numpy_helper.to_array(inits[r]).shape)
        if name in shapes and shapes[name]:
            return shapes[name]
        return None

    unique_roots = {}

    rows = []
    for idx, n in enumerate(model.graph.node):
        if n.op_type in ("Constant", "Identity"):
            continue
        ins = [(i, tensor_shape(i), dtypes.get(i, 1),
                is_const(i)) for i in n.input if i]
        outs = [(o, shapes.get(o), dtypes.get(o, 1)) for o in n.output if o]

        macs = alu = 0
        wbytes_f32 = wbytes_q = 0.0
        for name, shp, dt, is_init in ins:
            if not is_init or not shp:
                continue
            nb = numel(shp) * DTYPE_SIZE.get(dt, 4)
            qb = numel(shp) * 1 if (dt == 1 and len(shp) >= 2) else nb
            wbytes_f32 += nb
            wbytes_q += qb
            r = resolve(name)
            if r not in unique_roots:
                unique_roots[r] = (nb, qb)
        if n.op_type in ("Gemm", "MatMul"):
            a = shapes.get(n.input[0])
            bi = inits.get(n.input[1])
            b = list(numpy_helper.to_array(bi).shape) if bi is not None \
                else shapes.get(n.input[1])
            if n.op_type == "Gemm":
                transb = {a.name: a.i for a in n.attribute}.get("transB", 0)
                m, k = a[-2], a[-1]
                nn_ = b[-2] if transb else b[-1]
            else:
                m, k, nn_ = a[-2], a[-1], b[-1]
            batch = numel(a[:-2]) if len(a) > 2 else 1
            macs = batch * m * k * nn_
        else:
            o = outs[0]
            elems = numel(o[1]) if o[1] else 0
            alu = ALU_PER_ELEM.get(n.op_type, 0) * elems

        act_in_f = sum(numel(s) * DTYPE_SIZE.get(d, 4) for _, s, d, init in ins
                       if not init and s)
        act_out_f = sum(numel(s) * DTYPE_SIZE.get(d, 4) for _, s, d in outs if s)
        act_in_q = sum(numel(s) * (1 if d == 1 else DTYPE_SIZE.get(d, 4))
                       for _, s, d, init in ins if not init and s)
        act_out_q = sum(numel(s) * (1 if d == 1 else DTYPE_SIZE.get(d, 4))
                        for _, s, d in outs if s)
        kv_io = sum(numel(s) * DTYPE_SIZE.get(d, 4)
                    for nm, s, d, init in ins if not init and s and any(
                        p in nm for p in KV_PAT))
        kv_io += sum(numel(s) * DTYPE_SIZE.get(d, 4)
                     for nm, s, d in outs if s and any(p in nm for p in KV_PAT))
        rows.append(dict(idx=idx, op=n.op_type, top=OP2TOP.get(n.op_type, "-"),
                         ins=[(nm, s) for nm, s, _, _ in ins],
                         outs=[(nm, s) for nm, s, _ in outs],
                         macs=macs, alu=alu,
                         wf=wbytes_f32, wq=wbytes_q,
                         af=act_in_f + act_out_f, aq=act_in_q + act_out_q,
                         kv=kv_io))
    u_wf = sum(v[0] for v in unique_roots.values())
    u_wq = sum(v[1] for v in unique_roots.values())
    return rows, (u_wf, u_wq)


def fmt_shape(s):
    return "x".join(map(str, s)) if s else "?"


def md_type_summary(rows):
    agg = defaultdict(lambda: dict(cnt=0, macs=0, alu=0, wf=0, wq=0, af=0, aq=0))
    for r in rows:
        a = agg[r["op"]]
        a["cnt"] += 1
        for k in ("macs", "alu", "wf", "wq", "af", "aq"):
            a[k] += r[k]
    order = sorted(agg.items(), key=lambda kv: -kv[1]["macs"])
    lines = ["| op(top.*) | 实例数 | MACs | ALU ops | 权重B INT8 | 激活B INT8 |",
             "|---|---|---|---|---|---|"]
    for op, a in order:
        lines.append(f"| {op}({OP2TOP.get(op, '-')}) | {a['cnt']} | {a['macs']:,} | "
                     f"{a['alu']:,} | {a['wq']:,.0f} | {a['aq']:,.0f} |")
    return lines


def md_op_table(rows, title):
    lines = [f"### {title}", "",
             "| # | ONNX op | tpu-mlir top.* | 输入形状 | 输出形状 | MACs | ALU ops | 权重B(fp32/INT8) | 激活B(fp32/INT8) | KV B |",
             "|---|---------|----------------|----------|----------|------|---------|------------------|------------------|------|"]
    for i, r in enumerate(rows):
        lines.append(
            f"| {i} | {r['op']} | {r['top']} | "
            f"{'<br>'.join(fmt_shape(s) for _, s in r['ins'])} | "
            f"{'<br>'.join(fmt_shape(s) for _, s in r['outs'])} | "
            f"{r['macs']:,} | {r['alu']:,} | {r['wf']:,.0f} / {r['wq']:,.0f} | "
            f"{r['af']:,.0f} / {r['aq']:,.0f} | {r['kv']:,} |")
    t_m = sum(r["macs"] for r in rows)
    t_a = sum(r["alu"] for r in rows)
    tw_f, tw_q = sum(r["wf"] for r in rows), sum(r["wq"] for r in rows)
    ta_f, ta_q = sum(r["af"] for r in rows), sum(r["aq"] for r in rows)
    tkv = sum(r["kv"] for r in rows)
    lines.append(f"| **合计** | | | | | **{t_m:,}** | **{t_a:,}** | "
                 f"**{tw_f:,.0f} / {tw_q:,.0f}** | **{ta_f:,.0f} / {ta_q:,.0f}** | **{tkv:,}** |")
    return lines, (t_m, t_a, tw_f, tw_q, ta_f, ta_q, tkv)


def md_gemv_list(rows):
    """完整 GEMV 清单: 每个 M*K x K*1 实例(按头展开)。"""
    lines = ["| 实例 | 权重/操作数 | M | K | N | MACs | 说明 |",
             "|------|------------|---|---|---|------|------|"]
    n = 0
    for r in rows:
        if r["op"] == "Gemm":
            a = dict(r["ins"]).get(r["ins"][0][0])
            a_shape = a
            out = r["outs"][0][1]
            m, k = a_shape[0], a_shape[1]
            nn_ = out[1]
            wname = [nm for nm, _ in r["ins"] if "weight" in nm][0]
            n += 1
            lines.append(f"| G{n} | `{wname}` | {m} | {k} | {nn_} | "
                         f"{r['macs']:,} | M=1 纯 GEMV, K={k} |")
        elif r["op"] == "MatMul":
            (an, as_), (bn, bs) = r["ins"][0], r["ins"][1]
            b, m, k = as_[-3], as_[-2], as_[-1]
            nn_ = bs[-1]
            heads = bs[-3]
            for h in range(heads):
                n += 1
                lines.append(f"| G{n} | `{bn}`[h={h}] | {m} | {k} | {nn_} | "
                             f"{m * k * nn_:,} | 按头 GEMV(batch 维展开), K={k} |")
    return lines, n


def md_top_compare(onnx_rows, mlir_path, origin_path):
    lines = ["### TPU-MLIR 视角交叉核对", "",
             "| top.* op | 优化后 MLIR | ONNX 侧对应(计数) |", "|---|---|---|"]
    top_cnt = Counter()

    def hist(p):
        c = Counter()
        if not os.path.exists(p):
            return c
        import re
        for mo in re.finditer(r'"top\.([A-Za-z0-9_]+)"', open(p).read()):
            c[mo.group(1)] += 1
        return c

    top_cnt = hist(mlir_path)
    origin_cnt = hist(origin_path)
    onnx_cnt = Counter(r["top"] for r in onnx_rows)
    for op, c in sorted(top_cnt.items()):
        if op in ("Weight", "Input", "None", "Output"):
            continue
        lines.append(f"| top.{op} | {c} | {onnx_cnt.get(op, '-')} |")
    mm = top_cnt.get("MatMul", 0)
    onx_mm = sum(r["macs"] > 0 for r in onnx_rows)
    check = "OK" if mm == onx_mm else "MISMATCH"
    lines.append(f"| **矩阵算子核对** | top.MatMul={mm} | ONNX Gemm+MatMul={onx_mm} → **{check}** |")
    lines.append("")
    lines.append(f"_origin.mlir(导入视图)直方图: {dict(origin_cnt)}_")
    return lines, mm == onx_mm


def alu_analysis(t_alu, t_macs):
    """elementwise/激活算子的 ALU 负载: 若全压标量 RISC, 是否反超阵列。"""
    f = FREQ_MHZ * 1e6
    cyc16 = t_macs / 256
    L = ["### Elementwise/激活路径 ALU 负载(决定标量 RISC 是否成为瓶颈)", "",
         "| 执行单元 | ALU 周期/步 | vs 16x16 阵列周期(7,680) | 串行总周期 | tok/s(串行) |",
         "|---|---|---|---|---|"]
    for lanes in (1, 4, 16):
        cyc = t_alu / lanes
        tot = cyc + cyc16
        L.append(f"| 标量 RISC x{lanes} lane | {cyc:,.0f} | {cyc / cyc16:.1f}x | "
                 f"{tot:,.0f} | {f / tot:,.0f} |")
    L += ["", "- 纯标量(1 lane)时 elementwise 周期是 MAC 阵列的数倍, 成为系统瓶颈;",
          "- LN/Softmax/GELU 均为 256~1024 元素的规整向量, 4/16 lane SIMD 或查表 GELU "
          "即可把 elementwise 开销压到与阵列同量级以下, 配合流水重叠。",
          ""]
    return L


def roofline(t_macs, t_wq, ctx_vals):
    f = FREQ_MHZ * 1e6
    L = []
    L.append("### Roofline 吞吐/带宽估算(INT8, GEMV 按 K-切分映射近满利用)")
    L.append("")
    L.append("| 阵列 | 峰值 GMAC/s | decode 周期/步(片上权重) | 步时延 us | tok/s(算力上限) |"
             " 流式带宽需求 GB/s |")
    L.append("|---|---|---|---|---|---|")
    res = {}
    for n in ARRAYS:
        peak = n * n * f
        cyc = t_macs / (n * n)
        lat = cyc / f * 1e6
        tok = f / cyc
        bw = n * n * f / 1e9
        res[n] = (peak, cyc, lat, tok, bw)
        L.append(f"| {n}x{n} | {peak / 1e9:.2f} | {cyc:,.0f} | {lat:.1f} | "
                 f"{tok:,.0f} | {bw:.2f} |")
    L.append("")
    L.append("### 权重片外流式时的 AXI 瓶颈(每步权重 INT8 流量 "
             f"{t_wq / 2**20:.2f} MiB, 每权重恰用一次)")
    L.append("")
    L.append("| AXI 位宽 @120MHz | 带宽 GB/s | 可支撑 tok/s(带宽上限) |")
    L.append("|---|---|---|")
    for w in AXI_BITS:
        bw = w / 8 * f / 1e9
        tok = bw * 1e9 / t_wq
        L.append(f"| {w}-bit | {bw:.2f} | {tok:,.0f} |")
    L.append("")
    L.append("### 有效上下文 T 扫描(注意力项与 KV 流量随 T 线性, 线性层不变)")
    L.append("")
    L.append("| T | 总 MACs | 16x16 周期 | 16x16 tok/s | KV 读 B/步 | KV 写 B/步 |")
    L.append("|---|---|---|---|---|---|")
    mac_lin = t_macs - CTX_FULL * 1024
    for T in ctx_vals + [CTX_FULL]:
        tm = mac_lin + 1024 * T
        kvr = 1024 * T
        kvw = 1024
        cyc16 = tm / 256
        tok16 = f / cyc16
        L.append(f"| {T} | {tm:,} | {cyc16:,.0f} | {tok16:,.0f} | {kvr:,} | {kvw:,} |")
    return L, res


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--decode", default=os.path.join(MODELS, "minigpt_decode.onnx"))
    ap.add_argument("--prefill", default=os.path.join(MODELS, "minigpt_prefill.onnx"))
    ap.add_argument("--both", action="store_true")
    args = ap.parse_args()

    out = []
    out.append(f"_由 scripts/wl_profile.py 自动生成; 模型: {os.path.basename(args.decode)}, "
               f"频率 {FREQ_MHZ} MHz, 阵列 {ARRAYS}, 成本模型见脚本头部注释_")
    out.append("")

    rows, (u_wf, u_wq) = profile_model(args.decode)
    out += md_type_summary(rows)
    out += ["", f"_(decode 图按算子类型汇总; top.* 为 tpu-mlir 优化后 MLIR 视角)_", ""]
    tbl, tot = md_op_table(rows, "decode 图逐算子画像(静态图 ctx=128, fp32 计)")
    out += tbl
    t_m, t_a, tw_f, tw_q, ta_f, ta_q, tkv = tot
    out += ["", f"- 单步 decode 总计: **{t_m:,} MACs** + {t_a:,} ALU ops; "
            f"权重 {tw_f:,.0f} B (fp32) → **{tw_q:,.0f} B (INT8, {tw_q / 2**20:.2f} MiB)**; "
            f"激活 {ta_f:,.0f} B (fp32) → {ta_q:,.0f} B (INT8); "
            f"其中 KV 读写 {tkv:,} B/步(满 ctx=128)。",
            f"- 算术强度: fp32 {t_m / (tw_f + ta_f):.2f} MAC/B; "
            f"INT8 投影 **{t_m / (tw_q + ta_q):.2f} MAC/B**(权重流式时趋近 1 B/MAC)。",
            ""]

    gl, ngemv = md_gemv_list(rows)
    out += ["### decode GEMV 形状清单(完整, K 维全列)", ""] + gl
    out += ["", f"共 **{ngemv} 个 GEMV 实例**(Linear 9 个 + 注意力按头展开 {ngemv - 9} 个)。",
            ""]

    mlir_path = args.decode.replace(".onnx", ".mlir")
    origin_path = args.decode.replace(".onnx", "_origin.mlir")
    cmp_lines, ok = md_top_compare(rows, mlir_path, origin_path)
    out += cmp_lines
    out += ["", f"MLIR 交叉核对: {'PASSED' if ok else 'FAILED'}", ""]

    rl, res = roofline(t_m, tw_q, CTX_SWEEP)
    out += rl
    out += alu_analysis(t_a, t_m)

    kv_max = 2 * 2 * 4 * CTX_FULL * 64  # L,H,ctx,hd x (k,v) x 1B
    out += ["", "### 片上 SRAM 需求(INT8)", "",
            f"- 权重+一维参数(唯一存储, 共享常量去重): {u_wq:,.0f} B = {u_wq / 2**20:.2f} MiB"
            f"(每步读取流量 {tw_q:,.0f} B)",
            f"- KV cache 满上下文(2 层 x 4 头 x 128 x 64 x k/v): {kv_max:,} B = {kv_max / 2**10:.0f} KiB",
            f"- 激活/暂存: < 8 KiB; **合计 < {u_wq / 2**20 + kv_max / 2**20 + 0.01:.2f} MiB**", ""]

    if args.both:
        prows, _ = profile_model(args.prefill)
        ptbl, ptot = md_op_table(prows, "prefill 图逐算子画像(T=16, fp32 计)")
        out += ["", "---", ""] + ptbl
        pm, pa, pwf, pwq, paf, paq, _ = ptot
        out += ["", f"- prefill(T=16) 总计: **{pm:,} MACs**, 权重 INT8 {pwq:,.0f} B, "
                f"算术强度 {pm / (pwq + paq):.2f} MAC/B —— 比 decode 高一个数量级, "
                f"自然映射为 GEMM。",
                f"- prefill 16x16 阵列周期 = {pm / 256:,.0f}, "
                f"时延 = {pm / 256 / (FREQ_MHZ * 1e6) * 1e6:,.0f} us/整段。",
                ]

    print("\n".join(out))


if __name__ == "__main__":
    main()
