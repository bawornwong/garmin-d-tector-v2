# 2. Prefer literal translation over idiomatic Monkey C

Date: 2026-09-06

## Status

Accepted

## Context

The source is 12,261 lines of C# built on Unity's object model. Monkey C has no properties, no generics, no operator overloading, no `out` parameters, no coroutines. Every one of those needs a translation rule, and each rule can be resolved either toward what reads naturally in Monkey C or toward what diffs cleanly against the original.

The game's behaviour is not separately specified anywhere. The source *is* the specification, so any translation that cannot be checked against it line by line cannot be checked at all.

## Decision

**Where a literal translation and an idiomatic one conflict, take the literal one.** Ported game logic lives under `app/source/Logic/`, with source references on the implementations where useful.

Concretely: `C_Int`'s 30 operator overloads become named methods, so `a + b` becomes `a.add(b)` at every call site, because `C_Int` clamps *every* operation and a tidier `clamp()` at the end of an expression would miss mid-expression clamping. The source's `audioMgr.PlaySound` call sites remain; they now drive watch feedback. Cleanups that change a result are content changes.

## Consequences

- A reviewer can hold two files side by side and see what was dropped.
- The code will read awkwardly in places. That is the price, and it is paid deliberately.
- A later idiomatic pass is possible once behaviour is verified; it is not part of this effort.
