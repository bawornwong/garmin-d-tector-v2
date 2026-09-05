# Bitmap font rendering

Type: grilling
Status: open
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
