# Connect IQ binary assets and 1bpp blitting

Type: research
Status: resolved
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

Ticket [Sprite atlas layout and index](./05-sprite-atlas-layout.md) and [Render pipeline prototype](./06-render-pipeline-prototype.md) both wait on this.

## Context

Findings land at `.scratch/d-tector-venu4/research/01-ciq-binary-assets-and-blitting.md`.

## Answer

Full findings: [research/01-ciq-binary-assets-and-blitting.md](../research/01-ciq-binary-assets-and-blitting.md)

**Headline: don't ship a byte blob. Ship a 1-bpp bitmap atlas and blit cells out of it with `drawBitmap2`.**

Numbers below are measured — a self-signed dev key plus six real `venu445mm` apps compiled in the scratchpad, with the `.prg` section table parsed for sizes.

1. **Resource types.** There is **no binary/blob resource type** — verified against the SDK's own `bin/resources.xsd`. String resources are hard-capped at **32,767 bytes** (found in `Stringdef.write()` bytecode, confirmed by a build that errors). `jsonData` has no hard cap (8 KB is only a warning) but costs **5 bytes per JSON `Number` regardless of magnitude** — 120 KB expressed as a number array becomes ~600 KB of `.prg` and ~600 KB–1 MB of heap. Fatal. The right carrier is `<bitmap>`: `BitmapProcessor.determineBpp` yields 1 bpp for ≤2 palette entries, so *one colour plus transparency* packs to 1 bpp with an alpha mask. **Measured: a 1008×936 atlas holding 1,606 real sprites = 119,904 bytes of `.prg`** — within 2 KB of theoretical. And bitmaps load into the **4,194,304-byte graphics pool**, *not* the 768 KB heap; heap cost is 9 bytes.

2. **Partial loading.** No slicing API — `loadResource` always materialises the whole resource. The only genuine partial mechanism is the graphics pool, which purges and auto-restores static resources on its own. Otherwise, split into N resources. There is also an open Garmin bug report of repeated large-JSON load/unload crashing the VM — another mark against the blob route.

3. **Pixel-level drawing.** `AffineTransform`, `BufferedBitmap`, `BufferedBitmapReference`, `BitmapTexture`, `ResourceReference` and `createBufferedBitmap` are all confirmed present in `venu445mm.api.debug.xml`. Every gated `Dc` method was checked against its "Supported Devices" list — `drawBitmap2`, `drawScaledBitmap`, `drawOffsetBitmap`, `setBlendMode`, `setFill`/`setStroke` all list Venu 4 45mm. Buffered bitmaps cost `w×h×bpp/8` in the pool but are **not** restored if purged.

4. **10× scaling is a single native call.** `drawBitmap2` takes `:bitmapX`/`:bitmapY`/`:bitmapWidth`/`:bitmapHeight` (the atlas cell) plus `:transform` (`AffineTransform.setToScale(10,10)`) plus `:filterMode`, which defaults to `FILTER_MODE_POINT` — nearest-neighbour, exactly the crisp integer scale the fidelity contract wants. `drawScaledBitmap` also works but scales the whole bitmap, so it suits only per-sprite drawables. The 576-`fillRectangle` route is unnecessary: against the ~5,000–10,000-primitive watchdog envelope reported on the forum it buys roughly 8–17 sprites per frame with no headroom.

5. **The 1,674-drawable alternative compiles** — it was built. No documented or enforced limit on drawable count or `.prg` size exists, and the forum's "255 JSON IDs" claim is folklore not found in the compiler. But measured against the atlas: **387 KB of RESOURCES vs 120 KB**, plus **15,411 bytes of permanently-resident `DATA`** for the `Rez.Drawables` table (present whether referenced or not), plus **38 KB of CODE** for an array literal of all 1,674 ids. Dynamic selection works by indexing an array of symbols; there is no String→Symbol conversion, and Garmin's stated position is "we don't allow this, and it is by design."

**Risk to settle before the render pipeline commits**: no primary source confirms that `:transform` composes correctly *with* the source rect — whether you get a scaled 240×240 cell or a scaled whole-atlas clip. That is the single riskiest assumption. Per-frame timings are likewise unmeasurable from docs and need the simulator or hardware.
