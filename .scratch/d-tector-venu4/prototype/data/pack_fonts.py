#!/usr/bin/env python3
"""Extracts the three bitmap fonts from the Unity assets and packs them.

Each .fontsettings holds a UV rect per glyph into a 50x50 sheet, plus a vert
rect and an advance in Unity units. PIXEL_SIZE is 24, so dividing by 24 gives
game pixels. Glyph art lives in the sheet's ALPHA channel -- the RGB is solid
white -- so the same alpha-and-luma threshold the sprite packer uses applies.
"""
import os
import re
import sys
from PIL import Image

SRC, OUT = sys.argv[1], sys.argv[2]
os.makedirs(OUT, exist_ok=True)
UNIT = 24  # Constants.PIXEL_SIZE

GLYPH = re.compile(
    r'index: (\d+)\s*\n\s*uv:\s*\n\s*serializedVersion: 2\s*\n'
    r'\s*x: ([-\d.]+)\s*\n\s*y: ([-\d.]+)\s*\n\s*width: ([-\d.]+)\s*\n\s*height: ([-\d.]+)\s*\n'
    r'\s*vert:\s*\n\s*serializedVersion: 2\s*\n'
    r'\s*x: ([-\d.]+)\s*\n\s*y: ([-\d.]+)\s*\n\s*width: ([-\d.]+)\s*\n\s*height: ([-\d.]+)\s*\n'
    r'\s*advance: ([-\d.]+)')


def load_alpha(path):
    im = Image.open(path).convert("RGBA")
    w, h = im.size
    m = Image.new("1", (w, h), 0)
    mp, px = m.load(), im.load()
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            luma = (r * 299 + g * 587 + b * 114) // 1000
            mp[x, y] = 1 if (a > 0 and luma > 128) else 0
    return m


fonts = {}
for face, sheet in (("Big", "font_big"), ("Regular", "font_regular"), ("Small", "font_small")):
    text = open(os.path.join(SRC, "Assets/Fonts", face + ".fontsettings"),
                encoding="utf-8-sig", errors="replace").read()
    hdr = dict(re.findall(r'm_(\w+): (\S+)', text))
    png = os.path.join(SRC, "Assets/Sprites", sheet + ".png")
    mask = load_alpha(png)
    W, H = mask.size
    glyphs = []
    for g in GLYPH.findall(text):
        idx = int(g[0])
        ux, uy, uw, uh = (float(v) for v in g[1:5])
        adv = float(g[9])
        # Unity UV origin is bottom-left; PIL is top-left
        x = round(ux * W)
        y = round((1.0 - uy - uh) * H)
        w = round(uw * W)
        h = round(uh * H)
        glyphs.append({
            "char": chr(idx), "code": idx, "rect": (x, y, w, h),
            "advance_units": adv, "advance_px": adv / UNIT,
            "img": mask.crop((x, y, x + w, y + h)),
        })
    fonts[face] = {
        "glyphs": sorted(glyphs, key=lambda g: g["code"]),
        "lineSpacing_px": float(hdr["LineSpacing"]) / UNIT,
        "tracking": hdr["Tracking"], "padding": hdr["CharacterPadding"],
        "convertCase": hdr["ConvertCase"],
    }

print(f"{'face':9s} {'glyphs':>7s} {'line px':>8s} {'advances (px)':>28s} {'sizes':>22s}")
for face, f in fonts.items():
    advs = sorted({g["advance_px"] for g in f["glyphs"]})
    sizes = sorted({(g["rect"][2], g["rect"][3]) for g in f["glyphs"]})
    print(f"{face:9s} {len(f['glyphs']):7d} {f['lineSpacing_px']:8.1f} "
          f"{str(advs):>28s} {str(sizes):>22s}")

# pack every glyph into one strip, then read them back and diff
strip_cells = []
index = {}
for face, f in fonts.items():
    for g in f["glyphs"]:
        index[(face, g["code"])] = len(strip_cells)
        strip_cells.append((face, g))
CW = max(g["rect"][2] for _, g in strip_cells)
CH = max(g["rect"][3] for _, g in strip_cells)
COLS = 24
rows = (len(strip_cells) + COLS - 1) // COLS
atlas = Image.new("1", (COLS * CW, rows * CH), 0)
for i, (_, g) in enumerate(strip_cells):
    atlas.paste(g["img"], ((i % COLS) * CW, (i // COLS) * CH))
atlas.save(os.path.join(OUT, "font_atlas.png"))
print(f"\nglyph atlas: {len(strip_cells)} cells of {CW}x{CH} "
      f"-> {atlas.size[0]}x{atlas.size[1]} = {atlas.size[0]*atlas.size[1]//8} bytes at 1bpp")

bad = 0
for i, (face, g) in enumerate(strip_cells):
    cx, cy = (i % COLS) * CW, (i // COLS) * CH
    w, h = g["rect"][2], g["rect"][3]
    got = [1 if v else 0 for v in atlas.crop((cx, cy, cx + w, cy + h)).convert("L").getdata()]
    want = [1 if v else 0 for v in g["img"].convert("L").getdata()]
    if got != want:
        bad += 1
        if bad <= 5:
            print(f"  MISMATCH {face} '{g['char']}'")
print(f"round-trip: {len(strip_cells) - bad}/{len(strip_cells)} glyphs identical")

# how a name with characters the font lacks actually lays out
CHARSET = {face: {g["char"] for g in f["glyphs"]} for face, f in fonts.items()}


def layout(face, text):
    f = fonts[face]
    adv = {g["char"]: g["advance_px"] for g in f["glyphs"]}
    s = text.upper() if f["convertCase"] == "1" else text
    x = 0.0
    drawn, skipped = [], []
    for ch in s:
        if ch in adv:
            drawn.append((ch, x))
            x += adv[ch]
        else:
            skipped.append(ch)
    return x, "".join(c for c, _ in drawn), skipped


print()
for face in ("Big", "Regular"):
    for name in ("agumon (primal)", "gallantmon (crimson)", "000 AGUMON", "GAME"):
        w, drawn, skipped = layout(face, name)
        print(f"  {face:8s} {name!r:24s} -> width {w:5.1f} px  shows {drawn!r}"
              + (f"  dropped {skipped}" if skipped else ""))
