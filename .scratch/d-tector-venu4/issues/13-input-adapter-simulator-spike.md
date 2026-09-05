# Input adapter simulator spike

Type: prototype
Status: resolved
Blocked by: 09

## Question

Do the two unverified assumptions behind the input mapping hold on `venu445mm`?

[Input abstraction layer](./09-input-abstraction-layer.md) decided the mapping — `KEY_ENTER`→A, `KEY_ESC`→B, left/right screen halves held via `onDrag`→Left/Right — but two things could not be settled from documentation.

Build a throwaway Connect IQ app that logs every input event with a timestamp, and answer:

1. **Does `DRAG_TYPE_STOP` always fire on finger lift?** Including a lift near the screen edge, a lift during a system gesture, and a lift while the app is losing focus. If it can be missed, an input latches down forever and Maze becomes unplayable — so establish the timeout fallback empirically.
2. **Does Venu 4 reserve long-press `KEY_ESC` for the system?** If it does, the app cannot use it to exit and needs another route out.
3. **Does holding a host key in the simulator produce one sustained down/up pair, or OS-rate repeats of `onKeyPressed`?** Left open by the input research; it determines whether hold timing can be developed in the simulator at all.
4. **Does swipe-left survive?** It is unbound by the system, so it should reach the app raw — confirm, since the left half of the screen is now Left and a horizontal drag there must not be swallowed as a system gesture.
5. **Does consuming `onBack` actually prevent the app exiting?**

Start from the SDK's own `samples/Input` app, which already prints press/release state live.

The output is a verified event-flow table the adapter is written against, plus the timeout value from question 1.

## Answer

Probe: [`prototype/input/ciq/`](../prototype/input/ciq/) — a `BehaviorDelegate` logging every input event with a timestamp. Driven by [`prototype/input/evt.swift`](../prototype/input/evt.swift), a 40-line CGEvent tool that can press-and-hold the mouse, drag along a path, and hold a key by key code (AppleScript can hold only character keys). Full trace: [`prototype/input/trace.txt`](../prototype/input/trace.txt).

*Method note*: the simulator must be frontmost or it silently receives nothing — worth knowing before trusting a null result from this kind of automation.

### 1. Does `DRAG_TYPE_STOP` always fire on lift? — **Yes, and START fires at touch-down**

A drag inside the left half:

```
277357 onDrag START    (97,203)   half=LEFT
277358 onDrag CONTINUE (97,203)
277483 onDrag CONTINUE (104,208)
  ... 
278100 onDrag STOP     (131,230)  half=LEFT
```

STOP fired on every drag tested — slow, fast, and one crossing the screen's midpoint. Coordinates are canvas-relative (0–453), so the left/right split at x = 227 works directly.

**The degenerate case matters**: a *perfectly* still touch produces **no drag events at all** — only `onHold`, and that arrives about **1 second late**, then `onRelease` on lift:

```
190220 onHold    (91,198)
190726 onRelease (91,198)
```

A single pixel of movement is enough to rescue it — `START` then fires immediately at touch-down, with `onHold` arriving alongside and `STOP` still firing on lift:

```
282165 onDrag START    (91,198)
282554 onHold          (91,198)     <- 389 ms later, alongside the drag
282764 onDrag CONTINUE (92,198)
283368 onDrag STOP     (92,198)
283370 onRelease       (92,198)
```

A real finger is never perfectly still, so `START` will normally arrive at touch-down. But the adapter must not depend on that: **treat `onHold` as a down when no `START` has arrived, and `onRelease` as an up.** Both paths end in a definite up event, so the timeout fallback ticket 09 asked for is not needed — though a cheap one is still worth keeping against a lost event.

### 2. Does Venu 4 reserve a long press of `KEY_ESC`? — **No**

```
166559 onKeyPressed  KEY_ESC
169052 onBack (consumed)
169053 onKeyReleased KEY_ESC heldMs=2495
```

The app received the full 2.5 second hold and kept running. **`onBack` fires on release, not during the hold**, so a hold-to-exit gesture must be timed from the down/up pair rather than from `onBack`.

### 3. Does holding a host key repeat? — **No, one sustained pair**

| Gesture | Trace |
|---|---|
| Tap | `onKeyPressed`, then `onSelect` + `onKeyReleased heldMs=31` |
| Hold 2.5 s | `onKeyPressed`, then `onSelect` + `onKeyReleased heldMs=2239` |

One `onKeyPressed` and one `onKeyReleased` regardless of duration, with the held time recoverable to the millisecond. **Hold semantics can be developed in the simulator**, which the input research had left open. Note the ordering: the behaviour event (`onSelect`, `onBack`) fires immediately *before* `onKeyReleased`.

### 4. Does swipe-left reach the app? — **Yes, and the drag events arrive first**

```
286877 onDrag START    (349,198) half=RIGHT
286957 onDrag CONTINUE (308,198) half=RIGHT
287071 onDrag CONTINUE (226,198) half=LEFT     <- crosses the midpoint
  ...
287386 onDrag STOP     (61,198)  half=LEFT
287386 onSwipe LEFT
```

The full drag sequence arrives throughout the gesture and `onSwipe LEFT` only at the end, after `STOP`. A fast swipe (18 ms per step) still delivers START, a CONTINUE and STOP. So an adapter built on `onDrag` sees everything; **`onSwipe` should be consumed to prevent the same gesture being handled twice.**

Drag events track the input closely — CONTINUE events arrived 58–70 ms apart for 60 ms input steps, and 120–126 ms apart for 120 ms steps — so there is no meaningful added latency at the 50 ms game tick.

### 5. Does consuming `onBack` prevent exit? — **Yes**

Every `KEY_ESC` press logged `onBack (consumed)` and the app kept running throughout the session.

### Consequences for the adapter

The mapping from [Input abstraction layer](./09-input-abstraction-layer.md) survives, with one addition:

- **Touch down** is `onDrag START` **or** `onHold`, whichever arrives first.
- **Touch up** is `onDrag STOP` **or** `onRelease`, whichever arrives first; ignore the second.
- Half-crossing is handled inside `onDrag CONTINUE`, as designed — the trace above shows the midpoint crossing arriving as an ordinary CONTINUE.
- `onSwipe` is consumed and discarded.
- Exit-by-hold is timed from `onKeyPressed`/`onKeyReleased` on `KEY_ESC`, not from `onBack`.

### Not covered

Everything here is the simulator with synthetic events. A real digitizer may differ in the one place it matters most — whether a resting finger generates the small movements that produce `START` — which is exactly why the `onHold` fallback is not optional.
