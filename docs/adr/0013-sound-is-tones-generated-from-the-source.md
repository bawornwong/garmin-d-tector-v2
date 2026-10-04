# 13. Sound is tones, generated from the source's own audio

Date: 2026-09-08

## Status

Historical decision with hardware amendments below. The current Venu 4
**release** build uses Garmin's prerecorded system tones and vibration; the
source-derived `ToneProfile` notes remain for simulator debug playback and
comparison. The later amendments in this record supersede its initial
custom-tone playback and menu-sound decisions. See [README.md](../../README.md)
for the current player-facing behavior.

## Context

An earlier design ruled audio out of scope because a Connect IQ watchApp
cannot play the source's MP3s. The extraction work below was a later attempt
to reproduce those sounds as tone profiles. Physical Venu 4 testing then
showed those custom profiles were silent on the watch, leading to the
prerecorded-cue release implementation described in the amendments.

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
7. **Source effect traces keep their event names.** `AudioManager` emits the same `Kaisa.Trace.event("sound " + name)` it emitted when it was trace-only, and fires the real effect alongside. The watch-specific menu navigation cues added in decision 11 have their own `sound menuLeft` and `sound menuRight` trace names.
8. **Two gates, not one**: the watch's own `getDeviceSettings().tonesOn`, and the game's Configure menu. Either off means silence, and vibration is gated the same way by `vibrateOn` and its own entry. (This ADR first said there was no in-app setting; the Configure menu was added afterwards and this decision follows it. The settings live under their own `Storage` key rather than in the save record: they are preferences, not game state, they outlive a reset, and putting them in the positional save blob would cost a format version bump that ADR 8 gives no migration for.)
9. **Sound is muted outright during screen and animation probes.** A probe measures scheduled time; the trace carries the name and that time either way, so muting changes nothing a golden diff reads. Same discipline as pinning the RNG.
10. **Vibration rides on the sound name, and has no call sites of its own.** Every event the map curates for vibration — the two encounters, the four evolutions, level up, reward and the unlocks, damage and loss, and the digistorm's onset — already plays a distinctive sound, so a table keyed by that name is the entire hook. A sound absent from the table does not vibrate, which is what keeps all 160 button call sites, menu scrolling and map steps silent. It is untraced for the same reason the sound fiber is (the original has no vibration; an event here has no counterpart to diff against), and it checks `vibrateOn` *before* `tonesOn`, so sound-off-with-vibration-on behaves as the wearer asked.
11. **Watch menu cues use Garmin system tones (2026-09-25 amendment).** The source's `buttonA` and `buttonB` are both 4097 Hz; B only lasts longer. A simulator run of Right, Right, Left, Right in the main menu sent 4097 Hz on every press. Custom one-note `ToneProfile` cues initially made the pitches distinct, but even one such cue caused the following `charHappy` melody to go silent in the Venu 4 simulator. Garmin's predefined `TONE_KEY`, `TONE_MSG`, `TONE_STOP`, and `TONE_START` now mark A, B, menu Left, and menu Right respectively. A 120 ms limit drops excess beeps during rapid input while every input still moves the menu. In a 30-press alternating stress run the user heard distinct button sounds and the following melody. The cues honor both sound settings.
12. **The short `charHappy` effect uses the source melody (2026-09-25 amendment).** The generic extractor recorded seven notes, but spectral inspection of `Assets/Audio/char_happy.mp3` found that it mistook strong odd harmonics for fundamentals. The actual six-note sequence is 819, 1093, 1024, 910, 1024, 1093 Hz, with onsets at approximately 0, 234, 574, 723, 873, and 1023 ms. An earlier watch melody made the pitches more obvious but changed their order and rhythm; this source-based sequence replaces it. It is sent in one `ToneProfile` call to preserve playback after rapid menu input, so `stopSound` cannot cut it short during its 1.56 seconds. The other extracted sounds continue to use their generated sequences and 220 ms chunks.

## Consequences

- **Verified**: 53/53 animations and 27/27 screens still match with neither verifier edited, so adding sound cost none of the existing proof.
- **The extraction has a measured quality, not an asserted one — and the honest measure is ~78%, not 90%.** The per-sound round trip prints 90.3% average, but it scores the extracted notes against the pitch track *the same detector produced*, so a systematic detector error is invisible to it. Synthesising square waves from the shipped `SoundData.mc` and comparing that audio to the original MP3 frame by frame — no detector in the loop — gives **≈78%**: 100% on the single-tone button beeps, 98% on `reward`, 92% on `levelUp`, but 41% on `destroySpirits` and 33% on the **generated** `charHappy` data. Decision 12 overrides that generated sequence at runtime; a separate harmonic-track comparison of its replacement matches 311/313 active source frames (99.4%) within 8% frequency tolerance. Re-check the aggregate score after any change to the extractor.
- **Four attempts to improve the weak sounds have failed measurement**, including one that looked like a large win until it turned out to be scoring against its own smoothed output, and one that diagnosed 6.8% of notes as harmonic errors and then made those sounds dramatically worse when it "fixed" them. They are written up with their evidence in the map's *Not yet specified*. The extractor is at a local optimum that hypotheses keep failing to beat; the next real move is an ear, not another heuristic.
- **Simulator playback has been heard; watch hardware has not.** Distinct system button cues and a melody after rapid input were confirmed by ear in the Venu 4 simulator. The source-matched `charHappy` sequence has been played there but still needs a direct listening comparison. Whether Venu 4 hardware reproduces the same result, and over what frequency range, remains ticket 01.
- Five `AudioManager` fields in the original are never called by it, and six source MP3s are wired to nothing; all 51 files are now accounted for rather than assumed.
- The vibration effort did fill in alongside this without re-deriving any of it, and without needing call sites of its own -- see decision 10. What it still lacks is a wrist.

## Venu 4 hardware amendment (2026-09-28)

On a physical Venu 4, the player heard the four menu button cues but no
gameplay effects. Those four cues use Garmin's predefined `TONE_*` values;
gameplay used custom `ToneProfile` arrays. A [Connect IQ staff explanation](https://forums.garmin.com/developer/connect-iq/f/discussion/405695/the-toneprofile-does-not-work-on-venu3s/1908427)
states that speaker-based watches can play prerecorded system tones without
being able to synthesize custom profiles, and the simulator can misleadingly
play the profiles. This is a strong explanation for the observed Venu 4 split,
though the physical watch still needs a direct post-fix listening check.

For the Venu 4 target, `AudioManager` now maps every source effect name to
one of the four predefined tones already heard on the device: positive,
negative, alert, or action. Every gameplay effect also gets the category's
vibration pattern, independently gated by device and game vibration settings.
Menu button cues do not vibrate. The original sound names and scheduled trace
events remain unchanged. The generated note data stays in the repository for
source comparison, but the Venu 4 app no longer decodes or plays it. The
source melodies, including `charHappy`, cannot be claimed as audible on this
hardware, and `stopSound` cannot cancel a system tone already playing.

## Menu and event haptics amendment (2026-09-29)

Physical watch feedback led to a further change: Left, Right, A, and B now
use short vibration cues with no system tone. Rapid menu input is limited to
one vibration every 120 ms; input itself is not limited. This respects the
game and device vibration settings. The sound setting controls gameplay tones
only. Event, monster encounter, and story cut scene starts get a distinct
three-pulse vibration even when gameplay sound is disabled. Source sound names
remain in diagnostic traces, but those names no longer imply audible button
feedback.

## Venu 4 system-tone phrases (2026-09-29)

The game now plays short phrases of Garmin's predefined `TONE_*` sounds for
gameplay effects. Each phrase follows the source effect's broad direction and
accent where that can be identified: `charHappy` alternates low and high,
`charSad` falls, level and reward cues rise, and event and monster cues use
distinct warning patterns. The original six-note `charHappy` pitch contour
informs its four-cue phrase. New effects interrupt the remaining scheduled
cues of the previous phrase, and `stopSound` cancels future cues. Neither can
stop a predefined tone already handed to the device.

These are approximations with a fixed palette, not playback of the source
melodies. The SDK does not expose each predefined tone's exact pitch,
waveform, or duration on Venu 4. The phrase timings and the new `TONE_ALERT_*`,
`TONE_SUCCESS`, and `TONE_FAILURE` choices need listening tests on a physical
watch; simulator audio does not establish how its speaker will sound.

## Ringtone feedback and simulator preview (2026-09-29)

Listening in the simulator showed that combining prerecorded Garmin alerts
produces a ringtone-like sequence rather than the source's square-wave sound.
The phrase experiment above is superseded. The release build now plays one
short, previously heard system cue per gameplay sound (`TONE_START`,
`TONE_STOP`, or `TONE_MSG`) and keeps the existing event vibration. This avoids
layering Garmin's own `TONE_ALERT_*`, `TONE_SUCCESS`, and `TONE_FAILURE`
melodies. These cues are event feedback, not a reproduction of the MP3s.

## Single-sample melody trial on Venu 4 (2026-09-29)

After the player confirmed that `charHappy` produced only one "ding" on the
watch, the release build changed just the happy and sad character effects to
single prerecorded Garmin melodies: `TONE_SUCCESS` and `TONE_FAILURE`.
Inspection of the simulator SDK's tone samples found that `success.wav` lasts
about 1.66 s and contains five pitches, while `failure.wav` lasts about 1.71 s
and descends through three pitches. The original `charHappy` is a six-note,
about 1.56 s rising and falling phrase; the original `charSad` falls over
about 1.74 s. This choice matches broad duration and direction without
layering several system alert melodies as the discarded phrase experiment did.
The simulator samples are evidence for selecting a candidate, not proof of
the Venu 4 speaker's output. A physical-watch listen is still required; the
notes, waveform, and precise rhythm cannot be reproduced through these
predefined tone IDs.

The debug build is an audio preview for the simulator: it again plays the
source-derived frequency and duration data through `ToneProfile`, with the
six measured notes of `charHappy` overriding the extractor's harmonic errors.
Menu buttons remain vibration-only in both builds. Debug builds should not
be sideloaded to Venu 4 for audio testing: Garmin reports that speaker-based
watches may accept `ToneProfile` calls without playing them, while the
simulator plays them. Build with `tools/build.sh -r` for the watch.

Native simulator playback also requires **Settings → Tones** to be enabled. When it
was off, a `charHappy` scene reached `AudioManager` with game sound enabled,
but `System.getDeviceSettings().tonesOn` was false and the game correctly
skipped playback. After enabling it, a simulator diagnostic read `tonesOn=true`
and completed a two-note `ToneProfile` call. This setting is separate from
the in-game Configure → Sound switch.

Some macOS installations still play no simulator audio with `tonesOn=true`;
the [Garmin developer forum](https://forums.garmin.com/developer/connect-iq/f/discussion/363845/attention-toneprofile-is-silent-in-simulator-on-mac-osx-works-on-watch/1746731)
has a report of this without a general fix. For local listening,
the debug app also prints `SIM_AUDIO <name>` and `SIM_AUDIO_STOP` for gameplay
effects. `tools/run_simulator_with_audio.py` follows those messages and plays
the matching **original MP3** from a checkout of the source project through
macOS `afplay`. It is a simulator development tool; the watch build remains
on the Garmin system cues. With the simulator already open, run:

```sh
tools/build.sh
cp build/dtector.prg build/dtector-simulator.prg
python3 tools/run_simulator_with_audio.py --source /path/to/D-Tector-v2
```

If the simulator's own tones also work, turn its Settings → Tones off while
using this runner to avoid hearing each effect twice. The game Configure →
Sound setting still controls both preview paths.
