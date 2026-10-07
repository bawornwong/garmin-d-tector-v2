# D-Tector for Garmin Venu 4

A Connect IQ watch app based on [kaisadilla/D-Tector-v2](https://github.com/kaisadilla/D-Tector-v2). The target is the **Venu 4 45 mm** (`venu445mm`). The game keeps the source's 32 × 32 pixel screen, 593 Digimon, nine worlds, battles, and minigames, with controls and step tracking adapted to the watch. This repository is set up for personal sideloading; it does not contain a Connect IQ Store release.

## Play on the watch

The watch's **upper button is A** and **lower button is B**. Touch the four sectors of the round screen for the same four game inputs:

| Touch sector | Input |
| --- | --- |
| Left | Left |
| Right | Right |
| Top | B |
| Bottom | A |

The sectors meet at the centre and are separated by diagonals. A touch keeps its starting sector until release, so holding works in games that need it. Swipes have no separate command. On the idle character screen, Left or Right opens the main menu; A pages through status. Hold the lower button for 1.5 seconds, or press Back twice within 1.5 seconds on that screen, to exit.

Opening or returning to the game, pressing a game button, or touching a game sector requests **30 seconds of screen illumination** at the watch's configured brightness. After that, the normal display timeout applies. Garmin's display settings and AMOLED burn-in protection can limit illumination; if the firmware rejects a request, the game continues with the normal timeout until the view is shown again. Verify the duration on a physical Venu 4.

Connect IQ provides no API to suppress phone/system notifications or toggle the watch's Do Not Disturb mode. To silence these while playing, hold the upper button to open the watch controls and enable **Do Not Disturb** before launching the game; disable it afterwards. This also affects the watch's display and vibration settings. The game's own **Detected** notification is only sent by its background service when the foreground save lease is inactive.

### Menus and games

| Location | Available |
| --- | --- |
| Main menu | Map, Status, Game, Database, Digits (code entry), Camp, Connect, Config |
| Game | Finder; Reward → Jackpot Box; Travel → Speed Runner, Digi Hunter, Maze |
| Encounters | Battle and Data Storm events during the journey |
| Config | Vibration, Sound, pixel grid, BG STEP, Reset |

**Speed Runner controls:** Hold the left or right touch sector to move the rocket to that side. Releasing returns it to the centre lane. The top and bottom sectors remain B and A.

**Entries without gameplay:** Connect stays visible and gives a rejection vibration when selected. Energy Wars and Digi Catch under Reward, and Asteroids under Travel are hidden. Their apps do not exist yet. Change the switches in [`MenuFeatures.mc`](app/source/Data/MenuFeatures.mc) and rebuild to show or hide them; their source references remain in place. Battle is reached through encounters rather than a direct menu entry.

There is one automatically resumed save. **Config → Reset** starts over; the source game's separate save-slot picker and save naming screen are not part of this watch version. Sound, vibration, grid, and BG STEP preferences survive a game reset. Jackpot Box can legitimately award an empty box.

### Steps, events, and alerts

- While the app is open, deliberate wrist shakes and steps recorded by Garmin both advance the game.
- While the app is closed, only steps recorded by the watch are synced in the background and credited when the game opens again. Shakes are ignored. Steps recorded before that game's baseline do not count. **Config → BG STEP** turns this sync and its background wake events on or off; it defaults to ON. Steps recorded while it is OFF are skipped when the game next opens.
- Walking advances toward the first event or boss gate reached. Steps beyond that gate still increase the step statistics but do not carry over as travel after the event. This prevents a long walk from skipping several encounters.
- The app checks steps on opening and return. When closed, its background service requests a five-minute wake and Garmin's step event, which occurs at fixed 1,000-device-step multiples. These are opportunities to check the gate, not a guarantee of an alert at the exact step that reaches it.
- If a gate is reached during a background check, the watch can show a **Detected** notification with an **Open game** action. Opening the game reconciles the recorded steps and presents the pending event. An event prompt in the open app vibrates every 1.6 seconds until an action; Data Storm also has its own vibration cues.

Shake sensitivity, delayed Garmin step updates at the moment the app closes, background scheduling, notification delivery, and storage handoff still need end-to-end checks on a physical Venu 4. If the accelerometer listener cannot start, visible play falls back to watch steps. See [watch-step-sync-design.md](docs/watch-step-sync-design.md) for the step and save rules and the remaining device checks.

The release build uses Garmin's prerecorded tones for gameplay and vibration for menu input and events. The original MP3 files and custom melodies do not play on the Venu 4 release build. The **Config → Sound** switch controls gameplay tones; **Config → Vibration** controls haptics. The watch's own sound and vibration settings also apply. A debug build can preview source-derived tones in the simulator; see [ADR 13](docs/adr/0013-sound-is-tones-generated-from-the-source.md).

## Build and install

Requirements: a Garmin Connect IQ SDK with the `venu445mm` device profile, a Connect IQ developer signing key, macOS with `zsh` for `tools/build.sh`, and Python 3 for the asset and verification tools. The build script defaults to the project's original SDK path; set `CIQ_SDK` to the SDK directory on another machine. Its minimum declared Connect IQ API is 6.0.0.

The generated game data and artwork are already in `app/`, so a normal build does **not** need a checkout of the Unity source or Python dependencies.

```sh
export CIQ_SDK="/path/to/connectiq-sdk"
mkdir -p .scratch/keys
openssl genrsa -out .scratch/keys/developer_key.pem 4096
openssl pkcs8 -topk8 -inform PEM -outform DER \
  -in .scratch/keys/developer_key.pem \
  -out .scratch/keys/developer_key.der -nocrypt
tools/build.sh -r
```

The build writes `build/dtector.prg`. Copy the **release** build to `GARMIN/APPS/dtector.prg` on the watch over USB and eject it. Keep the `dtector.prg` name when replacing a build so the existing save remains associated with the app. To build a debug version for the simulator, run `tools/build.sh` without `-r`:

```sh
tools/build.sh
"$CIQ_SDK/bin/connectiq" &
"$CIQ_SDK/bin/monkeydo" build/dtector.prg venu445mm
```

If you already have a signing key, set `CIQ_KEY` to its `.der` file instead of creating the key above. The key under `.scratch/keys/` is ignored by Git.

### Regenerate assets and verify parity

The packers and source-comparison tools read the original Unity project through `DTECTOR_SRC`. They require Python packages **Pillow** and, for sound extraction, **NumPy** and `ffmpeg`. The numeric and screen comparisons additionally need .NET; simulator comparisons need the Connect IQ simulator running.

```sh
git clone https://github.com/kaisadilla/D-Tector-v2.git /tmp/dtector-v2
export DTECTOR_SRC=/tmp/dtector-v2
python3 -m pip install Pillow numpy

python3 tools/pack_sprites.py
python3 tools/pack_fonts.py
python3 tools/pack_ui_sprites.py
python3 tools/pack_data.py
python3 tools/gen_wellknown.py
python3 tools/pack_sounds.py

python3 tools/verify_worlds.py
python3 tools/verify_gallery.py
python3 tools/verify_numeric.py
python3 tools/verify_screens.py
python3 tools/verify_anim.py
python3 tools/smoke_apps.py
```

The last four checks use the SDK simulator, and `smoke_apps.py` drives the release build. The source checkout is only needed for regeneration and comparisons against the original. Generated files identify their generating tool in their headers; edit the generator rather than its output.

## Repository layout

| Path | Purpose |
| --- | --- |
| `app/source/DTectorApp.mc`, `DTectorView.mc`, `StepBackground.mc` | Connect IQ lifecycle, frame loop, step service and notification |
| `app/source/Input/` | Touch and button events, including held inputs |
| `app/source/Logic/`, `app/source/Apps/` | Game rules, menus, battles and minigames |
| `app/source/Save/` | Versioned save, watch-step ledger and background/foreground handoff |
| `app/source/Anim/`, `app/source/Render/` | Timed animations, sprite display list and drawing |
| `app/source/Data/`, `app/resources/` | Packed Digimon/world data, preferences, sounds, bitmaps and fonts |
| `tools/` | Build, asset generation and source-parity checks |
| `docs/adr/`, `CONTEXT.md` | Design history and game terminology |

The current save format is version 3. It keeps one game in `slot0` and includes a watch-step header that the background service can inspect without loading the game database. Version 2 saves are migrated on read; version 1 saves are not supported. The original source and its asset files are needed only for regeneration and verification.

The ADRs record how implementation decisions changed over time. This README and the current code describe the playable build; [CONTEXT.md](CONTEXT.md) defines its terms.
