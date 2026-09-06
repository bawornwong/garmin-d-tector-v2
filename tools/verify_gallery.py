#!/usr/bin/env python3
"""Check the packed gallery order against the original's OrderBy.

GameManager's stage gallery ends in `.OrderBy(d => d.order)`. The port has no
LINQ and no room to sort up to 136 rows on a menu press, so pack_data.py packs
the sorted sequence into the `orderIndex` section and the app walks it.

This diffs that packed sequence against a stable sort of the source JSON, per
stage. It exists because the first version of the port assumed row order WAS
`order` order -- and this check found all eight stages disagreeing, one of them
by 200 rows.

Usage:
    DTECTOR_SRC=/path/to/D-Tector-v2 tools/verify_gallery.py
"""
import json
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import src

DIGIMON_DB = "Assets/Resources/digimonDB.json"
STAGE_NAMES = ["Rookie", "Champion", "Perfect", "Mega", "Ultimate", "Armor",
               "Spirit", "none"]


def packed_order():
    """The orderIndex section of build/data.bin, as row indices."""
    build = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                         "build")
    sections = json.load(open(os.path.join(build, "data_index.json")))["sections"]
    blob = open(os.path.join(build, "data.bin"), "rb").read()
    off = sections["orderIndex"]["offset"]
    count = struct.unpack_from("<H", blob, off)[0]
    return [struct.unpack_from("<H", blob, off + 2 + i * 2)[0] for i in range(count)]


def main():
    db = json.load(open(src(DIGIMON_DB)))
    packed = packed_order()
    if len(packed) != len(db):
        raise SystemExit(f"orderIndex holds {len(packed)} rows, the database has {len(db)}")

    # The port's sequence: the packed order, minus the disabled rows the app
    # skips. The original's: a stable sort of the same rows by `order`.
    bad = []
    for stage in range(len(STAGE_NAMES)):
        in_stage = [(i, db[i]) for i in packed
                    if db[i]["stage"] == stage and not db[i].get("disabled")]
        port = [i for i, _ in in_stage]
        original = [i for i, _ in sorted(
            [(i, db[i]) for i in range(len(db))
             if db[i]["stage"] == stage and not db[i].get("disabled")],
            key=lambda p: p[1]["order"])]
        if port != original:
            first = next(k for k in range(len(port)) if port[k] != original[k])
            bad.append((STAGE_NAMES[stage], len(in_stage), first,
                        port[first], original[first]))

    for name, n, k, got, want in bad:
        print(f"  {name}: {n} rows, first difference at position {k}: "
              f"row {got} where OrderBy gives row {want}")

    print(f"{len(STAGE_NAMES) - len(bad)}/{len(STAGE_NAMES)} stages match "
          f"({len(packed)} rows): the packed orderIndex == OrderBy(order)")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
