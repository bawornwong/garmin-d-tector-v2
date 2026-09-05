#!/usr/bin/env python3
"""Prototype sprite packer for the D-Tector -> Venu 4 port.

Reads the original Unity assets, thresholds every sprite to 1 bit, and packs
them into one atlas per size class. Emits the atlas PNGs, an index table, and
a size report. Throwaway: this exists to make the ticket 05 decision concrete.
"""
import collections
import json
import math
import os
import re
import sys
from PIL import Image

SRC = sys.argv[1]
OUT = sys.argv[2]
os.makedirs(OUT, exist_ok=True)

LUMA_ON = 128  # a pixel is "on" when its luma exceeds this


def load_1bit(path, box=None):
    im = Image.open(path).convert("RGBA")
    if box:
        im = im.crop(box)
    w, h = im.size
    mask = Image.new("1", (w, h), 0)
    mp = mask.load()
    px = im.load()
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            luma = (r * 299 + g * 587 + b * 114) // 1000
            mp[x, y] = 1 if (a > 0 and luma > LUMA_ON) else 0
    return mask


sprites = []  # (key, size, PIL 1-bit image)

# --- family A: Resources sprites, addressed by name at runtime -------------
for group in ("Digimon", "Abilities", "Energies", "Maps"):
    d = os.path.join(SRC, "Assets/Resources/Sprites", group)
    for fn in sorted(os.listdir(d)):
        if not fn.endswith(".png"):
            continue
        img = load_1bit(os.path.join(d, fn))
        sprites.append((f"{group}/{fn[:-4]}", img.size, img))

# --- family B: sheet sub-sprites, rects recovered from the .meta ----------
RECT = re.compile(r"x: (\d+)\s*\n\s*y: (\d+)\s*\n\s*width: (\d+)\s*\n\s*height: (\d+)")
for meta in sorted(os.listdir(os.path.join(SRC, "Assets/Sprites"))):
    if not meta.endswith(".png.meta"):
        continue
    sheet = meta[:-9]
    text = open(os.path.join(SRC, "Assets/Sprites", meta), encoding="utf-8-sig", errors="replace").read()
    rects = [tuple(map(int, m)) for m in RECT.findall(text)]
    if not rects:
        continue
    png = os.path.join(SRC, "Assets/Sprites", sheet + ".png")
    H = Image.open(png).size[1]
    for i, (x, y, w, h) in enumerate(rects):
        top = H - y - h  # Unity rects are bottom-left origin
        img = load_1bit(png, (x, top, x + w, top + h))
        sprites.append((f"{sheet}_{i}", (w, h), img))

# --- pack, one atlas per size class ---------------------------------------
classes = collections.defaultdict(list)
for key, size, img in sprites:
    classes[size].append((key, img))

BIG = {sz: items for sz, items in classes.items() if len(items) >= 16}
odd = [(key, img) for sz, items in classes.items() if sz not in BIG for key, img in items]

index = {}
report = []
for (cw, ch), items in sorted(BIG.items(), key=lambda kv: -len(kv[1])):
    cols = max(1, int(math.ceil(math.sqrt(len(items)))))
    rows = int(math.ceil(len(items) / cols))
    atlas = Image.new("1", (cols * cw, rows * ch), 0)
    for i, (key, img) in enumerate(items):
        atlas.paste(img, ((i % cols) * cw, (i // cols) * ch))
        index[key] = {"atlas": f"{cw}x{ch}", "cell": i}
    name = f"atlas_{cw}x{ch}"
    atlas.save(os.path.join(OUT, name + ".png"))
    bits = atlas.size[0] * atlas.size[1]
    report.append((name, len(items), f"{cols}x{rows}", f"{atlas.size[0]}x{atlas.size[1]}", bits // 8))

# odd sizes: one strip with an explicit offset table
if odd:
    W = sum(img.size[0] for _, img in odd)
    H = max(img.size[1] for _, img in odd)
    atlas = Image.new("1", (W, H), 0)
    x = 0
    for key, img in odd:
        atlas.paste(img, (x, 0))
        index[key] = {"atlas": "odd", "x": x, "y": 0, "w": img.size[0], "h": img.size[1]}
        x += img.size[0]
    atlas.save(os.path.join(OUT, "atlas_odd.png"))
    report.append(("atlas_odd", len(odd), "strip", f"{W}x{H}", (W * H) // 8))

json.dump(index, open(os.path.join(OUT, "index.json"), "w"), indent=1, sort_keys=True)

total = sum(r[4] for r in report)
print(f"{'atlas':16s} {'sprites':>8s} {'grid':>10s} {'pixels':>12s} {'1bpp bytes':>12s}")
for name, n, grid, dims, b in report:
    print(f"{name:16s} {n:8d} {grid:>10s} {dims:>12s} {b:12,d}")
print(f"{'TOTAL':16s} {len(sprites):8d} {'':>10s} {'':>12s} {total:12,d}  ({total/1024:.1f} KB)")

# --- round-trip verification ---------------------------------------------
atlases = {}
bad = 0
for key, size, img in sprites:
    e = index[key]
    if e["atlas"] == "odd":
        a = atlases.setdefault("odd", Image.open(os.path.join(OUT, "atlas_odd.png")))
        box = (e["x"], e["y"], e["x"] + e["w"], e["y"] + e["h"])
    else:
        cw, ch = map(int, e["atlas"].split("x"))
        a = atlases.setdefault(e["atlas"], Image.open(os.path.join(OUT, f"atlas_{e['atlas']}.png")))
        cols = a.size[0] // cw
        cx, cy = (e["cell"] % cols) * cw, (e["cell"] // cols) * ch
        box = (cx, cy, cx + cw, cy + ch)
    got = [1 if v else 0 for v in a.crop(box).convert("L").getdata()]
    want = [1 if v else 0 for v in img.convert("L").getdata()]
    if got != want:
        bad += 1
        if bad <= 5:
            print("  MISMATCH", key)
print(f"round-trip: {len(sprites) - bad}/{len(sprites)} sprites identical, {bad} mismatched")
