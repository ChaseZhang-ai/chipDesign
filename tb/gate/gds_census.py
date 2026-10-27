import pya, os

in_gds   = globals().get("in_gds")
out_md   = globals().get("out", "gds_census.md")
png_full = globals().get("png_full")
png_ame  = globals().get("png_ame")

ly = pya.Layout()
ly.read(in_gds)
top = ly.top_cell()
dbu = ly.dbu

lines = []
lines.append("# P4B GDS 独立复核(KLayout 0.30.0 批处理,无 GUI)\n")
lines.append(f"- 文件:`{in_gds}`")
lines.append(f"- 大小:{os.path.getsize(in_gds)/1e6:.1f} MB")
lines.append(f"- 顶层单元:{top.name}")
lines.append(f"- 单元定义总数:{ly.cells()}")
lines.append(f"- 顶层 bbox(µm):{[round(v*dbu,3) for v in (top.bbox().left, top.bbox().bottom, top.bbox().right, top.bbox().top)]}")
lines.append(f"- 数据库单位:{dbu} µm/DBU\n")

lines.append("## 图层清单(GDS 层/类型 → 递归元素数)\n")
lines.append("| GDS 层 | 递归元素数 |")
lines.append("|---|---|")
total = 0
for li in ly.layer_indexes():
    info = ly.get_info(li)
    n = 0
    it = top.begin_shapes_rec(li)
    while not it.at_end():
        n += 1; it.next()
    total += n
    lines.append(f"| {info.layer}/{info.datatype} | {n} |")
lines.append(f"\n全层递归元素合计:**{total}**\n")

lines.append("## 关键单元存在性与顶层递归实例数\n")
def inst_count(cell_name):
    ci = ly.cell(cell_name)
    if ci is None:
        return None, 0
    n = 0
    for inst in top.each_inst():
        if inst.cell.name == cell_name:
            n += 1
    return ci, n

for name in ["sky130_sram_1rw1r_128x256_8", "sky130_fd_sc_hd__dfrtp_1",
             "sky130_fd_sc_hd__buf_4", "sky130_fd_sc_hd__decap_3"]:
    c, n = inst_count(name)
    lines.append(f"- `{name}`:{'存在' if c is not None else '**缺失**'}"
                 + (f",顶层递归实例 {n} 个" if c is not None else ""))

sr = ly.cell("sky130_sram_1rw1r_128x256_8")
macro_boxes = []
if sr is not None:
    for inst in top.each_inst():
        if inst.cell.name == "sky130_sram_1rw1r_128x256_8":
            macro_boxes.append(inst.bbox())
lines.append("")
if macro_boxes:
    for i, b in enumerate(macro_boxes):
        lines.append(f"- SRAM 宏实例 #{i} bbox(µm):"
                     f"[{b.left*dbu:.2f}, {b.bottom*dbu:.2f}, {b.right*dbu:.2f}, {b.top*dbu:.2f}]")

LAYERS = [
    (64, 20, (100,100,120), 255),   # nwell
    (67, 20, (160,160,160), 200),   # li1
    (68, 20, (120,170,255), 220),   # met1
    (69, 20, ( 80,200,200), 200),   # met2
    (70, 20, (255, 90, 90), 220),   # met3
    (71, 20, ( 90,220, 90), 235),   # met4
    (72, 20, (255,160, 40), 255),   # met5
]

def render(viewbox_um, out_png, w=2400, h=1200):
    from PIL import Image, ImageDraw
    x1, y1, x2, y2 = viewbox_um
    sx, sy = w/(x2-x1), h/(y2-y1)
    img = Image.new("RGB", (w, h), (10, 10, 14))
    drw = ImageDraw.Draw(img, "RGBA")
    clip = pya.Region(pya.Box(int(x1/dbu), int(y1/dbu), int(x2/dbu), int(y2/dbu)))
    for (l, d, color, alpha) in LAYERS:
        li = ly.find_layer(l, d)
        if li is None:
            continue
        reg = pya.Region(top.begin_shapes_rec(li)) & clip
        for sh in reg.each():
            b = sh.bbox()
            px1 = int((b.left*dbu - x1)*sx);  py1 = h-1-int((b.top*dbu - y1)*sy)
            px2 = int((b.right*dbu - x1)*sx); py2 = h-1-int((b.bottom*dbu - y1)*sy)
            if px2 < 0 or px1 >= w or py2 < 0 or py1 >= h:
                continue
            drw.rectangle((max(px1,0), max(py1,0), min(px2,w-1), min(py2,h-1)),
                          fill=color + (alpha,))
    img.save(out_png)
    return os.path.getsize(out_png)

tb = top.bbox()
full_um = (tb.left*dbu, tb.bottom*dbu, tb.right*dbu, tb.top*dbu)
if png_full:
    sz = render(full_um, png_full)
    lines.append(f"\n## 截图\n- 整图:`{png_full}`({sz/1024:.0f} KB,视窗 {full_um})")
if png_ame and macro_boxes:
    u = macro_boxes[0]
    for b in macro_boxes[1:]:
        u += b
    m = int(50.0/dbu)
    u = u.enlarged(pya.Vector(m, m))
    ame_um = (u.left*dbu, u.bottom*dbu, u.right*dbu, u.top*dbu)
    sz = render(ame_um, png_ame)
    lines.append(f"- AME 区(三宏 bbox 外扩 50µm):`{png_ame}`({sz/1024:.0f} KB,视窗 {ame_um})")

with open(out_md, "w") as f:
    f.write("\n".join(lines) + "\n")
print("P4B gds census written:", out_md)
