# Numeric parity golden test

Type: prototype
Status: open
Blocked by: 11

## Question

Does Monkey C's `Float` arithmetic reproduce Unity's `Mathf` results closely enough that no floor boundary is ever crossed?

[C# to Monkey C port rules](./11-port-rules-csharp-to-monkeyc.md) decided the numeric rule — compute in `Float`, narrow with `.toFloat()`, convert with `.toNumber()` only after `Math.floor` — but the rule is an assumption until measured. The exposure is 573 float literals, 54 `Mathf` calls and 25 floor sites, and the failure mode is silent: a one-ULP difference crosses a floor boundary and the player's level, EXP or unlock cost is wrong, with nothing to indicate it.

Build a harness that runs both sides over the same inputs and diffs the outputs:

- **The formulas that decide outcomes**, at minimum:
  - `level = FloorToInt(Mathf.Pow(playerXP, 1f/3f))`
  - `expGained = ((a * (b/c)) + 1) * d`, where `b`, `c` are `Mathf.Pow(..., 2.5f)` — from `LogicManager.cs:847-852`
  - `cost = baseCost * Mathf.Pow(0.5f, playerLevel/decay)` — from `Digimon.cs:111`
  - `percLevelDiff = baseLevel / (float)playerLevel` — from `Digimon.cs:119`
- **Input coverage**: sweep the whole plausible range rather than sampling — every player XP up to the maximum reachable, every level pair from 1 to 51 (the maximum stored level found in the save data), every Digimon `baseLevel`.
- **The C# side** runs the original formulas, either in the Unity project or in a standalone C# console program using the same `float` and `Mathf` semantics. Justify whichever is used — `Mathf.Pow` computes in double and casts to float, and a naive `Math.Pow` port would not reproduce it.
- **The Monkey C side** runs in the simulator and emits its results in a diffable form.

Answer:

1. **Do all outputs match exactly?** If not, how many inputs diverge, and by how much?
2. **Does any divergence cross a floor boundary?** This is the only difference that changes gameplay. A mismatch in the 7th decimal that floors identically is harmless.
3. **If boundaries are crossed**, what fixes it — computing in `Double` and narrowing later, an epsilon nudge before flooring, or an integer reformulation of that specific formula?
4. **Is `Math.pow` on this device actually IEEE-754 single precision?** Undocumented; the sweep answers it empirically.

The output is a verdict on the numeric rule plus, if needed, a per-formula exception list.
