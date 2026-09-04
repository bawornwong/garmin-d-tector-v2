# Connect IQ input events and simulator keyboard

Type: research
Status: open
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
