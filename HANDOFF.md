# Handoff: where the build stands

Companion to [SPEC.md](SPEC.md), which is the *specification* and does not change much. This file is the *state*: what is built, what is proven, what to do next, and which traps are already known. Update it at the end of a working session.

Last updated: 2026-09-06, at commit `28a23b4`.

## 1. Set this up first — it is not in the repo

Two things every packer and every build needs, and neither survives a fresh machine or a wiped scratchpad:

**The C# source.** The packers read `kaisadilla/D-Tector-v2` through `DTECTOR_SRC`; `tools/common.py` defaults to an old session scratchpad that will not exist.

```sh
git clone --depth 1 https://github.com/kaisadilla/D-Tector-v2.git /tmp/dtector
export DTECTOR_SRC=/tmp/dtector
```

**A signing key.** Throwaway and self-signed — this is a personal sideload, never a store build. `.scratch/keys/` is gitignored.

```sh
mkdir -p .scratch/keys
openssl genrsa -out /tmp/dev.pem 4096
openssl pkcs8 -topk8 -inform PEM -outform DER -in /tmp/dev.pem \
  -out .scratch/keys/developer_key.der -nocrypt
```

Then: `tools/build.sh` builds (debug, `venu445mm`, currently 491 KB against a 786 KB ceiling). The simulator has to be running for anything that executes: `"$CIQ_SDK/bin/connectiq" &`, then `"$CIQ_SDK/bin/monkeydo" build/dtector.prg venu445mm`.

`~/.dotnet/dotnet` is needed only by the numeric parity check.

## 2. What exists

```
app/source/
  DTectorApp.mc, DTectorView.mc   host: builds the scene, drives the 20 fps tick,
                                  routes input, and carries the verification probes
  Data/       GameData.mc         reads the packed blob (ADR 6)
              WellKnown.mc        GENERATED: the 8 literal Digimon names as indices
  Input/      InputAdapter.mc     twelve abstract events + the queue (ADR 9)
  Save/       SaveFormat.mc       the positional save blob (ADR 8)
  Render/     AtlasCache.mc       row buffers, LRU of 16 (ADR 3)
              Blit.mc             the drawBitmap2 rules: transform offset, tint, flips
              Renderer.mc         walks the display list once per frame
              ScreenElement.mc    the display list: 4 builders, ~24 operations
              ScreenBuilder.mc    ScreenElement.cs's static creators
              TextRenderer.mc     glyph-by-glyph bitmap text
              FontMetrics.mc      GENERATED from the .fontsettings
              SpriteDatabase.mc   GENERATED from the Unity scene: 215 UI sprites
              TextProbe.mc        GENERATED from tools/text_probe.json
  Logic/      CInt.mc, Enums.mc, Constants.mc, MathExt.mc, Digimon.mc,
              Database.mc, SavedGame.mc, LogicManager.mc, WorldManager.mc,
              GameManager.mc, IllegalBoundsException.mc
  Apps/       DigiviceApp.mc      base app: the twelve inputs, screen, tick
              Status.mc           the first real app, all seven of its screens
```

Generated files are marked GENERATED and say which tool writes them. Never hand-edit one; ADR 12 is the reason.

Against SPEC section 6's order of work:

| Step | State |
|---|---|
| 1. Skeleton | done |
| 2. Renderer + display list | done |
| 3. Input adapter | done |
| 4. Logic layer | **in progress** — the foundation and the Status/Database dependencies are translated; everything else is not |
| 5. Text renderer | done |
| 6. Vertical slice: Status + Database | **half** — Status runs; DatabaseApp is not started |
| 7. Runner + fibers, then the 4 linear coroutines | not started |
| 8. Battle | not started |
| 9. The remaining apps and minigames | not started |
| 10. `StartGameAnimation` | not started |

## 3. What is proven, and how to re-run it

Every check reads a frame back off the device or diffs two real implementations. None of them trusts a screenshot glance — both device bugs found so far were invisible that way.

| Check | Result | How |
|---|---|---|
| Sprite round-trip vs source PNGs | 2,423 / 2,423 | `tools/pack_sprites.py` |
| Glyph round-trip | 113 / 113 | `tools/pack_fonts.py` |
| UI sprite resolution | 215 resolved, 1 unassigned in the scene | `tools/pack_ui_sprites.py` |
| Numeric parity, original C# ↔ ported Monkey C | 16,211 values, 0 differences, floats bit-exact | `tools/verify_numeric.py` |
| Rendered sprite vs atlas (normal) | 576 / 576 | set `_probeIndex`, capture, `tools/verify_render.py <png> 8` |
| Rendered sprite vs atlas (inverted) | 576 / 576 | also set `_probeInvert`, then `... --inverted` |
| Text canvas vs font metrics | 102,400 / 102,400 device px | set `_probeText`, capture, `tools/verify_text.py <png>` |
| Flipped blits (h, v, both) | 576 / 576 each | one-off probe; the rule is in `Blit.mc` |

Capture is `tools/sim_capture.sh /abs/path.png` — it drives the simulator's own File ▸ Save Screen Capture through System Events, because the SDK has no CLI for it.

The probe flags live at the top of `DTectorView.mc` (`_probeIndex`, `_probeInvert`, `_probeText`, `_probeStatusScreen`). Set one, rebuild, run, capture. **Reset them to `-1` / `false` / `0` afterwards.**

Still to build: **per-coroutine golden diffs**, one per coroutine as each of the 60 is converted (step 7 blocks on the runner existing).

## 4. Device facts that cost time to find

All measured, all already encoded in the code that depends on them — listed here so nobody re-derives them.

- `drawBitmap2` with a `:transform` draws at `(x, y) + T * (bitmapX, bitmapY)`. Uncompensated, a cell 120 px into a row lands 1,200 px off-screen and draws **nothing**.
- `:tintColor` is a **multiply**, not a replacement. Hence white ink on a transparent field in every atlas: white × tint = tint, and black × anything = black.
- A `BufferedBitmap` created **with** a `:palette` is itself palettised, so `drawBitmap2` refuses it as a source. Row buffers must be palette-free — which is also what preserves alpha.
- A negative scale factor makes the drawn span run backwards from the anchor: the flip compensation is `+scale * (src + size)` on the flipped axis.
- Monkey C string concatenation **wraps modulo 65,536** rather than throwing. Decode each base64 chunk separately and join the `ByteArray`s.
- `Mathf.RoundToInt` is half-to-**even**; Monkey C's `Math.round` is not. Use `Kaisa.MathExt.roundToInt`.
- Unity's canvas is `m_PixelPerfect: 0`, so centred text lands on half game pixels. Halve the leftover width in **device** pixels.
- The watchdog kills a callback that scans all 593 names (each is a string decode). Anything that looks like a name lookup belongs at build time.
- `<bitmap>` resources need `dithering="none"` **and** an explicit `<palette>`, or the compiler quantises to 4 bpp and drops isolated ink pixels.

## 5. What to do next

**Immediately: `DatabaseApp` (`Logic/Apps/DatabaseApp.cs`, 484 lines)** — the other half of the vertical slice. It is the right next thing because it exercises what Status did not: menus with a cursor, paging through 593 entries, the element/stage/rarity art, and the D-Dock section. It needs, roughly in this order:

1. `Logic/Models/Menu.cs` (43 lines) — the cursor/paging model.
2. The `Database`-side accessors it reads: names, numbers, stages, elements, evolution lines, `extraEvolutions` (the packed `extraEvo` section has no reader yet).
3. `LogicManager`'s Digimon-data region (`GetDigimonExtraLevel`, ownership, digicode unlocks) — the file already carries the player-stat half and a `port of` line per method, so keep appending in source order.
4. The app itself, with `DigiviceApp` as its base, plus whichever `Kaisa.Sprites.DATABASE_*` constants it names.

**Then, in order:**

- **The host that owns the apps.** `LogicManager`'s screen state machine plus `AppLoader`, `Camp`, and the main menu, so apps can actually be opened and closed. Today `DTectorView.closeLoadedApp` only logs, and `Status` is started directly.
- **Step 7: the runner and fibers**, then the four linear coroutines, to validate the conversion pipeline end to end (ADR 4, ADR 5). This unblocks every animation and is what the per-coroutine golden check hangs off.
- **Step 8: Battle** (1,068 lines plus its animations), the heaviest surface.
- Steps 9 and 10: the remaining apps and minigames, then `StartGameAnimation` last.

## 6. Traps and loose ends

- **`DTectorView` is scaffolding.** `seedSkeletonStats` writes demo stats into the save record in RAM (never committed) so the Status screens have numbers of varying width; the probe flags build fixed scenes instead of the game. All of it comes out when the real host in step 5 above lands.
- **`Database.indexOfCode` will trip the watchdog** the way `indexOfName` did: it decodes 593 strings. Compare at the byte level before CodeInput ships.
- **Every render timing in SPEC is the simulator.** The frame budget, the 8 ms row fill and the ~30 sprites per frame all need re-measuring on hardware before anything depends on them.
- **Worlds, areas and bosses are unsurveyed.** `WorldManager` carries only the two counters Status reads; the rest is deliberately absent rather than guessed, and SPEC section 8 lists what is unknown.
- `SaveFormat`'s seeding of `bosses` and `semibossGroup` has not been checked against `WorldManager.cs`; the round-trip proves the format, not the initial values.
- The 20-entry cap on `lostSpirits` is inferred, not verified.
- Whether Unity draws *nothing* for a missing glyph or a blank box that consumes advance still wants confirming against a running original (ADR 10 chose "nothing").
- `.scratch/d-tector-venu4/` is the wayfinder map that produced SPEC and the ADRs. It is **history**, not the current plan; read SPEC first.
