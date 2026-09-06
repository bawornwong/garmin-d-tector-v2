#!/usr/bin/env python3
"""Production data packer. Implements ADR 6/7 + ticket 12:

  - digimonDB.json + frontier_rarities.json fold into one positional record
    per Digimon (frontier_rarities is parallel to digimonDB - same 593
    entries), keyed by digimonDB.json ORDER, never by name
  - each record also carries its six sprite-action cell refs, built from
    build/sprite_index.json (tools/pack_sprites.py output) - this is the
    "one row order shared by three tables" decision (ADR 7)
  - worlds/areas/bosses/semibosses, and the starter-Digimon list, pack too
  - output is one binary blob, base64'd across string resources (a
    <jsonData> resource costs 5.06 bytes/number on this device; a string
    resource costs 1.00 byte/char - see ticket 12)
  - every record is read back from the blob and diffed against the source
    JSON before anything is written

Outputs:
  build/data.bin
  app/resources/strings/data_strings.xml
  build/data_index.json   - human-readable manifest (offsets/sizes) for
                             the Monkey C reader to be written against
"""
import base64
import json
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import src, app as app_path

BUILD = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "build")

ATLAS_CODE = {"atlas_24x24": 0, "atlas_32x32": 1, "atlas_14x16": 2, "atlas_odd": 3}
NO_SPRITE = 0xFF
ACTIONS = [("base", ""), ("at", "_at"), ("cr", "_cr"), ("sp", "_sp"),
           ("sm", "_sm"), ("bl", "_bl")]

ENTRY = struct.Struct(
    "<HHBBBBBBhHHHHBB" +  # 22-byte core record (ticket 12)
    "BHHBB" * 6)          # 6 x (atlasClass, x, y, w, h) sprite refs = 42 bytes
ENTRY_SIZE = ENTRY.size
assert ENTRY_SIZE == 22 + 42, ENTRY_SIZE


def strtable(items):
    """u16 count, (count+1) x u16 offsets, then the concatenated ascii bytes."""
    blob, offs = b"", []
    for s in items:
        offs.append(len(blob))
        blob += s.encode("ascii")
    offs.append(len(blob))
    return struct.pack("<H", len(items)) + b"".join(struct.pack("<H", o) for o in offs) + blob


def main():
    db = json.load(open(src("Assets/Resources/digimonDB.json")))
    rar = {e["digimon"]: e for e in json.load(open(src("Assets/Resources/frontier_rarities.json")))}
    worlds = json.load(open(src("Assets/Resources/worlds.json")))
    initials = json.load(open(src("Assets/Resources/initials.json")))
    sprite_index = json.load(open(os.path.join(BUILD, "sprite_index.json")))["sprites"]

    name_to_index = {e["name"]: i for i, e in enumerate(db)}
    abilities = sorted({e["abilityName"] for e in db if e["abilityName"]})
    ability_index = {a: i for i, a in enumerate(abilities)}
    assert len(abilities) <= 255

    def sprite_ref(key):
        """key like 'Digimon/agumon_at' -> (atlasClass, x, y, w, h) or the
        'no sprite' sentinel if this action doesn't exist for this Digimon."""
        e = sprite_index.get(key)
        if e is None:
            return (NO_SPRITE, 0, 0, 0, 0)
        return (ATLAS_CODE[e["atlas"]], e["x"], e["y"], e["w"], e["h"])

    records = b""
    for e in db:
        st = e["stats"] or {}
        flags = ((1 if e["disabled"] else 0) | (2 if e["isPseudo"] else 0)
                 | (4 if e["HasBossStats"] else 0))
        evo = name_to_index.get(e["evolution"], -1) if e["evolution"] else -1
        rr = rar.get(e["name"], {})
        core = (
            e["number"], e["order"], e["stage"], e["spiritType"], e["element"],
            min(e["baseLevel"], 255), flags, ability_index.get(e["abilityName"], 255),
            evo, st.get("HP", 0), st.get("EN", 0), st.get("CR", 0), st.get("AB", 0),
            rr.get("rarity", 0), 1 if rr.get("exclusive") else 0)
        sprite_refs = []
        for _, suffix in ACTIONS:
            sprite_refs.extend(sprite_ref(f"Digimon/{e['name']}{suffix}"))
        records += ENTRY.pack(*core, *sprite_refs)

    names = strtable([e["name"] for e in db])
    codes = b"".join((e["code"] or "").encode("ascii").ljust(5, b"\0") for e in db)
    ability_names = strtable(abilities)

    # per-ability sprite ref (Abilities/<name>)
    ability_sprites = b""
    for a in abilities:
        ability_sprites += struct.pack("<BHHBB", *sprite_ref(f"Abilities/{a}"))

    # energy sprite refs, rank 0-15 (Energies/energy_<rank>)
    energy_sprites = b""
    for rank in range(16):
        energy_sprites += struct.pack("<BHHBB", *sprite_ref(f"Energies/energy_{rank}"))

    # extraEvolutions: sparse
    extra = b""
    extra_idx = []
    for i, e in enumerate(db):
        lst = e["extraEvolutions"] or []
        if not lst:
            continue
        extra_idx.append((i, len(extra)))
        extra += struct.pack("<B", len(lst))
        for n in lst:
            extra += struct.pack("<h", name_to_index.get(n, -1))
    extra_table = struct.pack("<H", len(extra_idx))
    extra_table += b"".join(struct.pack("<HH", i, o) for i, o in extra_idx) + extra

    # bossStats: sparse
    bosses_stats = [(i, e["bossStats"]) for i, e in enumerate(db) if e["bossStats"]]
    boss_stats_table = struct.pack("<H", len(bosses_stats))
    for i, bs in bosses_stats:
        boss_stats_table += struct.pack("<HHHHH", i, bs["HP"], bs["EN"], bs["CR"], bs["AB"])

    # worlds: number, multiMap, shuffle, removePlayer, semibossMode(0=None,1=Fill,2=Gank,3=Pseudo),
    #   worldSprite(Maps/<worldSprite>_<map> ref per area's map, resolved lazily by the reader),
    #   areas[{number,map,distance,x,y}], bosses[][ (as digimon indices, variable length per slot)],
    #   semibosses[][ digimon indices ]
    SEMIBOSS_MODE = {None: 0, "Fill": 1, "Gank": 2, "Pseudo": 3}
    wblob = struct.pack("<H", len(worlds))
    for w in worlds:
        areas = w["areas"]
        bosses = w.get("bosses") or []
        semibosses = w.get("semibosses") or []
        wblob += struct.pack("<BBBBB", w["number"], 1 if w["multiMap"] else 0,
                              1 if w.get("shuffle") else 0,
                              1 if w.get("removePlayer") else 0,
                              SEMIBOSS_MODE.get(w.get("semibossMode"), 0))
        wblob += struct.pack("<B", len(areas))
        for a in areas:
            wblob += struct.pack("<BBIBB", a["number"], a["map"], a["distance"],
                                  a["coords"]["x"], a["coords"]["y"])
        wblob += struct.pack("<B", len(bosses))
        for slot in bosses:
            names_ = slot if isinstance(slot, list) else [slot]
            wblob += struct.pack("<B", len(names_))
            for n in names_:
                wblob += struct.pack("<h", name_to_index.get(n, -1))
        wblob += struct.pack("<B", len(semibosses))
        for grp in semibosses:
            names_ = grp if isinstance(grp, list) else [grp]
            wblob += struct.pack("<B", len(names_))
            for n in names_:
                wblob += struct.pack("<h", name_to_index.get(n, -1))

    init_blob = struct.pack("<H", len(initials))
    init_blob += b"".join(struct.pack("<H", name_to_index[n]) for n in initials)

    sections = [
        ("entries", records), ("names", names), ("codes", codes),
        ("abilities", ability_names), ("abilitySprites", ability_sprites),
        ("energySprites", energy_sprites), ("extraEvo", extra_table),
        ("bossStats", boss_stats_table), ("worlds", wblob), ("initials", init_blob),
    ]

    header = struct.pack("<H", len(sections))
    body = b""
    offsets = []
    base_off = 2 + len(sections) * 8
    for _, blob in sections:
        offsets.append((base_off + len(body), len(blob)))
        body += blob
    for off, ln in offsets:
        header += struct.pack("<II", off, ln)
    packed = header + body

    open(os.path.join(BUILD, "data.bin"), "wb").write(packed)

    section_names = [n for n, _ in sections]
    json.dump({"sections": dict(zip(section_names, [
        dict(offset=o, length=l) for o, l in offsets])),
        "entrySize": ENTRY_SIZE, "digimonCount": len(db),
        "abilityCount": len(abilities)},
        open(os.path.join(BUILD, "data_index.json"), "w"), indent=1)

    print(f"{'section':16s} {'bytes':>8s}")
    for (n, _), (o, l) in zip(sections, offsets):
        print(f"{n:16s} {l:8,d}")
    print(f"{'TOTAL':16s} {len(packed):8,d}")

    json_total = sum(os.path.getsize(src("Assets/Resources", f)) for f in
                      ["digimonDB.json", "frontier_rarities.json", "worlds.json", "initials.json"])
    print(f"\nsource JSON {json_total:,} bytes -> packed {len(packed):,} bytes "
          f"({len(packed)/json_total*100:.1f}%)")

    b64 = base64.b64encode(packed).decode("ascii")
    CHUNK = 32000
    chunks = [b64[i:i + CHUNK] for i in range(0, len(b64), CHUNK)]
    # GameData.mc's loadDataChunk() has a fixed, hardcoded list of resource
    # IDs (Monkey C has no dynamic String->Symbol lookup, by design - see
    # ticket 05/12) - so every slot up to MAX_CHUNKS must exist as a real
    # resource, even if this build does not need it, or the build fails
    # with an undefined-symbol error rather than a data-dependent one.
    MAX_CHUNKS = 5
    assert len(chunks) <= MAX_CHUNKS, (
        f"data blob needs {len(chunks)} string chunks; GameData.mc's "
        f"loadDataChunk() only lists {MAX_CHUNKS} - raise MAX_CHUNKS in both places")
    while len(chunks) < MAX_CHUNKS:
        chunks.append("")
    with open(app_path("resources/strings/data_strings.xml"), "w") as f:
        f.write("<strings>\n")
        for i, c in enumerate(chunks):
            f.write(f'    <string id="Data{i}">{c}</string>\n')
        f.write("</strings>\n")
    real_chunks = sum(1 for c in chunks if c != "")
    print(f"base64: {len(b64):,} chars across {real_chunks} string resources "
          f"(padded to {MAX_CHUNKS} slots)")

    # --- verification: read every record back and diff against the source
    verify(packed, db, rar, ability_index, name_to_index)


def verify(packed, db, rar, ability_index, name_to_index):
    off = 0
    n_sections, = struct.unpack_from("<H", packed, 0)
    sec_off = {}
    for i in range(n_sections):
        o, l = struct.unpack_from("<II", packed, 2 + i * 8)
        sec_off[i] = (o, l)
    entries_off = sec_off[0][0]

    bad = 0
    for i, e in enumerate(db):
        vals = ENTRY.unpack_from(packed, entries_off + i * ENTRY_SIZE)
        core = vals[:15]
        st = e["stats"] or {}
        rr = rar.get(e["name"], {})
        flags = ((1 if e["disabled"] else 0) | (2 if e["isPseudo"] else 0)
                 | (4 if e["HasBossStats"] else 0))
        evo = name_to_index.get(e["evolution"], -1) if e["evolution"] else -1
        expect = (e["number"], e["order"], e["stage"], e["spiritType"], e["element"],
                  min(e["baseLevel"], 255), flags, ability_index.get(e["abilityName"], 255),
                  evo & 0xFFFF if evo < 0 else evo,
                  st.get("HP", 0), st.get("EN", 0), st.get("CR", 0), st.get("AB", 0),
                  rr.get("rarity", 0), 1 if rr.get("exclusive") else 0)
        # evo is packed as signed 'h', unpacked value is already signed - compare directly
        expect = list(expect)
        expect[8] = evo
        got = list(core)
        if got != expect:
            bad += 1
            if bad <= 5:
                print(f"  MISMATCH #{i} {e['name']}: got={got} want={expect}")
    if bad:
        print(f"\nVERIFICATION FAILED: {bad}/{len(db)} records mismatched")
        sys.exit(1)
    print(f"\nverification: {len(db)}/{len(db)} records, {len(db)*15:,} core fields, 0 mismatches")


if __name__ == "__main__":
    main()
