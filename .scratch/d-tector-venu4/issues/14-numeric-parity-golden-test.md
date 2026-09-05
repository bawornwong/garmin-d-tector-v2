# Numeric parity golden test

Type: prototype
Status: resolved
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

## Answer

Harness: [`prototype/numeric/`](../prototype/numeric/) — a C# reference reproducing Unity's arithmetic, and [`prototype/numeric/ciq/`](../prototype/numeric/ciq/) — the same four formulas in Monkey C, run on `venu445mm` in the simulator.

### What was swept

All four outcome-deciding formulas, over their whole plausible input range:

| Formula | Source | Sweep | Values |
|---|---|---|---|
| `GetPlayerLevel` | `LogicManager.cs:453` | every XP from 1 to 300,000 | 65 level transitions |
| `GetExperienceGained` | `LogicManager.cs:846` | every level pair, 1–51 × 1–51 | 2,601 |
| `GetSpiritCost` | `Digimon.cs:73` | all 8 `(baseCost, decay)` pairs the source uses × level 1–99 | 792 |
| `GetCallCost` | `Digimon.cs:117` | every `(baseLevel, playerLevel)` pair, 1–51 × 1–51 | 2,601 |

The C# side sweeps XP exhaustively; the Monkey C side scans a ±8 window around each cube, which cannot miss a shifted boundary because `pow` is monotonic.

The reference uses `(float)Math.Pow` for `Mathf.Pow` and keeps every intermediate in 32-bit float, matching Unity's implementation.

### Result

**Byte-for-byte identical. 180 lines of output, `diff` reports nothing.** 6,059 computed values plus 65 level transitions, all matching.

The port rule from [C# to Monkey C port rules](./issues/11-port-rules-csharp-to-monkeyc.md) — compute in `Float`, `.toNumber()` only after `Math.floor` — holds on this device.

### Margins: how much headroom the agreement has

A parity test that passes with no headroom is luck, so the distance from each result to its nearest floor or ceil boundary was measured:

| Formula | Closest approach to a boundary | Where |
|---|---|---|
| `GetPlayerLevel` | **0.000** | every perfect cube — `xp=1` gives exactly 1.0, `xp=8` exactly 2.0 |
| `GetSpiritCost` | **0.000** | `base=20, decay=20, level=20` gives exactly 10 |
| `GetExperienceGained` | 3.662 × 10⁻⁴ | `friendly=45, enemy=50` gives 842.99963, ceiling 843 |
| `GetCallCost` | 9.804 × 10⁻⁴ | `base=28, player=51` gives 0.54901963 against the 0.55 threshold |

The two **zero-margin** cases are the important ones: at every perfect cube the level formula lands exactly on a floor boundary, so a single ULP of disagreement would change the player's level — and both sides agree there. That is the strongest available evidence that Monkey C's `Math.pow` is IEEE-754 single precision on this device and matches C#'s.

The thinnest real margin is `GetExperienceGained` at `friendly=45, enemy=50`: 842.99963 sits about **6 ULP** below 843. It agrees today, but it is the one value to re-check if the formula, the SDK, or the device firmware ever changes.

### Consequences

- The numeric rule is confirmed rather than assumed; no per-formula exception list is needed.
- **This sweep should run in CI**, not once. It is four formulas and 180 lines of output, and it is the only thing standing between a compiler or firmware change and a silently wrong player level.
- Everything here is the simulator. The formulas are pure arithmetic with no device dependency, so hardware divergence is unlikely — but "unlikely" is not "measured", and the sweep is cheap to re-run on a real watch.
