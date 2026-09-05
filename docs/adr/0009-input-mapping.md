# 9. Two buttons carry A and B; held screen halves carry Left and Right

Date: 2026-09-06

## Status

Accepted. Supersedes the plan to defer input mapping.

## Context

The source exposes A, B, Left and Right, each with press, hold and release, plus shake. `Maze.cs` maps all four to directions and holds them: `InputADown` starts moving up, `InputAUp` stops. **Four sustained, mutually distinguishable inputs are required.**

Venu 4 has **two physical keys** — `KEY_ENTER` and `KEY_ESC` — and no menu pseudo-key. The simulator's keyboard is filtered by the device's key list, so it offers exactly those two. The original plan to develop against the simulator keyboard and decide hardware mapping later therefore had nothing to develop against.

## Decision

`KEY_ENTER` → **A**, `KEY_ESC` → **B**, both via `onKeyPressed`/`onKeyReleased`. Holding the **left half** of the screen → **Left**, the **right half** → **Right**. That is exactly four sustained inputs and no more. Nothing is drawn over the canvas.

All twelve abstract events are kept, so the logic layer translates unchanged. The adapter feeds an event queue that the 20 fps loop drains, giving deterministic per-frame ordering and a seam that a future remap touches alone.

Touch down is `onDrag START` **or** `onHold`, whichever arrives first; touch up is `onDrag STOP` **or** `onRelease`. `onSwipe` is consumed and discarded. Exiting is timed from a long press of `KEY_ESC`, since `onBack` fires on release.

## Consequences

- Interaction deviates from the original in a stated, bounded way: Left and Right are touch rather than buttons. Content and visuals — what the fidelity contract covers — are untouched.
- The dual-path touch handling is not belt-and-braces. A perfectly still touch produces **no drag events at all**, only `onHold` about a second late; one pixel of movement produces `START` immediately. A real finger jitters, but the fallback is what makes that an optimisation rather than an assumption.
- Hold semantics are developable in the simulator: a held key gives one sustained down/up pair with the held time recoverable to the millisecond.
