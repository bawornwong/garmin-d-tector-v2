#!/usr/bin/env python3
"""Production sprite packer. Implements ADR 3 + tickets 05/16:

  - every sprite thresholded to 1 bit (alpha>0 & luma>128), baked into a
    2-colour palette (index 0 = LCD background, index 1 = ink)
  - one atlas per size class: 24x24, 32x32, 14x16, odd
  - the 24x24 atlas is packed 24 cells wide, with a Digimon's sprite-action
    group never straddling a row (ticket 16)
  - round-trip verified: every packed cell must equal its source pixel-for-
    pixel before the atlas is written

Outputs:
  app/resources/drawables/atlas_<class>.png   - the atlas bitmaps
  build/sprite_index.json                     - key -> {atlas, cell/x/y/w/h}
                                                 for pack_data.py to consume
"""
import json
import math
import os
import re
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import (DT_SRC, app as app_path, load_mask, bake, new_atlas,
                    save_atlas, unbake_to_mask, src)

BUILD = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "build")
os.makedirs(BUILD, exist_ok=True)
os.makedirs(app_path("resources/drawables"), exist_ok=True)

GROUP_SUFFIX = re.compile(r"_(at|cr|sp|sm|bl|wh)$")


def digimon_key(basename):
    """Strip a sprite-action suffix, if present, to find the group name."""
    m = GROUP_SUFFIX.search(basename)
    return (basename[:m.start()], m.group(1)) if m else (basename, "base")


def collect():
    """Family A (Resources sprites) + family B (sheet sub-sprites)."""
    entries = []  # (key, size, mask)

    for group_dir in ("Digimon", "Abilities", "Energies", "Maps"):
        d = src("Assets/Resources/Sprites", group_dir)
        for fn in sorted(os.listdir(d)):
            if not fn.endswith(".png"):
                continue
            m = load_mask(os.path.join(d, fn))
            entries.append((f"{group_dir}/{fn[:-4]}", m.size, m))

    rect_re = re.compile(
        r"x: (\d+)\s*\n\s*y: (\d+)\s*\n\s*width: (\d+)\s*\n\s*height: (\d+)")
    sheets_dir = src("Assets/Sprites")
    for meta in sorted(os.listdir(sheets_dir)):
        if not meta.endswith(".png.meta"):
            continue
        sheet = meta[:-9]
        text = open(os.path.join(sheets_dir, meta), encoding="utf-8-sig",
                    errors="replace").read()
        rects = [tuple(map(int, r)) for r in rect_re.findall(text)]
        if not rects:
            continue
        png = os.path.join(sheets_dir, sheet + ".png")
        from PIL import Image
        H = Image.open(png).size[1]
        for i, (x, y, w, h) in enumerate(rects):
            top = H - y - h  # Unity rects are bottom-left origin
            m = load_mask(png, (x, top, x + w, top + h))
            entries.append((f"{sheet}_{i}", (w, h), m))

    return entries


def pack_grid(items, cols, groups_by_key=None):
    """Grid-pack items width `cols` cells. If groups_by_key is given (Digimon
    family only), a group's cells are kept contiguous within one row: if a
    group won't fit in the remaining row space, the row is padded and a new
    one started (ticket 16)."""
    index = {}
    row, col = 0, 0

    def newline():
        nonlocal row, col
        row += 1
        col = 0

    if groups_by_key:
        # stable order: by group name, then by the group's own member order
        order = []
        seen = set()
        for key, *_ in items:
            g, _ = groups_by_key(key)
            if g not in seen:
                seen.add(g)
                order.append(g)
        by_group = {}
        for it in items:
            g, _ = groups_by_key(it[0])
            by_group.setdefault(g, []).append(it)

        for g in order:
            members = by_group[g]
            if col + len(members) > cols:
                newline()
            for key, size, mask in members:
                index[key] = (row, col)
                col += 1
        if col > 0:
            newline()
    else:
        for key, size, mask in items:
            if col >= cols:
                newline()
            index[key] = (row, col)
            col += 1
        if col > 0:
            newline()

    return index, row  # row is now the total row count


def build_atlas(name, items, cell_w, cell_h, cols, groups_by_key=None):
    from PIL import Image
    index, rows = pack_grid(items, cols, groups_by_key)
    atlas = new_atlas(cols * cell_w, rows * cell_h)

    by_key = {key: (size, mask) for key, size, mask in items}
    for key, (row, col) in index.items():
        size, mask = by_key[key]
        w, h = size
        baked = bake(mask)
        atlas.paste(baked, (col * cell_w, row * cell_h))

    return atlas, index, cols, rows


def verify(atlas, index, items, cell_w, cell_h, cols):
    by_key = {key: (size, mask) for key, size, mask in items}
    bad = []
    for key, (row, col) in index.items():
        size, mask = by_key[key]
        w, h = size
        x0, y0 = col * cell_w, row * cell_h
        got = unbake_to_mask(atlas.crop((x0, y0, x0 + w, y0 + h)))
        if list(got.get_flattened_data()) != list(mask.get_flattened_data()):
            bad.append(key)
    return bad


def main():
    entries = collect()
    print(f"collected {len(entries)} sprites")

    by_size = {}
    for key, size, mask in entries:
        by_size.setdefault(size, []).append((key, size, mask))

    BIG = {sz: v for sz, v in by_size.items() if len(v) >= 16}
    odd_items = [it for sz, v in by_size.items() if sz not in BIG for it in v]

    result_index = {}  # key -> dict(atlas=name, x, y, w, h)
    atlas_meta = []

    for (cw, ch), items in sorted(BIG.items(), key=lambda kv: -len(kv[1])):
        name = f"atlas_{cw}x{ch}"
        cols = 24
        groups_by_key = digimon_key if (cw, ch) == (24, 24) else None
        atlas, index, used_cols, rows = build_atlas(
            name, items, cw, ch, cols, groups_by_key)

        bad = verify(atlas, index, items, cw, ch, cols)
        if bad:
            print(f"  ROUND-TRIP FAILURE in {name}: {bad[:5]} (+{len(bad)-5} more)")
            sys.exit(1)

        save_atlas(atlas, app_path("resources/drawables", name + ".png"))
        px = atlas.size[0] * atlas.size[1]
        print(f"  {name:16s} {len(items):5d} sprites  grid {cols}x{rows}  "
              f"{atlas.size[0]}x{atlas.size[1]}px  {px//8:,} bytes @1bpp  "
              f"round-trip OK")

        for key, (row, col) in index.items():
            result_index[key] = dict(atlas=name, x=col * cw, y=row * ch, w=cw, h=ch)
        atlas_meta.append(dict(name=name, cellW=cw, cellH=ch, cols=cols, rows=rows))

    # odd sizes: one strip, tight-packed left to right, no grid padding
    if odd_items:
        W = sum(size[0] for _, size, _ in odd_items)
        H = max(size[1] for _, size, _ in odd_items)
        atlas = new_atlas(W, H)
        x = 0
        strip_index = {}
        for key, size, mask in odd_items:
            baked = bake(mask)
            atlas.paste(baked, (x, 0))
            strip_index[key] = (x, 0, size[0], size[1])
            x += size[0]

        bad = []
        for key, (sx, sy, w, h) in strip_index.items():
            got = unbake_to_mask(atlas.crop((sx, sy, sx + w, sy + h)))
            want = [k for k in odd_items if k[0] == key][0][2]
            if list(got.get_flattened_data()) != list(want.get_flattened_data()):
                bad.append(key)
        if bad:
            print(f"  ROUND-TRIP FAILURE in atlas_odd: {bad}")
            sys.exit(1)

        save_atlas(atlas, app_path("resources/drawables/atlas_odd.png"))
        print(f"  {'atlas_odd':16s} {len(odd_items):5d} sprites  strip  "
              f"{atlas.size[0]}x{atlas.size[1]}px  round-trip OK")
        for key, (sx, sy, w, h) in strip_index.items():
            result_index[key] = dict(atlas="atlas_odd", x=sx, y=sy, w=w, h=h)
        atlas_meta.append(dict(name="atlas_odd", cellW=None, cellH=H, cols=None,
                                rows=None, strip=True, width=W))

    json.dump({"sprites": result_index, "atlases": atlas_meta},
              open(os.path.join(BUILD, "sprite_index.json"), "w"), indent=1)
    total_bytes = sum(a["cols"] * a["rows"] * a["cellW"] * a["cellH"] // 8
                      if not a.get("strip") else a["width"] * a["cellH"] // 8
                      for a in atlas_meta)
    print(f"\nTOTAL: {len(result_index)} sprites, {total_bytes:,} bytes @1bpp "
          f"across {len(atlas_meta)} atlases")
    print(f"wrote build/sprite_index.json")


if __name__ == "__main__":
    main()
