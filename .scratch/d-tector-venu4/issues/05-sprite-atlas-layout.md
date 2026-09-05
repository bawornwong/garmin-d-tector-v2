# Sprite atlas layout and index

Type: grilling
Status: resolved
Blocked by: 01

## Question

How are the 1,674 sprites laid out in a 1-bpp bitmap atlas, and how does the game address one cell at runtime?

[Connect IQ binary assets and blitting](./01-ciq-binary-assets-and-blitting.md) settled the carrier: not a byte blob (no binary resource type exists, and `jsonData` costs 5 bytes per number), but a **single 1-bpp `<bitmap>` atlas** blitted per-cell with `drawBitmap2` — measured at 119,904 bytes of `.prg` for 1,606 sprites in a 1008×936 atlas, living in the 4 MB graphics pool rather than the 768 KB heap. This ticket decides the layout on top of that.

Decide:

- **Atlas geometry** — cell grid versus packed rows. Sprites are mostly 24×24, with 31 at 32×32 and 20 at 14×16. A uniform 32×32 grid wastes ~40% of the area but makes addressing arithmetic; a packed layout needs an offset table. Given that the atlas lives in the graphics pool and not the heap, is the waste worth buying simpler addressing?
- **Atlas count** — one atlas for everything, or one per group (Digimon / Abilities / Maps / Energies)? The pool auto-purges and auto-restores static resources, so residency is managed for us; the question is load granularity and whether the atlas exceeds any per-resource dimension limit.
- **Addressing** — the source references sprites by name plus suffix (`agumon`, `agumon_at`, `agumon_cr`, `_sp`, `_bl`, `_sm`). There is no String→Symbol conversion in Monkey C, and Garmin says that is by design. So the runtime must reach a cell by **numeric index**. Decide how a Digimon plus a suffix resolves to a cell index — derived from `digimonDB.json`'s `number`/`order`, or from a build-generated table — and where that table lives.
- **The 8 multicolour sprites** — verified exceptions to 1-bit. Identify them and decide whether they degrade cleanly or need their own drawable.
- **Build pipeline** — the PNG → atlas packer is a build-time script (Python, Pillow) that emits both the atlas PNG and the index table. Where it lives, when it runs, and how its output is verified cell-by-cell against the source PNGs. A packing bug puts the wrong Digimon on screen, which is a content change.

The fidelity contract makes the index load-bearing.

## Answer

Prototype packer: [`prototype/pack_sprites.py`](../prototype/pack_sprites.py). Visual walkthrough: https://claude.ai/code/artifact/ab7f4f30-1a43-48c0-a45e-dbffeebb0c92

### Findings from the source

The inventory was larger than the charting estimate. Reading the Unity `.meta` files surfaced two families nobody had counted:

| Family | How the original addresses it | Sprites |
|---|---|---|
| Resources sprites | string path, loaded at runtime | 1,674 |
| Sheet sub-sprites | editor reference into 5 sliced sheets | 749 |
| Bitmap font glyphs | UV rects in three `.fontsettings` | 113 |
| **Total** | | **2,536** |

The five sheets in `Assets/Sprites/` are sliced on a 15×15 grid, 32×32 cells, 33 px pitch — `animations` 225, `characters` 225, `menus` 225, `energy` 20, `misc` 54 (mixed sizes: 30×5, 24×24, 8×8, 16×16). **Every rect is recoverable exactly from the `.meta`**, so the slicing never has to be guessed.

**The screen is grey-green, not black.** From `Preferences.cs`:

```csharp
ActiveColor     = Color.black              // #000000
BackgroundColor = new Color32(129,147,118) // #819376
```

Sprites are stored as white plus an alpha mask and tinted at draw time. The default pair is the reflective LCD of the physical device. The earlier working assumption of white-on-black was wrong; the user's photo of a real D-Tector confirmed it and the source gave the exact values.

### Decisions

1. **One atlas per size class.** A single uniform 32×32 grid addresses by pure arithmetic but pads every 24×24 sprite, costing **310 KB**. Tight packing with an offset table costs 217 KB but puts a lookup in front of every draw. Size classes give both — cells are uniform *within* an atlas, so addressing stays arithmetic, and nothing is padded.

   | Atlas | Sprites | Grid | Pixels | Bytes @ 1bpp |
   |---|---|---|---|---|
   | `atlas_24x24` | 1,633 | 41 × 40 | 984 × 960 | 118,080 |
   | `atlas_32x32` | 723 | 27 × 27 | 864 × 864 | 93,312 |
   | `atlas_14x16` | 21 | 5 × 5 | 70 × 80 | 700 |
   | `atlas_odd` | 46 | strip | 1011 × 82 | 10,362 |
   | **Four resources** | **2,423** | | | **222,454 (217 KB)** |

   Only `atlas_odd` carries an offset table.

2. **Sheets are re-sliced from their `.meta` rects** and packed into the same size-class atlases, not shipped whole. Shipping the five sheets as-is would cost 153 KB against 88 KB re-packed, and `misc` needs a rect table either way.

3. **Addressing is arithmetic, with no strings.** Monkey C has no String→Symbol conversion, so names disappear at build time. The packer emits `DIGIMON_CELLS[dex][action]` — 602 rows × 6 actions, `-1` where that action has no art. Sprite actions are sparse (602 base, 539 attack, 222 crush, 32 spirit, 31 black, 20 small), so a dense table costs a few KB of RAM and turns every lookup into an array index. **Row order is locked jointly with [Data pipeline: JSON to Connect IQ resources](./12-data-pipeline-json-to-resources.md)** — a one-row disagreement puts the wrong Digimon on screen for every entry.

4. **Threshold on luma > 128, not alpha.** The eight sprites flagged as multicolour turned out to be white plus values from `(1,1,1)` to `(13,13,13)` — black in all but name. Luma thresholding is lossless for them; alpha thresholding would have turned each into a solid block. Separately, `misc.png`'s 3,712 blue pixels fall **entirely outside every sliced rect** — the artist's guide layer, not content.

5. **Round-trip verification runs on every build.** The packer unpacks its own atlases and diffs every pixel against the source PNGs. Current result: **2,423 / 2,423 identical, zero mismatches.** A cell shifted by one puts the wrong Digimon on screen and nothing else would catch it.

### Consequences

- **Colour handling moves to [Render pipeline prototype](./06-render-pipeline-prototype.md)**: bake `#819376`/black into the atlas palette (exact, free, fixed) versus keep the atlas as a mask and tint at draw time (preserves the original's configurable `ConfigActiveColor`/`ConfigBackgroundColor`). Decide against what `drawBitmap2` actually supports on this device.
- **Fonts spin out** to [Bitmap font rendering](./15-bitmap-font-rendering.md).
- **Open**: the `energy` sheet holds 20 sub-sprites at 24×24 while `Resources/Sprites/Energies/` holds 16 files at the same size. Check which set the code draws before dropping either.
