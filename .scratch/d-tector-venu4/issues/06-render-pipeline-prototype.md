# Render pipeline prototype

Type: prototype
Status: open
Blocked by: 01, 04, 05

## Question

Can a 32×32 game canvas at 10× scale be drawn from packed 1bpp data on `venu445mm` at a playable frame rate?

Build a throwaway Connect IQ app that:

- draws the 320×320 canvas centred in the 454×454 round display
- unpacks and blits several 24×24 sprites from a packed 1bpp blob at 10× scale, at arbitrary canvas positions
- animates at least one sprite moving across the canvas
- reports achieved frame rate and peak memory in the simulator

Decide from what it shows:

- **Scaling technique** — scaled `drawBitmap`, an offscreen `BufferedBitmap` blitted with a transform, or 576 `fillRectangle` calls per sprite. Which is fast enough.
- **Redraw strategy** — full-canvas redraw every frame versus dirty-rectangle tracking.
- **Frame budget** — the frame rate the animation VM and the minigames can assume.
- **Colour** — the source is white-on-black 1-bit. Confirm what that should look like on an AMOLED panel and whether the original's configurable active colour (`config_active_color` in `SavedGame.cs`) is preserved.

If the frame rate is not playable, that invalidates the animation approach and reopens the blob format ticket.
