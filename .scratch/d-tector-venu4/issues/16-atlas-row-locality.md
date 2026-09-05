# Atlas row locality and buffer budget

Type: grilling
Status: resolved
Blocked by: 06

## Question

Which sprites share an atlas row, and how many row buffers stay resident?

[Render pipeline prototype](./06-render-pipeline-prototype.md) established that blit cost tracks the *source buffer's* area: a 984×24 row costs 0.3 ms per sprite, the whole 984×960 atlas costs 6.8 ms. So sprites are drawn out of row buffers, each row is a `BufferedBitmap` transferred from the palette resource at 9 ms a fill, and rows are held in the 4 MB graphics pool — where 40 rows of `atlas_24x24` alone would take ~1.9 MB, and adding `atlas_32x32` reaches ~3.4 MB.

Row assignment therefore stops being arbitrary. Decide:

- **The locality rule.** Which sprites must share a row? Candidates: a Digimon's own frames (base, attack, crush, spirit, small, black — up to 6 cells); the sprite set of one app screen; the frames of one animation. Walk the apps and the animations to find what is actually co-resident.
- **Residency policy.** How many row buffers stay live at once, and what evicts one. A 9 ms fill is affordable at a screen transition and not affordable inside a battle animation, so the policy has to guarantee that every sprite a scene needs is resident before the scene starts.
- **Worst case.** Find the screen that touches the most distinct sprites — the Database browser paging through 593 entries is the obvious suspect, and the Battle screen the one that cannot afford a stall. Establish the maximum simultaneous rows each needs.
- **Row geometry.** 41 cells per row came from a square-ish atlas. A narrower atlas means smaller, cheaper row buffers but more of them; a wider one is the reverse. Pick the width against the locality rule rather than aesthetics.
- **Purge recovery.** Buffered bitmaps are **not** auto-restored when the graphics pool purges them. Decide how the game detects a purged row and refills it without a visible glitch.

The output changes the packer in [Sprite atlas layout and index](./05-sprite-atlas-layout.md): sprite ordering becomes locality-driven, and the generated `DIGIMON_CELLS` table changes with it.

## Answer

Probes: [`prototype/render/`](../prototype/render/), rebuilt three times and run on `venu445mm` in the simulator.

### Blit cost against source size

Ticket 06 showed cost tracks the source buffer's area. The curve, 32 blits at 10× from each source:

| Source buffer | Pixels | Per blit | Fill |
|---|---|---|---|
| 24 × 24 | 576 | **1,687 µs** | 14 ms |
| 240 × 24 | 5,760 | 406 µs | 8 ms |
| 492 × 24 | 11,808 | **312 µs** | 8 ms |
| 984 × 24 | 23,616 | **312 µs** | 8 ms |
| 984 × 48 | 47,232 | 468 µs | 10 ms |
| 492 × 96 | 47,232 | 531 µs | 10 ms |
| 240 × 240 | 57,600 | 750 µs | 10 ms |
| 984 × 96 | 94,464 | 906 µs | 14 ms |
| 984 × 192 | 188,928 | 2,062 µs | 19 ms |
| 984 × 384 | 377,856 | 2,843 µs | 23 ms |
| 984 × 960 | 944,640 | 6,781 µs | 48 ms |

Two things fall out. Cost is **flat at 312 µs** for sources between roughly 12,000 and 24,000 pixels and climbs steeply above that — so there is a plateau to sit on rather than a "smaller is better" gradient. And a *tiny* source is the worst case of all: a 24 × 24 buffer costs 1,687 µs per blit, five times a full row. Caching individual sprites in their own small buffers is the wrong shape.

### The graphics pool's real ceiling

Allocating row buffers until the pool refuses:

| Row width | Rows before failure | Total pixels |
|---|---|---|
| 576 × 24 | 60 | **829,440** |
| 288 × 24 | 120 | **829,440** |

Identical, so the ceiling is a fixed **pixel** budget independent of buffer shape: about **829,000 pixels** of `BufferedBitmap`, alongside the atlas resource itself. Overcommitting **throws** — `The requested memory could not be allocated from the graphics memory pool` — rather than silently purging, so the residency policy must cap itself and catch the exception.

Note this is well under the 4,194,304 bytes that `graphicsResourcePoolSize` advertises: buffered bitmaps evidently cost more than the 2 bytes per pixel the 16 bpp display suggests.

### Decisions

1. **Atlas width: 24 cells (576 px).** Blit cost is already at its 312 µs floor by 492 px wide, so a 24-cell atlas is exactly as fast as the 41-cell one from ticket 05 while its row buffer is 40% smaller — 13,824 pixels against 23,616. The digimon section becomes 70 rows.

2. **Group-aware packing: a digimon's frames never straddle a row.** The 1,446 digimon sprites form **603 groups** (base plus `_at`, `_cr`, `_sp`, `_sm`, `_bl`), averaging 2.4 cells and never exceeding 6:

   | Group size | 1 | 2 | 3 | 4 | 5 | 6 |
   |---|---|---|---|---|---|---|
   | Groups | 61 | 316 | 197 | 3 | 6 | 20 |

   Padding row ends to keep groups whole costs **22 wasted cells** — about 1.6 KB on a 118 KB atlas. Effectively free, and it means one digimon is always one row.

3. **Abilities and energies get their own contiguous rows.** An ability is shared across many digimon (193 abilities for 603 groups), so it cannot sit beside all of its users. Duplicating each digimon's ability cell into its group was considered and rejected: 603 extra cells is +36% atlas to save two row fills per battle.

4. **Residency: an LRU of 16 row buffers, strong references held.** 16 rows is 221,184 pixels — 27% of the measured budget, with room for the display list and anything else that wants the pool. Eviction is dropping the strong reference; the cap is enforced in code, and the allocation is wrapped in a `try` because overcommit throws.

5. **Purge recovery: assume the contents are gone.** The docs say a resource "could be temporarily purged when all strong references are destroyed", and Connect IQ has **no pixel-read API**, so whether a re-acquired buffer keeps its pixels cannot be observed — a probe confirmed only that `get()` still returns an object of the right dimensions. The safe rule follows from the docs rather than from a measurement: **hold a strong reference to every row you depend on, and treat any row whose strong reference was dropped as empty and refill it.** At 8 ms a fill this is cheap insurance.

### Worst cases

- **Battle** needs the two combatants' groups (2 rows), their two ability sprites (up to 2 rows) and an energy sprite (1 row) — **5 rows, about 40 ms of fills** on entering the screen, then nothing. Well inside a screen transition, nowhere near a frame.
- **Database browsing** pages through 593 entries. At 24 cells per row and 2.4 cells per group, a row holds about **10 digimon**, so sequential paging costs one 8 ms fill every ten entries. Jumping by page or by search will miss more often; the LRU of 16 covers back-and-forth browsing.
- **Status** shows the player character plus up to four D-Dock digimon: 5 groups, at most 5 rows.

### Feeds back into the packer

[Sprite atlas layout and index](./05-sprite-atlas-layout.md) packed by size class with an arbitrary square-ish grid. That changes: the 24 × 24 class becomes 24 cells wide with group-aware row packing, and the generated `DIGIMON_CELLS` table changes with it. The packer's round-trip verification is unaffected — it checks cells, not their arrangement.
