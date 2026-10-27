import pya

try:
    gds = in_gds
except NameError:
    raise SystemExit("usage: klayout -b -r klayout_gds_check.py -rd in_gds=<file.gds>")

ly = pya.Layout()
ly.read(gds)
tops = [ly.cell(i).name for i in ly.each_top_cell()]
print("[klayout_gds_check] file :", gds)
print("[klayout_gds_check] cells:", ly.cells(), " layers:", ly.layers())
print("[klayout_gds_check] tops :", tops)
print("[klayout_gds_check] dbu  :", ly.dbu)
