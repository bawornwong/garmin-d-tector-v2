#!/usr/bin/env python3
"""Decode the packed worlds section and diff it against worlds.json.

The worlds section is the most awkward thing in the blob: variable-length,
nested three deep, and read on the device by walking it (a world's offset
depends on how many areas and bosses the worlds before it have). A packer or
reader bug there does not crash -- it silently yields a plausible wrong area,
boss or map sprite.

So this decodes the section exactly as GameData.mc does, and compares every
field with the source JSON: the flags, each area's number/map/distance/coords,
each boss slot and semiboss group as Digimon indices, and the four map sprite
refs against the sprite index.

Usage:
    DTECTOR_SRC=/path/to/D-Tector-v2 tools/verify_worlds.py
"""
import json
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import src

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD = os.path.join(ROOT, "build")
SEMIBOSS_MODE = {None: 0, "Fill": 1, "Gank": 2, "Pseudo": 3, "Deva": 4}
BOSS_MODE = {None: 0, "Evolve": 0, "UseBurst": 1}
ATLAS_CODE = {"atlas_24x24": 0, "atlas_32x32": 1, "atlas_14x16": 2, "atlas_odd": 3}
NO_SPRITE = 0xFF
WORLD_HEADER = 8 + 4 * 7


def read_world_section():
    sections = json.load(open(os.path.join(BUILD, "data_index.json")))["sections"]
    blob = open(os.path.join(BUILD, "data.bin"), "rb").read()
    off = sections["worlds"]["offset"]
    count = struct.unpack_from("<H", blob, off)[0]
    o = off + 2

    worlds = []
    for _ in range(count):
        (number, multi, shuffle, remove, mode, eyes, lock,
         boss_mode) = struct.unpack_from("<BBBBBBBB", blob, o)
        maps = []
        for m in range(4):
            base = o + 8 + m * 7
            cls = blob[base]
            if cls == NO_SPRITE:
                maps.append(None)
            else:
                x, y = struct.unpack_from("<HH", blob, base + 1)
                maps.append([cls, x, y, blob[base + 5], blob[base + 6]])
        o += WORLD_HEADER

        area_count = blob[o]; o += 1
        areas = []
        for _ in range(area_count):
            n, mp, dist, x, y = struct.unpack_from("<BBIBB", blob, o)
            areas.append(dict(number=n, map=mp, distance=dist, x=x, y=y))
            o += 8

        boss_count = blob[o]; o += 1
        bosses = []
        for _ in range(boss_count):
            nc = blob[o]; o += 1
            bosses.append([struct.unpack_from("<h", blob, o + i * 2)[0] for i in range(nc)])
            o += nc * 2

        semi_count = blob[o]; o += 1
        semibosses = []
        for _ in range(semi_count):
            nc = blob[o]; o += 1
            semibosses.append([struct.unpack_from("<h", blob, o + i * 2)[0] for i in range(nc)])
            o += nc * 2

        worlds.append(dict(number=number, multiMap=multi, shuffle=shuffle,
                           removePlayer=remove, semibossMode=mode, showEyes=eyes,
                           lockTravel=lock, bossMode=boss_mode,
                           maps=maps, areas=areas, bosses=bosses,
                           semibosses=semibosses))
    return worlds


def main():
    source = json.load(open(src("Assets/Resources/worlds.json")))
    db = json.load(open(src("Assets/Resources/digimonDB.json")))
    index_of = {d["name"].lower(): i for i, d in enumerate(db)}
    sprites = json.load(open(os.path.join(BUILD, "sprite_index.json")))["sprites"]
    packed = read_world_section()

    bad = []

    def check(where, got, want):
        if got != want:
            bad.append(f"{where}: packed {got!r} != source {want!r}")

    check("world count", len(packed), len(source))

    for w, (p, s) in enumerate(zip(packed, source)):
        check(f"world {w} number", p["number"], s["number"])
        check(f"world {w} multiMap", p["multiMap"], 1 if s["multiMap"] else 0)
        check(f"world {w} shuffle", p["shuffle"], 1 if s.get("shuffle") else 0)
        check(f"world {w} removePlayer", p["removePlayer"], 1 if s.get("removePlayer") else 0)
        check(f"world {w} semibossMode", p["semibossMode"],
              SEMIBOSS_MODE.get(s.get("semibossMode"), 0))
        check(f"world {w} showEyes", p["showEyes"], 1 if s.get("showEyes") else 0)
        check(f"world {w} lockTravel", p["lockTravel"], 1 if s.get("lockTravel") else 0)
        check(f"world {w} bossMode", p["bossMode"], BOSS_MODE.get(s.get("bossMode"), 0))

        for m in range(4):
            e = sprites.get(f"Maps/{s['worldSprite']}_{m}")
            want = None if e is None else [ATLAS_CODE[e["atlas"]], e["x"], e["y"],
                                           e["w"], e["h"]]
            check(f"world {w} map sprite {m}", p["maps"][m], want)

        check(f"world {w} area count", len(p["areas"]), len(s["areas"]))
        for a, (pa, sa) in enumerate(zip(p["areas"], s["areas"])):
            check(f"world {w} area {a}",
                  [pa["number"], pa["map"], pa["distance"], pa["x"], pa["y"]],
                  [sa["number"], sa["map"], sa["distance"],
                   sa["coords"]["x"], sa["coords"]["y"]])

        s_bosses = s.get("bosses") or []
        check(f"world {w} boss slots", len(p["bosses"]), len(s_bosses))
        for b, (pb, sb) in enumerate(zip(p["bosses"], s_bosses)):
            names = sb if isinstance(sb, list) else [sb]
            check(f"world {w} boss {b}", pb, [index_of.get(n.lower(), -1) for n in names])

        s_semi = s.get("semibosses") or []
        check(f"world {w} semiboss groups", len(p["semibosses"]), len(s_semi))
        for g, (pg, sg) in enumerate(zip(p["semibosses"], s_semi)):
            names = sg if isinstance(sg, list) else [sg]
            check(f"world {w} semiboss {g}", pg, [index_of.get(n.lower(), -1) for n in names])

    for line in bad[:20]:
        print("  " + line)
    if len(bad) > 20:
        print(f"  ... and {len(bad) - 20} more")

    fields = sum(8 + 4 + len(w["areas"]) + len(w["bosses"]) + len(w["semibosses"])
                 for w in packed) + 1
    print(f"{fields - len(bad)}/{fields} world fields match "
          f"({len(packed)} worlds, {sum(len(w['areas']) for w in packed)} areas)")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
