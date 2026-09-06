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
  - a sprite drawn from the old baked two-colour atlas painting its own field
    over whatever was beneath it, which this check now catches because the
    field pixels it expects are the ones the screen already had.
  - drawBitmap2 offsetting the destination by T * (bitmapX, bitmapY) when a
    :transform is set, which put the sprite 1,200 px off-screen.

Usage:
    tools/verify_render.py <frame.png> <digimon index> [action] [--inverted]

Build the app with DTectorView._probeIndex set to the same index first: that
makes the view draw the Digimon's base sprite alone, at the position below.
With --inverted, set DTectorView._probeInvert too: the sprite is then drawn
LCD-coloured on a black box, which checks the other two things the atlas
rewrite bought -- that ink can be tinted to any colour, and that the field
composites (a field pixel must still be the black of the box, not the LCD
green the old baked atlas carried in the art itself).
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
    argv = [a for a in sys.argv[1:] if a != "--inverted"]
    inverted = "--inverted" in sys.argv
    if len(argv) not in (2, 3):
        raise SystemExit(__doc__)
    frame_path = argv[0]
    index = int(argv[1])
    action = int(argv[2]) if len(argv) == 3 else 0

    cls, sx, sy, w, h = sprite_ref(index, action)
    frame = Image.open(frame_path).convert("RGB").load()
    # The atlas stores white ink on a TRANSPARENT field and the ink colour is
    # applied by the device as a tint, so what says "this pixel is ink" in the
    # atlas is its alpha, not its colour (ADR 3).
    atlas = Image.open(app("resources", "drawables", ATLAS_FILE[cls])).convert("RGBA").load()

    # A pixel is read as "dark" or "light"; which of those an ink pixel should
    # be depends on the probe. Normal: ink is black on the LCD field. Inverted:
    # ink is LCD-coloured on a black box, so the test flips.
    bad = []
    for r in range(h):
        for c in range(w):
            dark = sum(frame[ORIGIN + SCALE * c + SCALE // 2,
                             ORIGIN + SCALE * r + SCALE // 2]) < INK_SUM
            is_ink = atlas[sx + c, sy + r][3] > 0
            want_dark = (not is_ink) if inverted else is_ink
            if dark != want_dark:
                bad.append((r, c, int(dark), int(want_dark)))

    total = w * h
    print(f"digimon {index} action {action}: class {cls} at ({sx},{sy}) {w}x{h}"
          + (" [inverted]" if inverted else ""))
    for r, c, dark, want in bad[:20]:
        print(f"  row {r:2d} col {c:2d}: dark={dark} want={want}")
    if len(bad) > 20:
        print(f"  ... and {len(bad) - 20} more")
    print(f"{total - len(bad)}/{total} pixels match")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
