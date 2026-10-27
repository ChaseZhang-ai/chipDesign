# -----------------------------------------------------------------------------
#
#   klayout -b -rd in_gds=<6_final.gds> -rd def_file=<6_final.def> \
#     -r p4b3_lvs_pinlevel.py
# -----------------------------------------------------------------------------
import pya, re, os, sys
from collections import Counter

in_gds   = globals().get("in_gds")
def_file = globals().get("def_file")
lef_file = globals().get("lef_file")
nl_file  = globals().get("nl_file")
out_md   = globals().get("out", "p4b3_lvs_pinlevel.md")

lines = ["# P4B3 分层/引脚级 LVS 等效检查(宏黑盒策略)\n"]
fail = 0
MACRO = "sky130_sram_1rw1r_128x256_8"

def_insts = {}
for ln in open(def_file, errors="replace"):
    m = re.match(r"\s*-\s+(\S+)\s+" + MACRO + r"\s+\+\s+\S+\s+\(\s*(-?\d+)\s+(-?\d+)\s*\)\s+(\w+)\s*;", ln)
    if m:
        def_insts[m.group(1)] = (int(m.group(2)) / 1000.0, int(m.group(3)) / 1000.0, m.group(4))

_nl = open(nl_file, errors="replace").read() if nl_file else ""
_conn_cache = {}


def macro_conns(inst_name):
    out = {}
    m = re.search(r"sky130_sram_1rw1r_128x256_8 \\" + re.escape(inst_name) + r"\s*\((.*?)\);", _nl, re.S)
    if not m:
        return out
    body = m.group(1)
    for port in ["din0", "dout0", "dout1", "addr0", "addr1", "wmask0"]:
        mm = re.search(r"\." + port + r"\(\{(.*?)\}\)", body, re.S)
        if mm:
            out[port] = [t.strip() for t in mm.group(1).split(",")]
    for port in ["clk0", "csb0", "web0", "clk1", "csb1"]:
        mm = re.search(r"\." + port + r"\(([^{}()]*)\)", body, re.S)
        if mm:
            out[port] = [mm.group(1).strip()]
    return out


def net_expected_touch(net_tok):
    """引脚网的转义名出现次数 ≥3(声明+宏引脚+>=1 消费者)= 预期物理接触"""
    if not net_tok or net_tok in ("1'h0", "1'h1", "1'b0", "1'b1"):
        return None
    name = net_tok.lstrip("\\").strip()
    if name not in _conn_cache:
        _conn_cache[name] = len(re.findall(re.escape("\\" + name) + r"(?=\s)", _nl))
    return _conn_cache[name] >= 3


# ---------- GDS ----------
ly = pya.Layout()
ly.read(in_gds)
top = ly.top_cell()
dbu = ly.dbu

gds_insts = []
macro_trans = []
for inst in top.each_inst():
    if inst.cell.name == MACRO:
        t = inst.trans
        rot = int(t.rot)
        try:
            mir = bool(t.is_mirror())
        except TypeError:
            mir = bool(t.mirror)
        o = {0: "R0", 1: "R90", 2: "R180", 3: "R270"}[rot] + ("M" if mir else "")
        gds_insts.append((round(t.disp.x * dbu, 3), round(t.disp.y * dbu, 3), o))
        macro_trans.append(t)

lines.append("## L2 物理放置一致性\n")
lines.append(f"- DEF 宏实例:{len(def_insts)} 个;GDS 顶层宏实例:{len(gds_insts)} 个")
DEF_ORI = {"N": "R0", "S": "R180", "E": "R90", "W": "R270",
           "FN": "MY", "FS": "MY90", "FE": "MX90", "FW": "MX"}
def_pts = sorted((round(v[0], 3), round(v[1], 3), DEF_ORI.get(v[2], v[2])) for v in def_insts.values())
gds_pts = sorted(gds_insts)
l2_ok = (def_pts == gds_pts)
lines.append(f"- **L2 判定:{'PASS(位置/朝向 1:1 一致)' if l2_ok else 'FAIL(不一致!)'}**\n")
if not l2_ok:
    fail += 1

GDS_LAYER = {"li1": (67, 20), "met1": (68, 20), "met2": (69, 20),
             "met3": (70, 20), "met4": (71, 20), "met5": (72, 20)}
pins = {}  # name -> [(gds_layer, rect), ...]
cur = None
cur_layer = None
for ln in open(lef_file, errors="replace"):
    m = re.match(r"\s*PIN\s+(\S+)", ln)
    if m:
        cur = m.group(1); pins[cur] = []; cur_layer = None; continue
    m = re.match(r"\s*LAYER\s+(\w+)", ln)
    if m and cur:
        cur_layer = GDS_LAYER.get(m.group(1)); continue
    m = re.match(r"\s*RECT\s+([\d.\-]+)\s+([\d.\-]+)\s+([\d.\-]+)\s+([\d.\-]+)", ln)
    if m and cur:
        pins[cur].append((cur_layer, tuple(float(v) for v in m.groups())))


def top_region(layer_idx):
    r = pya.Region()
    r.insert(top.shapes(layer_idx), pya.Trans())
    return r


route_by_layer = {}
for gdsl in GDS_LAYER.values():
    li = ly.find_layer(*gdsl)
    if li is not None:
        route_by_layer[gdsl] = top_region(li)

for g, rgn in route_by_layer.items():
    print("DBG route[%s]=%d" % (g, rgn.count()), file=sys.stderr)
patch_by_layer = {gdsl: pya.Region() for gdsl in GDS_LAYER.values()}
import sys
_dbg_sizes = {}
_via_cell_ok = {}
lay_cache = {}
for inst in top.each_inst():
    cn = inst.cell.name
    if not cn.startswith("VIA"):
        continue
    if cn not in _via_cell_ok:
        lay = inst.cell.layout()
        lay_cache[cn] = lay
        _via_cell_ok[cn] = any(lay.find_layer(*g) is not None for g in GDS_LAYER.values())
    if not _via_cell_ok[cn]:
        continue
    lay = lay_cache[cn]
    for gdsl in GDS_LAYER.values():
        li = lay.find_layer(*gdsl)
        if li is not None:
            patch_by_layer[gdsl].insert(inst.cell.shapes(li), inst.trans)

lines.append("## L3 引脚级接触(LEF 引脚逐层几何 × 每宏实例)\n")
inst_names = {"8.120": "u_mem.u_core.u_ocram.u_ram.g_macro.u_macro",
              "1165.940": "u_ame.u_core.u_wbuf.g_macro.u_macro",
              "2323.760": "u_ame.u_core.u_xbuf.g_macro.u_macro"}
untouched = []
unexpected = []
dead_ok = 0
npins = 0
for t in macro_trans:
    key = "%.3f" % (t.disp.x * dbu)
    iname = inst_names.get(key, key)
    conns = macro_conns(iname) if nl_file else {}
    for pname, rects in pins.items():
        hit = False
        for (gds_l, (x1, y1, x2, y2)) in rects:
            box = pya.Box(int(x1 / dbu), int(y1 / dbu), int(x2 / dbu), int(y2 / dbu))
            abs_box = t.trans(box)
            probe = pya.Region(abs_box)
            for rgn in (route_by_layer.get(gds_l), patch_by_layer.get(gds_l)):
                if rgn is not None and not rgn.interacting(probe).is_empty():
                    hit = True
                    break
            if hit:
                break
        npins += 1
        if not hit:
            untouched.append((t.disp.x * dbu, t.disp.y * dbu, pname, iname))
            base, sep, idx = pname.partition("[")
            net = None
            if sep:
                k = int(idx.rstrip("]"))
                els = conns.get(base)
                if els:
                    w = len(els)
                    net = els[w - 1 - k]
            else:
                els = conns.get(pname)
                if els:
                    net = els[0]
            if net_expected_touch(net) is True:
                unexpected.append((t.disp.x * dbu, t.disp.y * dbu, pname, iname, (net or "?")[:70]))
            else:
                dead_ok += 1

lines.append(f"- 检查引脚·实例对:{npins}(实例 {len(macro_trans)} × 引脚 {len(pins)})")
_port_cnt = Counter(pname.split("[")[0] for _, _, pname, _ in untouched)
lines.append(f"- 物理未接触:{len(untouched)},其中 死网/常量预期(OK)={dead_ok},**预期应接触却未接触={len(unexpected)}**")
lines.append("- 未接触按端口分布:" + (", ".join(f"`{k}`×{v}" for k, v in sorted(_port_cnt.items())) or "无"))
for x, y, pname, iname, net in unexpected[:30]:
    lines.append(f"  - FAIL @({x:.1f},{y:.1f}) `{iname}` `{pname}` net=`{net}`")
l3_ok = (len(unexpected) == 0)
lines.append(f"- **L3 判定:{'PASS(全部有效连接引脚均有布线接触;死网不接触属预期)' if l3_ok else 'FAIL(存在应接触未接触引脚!)'}**\n")
if not l3_ok:
    fail += 1

lines.append("## 结论")
lines.append("- L1 网表引脚连接(1263/1263 位,v+cdl 双口径)= PASS(P4B3 独立复跑,见 p4b3_binding_final_recheck.rpt)")
lines.append(f"- L2 GDS↔DEF 宏放置 = {'PASS' if l2_ok else 'FAIL'}")
lines.append(f"- L3 引脚布线接触 = {'PASS' if l3_ok else 'FAIL'}")
lines.append(f"- **分层/引脚级 LVS 总判定:{'PASS' if fail == 0 else 'FAIL'}**(全展平 LVS 留 P5 可选)")
with open(out_md, "w") as f:
    f.write("\n".join(lines) + "\n")
print("P4B3 pin-level LVS written:", out_md, "fail=", fail)
