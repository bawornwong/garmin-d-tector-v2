# Bitmap font rendering

Type: grilling
Status: resolved
Blocked by: 05

## Question

How does the port draw text so that it matches the original glyph for glyph?

The original does not render a TTF at runtime. `Assets/Fonts/` holds three Unity custom fonts — `Small`, `Regular`, `Big` — with 38, 38 and 37 glyphs, each a UV rect into a 50×50 PNG (`font_small.png`, `font_regular.png`, `font_big.png`). Glyphs are roughly 5×7 pixels, cut from Consolas. Connect IQ's system fonts are a different typeface at a different pixel grid, so using them breaks the visual fidelity contract outright.

Decide:

- **Carrier** — glyphs packed into a size-class atlas alongside the sprites (they are tiny; ~113 cells), or a Connect IQ custom font resource (`.fnt`). The `.fnt` route gets `Dc.drawText` for free but must reproduce the exact bitmap; the atlas route means writing the text renderer but reuses everything the sprite path already does.
- **Metrics** — the `.fontsettings` carry `m_Tracking: 1`, `m_CharacterPadding: 1`, `m_LineSpacing` 144 for Small and Regular and 192 for Big, and `m_ConvertCase: 1` (forced uppercase). Establish what each means in source pixels and reproduce it. A one-pixel tracking error compounds across a line.
- **The three sizes** — Small and Regular share a line spacing but differ somewhere; find where. Big is a different scale. Are these three distinct glyph sets, or one set drawn at different scales?
- **Layout behaviour** — `TextBoxBuilder.cs` uses a `ContentSizeFitter` and exposes `Width` in canvas cells. Work out how the original wraps, truncates and centres text, and reproduce it.
- **Inversion** — `TextBoxBuilder.BaseInvertColors` swaps foreground and background for the text box. This must compose with whatever colour decision the render pipeline reaches.
- **Character set** — 37–38 glyphs is small. Enumerate exactly which characters exist, and decide what happens to a string containing anything else.

Verification follows the sprite path: round-trip every glyph against the source PNG, and render a known string in both the original and the port and diff it.

## Answer

Extractor: [`prototype/data/pack_fonts.py`](../prototype/data/pack_fonts.py).

### The three faces, measured

Unity's units divide by `PIXEL_SIZE` (24) to give game pixels:

| Face | Glyphs | Line spacing | Advances (px) | Glyph sizes |
|---|---|---|---|---|
| Big | 37 | 8 px | **6.0 only — monospaced** | 5×5, 5×7 |
| Regular | 38 | 6 px | 2, 3, 4, 5, 6 — **proportional** | 1×5, 3×5, 4×5, 5×5 |
| Small | 38 | 6 px | 2, 3, 4, 5, 6 — **proportional** | 1×5, 3×5, 4×5, 5×5 |

Small and Regular share their metric *ranges* but not their per-glyph values (Regular has 27 glyphs at 5 px, Small has 22), so they are genuinely different faces despite identical headers. Charset is `space` + `0-9` + `A-Z`, plus `!` on Regular and Small.

`m_ConvertCase: 1` forces uppercase. `m_Tracking: 1` and `m_CharacterPadding: 1` are the Unity defaults.

**Glyph art lives in the alpha channel** — all three sheets are solid white RGB — so the sprite packer's existing `alpha > 0 AND luma > 128` rule already covers fonts.

The layout is set by `TextBox.prefab`: `m_HorizontalOverflow: 1` (Overflow) and `m_VerticalOverflow: 0` (Truncate) — **the original never wraps text**. Long strings are handled by a marquee: `DatabaseApp.cs:252` builds the name box at `SetPosition(32, 0)`, off the right edge, and an `AnimateName` coroutine scrolls it in.

### Decisions

1. **Glyphs go in the sprite atlas, and the port draws text itself.** A Connect IQ custom font resource would hand over `dc.drawText`, but nothing guarantees it reproduces these bitmaps pixel-for-pixel, and per-glyph proportional advances may not survive the conversion. Drawing glyph by glyph reuses the whole existing pipeline.

   All 113 glyphs pack into **525 bytes at 1 bpp** (120 × 35). They are placed inside **one standard 576 × 24 atlas row** rather than a small buffer of their own — ticket 16 measured that sources below about 12,000 pixels get slower, and a dedicated 4,200-pixel glyph buffer would sit in that penalty zone. In a standard row they blit at the 312 µs plateau, so a 10-character string costs **3.1 ms**, comfortably inside a 50 ms frame.

2. **Advance is the per-glyph value ÷ 24, with nothing added.** `m_Tracking: 1` is a multiplier of 1.0 and `m_CharacterPadding: 1` applies when Unity generates the atlas, not when it lays out a line. **This is an assumption and must be measured** — a one-pixel error per character puts a 20-character name 20 px out, which is 62% of the screen's width.

3. **Characters the font lacks are skipped entirely — no glyph, no advance.** The data uses characters that exist in none of the three fonts:

   | Character | Occurrences | Where |
   |---|---|---|
   | `(` and `)` | 33 + 33 | **34 digimon names** — `agumon (primal)`, `rosemon (burst)`, `daemon (cloaked)` |
   | `_` | 133 | ability names, e.g. `flames_1` |
   | `=` | 1 | |

   Unity draws nothing for a glyph a custom font does not contain. Reproducing that is the fidelity-preserving choice; adding the missing glyphs would be an improvement to the original, which the standing rule forbids. Measured consequence:

   | Face | Input | Renders as | Width |
   |---|---|---|---|
   | Big | `agumon (primal)` | `AGUMON PRIMAL` | 78 px |
   | Big | `gallantmon (crimson)` | `GALLANTMON CRIMSON` | 108 px |
   | Regular | `agumon (primal)` | `AGUMON PRIMAL` | 64 px |

   Against a 32 px screen, so the marquee is not decoration — it is the only way most names are legible. **Still to confirm visually against the original build**: whether Unity truly draws nothing, or draws a blank box that consumes advance.

4. **`\n` breaks lines; nothing else does.** Literal strings in the source include `"GAME\nOVER"`, so the renderer honours explicit newlines at the face's line spacing (8 px for Big, 6 px for the others) and performs **no word wrapping at all**. Text is uppercased with `.toUpper()` before layout, per `ConvertCase: 1`.

5. **Text clips at the canvas, not at its own rect.** A text element keeps a rect for **alignment** — `DatabaseApp` uses `TextAnchor.UpperRight` to right-align stat numbers — but overflow spills past that rect and is clipped only by the 32 × 32 canvas. The marquee then needs no special mechanism: it is an ordinary animation moving x.

### Verification

**Shape**: every glyph was cut from its sheet by its UV rect, packed, unpacked and diffed. **113 / 113 identical.**

**Metrics** still need their own check: render a fixed string set and compare widths and glyph positions against values computed from the `.fontsettings`. The set must include at least one name containing parentheses, to pin the decision in point 3.

These are separate failure modes — a correct glyph at the wrong offset and a wrong glyph at the right offset both look like "the text is broken" — so both checks belong in CI beside the sprite round-trip.
