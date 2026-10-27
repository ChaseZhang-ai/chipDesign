#!/usr/bin/env python3
#   AME_GDS / AME_PNG_FULL / AME_PNG_REGION / AME_BOX("x1 y1 x2 y2" µm)
import os
import pya

in_gds  = os.environ["AME_GDS"]
png_out = os.environ["AME_PNG_FULL"]
png_reg = os.environ.get("AME_PNG_REGION", "")
box_str = os.environ.get("AME_BOX", "")
width  = int(os.environ.get("AME_W", "2400"))
height = int(os.environ.get("AME_H", "1200"))

ly = pya.Layout()
ly.read(in_gds)
top = ly.top_cells()[0]
print("top:", top.name, "dbu:", ly.dbu)

lv = pya.LayoutView(False)
lv.show_layout(ly, False)
lv.add_missing_layers()
lv.set_config("background-color", "#000000")
lv.set_config("grid-visible", "false")

def snap(path, w, h):
    pix = lv.get_pixels(w, h)
    try:
        pix.write_png(path)
    except AttributeError:
        pass
    print("saved:", path)

lv.zoom_fit()
snap(png_out, width, height)

if png_reg and box_str:
    x1, y1, x2, y2 = [float(v) for v in box_str.split()]
    lv.zoom_box(pya.DBox(x1, y1, x2, y2))
    snap(png_reg, width, height)
