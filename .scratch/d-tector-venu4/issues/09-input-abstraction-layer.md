# Input abstraction layer

Type: grilling
Status: resolved
Blocked by: 02

## Question

What is the input abstraction the game logic sees, and how is it wired to the SDK simulator's keyboard for the first build?

Physical hardware mapping is deliberately deferred. The logic layer must be written against an abstraction now, so that a later hardware decision changes one adapter and nothing else.

Decide:

- **The abstract vocabulary** — the source exposes A, B, Left, Right, each with press/hold/release, plus shake. Is that vocabulary preserved exactly, or narrowed to what the platform can actually deliver?
- **The adapter seam** — where the boundary sits between the Connect IQ delegate and the game logic, so that swapping the simulator-keyboard adapter for a hardware adapter touches nothing else.
- **Simulator mapping** — the concrete key-to-input table for development, drawn from the research findings.
- **Hold semantics** — the source distinguishes press, hold, and release. If Connect IQ cannot express one of them, decide the substitute now and record it as a known interaction deviation (permitted by the fidelity contract, which covers content and visuals only).
- **Shake** — whether shake is wired at all in the first build, or stubbed behind the abstraction.

## Answer

### Findings from the source

Input event usage across `Assets/Scripts` (excluding `InputManager.cs` itself): `InputA` 14, `InputB` 14, `InputLeft` 11, `InputRight` 11, `InputLeftDown`/`Up` 7 each, `InputRightDown`/`Up` 7 each, `InputADown`/`Up` 5 each, `InputBDown`/`Up` 4 each.

**Down/Up are genuine hold semantics, not taps:**
- `Maze.cs` — `InputADown` → `StartNavigation(Direction.Up)`, `InputBDown` → `Down`, Left/Right likewise; every `*Up` → `StopNavigation()`. **Four sustained, mutually distinguishable directional inputs are required.** This is the binding constraint.
- `SpeedRunner.cs` — `lastDirectionTapped` set on Down, cleared on Up: Left/Right held.
- `Finder.cs` — A held runs the loading bar; releasing it resets.

**Shake** is live in exactly one place: `LogicManager.ShakeDisabled()` returns true everywhere except inside the Status app. One detected shake calls `GameManager.TakeAStep()` → `WorldMgr.TakeSteps(1)` + `ReduceDistance(1)`, and `ShakeDetector.cs` requires 5 detections per step (`nextStep < 5`).

### Decisions

1. **Keep all 12 events.** A/B/Left/Right × press, down, up. The port rule translates `Logic/` close to line-for-line; narrowing the vocabulary would mean rewriting `LogicManager.cs`, `Maze.cs`, `SpeedRunner.cs`, `Finder.cs`, `CodeInput.cs`, `DatabaseApp.cs` and `DigiviceApp.cs`. The adapter absorbs the synthesis instead.

2. **Mapping: two buttons plus two touch halves.** `KEY_ENTER` (right-top) → **A**, `KEY_ESC` (right-bottom) → **B**, both via native `onKeyPressed`/`onKeyReleased`. Touch-hold on the **left half** of the screen → **Left**, **right half** → **Right**, driven by `onDrag`. That is exactly four sustained inputs, which is what Maze needs and no more. The physical buttons carry A and B because they are the most used (14 each) and because they are Maze's Up and Down. Nothing is drawn over the game canvas, so the visual fidelity contract is untouched.

3. **Touch down/up synthesis is a state machine in the adapter**, not a dependence on `DRAG_TYPE_CONTINUE` as a heartbeat: `START` inside a half → `InputLeftDown`; a `CONTINUE` that crosses into the other half → `Up` for the old half then `Down` for the new; `STOP` → `Up`. **Needs verification**: that `DRAG_TYPE_STOP` always fires on finger lift. If it does not, add a timeout so a missed STOP cannot leave an input stuck down.

4. **Shake: port `ShakeDetector.cs` faithfully** — low-pass filter, `shakeDetectionThreshold` 2.0 squared, 5 detections per step, active only inside Status — reading `Sensor.getInfo().accel` polled from the game timer (research established that `registerSensorDataListener` batches at a 1-second minimum and is unusable here). Because shake is live only in Status, accelerometer polling costs nothing in the rest of the game.

   *Reversal, recorded deliberately*: this ticket first proposed using the watch's real pedometer (`ActivityMonitor.getInfo().steps`), on the grounds that the physical D-Tector toy counted real steps and the Unity emulator only used shake because a PC has no legs. The user reaffirmed that the fidelity anchor is **the emulator source, not the toy** — this is a port, not a new game. Real steps would reduce in-game distance while merely walking, which the source never does. Rejected on those grounds. See Out of scope on the map.

5. **Seam: an event queue.** The adapter pushes abstract events; the game loop drains the queue on each 20 fps tick and calls into `LogicManager`. Connect IQ delivers input on a different path from the timer tick, so a queue gives the logic a deterministic per-frame ordering, makes input testable by feeding an event list, and confines any future remap to the adapter.

6. **`onBack` is consumed by the app** (return `true`) and delivered as **B**, since `KEY_ESC` is B under decision 2. Exit is via the game's own root-menu back, or a long-press of ESC. **Needs verification**: whether Venu 4 reserves long-press ESC for the system.

7. **A `(:debug)` second adapter for simulator work.** The simulator delivers only Enter and Esc from the keyboard; Left/Right would otherwise require mouse-dragging on the device image at offset (98,223), which makes testing Maze miserable. The debug adapter maps taps in the top/bottom screen zones to latched Left/Right. It sits behind the same seam and is annotated out of release builds.

### Consequences

- Interaction now deviates from the original in a stated, bounded way: Left and Right are touch rather than buttons. Content and visuals are untouched, which is what the fidelity contract covers.
- Two verifications are pulled forward into a spike — see [Input adapter simulator spike](./13-input-adapter-simulator-spike.md).
