#!/usr/bin/env python3
# -----------------------------------------------------------------------------
#
#
#
#   p4a4_bitblast_macro_conns.py <in.v> -o <out.v> [--order msb_first]
#       [--masters sky130_sram_1rw1r_128x256_8] [--check-only]
# -----------------------------------------------------------------------------
import argparse
import re
import sys

MACRO_PORTS = {
    "sky130_sram_1rw1r_128x256_8": {
        "addr0": 8, "addr1": 8, "wmask0": 16,
        "din0": 128, "dout0": 128, "dout1": 128,
    },
}

INST_RE = re.compile(r"^(\s*)(\S+)\s+(\\?\S+)\s*\(")
CONN_RE = re.compile(r"\.\s*([A-Za-z_][A-Za-z0-9_]*)\s*\(")


def find_close(text, start):
    """返回与 start 位置 '(' 配对的 ')' 下标"""
    depth = 0
    for i in range(start, len(text)):
        c = text[i]
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return i
    raise ValueError("unbalanced parens")


def split_top_commas(s):
    """按顶层逗号拆分(括号/转义名内的逗号不拆)"""
    parts, depth, cur = [], 0, []
    for c in s:
        if c in "([":
            depth += 1
        elif c in ")]":
            depth -= 1
        if c == "," and depth == 0:
            parts.append("".join(cur))
            cur = []
        else:
            cur.append(c)
    if cur:
        parts.append("".join(cur))
    return [p.strip() for p in parts if p.strip()]


def velem(elem):
    """连接元素 verbatim 规整:转义名保留尾随空格(转义 ID 以空白终结)"""
    e = elem.strip()
    if e.startswith("\\") and not e.endswith(" "):
        e += " "
    return e


def expand_instance(body, order, master, warnings):
    """把实例体内的拼接命名连接改写为逐位显式;返回新 body 文本"""
    ports = MACRO_PORTS.get(master, {})
    out, pos, changed = [], 0, False
    while pos < len(body):
        m = CONN_RE.search(body, pos)
        if not m:
            out.append(body[pos:])
            break
        expr_start = m.end()
        expr_end = find_close(body, expr_start - 1)
        expr = body[expr_start:expr_end]
        out.append(body[pos:m.start()])
        width = ports.get(m.group(1))
        if expr.lstrip().startswith("{"):
            elems = split_top_commas(expr.strip()[1:-1])
            if width is None:
                warnings.append(f"  WARN 端口 {m.group(1)} 不在宽度表,按元素数={len(elems)} 处理")
                width = len(elems)
            if len(elems) != width:
                raise ValueError(
                    f"端口 {m.group(1)} 拼接元素数 {len(elems)} != 位宽 {width}")
            conns = []
            for k, e in enumerate(elems):
                bit = (width - 1 - k) if order == "msb_first" else k
                conns.append(f".{m.group(1)}[{bit}]({velem(e)})")
            indent = re.match(r"[ \t]*", body[m.start():expr_start]).group(0)
            out.append((",\n" + indent).join(conns))
            changed = True
        else:
            out.append(body[m.start():expr_end + 1])
        pos = expr_end + 1
    return "".join(out), changed


def transform(text, masters, order, warnings):
    lines = text.split("\n")
    out, i, n = [], 0, len(lines)
    ninst = nchg = 0
    while i < n:
        line = lines[i]
        m = INST_RE.match(line)
        if m and m.group(2) in masters:
            acc = [line]
            depth = line.count("(") - line.count(")")
            start_line = i + 1
            while depth > 0:
                i += 1
                if i >= n:
                    raise ValueError(f"实例 {m.group(2)} 未闭合(行 {start_line})")
                acc.append(lines[i])
                depth += lines[i].count("(") - lines[i].count(")")
            joined = "\n".join(acc)
            p_open = joined.index("(")
            p_close = find_close(joined, p_open)
            body = joined[p_open + 1:p_close]
            new_body, changed = expand_instance(body, order, m.group(2), warnings)
            out.append(joined[:p_open + 1] + new_body + joined[p_close:])
            ninst += 1
            nchg += 1 if changed else 0
        else:
            out.append(line)
        i += 1
    return "\n".join(out), ninst, nchg


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("netlist")
    ap.add_argument("-o", "--out", help="输出文件(缺省 = 原位改写)")
    ap.add_argument("--order", choices=["msb_first", "lsb_first"], default="msb_first",
                    help="拼接元素→位 映射口径(msb_first=yosys 导入前,lsb_first=OpenROAD 导出后)")
    ap.add_argument("--masters", default=",".join(MACRO_PORTS),
                    help="处理的宏 master 逗号列表")
    ap.add_argument("--check-only", action="store_true",
                    help="只检测是否存在宏拼接连接(幂等守卫),不写文件")
    args = ap.parse_args()

    with open(args.netlist, "r", encoding="utf-8") as f:
        text = f.read()

    warnings = []
    new_text, ninst, nchg = transform(text, set(args.masters.split(",")),
                                      args.order, warnings)
    for w in warnings:
        print(w, file=sys.stderr)

    if args.check_only:
        print(f"{args.netlist}: 宏实例 {ninst} 个,含拼接连接 {nchg} 个")
        sys.exit(3 if nchg else 0)

    out_path = args.out or args.netlist
    if nchg == 0:
        print(f"{out_path}: 无需改写(已是逐位显式),共 {ninst} 个宏实例")
        if args.out:
            with open(out_path, "w", encoding="utf-8") as f:
                f.write(new_text)
        return
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(new_text)
    print(f"{out_path}: 改写 {ninst} 个宏实例中 {nchg} 个拼接连接 → 逐位显式 (order={args.order})")


if __name__ == "__main__":
    main()
