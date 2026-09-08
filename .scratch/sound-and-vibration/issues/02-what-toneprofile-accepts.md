# What ToneProfile and vibrate accept

Type: research
Status: resolved
Blocked by: —

## Question

What does the Connect IQ API *specify* for `Attention.playTone` and `Attention.vibrate`, so ticket 03 knows what shape to generate for and ticket 05 knows what it can rely on?

This is the documented contract; ticket 01 is what the device actually does. Where they disagree, the device wins — but the extractor cannot be written against nothing.

Answer all of:

1. **`ToneProfile`** — exact constructor and fields. What are the documented frequency bounds and the duration bounds? Integer Hz and ms, or something else?
2. **Array limits** — is there a documented maximum length for the `:toneProfile` array? Is there a total-duration cap?
3. **`:repeatCount`** — what does it repeat, the whole array or the last profile, and is there a maximum?
4. **Is `playTone` asynchronous?** Does it return immediately and play in the background, and what is documented about calling it again while a tone is playing?
5. **Is there any stop or cancel** for a tone in progress?
6. **`VibeProfile`** — constructor, duty-cycle and duration ranges, array behaviour, and whether the same interrupt questions apply.
7. **Permissions and manifest** — do tone or vibration need an entry in `manifest.xml`, and does either require a `has` check for devices that lack the hardware?
8. **`tonesOn` / `vibrateOn`** — what is the documented obligation on the app, and does the system enforce it or merely advertise it?

Prefer primary sources: the local SDK docs at `~/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.2.0-*/doc/`, the Connect IQ API reference, and Garmin staff posts on the developer forum.

## Context

Findings land at `.scratch/sound-and-vibration/research/02-what-toneprofile-accepts.md`.

Already established while charting, do not re-derive: the device's API surface carries `playTone`, `vibrate`, `ToneProfile`, `VibeProfile`, `tonesOn`, `vibrateOn`, and no `Toybox.Media`. `playTone` takes either a system `Tone` enum or `{:toneProfile => Array<ToneProfile>, :repeatCount => Number}`.

## Answer

Full findings: [research/02-what-toneprofile-accepts.md](../research/02-what-toneprofile-accepts.md)

- `ToneProfile(frequency as Number /* Hz */, duration as Number /* ms */)` — **no documented bounds on either field**, and **no documented max length or total-duration cap on the `:toneProfile` array**. Both are empirical questions for ticket 01.
- `VibeProfile(dutyCycle as Number /* 0-100% */, length as Number /* ms */)` — dutyCycle range *is* documented. `vibrate()` caps at **8 profiles per call**, explicitly.
- `:repeatCount` repeats the whole tone sequence, not the last note. No documented max.
- **No stop/cancel exists for a tone or a vibration in progress** — confirmed against the full method list (`backlight`, `hasFlashlightColor`, `playTone`, `setFlashlightMode`, `vibrate`). `TONE_STOP` is a semantic tone, not a playback control. This means `stopSound` can only ever prevent scheduling further chunks, never silence one already sent to the generator — which is exactly why ticket 05's chunking (~200–250 ms) matters: it bounds how late a stop can land.
- **Whether `playTone` blocks the caller is undocumented.** Ticket 01 must time it against the 50 ms frame budget before ticket 05's fiber design can be trusted.
- **No manifest entry or permission needed** for `Attention`/`playTone`/`vibrate` — absent from `Manifest_and_Permissions.html` entirely; the existing `Attention has :X` feature-check pattern is sufficient gating.
- `tonesOn`/`vibrateOn` are plain settings with no documented self-enforcement by the API — the app gating itself (already decided on the map) is necessary regardless of whether the system also enforces it, which ticket 01 can check empirically in passing.
- Venu 4 45mm is explicitly listed as a supported device for both `ToneProfile` and `vibrate`.
