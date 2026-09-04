# Sprite blob format and index

Type: grilling
Status: open
Blocked by: 01

## Question

How are the 1,674 sprites packed into a single binary asset, and how does the game address one at runtime?

Decide:

- **Blob layout** — header, index table, packed 1bpp payload. Fixed-stride (every sprite padded to 32×32 = 128 bytes, ~209 KB total) versus variable-stride with per-entry offset+dimensions (~120 KB plus index). Row padding: byte-aligned rows, or a flat bit stream?
- **Addressing** — a Digimon sprite is referenced in the source by name plus suffix (`agumon`, `agumon_at`, `agumon_cr`, `_sp`, `_bl`, `_sm`). Does the runtime look up by string name, by numeric id derived from `digimonDB.json`'s `number`/`order`, or by a generated symbol table? String keys in a 1,674-entry map cost RAM; numeric indices cost a build-time mapping.
- **Grouping** — one blob for everything, or separate blobs per group (Digimon / Abilities / Maps / Energies) so only what is in use is resident?
- **The 8 multicolour sprites** — verified exceptions to 1-bit. Identify them, decide whether they degrade to 1-bit cleanly or need a separate path.
- **Build pipeline** — the PNG → blob converter is a build-time script (Python, using Pillow). Where it lives, when it runs, and how its output is verified against the source PNGs so a packing bug cannot silently corrupt a sprite.

The fidelity contract makes this load-bearing: a wrong index means the wrong Digimon on screen, which is a content change.
