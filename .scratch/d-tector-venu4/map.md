# Map: D-Tector v2 → Garmin Venu 4

Label: `wayfinder:map`

## Destination

A handoff-ready **spec + ADR set** for a faithful port of [kaisadilla/D-Tector-v2](https://github.com/kaisadilla/D-Tector-v2) (Unity 2019.3 C#, 12,261 LOC) to a Connect IQ watchApp on Garmin Venu 4 45mm (`venu445mm`). The map is done when every architectural decision is locked and someone can start building without further discovery. Building the app itself is a separate effort.

## Notes

**Domain**: retro virtual-pet / Digimon D-Tector device emulation, ported from Unity/C# to Monkey C / Connect IQ.

**Skills every session should consult**: `mattpocock-skills:grilling` + `mattpocock-skills:domain-modeling` by default; `mattpocock-skills:research` for research tickets; `mattpocock-skills:prototype` for prototype tickets.

**Source checkout** (throwaway, re-clone if gone):
`/private/tmp/claude-502/-Users-tiscomacnb2227-Workspace-garmin-d-tector/2cfbef5b-836a-439a-b7ec-c70531a6572c/scratchpad/dtector`

### Standing constraints (locked before charting)

- **Fidelity contract**: game *content* (593 Digimon, stats, rarity, worlds, battle math, evolution rules) and *visuals* (sprites, 32×32 layout) reproduced exactly. *Interaction* may be remapped — the watch has different hardware.
- **Target**: `venu445mm` only (Venu 4 45mm). 41mm is not a target.
- **Rendering**: game canvas scaled **10×** → 320×320 centred inside the 454×454 round display. Integer scale, no blur, no corner clipping.
- **Distribution**: personal sideload only, educational, non-commercial, not distributed. No Connect IQ Store submission, so no store review constraints.
- **Input, for now**: physical button/touch mapping is **deferred**. Build against the SDK simulator's keyboard mapping first; decide real hardware mapping later.
- **Port rule**: `Logic/` layer is translated close to line-for-line to preserve behaviour; presentation layer is rewritten natively for Connect IQ (Unity's MonoBehaviour/GameObject/coroutine model has no Connect IQ equivalent).

### Hard facts established while charting

**Target device** (`venu445mm`, SDK 9.2.0 installed):
- 454×454 round AMOLED, 16 bpp, Connect IQ **6.0.2**, deviceFamily `round-454x454`
- watchApp memory limit **786,432 B (768 KB)**; `maxPrgFilespace` 64 MB; `codePageSize` 4096
- 2 physical buttons (right-top, right-bottom) + touchscreen; `screenRotationSupport: false`

**Source**:
- Unity 2019.3.10f1, 55 C# files, 12,261 LOC
- Game canvas `SCREEN_WIDTH/HEIGHT = 32`, `PIXEL_SIZE = 24`
- Inputs: A, B, Left, Right — each with press/hold/release — plus `ShakeDetector` (accelerometer)
- Apps: Camp, Database, Map, Status, CodeInput. Minigames: Battle, DigiHunter, Finder, JackpotBox, Maze, SpeedRunner
- `Animations.cs` is the heaviest surface: 2,902 LOC, **60 coroutines, 535 `yield return`**
- Data: `digimonDB.json` 260 KB / **593 entries**, `worlds.json` 8.6 KB, `frontier_rarities.json` 46 KB, `initials.json` 225 B

**Sprites are 1-bit** — verified across all 1,674 PNGs; only 8 files carry more than one opaque colour:

| Group | Files | Main size | Packed 1bpp |
|---|---|---|---|
| Digimon | 1,446 | 24×24 | 102.5 KB |
| Abilities | 196 | 24×24 | 13.8 KB |
| Maps | 16 | 32×32 | 2.0 KB |
| Energies | 16 | 24×24 | 1.1 KB |
| **Total** | **1,674** | | **119.5 KB** |

A 24×24 sprite is 72 bytes packed. The whole sprite set fits in storage with room to spare, and one sprite in RAM is negligible against the 768 KB budget.

## Decisions so far

<!-- one line per resolved ticket: gist + link -->

_(none yet)_

## Not yet specified

- **Battle math parity** — how exactly `Battle.cs` (1,068 LOC) computes outcomes, and whether Monkey C's numeric model (no `float` vs `double` distinction the way C# has it, different rounding) can reproduce it bit-for-bit. Waits on the port-rules ticket.
- **RNG parity** — Unity `Random` vs Monkey C `Math.rand`. Whether "content unchanged" demands identical distributions or merely identical rules.
- **Per-minigame specs** — DigiHunter, Finder, JackpotBox, Maze, SpeedRunner each need their own timing and input treatment. Waits on the animation VM and the render pipeline.
- **Physical input mapping** — real buttons/touch/shake on Venu 4. Deliberately deferred; simulator keyboard first.
- **D-Tector frame art** — the 454 ring around the 320×320 canvas. Cosmetic, undecided, not in the original.
- **Localization** — source has a `config_localization` setting; scope unknown.
- **Evolution / D-Dock / spirit logic** — depth not yet surveyed.

## Out of scope

- **Audio (51 MP3s, 12 MB)** — Connect IQ watchApps cannot play audio files; only `Attention.playTone` profiles and vibration. This is a hardware ceiling, not a content change. Could become its own effort later.
- **Venu 4 41mm (`venu441mm`, 390×390)** — different scale factor, needs a second asset treatment.
- **Connect IQ Store publication** — sideload only, so no store review, no IP clearance path.
