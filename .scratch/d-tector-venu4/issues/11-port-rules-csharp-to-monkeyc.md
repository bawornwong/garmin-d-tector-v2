# C# to Monkey C port rules

Type: grilling
Status: open
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
