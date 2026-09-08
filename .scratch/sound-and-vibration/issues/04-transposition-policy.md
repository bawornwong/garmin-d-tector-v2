# Transposition policy

Type: grilling
Status: open
Blocked by: 01, 03

## Question

If the extracted melodies fall outside the frequency range the watch can actually produce, what happens to them?

Options, and the trade is character against audibility:

- **Transpose by octaves.** Intervals survive, absolute pitch does not. The tune is recognisable; the toy's shrill character is not.
- **Clamp to the usable range.** Preserves pitch where possible but flattens the melody where it clips, which can turn distinct notes into one.
- **Leave them and accept silence** on notes the device cannot make.
- **Nothing to do** — the likely outcome if ticket 03's proper fundamental estimation lands the melodies far below where the naive tracker put them.

Whichever is chosen applies at generation time or playback time, and that is part of the decision: baking it into `SoundData.mc` keeps the runtime simple, applying it at playback keeps the generated data faithful to the source.

## Context

The naive tracker reported pitches of 3–7.5 kHz, but those are probably harmonics, not fundamentals (see the map's caveat and ticket 03). This ticket may well resolve to "no transposition needed" — that is a real and welcome outcome, not a failure.

**The extractor has now run, and the concern looks much smaller than it did when this ticket was written.** Across all 2,036 sounded notes in `build/sound_index.json`:

| | |
|---|---|
| range | 65 Hz – 5,669 Hz |
| median | 2,643 Hz |
| 5th–95th percentile | 910 Hz – 3,413 Hz |
| above 4 kHz | 41 notes (2.0%) |

So the naive reading was inflated by roughly the harmonic factor the map's caveat predicted: **95% of the melody sits at or below 3.4 kHz**, and the whole range is inside what Garmin's own `playTone` doc exercises in its worked example (2,500 / 5,000 / 10,000 Hz). Unless ticket 01 finds this watch's generator far more limited than the documentation's example implies, the answer here is likely "nothing to do" — and if some ceiling does bite, it would affect only the 2% above 4 kHz, which is a much narrower decision than transposing whole melodies.

Still blocked, because "likely" is not "measured on the device" — but whoever picks this up should start from these numbers rather than re-deriving them.

Blocked by [Probe tone and vibration on the watch](./01-probe-tone-and-vibration-on-hardware.md) for the device's real range, and by [The sound extractor](./03-sound-extractor.md) for the real pitches.
