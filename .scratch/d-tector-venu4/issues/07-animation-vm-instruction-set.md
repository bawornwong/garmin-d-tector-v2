# Animation VM instruction set

Type: prototype
Status: resolved
Blocked by: 04, 06

## Question

What is the instruction set of the animation VM that replaces Unity's coroutines?

`Animations.cs` is 2,902 LOC — 60 coroutines and 535 `yield return` statements. Monkey C has no coroutines. The locked decision is a data-driven VM: each animation becomes a list of steps, one interpreter walks them on a timer.

Decide:

- **Step vocabulary** — the minimum set of instructions that covers all 60 coroutines. Candidates: draw sprite at position, move sprite over N frames, wait N frames, show/hide, play sound (no-op, audio is out of scope), set text, clear region, loop, branch on state, call a sub-animation.
- **Step representation** — Monkey C arrays and dictionaries, or a packed byte encoding? Weigh RAM cost against readability against the cost of writing a converter.
- **The interpreter** — how it is driven (`Timer` tick versus `onUpdate`), how it composes with the render pipeline, how it is interrupted or cancelled mid-animation, how nested and parallel animations work.
- **Coverage proof** — pick the three most structurally different coroutines in `Animations.cs` and hand-encode them in the proposed instruction set. If any of the three does not fit, the vocabulary is wrong.

Prototype the interpreter plus those three animations, and compare against the original running in Unity.

## Answer

Prototype: [`prototype/anim/`](../prototype/anim/) — a Python golden reference transcribing the original C# coroutine semantics, and a Monkey C probe built for `venu445mm` and run in the simulator.

### The data-VM plan does not survive reading the file

The charting session specified a data-driven VM before anyone had opened `Animations.cs`. Reading it:

| Control flow in `Animations.cs` | Count |
|---|---|
| `for` loop | **202** (177 contain a wait) |
| `if` / `else` | 105 / 61 |
| local variable declaration | **267** |
| nested local coroutine | 6 |
| `while` / `switch` | 1 / 1 |

Of 535 yields, **504 are `WaitForSeconds`**, 26 call another coroutine, 1 is `yield return null`.

A data VM covering this needs branching, loop counters, arithmetic over 267 locals and a call stack — that is a general-purpose bytecode interpreter, which then has to be fed 2,900 lines of hand-compiled C# with no compiler checking the translation.

### The timing grid

Every `WaitForSeconds` in the codebase, evaluated:

| | |
|---|---|
| Waits that are exact multiples of the 50 ms tick | **434 / 531 (82%)** |
| Waits that would drift >10% if rounded individually | 69 |
| Waits **shorter than one tick** (0.0156–0.0469 s) | 36 — rounding these to one tick slows them by up to **+220%** |

The game was authored on a 0.05 s grid; `Constants.ATTACK_TRAVEL_SPEED = 0.05f` is exactly one tick. The 18% that are not on the grid are the fast per-frame motion loops.

### Decisions

1. **State-machine transform, not a data VM.** Each coroutine becomes a class with a `pc` field: every `yield return new WaitForSeconds(t)` is a resume point returning `t`, and every C# local that survives a yield becomes a field. This is the transformation the C# compiler already performs for iterators. Control flow stays real Monkey C, so the compiler type-checks it and the file still diffs line-for-line against the original — which is what the standing "literal over idiomatic" rule asks for.

2. **A fractional scheduler, not per-wait rounding.** The runner keeps the original schedule in floating-point milliseconds. Each 50 ms tick advances a budget and executes *every* step whose scheduled time has arrived. Waits shorter than a tick still happen — several within one frame — so total durations match the original exactly instead of drifting. Motion loops therefore advance more than one pixel per frame, which is the unavoidable consequence of showing a 60 fps original at 20 fps: the choice is between losing smoothness and losing duration, and duration is the more perceptible of the two.

3. **A retained display list mirroring `ScreenElement`.** Animations do not draw frames; they create elements and mutate them — `SetSprite` 311, `SetActive` 305, `Move` 155, `BuildSprite` 144, `SetSize` 129, `SetPosition` 82, `Center` 56, `PlaceOutside` 44, `SetTransparent` 41, `Dispose` 41, `FlipHorizontal` 39, `SetText` 17, and about a dozen more, ~24 operations in all. The port mirrors `ScreenElement`/`SpriteBuilder`/`TextBoxBuilder`/`RectangleBuilder` with the same names, and the renderer draws the whole list each frame from the row buffers of [Render pipeline prototype](./06-render-pipeline-prototype.md).

4. **Sub-animations run on a call stack.** The 26 sub-coroutine yields and the 6 nested local coroutines push a routine onto the runner's stack; the parent resumes at the same scheduled time when the child finishes. Inlining them would bloat already-long animations and break the line-for-line diff.

5. **Audio calls are kept as empty no-ops.** The 44 `PlaySound` and 20 `PlayButtonA` calls stay in the translated source with an empty body, so the files still diff against the original and a future audio or vibration effort fills in one place.

### Verification

Three structurally different coroutines were transformed and run: `CharHappy` (short, linear, calls another coroutine twice), `LaunchAttack` (a 38-iteration loop with a runtime-computed second loop and three nested branches), across its `attack == 0`, `attack == 1` with `disobeyed`, and `attack == 3` paths.

**150 of 150 events match the golden trace exactly** — same order, same scheduled time. End-to-end durations match to the fourth decimal:

| Case | Events | End time | Display ticks used | Max events in one tick |
|---|---|---|---|---|
| `CharHappy` | 16 | 4000.0000 ms | 9 | 5 |
| `LaunchAttack(0, …)` | 55 | 2518.7500 ms | 41 | 11 |
| `LaunchAttack(1, enemy, disobeyed)` | 63 | 3000.0000 ms | 11 | 11 |
| `LaunchAttack(3, …)` | 16 | 2600.0000 ms | 5 | 11 |

The "max events in one tick" column is the fractional scheduler doing its job: where the original waited less than 50 ms, several steps collapse into one displayed frame rather than stretching the animation.

### Consequences

- [Coroutine conversion strategy](./08-coroutine-conversion-strategy.md) is unblocked, and its question narrows: the transform is mechanical enough to script, and the golden-trace diff used here becomes the verification method for all 60 coroutines.
- The display list is now a named component the render pipeline must draw; it did not exist in the earlier plan.
