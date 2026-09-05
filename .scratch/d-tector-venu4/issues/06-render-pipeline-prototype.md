# Render pipeline prototype

Type: prototype
Status: resolved
Blocked by: 01, 04, 05

## Question

Can a 32×32 game canvas at 10× scale be drawn from a 1-bpp atlas on `venu445mm` at 20 fps?

Research settled the mechanism and the ceiling. `drawBitmap2` takes a source rect (`:bitmapX`/`:bitmapY`/`:bitmapWidth`/`:bitmapHeight`) plus `:transform` (`AffineTransform.setToScale(10,10)`) with `:filterMode` defaulting to `FILTER_MODE_POINT` — nearest-neighbour, the crisp integer scale the fidelity contract wants. The timer floor is 50 ms, so **20 fps is the ceiling**, redraw is full-screen every frame, and `Dc.setClip` is the only lever.

**Settle the riskiest assumption first**: no primary source confirms that `:transform` composes correctly *with* the source rect — whether a scaled 240×240 cell comes out, or a scaled clip of the whole atlas. If it does not compose, the atlas approach needs rework and [Sprite atlas layout and index](./05-sprite-atlas-layout.md) reopens.

Build a throwaway Connect IQ app that:

- draws the 320×320 canvas centred in the 454×454 round display
- blits several 24×24 cells out of the 1-bpp atlas at 10× scale, at arbitrary canvas positions
- animates at least one sprite moving across the canvas on a 50 ms timer
- reports achieved frame rate and peak memory in the simulator, in **release** as well as debug (debug builds measure ~2.7× fatter)

Decide from what it shows:

- **Does `:transform` compose with the source rect?** Everything else waits on this.
- **How many sprites fit in a frame** at 20 fps, against the `watchdogCount: 240000` bytecode budget. This is the number the animation VM and the minigames must live within.
- **Redraw strategy** — full-canvas redraw every frame versus `setClip` on a dirty region.
- **Colour** — the source is white-on-black 1-bit. Confirm how that should look on AMOLED, and whether the original's configurable active colour (`config_active_color` in `SavedGame.cs`) survives a 1-bpp atlas (it should: the atlas carries shape, the draw call carries colour).

## Answer

Probe app: [`prototype/render/`](../prototype/render/) — built with SDK 9.2.0 against `venu445mm` and run in the simulator. **Every number below is from the simulator, not hardware.** Relative costs are what matter; absolute timings need a real watch.

### The assumption failed

`drawBitmap2` **rejects a palette source outright** — not merely in combination with `:transform`:

```
Exception: Source must not use a color palette
  - drawCell() at RenderProbeView.mc:72
```

A 1-bpp bitmap resource *is* palettised, so the entire "blit cells straight out of the atlas resource" plan is dead. Probed systematically:

| Path | Result |
|---|---|
| `drawBitmap2(paletteAtlas, srcRect)` | **rejected** — palette source |
| `drawBitmap2(paletteAtlas, srcRect, :tintColor)` | **rejected** — palette source |
| `drawBitmap2(paletteAtlas, srcRect)` into a BufferedBitmap | **rejected** — palette source |
| `drawBitmap(paletteAtlas)` (classic) | OK |
| `drawScaledBitmap(paletteAtlas)` (classic) | OK |
| `createBufferedBitmap` with `:palette` | creates OK, but **rejected as a `drawBitmap2` source** |
| `drawBitmap2(bufferedBitmap, srcRect, :transform)` | **OK** |
| `drawScaledBitmap(bufferedBitmap)` | OK |

So the atlas ships as a palette resource (cheap on disk) and must be **transferred into a non-palette `BufferedBitmap` at runtime** before any cell can be addressed.

### Blit cost tracks source area, not output size

Composing a 24×24 cell at 1:1 and blitting the same cell scaled to 240×240 cost **the same**, so this is not a fill-rate limit. What moves the number is how big the *source* buffer is:

| Blit source | 32 sprites at 10× | Per sprite |
|---|---|---|
| Row buffer, 984×24 | **9–10 ms** | **0.3 ms** |
| Whole-atlas buffer, 984×960 | 219 ms | 6.8 ms |
| Cell buffer, 24×24, drawn whole and scaled | 43 ms | 1.35 ms |

A single big `BufferedBitmap` holding the whole atlas is ~23× slower per blit than a row of the same atlas. Release build (`-r`, 140,684 bytes vs 223,356 debug) changed the sizes but not the timings.

Other measurements: filling one 984×24 row buffer from the palette resource costs **9 ms**; refilling a 24×24 cell buffer by drawing the whole atlas at a negative offset costs **7–8 ms**; the present stage — one 32×32 buffer scaled 10× to the screen — is **3 ms and constant**. App memory held at **12,024 / 781,888** throughout, confirming that buffers and bitmap resources live in the graphics pool, not the app heap.

### Decisions

1. **The atlas ships as a 1-bpp palette bitmap resource.** Measured cost in the `.prg`: **122,816 bytes** for `atlas_24x24` (984×960), identical across three PNG encodings (P-mode with `transparency`, RGBA white-on-transparent, and mode-1) — so the compiler reaches 1 bpp regardless, and the encoding choice is free.

2. **Row buffers are the blit source.** At load, each atlas row is transferred into its own `BufferedBitmap` (984×24) with the classic `drawBitmap`. Per frame, sprites are drawn with `drawBitmap2` from the row buffer using `:bitmapX/:bitmapY/:bitmapWidth/:bitmapHeight` plus `:transform` at `FILTER_MODE_POINT`. At 0.3 ms per sprite, ~30 sprites fit in a 50 ms frame with room for the background fill.

3. **No 32×32 compose stage.** Drawing cells directly to the screen at 10× costs the same as composing at 1:1 and scaling once, so the extra buffer buys nothing.

4. **Row buffers are filled lazily with an LRU**, not all at once: 40 rows for `atlas_24x24` alone would take ~1.9 MB of the 4 MB graphics pool, and adding `atlas_32x32` would take it to ~3.4 MB. A fill costs 9 ms, which is affordable on a screen transition but not mid-animation.

5. **Consequence for the packer**: row assignment is now performance-relevant. Sprites that appear together — a Digimon's base, attack and crush frames; the sprites of one app's screen — should land in the same row so a scene needs few resident buffers. This reopens ordering as a joint concern with [Sprite atlas layout and index](./05-sprite-atlas-layout.md); see [Atlas row locality and buffer budget](./16-atlas-row-locality.md).

6. **Colour: bake, don't tint.** The atlas palette carries transparent-plus-ink, the canvas is filled `#819376`, and the sprite draws in the ink colour. `:tintColor` was rejected on the palette path; **it has not been tested on the row-buffer path**, so preserving the original's configurable `ConfigActiveColor`/`ConfigBackgroundColor` remains unproven. Baking the default pair is what this prototype demonstrates working.

### Still unmeasured

- Everything above is simulator timing. Hardware may be faster or slower by a large factor.
- `:tintColor` from a `BufferedBitmap` source.
- Whether a row buffer survives a graphics-pool purge, and what a purge costs mid-game — research noted buffered bitmaps are **not** auto-restored.
- Full-screen background fill cost on the real panel.
