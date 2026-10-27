# -----------------------------------------------------------------------------
#
#   klayout -b \
#     -rd in_gds=<6_final.gds> \
#     -rd width=2400 -rd height=1200 \
#     -r gds_png.py
#
# -----------------------------------------------------------------------------
import pya

in_gds    = pya.Application.instance().get_variable("in_gds")
png_out   = pya.Application.instance().get_variable("png_out")
png_reg   = pya.Application.instance().get_variable("png_region")
box_str   = pya.Application.instance().get_variable("box")
width     = int(pya.Application.instance().get_variable("width") or 2400)
height    = int(pya.Application.instance().get_variable("height") or 1200)

ly = pya.Layout()
ly.read(in_gds)
top = ly.top_cells()[-1] if len(ly.top_cells()) == 1 else ly.top_cells()[0]
print("top cell:", top.name, " dbu:", ly.dbu)

lv = pya.LayoutView(True)
lv.show_layout(ly, True)
lv.set_config("background-color", "#000000")
lv.set_config("grid-visible", "false")
lv.set_config("grid-style0-color", "#000000")

def snap(path, w, h):
    pix = lv.get_pixels(w, h)
    pix.save(path)
    print("saved:", path)

lv.zoom_fit()
snap(png_out, width, height)

if png_reg and box_str:
    x1, y1, x2, y2 = [float(v) for v in box_str.split()]
    lv.zoom_box(pya.DBox(x1, y1, x2, y2))
    snap(png_reg, width, height)
