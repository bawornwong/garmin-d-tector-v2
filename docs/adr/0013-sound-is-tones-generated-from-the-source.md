# 13. Sound is tones, generated from the source's own audio

Date: 2026-09-08

## Status

Accepted. Supersedes [ADR 11](0011-audio-is-out-of-scope.md) for **sound**.

Vibration is half-covered, and the halves are worth separating. Its **mechanism** is decided and built (decision 10 below): which events vibrate, that it rides on the sound name rather than call sites of its own, that it is untraced, and that it honours `vibrateOn` independently of `tonesOn`. Its **values** — how each one actually feels — are not decided, have never been felt, and are ticket 06. If the felt result forces a different shape (for instance if this watch ignores duty cycle, as Garmin documents Forerunners doing), that would amend decision 10 rather than the sound decisions above it.

## Context

ADR 11 ruled audio out of scope on two claims. The first is permanent: a Connect IQ watchApp has no `Toybox.Media`, so the source's 51 MP3s cannot be played, and no amount of effort changes that. The second was an inference — that approximating those sounds as tone profiles "is a project of its own, and an approximation is not a reproduction."

Measuring the source audio showed the inference was wrong:

- The sounds are **monophonic square waves**. `Battle/encounter_regular.mp3` is a 1094 Hz fundamental carrying energy at its 3rd (3280 Hz) and 5th (5464 Hz) harmonics and nothing even. `button_a.mp3` is a single 4095 Hz partial. Checked properly rather than on a couple of examples: across `levelUp`, `gameStart`, `digistorm`, `reward` and `charHappy`, **85–94% of sounding frames have every one of their peaks explained as an integer multiple of a single fundamental**. The rest are frames whose extra peaks sit ~2% apart (2972 / 3036 / 3101 Hz), which is the signature of modulation and the analysis window, not of a second voice — a second voice would be at a musically distinct pitch. One tone at a time is therefore a property of the material, not just of the tone generator.
- `Attention.playTone` takes an **array of `ToneProfile`**, each a frequency in Hz and a duration in ms — which is exactly what a square-wave beep is made of.

A square-wave beep reproduced by a square-wave generator at the same fundamental and duration is not an approximation of that beep. It is that beep, within the resolution of the extraction.

Two further facts made the port cheap rather than speculative. The timing was **already proven**: `AudioManager`'s methods emitted trace events from the start, and the C# reference harness emits the same ones, so the 53/53 animation and 27/27 screen diffs already established *which* sound fires *when*, event for event. Nothing about timing was open — only what a sound is made of.

## Decision

**Sound is in scope, and is reproduced rather than approximated.**

1. **Extraction is generated, never transcribed.** `tools/pack_sounds.py` recovers each sound's note sequence from the source MP3s and writes `app/source/Data/SoundData.mc`. [ADR 12](0012-verification-is-generated-not-transcribed.md) governs it like any other packer.
2. **The fundamental is the lowest spectral peak clearing a noise floor**, not a harmonic product spectrum. HPS collapses on the button beeps, which carry no harmonics for it to rank against; a square wave's 1/n falloff leaves the fundamental present as *some* peak even when a harmonic is louder.
3. **Notes ship packed, not as a literal array.** Bytes (UINT16 frequency, UINT16 duration) as base64 in a string resource, exactly as [ADR 6](0006-packed-data-in-string-resources.md) does for the Digimon database. This is forced, not stylistic: a 4,106-number literal array overflows `monkeyc`'s const type checker outright — a real `StackOverflowError` in `ConstTypeChecker`, which recurses per element.
4. **Playback is a fiber on the existing 20 fps runner** ([ADR 4](0004-state-machines-not-a-data-vm.md), [ADR 5](0005-fractional-scheduler-at-20-fps.md)), scheduling chunks of roughly 220 ms that the tone generator then plays autonomously. Sub-frame note detail is the hardware's job; the runner only schedules phrases.
5. **`stopSound` means "send no more chunks".** `Attention` has no cancel for a tone already handed over, so a stop can only land at a chunk boundary — which is what bounds the chunk size from above. **A note longer than one chunk is split across chunks at the same frequency**, so the bound is genuinely `CHUNK_MS` rather than "the longest note in the sound". Without that split the bound was as loose as the longest note — measured at 659 ms on `travelMap` and 589 ms on `digistorm`, both of which the animations really do call `stopSound` on, so the guarantee failed on exactly the sounds relying on it. A sustained tone delivered as consecutive profiles at one frequency is the same waveform continuing; that it is *audibly* seamless is assumed and wants confirming by ear (ticket 01).
6. **A new sound interrupts the one playing** — which is what the original does, not a compromise forced by the watch. `AudioManager.cs` holds a single `AudioSource` and every `PlaySound` is `source.clip = sound; source.Play();`, replacing whatever was playing. The overlapping alternative is present in the file as commented-out `AudioSource.PlayClipAtPoint` calls at every site, with a note at the top explaining why it was abandoned. So one sound at a time is faithful, and it happens to suit a device with one tone generator. (An earlier draft of this ADR claimed the original had overlapping channels; it does not.)
7. **The trace never changes.** `AudioManager` emits the same `Kaisa.Trace.event("sound " + name)` it emitted when it was trace-only, and fires the real effect alongside. The proven timing is the most expensive asset in the project and is not spent on this.
8. **System settings gate it**: `getDeviceSettings().tonesOn`. There is no in-app setting.
9. **Sound is muted outright during screen and animation probes.** A probe measures scheduled time; the trace carries the name and that time either way, so muting changes nothing a golden diff reads. Same discipline as pinning the RNG.
10. **Vibration rides on the sound name, and has no call sites of its own.** Every event the map curates for vibration — the two encounters, the four evolutions, level up, reward and the unlocks, damage and loss, and the digistorm's onset — already plays a distinctive sound, so a table keyed by that name is the entire hook. A sound absent from the table does not vibrate, which is what keeps all 160 button call sites, menu scrolling and map steps silent. It is untraced for the same reason the sound fiber is (the original has no vibration; an event here has no counterpart to diff against), and it checks `vibrateOn` *before* `tonesOn`, so sound-off-with-vibration-on behaves as the wearer asked.

## Consequences

- **Verified**: 53/53 animations and 27/27 screens still match with neither verifier edited, so adding sound cost none of the existing proof.
- **The extraction has a measured quality, not an asserted one**: round-trip scored per sound against the source's own pitch track, 90.3% average, worst case 58.4% (`destroySpirits`). The weak group is noisier source material or pitch moving faster than the segmentation follows. Recorded rather than tuned — the judgement belongs on hardware.
- **Nothing has been heard yet.** Every claim here is about data and scheduling. Whether this watch's generator is audible at all, and over what frequency range, is ticket 01, and the answer could still force a transposition policy (ticket 04) — though 95% of the extracted notes sit at or below 3.4 kHz, well inside what Garmin's own documentation exercises.
- Five `AudioManager` fields in the original are never called by it, and six source MP3s are wired to nothing; all 51 files are now accounted for rather than assumed.
- The vibration effort did fill in alongside this without re-deriving any of it, and without needing call sites of its own -- see decision 10. What it still lacks is a wrist.
