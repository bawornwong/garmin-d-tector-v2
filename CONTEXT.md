# Context

Shared vocabulary for the D-Tector v2 → Garmin Venu 4 port. The current build, setup, and feature status are in [README.md](README.md). The [ADRs](docs/adr/) preserve the history of implementation decisions.

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

**Slot** — the one saved game under the `slot0` Storage key. Save version 3 includes a watch-step header; see [watch-step-sync-design.md](docs/watch-step-sync-design.md).

**Golden trace** — the event-and-time log produced by running the original's own code outside Unity. The reference every ported animation is diffed against.

**Face** — one of the three bitmap fonts: Big, Regular, Small.

**Glyph** — one character's bitmap in a face, with its own advance.

**Note** — one extracted source-sound step: a frequency in hertz and a duration in milliseconds. A note of frequency 0 is a **rest**. These notes are retained for source comparison and simulator debug playback; the Venu 4 release uses Garmin's prerecorded tones.

**Chunk** — a group of extracted notes handed to `playTone` during simulator debug playback. The Venu 4 release does not play these custom tone profiles.

**Sound name** — the string a call site passes to `playSound`, such as `levelUp`. The identifier shared by the port's call sites, the extractor's table and the golden trace, the way a Digimon index is shared elsewhere. Never a filename.

**Vibration event** — a named gameplay sound with an associated vibration cue. Menu input and event prompts also have their own vibration cues.

**Duty cycle** — a vibration's strength, 0–100. Distinct from its length; some Garmin devices ignore it and vibrate at one strength regardless.
