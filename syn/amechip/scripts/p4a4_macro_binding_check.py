#!/usr/bin/env python3
# -----------------------------------------------------------------------------
#
#
#
#   p4a4_macro_binding_check.py --yosys results/.../1_2_yosys_yosys_pristine.v \
#       --odb results/.../1_synth.odb --report reports/P4A4_binding_synth.rpt
#   p4a4_macro_binding_check.py --yosys ...pristine.v --final-v .../6_final.v \
#       --cdl .../6_final.cdl --masters-cdl pnr/amechip/sky130hd_ame_masters.cdl \
#       --report reports/P4A4_binding_final.rpt
#
# -----------------------------------------------------------------------------
import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile

MACRO_MASTERS = {
    "sky130_sram_1rw1r_128x256_8": {
        # port: (width, direction)  direction: I/O
        "clk0": (1, "I"), "csb0": (1, "I"), "web0": (1, "I"),
        "wmask0": (16, "I"), "addr0": (8, "I"), "din0": (128, "I"),
        "dout0": (128, "O"),
        "clk1": (1, "I"), "csb1": (1, "I"), "addr1": (8, "I"),
        "dout1": (128, "O"),
    },
}
PG_PINS = {"vpwr", "vgnd", "vpbp", "vnbb", "vdd", "gnd", "vcc", "vss", "vpb", "vnb"}
CONST0_NAMES = {"zero_", "1'h0", "1'b0", "0"}
CONST1_NAMES = {"one_", "1'h1", "1'b1", "1"}


def norm(name):
    """网/实例名规一:去掉所有转义反斜杠,去首尾空白"""
    return name.replace("\\", "").strip() if name else name


def unescape_tok(tok):
    t = tok.strip()
    if t.startswith("\\"):
        t = t[1:]
    return t.strip()


class Const:
    def __init__(self, val):
        self.val = val

    def key(self):
        return f"CONST{self.val}"

    def __repr__(self):
        return self.key()


class VReader:
    """极简 Verilog 门级网表读取器:实例(含逐位端口连接)/assign/顶层端口

    concat_order:拼接元素→位 的映射口径
      "msb_first"  yosys write_verilog(IEEE 语义):元素 k → 位 width-1-k
      "lsb_first"  OpenROAD write_verilog(liberty 升序成员序):元素 k → 位 k
    """

    def __init__(self, path, concat_order="lsb_first"):
        self.path = path
        self.concat_order = concat_order
        self.insts = {}        # inst -> (master, {pinname: {"bits": {bit: ref}, "plain": ref|None}})
        self.assigns = []
        self.ports = []

    def read(self):
        with open(self.path, "r", encoding="utf-8", errors="replace") as f:
            text = f.read()
        text = re.sub(r"\(\*.*?\*\)", " ", text, flags=re.S)
        text = re.sub(r"//[^\n]*", " ", text)
        m = re.search(r"\bmodule\s+(\S+)\s*\(([^)]*)\)\s*;", text)
        if m:
            for p in m.group(2).split(","):
                p = p.strip()
                if p:
                    self.ports.append(unescape_tok(p))
        # assign
        for am in re.finditer(r"\bassign\s+(.+?);", text):
            body = am.group(1)
            mm = re.match(r"^\s*(\\?\S+)\s*=\s*(.+?)\s*$", body, flags=re.S)
            if mm:
                self.assigns.append((unescape_tok(mm.group(1)),
                                     self._ref_of(mm.group(2))))
        i = 0
        n = len(text)
        inst_re = re.compile(r"^\s*(\S+)\s+(\\?[^\s(]+)\s*\(", re.M)
        while True:
            m = inst_re.search(text, i)
            if not m:
                break
            master = unescape_tok(m.group(1))
            inst = unescape_tok(m.group(2))
            p_open = m.end() - 1
            depth, j = 0, p_open
            while j < n:
                if text[j] == "(":
                    depth += 1
                elif text[j] == ")":
                    depth -= 1
                    if depth == 0:
                        break
                j += 1
            body = text[p_open + 1:j]
            i = j + 1
            if inst in self.insts or master in ("module", "assign", "input",
                                                "output", "wire", "inout"):
                continue
            conns = self._parse_conns(body)
            self.insts[inst] = (master, conns)
        return self

    def _ref_of(self, expr):
        e = expr.strip()
        cm = re.match(r"^\d+'[bhd]([01xz]+|[0-9a-fA-Fxz]+)$", e)
        if cm:
            digits = cm.group(1)
            if set(digits) <= {"0", "x", "z", "X", "Z"}:
                return Const(0)
            base = {"b": 2, "h": 16, "d": 10}[e[len(e) - len(digits) - 1]]
            try:
                v = int(digits.replace("x", "0").replace("X", "0")
                         .replace("z", "0").replace("Z", "0"), base)
            except ValueError:
                return Const(0)
            all1 = v == (1 << len(digits)) - 1 if base != 10 else v == int(digits)
            return Const(1 if all1 else 0)
        return NetRef(unescape_tok(e))

    def _parse_conns(self, body):
        """解析命名连接列表 → {pinname: {"bits":{bit:ref},"plain":ref|None}}"""
        conns = {}
        pos = 0
        conn_re = re.compile(r"\.\s*([A-Za-z_][A-Za-z0-9_]*)\s*(\[\s*(\d+)\s*\])?\s*\(")
        while True:
            m = conn_re.search(body, pos)
            if not m:
                break
            pin = m.group(1)
            bit = int(m.group(3)) if m.group(3) is not None else None
            p_open = m.end() - 1
            depth, j = 0, p_open
            while j < len(body):
                if body[j] == "(":
                    depth += 1
                elif body[j] == ")":
                    depth -= 1
                    if depth == 0:
                        break
                j += 1
            expr = body[p_open + 1:j].strip()
            pos = j + 1
            slot = conns.setdefault(pin, {"bits": {}, "plain": None})
            if expr.startswith("{"):
                elems = split_top_commas(expr[1:-1])
                width = len(elems)
                for k, e in enumerate(elems):
                    b = (width - 1 - k) if self.concat_order == "msb_first" else k
                    slot["bits"][b] = self._ref_of(e)
            elif expr == "":
                continue
            else:
                r = self._ref_of(expr)
                if bit is not None:
                    slot["bits"][bit] = r
                else:
                    slot["plain"] = r
        return conns


def split_top_commas(s):
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


class NetRef(str):
    __slots__ = ()



def golden_from_yosys(path):
    """→ (gold, normalizer):gold 同前;normalizer(名字)→ 归一 key(别名/常量折叠)"""
    r = VReader(path, concat_order="msb_first").read()
    alias = {}

    def find(x):
        while x in alias and alias[x] != x:
            x = alias[x]
        return x

    const_of = {}
    for lhs, rhs in r.assigns:
        if isinstance(rhs, Const):
            const_of[lhs] = rhs.val
        elif isinstance(rhs, NetRef):
            a, b = find(lhs), find(norm(rhs))
            if a != b:
                alias[max(a, b)] = min(a, b)

    def normalizer(nm):
        """任意侧的网名 → 金标准归一 key(NET:<canonical> / CONSTn)"""
        nm = norm(nm)
        if nm in CONST0_NAMES or nm in const_of and const_of[nm] == 0:
            return "CONST0"
        if nm in CONST1_NAMES or nm in const_of and const_of[nm] == 1:
            return "CONST1"
        return f"NET:{find(nm)}"

    def refkey(ref):
        if isinstance(ref, Const):
            return f"CONST{ref.val}"
        nm = norm(ref)
        if nm in const_of:
            return f"CONST{const_of[nm]}"
        if nm in CONST0_NAMES:
            return "CONST0"
        if nm in CONST1_NAMES:
            return "CONST1"
        return normalizer(nm)

    gold = {}
    for inst, (master, conns) in r.insts.items():
        if master not in MACRO_MASTERS:
            continue
        ports = {}
        for port, spec in conns.items():
            width, _dir = MACRO_MASTERS[master][port]
            bits = {}
            if spec["plain"] is not None:
                base = refkey(spec["plain"])
                if base.startswith("NET:"):
                    nb = base[4:]
                    for b in range(width):
                        bits[b] = f"NET:{nb}[{b}]" if width > 1 else base
                else:
                    for b in range(width):
                        bits[b] = base
            else:
                for b, ref in spec["bits"].items():
                    bits[b] = refkey(ref)
            ports[port] = bits
        gold[inst] = {"master": master, "ports": ports}
    return gold, normalizer



DUMP_TCL = """
read_db {odb}
set block [ord::get_db_block]
set fp [open {{{out}}} w]
foreach inst [$block getInsts] {{
  set master [[$inst getMaster] getName]
  if {{[string first sky130_sram_1rw1r $master] < 0}} {{ continue }}
  puts $fp "INST [$inst getName] MASTER $master"
  foreach it [$inst getITerms] {{
    set n [$it getNet]
    set nn UNCONNECTED
    if {{$n != "NULL"}} {{ set nn [$n getName] }}
    puts $fp "  [[$it getMTerm] getName] -> $nn"
  }}
}}
close $fp
puts "DUMP_OK"
"""


def odb_binding(odb_path, openroad, normalizer):
    with tempfile.TemporaryDirectory() as td:
        tcl = os.path.join(td, "dump.tcl")
        out = os.path.join(td, "dump.txt")
        with open(tcl, "w") as f:
            f.write(DUMP_TCL.format(odb=odb_path, out=out))
        res = subprocess.run([openroad, "-no_init", "-exit", tcl],
                             capture_output=True, text=True, timeout=1800)
        blob = res.stdout + res.stderr
        if "DUMP_OK" not in blob:
            sys.stderr.write(blob[-4000:])
            raise RuntimeError(f"OpenROAD 导出 ODB 绑定失败: {odb_path}")
        bind = {}
        cur = None
        with open(out) as f:
            for line in f:
                line = line.rstrip("\n")
                if line.startswith("INST "):
                    parts = line.split()
                    cur = norm(parts[1])
                    bind[cur] = {"master": parts[3], "ports": {}}
                elif line.strip() and cur:
                    pin, net = [x.strip() for x in line.split("->")]
                    if pin in PG_PINS:
                        continue
                    m = re.match(r"^(\w+)\[(\d+)\]$", pin)
                    key = normalizer(net)
                    if key.startswith("NET:"):
                        k2 = odb_net_key(net)
                        key = k2 if not k2.startswith("NET:") else key
                    if m:
                        bind[cur]["ports"].setdefault(m.group(1), {})[int(m.group(2))] = key
                    else:
                        bind[cur]["ports"].setdefault(pin, {})[0] = key
        return bind


def odb_net_key(net):
    nm = norm(net)
    if nm in CONST0_NAMES:
        return "CONST0"
    if nm in CONST1_NAMES:
        return "CONST1"
    if nm == "UNCONNECTED" or nm.startswith("_NC"):
        return "UNCONNECTED"
    return f"NET:{nm}"



class Lib:
    def __init__(self):
        self.pins = {}       # cell -> {pin: "I"/"O"}
        self.passthrough = {}  # cell -> (in_pin, out_pin)
        self.tie = {}        # cell -> {pin: 0/1}

    def load(self, path):
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            text = f.read()
        for cm in re.finditer(r'\bcell\s*\(\s*"?([A-Za-z0-9_\\$/]+)"?\s*\)\s*\{', text):
            cname = cm.group(1)
            body = extract_brace(text, cm.end() - 1)
            pins = {}
            for pm in re.finditer(r'\bpin\s*\(\s*"?([A-Za-z0-9_]+)"?\s*\)\s*\{', body):
                pbody = extract_brace(body, pm.end() - 1)
                dm = re.search(r'\bdirection\s*:\s*"?(\w+)"?\s*;', pbody)
                if not dm:
                    continue
                d = dm.group(1)
                if d in ("input", "output", "inout"):
                    pins[pm.group(1)] = {"input": "I", "output": "O",
                                         "inout": "B"}[d]
            sig = {p: d for p, d in pins.items() if p.lower() not in PG_PINS}
            self.pins[cname] = sig
            ins = [p for p, d in sig.items() if d == "I"]
            outs = [p for p, d in sig.items() if d == "O"]
            if len(ins) == 1 and len(outs) == 1:
                self.passthrough[cname] = (ins[0], outs[0])
            elif len(ins) == 0 and len(outs) == 2 and \
                    {"LO", "HI"} <= set(outs):
                self.tie[cname] = {"LO": 0, "HI": 1}
        return self


def extract_brace(text, open_pos):
    depth, j = 0, open_pos
    while j < len(text):
        if text[j] == "{":
            depth += 1
        elif text[j] == "}":
            depth -= 1
            if depth == 0:
                return text[open_pos + 1:j]
        j += 1
    return text[open_pos + 1:]



class Graph:
    """从 VReader 构建信号连通图(仅信号引脚),支持源/负载追踪"""

    def __init__(self, reader, lib, masters_cdl=None):
        self.reader = reader
        self.lib = lib
        self.subckt_order = {}
        if masters_cdl:
            self._load_subckts(masters_cdl)
        self.net_pins = {}   # norm net -> [(inst, pinname)]
        self.port_nets = set()
        self._build()

    def _load_subckts(self, path):
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            text = f.read()
        for m in re.finditer(r"(?im)^\.SUBCKT\s+(\S+)\s+(.*)$", text):
            name = m.group(1)
            pins = m.group(2).split()
            self.subckt_order[name] = [norm(p) for p in pins]

    def dir_of(self, master, pin):
        if master in MACRO_MASTERS:
            d = MACRO_MASTERS[master].get(pin)
            if d is None:
                mb = re.match(r"^(\w+)\[\d+\]$", pin)
                if mb:
                    d = MACRO_MASTERS[master].get(mb.group(1))
            return d[1] if d else None
        return (self.lib.pins.get(master) or {}).get(pin)

    def is_pg(self, pin):
        return pin.lower() in PG_PINS

    def _build(self):
        r = self.reader
        for inst, (master, conns) in r.insts.items():
            for port, spec in conns.items():
                if self.is_pg(port):
                    continue
                if spec["plain"] is not None:
                    if isinstance(spec["plain"], Const):
                        continue
                    nm = norm(spec["plain"])
                    w = self.width_of(master, port)
                    if w > 1:
                        for b in range(w):
                            self.net_pins.setdefault(f"{nm}[{b}]", []).append((inst, port))
                    else:
                        self.net_pins.setdefault(nm, []).append((inst, port))
                for b in sorted(spec["bits"]):
                    ref = spec["bits"][b]
                    if isinstance(ref, Const):
                        continue
                    self.net_pins.setdefault(norm(ref), []).append((inst, port))

    def width_of(self, master, port):
        if master in MACRO_MASTERS:
            return MACRO_MASTERS[master][port][0]
        return 1


def trace_in(graph, net, normalizer, seen=None):
    """输入引脚向源追踪:回穿单入单出单元,身份=第一个真实驱动所在网
    (经金标准别名/常量折叠)。容忍并联驱动 buffer(repair_fanout 插入):
    有真实驱动即停(网名即身份),否则任取一个穿透驱动回穿。"""
    nm = norm(net)
    if seen is None:
        seen = set()
    if nm in seen:
        return f"LOOP:{nm}"
    seen.add(nm)
    if nm in CONST0_NAMES:
        return "CONST0"
    if nm in CONST1_NAMES:
        return "CONST1"
    real, pass_through = [], []
    for (inst, pin) in graph.net_pins.get(nm, []):
        master = graph.reader.insts[inst][0]
        if graph.dir_of(master, pin) != "O":
            continue
        if master in graph.lib.tie:
            return f"CONST{graph.lib.tie[master][pin]}"
        if master in graph.lib.passthrough:
            pass_through.append((inst, pin, master))
        else:
            real.append((inst, pin, master))
    if len(real) > 1:
        return f"MULTI:{nm}"
    if len(real) == 1:
        return normalizer(nm)
    if pass_through:
        inst, pin, master = pass_through[0]
        up = pin_net_of(graph, inst, graph.lib.passthrough[master][0])
        if up:
            return trace_in(graph, up, normalizer, seen)
    return normalizer(nm)


def pin_net_of(graph, inst, pin):
    """单元某输入引脚连接的网名(标量端口)"""
    _master, conns = graph.reader.insts[inst]
    spec = conns.get(pin)
    if not spec:
        return None
    if spec["plain"] is not None and not isinstance(spec["plain"], Const):
        return norm(spec["plain"])
    if spec["bits"]:
        ref = spec["bits"][sorted(spec["bits"])[0]]
        if not isinstance(ref, Const):
            return norm(ref)
    return None


def trace_out(graph, net, seen=None, sinks=None):
    """输出引脚向负载追踪:收集非单入单出单元的负载 (inst,pin) 集合"""
    if seen is None:
        seen = set()
    if sinks is None:
        sinks = set()
    nm = norm(net)
    if nm in seen:
        return sinks
    seen.add(nm)
    for (inst, pin) in graph.net_pins.get(nm, []):
        if pin == "DIODE":
            continue
        master = graph.reader.insts[inst][0]
        if graph.dir_of(master, pin) == "O":
            continue
        if master in graph.lib.passthrough and graph.dir_of(master, pin) == "I":
            opin = graph.lib.passthrough[master][1]
            onet = out_net_of(graph, inst, opin)
            if onet:
                trace_out(graph, onet, seen, sinks)
            continue
        sinks.add(f"{inst}/{pin}")
    return sinks


def out_net_of(graph, inst, pin):
    _master, conns = graph.reader.insts[inst]
    spec = conns.get(pin)
    if not spec:
        return None
    if spec["plain"] is not None and not isinstance(spec["plain"], Const):
        return norm(spec["plain"])
    return None



def cdl_instances(path, subckt_order):
    """→ {inst: (master, {pinname: netname})},位置传参按 subckt 引脚序"""
    insts = {}
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        text = f.read()
    text = re.sub(r"\n\+", " ", text)
    for m in re.finditer(r"(?im)^X(\S+)\s+(.*)$", text):
        toks = m.group(2).split()
        if not toks:
            continue
        master = toks[-1]
        nets = toks[:-1]
        pins = subckt_order.get(master)
        if pins is None or len(pins) != len(nets):
            continue
        insts[norm(m.group(1))] = (master, {pins[k]: nets[k] for k in range(len(nets))})
    return insts


def graph_from_cdl(insts, ports, lib, subckt_order):
    g = Graph.__new__(Graph)
    g.reader = type("R", (), {})()
    g.reader.insts = {}
    g.reader.ports = ports
    g.lib = lib
    g.subckt_order = subckt_order
    g.net_pins = {}
    g.port_nets = set(norm(p) for p in ports)
    for inst, (master, pmap) in insts.items():
        conv = {}
        for pin, net in pmap.items():
            if pin.lower() in PG_PINS:
                continue
            mb = re.match(r"^(\w+)\[(\d+)\]$", pin)
            if mb and master in MACRO_MASTERS and mb.group(1) in MACRO_MASTERS[master]:
                slot = conv.setdefault(mb.group(1), {"plain": None, "bits": {}})
                slot["bits"][int(mb.group(2))] = NetRef(net.replace("\\", ""))
            else:
                conv[pin] = {"plain": NetRef(net.replace("\\", "")), "bits": {}}
            g.net_pins.setdefault(norm(net.replace("\\", "")), []).append((inst, pin))
        g.reader.insts[inst] = (master, conv)
    return g


def final_binding(gold_graph, final_graph, gold, normalizer, label, problems):
    """final 口径:输入位向源追踪、输出位向负载追踪,与金标准等价比对。
    容忍:布线期 buffer 插入(回穿单入单出单元)、tie 单元、死逻辑消除
    (final 缺失的 sink 其单元已不存在)。"""
    ncmp = 0
    for inst, gspec in sorted(gold.items()):
        master = gspec["master"]
        fconns = final_graph.reader.insts.get(inst, (None, {}))[1]
        if not fconns:
            problems.append(f"[{label}] 宏实例缺失: {inst}")
            continue
        for port, gbits in gspec["ports"].items():
            width, direction = MACRO_MASTERS[master][port]
            spec = fconns.get(port)
            if spec is None:
                problems.append(f"[{label}] {inst} {port} 引脚缺失")
                continue
            nets = {}
            if spec["plain"] is not None:
                if isinstance(spec["plain"], Const):
                    for b in range(width):
                        nets[b] = f"CONST{spec['plain'].val}"
                else:
                    base = norm(spec["plain"])
                    for b in range(width):
                        nets[b] = f"{base}[{b}]" if width > 1 else base
            else:
                for b, ref in spec["bits"].items():
                    nets[b] = ("CONST%d" % ref.val) if isinstance(ref, Const) else norm(ref)
            for b in sorted(gbits):
                ncmp += 1
                gk = gbits[b]
                if direction == "I":
                    nb = nets.get(b)
                    if nb is None:
                        problems.append(f"[{label}] {inst} {port}[{b}] 位缺失")
                        continue
                    if nb.startswith("CONST"):
                        fk = nb
                    elif nb.startswith("_NC") or nb == "UNCONNECTED":
                        fk = "UNCONNECTED"
                    else:
                        fk = trace_in(final_graph, nb, normalizer)
                    if gk.startswith("NET:"):
                        gkey = trace_in(gold_graph, gk[4:], normalizer)
                    else:
                        gkey = gk
                    if fk != gkey:
                        problems.append(
                            f"[{label}] {inst} {port}[{b}]: yosys={gkey} vs final={fk}")
                else:
                    gb_net = (gk[4:] if gk.startswith("NET:") else None)
                    if gb_net is None:
                        problems.append(
                            f"[{label}] {inst} {port}[{b}]: 金标准非网名 {gk}")
                        continue
                    gsinks = trace_out(gold_graph, gb_net)
                    nb = nets.get(b)
                    if nb is None:
                        problems.append(f"[{label}] {inst} {port}[{b}] 位缺失")
                        continue
                    if nb.startswith("_NC") or nb == "UNCONNECTED":
                        fsinks = set()
                    else:
                        fsinks = trace_out(final_graph, nb)
                    if fsinks == gsinks:
                        continue
                    extra = fsinks - gsinks
                    missing = gsinks - fsinks
                    dead_ok = all(
                        (s.split("/", 1)[0]) not in final_graph.reader.insts
                        for s in missing)
                    if not extra and dead_ok:
                        continue
                    problems.append(
                        f"[{label}] {inst} {port}[{b}]: sink 不一致 "
                        f"yosys={sorted(gsinks)[:4]}{'…' if len(gsinks) > 4 else ''} "
                        f"final={sorted(fsinks)[:4]}{'…' if len(fsinks) > 4 else ''} "
                        f"extra={sorted(extra)[:3]} missing_dead_ok={dead_ok}")
    return ncmp


def graph_from_v(reader, lib):
    return Graph(reader, lib)



def compare(gold, other, label, problems, max_show=20):
    """逐实例逐端口逐位比对;other: {inst: {"ports": {port:{bit:key}}}}"""
    ncmp = 0
    for inst in sorted(gold):
        if inst not in other:
            problems.append(f"[{label}] 宏实例缺失: {inst}")
            continue
        for port, gbits in sorted(gold[inst]["ports"].items()):
            obits = other[inst]["ports"].get(port, {})
            for bit in sorted(gbits):
                ncmp += 1
                gk = gbits[bit]
                if obits.get(bit) != gk:
                    msg = (f"[{label}] {inst} {port}[{bit}]: "
                           f"yosys={gk} vs {label}={obits.get(bit, '<缺失>')}")
                    problems.append(msg)
    return ncmp


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--yosys", required=True, help="yosys 原始源网表(金标准)")
    ap.add_argument("--odb", help="1_synth 阶段 ODB(直接绑定比对)")
    ap.add_argument("--final-v", dest="final_v", help="布线后网表 6_final.v(追踪比对)")
    ap.add_argument("--final-odb", dest="final_odb", help="布线后 ODB(转 .v 比对用,预留)")
    ap.add_argument("--cdl", help="6_final.cdl(追踪比对)")
    ap.add_argument("--masters-cdl", dest="masters_cdl", help="masters 合并件(引脚序)")
    ap.add_argument("--lib", action="append", default=[],
                    help="标准单元 liberty(可多次,用于方向/穿透单元)")
    ap.add_argument("--openroad", default=os.environ.get(
        "OPENROAD",
        os.path.expanduser("~/tools/openroad-flow-scripts/tools/install/OpenROAD/bin/openroad")))
    ap.add_argument("--report", help="报告输出路径(缺省 stdout)")
    args = ap.parse_args()

    problems = []
    try:
        gold, normalizer = golden_from_yosys(args.yosys)
    except Exception as e:
        print(f"ERROR: 金标准解析失败: {e}", file=sys.stderr)
        return 2
    n_macro = len(gold)
    n_bits = sum(len(b) for s in gold.values() for b in s["ports"].values())
    print(f"金标准: {n_macro} 个宏实例, {n_bits} 个引脚位")

    if args.odb:
        if not os.path.exists(args.openroad):
            print(f"ERROR: 找不到 openroad: {args.openroad}", file=sys.stderr)
            return 2
        ob = odb_binding(args.odb, args.openroad, normalizer)
        odb_flat = {i: ob[i] for i in gold}
        ncmp = compare(gold, odb_flat, "odb", problems)

    lib = Lib()
    for lp in args.lib:
        lib.load(lp)
    n_pass = len(lib.passthrough)
    print(f"liberty: {len(lib.pins)} 单元, 其中单入单出(穿透) {n_pass} 个, tie {len(lib.tie)} 个")

    gold_vr = VReader(args.yosys, concat_order="msb_first").read()
    gold_graph = graph_from_v(gold_vr, lib)

    if args.final_v:
        vr = VReader(args.final_v, concat_order="msb_first").read()
        g = graph_from_v(vr, lib)
        ncmp = final_binding(gold_graph, g, gold, normalizer, "final_v", problems)

    if args.cdl:
        if not args.masters_cdl:
            print("ERROR: --cdl 需要配 --masters-cdl(subckt 引脚序)", file=sys.stderr)
            return 2
        gtmp = Graph.__new__(Graph)
        gtmp.subckt_order = {}
        gtmp._load_subckts(args.masters_cdl)
        insts = cdl_instances(args.cdl, gtmp.subckt_order)
        g = graph_from_cdl(insts, gold_vr.ports, lib, gtmp.subckt_order)
        ncmp = final_binding(gold_graph, g, gold, normalizer, "cdl", problems)

    n_problems = len(problems)
    total = n_bits
    print()
    print("=" * 72)
    if n_problems == 0:
        print(f"PASS: 宏引脚绑定 {total}/{total} 位 100% 一致(所有启用口径)")
        rc = 0
    else:
        print(f"FAIL: {n_problems} 处不一致 / 共 {total} 位")
        for p in problems[:50]:
            print("  " + p)
        if n_problems > 50:
            print(f"  ...(其余 {n_problems - 50} 条见报告文件)")
        rc = 1
    print("=" * 72)

    if args.report:
        with open(args.report, "w") as f:
            f.write(f"# P4A4 宏引脚绑定静态检查报告\n\n")
            f.write(f"- 金标准: {args.yosys} ({n_macro} 实例 / {n_bits} 位)\n")
            if args.odb:
                f.write(f"- ODB: {args.odb}\n")
            if args.final_v:
                f.write(f"- final.v: {args.final_v}\n")
            if args.cdl:
                f.write(f"- CDL: {args.cdl}\n")
            f.write(f"\n结论: {'PASS' if n_problems == 0 else 'FAIL'}"
                    f"{' (全部一致)' if n_problems == 0 else f' ({n_problems} 处不一致)'}\n\n")
            for p in problems:
                f.write(p + "\n")
        print(f"报告已写: {args.report}")
    return rc


if __name__ == "__main__":
    sys.exit(main())
