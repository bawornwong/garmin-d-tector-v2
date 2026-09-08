# Research: What ToneProfile and vibrate accept

Source: local SDK docs, `connectiq-sdk-mac-9.2.0-2026-06-09-92a1605b2/doc/`, specifically `Toybox/Attention.html`, `Toybox/Attention/ToneProfile.html`, `Toybox/Attention/VibeProfile.html`, `Toybox/System/DeviceSettings.html`, `docs/Core_Topics/Getting_the_Users_Attention.html`, `docs/Core_Topics/Manifest_and_Permissions.html`. All primary, all local — no web fetch needed.

## 1. ToneProfile

`ToneProfile.initialize(aFrequency as Number, aDuration as Number)`. `frequency` is Hz, `duration` is ms. Both plain `Lang.Number` — **no documented minimum, maximum, or valid range for either field.** The one worked example uses 2500/5000/10000 Hz at 250 ms each, which is the only signal the docs give about a plausible frequency ceiling, and it is illustrative, not a spec. API level 3.1.0.

## 2. Array limits

**`:toneProfile` (playTone): no documented maximum length, and no documented total-duration cap.** This is a real gap, not an oversight in reading — the `playTone` doc lists only `:toneProfile` and `:repeatCount` with no size note, unlike `vibrate`, whose doc states its cap explicitly. Whatever ceiling exists (if any) is empirical, so ticket 03's chunk size and ticket 01's probe both need to establish a safe practical bound rather than trust one from a doc that doesn't give it.

**`vibrate`: documented maximum of 8 `VibeProfile` objects per call, played in sequence.** This is explicit and unambiguous, straight from the `vibrate()` doc: "takes an Array containing at least one VibeProfile object, up to a maximum of 8, and runs them in sequence."

## 3. `:repeatCount`

Repeats **the whole given tone sequence**, not the last profile alone — "Number of times to repeat the given tone sequence." No documented maximum value.

## 4. Is `playTone` asynchronous?

**Undocumented.** The signature returns `Void` and nothing in the API doc or the core-topic guide states whether the call blocks for the tone's duration or fires-and-forgets into hardware. This is exactly what ticket 01 needs to time against the 50 ms frame budget — the playback engine design (ticket 05) depends on the answer and may need to change if it blocks.

## 5. Stopping a tone or vibration in progress

**No such method exists.** The full `Attention` module method list is `backlight`, `hasFlashlightColor`, `playTone`, `setFlashlightMode`, `vibrate` — confirmed against the class's own Instance Method Summary, not inferred. `TONE_STOP` looked promising by name but is a **semantic** `Tone` enum value ("Indicates that an activity has stopped"), not a playback control — it plays a stop-sound tone, it does not stop a tone that's playing. This settles part of ticket 05's design: there is no engine-level stop to call, so `stopSound` can only ever mean "don't schedule further chunks," never "silence what's already been sent to the generator." The chunk-based design (~200–250 ms chunks) is what makes that limitation tolerable rather than a problem.

## 6. VibeProfile

`VibeProfile.initialize(dutyCycleVal as Number, lengthVal as Number)`. `dutyCycle` is **0 to 100** (%, 0 = no vibration, 100 = strongest — explicitly documented, unlike ToneProfile's frequency), `length` is ms. API level 1.0.0 (universal on this device generation).

**Caveat worth carrying into ticket 01 and ticket 06**: the doc notes "Forerunner devices do not support vibration patterns. Vibration may still be used, but the vibration will always run at the same duty cycle." That's a stated exception for one product line, not evidence about Venu 4 — but it proves duty-cycle fidelity is not guaranteed uniformly across Garmin's lineup, so ticket 01 should not assume Venu 4 honours duty-cycle gradation without checking.

## 7. Manifest and permissions

**No manifest entry or permission is required for `Attention`, `playTone`, or `vibrate`.** Checked `Manifest_and_Permissions.html` directly: the whole `Attention`/vibrate/tone surface is absent from that document. Both devices lists (Venu 4 45mm appears in both `ToneProfile`'s and `vibrate`'s supported-device lists) imply the feature check pattern already used elsewhere in this codebase (`Attention has :ToneProfile`, `Attention has :vibrate`) is the only gating needed — not a manifest declaration.

## 8. `tonesOn` / `vibrateOn`

`DeviceSettings.tonesOn` and `.vibrateOn` exist (`Lang.Boolean`), documented only as "The tone setting mode" / "The vibration setting mode" — **no statement anywhere that `playTone`/`vibrate` self-enforces these.** Nothing in the `Attention` docs references them at all. This reads as the app's own responsibility to check, which is what the map already decided (gate in `AudioManager`/vibration call sites on `getDeviceSettings().tonesOn`/`.vibrateOn`) — but whether the system *also* silently suppresses calls when a setting is off is unconfirmed by documentation and worth a quick empirical check in ticket 01 while the device is in hand (toggle the setting, see if a call that isn't self-gated still makes noise).
