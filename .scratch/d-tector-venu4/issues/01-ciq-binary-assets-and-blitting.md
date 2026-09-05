# Connect IQ binary assets and 1bpp blitting

Type: research
Status: claimed
Blocked by: —

## Question

Can a Connect IQ 6.0.2 watchApp hold a ~120 KB packed 1-bit sprite blob as a single resource, and draw a 24×24 sprite from it at 10× scale, fast enough for gameplay?

Answer all of:

1. **Resource types** — what resource kinds can carry arbitrary binary or bulk data (`Rez.JsonData`, string resources, `Rez.Drawables`, anything else)? Size ceilings per resource and in total? How is a resource loaded and how much RAM does the loaded form cost versus the on-disk form?
2. **Partial loading** — can a resource be read in slices, or does `loadResource` always materialise the whole thing in RAM? A 120 KB blob resident against a 768 KB budget is affordable but not free; establish whether it must be.
3. **Pixel-level drawing** — the API for building an image from raw pixel data at runtime: `Graphics.createBufferedBitmap`, `BufferedBitmap`, `Dc.setColor`/`drawPoint`/`fillRectangle`, `Graphics.BufferedBitmapReference`. What exists in CIQ 6.0.2 on `venu445mm`, and what does each cost?
4. **10× scaling** — is there a scaled blit (`drawBitmap2` with a scale/transform, or an affine transform), or must scaling be done by drawing 576 filled 10×10 rectangles? Measure or cite the cost of each.
5. **Alternative** — how bad is the "1,674 individual PNG drawables" route really? Are there documented limits on drawable count, symbol table size, or `.prg` size that rule it out? Can drawables be selected dynamically at runtime (an array of `Rez.Drawables` symbols) or only by literal symbol?

Prefer primary sources: the Connect IQ API docs, the SDK's own `venu445mm.api.debug.xml`, Garmin developer forum posts from Garmin staff. The SDK is installed at `~/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.2.0-2026-06-09-92a1605b2`.

Ticket [Sprite blob format and index](./05-sprite-blob-format.md) and [Render pipeline prototype](./06-render-pipeline-prototype.md) both wait on this.

## Context

Findings land at `.scratch/d-tector-venu4/research/01-ciq-binary-assets-and-blitting.md`.
