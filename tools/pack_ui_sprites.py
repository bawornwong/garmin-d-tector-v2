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
ANIMATIONS_CS = "Assets/Scripts/Logic/Data/Animations.cs"
DIGIMON_DB = "Assets/Resources/digimonDB.json"

# The actions GetDigimonSprite can ask for, and the suffix each one uses.
SPRITE_ACTIONS = [("", "Default"), ("_at", "Attack"), ("_cr", "Crush"),
                  ("_sp", "Spirit"), ("_sm", "SpiritSmall"), ("_bl", "Black")]

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


def code_named_sprites(index):
    """Art the C# fetches by name for something that is not a Digimon row.

    `GetDigimonSprite("jackpot")` is the only case: the Jackpot Box draws from
    the Digimon sheet but has no row in digimonDB.json, so the port cannot
    reach it through an index (ADR 7). Its cells become named constants here,
    resolved at build time like every other UI sprite.
    """
    rows = {r["name"].lower() for r in json.load(open(src(DIGIMON_DB)))}
    anims = open(src(ANIMATIONS_CS), encoding="utf-8-sig", errors="replace").read()
    names = []
    for name in re.findall(r'GetDigimonSprite\("(\w+)"', anims):
        if name.lower() not in rows and name not in names:
            names.append(name)

    out = []
    for name in names:
        for suffix, action in SPRITE_ACTIONS:
            key = "Digimon/" + name + suffix
            if key not in index:
                continue
            e = index[key]
            out.append((name.upper() + ("" if action == "Default" else "_" + action.upper()),
                        [ATLAS_CLASS[e["atlas"]], e["x"], e["y"], e["w"], e["h"]],
                        key))
    return out


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
    names = {}             # SpriteDatabase field name -> cell, for the verifier
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
                names[name] = cell
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
                    names[f"{name}_{i}"] = cell
                    cells.append(str(cell))
            if not cells:
                missing.append(name)
            body = ",\n            ".join(cells)
            lines.append(f"        const {const_name(name)} = [")
            lines.append(f"            {body}")
            lines.append("        ];")

    named = code_named_sprites(index)
    if named:
        lines += [
            "",
            "        // Art the C# fetches by name for something with no Digimon",
            "        // row -- the Jackpot Box. Resolved here so nothing addresses",
            "        // a sprite by name at runtime (ADR 7).",
        ]
        for const, cell, key in named:
            resolved += 1
            names[key.split("/")[-1]] = cell
            lines.append(f"        const {const} = {cell};   // {key}")

    # No reverse name table: the port prints a sprite as its CELL, and
    # verify_anim.py canonicalises the reference's field names to cells
    # anyway. Carrying 218 names cost the debug build several kilobytes of a
    # 786 KB budget that is nearly spent, and bought nothing the diff uses.
    lines += [
        "        // A sprite prints as its cell. The original prints a",
        "        // SpriteDatabase field name instead; verify_anim.py maps those",
        "        // to cells, so both sides of a diff say the same thing.",
        "        (:debug)",
        "        function nameOf(ref as Array<Number>?) as String {",
        '            if (ref == null) { return "null"; }',
        '            return "sprite(" + ref[0] + "," + ref[1] + "," + ref[2] + ")";',
        "        }",
    ]
    lines += ["    }", "}", ""]
    open(app_path("source/Render/SpriteDatabase.mc"), "w").write("\n".join(lines))

    # The field-name table the port no longer carries. tools/verify_anim.py
    # needs it to canonicalise what the C# reference prints; the device does
    # not, and it was several kilobytes of a debug build.
    json.dump(names, open(os.path.join(BUILD, "ui_sprite_names.json"), "w"),
              indent=1, sort_keys=True)

    print(f"wrote app/source/Render/SpriteDatabase.mc "
          f"({len(fields)} fields, {resolved} sprites resolved) "
          f"and build/ui_sprite_names.json")
    if missing:
        print(f"  {len(missing)} unassigned in the scene: {', '.join(missing[:12])}"
              + (" ..." if len(missing) > 12 else ""))


if __name__ == "__main__":
    main()
