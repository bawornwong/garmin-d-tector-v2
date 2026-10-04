# 9. Two buttons carry A and B; four touch sectors carry Left, Right, A and B

Date: 2026-09-06

## Status

Accepted. Supersedes the plan to defer input mapping. Touch mapping amended
2026-09-28 to match the player's three-zone diagram and remove swipe input,
then 2026-09-30 to match the four-sector diagram.

## Context

The source exposes A, B, Left and Right, each with press, hold and release, plus shake. `Maze.cs` maps all four to directions and holds them: `InputADown` starts moving up, `InputAUp` stops. **Four sustained, mutually distinguishable inputs are required.**

Venu 4 has **two physical keys** — `KEY_ENTER` and `KEY_ESC` — and no menu pseudo-key. The simulator's keyboard is filtered by the device's key list, so it offers exactly those two. The original plan to develop against the simulator keyboard and decide hardware mapping later therefore had nothing to develop against.

## Decision

`KEY_ENTER` → **A**, `KEY_ESC` → **B**, both via `onKeyPressed`/`onKeyReleased`.
Touch uses four sectors meeting at the centre of the 454 px screen. The two
diagonals divide it into **left → Left**, **right → Right**, **bottom → A**, and
**top → B**. At an exact diagonal tie, the vertical sector wins; the exact
centre maps to A. The coloured regions in the player's diagram identify
touch targets; they are not colour overlays drawn over the game.

Each sector supports both taps and holds. The zone chosen at touch-down owns
the press until release, even when a finger drifts across a boundary. Swipe
direction never generates an additional Left or Right command.

All twelve abstract events are kept, so the logic layer translates unchanged. The adapter feeds an event queue that the 20 fps loop drains, giving deterministic per-frame ordering and a seam that a future remap touches alone.

The delegate derives directly from `WatchUi.InputDelegate`, so a quick touch
arrives as `onTap` with coordinates instead of being translated by
`BehaviorDelegate` into a coordinate-free `onSelect`. A standalone `onTap`
generates down/up/action immediately on release; no hold is required. A held
or moving finger still uses `onDrag START` or `onHold` for down and `onDrag
STOP` or `onRelease` for up/action. `onSwipe` is consumed and discarded. Exit
uses a long press of `KEY_ESC`, or two completed Back presses within 1.5
seconds on the idle character screen.

## Consequences

- Interaction deviates from the original in a stated, bounded way: Left and Right are touch rather than buttons. Content and visuals — what the fidelity contract covers — are untouched.
- The dual-path touch handling is not belt-and-braces. A perfectly still touch produces **no drag events at all**, only `onHold` about a second late; one pixel of movement produces `START` immediately. A real finger jitters, but the fallback is what makes that an optimisation rather than an assumption.
- Hold semantics are developable in the simulator: a held key gives one sustained down/up pair with the held time recoverable to the millisecond.
