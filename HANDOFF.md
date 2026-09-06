# Handoff: where the build stands

Companion to [SPEC.md](SPEC.md), which is the *specification* and does not change much. This file is the *state*: what is built, what is proven, what to do next, and which traps are already known. Update it at the end of a working session.

Last updated: 2026-09-06, at commit `7a11c80` (StartGameAnimation and CreateNewGame).

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

Then: `tools/build.sh` builds (debug, `venu445mm`, currently **781 KB against a 786 KB ceiling** — see the traps: this is now the first thing that will break). The simulator has to be running for anything that executes: `"$CIQ_SDK/bin/connectiq" &`, then `"$CIQ_SDK/bin/monkeydo" build/dtector.prg venu445mm`.

`~/.dotnet/dotnet` is needed only by the numeric parity check.

## 2. What exists

```
app/source/
  DTectorApp.mc, DTectorView.mc   host: builds the scene, drives the 20 fps tick,
                                  routes input, and carries the verification probes
  Data/       GameData.mc         reads the packed blob (ADR 6)
              WellKnown.mc        GENERATED: every Digimon the source names as a
                                  literal, as indices -- the 8 defaults plus the
                                  ancient pairs, the fusion spirit lists and the
                                  fusion element sets
  Input/      InputAdapter.mc     twelve abstract events + the queue (ADR 9)
  Save/       SaveFormat.mc       the positional save blob (ADR 8)
  Anim/       Runner.mc           Routine / Fiber / Runner (ADR 4 + ADR 5)
              Animations.mc       the converted coroutines, 40 of 53 so far
              Trace.mc            the debug-only event trace the goldens read
  Render/     AtlasCache.mc       row buffers, LRU of 16 (ADR 3)
              Blit.mc             the drawBitmap2 rules: transform offset, tint, flips
              Renderer.mc         walks the display list once per frame
              ScreenElement.mc    the display list: 4 builders, ~24 operations
              ScreenBuilder.mc    ScreenElement.cs's static creators
              ScreenManager.mc    the character/menu screens, the blinking
                                  overlays and the animation queue
              TextRenderer.mc     glyph-by-glyph bitmap text
              FontMetrics.mc      GENERATED from the .fontsettings
              SpriteDatabase.mc   GENERATED from the Unity scene: 215 UI sprites
              TextProbe.mc        GENERATED from tools/text_probe.json
  Logic/      CInt.mc, Enums.mc, Constants.mc, MathExt.mc, Digimon.mc,
              Database.mc, SavedGame.mc, LogicManager.mc, WorldManager.mc,
              GameManager.mc, PlayerCharacter.mc, IllegalBoundsException.mc
  Apps/       DigiviceApp.mc      base app: the twelve inputs, screen, tick
              AppLoader.mc        the App enum; makes an app, null if untranslated
              Status.mc           the first real app, all seven of its screens
              DatabaseApp.mc      six screens, three converted coroutines
              CodeInput.mc        the five-character code entry
              Finder.mc           the battle-search minigame
              DigiHunter.mc       the 3x3 face-hunting minigame
              SpeedRunner.mc      the three-lane rocket minigame
              Maze.mc             the 15x12 maze minigame
              Map.mc              the world map: pan, pick an area, travel
              JackpotBox.mc       the pattern-repeating reward minigame
              Battle.mc           eight screens, the turn loop, win/lose/escape
              Camp.mc             the smallest app; clears the defeated flag
```

Generated files are marked GENERATED and say which tool writes them. Never hand-edit one; ADR 12 is the reason.

Against SPEC section 6's order of work:

| Step | State |
|---|---|
| 1. Skeleton | done |
| 2. Renderer + display list | done |
| 3. Input adapter | done |
| 4. Logic layer | **done** — including `CreateNewGame` and `HasAllSpiritsForFusion`; the last stub in `GameManager` is gone |
| 5. Text renderer | done |
| 6. Vertical slice: Status + Database | **done** — both apps run, opened from the real main menu |
| 7. Runner + fibers, then the 4 linear coroutines | **done** — runner with concurrent fibers, the 4 linear coroutines converted and diffed against the original, plus 6 app-local ones |
| 8. Battle | **done** — every screen, the turn loop and the three endings; its animations are converted (`DisplayTurn` and everything under it) but not yet wired into the app's call sites |
| 9. The remaining apps and minigames | **done** — every app the original implements is translated |
| 10. `StartGameAnimation` | **done** — 931 events, matched exactly, and `CreateNewGame` plays it |

## 3. What is proven, and how to re-run it

Every check reads a frame back off the device or diffs two real implementations. None of them trusts a screenshot glance — both device bugs found so far were invisible that way.

| Check | Result | How |
|---|---|---|
| Sprite round-trip vs source PNGs | 2,423 / 2,423 | `tools/pack_sprites.py` |
| Glyph round-trip | 113 / 113 | `tools/pack_fonts.py` |
| UI sprite resolution | 215 resolved, 1 unassigned in the scene | `tools/pack_ui_sprites.py` |
| Numeric parity, original C# ↔ ported Monkey C | 16,211 values, 0 differences, floats bit-exact | `tools/verify_numeric.py` |
| Packed gallery order vs the original's `OrderBy(order)` | 8 / 8 stages, 593 rows | `tools/verify_gallery.py` |
| Packed world layout vs `worlds.json` | 225 / 225 fields | `tools/verify_worlds.py` |
| Converted animations vs a golden trace of the original | 32 / 32, 4,257 events | `tools/verify_anim.py` (~10 minutes: it rebuilds and runs the app once per animation) |
| Rendered sprite vs atlas (normal) | 576 / 576 | set `_probeIndex`, capture, `tools/verify_render.py <png> 8` |
| Rendered sprite vs atlas (inverted) | 576 / 576 | also set `_probeInvert`, then `... --inverted` |
| Text canvas vs font metrics | 102,400 / 102,400 device px | set `_probeText`, capture, `tools/verify_text.py <png>` |
| Flipped blits (h, v, both) | 576 / 576 each | one-off probe; the rule is in `Blit.mc` |

Capture is `tools/sim_capture.sh /abs/path.png` — it drives the simulator's own File ▸ Save Screen Capture through System Events, because the SDK has no CLI for it.

The probe flags live at the top of `DTectorView.mc` (`_probeIndex`, `_probeInvert`, `_probeText`, `_probeStatusScreen`). Set one, rebuild, run, capture. **Reset them to `-1` / `false` / `0` afterwards.**

The animation check is per coroutine: add the new one to `CONVERTED` in `tools/verify_anim.py` and to the probe list in `DTectorView.startAnimProbe`, and it is checked against the original from then on.

Three things about that harness are worth knowing before touching it:

- **Both sides are real code.** The reference compiles the checkout's own `Animations.cs` against display-list stubs, and reads the real `sprite_index.json` and `worlds.json`. Every mismatch found so far but one was the *reference* under-reporting — a stubbed `BuildStatSign`, a `ReorderedAs` that returned its input, elements that registered under the wrong parent — never the port. Suspect the stub first.
- **The RNG is pinned on both sides.** The port reproduces the original's RNG *semantics*, not its sequence (ticket 11 decision 4), so an animation whose length depends on a roll could never agree by accident. `FIXED_RNG` in `verify_anim.py` goes to the harness as `DTECTOR_RNG` and to the port as `_probeRand` → `Kaisa.Rand.forced` (debug only).
- **The probe runs the clock fast.** Ten runner steps per frame, and the app exits itself at `ANIMEND`. Events carry their *scheduled* time, so the traces are identical — a 53-second animation costs the verifier about five seconds. The verifier also reaps monkeydo's lingering java client after every probe and retries an empty trace against a restarted simulator; without that, a long run degenerates into a wall of "emitted nothing".

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

`Animations.cs` is 40 of its 53 coroutines. **32 are committed and verified; 8 are written, built and wired to probes 32-39 but NOT yet run through `verify_anim.py`** — that is the first thing to do, before anything else is added:

```sh
export DTECTOR_SRC=...            # the checkout, see section 1
python3 tools/verify_anim.py EncounterEnemy EncounterBoss SpendCallPoints \
    DeportSprite DeportDigimon DeportSpirit ReceiveSpirit LoseSpirit
```

Then, in order:

1. **The thirteen coroutines still untranslated.** `LoadCharacterSelection`, `AwardDistance`, `TravelMap`, `ForcedTravelMap`, `SusanoomonEvolution`, `BoostFailed`, `BoostSucceed`, `DestroyBox`, `BoxResists`, `StartAppDigiHunter`, `TransitionToMap1`, `TransitionToMap3`, `EnemyEscapes`. None is harder than what is already done; `TravelMap` and the two transitions are the longest.
2. **Wire the call sites.** There are ~40 `enqueueAnimation(null)` left, mostly in `Battle` (27) and `JackpotBox` (6), and most of them now have their animation. Each names the one it is waiting for. `EnqueueRewardAnimation` is already wired, and so is `CreateNewGame`.
3. **The character-selection screen**, which is the one thing `CreateNewGame` still fakes: it uses the save record's default character instead of asking. `LoadCharacterSelection` is the animation behind it.
4. **Re-measure on hardware.** Every render timing in SPEC is the simulator's, and nothing has run on a watch yet.

## 6. Traps and loose ends

- **`DTectorView` still carries scaffolding**, though it now boots the real host: `seedSkeletonStats` writes demo stats and a spread of unlocked Digimon into the save record in RAM (never committed) so the screens have something to show; `_sliceApp` can open one app directly instead of starting on the character screen; `_probeInputs` replays a scripted press sequence so a capture can reach a screen several presses deep.
- **The character screen shows a character but nothing else.** The pending-event machinery and `TakeAStep` are not translated, so `isEventPending` is never set and the event/eyes overlays never show. `CreateNewGame` IS translated now, and runs when slot 0 is empty.
- **The debug build is 781 KB against a 786 KB ceiling.** This is the next thing that will break, and it will break as an opaque build failure. The trace, the probes and `TRACE_NAMES` are all `(:debug)` and all in that build; the release build is far smaller and does not carry them. When it hits, the fix is to move the animation probes and the sprite name table behind their own exclude annotation so a normal debug build does not carry them, rather than to delete anything.
- **`Animations.cs` is 40 of 53 translated.** `GameManager.enqueueAnimation` still takes null at ~40 call sites; each says which animation it is waiting for, and most of those animations now exist and only need wiring.
- **The reference harness under-reports more often than the port is wrong.** Every animation mismatch found so far but one came from a stub that did less than the real `ScreenElement.cs` — `BuildStatSign` building nothing, `ReorderedAs` returning its input, `BuildMapScreen` as a bare container, elements registering under `AnimParent` instead of their real parent, `Destroy` not unparenting. Check the stub before the port.
- **Two `Kaisa.Sprites` fields can be the same cell** (`animDistance` and `games_distance` are one sprite), so the debug name lookup is ambiguous by nature; `verify_anim.py` canonicalises names to cells rather than trusting them.
- **Every render timing in SPEC is the simulator.** The frame budget, the 8 ms row fill and the ~30 sprites per frame all need re-measuring on hardware before anything depends on them.
- **The save format is version 2.** Version 1 slots are refused (and logged) rather than decoded: the world arrays are sized from the packed data, so an old slot would run off the end of the blob. There is no migration; the port has no released saves to migrate.
- The 20-entry cap on `lostSpirits` is inferred, not verified.
- Whether Unity draws *nothing* for a missing glyph or a blank box that consumes advance still wants confirming against a running original (ADR 10 chose "nothing").
- `.scratch/d-tector-venu4/` is the wayfinder map that produced SPEC and the ADRs. It is **history**, not the current plan; read SPEC first.
