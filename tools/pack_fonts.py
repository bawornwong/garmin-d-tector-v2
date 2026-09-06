#!/usr/bin/env python3
"""Production font packer. Implements ticket 15:

  - extracts the three bitmap faces (Big, Regular, Small) from their
    .fontsettings UV rects, in game pixels (Unity units / PIXEL_SIZE)
  - glyph art lives in the alpha channel; same alpha+luma threshold as sprites
  - each face packs as ONE tight strip (natural glyph widths, no cell padding)
    baked with the same 2-colour palette as the sprite atlases
  - round-trip verified

Outputs:
  app/resources/drawables/font_<face>.png
  build/font_index.json   - per face: lineSpacing, convertCase, glyphs[]
                             (char, x, w, h, advance)
"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import (src, app as app_path, load_mask, bake, new_atlas,
                    save_atlas, unbake_to_mask)
from PIL import Image

BUILD = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "build")
UNIT = 24  # Constants.PIXEL_SIZE

GLYPH_RE = re.compile(
    r'index: (\d+)\s*\n\s*uv:\s*\n\s*serializedVersion: 2\s*\n'
    r'\s*x: ([-\d.]+)\s*\n\s*y: ([-\d.]+)\s*\n\s*width: ([-\d.]+)\s*\n\s*height: ([-\d.]+)\s*\n'
    r'\s*vert:\s*\n\s*serializedVersion: 2\s*\n'
    r'\s*x: ([-\d.]+)\s*\n\s*y: ([-\d.]+)\s*\n\s*width: ([-\d.]+)\s*\n\s*height: ([-\d.]+)\s*\n'
    r'\s*advance: ([-\d.]+)', re.S)


def extract_face(face, sheet_name):
    text = open(src("Assets/Fonts", face + ".fontsettings"),
                encoding="utf-8-sig", errors="replace").read()
    hdr = dict(re.findall(r'm_(\w+): (\S+)', text))
    png = src("Assets/Sprites", sheet_name + ".png")
    W, H = Image.open(png).size

    glyphs = []
    for gm in GLYPH_RE.findall(text):
        idx = int(gm[0])
        ux, uy, uw, uh = (float(v) for v in gm[1:5])
        vx, vy, vw, vh = (float(v) for v in gm[5:9])
        adv = float(gm[9])
        x = round(ux * W)
        y = round((1.0 - uy - uh) * H)  # Unity UV origin bottom-left; PIL top-left
        w, h = round(uw * W), round(uh * H)
        # vert is the glyph's box relative to the text cursor, in Unity units,
        # y growing upward: y = 0 means the glyph's top sits on the line's top.
        # It is NOT decoration -- Big's letters carry y = -48 (2 px) against
        # the digits' 0, so a face whose glyphs differ in height would render
        # its letters 2 px too high if this were dropped.
        if round(vx / UNIT) != 0:
            raise SystemExit(f"{face} glyph {chr(idx)!r} has a nonzero vert.x "
                             f"({vx}); the renderer assumes no x bearing")
        mask = load_mask(png, (x, y, x + w, y + h))
        inked = any(mask.get_flattened_data())
        # The uv rect (where the art is) and the vert rect (how big it draws)
        # agree for every glyph that has ink; only the blank space glyph of
        # Regular and Small differs (uv 5x5, vert 4x5), and nothing is drawn
        # from it -- a space is pure advance. A disagreement on an inked glyph
        # would mean Unity scales that glyph, which the renderer does not do,
        # so it is a build failure rather than a comment.
        if inked and (round(vw / UNIT) != w or round(-vh / UNIT) != h):
            raise SystemExit(f"{face} glyph {chr(idx)!r}: vert box "
                             f"{vw / UNIT}x{-vh / UNIT} != uv box {w}x{h}")
        glyphs.append(dict(char=chr(idx), code=idx, w=w, h=h,
                            advance_px=adv / UNIT, offsetY_px=-vy / UNIT,
                            inked=inked, mask=mask))

    glyphs.sort(key=lambda g: g["code"])
    return dict(
        glyphs=glyphs,
        lineSpacing_px=float(hdr["LineSpacing"]) / UNIT,
        convertCase=hdr["ConvertCase"] == "1",
    )


def pack_strip(face_data):
    glyphs = face_data["glyphs"]
    H = max(g["h"] for g in glyphs)
    W = sum(g["w"] for g in glyphs)
    atlas = new_atlas(W, H)

    x = 0
    packed_glyphs = []
    for g in glyphs:
        atlas.paste(bake(g["mask"]), (x, 0))
        packed_glyphs.append(dict(char=g["char"], code=g["code"], x=x, w=g["w"],
                                   h=g["h"], advance_px=g["advance_px"],
                                   offsetY_px=g["offsetY_px"]))
        x += g["w"]
    return atlas, packed_glyphs


def verify(atlas, packed_glyphs, glyphs_by_code):
    bad = []
    for pg in packed_glyphs:
        g = glyphs_by_code[pg["code"]]
        got = unbake_to_mask(atlas.crop((pg["x"], 0, pg["x"] + pg["w"], pg["h"])))
        if list(got.get_flattened_data()) != list(g["mask"].get_flattened_data()):
            bad.append(pg["char"])
    return bad


FIRST_CODE = 32       # every glyph in all three faces falls in 32..90
LAST_CODE = 90


def write_monkeyc(out):
    """Emit the metrics as Monkey C source (ADR 12: generated, not transcribed).

    A flat Number array per face, five entries per character code from 32 to
    90 -- x in the strip, width, height, advance, and the vertical bearing
    that drops Big's letters 2 px below its digits -- with x = -1 for a code
    the face has no glyph for. Flat because a nested array would cost an object
    per glyph, and dense because the whole range is 59 codes: the faces cover
    space, '!', the digits and A-Z and nothing else, which is why the renderer
    skips anything it cannot draw (ADR 10).
    """
    lines = [
        "import Toybox.Lang;",
        "",
        "// GENERATED by tools/pack_fonts.py from the three .fontsettings --",
        "// do not edit. Regenerate with `tools/pack_fonts.py`.",
        "//",
        "// Metrics are in game pixels (Unity units / 24). The renderer scales",
        "// by 10 when it draws, exactly as it does for sprites.",
        "module Kaisa {",
        "    module Font {",
    ]
    faces = ["Big", "Regular", "Small"]
    for i, face in enumerate(faces):
        lines.append(f"        const {face.upper()} = {i};")
    lines += [
        f"        const FIRST_CODE = {FIRST_CODE};",
        f"        const LAST_CODE = {LAST_CODE};",
        "        const FIELDS = 5;      // x, w, h, advance, offsetY",
        "",
        "        // AtlasCache class ids for the three font strips.",
        "        const ATLAS_CLASS = [%s];"
        % ", ".join(str(4 + i) for i in range(len(faces))),
        "        const LINE_SPACING = [%s];"
        % ", ".join(str(int(out[f]["lineSpacing_px"])) for f in faces),
        "        // Every face has ConvertCase: upper in its .fontsettings, so",
        "        // the renderer uppercases before looking a character up.",
        "        const CONVERT_CASE = [%s];"
        % ", ".join("true" if out[f]["convertCase"] else "false" for f in faces),
        "",
    ]

    for face in faces:
        by_code = {g["code"]: g for g in out[face]["glyphs"]}
        cells = []
        for code in range(FIRST_CODE, LAST_CODE + 1):
            g = by_code.get(code)
            if g is None:
                cells.append("-1, 0, 0, 0, 0")
            else:
                cells.append(f'{g["x"]}, {g["w"]}, {g["h"]}, '
                             f'{int(g["advance_px"])}, {int(g["offsetY_px"])}')
        body = ",\n            ".join(cells)
        lines.append(f"        const GLYPHS_{face.upper()} = [")
        lines.append(f"            {body}")
        lines.append("        ];")
        lines.append("")

    lines += [
        "        function glyphs(face as Number) as Array<Number> {",
        "            if (face == BIG) { return GLYPHS_BIG; }",
        "            if (face == REGULAR) { return GLYPHS_REGULAR; }",
        "            return GLYPHS_SMALL;",
        "        }",
        "    }",
        "}",
        "",
    ]
    path = app_path("source/Render/FontMetrics.mc")
    open(path, "w").write("\n".join(lines))
    glyph_total = sum(len(out[f]["glyphs"]) for f in faces)
    print(f"wrote app/source/Render/FontMetrics.mc ({glyph_total} glyphs, "
          f"{(LAST_CODE - FIRST_CODE + 1) * 5 * len(faces)} table entries)")


def main():
    faces = {
        "Big": extract_face("Big", "font_big"),
        "Regular": extract_face("Regular", "font_regular"),
        "Small": extract_face("Small", "font_small"),
    }

    out = {}
    total_bytes = 0
    for face, data in faces.items():
        atlas, packed = pack_strip(data)
        glyphs_by_code = {g["code"]: g for g in data["glyphs"]}
        bad = verify(atlas, packed, glyphs_by_code)
        if bad:
            print(f"  ROUND-TRIP FAILURE in font {face}: {bad}")
            sys.exit(1)

        fname = f"font_{face.lower()}"
        save_atlas(atlas, app_path("resources/drawables", fname + ".png"))
        b = atlas.size[0] * atlas.size[1] // 8
        total_bytes += b
        print(f"  {face:8s} {len(packed):3d} glyphs  strip {atlas.size[0]}x{atlas.size[1]}px  "
              f"{b} bytes @1bpp  lineSpacing={data['lineSpacing_px']}px  round-trip OK")

        out[face] = dict(
            resource=fname,
            lineSpacing_px=data["lineSpacing_px"],
            convertCase=data["convertCase"],
            glyphs=packed,
        )

    for face, data in out.items():
        for g in data["glyphs"]:
            if not (FIRST_CODE <= g["code"] <= LAST_CODE):
                print(f"  glyph {g['char']!r} (code {g['code']}) in {face} is "
                      f"outside the {FIRST_CODE}..{LAST_CODE} table range")
                sys.exit(1)
            for field in ("advance_px", "offsetY_px"):
                if g[field] != int(g[field]):
                    print(f"  glyph {g['char']!r} in {face} has a fractional "
                          f"{field} ({g[field]}); the table stores Numbers")
                    sys.exit(1)

    json.dump(out, open(os.path.join(BUILD, "font_index.json"), "w"), indent=1)
    print(f"\nTOTAL: {total_bytes} bytes @1bpp across 3 face atlases")
    print("wrote build/font_index.json")
    write_monkeyc(out)


if __name__ == "__main__":
    main()
