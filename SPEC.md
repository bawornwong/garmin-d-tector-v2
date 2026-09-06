# D-Tector v2 → Garmin Venu 4: build specification

Handoff document. Every number here was measured on `venu445mm` with Connect IQ SDK 9.2.0, or computed from the source assets — nothing is estimated. Terms are defined in [CONTEXT.md](CONTEXT.md); the reasoning behind each decision is in [docs/adr](docs/adr/), and the investigation that produced them is in the wayfinder map at `.scratch/d-tector-venu4/map.md`, with runnable prototypes under `.scratch/d-tector-venu4/prototype/`.

## 1. Scope

Port [kaisadilla/D-Tector-v2](https://github.com/kaisadilla/D-Tector-v2) — Unity 2019.3, 55 C# files, 12,261 lines — to a Connect IQ watchApp on **Venu 4 45mm (`venu445mm`)**, reproducing its content and visuals exactly.

**In scope**: all five apps (Camp, Database, Map, Status, CodeInput), all six minigames (Battle, DigiHunter, Finder, JackpotBox, Maze, SpeedRunner), all 593 Digimon, the full sprite and font set, saves.

**Out of scope**: audio ([ADR 11](docs/adr/0011-audio-is-out-of-scope.md)); Venu 4 41mm; Connect IQ Store publication. Distribution is personal sideload, educational, non-commercial.

**Interaction may be remapped; content and visuals may not.** Where the physical toy and the source disagree, the source wins ([ADR 1](docs/adr/0001-fidelity-anchor-is-the-source.md)).

## 2. Target and budgets

| Constraint | Value | How it was established |
|---|---|---|
| Display | 454 × 454 round AMOLED, 16 bpp | device profile |
| Connect IQ | 6.0.2 | device profile |
| Canvas | 320 × 320, centred; **10× integer scale** of the 32 × 32 game canvas | 32 × 10 |
| Screen colours | ink `#000000` on `#819376` | `Preferences.cs` |
| `.prg` ceiling | 786,432 bytes, enforced **at build time** | triggered the compiler error |
| Code exemption | `(:extendedCode)` moves annotated code out of that check | a build rejected at 1,197,785 B succeeded once annotated |
| Code density | ≈16.5 bytes of bytecode per source line → 12,000 lines ≈ 200 KB | measured |
| Frame | **50 ms timer floor → 20 fps**, full-screen redraw, no partial update | documented floor, confirmed in use |
| Sprite budget | ≈30 sprites per frame at 312 µs each | measured |
| Graphics pool | ≈829,000 pixels of buffered bitmap, **shape-independent**; overcommit throws | 60 rows at 576 wide, 120 at 288 wide — identical totals |
| Storage | **9,214 KB** before `storage limit exceeded`; 1 ms per 1 KB write | measured |
| Debug builds | ≈2.7× larger than release, and the simulator runs debug | 867,276 vs 318,236 bytes |

Asset budget, all measured:

| Item | Size |
|---|---|
| Sprite atlases (2,423 sprites) | 217 KB |
| Font atlas (113 glyphs) | 525 B |
| Packed game data | 26,484 B (35,312 B as base64) |
| One save slot | 963 B |

## 3. Architecture

Four layers, with a hard rule about which is translated and which is rewritten.

```
Connect IQ delegates ──► InputAdapter ──► event queue
                                              │
                                       ┌──────▼───────┐
              row buffers ◄── Renderer │ 20 ms.. tick │──► Runner (fibers)
                    │                  └──────┬───────┘         │
                atlases                       │                 ▼
                                       display list ◄──── routines (state machines)
                                              ▲
                                              └──────── logic layer (translated 1:1)
                                                              │
                                                     packed data · save
```

**Logic layer** — everything from the source that is *not* a coroutine, translated close to line-for-line ([ADR 2](docs/adr/0002-literal-translation-over-idiom.md)). Annotated `(:extendedCode)`.

**Routines** — everything that *is* a coroutine, including all of `Animations.cs`, as `pc`-switch state machines ([ADR 4](docs/adr/0004-state-machines-not-a-data-vm.md)). **The logic/presentation split is `IEnumerator`, not the folder**: `Animations.cs` lives under `Logic/` but is 32% of it and is pure presentation.

**Display list** — mirrors `ScreenElement`/`SpriteBuilder`/`TextBoxBuilder`/`RectangleBuilder`/`ContainerBuilder` with the same ~24 operations (`SetSprite`, `SetActive`, `Move`, `SetSize`, `Center`, `PlaceOutside`, `FlipHorizontal`, `Dispose`, …). Animations mutate it; the renderer draws it whole each frame.

**Renderer** — see [ADR 3](docs/adr/0003-sprite-atlas-and-row-buffers.md). Draws from row buffers, never from the atlas resource.

## 4. Build pipeline

Three generators, all run before `monkeyc`, all self-verifying.

**Sprite packer** (`prototype/data/pack_sprites.py` is the working prototype)
- Reads `Assets/Resources/Sprites/**` and the five `Assets/Sprites/*.png` sheets, slicing the latter by the rects in their `.meta` files — never by a guessed grid.
- Thresholds each pixel: **on when `alpha > 0` and `luma > 128`**. Alpha alone would turn eight Digimon sprites into solid blocks; luma alone would lose the fonts, whose art is in the alpha channel.
- Writes **white ink on a transparent field** — never the screen colours. Ink colour is applied at draw time as a tint, which is what lets sprites composite and lets anything be drawn inverted ([ADR 3](docs/adr/0003-sprite-atlas-and-row-buffers.md)).
- Packs one atlas per size class, **24 cells wide**, with a Digimon's group never straddling a row.
- Every `<bitmap>` it feeds `drawables.xml` carries `dithering="none"` and an explicit `<palette>` of the single ink colour. Without both, the resource compiler quantises to 4 bpp and dithers, silently losing isolated ink pixels ([ADR 3](docs/adr/0003-sprite-atlas-and-row-buffers.md)).
- Emits `DIGIMON_CELLS[index][action]`, 603 rows × 6, `-1` where an action has no art.
- Verifies by unpacking its own output and diffing every cell.

**Font packer** (`tools/pack_fonts.py`)
- Reads the three `.fontsettings`, converting Unity units to game pixels by dividing by 24.
- Emits per-glyph bitmaps, advances and vertical bearings: Big monospaced at 6 px, Regular and Small proportional (2–6 px); line spacing 8 px for Big, 6 px otherwise. It fails the build on a glyph whose `vert` box disagrees with its `uv` box (only the blank space glyph does, and nothing is drawn from it) or whose advance or bearing is fractional.
- Places all 113 glyphs inside **one standard atlas row** so text blits on the 312 µs plateau.
- Generates `app/source/Render/FontMetrics.mc`, the table the renderer reads: flat `Number` arrays, five entries per character code from 32 to 90 ([ADR 12](docs/adr/0012-verification-is-generated-not-transcribed.md)).

**Data packer** (`prototype/data/pack_data.py`)
- Packs `digimonDB.json` + `frontier_rarities.json` + `worlds.json` + `initials.json` into the byte layout, base64s it, and writes the string resources ([ADR 6](docs/adr/0006-packed-data-in-string-resources.md)).
- Row order is `digimonDB.json` order, shared with the sprite and save tables ([ADR 7](docs/adr/0007-one-row-order-shared-by-three-tables.md)).

## 5. Runtime

**Startup** — load the packed data (35,312 chars → 26,484 bytes, about 1 ms), build the index tables, restore the save slot. Decode each base64 string resource to a `ByteArray` **separately** and join with `addAll`: **Monkey C string concatenation wraps modulo 65,536** rather than throwing, so joining the chunks first silently truncates the blob (70,876 chars came back as 5,340 = 70,876 − 65,536). Row buffers are *not* pre-filled.

**Row residency** — an LRU of 16 row buffers, each holding a strong reference; eviction drops the reference. A fill costs 8 ms, affordable on a screen transition and not inside an animation. Allocation is wrapped in `try`: overcommitting the pool throws. A row whose strong reference was dropped is treated as empty and refilled.

**Frame** — a 50 ms timer drives: drain the input queue → advance the runner → redraw. The runner keeps the original millisecond schedule and executes every step whose scheduled time has arrived, so sub-tick waits still fire and durations are exact ([ADR 5](docs/adr/0005-fractional-scheduler-at-20-fps.md)).

**Drawing a sprite** — `drawBitmap2` from a row buffer with `:bitmapX`/`:bitmapY`/`:bitmapWidth`/`:bitmapHeight`, `:transform` = `AffineTransform.setToScale(10, 10)`, `:filterMode` = `FILTER_MODE_POINT`, `:tintColor` = the ink colour. **Pass `x - 10 * srcX`, `y - 10 * srcY` as the destination**: with a transform set the device draws at `(x, y) + T * (bitmapX, bitmapY)`, so an uncompensated call puts the sprite off-screen and draws nothing. The tint is a multiply over white ink, so the same cell draws in any colour, and the transparent field lets it composite over what is already on screen.

**Drawing text** — uppercase the string, then blit glyph by glyph, advancing by each glyph's own advance and dropping it by its own **vertical bearing** (Unity's `vert.y`, which sits Big's letters 2 px below its digits). `\n` breaks lines; **nothing wraps**. Characters with no glyph are skipped entirely ([ADR 10](docs/adr/0010-missing-glyphs-are-skipped.md)). Text clips at the canvas, not at its own rect; the rect exists for alignment. **Centre alignment halves the leftover width in device pixels, not game pixels**: the scene canvas is `m_PixelPerfect: 0`, so a line 3 game px wider than its box sits at −1.5 game px, which 10× expresses exactly and game-pixel rounding shifts by one.

**Input** — see [ADR 9](docs/adr/0009-input-mapping.md). Down is `onDrag START` or `onHold`; up is `onDrag STOP` or `onRelease`; `onSwipe` is consumed; `onBack` is consumed and delivered as B.

**Saving** — RAM-resident state committed at checkpoints ([ADR 8](docs/adr/0008-positional-save-format.md)). **Keep the `.prg` filename stable and ≤ 8 characters**, or every existing save is orphaned.

## 6. Order of work

1. **Skeleton**: manifest, resources, the three packers wired into the build, a blank canvas at the right colours.
2. **Renderer + display list**: draw a static screen from row buffers. This proves the whole asset path.
3. **Input adapter**: the twelve events, the queue, the `(:debug)` simulator adapter.
4. **Logic layer**, translated file by file, `(:extendedCode)`. `C_Int` first — everything else depends on it.
5. **Text renderer**.
6. **Vertical slice: Status + Database.** Touches the atlas, the renderer, menus, saves, input and text without needing a single animation.
7. **Runner + fibers**, then the 4 linear coroutines, to validate the conversion pipeline end to end.
8. **Battle**, the heaviest surface: `Battle.cs` (1,068 lines) and its animations.
9. The remaining apps and minigames.
10. `StartGameAnimation` (236 lines, 48 yields) last.

## 7. Verification

Every check runs in CI ([ADR 12](docs/adr/0012-verification-is-generated-not-transcribed.md)). Current results:

| Check | Result |
|---|---|
| Sprite round-trip against source PNGs | 2,423 / 2,423 |
| Glyph round-trip | 113 / 113 |
| Database read back from the device | 593 records, 9,488 fields, 0 mismatches |
| Numeric parity, C# ↔ Monkey C | 16,211 values, 0 differences (floats bit-exact) |
| Animation events against the golden trace | 150 / 150 |
| Coroutines traceable from the real source | 53 / 53, 6,911 events |
| Rendered frame against the atlas, read back off the device | 576 / 576 pixels per cell, two cells |
| Same, drawn inverted (tinted ink over a black box) | 576 / 576 |
| Flipped blits (h, v, both) against the atlas | 576 / 576 each |
| Text canvas against the font metrics, read back off the device | 102,400 / 102,400 device pixels, 5 strings |

`tools/verify_numeric.py` runs the numeric-parity check on both sides at once: the C# side compiles the **original** `Logic/Models/Digimon.cs` against a Mathf shim, the Monkey C side compiles the **ported** `app/source/Logic/Digimon.mc` through its own jungle `sourcePath`, and the two sweeps are diffed line for line. Float results are compared as IEEE-754 bit patterns, so a one-ULP difference — the thing that moves a floor boundary elsewhere — cannot hide behind a decimal rendering. It covers `MaxExtraLevel`, `GetSpiritCost`, `GetCallCost`, `GetBossLevel`, `GetObeyChance`, `GetIdleChance`, `GetEvolveChance`, `GetBossStats`, `GetFriendlyStats` and `GetEnergyRank`. **`Mathf.RoundToInt` is half-to-even and Monkey C's `Math.round` is not**, so the port has its own `roundToInt`; this check is what would have caught the difference.

`tools/verify_render.py` runs the render-parity check: it resolves the sprite reference out of `build/data.bin` — the bytes the device itself reads — samples the centre of each 10× block of a captured frame, and diffs. It is what caught both device behaviours above; neither was visible in a screenshot at a glance.

`tools/verify_text.py` is the font-metrics check: `tools/text_probe.json` holds a fixed string set covering all three faces, every anchor the source uses, the vertical bearing, a line break, a name with parentheses (no glyph, so it must vanish) and inversion; `tools/gen_text_probe.py` generates the scene the app draws from that spec and the checker computes the expected 320 × 320 canvas from the same spec, so neither side can drift. It caught the half-pixel centring rule above.

One check still to be built: **per-coroutine golden diffs** as each of the 60 is converted.

## 8. Known open items

- **Every render timing here is the simulator.** The frame budget, the 8 ms row fill and the ~30 sprites per frame all need re-measuring on hardware before anything depends on them.
- Whether Unity draws *nothing* for a missing glyph, or a blank box that consumes advance, needs confirming against a running original.
- `SaveFormat`'s seeding of `bosses` and `semibossGroup` has not been checked against `WorldManager.cs`; the round-trip proves the format, not the initial values.
- The 20-entry cap on `lostSpirits` is inferred, not verified against the game's own maximum.
- Per-minigame timing and input treatment, the D-Tector frame art around the canvas, localization, and the evolution/D-Dock/spirit rules are unsurveyed.
