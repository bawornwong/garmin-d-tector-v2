# Animation VM instruction set

Type: prototype
Status: open
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
