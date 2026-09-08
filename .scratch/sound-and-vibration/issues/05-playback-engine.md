# The playback engine

Type: task
Status: resolved
Blocked by: 02, 03

## Question

Make `AudioManager` actually play the extracted sounds, on the terms already settled.

The shape:

1. **A sound is a fiber on the existing runner** ([ADR 4](../../../docs/adr/0004-state-machines-not-a-data-vm.md), [ADR 5](../../../docs/adr/0005-fractional-scheduler-at-20-fps.md)), one per playing sound, scheduling chunks of roughly 200–250 ms. Each chunk is a `ToneProfile` array handed to `playTone`, so notes shorter than the 50 ms frame are the tone generator's business, not the runner's.
2. **`stopSound` kills the fiber**, so a stop lands within one chunk. All nine call sites become truthful.
3. **A new sound interrupts the one playing.** One generator, and a button that goes silent feels broken.
4. **The trace events do not change.** Keep emitting `Kaisa.Trace.event("sound " + name)` exactly as now and fire the effect alongside it. `tools/verify_anim.py` (53/53) and `tools/verify_screens.py` (27/27) must pass afterwards with no edits to either — that is the acceptance test for this ticket.
5. **Names resolve through the generated dictionary**, not integer constants at call sites, so the trace text stays byte-identical.
6. **Gate on `getDeviceSettings().tonesOn`** and skip the work entirely when it is off — not just the sound, the scheduling too.
7. **Watch the frame budget.** The runner has a measured watchdog ceiling; a per-frame chunk push must not threaten it. If ticket 01 found `playTone` blocks, this design changes and the ticket needs re-cutting before it is built.

## Context

`AudioManager` is at the bottom of `app/source/Logic/GameManager.mc`. 220 call sites across `Animations.mc`, the apps and the logic layer.

Vibration is [its own ticket](./06-vibration-vocabulary.md) and fires from the curated event list, not from every sound.

## Progress

The engine is built and both builds compile: `AudioManager` takes the runner, `SoundRoutine` schedules ~220 ms chunks of `ToneProfile` onto it, `stopSound` kills the fiber, a new sound interrupts the old, and `getDeviceSettings().tonesOn` gates the lot. `Kaisa.Sounds.load()` runs beside `GameData.load()` at startup.

Getting the acceptance test (53/53 unchanged) to actually pass turned up **three** separate problems, only the first of which was this ticket's own doing:

1. **`Runner.start()` traces.** Routing sound through it emitted a `startCoroutine` event per `playSound`, which the reference has no counterpart for — every animation desynced, 0/53. Added `Runner.startSilent()` for machinery the original does not have (its `AudioManager.PlaySound` is a fire-and-forget `AudioSource.Play`, not a coroutine) and pointed `play()` at it.

2. **A stray trailing `sound triggerEvent`, on every animation** — and it survived muting sound entirely, which is what proved it was **not** this ticket's bug. Bisected by stashing the sound work and re-running against `0e4be0b` alone: it reproduces there, so it is a **pre-existing regression** that shipped in that commit unverified (that session ran the builds and the sprite round-trip, but never `verify_anim.py`). Cause: a probe record is built by `createDefault()` + `seedSkeletonStats()` and never by `createNewGame()`, so `stepsToNextEvent` keeps `SaveFormat`'s raw class default of **0** instead of the 300 a real new game sets. The first `takeSteps()` any probed animation makes therefore trips `<= 0`, arms a pending event, and **commits it to the simulator's persisted Storage**, where it leaks into every later probe in the same simulator session — and `ScreenManager.consumeNext()` faithfully calls `checkPendingEvents()` when the queue drains (`ScreenManager.cs:101`), so *any* animation's completion then fired `enqueueRegularEvent()` → `playSound("triggerEvent")`. Fixed by resetting `pendingEvent`/`stepsToNextEvent` at the probe call site, unconditionally — not inside `seedSkeletonStats`, whose `playerExperience != 0` guard would skip it on exactly the second-and-later launches that need it most.

3. **`CharSad`/`CharSadShort` drew the wrong character's sprites.** They read `gm.saved.playerChar()` instead of taking a character argument the way `OpenCamp`/`CloseCamp` do, and `tools/anim_golden/src/Builders.cs` hardcodes `GameChar.takuya`. The probe record's `gameChar` was whatever Storage happened to hold. Fixed by pinning `record.gameChar = Kaisa.CHAR_TAKUYA` alongside the other probe-record resets.

**A trap worth writing down:** `verify_anim.py` rewrites `DTectorView.mc` (to set `_probeAnim`) from a copy it read at startup, so **editing that file while the verifier is running silently loses the edit** — fix 3 was clobbered exactly that way and looked like it had failed on re-test.

## Answer

**Both halves of the acceptance test pass, with the trace untouched: `tools/verify_anim.py` 53/53 animations (`StartGameAnimation` included, 931/931 events) and `tools/verify_screens.py` 27/27 screens.** Neither verifier was edited. Debug and release both build clean, and the probe flags are back at their defaults.

The full 53 had to be run in **batches of six** — the dev machine was under real memory pressure from unrelated applications and its OOM killer took two whole-suite runs. Batching also means partial results survive a kill, which is worth keeping in mind for anyone re-running this on a loaded machine: `timeout 900 python3 -u tools/verify_anim.py <six names>`, in nine passes.

Everything the map settled is in place: fibers on the existing runner, ~220 ms chunks, interrupt-on-new-sound, `stopSound` killing the fiber, `tonesOn` gating, names resolved through the generated dictionary, and the trace emitted exactly as it was when this was trace-only.

One thing this ticket added that the map did not anticipate: **sound is muted outright during screen and animation probes**. A probe measures scheduled time, and the real `Attention.playTone` call costs wall-clock time on a machine whose audio stack the simulator cannot drive (see below) — pinning that off is the same discipline as pinning the RNG.
