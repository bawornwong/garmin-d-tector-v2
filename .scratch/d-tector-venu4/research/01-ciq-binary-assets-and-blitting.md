# Connect IQ binary assets and 1bpp blitting (`venu445mm`)

Research output for [issue 01](../issues/01-ciq-binary-assets-and-blitting.md). Target: Venu 4 45mm, Connect IQ 6.0.2, SDK 9.2.0.

## TL;DR

**Do not carry the sprites as a raw byte blob. Carry them as one 1-bpp bitmap atlas resource and blit sub-rectangles out of it.**

- There is **no binary/blob resource type** in Connect IQ. The resource compiler accepts `bitmap`, `font`, `string`, `jsonData`, `animation`, plus UI resources — nothing else (verified against `bin/resources.xsd`).
- A **string resource is hard-capped at 32,767 bytes** (verified in the compiler bytecode *and* by a build that fails). `jsonData` has **no hard cap** (only a warning above 8 KB), but its serialization costs **5 bytes per JSON `Number`** — 120 KB of bytes as a number array is 600 KB of PRG and roughly that again in heap. Fatal.
- The **right carrier is a `<bitmap>`**. Give it a 1-colour palette (+ transparency) and the compiler emits **exactly 1 bpp**. Measured: a 1008×936 atlas holding 1,606 sprites costs **119,904 bytes** in the `.prg` — within 2 KB of the theoretical 117,936.
- Bitmaps load into the **graphics pool (4,194,304 bytes on this device), not the 768 KB app heap**. A 120 KB atlas is ~3 % of the pool and ~0 heap.
- `Dc.drawBitmap2()` is **supported on Venu 4 45mm** and takes `:bitmapX/:bitmapY/:bitmapWidth/:bitmapHeight` (source rect = sprite-sheet cell) **plus** `:transform` (a `Graphics.AffineTransform`, so `setToScale(10,10)`) **plus** `:filterMode` defaulting to `FILTER_MODE_POINT` (nearest-neighbour — exactly the crisp integer scale the fidelity contract demands). This is a **single native call per sprite**. `Dc.drawScaledBitmap()` is also supported and is simpler, but scales the *whole* bitmap, so it cannot address an atlas cell.
- The 576-`fillRectangle` fallback is **not needed**. Keep it only as a contingency; forum data suggests it is roughly an order of magnitude away from the per-frame budget once several sprites are on screen.
- The "1,674 individual drawables" route **compiles and works** (I built it), but costs **387 KB of `.prg` vs 120 KB**, adds **~15 KB of permanently-resident `DATA`** for the `Rez.Drawables` table, and an array literal of all 1,674 `ResourceId`s adds **38 KB of CODE**. It is survivable, not preferable.
- **Not established from primary sources**: actual per-frame timings on hardware. Ticket 06 must measure.

---

## Method

Three evidence classes, in descending trust:

1. **Device API surface** — `~/Library/Application Support/Garmin/ConnectIQ/Devices/venu445mm/{compiler.json,simulator.json,venu445mm.api.debug.xml}`.
2. **SDK-local primary docs and compiler internals** — the API reference and Core Topics that ship in `connectiq-sdk-mac-9.2.0-2026-06-09-92a1605b2/doc`, and disassembly (`javap`) of `bin/monkeybrains.jar`.
3. **Empirical builds** — I generated a self-signed developer key and compiled six real apps for `-d venu445mm` in `/private/tmp/.../scratchpad/ciqtest`, then parsed the resulting `.prg` section table. Numbers below marked **[measured]** come from those builds. Forum posts are used only where nothing better exists, and are labelled as such.

---

## 1. Resource types: what can carry bulk data

### 1.1 The complete list of resource kinds

From `bin/resources.xsd` (the schema the resource compiler validates against), the resource element names are:

```
animation  bitmap  drawable  drawable-list  font  jsonData  layout  menu  menu2
checkbox-menu  action-menu  string  property  setting  settingConfig  complication
watchface-config  fitContributions  ...
```

**There is no `binary`, `blob`, `data`, or `bytes` resource.** Connect IQ has no equivalent of an Android raw asset. The candidates for bulk data are therefore `string`, `jsonData`, and `bitmap`/`font`.

### 1.2 `string` — hard 32,767-byte ceiling

`com.garmin.monkeybrains.asm.Stringdef.write()` encodes the value as UTF-8 and writes the length as a **16-bit short**:

```
11: arraylength
12: sipush        32767
15: if_icmple     29
18: new           AssemblerException   // STRING_SIZE_ERROR
```

and the static initialiser formats that constant into the message `"String exceeds size limit of %d bytes."`.

**[measured]** A `<string>` holding a 54,616-character base64 payload fails the build:

```
ERROR: venu445mm: Resource string with id 'Big' exceeds string size limit.
```

So 120 KB of base64 (163,840 chars) would need **at least 5 string resources**. Workable but ugly, and see §1.4 for why it is still the wrong shape.

### 1.3 `jsonData` — no hard cap, but a brutal per-element cost

Core Topics (`doc/docs/Core_Topics/Resources.html`) sells `jsonData` for exactly this use case:

> JSON data resources can store relatively large amounts of data in your app without having to keep it in memory at all times.

The compiler emits only a **warning** above 8 KB — `com.garmin.monkeybrains.resourcecompiler.json.JsonResourceData`:

```
89: sipush 8192
92: if_icmple 129
...  "The serialized form of the <jsonData> record " + id + " is large (> 8kb)."
```

**[measured]** built and inspected the `RESOURCES` section (`0xf00d600d`) of the `.prg`, baseline subtracted:

| `jsonData` record | Elements | PRG bytes | Per element |
|---|---|---|---|
| array of 0–255 `Number`s | 122,880 | 614,442 | **5.00 B** |
| array of 31-bit `Number`s | 30,720 | 153,642 | **5.00 B** |
| 7 base64 `String`s (163,840 chars total) | 7 | 163,948 | ~1 B/char + ~5 B/string |
| 1 base64 `String` (163,840 chars) | 1 | 163,884 | ~1 B/char |

Three things follow:

- A `Number` costs 5 bytes **regardless of magnitude**. Storing 122,880 raw bytes as a JSON number array is **600 KB of `.prg`** and, at runtime, an `Array` of 122,880 boxed values. (Travis.ConnectIQ, a long-standing forum regular — *not* Garmin staff — puts a Monkey C array element at 5 bytes, 8 worst case; that would be 600 KB–1 MB against a 768 KB heap.) **Ruled out.**
- Packing 4 bytes per `Number` cuts it to 30,720 elements ≈ 150 KB PRG and ~150–245 KB heap. Survivable, but it burns a fifth to a third of the heap permanently and you still have to unpack bytes in Monkey C.
- **`jsonData` strings are *not* subject to the 32,767-byte string-resource limit** — a single 163,840-char JSON string compiled fine. So `jsonData` → base64 string → `StringUtil.convertEncodedString(..., :toRepresentation => REPRESENTATION_BYTE_ARRAY)` → a 120 KB `ByteArray` is the best *blob* path if a blob is ever genuinely needed. `StringUtil` and `Lang.ByteArray` both exist on this device. Peak cost is String + ByteArray simultaneously (~284 KB) unless you decode chunk-by-chunk.

### 1.4 `bitmap` — the actual answer

Garmin's own bitmap FAQ (`doc/docs/Connect_IQ_FAQ/How_Do_I_Optimize_Bitmaps.html`) states the memory model outright:

> Connect IQ supports images of bit depth of 1 BPP, 2 BPP, 4 BPP, 8 BPP, and 16 BPP.

with a table giving a 100×100 image at 1 bpp as **1.22 KB** — i.e. cost is exactly `width × height × bpp / 8`. And:

> By setting the import palette, you can communicate the total number of colors the image should use. […] With the four colors set and transparency resource compiler creates a 4 bit image; with no transparency it will create a 2 bit image for a 50% memory savings.

The bit-depth rule is hard-coded in `BitmapProcessor.determineBpp(int numColors)`:

| Colours (incl. the implicit transparent entry) | bpp |
|---|---|
| ≤ 2 | **1** |
| ≤ 4 | 2 |
| ≤ 16 | 4 |
| ≤ 256 | 8 |
| ≤ 65536 | 16 |

So **one palette colour plus transparency = 2 entries = 1 bpp** — a monochrome sprite *with* an alpha mask, at one bit per pixel.

**[measured]** I built a 1008×936 atlas (42×39 grid of 24×24 cells, 1,606 of the project's real sprites) into a real `venu445mm` app. `.prg` deltas against a baseline build:

| `<bitmap>` declaration | `.prg` delta | Implied bpp |
|---|---|---|
| `<palette><color>FFFFFF</color></palette>` (transparency on) | **119,904 B** | **1** |
| `<palette disableTransparency="true">` black+white | **119,904 B** | **1** |
| no palette (`automaticPalette` default) | 471,856 B | 4 |
| 1-colour palette + `packingFormat="png"` | 244,400 B | — (png packing discards the reduction) |
| 1-colour palette + `compress="true"` | 122,544 B | 1 (+2.6 KB; compression *hurts* here) |

Theoretical 1 bpp for 943,488 px = 117,936 B. The 1,968-byte excess is header/row padding. **The atlas costs what the map's table says the packed blob costs — 120 KB — with none of the decode work.**

Two mandatory attributes: `dithering="none"` (otherwise Floyd–Steinberg speckles a 1-bit image) and an explicit `<palette>` (otherwise `automaticPalette` picks 4 bpp on this 16 bpp device). Do **not** set `packingFormat="png"`; it is both bigger here and has a [reported drawBitmap2 correctness bug](https://forums.garmin.com/developer/connect-iq/f/discussion/378901/does-the-fr955-properly-support-drawbitmap2-or-not).

### 1.5 Where a loaded resource lives — heap vs graphics pool

This is the fact that decides the whole ticket. Core Topics *Graphics*:

> Before API level 4.0.0, all resources loaded at runtime into the application heap. […] API level 4.0.0 introduced a new graphics pool that is separate from your application heap. When you load a bitmap or font at runtime, the resource will load into the graphics pool, and you will be returned a `Graphics.ResourceReference`. The graphics pool dynamically caches, unloads and reloads your resources behind the scenes based on available memory.

`venu445mm/simulator.json` gives this device's pool size:

```json
"graphicsResourcePoolSize": 4194304
```

**4 MB, separate from the 786,432-byte watchApp heap.** A 120 KB 1-bpp atlas is 2.9 % of it. Calling `ResourceReference.get()` (present on this device) pins it so the pool cannot purge it; static resources that *are* purged are transparently reloaded from the executable.

Contrast: a `jsonData` blob lands in the app heap and stays there.

**Total picture for the atlas route: ~120 KB of `.prg`, ~120 KB of graphics pool, ~9 bytes of app heap** (one `Rez.Drawables` table entry — **[measured]**, `DATA` grew 345 → 354 bytes).

---

## 2. Partial loading

**No. There is no slicing API.** `Application.loadResource(ResourceId)` / `WatchUi.loadResource()` are the only entry points; both take a whole resource id and return the whole materialised object. Nothing in `Toybox.Application`, `Toybox.WatchUi`, or `Lang.ResourceId` offers an offset/length read, and there is no file-system API for the `.prg`'s own contents.

The three ways to avoid materialising 120 KB at once:

1. **Split into N resources and load only what you need.** Works for `jsonData` and `bitmap` alike. Resources are reference-counted like ordinary objects, so dropping the reference frees them.
2. **Use a bitmap and let the graphics pool page it.** This is the documented mechanism for exactly this problem and is automatic — the pool purges and restores static resources behind your back. It is the only "partial loading" Connect IQ actually has.
3. **Decode a base64 `jsonData` chunk at a time** into a `ByteArray`, if a blob is unavoidable.

**Caveat worth carrying forward.** Repeated load/unload of large JSON resources has an open bug report — [*Loading/unloading large json resources leads to VM crash over time*](https://forums.garmin.com/developer/connect-iq/i/bug-reports/loading-unloading-large-json-resources-leads-to-vm-crash-over-time) — reproducible on watch and simulator, with the crash landing inside `Application.loadResource` while reported memory is well below the cap. Another reason to prefer bitmaps.

One cost you cannot avoid: forum consensus (flowstate, in [*Is there a better way to select resources?*](https://forums.garmin.com/developer/connect-iq/f/discussion/218088/is-there-a-better-way-to-select-resources)) is that *"the resource table is loaded into your app unless you call `loadResource()` at least once… and it has entries for ALL resources"*, measured at roughly 1 KB for a small app. My `.prg` section measurements are consistent with that and quantify it properly in §5.

---

## 3. Pixel-level drawing: what exists on `venu445mm`

Confirmed present in `venu445mm.api.debug.xml` as `dataEntry` classes under `Toybox_Graphics`:

`AffineTransform`, `BitmapReference`, `BitmapTexture`, `BoundingBox`, **`BufferedBitmap`**, **`BufferedBitmapReference`**, `Dc`, `FontReference`, `InvalidBitmapResourceException`, `InvalidPaletteException`, `OutOfGraphicsMemoryException`, `ResourceReference`, `VectorFont`.

`Graphics.createBufferedBitmap` is present as a `functionEntry` on the device. `WatchUi.Layer` and `WatchUi.AnimationLayer` also exist (relevant to ticket 06, out of scope here).

Every `Dc` method whose doc page carries a "Supported Devices" list was checked against the string `Venu® 4 45mm`. **All present:** `drawBitmap2` (4.2.1), `drawScaledBitmap` (4.0.0), `drawOffsetBitmap` (4.0.0), `setAntiAlias` (3.2.0), `setBlendMode`/`setFill`/`setStroke` (4.0.0), `drawAngledText`/`drawRadialText` (4.2.1). `drawBitmap`, `drawPoint`, `fillRectangle`, `setColor`, `setClip` are API 1.0.0 universals with no device gate.

**[measured]** an app calling `drawBitmap2` with `:transform`/`:filterMode`, `drawScaledBitmap`, `new Graphics.AffineTransform()`, and `StringUtil.convertEncodedString` compiles cleanly for `-d venu445mm`. `monkeyc` type-checks API availability per device, so a clean build is real evidence of presence.

Costs, by mechanism:

| Mechanism | Where it lives | Cost |
|---|---|---|
| `BitmapResource` from `loadResource` | graphics pool | `w × h × bpp / 8`; purgeable and auto-restored |
| `createBufferedBitmap({:width,:height,:palette,:colorDepth,:bitmapResource,:alphaBlending})` | graphics pool | same formula at the chosen `:colorDepth`; **purged buffers are NOT restored** — you must re-render |
| `BufferedBitmap.getDc()` | — | a full `Dc` with the same capabilities as the screen `Dc` |
| `Dc.drawPoint` / `fillRectangle` | — | VM-interpreted, one bytecode call each; the dominant cost is interpreter dispatch, not the pixels |

`createBufferedBitmap` caps `:palette` at 256 colours and accepts `:colorDepth` in bits/pixel, so a 320×320 1-bpp scratch buffer is 12.8 KB of pool — a viable option for compositing the game canvas once and blitting it, if ticket 06 wants it.

Watchdog: `simulator.json` gives `"watchdogCount": 240000` for this device. Monkey C aborts a callback that executes too long; the forum thread [*Techniques for faster pixel-level drawing?*](https://forums.garmin.com/developer/connect-iq/f/discussion/339514/techniques-for-faster-pixel-level-drawing/1645945) reports **~10,000 `dc.drawPoint` calls, or ~5,000 `setColor`+`drawPoint` pairs, before the watchdog trips**, and that generating pixels into a `BufferedBitmap` and issuing a single `drawBitmap2` handled a 49×49 block (2,401 pixels) comfortably. Treat those as order-of-magnitude, not spec.

---

## 4. 10× scaling

**Yes, there is a scaled blit, and it is a single native call.** Two of them, in fact.

### 4.1 `Dc.drawBitmap2` — the one to use

```
drawBitmap2(x, y, bitmap, {
    :bitmapX, :bitmapY, :bitmapWidth, :bitmapHeight,   // source rectangle
    :tintColor,                                        // recolour a grayscale asset
    :filterMode,                                       // default FILTER_MODE_POINT
    :transform                                         // Graphics.AffineTransform
})
```

The API reference defines `:bitmapX/:bitmapY/:bitmapWidth/:bitmapHeight` as *"the top left corner of the source bitmap area"* and its extent — i.e. a sprite-sheet cell — and `:transform` as *"Transformation to apply to the source image when drawing it to the output."* `:filterMode` *"Default is `FILTER_MODE_POINT`"*, the nearest-neighbour sampler; the alternative is `FILTER_MODE_BILINEAR`. Point filtering at integer scale is exactly the "integer scale, no blur" the fidelity contract asks for.

So one sprite at 10× is:

```monkeyc
var t = new Graphics.AffineTransform();
t.setToScale(10.0, 10.0);
dc.drawBitmap2(dstX, dstY, atlas, {
    :bitmapX => cellX, :bitmapY => cellY,
    :bitmapWidth => 24, :bitmapHeight => 24,
    :transform => t });
```

**Gotchas to design around** (from [*Bitmap Transformation*](https://forums.garmin.com/developer/connect-iq/f/discussion/336765/bitmap-transformation/1636756), forum, not Garmin staff):

- The transform origin is **(0,0) of the source bitmap**; `x,y` positions the transformed result.
- Composition is **applied in reverse of the order you write it**. `setToScale/setToRotation/...` overwrite the matrix; `scale/rotate/...` concatenate. For a pure uniform scale this is moot.
- Build one `AffineTransform` at init and reuse it — it is a scale-by-10 forever.
- Combining `:transform` with the source rect is the intended use per the docs, but **verify in the simulator on the first spike of ticket 06** that the source rect is honoured *before* the transform (i.e. that you get a 240×240 cell, not a scaled whole-atlas clip). I found no primary source stating the composition order, and no forum thread exercising both together. **This is the single riskiest unverified assumption in this document.**

### 4.2 `Dc.drawScaledBitmap` — the fallback

`drawScaledBitmap(x, y, width, height, bitmap)`, API 4.0.0, explicitly listed for *Venu® 4 45mm / D2™ Air X15*. Simpler and older, but it scales the **entire** bitmap — no source rect. It only works if each sprite is its own resource (§5), in which case `dc.drawScaledBitmap(x, y, 240, 240, sprite)` is the whole render call.

That gives a clean decision rule: **atlas ⇒ `drawBitmap2`; per-sprite drawables ⇒ `drawScaledBitmap`.** Both are one native call per sprite.

### 4.3 The 576-rectangle route

Drawing a 24×24 sprite as 576 `fillRectangle(10,10)` calls means 576 VM-interpreted calls per sprite, plus the bit-unpacking loop feeding them. Against the ~5,000–10,000-primitive watchdog envelope reported above, that is ~8–17 sprites per frame *before* any game logic, with no headroom. The original renders a 32×32 canvas that may hold several sprites plus UI. **Do not plan on this.** Keep it documented as a contingency only if the `:transform`+source-rect combination in §4.1 turns out broken on hardware.

Actual per-frame timings: **not established.** Neither Garmin's docs nor any forum post gives µs figures for `drawBitmap2`, and the simulator is not a timing oracle. **Ticket 06 must measure on hardware** — that is precisely what the render-pipeline prototype is for.

---

## 5. The 1,674-drawable alternative, measured

I built it. 1,674 real sprite PNGs, each its own `<bitmap>` with a 1-colour palette, compiled for `venu445mm`.

**It compiles.** No error, no warning, 4.4 seconds. I found **no documented or enforced limit** on drawable count, `.prg` size (device advertises `maxPrgFilespace` 67,108,864), or resource-symbol count. The compiler's only count limits are on menu items and complications. The debug-symbol table caps at 32,767 entries (`"Too many debug symbols in project."`). The forum claim of a "255 maximum JSON IDs" ([*How to store a database?*](https://forums.garmin.com/developer/connect-iq/f/discussion/303018/how-to-store-a-database/1463950)) is **unverified and I could find no such check in the compiler** — treat it as folklore unless someone reproduces it.

**[measured]** `.prg` section sizes, in bytes (sections identified by their magic in the PRG container):

| Build | DATA | CODE | RESOURCES | total `.prg` |
|---|---|---|---|---|
| baseline (launcher icon only) | 345 | 258 | 10,490 | 98,764 |
| **1 atlas bitmap** | **354** | 288 | **130,338** | **218,668** |
| 1,674 bitmaps, load one by literal symbol | **15,411** | 175 | **397,231** | 528,892 |
| 1,674 bitmaps + array literal of all 1,674 ids | 15,411 | **38,543** | 397,231 | 567,276 |

Reading:

- **`DATA` grows to 15,411 B** — 1,674 `Rez.Drawables` entries at ~9 bytes each — **whether or not you reference them**. `DATA` is app-heap-resident. That is **~2 % of the 768 KB budget spent permanently on a name table**, versus 9 bytes for the atlas.
- **`RESOURCES` is 387 KB vs 120 KB** — 231 bytes per 72-byte sprite. Per-bitmap headers, palettes, and row padding triple the payload. Still nowhere near the 64 MB filespace ceiling; the cost is install size and load churn, not a wall.
- **An array literal of all 1,674 `ResourceId`s costs 38 KB of `CODE`.** Code is paged (`codePageSize` 4096) and, on this 6.0.2 device, `(:extendedCode)` can push functions into a 16 MB paged code space — so this is not heap, but paging it in has a documented performance penalty.

### Can drawables be selected dynamically?

**Yes, by index into an array of symbols; no, by name computed at runtime.**

`Rez.Drawables.foo` is a `Lang.ResourceId` value and can be stored in an array: `[Rez.Drawables.s0000, Rez.Drawables.s0001, ...]`, indexed at runtime, and passed to `loadResource`. I compiled exactly this with 1,674 entries and it builds and type-checks.

What you cannot do is turn a `String` or `Number` into a `Symbol`/`ResourceId`. Travis.ConnectIQ, quoting the design intent in [*Is there a better way to select resources?*](https://forums.garmin.com/developer/connect-iq/f/discussion/218088/is-there-a-better-way-to-select-resources):

> The problem that you're running into is that you seem to want to be able to convert a Setting value (a String or Number) to a Symbol so that you can load the corresponding JSON resource. **We don't allow this, and it is by design.**

So the mapping from the game's Digimon id to a sprite must be a **compile-time-generated array**, and that array is the 38 KB of CODE above. Note also that a `Rez.Drawables` symbol id can change between builds — never persist one (this is the same warning that made `Symbol` an illegal Storage key in ticket 03).

### Verdict on the alternative

Not ruled out by any hard limit. Ruled out on merit: **3× the `.prg`, ~15 KB of permanent heap, 38 KB of code for the lookup table, and a generated resource XML with 1,674 entries** — in exchange for being able to use the simpler `drawScaledBitmap`. The atlas wins.

---

## 6. Recommendation

1. **Asset**: one (or a few, split by sprite group) `<bitmap>` atlas, 24×24 cells in a fixed grid, `dithering="none"`, `automaticPalette="false"`, `<palette><color>FFFFFF</color></palette>` (one colour + implicit transparency ⇒ 1 bpp). No `packingFormat`, no `compress`. **~120 KB of `.prg`, ~120 KB of graphics pool, ~0 heap.**
2. **Index**: sprite → `(cellX, cellY)`. That is two small integers, derivable arithmetically from a sequential sprite index — so the "index" can be a compile-time *ordering* rather than a stored table. This is ticket 05's problem; the constraint this ticket hands it is that the index maps to **atlas coordinates**, not byte offsets.
3. **Load**: `Application.loadResource(Rez.Drawables.Atlas)` once at app start; hold the reference (or `ResourceReference.get()`) for the app's life.
4. **Draw**: one `dc.drawBitmap2()` per sprite with the cell as the source rect and a shared `AffineTransform.setToScale(10,10)`; `FILTER_MODE_POINT` (the default) gives crisp integer scaling.
5. **Recolour** with `:tintColor` if the D-Tector's monochrome palette needs to change per screen — free, and it is why a 1-colour-plus-alpha atlas is better than a black-and-white opaque one.

### What ticket 06 must verify empirically

- **`:transform` composed with `:bitmapX/:bitmapY/:bitmapWidth/:bitmapHeight`** — does the source rect clip *before* the scale? (§4.1). If not, fall back to one `BufferedBitmap` per visible sprite, or to per-sprite drawables + `drawScaledBitmap`.
- **Per-frame cost** of N `drawBitmap2` calls at 10× on hardware, and the resulting frame rate.
- **Graphics-pool behaviour** — whether a 120 KB pinned atlas plus any `BufferedBitmap`s stays clear of `OutOfGraphicsMemoryException`.
- Whether transparency on a 16 bpp device really costs the second palette entry the way the FAQ describes for 16-colour/RGB222 devices (my `.prg` measurement says the emitted resource is 1 bpp either way, but *runtime* alpha handling on an RGB565 device is not documented).

---

## Reproduction

The empirical builds live in `/private/tmp/claude-502/.../scratchpad/ciqtest/` (throwaway; self-signed `developer_key.der` generated with `openssl genrsa` + `openssl pkcs8 -topk8 -outform DER -nocrypt`). Rebuild with:

```
monkeyc -f monkey.jungle -o out.prg -y developer_key.der -d venu445mm -w
```

`.prg` section sizes were read by walking the container's `(uint32 magic, uint32 length)` records; the ones that matter are `0xda7ababe` DATA, `0xc0debabe` CODE, `0xf00d600d` RESOURCES.

---

## Sources

### Local — device profile (`~/Library/Application Support/Garmin/ConnectIQ/Devices/venu445mm/`)

- `compiler.json` — `bitsPerPixel: 16`, `codePageSize: 4096`, `maxPrgFilespace: 67108864`, watchApp `memoryLimit: 786432`, `alphaBlendingSupport: true`, `enhancedGraphicSupport: true`, `imageFormats: [yuv, jpg, png]`
- `simulator.json` — `graphicsResourcePoolSize: 4194304`, `watchdogCount: 240000`, `appStorageCapacity: 10485760`
- `venu445mm.api.debug.xml` — presence of `Toybox_Graphics_{AffineTransform,BufferedBitmap,BufferedBitmapReference,BitmapReference,BitmapTexture,ResourceReference,OutOfGraphicsMemoryException,InvalidPaletteException}`, `Graphics.createBufferedBitmap`, `WatchUi.{Layer,AnimationLayer,BitmapResource}`, and symbols `drawBitmap2`, `drawScaledBitmap`, `setPalette`, `ByteArray`

### Local — SDK 9.2.0 (`~/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.2.0-2026-06-09-92a1605b2/`)

- `doc/Toybox/Graphics/Dc.html` — `drawBitmap2`, `drawScaledBitmap`, `drawBitmap` signatures and per-method Supported Devices lists
- `doc/Toybox/Graphics.html` — `createBufferedBitmap` options, `FilterMode`, `AlphaBlending`
- `doc/Toybox/Graphics/{AffineTransform,BufferedBitmap,BufferedBitmapReference,ResourceReference,BitmapTexture,BitmapReference}.html`
- `doc/Toybox/StringUtil.html` — `convertEncodedString`, `REPRESENTATION_*`
- `doc/docs/Core_Topics/Graphics.html` — graphics pool, buffered bitmaps, transformation, tinting
- `doc/docs/Core_Topics/Resources.html` — Rez module, `loadResource`, resource scopes, bitmap attributes, packing formats, `jsonData`
- `doc/docs/Connect_IQ_FAQ/How_Do_I_Optimize_Bitmaps.html` — bit-depth/memory table, palette and `disableTransparency` behaviour
- `doc/docs/Monkey_C/Annotations.html` — `(:extendedCode)`, 16 MB paged code space
- `bin/resources.xsd` — the complete set of resource element names
- `bin/monkeybrains.jar`, disassembled with `javap`:
  - `com.garmin.monkeybrains.asm.Stringdef` — 32,767-byte string limit
  - `com.garmin.monkeybrains.resourcecompiler.json.JsonResourceData` — 8 KB warning threshold
  - `com.garmin.monkeybrains.resourcecompiler.drawables.bitmaps.bitmapprocessing.BitmapProcessor.determineBpp` — colour-count → bpp table
  - `com.garmin.monkeybrains.asm.ResourceSymbolTable` — 32,767 debug-symbol limit
- `bin/monkeyc` — the six empirical builds described above

### Local — project

- `.scratch/d-tector-venu4/map.md` — sprite inventory (1,674 PNGs, 119.5 KB packed 1 bpp)
- `/private/tmp/.../scratchpad/dtector/Assets/Resources/Sprites/` — the source PNGs used to build the test atlas

### Web (secondary; forum posts are developer opinion unless attributed to Garmin)

- https://developer.garmin.com/connect-iq/core-topics/graphics/
- https://developer.garmin.com/connect-iq/connect-iq-faq/how-do-i-optimize-bitmaps/
- https://developer.garmin.com/connect-iq/api-docs/Toybox/Graphics/BufferedBitmap.html
- https://forums.garmin.com/developer/connect-iq/f/discussion/339514/techniques-for-faster-pixel-level-drawing/1645945 — watchdog envelope for `drawPoint`, BufferedBitmap + single `drawBitmap2`
- https://forums.garmin.com/developer/connect-iq/f/discussion/336765/bitmap-transformation/1636756 — `AffineTransform` origin and reverse composition order
- https://forums.garmin.com/developer/connect-iq/f/discussion/358907/dc-drawbitmap2 — working `:bitmapX/:bitmapY/:bitmapWidth/:bitmapHeight` example
- https://forums.garmin.com/developer/connect-iq/f/discussion/218088/is-there-a-better-way-to-select-resources — no String→Symbol conversion "by design"; resource-table RAM overhead
- https://forums.garmin.com/developer/connect-iq/f/discussion/303018/how-to-store-a-database/1463950 — unverified "255 JSON IDs" claim
- https://forums.garmin.com/developer/connect-iq/f/discussion/193873/how-to-load-rez-resource-dynamically — arrays of `Rez.Drawables` symbols
- https://forums.garmin.com/developer/connect-iq/i/bug-reports/loading-unloading-large-json-resources-leads-to-vm-crash-over-time — VM crash on repeated large-JSON load/unload
- https://forums.garmin.com/developer/connect-iq/f/discussion/378901/does-the-fr955-properly-support-drawbitmap2-or-not — `packingFormat="png"` breaks `drawBitmap2`
- https://forums.garmin.com/developer/connect-iq/b/news-announcements/posts/a-whole-new-world-of-graphics-with-connect-iq-4 — graphics pool announcement
