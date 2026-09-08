# 13. Sound is tones, generated from the source's own audio

Date: 2026-09-08

## Status

Accepted. Supersedes [ADR 11](0011-audio-is-out-of-scope.md) for **sound**. Vibration is not covered here — it is still being designed (`.scratch/sound-and-vibration/`, ticket 06) and will want its own ADR or an amendment to this one.

## Context

ADR 11 ruled audio out of scope on two claims. The first is permanent: a Connect IQ watchApp has no `Toybox.Media`, so the source's 51 MP3s cannot be played, and no amount of effort changes that. The second was an inference — that approximating those sounds as tone profiles "is a project of its own, and an approximation is not a reproduction."

Measuring the source audio showed the inference was wrong:

- The sounds are **monophonic square waves**. `Battle/encounter_regular.mp3` is a 1094 Hz fundamental carrying energy at its 3rd (3280 Hz) and 5th (5464 Hz) harmonics and nothing even. `button_a.mp3` is a single 4095 Hz partial.
- `Attention.playTone` takes an **array of `ToneProfile`**, each a frequency in Hz and a duration in ms — which is exactly what a square-wave beep is made of.

A square-wave beep reproduced by a square-wave generator at the same fundamental and duration is not an approximation of that beep. It is that beep, within the resolution of the extraction.

Two further facts made the port cheap rather than speculative. The timing was **already proven**: `AudioManager`'s methods emitted trace events from the start, and the C# reference harness emits the same ones, so the 53/53 animation and 27/27 screen diffs already established *which* sound fires *when*, event for event. Nothing about timing was open — only what a sound is made of.

## Decision

**Sound is in scope, and is reproduced rather than approximated.**

1. **Extraction is generated, never transcribed.** `tools/pack_sounds.py` recovers each sound's note sequence from the source MP3s and writes `app/source/Data/SoundData.mc`. [ADR 12](0012-verification-is-generated-not-transcribed.md) governs it like any other packer.
2. **The fundamental is the lowest spectral peak clearing a noise floor**, not a harmonic product spectrum. HPS collapses on the button beeps, which carry no harmonics for it to rank against; a square wave's 1/n falloff leaves the fundamental present as *some* peak even when a harmonic is louder.
3. **Notes ship packed, not as a literal array.** Bytes (UINT16 frequency, UINT16 duration) as base64 in a string resource, exactly as [ADR 6](0006-packed-data-in-string-resources.md) does for the Digimon database. This is forced, not stylistic: a 4,106-number literal array overflows `monkeyc`'s const type checker outright — a real `StackOverflowError` in `ConstTypeChecker`, which recurses per element.
4. **Playback is a fiber on the existing 20 fps runner** ([ADR 4](0004-state-machines-not-a-data-vm.md), [ADR 5](0005-fractional-scheduler-at-20-fps.md)), scheduling chunks of roughly 220 ms that the tone generator then plays autonomously. Sub-frame note detail is the hardware's job; the runner only schedules phrases.
5. **`stopSound` means "send no more chunks".** `Attention` has no cancel for a tone already handed over, so a stop can only land at a chunk boundary — which is what bounds the chunk size from above.
6. **A new sound interrupts the one playing.** The device has one tone generator where the original had overlapping Unity channels. A button that goes silent reads as a hang, and queueing would put a sound behind the picture it belongs to, which is worse than losing it.
7. **The trace never changes.** `AudioManager` emits the same `Kaisa.Trace.event("sound " + name)` it emitted when it was trace-only, and fires the real effect alongside. The proven timing is the most expensive asset in the project and is not spent on this.
8. **System settings gate it**: `getDeviceSettings().tonesOn`. There is no in-app setting.
9. **Sound is muted outright during screen and animation probes.** A probe measures scheduled time; the trace carries the name and that time either way, so muting changes nothing a golden diff reads. Same discipline as pinning the RNG.

## Consequences

- **Verified**: 53/53 animations and 27/27 screens still match with neither verifier edited, so adding sound cost none of the existing proof.
- **The extraction has a measured quality, not an asserted one**: round-trip scored per sound against the source's own pitch track, 90.3% average, worst case 58.4% (`destroySpirits`). The weak group is noisier source material or pitch moving faster than the segmentation follows. Recorded rather than tuned — the judgement belongs on hardware.
- **Nothing has been heard yet.** Every claim here is about data and scheduling. Whether this watch's generator is audible at all, and over what frequency range, is ticket 01, and the answer could still force a transposition policy (ticket 04) — though 95% of the extracted notes sit at or below 3.4 kHz, well inside what Garmin's own documentation exercises.
- Five `AudioManager` fields in the original are never called by it, and six source MP3s are wired to nothing; all 51 files are now accounted for rather than assumed.
- A later vibration effort fills in alongside this, at the same call sites, without re-deriving any of it.
