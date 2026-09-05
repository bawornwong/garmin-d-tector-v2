# Map: D-Tector v2 → Garmin Venu 4

Label: `wayfinder:map`

## Destination

A handoff-ready **spec + ADR set** for a faithful port of [kaisadilla/D-Tector-v2](https://github.com/kaisadilla/D-Tector-v2) (Unity 2019.3 C#, 12,261 LOC) to a Connect IQ watchApp on Garmin Venu 4 45mm (`venu445mm`). The map is done when every architectural decision is locked and someone can start building without further discovery. Building the app itself is a separate effort.

## Notes

**Domain**: retro virtual-pet / Digimon D-Tector device emulation, ported from Unity/C# to Monkey C / Connect IQ.

**Toolchain**: Connect IQ SDK 9.2.0 at `~/Library/Application Support/Garmin/ConnectIQ/Sdks/`; a self-signed dev key in the session scratchpad; .NET 9 for the golden-trace harness (`DOTNET_ROOT=$HOME/.dotnet`).

**Skills every session should consult**: `mattpocock-skills:grilling` + `mattpocock-skills:domain-modeling` by default; `mattpocock-skills:research` for research tickets; `mattpocock-skills:prototype` for prototype tickets.

**Source checkout** (throwaway, re-clone if gone):
`/private/tmp/claude-502/-Users-tiscomacnb2227-Workspace-garmin-d-tector/2cfbef5b-836a-439a-b7ec-c70531a6572c/scratchpad/dtector`

### Standing constraints (locked before charting)

- **Fidelity contract**: game *content* (593 Digimon, stats, rarity, worlds, battle math, evolution rules) and *visuals* (sprites, 32×32 layout) reproduced exactly. *Interaction* may be remapped — the watch has different hardware.
- **Target**: `venu445mm` only (Venu 4 45mm). 41mm is not a target.
- **Screen colours** are the physical device's reflective LCD, from `Preferences.cs`: background `#819376` (`Color32(129,147,118)`), active `#000000`. Not white-on-black — confirmed against a photo of a real D-Tector.
- **Rendering**: game canvas scaled **10×** → 320×320 centred inside the 454×454 round display. Integer scale, no blur, no corner clipping.
- **Frame rate ceiling: 20 fps** (50 ms timer floor, established by research). The original is a 60 fps Unity game. Everything animated is designed against 50 ms ticks.
- **Distribution**: personal sideload only, educational, non-commercial, not distributed. No Connect IQ Store submission, so no store review constraints.
- **Input**: two physical buttons carry A and B; the left and right screen halves, held, carry Left and Right. Decided in [Input abstraction layer](./issues/09-input-abstraction-layer.md) after research showed the simulator exposes only two keys, killing the original "keyboard first, hardware later" plan.
- **The fidelity anchor is the emulator source, not the physical toy.** This is a port. Where the two differ, the source wins.
- **Port rule**: everything that is not a coroutine is translated close to line-for-line to preserve behaviour; every coroutine goes to the animation VM. Presentation is rewritten natively for Connect IQ (Unity's MonoBehaviour/GameObject/coroutine model has no Connect IQ equivalent). Sharpened in [C# to Monkey C port rules](./issues/11-port-rules-csharp-to-monkeyc.md) — the split is by `IEnumerator`, not by folder.
- **Working app first, idiom later.** Where a literal translation and an idiomatic Monkey C one conflict, take the literal one. A cleanup that changes a result is a content change.

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

The full inventory is larger than this table: **749 sheet sub-sprites** (five Unity-sliced sheets, rects recoverable from the `.meta`) and **113 bitmap font glyphs** (three `.fontsettings`) were found later. Packed total: 2,423 sprites in 217 KB, plus fonts.

## Decisions so far

<!-- one line per resolved ticket: gist + link -->

- [Connect IQ input events and simulator keyboard](./issues/02-ciq-input-and-simulator-keyboard.md): Venu 4 has only two keys (`KEY_ENTER`, `KEY_ESC`) and no menu pseudo-key; press/release separate but hold must be timed in app code; use `onDrag` not `onSwipe`; shake needs `Sensor.getInfo().accel` polled from the game timer, and the simulator cannot generate it. **Two keys cannot carry A/B/Left/Right, so the "defer input mapping" plan does not survive — a real remap must be decided now.**
- [Connect IQ storage limits for save games](./issues/03-ciq-storage-limits.md): `Application.Storage` supports `ByteArray`; a packed index-keyed save is ~1.1 KB/slot against a quota of at least 128 KB, so 3–4 slots are affordable and storage is not a constraint. Writes are synchronous and expensive, so the original's save-on-every-setter must become checkpointed saves. Keep the `.prg` filename stable (≤8 chars) or saves are orphaned.
- [Connect IQ memory and timing budget](./issues/04-ciq-memory-and-timing-budget.md): the 768 KB limit is enforced at **build time** against the whole `.prg`, but `(:extendedCode)` exempts annotated code (measured: a build rejected at 1,197,785 B succeeded once annotated), runtime `BufferedBitmap`s live in a separate **4 MB graphics pool**, and 12,000 LOC measures at ≈200 KB. **Timer floor is 50 ms — a hard 20 fps ceiling**, with full-screen redraw every frame and no partial update.
- [Connect IQ binary assets and blitting](./issues/01-ciq-binary-assets-and-blitting.md): Connect IQ has **no binary resource type**, and `jsonData` costs 5 bytes per number, so the packed-blob plan is dead. Ship instead a **single 1-bpp `<bitmap>` atlas** — measured at 119,904 bytes of `.prg` for 1,606 sprites — blitted per cell with `drawBitmap2` + `AffineTransform.setToScale(10,10)` at `FILTER_MODE_POINT`. Atlases live in the 4 MB graphics pool, costing 9 bytes of heap. The 1,674-drawable alternative compiles but costs 387 KB of resources plus 15 KB of resident table.
- [Input abstraction layer](./issues/09-input-abstraction-layer.md): all 12 abstract events kept; `KEY_ENTER`→A, `KEY_ESC`→B, left/right screen halves held via `onDrag`→Left/Right — exactly the four sustained inputs Maze requires. Adapter synthesises touch down/up as a state machine and feeds an event queue the 20 fps loop drains. Shake is a faithful port of `ShakeDetector.cs` polling `Sensor.getInfo().accel`, live only inside Status.
- [C# to Monkey C port rules](./issues/11-port-rules-csharp-to-monkeyc.md): the logic/presentation boundary is **`IEnumerator`, not the folder** — `Animations.cs` is 32% of `Logic/` and is pure presentation. Numeric rule: compute in `Float`, `.toNumber()` only after `Math.floor`. `C_Int`'s 30 operator overloads become named methods because it clamps every operation. RNG reproduces bounds and probabilities, not Unity's sequence. Layout is 1:1 per original file with provenance comments, modules annotated `(:extendedCode)`.
- [Sprite atlas layout and index](./issues/05-sprite-atlas-layout.md): four atlases split by size class — 2,423 sprites in **222,454 bytes**, verified 2,423/2,423 by round-trip diff against the source PNGs. Addressing is arithmetic via a generated `DIGIMON_CELLS[dex][action]` table, no strings. Threshold on luma, not alpha. Sheet rects come from the Unity `.meta`, never guessed.
- [Render pipeline prototype](./issues/06-render-pipeline-prototype.md): **`drawBitmap2` rejects a palette source outright**, so the atlas ships as a 1-bpp resource (122,816 bytes measured) and is transferred into non-palette `BufferedBitmap` **row buffers** at runtime. Blit cost tracks source area, not output size: a 984×24 row costs **0.3 ms/sprite** against 6.8 ms from a whole-atlas buffer, so ~30 sprites fit a 50 ms frame. Rows fill lazily under an LRU. Colours are baked, not tinted. All timings are simulator, not hardware.
- [Animation VM instruction set](./issues/07-animation-vm-instruction-set.md): the data-VM plan is replaced by a **state-machine transform** — `Animations.cs` carries 202 `for` loops, 105 `if`s and 267 locals, so a data VM would mean writing a language. Each coroutine becomes a `pc`-switch class; a fractional scheduler runs every step whose scheduled time has arrived within each 50 ms tick, so durations match exactly. Verified **150/150 events** against a golden trace across three structurally different coroutines.
- [Coroutine conversion strategy](./issues/08-coroutine-conversion-strategy.md): a script emits the `pc`-case skeleton and lifts locals to fields, a human fills the statements. **Golden traces are generated from the true source, never transcribed** — 485 lines of stubs let the unmodified `Animations.cs` compile and run outside Unity: **53/53 coroutines traced, 0 failures, 6,911 events**. The runner gains fibers for the 32 `StartCoroutine`/`StopCoroutine` sites.

## Not yet specified

- **Per-minigame specs** — DigiHunter, Finder, JackpotBox, Maze, SpeedRunner each need their own timing and input treatment. Waits on the animation VM and the render pipeline.
- **D-Tector frame art** — the 454 ring around the 320×320 canvas. Cosmetic, undecided, not in the original.
- **Hardware timing** — every render number so far is from the simulator. The frame budget, the row-fill cost and the sprite-per-frame ceiling all need re-measuring on a real Venu 4 before anything depends on them.
- **Graphics-pool purges** — buffered bitmaps are not auto-restored. How the game notices a purged row buffer and refills it without a visible glitch is unspecified.
- **Localization** — source has a `config_localization` setting; scope unknown.
- **Evolution / D-Dock / spirit logic** — depth not yet surveyed.

## Out of scope

- **Audio (51 MP3s, 12 MB)** — Connect IQ watchApps cannot play audio files; only `Attention.playTone` profiles and vibration. This is a hardware ceiling, not a content change. Could become its own effort later.
- **Venu 4 41mm (`venu441mm`, 390×390)** — different scale factor, needs a second asset treatment.
- **Using the watch's real pedometer for in-game steps** — `ActivityMonitor.getInfo().steps` would echo the physical D-Tector toy, but the source only ever advances distance on shake. Ruled out in [Input abstraction layer](./issues/09-input-abstraction-layer.md); it would change gameplay.
- **Connect IQ Store publication** — sideload only, so no store review, no IP clearance path.
