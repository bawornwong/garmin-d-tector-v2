# Save format mapping

Type: grilling
Status: resolved
Blocked by: 03

## Question

How does the original save game map onto Connect IQ persistence?

The original uses Unity `PlayerPrefs` plus binary serialisation, with multiple save slots and encryption (`SavedGame.cs`, 430 LOC; `EncryptedPlayerPrefs.cs`). Connect IQ offers `Application.Storage` and `Application.Properties`.

Decide:

- **Slot count** — multiple slots as in the original, or one, given the measured storage quota.
- **Encoding** — one dictionary per slot versus many flat keys. Weigh per-key overhead against read/write cost against the quota.
- **Encryption** — the original encrypts saves. On a sideloaded personal build there is no threat model for it. Drop it, or keep it for fidelity?
- **Save points** — when a save is written: every state change, on a timer, on app exit, or a mix. Depends on the measured write cost.
- **Migration** — the original tracks `last_update_version` for save migrations. Is a version field carried forward?
- **Field mapping** — walk `SavedGame.cs` and produce the field-by-field mapping. Anything dropped is a content change and must be justified.

## Answer

Probe: [`prototype/save/ciq/`](../prototype/save/ciq/), built for `venu445mm` and run in the simulator.

### Measurements

| | |
|---|---|
| Write a 1,024-byte `ByteArray` to Storage | **1 ms** |
| Read it back | **1 ms**, byte-identical |
| Write four slots | 18 ms total |
| Build a 593-key name→level `Dictionary` | 7 ms, **+39.7 KB of heap** (46,944 vs 7,208 baseline) |
| Write that dictionary / read it back | 5 ms / 4 ms, all 593 keys survive |
| **Storage quota** | **9,214 KB written before `storage limit exceeded`** |

The quota settles the open question from [Connect IQ storage limits for save games](./03-ciq-storage-limits.md): `appStorageCapacity: 10485760` in `simulator.json` is the real figure, and the Core Topics doc's "total of 128 KB" does not apply to this device. About 9.0 MB of the 10 MB was reachable with 1 KB values; the remainder goes to key names and bookkeeping.

Two things the measurements change:

- **Storage writes are cheap**, not the expensive operation the forum guidance in ticket 03 implied — at least in the simulator. 1 ms for a full slot.
- **The dictionary shape costs ~40 KB of RAM**, not just disk. Ticket 03 estimated ~27 KB stored; the live cost on the heap is worse. It works, but it spends 5% of the app's memory budget on data that packs into 593 bytes.

### The packed slot: 963 bytes

Every field of `SavedGameFile` (`SavedGame.cs:354`), nothing dropped:

| Field | Bytes | Encoding |
|---|---|---|
| version | 1 | format version, for migrations |
| name | 17 | u8 length + up to 16 chars |
| gameChar | 1 | |
| cheats / insured / leaverBuster / defeated | 1 | four flags in one byte |
| pendingEvent | 1 | |
| leaverBusterExpLoss | 4 | |
| leaverBusterDigimonLoss | 2 | digimon index |
| jackpotValue | 4 | |
| currentMap, currentArea | 2 | |
| currentDistance | 4 | reaches 99,999 |
| steps, stepsToNextEvent | 8 | |
| playerExperience | 4 | |
| spiritPower | 1 | 0–99 |
| battleSeed | 12 | 3 × u32 |
| totalBattles, totalWins | 8 | |
| ddockDigimon | 8 | 4 × i16 index |
| lostSpirits | 41 | u8 count + up to 20 × i16 index |
| **digimonLevel** | **593** | one byte per digimon, positional |
| **digicodeUnlocked** | **75** | 593 bits |
| areasCompleted | 7 | 52 bits, one per area |
| bosses | 155 | 51 slots, u8 count + i16 indices (51 names) |
| semibossGroup | 14 | 13 groups |
| **Total** | **963** | |

Dimensions come from the shipped data: 9 worlds, 52 areas, 21 distinct (world, map) pairs, 51 boss slots, 13 semiboss groups.

### Decisions

1. **Positional, not keyed.** `digimonLevel` and `digicodeUnlocked` are dictionaries keyed by digimon name in the original; here they are arrays indexed by position in `digimonDB.json` — 593 bytes and 75 bytes against ~40 KB of heap for the keyed form. Every name-valued field (`ddockDigimon`, `lostSpirits`, `leaverBusterDigimonLoss`, `bosses`) likewise stores an index. **This is the same row order as [Data pipeline: JSON to Connect IQ resources](./12-data-pipeline-json-to-resources.md) and [Sprite atlas layout and index](./05-sprite-atlas-layout.md)** — the three tables share one ordering, and a disagreement of one row corrupts saves silently.

2. **Four slots, one Storage key each**, plus a small index key holding each slot's name and character for the slot picker. At 963 bytes against a 9 MB quota, slot count is not a constraint; four matches what the original's file-based scheme offered in practice.

3. **Encryption is dropped.** `EncryptedPlayerPrefs.cs` is dead code — unreferenced by `SavedGame.cs` — and on a personal sideload there is no threat model for it. Nothing in the save's *content* changes.

4. **Checkpointed saves, not save-on-every-setter.** The original calls `SaveGame()` from 25 property setters, including `Steps` and `CurrentDistance`, which fire constantly while walking. Writes measure 1 ms so this is not a latency problem, but it is thousands of flash writes an hour. The port keeps state in RAM and commits at checkpoints: app exit, screen transitions, after a battle, after an event. **The saved content is identical either way** — only the write schedule changes, so the fidelity contract is untouched.

5. **A version byte leads the record.** The original tracks `last_update_version` for migrations; this carries the same idea in one byte.

6. **The `.prg` filename is part of the format.** Storage lives in `\GARMIN\APPS\DATA` named after the `.prg`, so the filename must stay byte-identical and ≤8 characters across builds or every save is orphaned. This is a build-system constraint, recorded here because nothing else would catch it.

### Still open

- All timings are the simulator. Flash on real hardware is slower, which strengthens the case for checkpointing rather than weakening it.
- The 20-entry cap on `lostSpirits` is assumed from the spirit count, not verified against the game's own maximum.
- Slot names are capped at 16 characters; the original's limit was not checked.
