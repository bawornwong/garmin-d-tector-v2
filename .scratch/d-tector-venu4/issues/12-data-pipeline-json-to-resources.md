# Data pipeline: JSON to Connect IQ resources

Type: grilling
Status: resolved
Blocked by: 01, 11

## Question

How do the source's JSON data files reach the watch, and in what runtime shape?

The data: `digimonDB.json` (260 KB, 593 entries), `frontier_rarities.json` (46 KB), `worlds.json` (8.6 KB), `initials.json` (225 B). A Digimon entry carries `number`, `order`, `name`, `stage`, `spiritType`, `abilityName`, `element`, `evolution`, `extraEvolutions[]`, `disabled`, `baseLevel`, `stats{HP,EN,CR,AB}`, `bossStats`, `isPseudo`, `code`.

Decide:

- **Resource form** — `Rez.JsonData`, or a compacted binary table built alongside the sprite blob. 260 KB of JSON parsed into Monkey C dictionaries will not fit comfortably in 768 KB alongside code and sprites; establish what it actually costs.
- **Residency** — is the whole database resident, or looked up on demand from a packed table? The Database app browses all 593 entries; Battle needs one or two at a time.
- **Field packing** — string fields (`name`, `code`, `abilityName`, `evolution`, `extraEvolutions`) dominate the size. Intern them into a string table with numeric references, or keep them inline?
- **Sprite linkage** — how a database entry resolves to its sprite indices in the blob. Must agree with whatever [Sprite atlas layout and index](./05-sprite-atlas-layout.md) decided.
- **Verification** — the build script must prove every one of the 593 entries survives the transform with every field intact. Content fidelity is the whole point.

## Answer

Packer: [`prototype/data/pack_data.py`](../prototype/data/pack_data.py). Watch-side probe: [`prototype/data/ciq/`](../prototype/data/ciq/), built for `venu445mm` and run in the simulator.

### Measured carrier costs

Connect IQ has no binary resource type, so the carriers were measured by building the same app three ways and differencing the `.prg`:

| Carrier | `.prg` cost | Rate |
|---|---|---|
| `jsonData` holding 5,000 numbers | 25,280 bytes | **5.06 bytes per number** |
| String resource holding base64 | 35,312 bytes | **1.00 bytes per character** |

The 5-bytes-per-number figure from the assets research is confirmed on this device. Shipping the database as `jsonData` would spend roughly 48 KB on its numeric fields alone, before strings and before the per-entry dictionary keys, and all of it would land in the 768 KB heap as live Monkey C objects.

String resources cost exactly one byte per character with no overhead, and cap at 32,767 bytes each — so packed bytes ride as base64 (4/3 inflation) across two resources. Raw bytes in a UTF-8 string were rejected: every byte ≥ 0x80 costs two, which is worse than base64 on binary data.

### The packing

`frontier_rarities.json` turned out to be **parallel to `digimonDB.json`** — the same 593 digimon, one `{digimon, rarity, exclusive}` record each — so it folds into the main table as two more fields instead of shipping as 46 KB of its own.

| Section | Bytes |
|---|---|
| entries (593 × 22-byte fixed record) | 13,046 |
| names (length-prefixed table) | 7,212 |
| codes (5 bytes each, fixed) | 2,965 |
| ability names | 2,275 |
| extraEvolutions (sparse: 67 across the database) | 296 |
| bossStats (sparse: 13 entries) | 132 |
| worlds and areas | 454 |
| initials | 38 |
| **Total** | **26,484** |

**26,484 bytes against 315,982 bytes of source JSON — 8.4%.**

The 22-byte record is `number` u16, `order` u16, `stage`/`spiritType`/`element`/`baseLevel`/`flags`/`abilityIndex` one byte each, `evolutionIndex` i16, four u16 stats, then `rarity` and `exclusive`. Everything that was a string reference in the JSON — `evolution`, `abilityName` — becomes a numeric index, so **no string comparison happens at runtime**, matching the addressing decision in [Sprite atlas layout and index](./05-sprite-atlas-layout.md).

### Decisions

1. **Carrier: base64 in string resources**, decoded once at startup with `StringUtil.convertEncodedString` into a `ByteArray`, read with `ByteArray.decodeNumber` and `slice`.
2. **The whole database stays resident.** 26 KB against a 768 KB budget is 3.4%; on-demand slicing would add complexity to save nothing.
3. **Row order is `digimonDB.json` order**, and the sprite table, the save format and this table all key off it. This is the joint decision flagged by tickets 05 and 10 — a one-row disagreement puts the wrong Digimon everywhere.
4. **Strings are interned in a table with u16 offsets.** Names are needed on screen (the Database app), codes are needed by `CodeInput`; ability names ship too, at 2,275 bytes, so the Database app can display them.
5. **Sparse fields get side tables.** `extraEvolutions` exists on a handful of entries (67 targets total, max 4 per entry) and `bossStats` on 13 — inlining either into the fixed record would waste more than the side table costs.

### Verification on the device

Measured in the simulator:

| | |
|---|---|
| Load two string resources | 35,312 chars, **1 ms** |
| Base64 → ByteArray | 26,484 bytes, **0 ms** |
| Memory after load | 69,888 / 781,888 (peak, both string and bytes live) |
| Memory once the string is collected | 34,552 / 781,888 |
| Walk all 593 HP fields | **3 ms** |
| Read all 593 names | **9 ms**, 6,022 characters |

Then every record was dumped off the watch and diffed against the source JSON:

**593 / 593 records, 9,488 fields, zero mismatches.**

This diff is the pipeline's regression test and belongs in CI beside the numeric sweep.

### Two Monkey C gotchas worth recording

- `ByteArray.decodeNumber(NUMBER_FORMAT_UINT32, …)` returns a **`Long`**, not a `Number`. Using one as an array index throws `UnexpectedTypeException: Expected Number, given Long`. Call `.toNumber()`.
- `StringUtil.utf8ArrayToString` will not take a `ByteArray` — the type annotation compiles, but it fails at runtime with `Unexpected Type Error`. Use `convertEncodedString` with `REPRESENTATION_BYTE_ARRAY` → `REPRESENTATION_STRING_PLAIN_TEXT` instead.

### Still open

- Peak memory during load holds both the 35 KB base64 string and the 26 KB `ByteArray`. Decoding one chunk at a time would halve the peak; not needed at these sizes, but worth knowing if the data grows.
- `worlds.json`'s `bosses`, `semibosses`, `removePlayer` and `semibossMode` fields are not yet packed — the world section currently carries only areas. They need adding once the Map app's requirements are known.
