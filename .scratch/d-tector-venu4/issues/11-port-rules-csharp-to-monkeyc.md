# C# to Monkey C port rules

Type: grilling
Status: resolved
Blocked by: 04

## Question

What are the mechanical rules for translating the `Logic/` layer from C# to Monkey C?

The locked port rule: `Logic/` translates close to line-for-line to preserve behaviour; presentation is rewritten natively. This ticket makes "close to line-for-line" precise enough that two sessions translating different files produce consistent code.

Decide a rule for each construct the source uses and Monkey C lacks:

- **Properties** (`get`/`set`) → methods? public members? naming convention?
- **Generics** (`List<T>`, `Dictionary<K,V>`) → `Array` / `Dictionary` with what type discipline, given Monkey C's optional typing
- **LINQ** → explicit loops; whether a small helper module is worth it
- **Interfaces** (`IAppController`) → duck typing, or a base class?
- **Enums** (`MenuEnums.cs`, `DigimonRarity.cs`) → module constants, and how exhaustive switches are handled
- **Exceptions** (`IllegalBoundsException`) → Monkey C exception support and what replaces the ones it cannot express
- **Numerics** — C# `int`/`float` versus Monkey C `Number`/`Float`/`Long`/`Double`. This one is load-bearing for the fidelity contract: `Constants.ATTACK_TRAVEL_SPEED = 0.05f`, and battle math depends on rounding. Decide the numeric mapping and where it could diverge.
- **`C_Int.cs`** (145 LOC) — a custom clamped-integer type. Direct translation or replacement?
- **Naming and file layout** — how `Assets/Scripts/Logic/**` maps onto a Monkey C source tree, so a reviewer can diff a ported file against its original.

Output is a rules document the build effort follows.

## Answer

### Findings from the source

`Logic/` is 32 files, 9,090 lines. Construct census:

| Construct | Count | Monkey C |
|---|---|---|
| float literal (`0.05f`) | 573 | `Float` exists, semantics differ |
| `float` type | 76 | yes |
| `Mathf.*` | 54 | partial `Math.*` |
| `override` / `virtual` | 79 / 16 | inheritance exists |
| array `[]` | 145 | `Array` |
| `static` | 136 | module |
| `enum` declaration | 23 | `enum` exists |
| `Random.Range` | 33 | only `Math.rand()` |
| **operator overload** | **30** | **absent** |
| `readonly` / `const` | 37 / 21 | `const` |
| **`out` / `ref` parameter** | **33 / 7** | **absent** |
| ternary / switch | 30 / 16 | yes |
| generic `<T>` | 16 | no generics |
| string interpolation `$"` | 40 | absent |
| `interface` / `abstract` | 2 / 2 | no `interface` keyword |
| extension method | 5 | absent |
| LINQ | 4 sites | absent (mercifully rare) |

Confirmed from the SDK's own `doc/Toybox/Math.html`:
- `Math.pow(x, y)` returns **Float when both inputs are Number or Float**, Double if either is Long or Double — matching `Mathf.Pow`'s float return.
- `Math.floor`/`ceil`/`round` **return the input's type**, so `.toNumber()` is required explicitly.
- `Math.rand()` returns a non-negative Number, with `Math.srand(seed)`. **There is no range API.**

### Decisions

1. **The logic/presentation boundary is `IEnumerator`, not the folder.** The original port rule said "`Logic/` translates line-for-line", but `Logic/Data/Animations.cs` is 2,902 lines — **32% of `Logic/`** — of pure presentation carrying 535 `yield return`s, and the other 45 yields are scattered through real app files (`Maze.AutoNavigateDir` and friends). A per-folder split cuts the wrong way. New rule: **anything that is a coroutine belongs to the animation VM** ([Animation VM instruction set](./07-animation-vm-instruction-set.md), [Coroutine conversion strategy](./08-coroutine-conversion-strategy.md)); everything else in `Logic/` is translated line-for-line. `Animations.cs` moves wholesale to the VM side, and app files containing coroutines are split within the file.

2. **Numeric rule — the heart of the fidelity contract.** Outcome-deciding formulas use 32-bit float with fractional-exponent `Mathf.Pow`, then floor (25 sites):

   ```
   level     = FloorToInt(Mathf.Pow(playerXP, 1f/3f))
   expGained = ((a * (b/c)) + 1) * d    // b, c = Mathf.Pow(..., 2.5f)
   cost      = baseCost * Mathf.Pow(0.5f, playerLevel/decay)
   ```

   A one-ULP error crosses a floor boundary and the player's level is wrong. The rule: **compute in `Float` — `Math.pow` already returns Float for Number/Float inputs — force `.toFloat()` at each narrow point, and `.toNumber()` only after `Math.floor`.** Integer-only reformulation was rejected: it would change results. This rule is **not trusted until measured** — see [Numeric parity golden test](./14-numeric-parity-golden-test.md).

3. **`C_Int` becomes a class with named methods**: `add`, `sub`, `mul`, `div`, `mod`, `shl`, `shr`, `eq`, `lt`, and so on, so `a + b` becomes `a.add(b)` at every call site. Ugly, and correct: `C_Int` clamps **every operation**, not just assignment. Replacing it with a plain `clamp(v, min, max)` after the fact would miss mid-expression clamping that the original applies — which is exactly where game results would diverge.

4. **RNG reproduces semantics, not sequence.** Write `Rand.rangeInt(min, max)` (max **exclusive**, as C# `Random.Range(int,int)`) and `Rand.rangeFloat(min, max)` (max **inclusive**, as C# `Random.Range(float,float)`) over `Math.rand()`. Unity does not seed deterministically, so players already see different sequences every run; what must match is the **bounds and the probabilities**. The exclusive/inclusive split is the silent-bug risk — an off-by-one there changes drop rates.

5. **Mechanical rules, approved as a block:**

   | C# | Monkey C | Sites |
   |---|---|---|
   | property `get`/`set` | `getX()` / `setX(v)` | 37 |
   | expression-bodied `=>` | ordinary method | 70 |
   | `out` parameter | return `[ok, value]` array | 33 |
   | `ref` parameter | take and return the value | 7 |
   | `interface IAppController` | base class + duck typing | 2 |
   | `abstract` / `virtual` | plain method, subclass overrides | 18 |
   | `enum` | Monkey C `enum {}` | 23 |
   | generic `<T>` | fixed type per use site | 16 |
   | extension method | module function | 5 |
   | `$"..."` | `Lang.format("$1$...", [x])` | 40 |
   | LINQ | explicit loop | 4 |
   | `throw new IllegalBoundsException` | `throw new Lang.Exception()` | 5 |
   | `readonly` / `const` | `const` | 58 |

6. **Layout is 1:1 for diffability.** `source/logic/<original name>.mc`, one file per original, each carrying a provenance comment (`// port of Logic/Models/Digimon.cs:119`) so a reviewer can hold the two files side by side and spot anything dropped. Modules are annotated `(:extendedCode)`, which research proved exempt from the 768 KB limit.

7. **Working app first, idiom later.** The user's standing instruction: get it running, then refactor. Where a literal translation and an idiomatic Monkey C one conflict, **take the literal one** and leave the idiom for a later pass. Do not "improve" logic in flight — a cleanup that changes a result is a content change.

### Consequences

- [Data pipeline: JSON to Connect IQ resources](./12-data-pipeline-json-to-resources.md) is unblocked.
- The map's fog entries for battle-math parity and RNG parity are resolved into decision 2 and decision 4, and the remaining doubt is now a concrete measurement in [Numeric parity golden test](./14-numeric-parity-golden-test.md).
