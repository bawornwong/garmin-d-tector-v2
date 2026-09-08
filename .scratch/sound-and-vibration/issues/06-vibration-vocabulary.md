# The vibration vocabulary

Type: prototype
Status: open
Blocked by: 01

## Question

What does each vibrating event actually feel like?

Unlike the sounds, this has **no source to diff against** — the original is a phone game with no haptics at all, so every profile here is designed, not reproduced. That makes it a taste question settled on the wrist, and the only ticket on this map with no golden reference.

The curated list, already settled:

| Event | Should feel like |
|---|---|
| Encounter, regular | ? |
| Encounter, boss | ? — must be distinguishable from the regular one without looking |
| Evolution (regular, armor, spirit, ancient) | ? — one profile or four? |
| Level up | ? |
| Reward / unlock | ? |
| Damage / loss | ? |
| Digistorm | ? |
| Jackpot win | ? |

Never vibrates: any button, menu scrolling, map walking.

Build a probe that fires candidate `VibeProfile`s on demand so they can be felt back to back and compared, rather than judged one at a time from memory. Land the chosen profiles as a small table, and record *why* each is what it is — a future reader cannot re-derive taste from the code.

The open sub-questions: does an evolution get one profile or one per tier; is boss-versus-regular carried by length, intensity, or pattern; and is `digistorm` (89 seconds of it) a single hit at the start or something sustained.

## Context

Blocked by [Probe tone and vibration on the watch](./01-probe-tone-and-vibration-on-hardware.md), which establishes the duty-cycle and duration range that is actually distinguishable on this hardware — the space this ticket designs inside.
