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

Row buffers are filled lazily and held in an LRU of 16, each holding a strong reference. Colours are baked into the atlas palette rather than tinted at draw time.

## Consequences

- 2,423 sprites cost 217 KB of `.prg` and 9 bytes of app heap; the pixels live in the graphics pool.
- About 30 sprites fit in a 50 ms frame, which is well beyond what any screen draws.
- Entering a Battle costs about five row fills, roughly 40 ms — a screen transition, not a frame.
- Group-aware packing wastes 22 cells, about 1.6 KB.
- The graphics pool holds about 829,000 pixels of buffered bitmap regardless of buffer shape, and **overcommitting throws** rather than purging, so the LRU cap is load-bearing.
- Buffered bitmaps are not restored after a purge and Connect IQ has no pixel-read API, so a row whose strong reference was dropped is treated as empty and refilled.
- `drawBitmap2` places the source rect at `(x, y) + T * (bitmapX, bitmapY)` when `:transform` is set, so the caller that owns the transform must pass `x - 10 * srcX`, `y - 10 * srcY`. Research 01 named the composition order "the single riskiest unverified assumption" in the plan; it was wrong in the worst way, because a cell 120 px into a row landed 1,200 px off-screen and the call drew **nothing at all** rather than drawing something misplaced.
- The `<bitmap>` resources must carry `dithering="none"` **and** an explicit two-colour `<palette>`. Without them the resource compiler quantises to 4 bpp and Floyd–Steinbergs the result, which dropped 10 of the 576 pixels of one 24 × 24 cell — isolated single ink pixels of a sprite's outline, invisible at a glance and fatal to the fidelity contract.
- The original's user-configurable `ConfigActiveColor`/`ConfigBackgroundColor` are not preserved by the baked palette. `:tintColor` exists and may restore them; it is untested on the row-buffer path.
