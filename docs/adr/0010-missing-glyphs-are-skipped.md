# 10. Characters the fonts lack are skipped, not added

Date: 2026-09-06

## Status

Accepted

## Context

The game draws text with three bitmap faces cut from Consolas: Big (37 glyphs, monospaced), Regular and Small (38 glyphs, proportional). The charset is `space`, `0-9`, `A-Z`, plus `!` on two faces.

The game's own data uses characters none of them contain:

| Character | Occurrences | Where |
|---|---|---|
| `(` and `)` | 33 + 33 | **34 Digimon names** — `agumon (primal)`, `rosemon (burst)` |
| `_` | 133 | ability names, e.g. `flames_1` |
| `=` | 1 | |

Unity draws nothing for a glyph a custom font does not define. So in the original, `agumon (primal)` appears as `AGUMON PRIMAL`.

## Decision

The port does the same: a character with no glyph is **skipped entirely — no draw, no advance**. The missing glyphs are not added.

## Consequences

- 34 Digimon names render without their parentheses, exactly as in the original.
- Adding `(`, `)` and `_` would be an improvement to the original, which [ADR 2](0002-literal-translation-over-idiom.md) forbids.
- Anyone reading the rendered names will think this is a bug. It is not, and this ADR is the reason it will not be "fixed".
- Still to confirm against a running original: whether Unity draws nothing at all, or a blank box that consumes advance.
