# 6. Game data ships packed, carried as base64 in string resources

Date: 2026-09-06

## Status

Accepted

## Context

The game's data is 315,982 bytes of JSON: `digimonDB.json` (593 entries), `frontier_rarities.json`, `worlds.json`, `initials.json`.

Connect IQ has no binary resource type. The two carriers that exist were measured by differencing `.prg` builds:

| Carrier | Cost |
|---|---|
| `jsonData` holding numbers | **5.06 bytes per number** |
| String resource | **1.00 bytes per character**, capped at 32,767 |

Shipping the database as `jsonData` would spend roughly 48 KB on numeric fields alone, before strings and before each entry's dictionary keys, and all of it would live in the 768 KB heap as Monkey C objects.

`frontier_rarities.json` turned out to be parallel to `digimonDB.json` — the same 593 Digimon, one `{digimon, rarity, exclusive}` record each.

## Decision

Data is packed into a **byte layout** — a fixed 22-byte record per Digimon plus length-prefixed string tables and sparse side tables — and carried as **base64 across two string resources**, decoded once at startup with `StringUtil.convertEncodedString` into a `ByteArray` and read with `ByteArray.decodeNumber` and `slice`. `frontier_rarities` folds into the main record as two fields.

Every string reference in the source — `evolution`, `abilityName` — becomes a numeric index, so no string comparison happens at runtime.

## Consequences

- 26,484 bytes packed, **8.4% of the source JSON**; 35,312 bytes of `.prg` after base64.
- The whole database stays resident at 3.4% of the heap. Reading all 593 HP fields takes 3 ms; all 593 names, 9 ms.
- Base64's 4/3 inflation is accepted: raw bytes in a UTF-8 string cost two bytes for every value ≥ 0x80, which is worse on binary data.
- Peak memory during load holds both the string and the byte array; chunked decoding would halve it if the data ever grows.
- Verified: **593/593 records, 9,488 fields, zero mismatches** read back off the device.
