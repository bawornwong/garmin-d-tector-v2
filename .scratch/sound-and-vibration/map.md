# Map: Sound and vibration

Label: `wayfinder:map`

## Destination

The port **makes sound and vibrates on the wrist**. Every sound the original plays is reproduced as a melody the watch's own tone generator plays — extracted from the source MP3s by a tool, not transcribed by hand — and a curated set of events also vibrate.

Done when: it plays on the watch; the existing trace diffs (53/53 animations, 27/27 screens) still pass **untouched**; the extraction is generated and round-trip verified; [ADR 11](../../docs/adr/0011-audio-is-out-of-scope.md) is superseded and SPEC's out-of-scope line updated.

**This effort carries execution, not just decisions.** The destination is working code, so implementation tickets belong on this map (the wayfinder default of "plan, don't do" is overridden here deliberately).

## Notes

**Read first**: [SPEC.md](../../SPEC.md), [HANDOFF.md](../../HANDOFF.md). House style: device behaviour is settled by probe, never by assumption; generated data is never hand-edited ([ADR 12](../../docs/adr/0012-verification-is-generated-not-transcribed.md)).

**Skills every session should consult**: `mattpocock-skills:grilling` + `mattpocock-skills:domain-modeling` by default; `mattpocock-skills:research` for research tickets; `mattpocock-skills:prototype` for prototype tickets.

**Source checkout** (throwaway, re-clone if gone): `git clone --depth 1 https://github.com/kaisadilla/D-Tector-v2.git /tmp/dtector && export DTECTOR_SRC=/tmp/dtector`. Audio lives at `$DTECTOR_SRC/Assets/Audio/`.

### Settled while charting

- **Fidelity bar: reproduction, not approximation.** The source sounds are square-wave beeps and `ToneProfile` is a square-wave tone generator, so a faithful result is achievable. This is what breaks ADR 11's conclusion.
- **Extraction is a tool, not a transcription.** `tools/pack_sounds.py` → generated `SoundData.mc`, round-trip verified, in the same family as `pack_sprites.py` / `pack_fonts.py`. The round trip is what settles "reproduction or approximation" as a measurement rather than an opinion.
- **All 51 at once.** The staged "first wave" idea was premised on per-sound cost that a tool removes.
- **Playback is fibers on the existing 20 fps runner**, one per sound, scheduling **chunks of ~200–250 ms**; each chunk is a `ToneProfile` array the tone generator plays autonomously. Sub-frame note detail is the hardware's job, not the runner's. `stopSound` kills the fiber, so a stop lands within one chunk.
- **A new sound interrupts the one playing** — and this turned out to be what the original does, not a compromise. `AudioManager.cs` has a single `AudioSource` whose clip is replaced on every `PlaySound`; the overlapping `PlayClipAtPoint` alternative is commented out at every site with a note explaining why. (Charting recorded the opposite, from the Unity-channels assumption rather than from reading the file. Corrected once someone asked whether it really was one tone at a time.)
- **Vibration is curated, never ambient.** Fires on: encounter (regular and boss), every evolution, level up, reward/unlock, damage/loss, digistorm, jackpot win. Never on: any button, menu scrolling, map walking. A buzz on each of the 160 button call sites would be miserable and drain the battery.
- **Sound fires on every event; vibration only on that list.**
- **The trace events do not change.** `AudioManager` keeps emitting `Kaisa.Trace.event("sound " + name)` exactly as now and fires the real effect alongside. The proven timing is the most expensive asset in the project.
- **Call sites keep their string names**, resolved through a build-time-generated dictionary. 34 names is not the 593-name scan that tripped the watchdog, and integer constants would risk the trace text.
- **System settings are honoured**: `getDeviceSettings().tonesOn` / `.vibrateOn` gate everything. No in-app settings UI.

### Hard facts established while charting

**Platform**:
- `venu445mm` firmware exposes `Toybox.Attention` with `playTone`, `vibrate`, `ToneProfile`, `VibeProfile`; settings carry `tonesOn` and `vibrateOn`.
- **No `Toybox.Media` in the watchApp API surface** — playing an MP3/WAV is impossible. ADR 11 was right about this and stays right about it.
- `Attention.playTone()` accepts either a system `Tone` enum value **or** `{:toneProfile => Array<ToneProfile>, :repeatCount => Number}`. A `ToneProfile` is a frequency plus a duration, which is exactly the shape a square-wave beep needs.

**The source audio** (51 MP3s in `Assets/Audio/`):
- **Monophonic square waves.** `encounter_regular` has a 1094 Hz fundamental with energy at 3× (3280 Hz) and 5× (5464 Hz) and nothing even — a textbook square wave. `button_a` is a single partial at 4095 Hz, `button_b` at 4104 Hz.
- **Melodies are clean note sequences.** A crude per-frame peak tracker on `level_up` recovers a 4-note motif repeated four times (~0.10 s per note) closing on a held note of 0.43 s; `char_happy` comes out as six notes with clearly varied lengths (0.21, 0.30, 0.12, 0.10, 0.12, 0.50 s).
- **CAVEAT, and it is the reason ticket 03 exists**: that tracker picks the *loudest partial*, which is **not** the fundamental — proven by `encounter_regular`, where the loudest partial (5464 Hz) is the 5th harmonic of a 1094 Hz tone. So the note *rhythms* above are trustworthy and the *pitches* are not. The real fundamentals may be 3× or 5× lower than the numbers a naive tracker reports, which would also mean the melodies sit far lower than the 3–7.5 kHz those first readings suggested. Ticket 03 must estimate fundamentals properly (harmonic product spectrum or autocorrelation), and ticket 04's transposition worry may evaporate once it does.
- **Durations span three orders of magnitude**: `button_a` 0.081 s, `button_b` 0.123 s, `level_up` 2.24 s, `evolve_spirit` 21.1 s, `game_start` 45.8 s, `digistorm` 89.4 s.
- **Two files are dead**: `UNUSED get_digimon.mp3` and `Battle/Change boss.mp3` are referenced nowhere in the source's `Scripts/`.

**The port's audio surface**:
- `AudioManager` in `app/source/Logic/GameManager.mc` — `playButtonA`, `playButtonB`, `playCharHappy`, `playCharSad`, `playSound(name)`, `stopSound`. All trace-only today.
- **220 call sites**: `playButtonA` 106, `playButtonB` 54, `playSound` 50, `stopSound` 9, `playCharHappy` 1. ADR 11's count of 64 was the original's, and low.
- **34 distinct `playSound` names**, string literals at every call site but three (one dynamic `sound()` callback, two ternaries between two literals).
- **Timing is already proven.** `tools/anim_golden/src/Stubs.cs` emits the same `sound <name>` events the port does, so the 53/53 animation diff and 27/27 screen diff already establish *which sound fires when*, event for event. Nothing about timing is open.
- **`verify_anim.py` rewrites `DTectorView.mc` while it runs**, to set `_probeAnim` per animation, from a copy it read at startup — so editing that file mid-run silently loses the edit, and the next re-test looks like the fix simply did not work. Wait for the verifier to finish before touching it.
- **A probe record never goes through `createNewGame()`**, so any field that function initialises (notably `stepsToNextEvent = 300`) sits at `SaveFormat`'s raw class default instead, and anything a probe commits persists in the simulator's Storage into the *next* probe launch. Probe-record state has to be pinned explicitly at the call site, the way the RNG already is.
- **A literal Monkey C array past a few thousand numbers overflows `monkeyc`'s const type checker** — a real `java.lang.StackOverflowError` in `ConstTypeChecker`, which recurses once per array element, not a documented or configurable limit. Found packing the 4,106-number flat notes table; fixed by following [ADR 6](../../docs/adr/0006-packed-data-in-string-resources.md)'s existing pattern (bytes, base64, a string resource) instead of a literal array. Worth remembering for any future generated table of comparable size.

## Decisions so far

<!-- one line per closed ticket -->

- [What ToneProfile and vibrate accept](./issues/02-what-toneprofile-accepts.md): both constructors documented (Hz/ms for tone, 0-100%/ms for vibe); `vibrate` caps at 8 profiles, `:toneProfile` has no documented length or duration cap; **no stop/cancel exists for either** — `stopSound` can only halt future chunks, never a chunk already sent; whether `playTone` blocks is undocumented and falls to ticket 01; no manifest entry needed.
- [The playback engine](./issues/05-playback-engine.md): built and **verified — 53/53 animations and 27/27 screens still match, with neither verifier edited**; fibers on the existing runner in ~220 ms chunks, `stopSound` kills the fiber, a new sound interrupts the old, `tonesOn` gates it, and sound is muted outright during probes. Getting there turned up three bugs, two of them **pre-existing in `0e4be0b`** and unrelated to sound (see the ticket): a probe record never passes through `createNewGame()`, so it armed a pending event that leaked through the simulator's Storage into later probes, and `CharSad`/`CharSadShort` drew whatever character Storage held rather than the reference's hardcoded takuya.
- [The sound extractor](./issues/03-sound-extractor.md): `tools/pack_sounds.py` built and run on all 40 reachable sounds — **90.3% average round-trip, worst case 58.4%** (`destroySpirits`); all 51 source MP3s now accounted for (40 reachable, 5 orphaned fields, 6 unwired files — see the ticket); hit a real `monkeyc` compiler wall (a literal array past ~4,000 numbers overflows the const type checker) and fixed it the way ADR 6 already established — notes pack as bytes, ship as base64 in a string resource, decode once into a `ByteArray`.

## Not yet specified

- **Rate limiting.** What happens when tones are triggered faster than the generator can start them, and whether a minimum gap between tones is needed. Waits on what ticket 01 sees when it spams `playTone`.
- **Battery cost** of tones and vibration over a long play session, and whether that forces the vibration list shorter.
- **The very long sounds.** `digistorm` (89 s) and `game_start` (46 s) are faithful to the original but may be unbearable on a wrist. Whether to truncate or loop a section is a taste call that needs the hardware.
- **Whether the round-trip check earns a row** in HANDOFF's table of proven checks, now that it has a real number (90.3% average / 58.4% worst) rather than a hypothetical pass bar to design.
- **What to do with the weak round-trip group** (`destroySpirits` 58%, `digistorm` 65%, `evolutionSpirit`/`evolutionAncient`/`attackTravelVeryLong` ~79-80%, a few others in the low-to-mid 80s) — moderately noisy source audio and fast pitch movement the current segmentation tolerances don't track cleanly. Not yet sharp enough to ticket: whether it needs tighter extraction parameters, a different technique for the noisy ones, or is simply fine once heard on hardware is a call ticket 06's design session and a real listen should drive, not something to resolve by staring at a number.

  **Three fixes were tried and none earned its place — do not repeat them without new evidence:**

  1. **Median-filtering the pitch track.** Looked excellent at first (avg 90.3% → 92.7% at width 5) — but that was **measuring against the filtered track it produced**, so smoothing was flattering itself. Scored honestly against the *raw* signal every time, the real gain is ~0.25pp average (90.28% → 90.53% at width 3), and width 9 makes it worse. **The methodological trap is the finding worth keeping**: a round-trip that scores extracted notes against a *derived* reference measures self-consistency, not fidelity.
  2. **Dropping isolated chirps** (a short note far in pitch from both neighbours, folded into the previous one). Removes all 51 cleanly, and costs almost nothing on the metric (90.28% → 90.19%) — the metric cannot tell an artifact from signal, since the chirp is in the detected track either way.
  3. **The justification for (2), tested and refuted.** If chirps were harmonic slips they should sit at integer multiples of their neighbours. Only **6 of 51 do**. The median chirp-to-neighbour ratio is **0.34** — most sit *below* their surroundings, which is the shape of the lowest-peak rule finding a true fundamental on a frame where the *neighbours* settled on a harmonic. Dropping them may delete the most accurate frames in the file, not the least.

  Which leaves the honest state: the weak scores are not obviously fixable by post-processing the current estimator's output, and telling a real artifact from a real note here wants either a better fundamental estimator or an ear. The ear is cheaper and is coming with ticket 01.

## Out of scope

- **Playing audio files of any kind.** `Toybox.Media` is not available to a watchApp; this is a platform ceiling, not a preference, and it does not return unless Garmin changes the API.
- **Music or ambience the original does not have.** The fidelity anchor is the source ([ADR 1](../../docs/adr/0001-fidelity-anchor-is-the-source.md)).
- **Re-measuring render timings on hardware.** Real work, and it shares the sideload prerequisite, but it belongs to HANDOFF section 5 item 1, not to this map.
