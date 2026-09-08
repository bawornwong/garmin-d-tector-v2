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

Blocked by [Probe tone and vibration on the watch](./01-probe-tone-and-vibration-on-hardware.md) for the device's real range, and by [The sound extractor](./03-sound-extractor.md) for the real pitches.
