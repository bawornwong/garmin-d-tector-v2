# 4. Coroutines become state machines, not a data-driven VM

Date: 2026-09-06

## Status

Accepted. Supersedes the data-VM approach assumed while charting.

## Context

`Animations.cs` is 2,902 lines: 60 coroutines, 535 `yield return`s. Monkey C has no coroutines, so something has to replace them.

The plan formed before anyone opened the file was a data-driven VM: compile each coroutine into a list of steps and interpret them. Reading the file killed it. The coroutines contain **202 `for` loops** (177 with a wait inside), **105 `if`s**, **267 local declarations**, six nested local coroutines, and loops whose bounds are computed at runtime. A VM covering that is a general-purpose bytecode interpreter, which then has to be fed 2,900 hand-compiled lines with no compiler checking the translation.

## Decision

Each coroutine becomes a **class with a `pc` field**: every `yield return new WaitForSeconds(t)` is a resume point returning `t`, and every local surviving a yield becomes a field. This is the transformation the C# compiler already performs for iterators. Control flow stays as real Monkey C.

Sub-coroutines push onto a **fiber**'s call stack. `StartCoroutine`/`StopCoroutine` — 2 sites in `Animations.cs` and 30 elsewhere — create and drop fibers.

Conversion is a hybrid: a script splits bodies at yields, generates loop head/body case pairs with their back-edges, and lifts locals to fields; a human fills in the statements.

## Consequences

- The compiler type-checks the translation, and files still diff against the original.
- No interpreter of our own to debug.
- Verified on three structurally different coroutines: **150 of 150 events matched** the golden trace in order and scheduled time.
- The runner needs concurrency, which the first prototype lacked.
