# Sprite atlas layout and index

Type: grilling
Status: open
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
