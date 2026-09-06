#!/usr/bin/env python3
"""Resolve SpriteDatabase's inspector wiring into a Monkey C table.

SpriteDatabase.cs declares ~90 named fields -- status_distance, mainMenu[7],
elements[10], battle_combatMenu[5] and so on -- but assigns none of them: the
sprites are wired in the Unity scene, so the names the game's code uses exist
only as inspector references. Nothing in the C# tells you which cell of which
sheet `status_distance` is.

The chain that does, and which this walks:

    SpriteDatabase.cs           field names, and array lengths
    DigiviceFrontier.unity      field -> {fileID, guid} reference
    Assets/Sprites/*.png.meta   guid -> sheet, fileID -> sprite name (the
                                fileIDToRecycleName table)
    build/sprite_index.json     sprite name -> atlas, x, y, w, h

Output: app/source/Render/SpriteDatabase.mc, one constant per field holding
[atlasClass, x, y, w, h] -- the same shape GameData.spriteRef returns, so a
UI sprite and a Digimon sprite are the same thing to the display list.

Run tools/pack_sprites.py first: this reads its index.
"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import src, app as app_path

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD = os.path.join(ROOT, "build")
SCENE = "Assets/Scenes/DigiviceFrontier.unity"
SPRITE_DB_CS = "Assets/Scripts/SpriteDatabase.cs"

ATLAS_CLASS = {"atlas_24x24": 0, "atlas_32x32": 1, "atlas_14x16": 2, "atlas_odd": 3}

FIELD_RE = re.compile(
    r"public\s+Sprite(\[\])?\s+(\w+)\s*(?:=\s*new\s+Sprite\[(\d+)\])?\s*;")
REF_RE = re.compile(r"\{fileID:\s*(-?\d+),\s*guid:\s*([0-9a-f]{32}),\s*type:\s*\d+\}")


def declared_fields():
    """[(name, count)] in declaration order; count is None for scalars."""
    text = open(src(SPRITE_DB_CS), encoding="utf-8-sig", errors="replace").read()
    out = []
    for is_array, name, size in FIELD_RE.findall(text):
        out.append((name, int(size) if size else (0 if is_array else None)))
    return out


def sheet_tables():
    """guid -> (sheet name, {fileID: sprite key})."""
    tables = {}
    sheets_dir = src("Assets/Sprites")
    for meta in sorted(os.listdir(sheets_dir)):
        if not meta.endswith(".png.meta"):
            continue
        sheet = meta[:-9]
        text = open(os.path.join(sheets_dir, meta), encoding="utf-8-sig",
                    errors="replace").read()
        guid = re.search(r"^guid: ([0-9a-f]{32})", text, re.M).group(1)
        # fileIDToRecycleName: "- first:\n    213: <id>\n  second: <name>"
        ids = dict((int(fid), name) for fid, name in
                   re.findall(r"213:\s*(-?\d+)\s*\n\s*second:\s*(\S+)", text))
        tables[guid] = (sheet, ids)
    return tables


def resource_sprites():
    """guid -> sprite key, for the sprites that are their own .png asset."""
    out = {}
    for group in ("Digimon", "Abilities", "Energies", "Maps"):
        d = src("Assets/Resources/Sprites", group)
        for fn in sorted(os.listdir(d)):
            if not fn.endswith(".png.meta"):
                continue
            text = open(os.path.join(d, fn), encoding="utf-8-sig",
                        errors="replace").read()
            m = re.search(r"^guid: ([0-9a-f]{32})", text, re.M)
            if m:
                out[m.group(1)] = f"{group}/{fn[:-9]}"
    return out


def scene_component(fields):
    """The SpriteDatabase component's block of the scene, as {field: [refs]}.

    The component is found by its first field rather than by its script guid:
    the block is plain YAML mapping and every field of interest appears in
    declaration order inside it.
    """
    text = open(src(SCENE), encoding="utf-8-sig", errors="replace").read()
    names = [f[0] for f in fields]
    first = names[0]
    start = text.find(f"\n  {first}:")
    if start < 0:
        raise SystemExit(f"{first} not found in {SCENE}")
    # the block ends at the next top-level document separator
    end = text.find("\n--- !u!", start)
    block = text[start:end if end > 0 else len(text)]

    out = {}
    for i, name in enumerate(names):
        m = re.search(rf"\n  {re.escape(name)}:(.*?)(?=\n  \w+:|\Z)", block, re.S)
        if not m:
            continue
        out[name] = REF_RE.findall(m.group(1))
    return out


def const_name(field, index=None):
    """camelCase / snake_case field -> SCREAMING_SNAKE constant.

    Acronym runs stay together: `battle_gainingSP` is BATTLE_GAINING_SP, not
    BATTLE_GAINING_S_P, which is what a naive split produces and what silently
    left that sprite unreachable until an animation asked for it.
    """
    s = re.sub(r"(?<=[a-z0-9])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])", "_", field)
    s = s.upper().replace("__", "_")
    return s if index is None else f"{s}_{index}"


def main():
    fields = declared_fields()
    sheets = sheet_tables()
    resources = resource_sprites()
    assigned = scene_component(fields)
    index = json.load(open(os.path.join(BUILD, "sprite_index.json")))["sprites"]

    lines = [
        "import Toybox.Lang;",
        "",
        "// GENERATED by tools/pack_ui_sprites.py -- do not edit.",
        "//",
        "// port of SpriteDatabase.cs, whose fields are wired in the Unity",
        "// scene rather than in the C#. Each constant is [atlasClass, x, y, w,",
        "// h], the same shape GameData.spriteRef returns, so the display list",
        "// treats a UI sprite and a Digimon sprite identically.",
        "//",
        "// A field the scene leaves unassigned is emitted as null, and the",
        "// generator prints it: an unassigned sprite is a hole in the port, not",
        "// a detail to discover at runtime.",
        "module Kaisa {",
        "    module Sprites {",
    ]

    resolved = 0
    missing = []
    trace_names = []       # (name the original prints, cell) for the debug table
    for name, count in fields:
        refs = assigned.get(name, [])

        def lookup(ref):
            fid, guid = int(ref[0]), ref[1]
            if guid in sheets:
                key = sheets[guid][1].get(fid)
            else:
                key = resources.get(guid)
            if key is None or key not in index:
                return None
            e = index[key]
            return [ATLAS_CLASS[e["atlas"]], e["x"], e["y"], e["w"], e["h"]]

        if count is None:                       # scalar Sprite
            cell = lookup(refs[0]) if refs else None
            if cell is None:
                missing.append(name)
                lines.append(f"        const {const_name(name)} = null;")
            else:
                resolved += 1
                trace_names.append((name, cell))
                lines.append(f"        const {const_name(name)} = {cell};")
        else:                                   # Sprite[]
            cells = []
            for i, ref in enumerate(refs):
                cell = lookup(ref)
                if cell is None:
                    missing.append(f"{name}[{i}]")
                    cells.append("null")
                else:
                    resolved += 1
                    trace_names.append((f"{name}_{i}", cell))
                    cells.append(str(cell))
            if not cells:
                missing.append(name)
            body = ",\n            ".join(cells)
            lines.append(f"        const {const_name(name)} = [")
            lines.append(f"            {body}")
            lines.append("        ];")

    # The reverse table, debug builds only: the animation golden diffs print a
    # sprite by its SpriteDatabase field name, exactly as the C# reference
    # does, and nothing else in the port ever needs a sprite's name.
    lines += [
        "        // GENERATED reverse lookup, debug only: [atlasClass, x, y, w, h]",
        "        // -> the SpriteDatabase field name the original would print.",
        "        // Array fields print as `field_index`, matching the reference.",
        "        (:debug) const TRACE_NAMES = [",
    ]
    for key, cell in trace_names:
        lines.append(f'            ["{key}", {cell[0]}, {cell[1]}, {cell[2]}],')
    lines += [
        "        ];",
        "",
        "        (:debug)",
        "        function nameOf(ref as Array<Number>?) as String {",
        '            if (ref == null) { return "null"; }',
        "            for (var i = 0; i < TRACE_NAMES.size(); i += 1) {",
        "                var e = TRACE_NAMES[i];",
        "                if (e[1] == ref[0] && e[2] == ref[1] && e[3] == ref[2]) {",
        "                    return e[0];",
        "                }",
        "            }",
        '            return "sprite(" + ref[0] + "," + ref[1] + "," + ref[2] + ")";',
        "        }",
    ]
    lines += ["    }", "}", ""]
    open(app_path("source/Render/SpriteDatabase.mc"), "w").write("\n".join(lines))

    print(f"wrote app/source/Render/SpriteDatabase.mc "
          f"({len(fields)} fields, {resolved} sprites resolved)")
    if missing:
        print(f"  {len(missing)} unassigned in the scene: {', '.join(missing[:12])}"
              + (" ..." if len(missing) > 12 else ""))


if __name__ == "__main__":
    main()
