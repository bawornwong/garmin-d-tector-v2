# Connect IQ input events and simulator keyboard

Type: research
Status: resolved
Blocked by: —

## Question

What input events can a `venu445mm` watchApp observe, and how does the SDK simulator drive them from a keyboard?

Answer all of:

1. **Key events** — `WatchUi.BehaviorDelegate` / `InputDelegate`: does `onKey` / `onKeyPressed` / `onKeyReleased` give genuine press/hold/release separation, or only discrete presses? The source needs A/B/Left/Right each with down, up, and hold, so establish exactly which of those the platform can express.
2. **Which keys exist** on Venu 4 — `KEY_ENTER`, `KEY_ESC`, `KEY_UP`, `KEY_DOWN`, `KEY_MENU`, etc. Two physical buttons: what do they report?
3. **Touch** — `onTap`, `onSwipe`, `onHold`, `onDrag`. Latency and event rate. Whether swipe is usable in a fast-timing minigame (SpeedRunner, Maze) or only for menus.
4. **Accelerometer** — `Sensor.registerSensorDataListener` / `Sensor.getInfo` accel access: sample rate, whether a watchApp in the foreground can poll it cheaply enough to detect a shake gesture.
5. **Simulator keyboard mapping** — which host keys the Connect IQ simulator sends for each device button and for touch/swipe on `venu445mm`. This is what the first build is developed against, so it needs to be exact.

Prefer primary sources: Connect IQ API docs, the simulator's own documentation and `simulator.ini`, Garmin developer forum posts from Garmin staff.

Ticket [Input abstraction layer](./09-input-abstraction-layer.md) waits on this.

## Context

Findings land at `.scratch/d-tector-venu4/research/02-ciq-input-and-simulator-keyboard.md`.

## Answer

Full findings: [research/02-ciq-input-and-simulator-keyboard.md](../research/02-ciq-input-and-simulator-keyboard.md)

1. **Press/release yes, hold no.** `onKeyPressed` (`PRESS_TYPE_DOWN`) and `onKeyReleased` (`PRESS_TYPE_UP`) give genuine down/up separation. `KeyEvent` carries no duration and there is no hold event — hold must be timed in app code between down and up. `venu445mm/simulator.json` does not carry the `pressDownSupport`/`pressUpSupport: false` opt-out that some devices have, and both symbols are in the device's `api.debug.xml`. Caveat: a Garmin staff post (Travis Vitek, FR230-era) advises avoiding these two callbacks because the simulator "behaves the way they want things to behave, not the way they actually behave". Old, but it is the only first-party statement.

2. **Only two keys exist: `KEY_ENTER` (right-top) and `KEY_ESC` (right-bottom).** No UP/DOWN/LEFT/RIGHT/MENU. Unlike Venu 2/3, Venu 4 has **no `menu` pseudo-key** and no `onMenu` touch binding, so `BehaviorDelegate.onMenu()` is unreachable. Bound touch behaviours: tap→`onSelect`, swipeRight→`onBack`, swipeUp→next page, swipeDown→previous page. swipeLeft, hold and release are unbound and surface raw.

3. **Use `onDrag`, not `onSwipe`.** `SwipeEvent` carries a direction only — no coordinates, no velocity — and fires only once the gesture completes. `onDrag` is explicitly supported on this device and gives `DRAG_TYPE_START/CONTINUE/STOP` with coordinates, i.e. a real touch-down signal; `onFlick` adds measured velocity. **Garmin documents no touch latency or event rate anywhere.** The only quantified figures for this device are the swipeRight recogniser parameters (250 ms / 90 px / 81 px from edge), and even those field semantics are inferred.

4. **Accelerometer: no gesture API, poll it yourself.** The device supports 100 Hz high-frequency accel, but `registerSensorDataListener` batches with a **1-second minimum `:period`**, which is wrong for interactive shake detection. The workable path is `Sensor.getInfo().accel` (millig) polled from the game timer — what Garmin's own AccelMag sample does at 100 ms for a real-time accel game. Handle the documented null case where a device has not enabled the accelerometer at startup. The simulator has **no shake control** (only random FIT "Simulate Data" or FIT playback), so a debug injection path is needed.

5. **Simulator keyboard gives Enter and Esc, and nothing else.** The SDK's own mapping table (`doc/docs/Readme/History.html`, v3.0.0.beta1 release notes) lists Enter/Esc/arrows/M/F/I/O/P, but it is filtered by the device's `keys` array — so on `venu445mm` only **Enter → `KEY_ENTER`** and **Esc → `KEY_ESC`** are live. Two keyboard inputs for a game that wants four directions plus A and B: a remap is unavoidable even for simulator-only development. Everything else comes from the mouse — button hotspots on the device image, and the 454×454 screen at offset (98,223) for tap/hold/drag/swipe.

**Left open, not guessed:** whether holding a host key yields one sustained down/up pair or OS-rate repeats of `onKeyPressed`, and whether focus placement affects key delivery. The SDK's `samples/Input` app prints press/release status live and settles both — build it first.

**Consequence for the map:** the "defer input mapping, use the simulator keyboard first" plan does not survive contact. Two keys cannot carry A/B/Left/Right, so [Input abstraction layer](./09-input-abstraction-layer.md) must decide a real remap now, and touch is load-bearing from the first build rather than later.
