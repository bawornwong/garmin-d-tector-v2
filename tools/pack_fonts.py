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
    r'\s*vert:.*?\n\s*advance: ([-\d.]+)', re.S)


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
        adv = float(gm[5])
        x = round(ux * W)
        y = round((1.0 - uy - uh) * H)  # Unity UV origin bottom-left; PIL top-left
        w, h = round(uw * W), round(uh * H)
        mask = load_mask(png, (x, y, x + w, y + h))
        glyphs.append(dict(char=chr(idx), code=idx, w=w, h=h,
                            advance_px=adv / UNIT, mask=mask))

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
                                   h=g["h"], advance_px=g["advance_px"]))
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

    json.dump(out, open(os.path.join(BUILD, "font_index.json"), "w"), indent=1)
    print(f"\nTOTAL: {total_bytes} bytes @1bpp across 3 face atlases")
    print("wrote build/font_index.json")


if __name__ == "__main__":
    main()
