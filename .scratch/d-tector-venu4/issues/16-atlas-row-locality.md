# Atlas row locality and buffer budget

Type: grilling
Status: open
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
