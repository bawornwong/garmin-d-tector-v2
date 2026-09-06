#!/usr/bin/env python3
"""Diff a captured frame of the text probe against the font metrics.

The counterpart to tools/verify_render.py for text (SPEC section 7's second
outstanding check). verify_render proves the device draws a cell where the
atlas says it is; this proves the text renderer places every glyph where the
.fontsettings say it goes -- the advances, the vertical bearing, the line
spacing, the three anchors, and the skipping of characters no face has.

It rebuilds the whole 320x320 canvas in Python from tools/text_probe.json,
build/font_index.json and the font strip PNGs, and diffs every device pixel --
so a stray glyph, a shifted line, an off-by-one advance or a half-pixel
alignment error all show up, not just the pixels the expectation happens to
look at.

Usage:
    tools/build.sh && tools/verify_text.py <frame.png>

Build the app with DTectorView._probeText = true first.
"""
import json
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import app

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD = os.path.join(ROOT, "build")

SCREEN = 454          # venu445mm
CANVAS = 320          # DTectorView.CANVAS
SCALE = 10            # DTectorView.SCALE
GAME = 32             # Constants.SCREEN_WIDTH / SCREEN_HEIGHT
ORIGIN = (SCREEN - CANVAS) // 2
INK_SUM = 200         # ink sums to ~0; the LCD field to ~394
BOX_HEIGHT = 6        # TextProbe.BOX_HEIGHT


def fill(dark, x, y, w, h, value):
    """Paint one scale x scale block (or a whole rect) into the device canvas,
    clipped to it -- the canvas clips, the text box does not."""
    for yy in range(max(0, int(y)), min(CANVAS, int(y) + h)):
        row = dark[yy]
        for xx in range(max(0, int(x)), min(CANVAS, int(x) + w)):
            row[xx] = value


def glyph_masks(face, meta):
    """char -> PIL '1' mask, cut out of the face's strip by its packed x/w/h."""
    strip = Image.open(app("resources", "drawables", meta["resource"] + ".png"))
    strip = strip.convert("RGBA")
    out = {}
    for g in meta["glyphs"]:
        cell = strip.crop((g["x"], 0, g["x"] + g["w"], g["h"]))
        out[g["char"]] = [[cell.getpixel((cx, cy))[3] > 0 for cx in range(g["w"])]
                          for cy in range(g["h"])]
    return out


def expected_canvas(spec, fonts):
    """The canvas at DEVICE resolution as [is_dark] booleans.

    Device resolution, not game resolution, because centre alignment can land
    a line on a half game pixel: the scene canvas has m_PixelPerfect: 0, so
    Unity centres at the exact half of the leftover width, and at 10x that
    half is five device pixels. A game-pixel grid cannot express it.
    """
    dark = [[False] * CANVAS for _ in range(CANVAS)]

    for s in spec["strings"]:
        meta = fonts[s["face"]]
        by_char = {g["char"]: g for g in meta["glyphs"]}
        masks = glyph_masks(s["face"], meta)
        text = s["text"].upper() if meta["convertCase"] else s["text"]

        if s["inverted"]:
            # The element's background paints ink across its whole rect, and
            # the glyphs then paint the field colour into it.
            fill(dark, s["x"] * SCALE, s["y"] * SCALE,
                 s["w"] * SCALE, BOX_HEIGHT * SCALE, True)

        line_y = s["y"]
        for line in text.split("\n"):
            width = sum(by_char[c]["advance_px"] for c in line if c in by_char)
            if s["anchor"] == 2:
                pen = (s["x"] + s["w"] - width) * SCALE
            elif s["anchor"] == 1:
                pen = s["x"] * SCALE + ((s["w"] - width) * SCALE) // 2
            else:
                pen = s["x"] * SCALE

            for c in line:
                g = by_char.get(c)
                if g is None:
                    continue        # skipped entirely, advance included (ADR 10)
                mask = masks[c]
                top = (line_y + g["offsetY_px"]) * SCALE
                for gy in range(g["h"]):
                    for gx in range(g["w"]):
                        if mask[gy][gx]:
                            fill(dark, int(pen) + gx * SCALE, int(top) + gy * SCALE,
                                 SCALE, SCALE, not s["inverted"])
                pen += g["advance_px"] * SCALE
            line_y += meta["lineSpacing_px"]

    return dark


def main():
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)

    spec = json.load(open(os.path.join(ROOT, "tools", "text_probe.json")))
    fonts = json.load(open(os.path.join(BUILD, "font_index.json")))
    want = expected_canvas(spec, fonts)

    frame = Image.open(sys.argv[1]).convert("RGB").load()

    bad = []
    for dy in range(CANVAS):
        for dx in range(CANVAS):
            drawn = sum(frame[ORIGIN + dx, ORIGIN + dy]) < INK_SUM
            if drawn != want[dy][dx]:
                bad.append((dx, dy, int(drawn), int(want[dy][dx])))

    total = CANVAS * CANVAS
    for dx, dy, drawn, w in bad[:20]:
        print(f"  device ({dx:3d},{dy:3d}) = game ({dx / SCALE:2d},{dy / SCALE:2d}): "
              f"drawn={drawn} want={w}")
    if len(bad) > 20:
        print(f"  ... and {len(bad) - 20} more")
    print(f"{total - len(bad)}/{total} device pixels match "
          f"({len(spec['strings'])} strings)")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
