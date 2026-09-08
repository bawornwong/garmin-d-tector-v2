# The vibration vocabulary

Type: prototype
Status: open
Blocked by: 01

## Question

What does each vibrating event actually feel like?

Unlike the sounds, this has **no source to diff against** — the original is a phone game with no haptics at all, so every profile here is designed, not reproduced. That makes it a taste question settled on the wrist, and the only ticket on this map with no golden reference.

Never vibrates: any button, menu scrolling, map walking.

Build a probe that fires candidate `VibeProfile`s on demand so they can be felt back to back and compared, rather than judged one at a time from memory. Land the chosen profiles as a small table, and record *why* each is what it is — a future reader cannot re-derive taste from the code.

## A starting proposal, to react to rather than start from

These are **drafted, not decided** — a wrist is the only instrument that can settle them. They exist so the session with the watch in hand starts by feeling eight candidates and adjusting, instead of designing from a blank page. Durations are matched to each event's real sound length, now that the extractor has produced them.

`VibeProfile(dutyCycle 0-100, length ms)`, max **8 per `vibrate()` call** (ticket 02).

| Event | Sound is | Proposed profile | Why |
|---|---|---|---|
| Encounter, regular | 2.33 s | `[(50, 150)]` | one plain knock — something is here |
| Encounter, boss | 5.04 s | `[(80,150),(0,80),(80,150),(0,80),(80,250)]` | same gesture, three beats and harder: recognisable as "encounter" but unmistakably worse news, without looking |
| Evolution, regular | 5.07 s | `[(40,100),(0,60),(60,100),(0,60),(85,300)]` | a rising three-step: the shape of the animation itself |
| Evolution, spirit / ancient | 21.1 s / 18.0 s | the same rise, then `[(100,500)]` at the transformation | one vocabulary for all four tiers, with the long two earning a payoff hit — answers the ticket's "one profile or four" as *one, with a tail* |
| Level up | 2.22 s | `[(60,120),(0,80),(60,120)]` | a light double-tap, clearly not an encounter |
| Reward / unlock | 4.99–8.28 s | `[(50,200)]` | one soft, longer press — pleasant, not urgent |
| Damage / loss | 4.94–5.58 s | `[(100,400)]` | a single hard hit; the only profile that should feel unpleasant |
| Digistorm | 89.5 s | `[(70,200),(0,150),(70,200)]` **once, at the start** | 89 seconds of sustained buzzing would be intolerable and would drain the battery; mark the onset and then leave the player alone |
| Jackpot win | — | `[(60,100),(0,60),(60,100),(0,60),(60,100),(0,60),(90,350)]` | the longest, most celebratory pattern in the set; it is the rarest event in the game |

Sub-questions this proposal takes a position on, all still open to the wrist:
- **One evolution profile, not four** — tier is already carried by how long the animation runs.
- **Boss vs regular is pattern + intensity**, not length alone; length alone is hard to judge without a reference to compare against.
- **Digistorm marks its onset only.**

What still needs feeling: whether `dutyCycle` gradation is even perceptible on this watch (ticket 02 found Garmin documents Forerunners as ignoring it — unconfirmed either way for Venu 4), and whether 150 ms reads as a distinct knock or as a buzz.

## Context

Blocked by [Probe tone and vibration on the watch](./01-probe-tone-and-vibration-on-hardware.md), which establishes the duty-cycle and duration range that is actually distinguishable on this hardware — the space this ticket designs inside.
