# Input abstraction layer

Type: grilling
Status: open
Blocked by: 02

## Question

What is the input abstraction the game logic sees, and how is it wired to the SDK simulator's keyboard for the first build?

Physical hardware mapping is deliberately deferred. The logic layer must be written against an abstraction now, so that a later hardware decision changes one adapter and nothing else.

Decide:

- **The abstract vocabulary** — the source exposes A, B, Left, Right, each with press/hold/release, plus shake. Is that vocabulary preserved exactly, or narrowed to what the platform can actually deliver?
- **The adapter seam** — where the boundary sits between the Connect IQ delegate and the game logic, so that swapping the simulator-keyboard adapter for a hardware adapter touches nothing else.
- **Simulator mapping** — the concrete key-to-input table for development, drawn from the research findings.
- **Hold semantics** — the source distinguishes press, hold, and release. If Connect IQ cannot express one of them, decide the substitute now and record it as a known interaction deviation (permitted by the fidelity contract, which covers content and visuals only).
- **Shake** — whether shake is wired at all in the first build, or stubbed behind the abstraction.
