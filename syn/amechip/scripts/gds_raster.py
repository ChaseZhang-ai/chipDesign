#!/usr/bin/env python3
# -----------------------------------------------------------------------------
#
# -----------------------------------------------------------------------------
import os
import pya

GDS   = os.environ["AME_GDS"]
FULL  = os.environ["AME_PNG_FULL"]
REG   = os.environ.get("AME_PNG_REGION", "")
BOX   = os.environ.get("AME_BOX", "")
W, H  = 2400, 1200

ly = pya.Layout()
ly.read(GDS)
top = ly.top_cell()
dbu = ly.dbu

LAYERS = [
    (64, 20, ( 90, 90,110), 255),
    (67, 20, (150,150,150), 200),   # li1
    (68, 20, (120,170,255), 220),   # met1
    (69, 20, ( 80,200,200), 200),   # met2
    (70, 20, (255, 90, 90), 220),   # met3
    (71, 20, ( 90,220, 90), 235),   # met4
    (72, 20, (255,160, 40), 255),   # met5
]

def render(viewbox, out_png, w, h):
    from PIL import Image, ImageDraw
    x1, y1, x2, y2 = viewbox
    sx = w / (x2 - x1)
    sy = h / (y2 - y1)
    img = Image.new("RGB", (w, h), (8, 8, 12))
    drw = ImageDraw.Draw(img, "RGBA")
    clip = pya.Region(pya.Box(int(x1/dbu), int(y1/dbu), int(x2/dbu), int(y2/dbu)))
    for (l, d, color, alpha) in LAYERS:
        li = ly.find_layer(l, d)
        if li is None:
            continue
        reg = pya.Region(top.begin_shapes_rec(li)) & clip
        n = 0
        ov = drw
        for sh in reg.each():
            b = sh.bbox()
            px1 = int((b.left * dbu - x1) * sx)
            py1 = h - 1 - int((b.top * dbu - y1) * sy)
            px2 = int((b.right * dbu - x1) * sx)
            py2 = h - 1 - int((b.bottom * dbu - y1) * sy)
            if px2 < 0 or px1 >= w or py2 < 0 or py1 >= h:
                continue
            ov.rectangle((max(px1,0), max(py1,0), min(px2,w-1), min(py2,h-1)),
                         fill=color + (alpha,))
            n += 1
        print(f"  layer {l}/{d}: {n} shapes")
    img.save(out_png)
    print("saved:", out_png)

print("== full chip ==")
die = top.dbbox()
render((die.left, die.bottom, die.right, die.top), FULL, W, H)

if REG and BOX:
    print("== AME region ==")
    bx = [float(v) for v in BOX.split()]
    render((bx[0], bx[1], bx[2], bx[3]), REG, W, H)
