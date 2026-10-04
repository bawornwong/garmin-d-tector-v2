# 3. Sprites ship as 1-bit atlases and blit from row buffers

Date: 2026-09-06

## Status

Accepted

## Context

The game has 1,674 sprites in `Assets/Resources` plus 749 more sliced out of five Unity sprite sheets. All of them are 1 bit deep — verified across every file: white where drawn, transparent elsewhere, with eight files carrying near-black values that threshold identically.

Connect IQ has **no binary resource type**, and a `jsonData` resource costs a measured 5.06 bytes per number, so a packed byte blob cannot be carried that way. `<bitmap>` resources reach 1 bpp when the palette has two entries.

Probing `drawBitmap2` on the device produced the decisive constraint: it **rejects a palette source outright** — `Exception: Source must not use a color palette` — not merely in combination with `:transform`. A 1-bpp bitmap resource is palettised by definition, so cells cannot be blitted out of it at all.

The classic `drawBitmap` *does* accept a palette source, and `drawBitmap2` accepts a `BufferedBitmap`. Blit cost then turned out to track the **source buffer's area**, not the output size: 312 µs per sprite from a 984 × 24 row against 6,781 µs from a whole-atlas buffer, with the cost flat between roughly 12,000 and 24,000 source pixels and *worse* below that — a 24 × 24 source costs 1,687 µs.

## Decision

Sprites ship as **1-bit `<bitmap>` atlas resources split by size class**, 24 cells wide, with a Digimon's group never straddling a row. At runtime each row is transferred into its own `BufferedBitmap` **row buffer** with the classic `drawBitmap`, and sprites are drawn from that row with `drawBitmap2` plus a source rect, `AffineTransform.setToScale(10, 10)` and `FILTER_MODE_POINT`, with the destination pre-compensated for the transform (see Consequences).

Row buffers are filled lazily and held in an LRU of 16, each holding a strong reference.

**Art is stored as white ink on a transparent field, and the colour is chosen at draw time** with `drawBitmap2`'s `:tintColor`. The tint is a **multiply**, measured: an opaque `#819376` pixel tinted `#FF0000` came back `#810000`, and a black pixel tinted anything stayed black. White ink is therefore the only storage colour that can become *any* ink colour, and it is what makes the three things below reachable at all.

## Consequences

- 2,423 sprites cost 217 KB of `.prg` and 9 bytes of app heap; the pixels live in the graphics pool.
- About 30 sprites fit in a 50 ms frame, which is well beyond what any screen draws.
- Entering a Battle costs about five row fills, roughly 40 ms — a screen transition, not a frame.
- Group-aware packing wastes 22 cells, about 1.6 KB.
- The graphics pool holds about 829,000 pixels of buffered bitmap regardless of buffer shape, and **overcommitting throws** rather than purging, so the LRU cap is load-bearing.
- Buffered bitmaps are not restored after a purge and Connect IQ has no pixel-read API, so a row whose strong reference was dropped is treated as empty and refilled.
- `drawBitmap2` places the source rect at `(x, y) + T * (bitmapX, bitmapY)` when `:transform` is set, so the caller that owns the transform must pass `x - 10 * srcX`, `y - 10 * srcY`. Research 01 named the composition order "the single riskiest unverified assumption" in the plan; it was wrong in the worst way, because a cell 120 px into a row landed 1,200 px off-screen and the call drew **nothing at all** rather than drawing something misplaced.
- The `<bitmap>` resources must carry `dithering="none"` **and** an explicit `<palette>` — now a single `FFFFFF` entry, with the field left to the PNG's `tRNS` so it stays transparent. Without them the resource compiler quantises to 4 bpp and Floyd–Steinbergs the result, which dropped 10 of the 576 pixels of one 24 × 24 cell — isolated single ink pixels of a sprite's outline, invisible at a glance and fatal to the fidelity contract.
- Sprites **composite** over what is beneath them, as the Unity original's transparent-backed `Image` components do. A baked two-colour atlas instead stamped a rectangle of screen colour over the background, which would have been wrong wherever the game overlaps sprites — every attack over a Digimon, every Digimon over map art.
- `InvertColors`, which the source uses for menu highlights and every stat sign, is a different tint rather than a second set of assets. It is unreachable from black ink, since black multiplied by anything is black.
- The renderer can tint the ink and fill the field independently. The watch's
  Config menu currently exposes the pixel grid, sound, vibration and reset;
  it does not expose the original's colour controls.
- A `BufferedBitmap` created **with** a `:palette` is itself palettised, so `drawBitmap2` refuses it as a source with the same `Source must not use a color palette`. Row buffers must be created with no palette option — which is also what preserves the atlas's alpha through the copy.
- Alpha atlases are *smaller* in the `.prg`, not larger: the debug build fell from 652,140 to 424,684 bytes when the baked field became transparency.
- Verified end to end on the device: `tools/verify_render.py` reads a captured frame back and matches all 576 pixels of a 24 × 24 cell against the atlas, both drawn normally and drawn inverted (LCD ink on a black box, which also proves the field composites).
