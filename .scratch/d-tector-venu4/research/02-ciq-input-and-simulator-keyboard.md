# Connect IQ input events and simulator keyboard (venu445mm)

Research answer for `issues/02-ciq-input-and-simulator-keyboard.md`.
SDK inspected: `connectiq-sdk-mac-9.2.0-2026-06-09-92a1605b2`. Device files: `Devices/venu445mm/`.

---

## TL;DR for the port

- **Venu 4 45mm has exactly two key events: `KEY_ENTER` (right-top) and `KEY_ESC` (right-bottom).** There is no `KEY_UP`/`KEY_DOWN`/`KEY_LEFT`/`KEY_RIGHT`/`KEY_MENU` on this device. The game's A/B/Left/Right cannot map 1:1 to physical keys.
- **Press/hold/release separation exists in the API** (`onKeyPressed` → `PRESS_TYPE_DOWN`, `onKeyReleased` → `PRESS_TYPE_UP`) and `venu445mm` does **not** opt out of it in `simulator.json`. But Garmin staff have on record advised avoiding these callbacks because real-device behaviour diverges from the simulator. Hold duration is **not** delivered by the platform — you must time it yourself between down and up.
- **Touch gives a genuine down/move/up stream** via `onDrag` (`DRAG_TYPE_START` / `CONTINUE` / `STOP`) with coordinates. `onSwipe` does **not** — it is a discrete, post-hoc, no-coordinate event. Use drag (or tap + hold/release) for the timing minigames; keep swipe for menus only.
- **No shake/gesture API exists.** Shake must be hand-rolled from the accelerometer. The low-latency path is `Sensor.getInfo().accel` polled from the game's own `Timer` (Garmin's own AccelMag sample polls at 100 ms). `registerSensorDataListener` batches — minimum `:period` is 1 second — so it adds ~1 s latency and is wrong for an interactive shake.
- **Simulator keyboard:** for `venu445mm` only **Enter** → `KEY_ENTER` and **Esc** → `KEY_ESC` are live. Arrow keys and M/F/I/O/P exist in the simulator's mapping table but this device declares no such keys, so they produce nothing. Everything else must come from the mouse on the 454×454 screen area.

---

## 1. Key events — press / hold / release separation

### What the API offers

`WatchUi.InputDelegate` (base class of `BehaviorDelegate`) defines three key callbacks
(SDK `doc/Toybox/WatchUi/InputDelegate.html`, and `doc/docs/Core_Topics/Input_Handling.html`):

| Callback | Meaning | Since |
|---|---|---|
| `onKey(KeyEvent)` | "A physical button has been pressed **and released**" | 1.0.0 |
| `onKeyPressed(KeyEvent)` | "A physical button has been **pressed down**" | 1.1.2 |
| `onKeyReleased(KeyEvent)` | "A physical button has been **released**" | 1.1.2 |

`KeyEvent.getType()` returns a `WatchUi.KeyPressType` (SDK `doc/Toybox/WatchUi.html`):

| Constant | Value | Meaning |
|---|---|---|
| `PRESS_TYPE_DOWN` | 0 | key is pressed down |
| `PRESS_TYPE_UP` | 1 | key is released |
| `PRESS_TYPE_ACTION` | 2 | key's action is performed |

So the platform **does** express down and up as separate events. It does **not** express "hold"
for keys — there is no key-hold callback and no duration on `KeyEvent`. A hold has to be
synthesised in app code: start a timer on `onKeyPressed`, cancel it on `onKeyReleased`.

### Does `venu445mm` actually deliver down/up?

The simulator's device-config schema has per-key flags `pressDownSupport`, `pressUpSupport`,
`pressActionSupport`, `isHold` (string table in `bin/ConnectIQ.app/Contents/MacOS/simulator`,
alongside the other `simulator.json` key names). Surveying all 173 installed device profiles:

- `pressDownSupport: false` appears on 64 keys, `pressUpSupport: false` on 44, all on
  non-Venu hardware (e.g. `gpsmap86`). The flags are **absent by default**, i.e. supported.
- `venu445mm/simulator.json` sets **neither**, so both `enter` and `esc` are modelled as
  supporting press-down and press-up.

That is the strongest device-specific evidence available; Garmin publishes no per-device
"onKeyPressed supported" list in the API docs (the `onKeyPressed`/`onKeyReleased` doc pages carry
no *Supported Devices* section, which normally means "all devices"). The symbols
`Toybox_WatchUi_InputDelegate::onKeyPressed` / `onKeyReleased` are present in
`venu445mm.api.debug.xml`, confirming they exist in this device's firmware VM.

### Caveat you must design around

Garmin staff (Travis Vitek) on the forum:

> "The simulator is behaving the way that they want things to behave, not the way they actually behave."
> "The `onKeyPressed()` and `onKeyReleased()` functionality doesn't work, or at least doesn't work with many devices."
> "To be safe, you should avoid using `onKeyPressed()` and `onKeyReleased()`."

That thread is about FR230/235/735 (~2016 hardware) and is not a statement about Venu 4. But it is
the only first-party statement on the topic, and it means: **do not treat simulator-verified
press/release as proof of on-device behaviour.** Since hardware mapping is deferred anyway, the
input abstraction layer should keep press/hold/release as an *internal* model that can be fed
either by real down/up events or by synthesised ones (`onKey` = down immediately followed by up).

### Delegate choice

`BehaviorDelegate` extends `InputDelegate` and is dispatched **first**:

> "If a BehaviorDelegate returns true for a function (indicating the input was used) then the
> InputDelegate function that corresponds to the behavior will not be called."
> — SDK `doc/Toybox/WatchUi/BehaviorDelegate.html`

For a game that wants raw events, extend `WatchUi.InputDelegate` directly, or extend
`BehaviorDelegate` and return `false` from `onSelect`/`onBack`/`onNextPage`/`onPreviousPage`
so the raw `onKey`/`onTap`/`onSwipe` still fire.

Also documented on `onBack()`: "Some devices interpret `SWIPE_RIGHT` SwipeEvents as `KEY_ESC`
events. On these devices, returning false will cause `onKey()` to be called rather than `onSwipe()`."

---

## 2. Which keys exist on Venu 4 45mm

`Devices/venu445mm/simulator.json` → `keys` (verbatim, minus geometry):

```json
[ { "behavior": "onSelect", "id": "enter", "location": {"x":567,"y":253,"width":52,"height":75} },
  { "behavior": "onBack",   "id": "esc",   "location": {"x":560,"y":550,"width":62,"height":97} } ]
```

`location` is in `device.png` coordinates (650×902); the screen sits at (98,223) 454×454. So
`enter` is the **right-top** button and `esc` the **right-bottom** button — matching the device's
own hint icons (`system_icon_*__hint_button_right_top.svg` / `..._right_bottom.svg`).

**Only two key events reach the app: `KEY_ENTER` (4) and `KEY_ESC` (5).**

The full `WatchUi.Key` enum (POWER, LIGHT, ZIN, ZOUT, ENTER, ESC, FIND, MENU, DOWN, DOWN_LEFT,
DOWN_RIGHT, LEFT, RIGHT, UP, UP_LEFT, UP_RIGHT, PAGE, START, LAP, RESET, SPORT, CLOCK, MODE,
ACTION_MENU) is compiled into every device's API surface, so its presence in
`venu445mm.api.debug.xml` proves nothing about hardware. `simulator.json` is the device truth.

### Notable: no `KEY_MENU`, and `onMenu()` is unreachable

Venu 2 and Venu 3 declare a third pseudo-key `{"behavior":"onMenu","id":"menu","isHold":true}`
(long-press of the top button). **Venu 4 45mm and 41mm do not.** Combined with the touch
behaviour table (below), which has no `onMenu` id either, `BehaviorDelegate.onMenu()` has no
trigger on this device. Don't build anything on it.

`BehaviorDelegate.onActionMenu()` (API 5.1.1) *is* listed as supported on Venu 4 45mm, but it fires
in response to the app calling `WatchUi.showActionMenu()` — it is not a hardware button.

### Touch behaviours declared for this device

`Devices/venu445mm/simulator.json` → `display.behaviors`:

| Gesture | Mapped behavior | Extra params |
|---|---|---|
| `swipeRight` | `onBack` | `maxDistToEdge: 81`, `maxSwipeDuration: 250`, `minSwipeDeltaX: 90`, `minSwipeDeltaY: 90` |
| `swipeLeft` | *(none)* | |
| `swipeUp` | `nextPage` | |
| `swipeDown` | `previousPage` | |
| `hold` | *(none)* | |
| `release` | *(none)* | |
| `tap` | `onSelect` | |

`display.isTouch: true`, `display.shape: round`.

Across all 173 device profiles the `maxDistToEdge`/`maxSwipeDuration`/`minSwipeDelta*` fields
appear **only** on `swipeRight`, i.e. they parameterise the edge-swipe-back recogniser.
Reading the field names at face value: the back swipe must start within 81 px of the edge, travel
≥90 px, and complete within 250 ms. *This is inference from the config schema — Garmin does not
document these fields.* Swipes with no `id` (`swipeLeft`, `hold`, `release`) generate no behavior
and surface only as raw `InputDelegate.onSwipe` / `onHold` / `onRelease`.

---

## 3. Touch

### Available callbacks on venu445mm

| Callback | Payload | Notes |
|---|---|---|
| `onTap(ClickEvent)` | coords + `CLICK_TYPE_TAP` | "a quick touch and release" |
| `onHold(ClickEvent)` | coords + `CLICK_TYPE_HOLD` | "touched and not released" |
| `onRelease(ClickEvent)` | coords + `CLICK_TYPE_RELEASE` | "only sent after an `onHold()` event" |
| `onSwipe(SwipeEvent)` | **direction only** — `SWIPE_UP/RIGHT/DOWN/LEFT` | no coordinates, no velocity |
| `onDrag(DragEvent)` | coords + `DRAG_TYPE_START` / `CONTINUE` / `STOP` | API 3.3.0; Venu 4 45mm explicitly listed as supported |
| `onFlick(FlickEvent)` | coords, direction in degrees, distance in px, **velocity in px/s** | API 3.3.0; Venu 4 45mm explicitly listed as supported |

All six symbols are present in `venu445mm.api.debug.xml`.

### Is swipe usable for SpeedRunner / Maze?

**No — use `onDrag` instead.** Reasons, from the primary sources:

1. `SwipeEvent` exposes *only* `getDirection()`. No coordinates, no timestamps, no velocity. You
   cannot tell where the swipe happened or how hard.
2. A swipe is recognised only after the whole gesture completes, so the event lands at the *end*
   of the motion, not the start. For `swipeRight` on this device that is up to 250 ms after
   touch-down, plus a ≥90 px travel requirement.
3. `swipeUp`/`swipeDown`/`swipeRight` are bound to system behaviours (`nextPage`, `previousPage`,
   `onBack`). You can consume them by returning `true`, but there is a known
   real-device bug where swipe-right still triggers back on some watches regardless of the return
   value (community reports; simulator honours the return value correctly).

`onDrag` gives `DRAG_TYPE_START` with coordinates at touch-down — that is the low-latency signal a
timing minigame needs — plus `CONTINUE` updates and `STOP`. `onFlick` additionally gives measured
velocity if a flick-strength input is wanted.

### Latency and event rate

**Garmin documents neither.** There is no published touch sampling rate, no `onDrag` event-rate
figure, and no latency SLA anywhere in the SDK docs, the device profile, or the API reference. The
only quantified touch numbers that exist for `venu445mm` are the `swipeRight` recogniser
parameters above (250 ms / 90 px / 81 px). Anything else would be a guess — measure it on the
simulator and on hardware before committing a minigame's timing budget.

---

## 4. Accelerometer

### There is no gesture/shake API

Searching `venu445mm.api.debug.xml` for anything gesture-shaped returns nothing. Shake detection
must be written from raw accelerometer samples.

### Device capability

`Devices/venu445mm/simulator.json` → `sensorSampleRate`:

```json
{ "highFrequencyRate": true, "maxAccelRate": 100, "maxGyroRate": 100, "maxMagRate": 50 }
```

So the accelerometer supports up to **100 Hz** high-frequency sampling on this device.
`Sensor.getMaxSampleRate()`, `registerSensorDataListener()` and `unregisterSensorDataListener()`
all list Venu 4 45mm under *Supported Devices*, as does `Sensor.Info.accel`.

### Two access paths, and which one fits a shake

**(a) `Sensor.getInfo().accel` — polled. This is the one to use.**

- Returns `[x, y, z]` as `Array<Number>` in **millig** units (API 1.2.0).
- Documented usage is "on demand or periodically within a `Timer`".
- Garmin's own **AccelMag** sample (`samples/AccelMag/source/AccelMagView.mc`) does exactly this
  for a real-time accel-driven rolling-ball game: `_dataTimer.start(method(:timerCallback), 100, true)`
  → `Sensor.getInfo()` every **100 ms**. It calls no `setEnabledSensors`/`enableSensorType` first.
- Cost is one VM call per poll. If the port already runs a frame timer, folding an accel read into
  it is cheap. **Caveat from the docs:** "Some devices do not enable the accelerometer at startup.
  To get valid data from this field on such devices, applications must enable the sensor with a
  call to `registerSensorDataListener`." Whether Venu 4 needs that is untested here — check
  `info.accel != null` at startup and fall back to registering a listener once if it is null.
- Note `Sensor.enableSensorEvents()` is **not** the answer: it delivers at a fixed **1 Hz**.
- Community reports put the underlying `getInfo` accel refresh at ~25 Hz on modern devices, so
  polling much faster than that likely returns repeats. *Not first-party — verify by measurement.*

**(b) `Sensor.registerSensorDataListener()` — batched. Too laggy for an interactive shake.**

- `:period` is "Period of time to request samples in seconds. Maximum is 4 seconds", and the
  callback fires "each time a new set of sensor data over the length of time specified in the
  period option is available". It is a `Number` of seconds, so the **floor is 1 second** — the
  PitchCounter sample uses `{:period => 1, :accelerometer => {:enabled => true, :sampleRate => 25}}`.
- That means a shake would be reported up to ~1 s after it happened. Unacceptable for a game input.
- Only one listener may be registered at a time.
- Both `registerSensorDataListener` and `getMaxSampleRate` crash if called from a data field app
  (irrelevant here — this is a watchApp).
- Useful only if you want a high-fidelity 25–100 Hz window for tuning a shake threshold offline.

**Recommendation:** poll `Sensor.getInfo().accel` from the existing game timer at ~50–100 ms and run
the original `ShakeDetector` threshold logic over the magnitude delta. Verify `accel` is non-null
at startup; if null, call `registerSensorDataListener` once to wake the sensor.

### Simulating it

There is no shake control and no accelerometer input panel in the simulator — the only accel
strings in the binary are `maxAccelRate` and internal `AccelSensorResource` class names. The
documented ways to get accel data into the simulator are:

- *Simulation → FIT Data → Simulate Data* — "generates valid but random values". Fine for
  null-checking, useless for testing a threshold.
- *Simulation → FIT Data → Playback File* — replays a FIT file into `Toybox.Sensor`; accel logged
  on a real device via `SensorLogging.SensorLogger` can be played back here.

So **shake cannot be meaningfully exercised from the keyboard in the simulator.** Plan a debug
key/tap that injects a synthetic shake event into the input abstraction layer.

---

## 5. Simulator keyboard mapping

### The mapping table (first-party)

From the SDK's own release notes, **v3.0.0.beta1**
(`doc/docs/Readme/History.html`, verbatim):

> "Add simulator keyboard mappings for FIND (F), ZOOM_IN (I), ZOOM_OUT (O), PAGE (P) and MENU (M),
> KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_ENTER, and KEY_ESC."

Expanded (corroborated by the Garmin forum thread *"Where is the map from keyboard keys to
WatchUi.KEY_*"*, which quotes the same release note):

| Host key | Connect IQ key |
|---|---|
| `Enter` | `KEY_ENTER` |
| `Esc` | `KEY_ESC` |
| `↑` / `↓` / `←` / `→` | `KEY_UP` / `KEY_DOWN` / `KEY_LEFT` / `KEY_RIGHT` |
| `M` | `KEY_MENU` |
| `F` | `KEY_FIND` |
| `I` | `KEY_ZIN` |
| `O` | `KEY_ZOUT` |
| `P` | `KEY_PAGE` |

### What is actually live on `venu445mm`

The mapping is filtered by the device's own `keys` array — the forum thread states this
explicitly ("whether keys are enabled for a device is specified in
`…/Devices/<Device name>/simulator.json`"), and `venu445mm` declares only `enter` and `esc`.

**Therefore, on `venu445mm` the working keyboard is:**

| Host key | Event delivered | Device button it stands for |
|---|---|---|
| **`Enter`** | `KEY_ENTER` → `onKey`/`onKeyPressed`/`onKeyReleased`; behavior `onSelect` | right-**top** button |
| **`Esc`** | `KEY_ESC` → same; behavior `onBack` | right-**bottom** button |
| Arrows, M, F, I, O, P | **nothing** — no such key on this device | — |

That is **two** keyboard inputs for a game that wants A, B, Left and Right. The remaining two
directions must come from touch (mouse in the simulator), or A/B/Left/Right must be remapped —
which the map's fidelity contract explicitly permits ("*Interaction* may be remapped").

### Mouse inputs in the simulator

- **Device buttons:** click the button hotspots on the device image. From `simulator.json`
  `keys[].location` (in `device.png` space, 650×902): `enter` at x 567–619, y 253–328;
  `esc` at x 560–622, y 550–647. Hold the mouse button down to hold the device button.
- **Touch:** the screen is the 454×454 region at (98, 223) in the device image. Click = tap;
  click-and-hold = `onHold` then `onRelease`; press-drag-release = `onDrag` (START/CONTINUE/STOP),
  and a fast enough drag is recognised as `onSwipe`/`onFlick`.
- Touch can be turned off entirely with *Settings → Toggle Touch Screen* (string present in the
  simulator binary), which is a useful way to prove the app is playable on buttons alone.

### Two things I could not establish from primary sources

1. **Whether holding a host key down in the simulator yields a single sustained
   `PRESS_TYPE_DOWN` … `PRESS_TYPE_UP` pair, or repeats `onKeyPressed` at the OS key-repeat rate.**
   Nothing in the SDK docs, release notes, or the simulator's string table addresses this, and no
   Garmin forum answer covers it. This matters for the hold half of the input model — **test it
   first thing** with the SDK's `samples/Input` app, which prints
   `"<KEY> PRESSED"` / `"<KEY> RELEASED"` on every `onKeyPressed`/`onKeyReleased`.
2. **Whether the simulator delivers key events when window focus is on the device window vs. the
   console window.** Undocumented; empirical.

The `samples/Input` project is the right first build target for both questions — it renders the
current key, behavior, and press status live.

---

## Design implications for ticket 09 (input abstraction layer)

- Model the six-way source (A, B, Left, Right × down/hold/up) as an **internal** state machine fed
  by adapters, not as a direct mapping onto CIQ callbacks.
- Only two hardware buttons exist and only two host keys work. Expect a remap:
  e.g. Enter = A, Esc = B, and Left/Right from on-screen touch zones or drag direction. Decide in
  ticket 09; this ticket only establishes the ceiling.
- Synthesise hold in app code with a `Timer`. Never rely on the platform for hold duration.
- Prefer `onDrag` over `onSwipe` everywhere timing matters.
- Provide a debug injection path for shake, because the simulator cannot produce one.
- Return `false` from behavior handlers (or skip `BehaviorDelegate` entirely) so raw input still
  reaches the game.

---

## Sources

### Local — Connect IQ SDK 9.2.0 (`~/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.2.0-2026-06-09-92a1605b2/`)

- `doc/Toybox/WatchUi/InputDelegate.html` — callback list, semantics, per-device support lists
- `doc/Toybox/WatchUi/BehaviorDelegate.html` — behavior-before-input dispatch rule, `onBack`/`onActionMenu` notes and supported-device lists
- `doc/Toybox/WatchUi/KeyEvent.html` — `getKey()`, `getType()`
- `doc/Toybox/WatchUi/ClickEvent.html`, `SwipeEvent.html`, `DragEvent.html`, `FlickEvent.html` — event payloads
- `doc/Toybox/WatchUi.html` — `Key`, `KeyPressType`, `ClickType`, `SwipeDirection`, `DragType` enums and values
- `doc/Toybox/Sensor.html` — `getInfo`, `enableSensorEvents` (1 Hz), `registerSensorDataListener` options and `:period` limits, `getMaxSampleRate`, supported-device lists
- `doc/Toybox/Sensor/Info.html` — `accel` units (millig) and the "not enabled at startup" note
- `doc/docs/Core_Topics/Input_Handling.html` — input vs behavior overview
- `doc/docs/Core_Topics/Sensors.html` — high-frequency data, FIT simulate/playback, `SensorLogger`
- `doc/docs/Readme/History.html` — **v3.0.0.beta1 simulator keyboard mapping release note**
- `samples/Input/source/InputDelegate.mc` — reference implementation printing key/behavior/press status
- `samples/AccelMag/source/AccelMagView.mc` — `Sensor.getInfo()` polled at 100 ms for a real-time accel game
- `samples/PitchCounter/source/PitchCounterProcess.mc` — `{:period => 1, :accelerometer => {:enabled => true, :sampleRate => 25}}`
- `bin/ConnectIQ.app/Contents/MacOS/simulator` — string table: `simulator.json` schema keys (`isHold`, `pressDownSupport`, `pressUpSupport`, `pressActionSupport`, `maxDistToEdge`, `maxSwipeDuration`, `minSwipeDeltaX/Y`, `maxAccelRate`), `Toggle Touch Screen`, sensor-listener error strings

### Local — device profiles (`~/Library/Application Support/Garmin/ConnectIQ/Devices/`)

- `venu445mm/simulator.json` — `keys` (enter/esc + hotspots), `display.behaviors`, `display.isTouch`, `sensorSampleRate`, `glance`, `graphicsResourcePoolSize`
- `venu445mm/compiler.json` — deviceId, `round-454x454`, API level 6.0, 786432 B watchApp limit
- `venu445mm/venu445mm.api.debug.xml` — presence of `Toybox_WatchUi_InputDelegate` symbols `onKey`, `onKeyPressed`, `onKeyReleased`, `onTap`, `onHold`, `onRelease`, `onSwipe`, `onDrag`, `onFlick`; `registerSensorDataListener`; absence of any gesture API
- `venu445mm/device.png` (650×902), `system_icon_*__hint_button_right_top.svg`, `..._right_bottom.svg`
- `venu441mm/`, `venu2/`, `venu3/`, `vivoactive6/`, `venux1/`, `fenix847mm/`, `edge850/`, `gpsmap86/`, `gpsmap67/` `simulator.json` — comparison of `keys` arrays and of the `pressDownSupport`/`pressUpSupport`/`isHold` flags across all 173 installed profiles

### Web

- https://developer.garmin.com/connect-iq/api-docs/Toybox/WatchUi/InputDelegate.html
- https://developer.garmin.com/connect-iq/api-docs/Toybox/WatchUi/BehaviorDelegate.html
- https://forums.garmin.com/developer/connect-iq/f/discussion/333202/where-is-the-map-from-keyboard-keys-to-watchui-key_ — quotes the v3.0.0.beta1 keyboard-mapping release note; notes device filtering via `simulator.json`
- https://forums.garmin.com/developer/connect-iq/f/discussion/338303/keyboard-shortcuts-in-the-simulator — Enter/Esc/arrows/M; caveat that M only works where a physical button opens the menu (community, not staff)
- https://forums.garmin.com/developer/connect-iq/f/discussion/4562/onkeypressed-and-onkeyreleased-on-fr230-235-735 — **Garmin staff (Travis Vitek)**: simulator behaves as intended not as devices behave; avoid `onKeyPressed`/`onKeyReleased`
- https://forums.garmin.com/developer/connect-iq/i/bug-reports/onkeypressed-and-onkeyreleased-do-they-work — same divergence reported as a bug
- https://forums.garmin.com/developer/connect-iq/f/discussion/2213/pressing-buttons-in-simulator — mouse click on the button hotspot; hold longer for long-press behaviours
- https://forums.garmin.com/developer/connect-iq/i/bug-reports/swipe-right-end-program-even-when-onback-or-onswipe-is-handled-and-returns-true — swipe-right still triggers back on some devices despite returning `true`; simulator honours it
- https://forums.garmin.com/developer/connect-iq/f/discussion/258395/behaviordelegate-and-vivoactive4 — swipe→behavior bindings on touch Venu-class devices
- https://forums.garmin.com/developer/connect-iq/f/discussion/1773/accelerometer-in-simulator — accelerometer simulation limitations (old thread; superseded in part by FIT playback)

### Explicitly not found

- No documented touch latency or touch/drag event rate for any Connect IQ device.
- No documentation of how the simulator translates a *held* host key into `PRESS_TYPE_DOWN`/`UP`.
- No documentation of the `maxDistToEdge` / `maxSwipeDuration` / `minSwipeDelta*` semantics; the
  reading above is inferred from the field names.
- No shake/gesture API in Connect IQ.
