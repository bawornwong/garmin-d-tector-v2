# Coroutine conversion strategy

Type: grilling
Status: resolved
Blocked by: 07

## Question

How do all 60 coroutines in `Animations.cs` get converted into VM step lists, and how is the result verified as visually identical?

Decide:

- **Conversion method** — by hand, by a script that parses the C# and emits step lists, or a hybrid (script does the mechanical bulk, a human resolves what it cannot).
- **Non-mechanical constructs** — inventory the coroutines that do something the VM's vocabulary cannot express directly (conditional branching mid-animation, waiting on input, nested coroutine calls, `yield return` on another coroutine). Each needs a named treatment.
- **Verification** — the fidelity contract says visuals are exact. How is that checked? Frame-by-frame capture from the Unity original against the simulator? Eyeballing? A golden-frame test set? Decide the standard and what "identical enough" means, because a per-frame pixel diff across 60 animations is a project in itself.
- **Ordering** — which animations must be converted for the first vertical slice (Status + Database), and which can wait.

This is the largest single chunk of the port. Getting the method wrong costs weeks.

## Answer

Harness: [`prototype/golden/`](../prototype/golden/) — a .NET 9 console project that compiles the **unmodified** `Animations.cs` against stubs and runs every coroutine.

### The conversion surface, counted

60 coroutines across 2,988 lines: 53 public, 6 nested local ones, and one private helper. 550 yields, 31 of them calls to another coroutine. 214 `for` loops, 113 `if`s, 281 local declarations.

By difficulty: **4 linear** (no `if`, no `for`, no sub-call), **41 moderate** (≤80 lines, no nested coroutine), **15 hard**. The five largest are `StartGameAnimation` (236 lines, 48 yields, 19 loops), `AttackCollision` (194 lines, 35 `if`s, 5 nested coroutines), `SusanoomonEvolution` (148), `AncientEvolution` (147), `FusionSpiritEvolution` (139).

### What the prototype's runner does not yet handle

```csharp
1181: Coroutine bgAnimation = gm.StartCoroutine(AnimateSPScreen(sbSPBackground));
1204: gm.StopCoroutine(bgAnimation);
```

`AWardSpiritPower` and `PaySpiritPower` run a background animation **in parallel** and later stop it, and there are **30 more** `StartCoroutine`/`StopCoroutine` sites outside `Animations.cs`. The runner built for [Animation VM instruction set](./07-animation-vm-instruction-set.md) has a call stack but no concurrency.

### Decisions

1. **Hybrid conversion: a script emits the skeleton, a human fills the statements.** The mechanical, error-prone parts are exactly what a script does reliably — splitting a body into `pc` cases at every yield, generating loop head/body case pairs with their back-edges, and lifting every local that survives a yield into a field. The ordinary statements (`.SetSprite()`, `.Move()`) are quick to translate by hand and easy to review. A full C#→Monkey C transpiler would need real control-flow analysis and costs more than it saves across 60 routines.

2. **Golden traces are generated from the true source, never transcribed.** This is the load-bearing decision. Ticket 07's golden was a hand transcription of the C# into Python — doing that 60 times repeats the translation risk twice over. Instead, 485 lines of stubs (Unity types 257, the builder layer 182, extras 46) plus a 47-line driver reimplementing Unity's coroutine pumping let the **unmodified** `Animations.cs` compile and run outside Unity, with every builder call recording an event and every `WaitForSeconds` advancing a clock.

   The harness immediately earned its place: the hand-written golden in ticket 07 emitted a `clearAnimParent` event that the real code does not produce, because `ClearAnimParent()` iterates an empty child list. One spurious event per `LaunchAttack` case — exactly the class of error this removes.

3. **The runner gains fibers.** `startCoroutine()` returns a handle and `stopCoroutine(h)` drops that fiber; each fiber keeps its own call stack. This maps 1:1 onto `StartCoroutine`/`StopCoroutine`, so translated code keeps the shape of the original.

4. **Treatments for what cannot be automated:**

   | Construct | Count | Treatment |
   |---|---|---|
   | yield inside a `for` | 177 | script emits paired head/body cases with a back-edge |
   | call to another coroutine | 31 | push onto the fiber's stack |
   | nested local coroutine | 6 | inner class of the parent, sees the parent's fields |
   | parallel `StartCoroutine` | 2 (+30 elsewhere) | fiber plus handle |
   | wait with a runtime-computed duration | 22 (`animDuration / 64`, `Random.Range(0.25f, 1f)`, `delay`, `finalDelay`) | the case returns a computed `Float` |
   | `foreach` | 9 | index loop |

5. **Order: the vertical slice first.** Start with the 4 linear coroutines to validate the whole pipeline — script → skeleton → fill → golden diff — then the Status and Database animations agreed at charting, then Battle. The 236-line `StartGameAnimation` is last.

6. **"Identical" means the event and schedule diff.** Comparing event order, scheduled time and arguments catches everything a state-machine transform can get wrong — order, timing, and the values passed. Frame-by-frame pixel comparison is left to spot checks, because the pixels are the display list and renderer's responsibility ([Render pipeline prototype](./06-render-pipeline-prototype.md)), not the transform's.

### Verification that the harness scales

Invoked by reflection over every public coroutine, with synthesised arguments:

**53 of 53 coroutines traced, 0 failures, 6,911 events.**

| Coroutine | Duration | Events |
|---|---|---|
| `StartGameAnimation` | 52,781.3 ms | 898 |
| `TransitionToMap3` | 22,850.0 ms | 722 |
| `DataStorm` | 14,850.0 ms | 638 |
| `SusanoomonEvolution` | 20,000.0 ms | 443 |
| `FusionSpiritEvolution` | 20,300.0 ms | 390 |

Every one of the 60 coroutines now has a golden to be checked against, produced from the source rather than from anyone's reading of it.

### Note

The stubs synthesise sprite data (`GetAllDigimonSprites` returns generated names), so traces are self-consistent but not tied to the real sprite database. Where an animation's behaviour depends on actual data — `digimonSprites[4].texture.width > 32` in `LaunchAttack` picks the wide-sprite branch — the stub must be fed the real values before that branch is trusted.
