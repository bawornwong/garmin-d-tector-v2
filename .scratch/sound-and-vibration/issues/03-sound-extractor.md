# The sound extractor

Type: task
Status: resolved
Blocked by: 02

## Question

Build `tools/pack_sounds.py`: read the source MP3s, recover each one's note sequence, and generate `app/source/Data/SoundData.mc` — round-trip verified, in the same family as `pack_sprites.py` and `pack_fonts.py`.

The work:

1. **Estimate fundamentals properly.** A peak picker is not enough: on `encounter_regular` the loudest partial is the 5th harmonic of the real 1094 Hz fundamental. Use harmonic product spectrum or autocorrelation, and prove it on the known case — a correct estimator returns 1094 Hz there, not 5464.
2. **Segment into notes.** Per-frame fundamental plus energy, collapsed into runs of (frequency, duration) with rests where the signal drops out. The rhythms recovered by the crude tracker are a sanity check: `level_up` should come out as a 4-note motif repeated four times closing on a held note; `char_happy` as six notes of clearly varied length.
3. **Decide what a note is.** Pick and document the thresholds — how much pitch drift stays one note, what energy counts as a rest, what minimum duration survives. These are the knobs the round trip scores.
4. **Emit `SoundData.mc`**, GENERATED and marked so, keyed by the same names the call sites already pass (34 `playSound` names plus the button and character calls), and a build-time dictionary from name to table.
5. **Round-trip verify.** Re-synthesise the extracted notes and compare against the source's own fundamental track. This is the check that decides whether the result is a reproduction or an approximation, and it should print a per-sound score, not a single pass/fail.
6. **Account for every file.** 51 MP3s, of which `UNUSED get_digimon.mp3` and `Battle/Change boss.mp3` are referenced nowhere. That leaves 49 live files against 34 `playSound` names plus the button and character sounds — reconcile the remainder and say what each unmatched file is.

## Context

`DTECTOR_SRC` points at the source checkout; audio is under `$DTECTOR_SRC/Assets/Audio/`. `ffmpeg`/`ffprobe` and `numpy` are available; `scipy` is not.

[ADR 12](../../../docs/adr/0012-verification-is-generated-not-transcribed.md) governs: the output is generated, never hand-edited.

Blocked by [What ToneProfile and vibrate accept](./02-what-toneprofile-accepts.md) because the emitted shape has to match what `playTone` will take — frequency and duration units, bounds, and any array-length ceiling.

## Answer

Built `tools/pack_sounds.py`. It writes `app/source/Data/SoundData.mc` (GENERATED) and `app/resources/strings/sound_strings.xml`, and prints a per-sound round-trip score plus `build/sound_index.json` for inspection.

**Fundamental estimator**: the lowest spectral peak clearing a noise floor, not harmonic-product-spectrum. HPS degrades exactly on this dataset's button beeps — a pure tone has no energy at the sub-harmonics HPS multiplies against, so every candidate scores near the noise floor and the true fundamental doesn't stand out. A square wave's harmonics fall off as 1/n, so its fundamental is reliably present as *some* peak even when it isn't the loudest one (proven case: `encounterDigimon`'s loudest partial is 5464 Hz, its fundamental — the lowest peak — is 1094 Hz). This one rule handles both the pure-tone button beeps and the harmonic-rich melodies.

**Name-to-file mapping**: resolved by a GUID join, not filename guessing — `DigiviceFrontier.unity`'s `AudioManager` MonoBehaviour (component `2122903411`) binds each of 45 fields to an asset GUID, and every asset's own `.meta` states that GUID, so each of the 40 names below is a two-hop lookup through the source's own data, cross-checked against `AudioManager.cs`'s field list. **All 51 source MP3s are now accounted for**, closing the map's "unused source sounds" fog:
- **40 fields reachable** by some call site in the source (and the port has exactly these 40, confirmed by grep against both codebases) — this is the table `pack_sounds.py` carries.
- **5 fields wired but never called anywhere in the source's own `Scripts/`**: `charHappyLong`, `charSadLong`, `attackTravel`, `attackTravelLong`, `evolutionArmor`. `attackTravel`/`attackTravelLong` even say `//Not used` in the source's own `AudioManager.cs`. The port correctly has no call sites for any of the five.
- **6 files not wired to any field at all**: `UNUSED get_digimon.mp3` and `Battle/Change boss.mp3` say so in their own names; `Battle/attack_travel_and_explode.mp3` and `Battle/attack_travel_long_2x.mp3` are unused variants of the attack-travel family; `punishment.mp3` and `unlock_code.mp3` are superseded by `punishment2.mp3` and `unlock_code_long.mp3`, which the wired `punishment`/`unlockCode` fields actually point at.

**A real compiler wall, found building this**: a single Monkey C literal array past a few thousand numbers overflows `monkeyc`'s const type checker — a genuine `java.lang.StackOverflowError` in `ConstTypeChecker` (it recurses per element), not a documented limit. The flat notes table is 4,106 numbers (2,053 notes) and hit it immediately. [ADR 6](../../../docs/adr/0006-packed-data-in-string-resources.md) already solved this exact shape of problem for the Digimon database, so the fix is the same move: notes pack as bytes (`UINT16` freq, `UINT16` duration, little-endian) and ship as base64 in a string resource (`SoundData0`, one slot needed of `MAX_CHUNKS = 2` declared — 8,212 bytes packs to 10,952 base64 chars, comfortably under ADR 6's 32,000-char chunk size), decoded once into a `ByteArray` exactly the way `GameData.load()` already does. `NAMES`/`OFFSETS`/`COUNTS` stay ordinary literal arrays (40 elements each, nowhere near the ceiling that broke the notes table). Verified independently of the acoustic round trip: the generated resource's base64, decoded and re-read through the same offset arithmetic `noteAt()` uses, reproduces the extractor's own note list byte-for-byte for every sound checked.

**Round-trip result** (% of active source frames whose measured fundamental agrees with the note covering that frame, within 8%): **90.3% average across the 40 sounds, worst case 58.4%** (`destroySpirits`). Full table in `build/sound_index.json`; both builds (`tools/build.sh` and `-r`) compile clean with the generated file in the tree, unused — nothing calls `Sounds.load()`/`noteAt()` yet, which is ticket 05's job.

| Band | Sounds |
|---|---|
| ≥ 95% | buttonA, buttonB, unpleasantBeep, charSad, deportSpirit, encounterDigimon, loseDigimon, speedRunner_Finish, stealAllSpirits, unlockCode (10) |
| 85–95% | most of the rest (21) |
| < 85% | destroySpirits (58%), digistorm (65%), evolutionSpirit (79%), attackTravelVeryLong/evolutionAncient (79-80%), gameStart (84%), explosion/launchAttack/launchAttackLong (83-85%) |

The weak group is not a segmentation bug to chase further right now — `destroySpirits` and `digistorm` measure as moderately noisy/broadband (spectral flatness 0.37 and 0.19; a pure tone is ~0, white noise is ~1), and the others show fast pitch movement the 8% note-merge tolerance and 20ms minimum note length don't track cleanly. Recorded in the map's Not-yet-specified rather than iterated on now, since tuning further is exactly the kind of taste call ticket 06's design session (and eventually a hardware listen) should drive, not a number to chase in isolation.
