# Render pipeline prototype

Type: prototype
Status: open
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
