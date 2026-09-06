#!/usr/bin/env python3
"""Diff a frame captured off the simulator against the atlas it was drawn from.

This is the render path's counterpart to the packers' round-trip checks:
those prove the atlas matches the source art, this proves the device draws
the atlas. It resolves the sprite reference out of build/data.bin -- the very
bytes the device reads -- samples the centre of each 10x block of the
captured frame, and compares. Both failures found while building the
skeleton would have survived a "looks right" glance at the screenshot:

  - the resource compiler quantising and dithering the atlas, which silently
    dropped 10 isolated ink pixels out of 576 in one 24x24 cell. Fixed with
    an explicit <palette> plus dithering="none" in drawables.xml.
  - drawBitmap2 offsetting the destination by T * (bitmapX, bitmapY) when a
    :transform is set, which put the sprite 1,200 px off-screen.

Usage:
    tools/verify_render.py <frame.png> <digimon index> [action]

Build the app with DTectorView._probeIndex set to the same index first: that
makes the view draw the Digimon's base sprite alone, at the position below.
"""
import json
import os
import struct
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import app
from pack_data import ATLAS_CODE, ENTRY, ENTRY_SIZE, NO_SPRITE

BUILD = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "build")

SCREEN = 454          # venu445mm
CANVAS = 320          # DTectorView.CANVAS
SCALE = 10            # DTectorView.SCALE
ORIGIN = (SCREEN - CANVAS) // 2 + 40    # DTectorView draws the probe at off + 40
INK_SUM = 200         # ink sums to ~0; the LCD field to ~394

ATLAS_FILE = {v: k + ".png" for k, v in ATLAS_CODE.items()}


def sprite_ref(index, action):
    """[atlasClass, x, y, w, h] for one Digimon action, read from data.bin."""
    sections = json.load(open(os.path.join(BUILD, "data_index.json")))["sections"]
    blob = open(os.path.join(BUILD, "data.bin"), "rb").read()
    base = sections["entries"]["offset"] + index * ENTRY_SIZE
    fields = ENTRY.unpack_from(blob, base)
    ref = fields[15 + action * 5: 20 + action * 5]
    if ref[0] == NO_SPRITE:
        raise SystemExit(f"digimon {index} has no art for action {action}")
    return ref


def main():
    if len(sys.argv) not in (3, 4):
        raise SystemExit(__doc__)
    frame_path = sys.argv[1]
    index = int(sys.argv[2])
    action = int(sys.argv[3]) if len(sys.argv) == 4 else 0

    cls, sx, sy, w, h = sprite_ref(index, action)
    frame = Image.open(frame_path).convert("RGB").load()
    atlas = Image.open(app("resources", "drawables", ATLAS_FILE[cls])).convert("RGB").load()

    bad = []
    for r in range(h):
        for c in range(w):
            drawn = sum(frame[ORIGIN + SCALE * c + SCALE // 2,
                              ORIGIN + SCALE * r + SCALE // 2]) < INK_SUM
            want = sum(atlas[sx + c, sy + r]) < INK_SUM
            if drawn != want:
                bad.append((r, c, int(drawn), int(want)))

    total = w * h
    print(f"digimon {index} action {action}: class {cls} at ({sx},{sy}) {w}x{h}")
    for r, c, drawn, want in bad[:20]:
        print(f"  row {r:2d} col {c:2d}: drawn={drawn} want={want}")
    if len(bad) > 20:
        print(f"  ... and {len(bad) - 20} more")
    print(f"{total - len(bad)}/{total} pixels match")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
