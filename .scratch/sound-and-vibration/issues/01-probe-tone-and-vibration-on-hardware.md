# Probe tone and vibration on the watch

Type: task
Status: open
Blocked by: —

## Question

Does this watch actually make the sounds this effort is built on, and what are the real limits?

Everything else on this map is guesswork until a physical `venu445mm` answers. The app has never run on hardware at all ([HANDOFF](../../../HANDOFF.md) section 5 item 1), so this ticket carries the first sideload too.

Answer all of:

1. **Is a CIQ tone audible at all?** Venu has a speaker, but that is not the same as `Attention.playTone` reaching it from a watchApp. If the answer is no, this map collapses to vibration only and the destination must be redrawn.
2. **What frequency range is usable?** Play a sweep and find where it stops being audible or stops being produced at both ends. The measured note pitches are unreliable (see the map's caveat) but the range matters either way — ticket 04 is written against whatever this finds.
3. **What does a `ToneProfile` array actually do?** Confirm an array plays as a sequence, that the durations are honoured, and find the array-length ceiling if there is one.
4. **What happens under spam?** Fire tones back to back at the rate the button call sites would (up to several per second) and at frame rate. Does a new call interrupt, queue, or get dropped — and does that match the "new sound interrupts" decision, or does the platform force something else?
5. **Does `playTone` block?** Time a call against the 50 ms frame budget. A call that blocks for the length of the tone would break the runner and change the whole playback design.
6. **Can a playing tone be stopped?** If some call stops one, the chunking decision gets simpler.
7. **Vibration**: confirm `vibrate` works, and find what range of `VibeProfile` duty cycle and duration is actually distinguishable on the wrist. Ticket 06 designs against this.
8. **Do `tonesOn` / `vibrateOn` gate it**, or does the app have to check them itself?

## Context

Sideload: `tools/build.sh -r`, copy `build/dtector.prg` to `GARMIN/APPS/` over USB, eject.

A throwaway probe app is likely a better instrument than the game — it can sweep and log without the game's own sound calls in the way. Build it under `.scratch/sound-and-vibration/probe/` if so.
