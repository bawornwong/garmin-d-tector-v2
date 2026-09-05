#!/usr/bin/env python3
"""Packs the game's JSON data into the byte layout the watch reads.

digimonDB.json is 260 KB of JSON. Connect IQ has no binary resource type and
charges 5 bytes per number in a jsonData resource, so the database ships as a
packed byte table carried in base64 string resources and read back with
ByteArray.decodeNumber.

frontier_rarities.json is parallel to digimonDB (same 593 digimon), so it
folds into the main table as two more fields rather than shipping separately.
"""
import base64
import json
import os
import struct
import sys

SRC, OUT = sys.argv[1], sys.argv[2]
os.makedirs(OUT, exist_ok=True)
R = os.path.join(SRC, "Assets/Resources")

db = json.load(open(os.path.join(R, "digimonDB.json")))
rar = json.load(open(os.path.join(R, "frontier_rarities.json")))
worlds = json.load(open(os.path.join(R, "worlds.json")))
initials = json.load(open(os.path.join(R, "initials.json")))

name_to_index = {e["name"]: i for i, e in enumerate(db)}
rarity_by_name = {e["digimon"]: e for e in rar}

abilities = sorted({e["abilityName"] for e in db if e["abilityName"]})
ability_index = {a: i for i, a in enumerate(abilities)}
assert len(abilities) <= 255, len(abilities)


def strtable(items):
    """Length-prefixed string table: u16 count, u16 offsets, then the bytes."""
    blob = b""
    offs = []
    for s in items:
        offs.append(len(blob))
        blob += s.encode("ascii")
    offs.append(len(blob))
    out = struct.pack("<H", len(items))
    out += b"".join(struct.pack("<H", o) for o in offs)
    return out + blob


# --- main table: one fixed 22-byte record per digimon --------------------
ENTRY = struct.Struct("<HHBBBBBBhHHHHBB")   # 22 bytes
records = b""
for e in db:
    st = e["stats"] or {}
    flags = ((1 if e["disabled"] else 0)
             | (2 if e["isPseudo"] else 0)
             | (4 if e["HasBossStats"] else 0))
    evo = name_to_index.get(e["evolution"], -1) if e["evolution"] else -1
    rr = rarity_by_name.get(e["name"], {})
    records += ENTRY.pack(
        e["number"], e["order"], e["stage"], e["spiritType"], e["element"],
        min(e["baseLevel"], 255), flags,
        ability_index.get(e["abilityName"], 255),
        evo,
        st.get("HP", 0), st.get("EN", 0), st.get("CR", 0), st.get("AB", 0),
        rr.get("rarity", 0), 1 if rr.get("exclusive") else 0)

names = strtable([e["name"] for e in db])
codes = b"".join((e["code"] or "").encode("ascii").ljust(5, b"\0") for e in db)
ability_names = strtable(abilities)

# extraEvolutions: sparse, 67 entries across the whole database
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

# bossStats: 13 entries
boss = b""
bosses = [(i, e["bossStats"]) for i, e in enumerate(db) if e["bossStats"]]
boss_table = struct.pack("<H", len(bosses))
for i, bs in bosses:
    boss_table += struct.pack("<HHHHH", i, bs["HP"], bs["EN"], bs["CR"], bs["AB"])

# worlds and areas
wblob = struct.pack("<H", len(worlds))
for w in worlds:
    areas = w["areas"]
    wblob += struct.pack("<BBBB", w["number"], 1 if w["multiMap"] else 0,
                         1 if w.get("shuffle") else 0, len(areas))
    for a in areas:
        wblob += struct.pack("<BBIBB", a["number"], a["map"], a["distance"],
                             a["coords"]["x"], a["coords"]["y"])

init_blob = struct.pack("<H", len(initials))
init_blob += b"".join(struct.pack("<H", name_to_index[n]) for n in initials)

sections = [
    ("entries", records), ("names", names), ("codes", codes),
    ("abilities", ability_names), ("extraEvo", extra_table),
    ("bossStats", boss_table), ("worlds", wblob), ("initials", init_blob),
]

# container: u16 section count, then (u32 offset, u32 length) per section
header = struct.pack("<H", len(sections))
body = b""
offsets = []
base = 2 + len(sections) * 8
for _, blob in sections:
    offsets.append((base + len(body), len(blob)))
    body += blob
for off, ln in offsets:
    header += struct.pack("<II", off, ln)
packed = header + body

json_total = sum(os.path.getsize(os.path.join(R, f)) for f in
                 ["digimonDB.json", "frontier_rarities.json", "worlds.json", "initials.json"])

print(f"{'section':12s} {'bytes':>8s}")
for (n, blob), (off, ln) in zip(sections, offsets):
    print(f"{n:12s} {ln:8,d}")
print(f"{'TOTAL':12s} {len(packed):8,d}")
b64 = base64.b64encode(packed).decode("ascii")
print(f"\nsource JSON       {json_total:8,d} bytes")
print(f"packed            {len(packed):8,d} bytes  ({len(packed)/json_total*100:.1f}% of JSON)")
print(f"base64 for a string resource {len(b64):8,d} bytes"
      f"  -> {(len(b64) + 32766) // 32767} string resources at the 32,767 cap")

open(os.path.join(OUT, "data.bin"), "wb").write(packed)
CHUNK = 32000
chunks = [b64[i:i + CHUNK] for i in range(0, len(b64), CHUNK)]
with open(os.path.join(OUT, "data_strings.xml"), "w") as f:
    f.write("<strings>\n")
    for i, c in enumerate(chunks):
        f.write(f'    <string id="Data{i}">{c}</string>\n')
    f.write("</strings>\n")
print(f"wrote data.bin and data_strings.xml ({len(chunks)} chunks)")

# a couple of records decoded back, to prove the layout round-trips
for probe in (0, 100, 592):
    vals = ENTRY.unpack_from(records, probe * ENTRY.size)
    src = db[probe]
    assert vals[0] == src["number"] and vals[9] == (src["stats"] or {}).get("HP", 0)
    print(f"  check #{probe}: number={vals[0]} name={db[probe]['name']} HP={vals[9]} ok")
