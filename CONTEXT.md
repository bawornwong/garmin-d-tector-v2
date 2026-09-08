# Context

Shared vocabulary for the D-Tector v2 → Garmin Venu 4 port. Terms only — no implementation detail, no decisions. Decisions live in [docs/adr](docs/adr/), the build plan in [SPEC.md](SPEC.md), and the reasoning behind both in the wayfinder map at `.scratch/d-tector-venu4/map.md`.

## The game

**D-Tector** — the physical Digimon Frontier toy this game recreates. Not the source of truth for the port; see **the source**.

**The source** — [kaisadilla/D-Tector-v2](https://github.com/kaisadilla/D-Tector-v2), a Unity 2019.3 C# project. The **fidelity anchor**: where the toy and the source disagree, the source wins.

**Canvas** — the game's screen, 32 × 32 game pixels. Everything the game draws is positioned in these units, never in device pixels.

**Game pixel** — one unit of the canvas. `Constants.PIXEL_SIZE` is 24, which is how many Unity units one game pixel spans; on the watch it is 10 device pixels.

**App** — one of the game's screens: Camp, Database, Map, Status, CodeInput. Distinct from the Connect IQ watchApp, which contains all of them.

**Minigame** — Battle, DigiHunter, Finder, JackpotBox, Maze, SpeedRunner.

**Sprite action** — a variant of a Digimon's artwork, named by the file suffix the source uses: base (no suffix), `_at` attack, `_cr` crush, `_sp` spirit, `_sm` small, `_bl` black.

**Group** — one Digimon's sprite actions taken together, 1 to 6 cells. The unit of atlas locality: a group never straddles an atlas row.

**Digimon index** — a Digimon's position in `digimonDB.json`. The single identifier shared by the sprite table, the packed database and the save format. Nothing addresses a Digimon by name at runtime.

**Spirit power**, **D-Dock**, **distance**, **area**, **world** — game concepts carried over unchanged from the source; see the source for their rules.

## The port

**Watch pixel** — one device pixel on the 454 × 454 display. Ten to a game pixel.

**Atlas** — a 1-bit bitmap resource holding many sprites in a fixed grid. Split by size class, 24 cells wide.

**Cell** — one sprite's slot in an atlas, addressed by a numeric index.

**Row** — one row of atlas cells, 24 cells wide. The unit of transfer and of residency.

**Row buffer** — a `BufferedBitmap` holding one row, transferred from the atlas resource at runtime. The only thing sprites are ever blitted *from*; the atlas resource itself cannot be a blit source.

**Graphics pool** — the memory buffered bitmaps live in, separate from the app's heap.

**Display list** — the retained set of on-screen elements (sprites, text boxes, rectangles, containers) that animations mutate and the renderer draws each frame. Mirrors the source's `ScreenElement` hierarchy.

**Routine** — one of the source's coroutines, translated into a resumable state machine.

**Fiber** — an independently running routine with its own call stack. `StartCoroutine` creates one; `StopCoroutine` drops it.

**Tick** — one 50 ms timer firing. The display's clock, not the animation's.

**Scheduled time** — an animation event's time on the *original's* millisecond timeline. Preserved exactly; several scheduled events may land in one tick.

**Slot** — one saved game, 963 packed bytes under one Storage key.

**Golden trace** — the event-and-time log produced by running the original's own code outside Unity. The reference every ported animation is diffed against.

**Face** — one of the three bitmap fonts: Big, Regular, Small.

**Glyph** — one character's bitmap in a face, with its own advance.

**Note** — one step of a sound: a frequency in hertz and a duration in milliseconds, the pair a `ToneProfile` takes. A note of frequency 0 is a **rest** — silence of that duration, played by waiting rather than by asking for a tone.

**Chunk** — the run of notes handed to `playTone` in one call, about 220 ms of them. The tone generator plays a chunk autonomously, so notes shorter than a tick keep their timing; the runner only schedules chunk boundaries. A note longer than a chunk is split across chunks at the same frequency, and a rest ends one.

**Sound name** — the string a call site passes to `playSound`, such as `levelUp`. The identifier shared by the port's call sites, the extractor's table and the golden trace, the way a Digimon index is shared elsewhere. Never a filename.

**Vibration event** — a sound name that also vibrates. Vibration has no call sites of its own: it rides on the sound already marking that moment, and a sound absent from the table is silent to the wrist.

**Duty cycle** — a vibration's strength, 0–100. Distinct from its length; some Garmin devices ignore it and vibrate at one strength regardless.
