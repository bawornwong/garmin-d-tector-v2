# Connect IQ memory and timing budget

Type: research
Status: resolved
Blocked by: —

## Question

What are the real resource ceilings for a `venu445mm` watchApp, and what frame rate can it sustain?

Answer all of:

1. **The 768 KB limit** — what exactly counts against `memoryLimit`: compiled code, loaded resources, live objects, all of it? How is it measured, and what tooling reports it (the simulator's memory viewer, `monkeyc` build output)?
2. **Code size** — is there a separate ceiling on compiled code independent of the memory limit? What does 12,000 LOC of ported logic plausibly cost? What is `codePageSize: 4096` actually constraining?
3. **Timers** — `Timer.Timer` minimum interval and actual resolution. Can a 30 fps or 60 fps update loop be driven from a timer, or is the practical ceiling lower?
4. **Redraw model** — `WatchUi.requestUpdate` and `View.onUpdate`: is the whole screen redrawn every frame, is there partial-update or clipping, and what does a full 454×454 redraw cost?
5. **AMOLED constraints** — does Venu 4 impose burn-in protection, forced dimming, or a foreground-app timeout that would interrupt a long play session?

Prefer primary sources: Connect IQ API docs, the SDK's own device files, Garmin developer forum posts from Garmin staff.

Tickets [Render pipeline prototype](./06-render-pipeline-prototype.md), [Animation VM instruction set](./07-animation-vm-instruction-set.md) and [C# to Monkey C port rules](./11-port-rules-csharp-to-monkeyc.md) wait on this.

## Context

Findings land at `.scratch/d-tector-venu4/research/04-ciq-memory-and-timing-budget.md`.

## Answer

Full findings: [research/04-ciq-memory-and-timing-budget.md](../research/04-ciq-memory-and-timing-budget.md)

Several numbers below are **measured**, not inferred — real apps built against `venu445mm` with SDK 9.2.0 and `monkeyc --build-stats`.

1. **What counts against 786,432 B**: the whole compiled `.prg` — bytecode, data, and compiled-in resources — charged up front and enforced **at build time**. The real error, triggered: `PRG generated exceeds the memory limit of app type 'watch-app' for device id 'venu445mm': 1197785 bytes used out of 786432 available bytes.` Whatever is left over is runtime heap. **Two exemptions matter**: runtime-loaded bitmaps, fonts and `BufferedBitmap`s live in a **separate 4 MB graphics pool** (`graphicsResourcePoolSize: 4194304`, found in `simulator.json` — not in `compiler.json`, not on the public device page), and `Storage` has its own 10 MB quota. **Trap**: debug builds are ~2.7× fatter than release (867,276 vs 318,236 bytes from identical source) — and the simulator runs debug. Tooling: `--build-stats`, the simulator's File → View Memory (peak), `System.getSystemStats()`, on-device `CIQ_LOG.txt`, and the profiler.

2. **Code size — the decisive finding.** There is no separate code ceiling, but **`(:extendedCode)`** (API 5.1.0) moves annotated code into a paged 16 MB extended space that is **exempt from the limit check**. Proven both ways: ~69k LOC unannotated → rejected at 1,197,785 B; the same source annotated → **1,222,812 B, BUILD SUCCESSFUL**. `codePageSize: 4096` is that space's page granularity (measured 1,132,772 B → 276 pages). Measured density on synthetic ported-logic-shaped code: **≈16.5 bytes of bytecode per source line**, so **12,000 LOC ≈ 200 KB ≈ 27% of the budget** even without the exemption. Recommendation: put `Logic/` behind `(:extendedCode)`, keep the render loop and the animation-VM interpreter out of it (Garmin's own docs warn of a page-in penalty). Cost is build time: 5.7 s → 26.8 s.

3. **Timers**: the documented default is a **50 ms minimum interval and 3 concurrent timers**, host-dependent. The per-device values for `venu445mm` are **not published anywhere** — checked `compiler.json`, `simulator.json`, and the Device Reference. 50 ms is a hard **20 fps ceiling**; 30 fps and 60 fps are simply not expressible. There is no vsync (per the Monkey Motion reference), and Garmin's own video tooling targets 1–10 fps. Separately, `watchdogCount: 240000` (undocumented, from `simulator.json`) is the real per-frame budget, measured in VM bytecodes.

4. **Redraw is full-screen, every frame.** `onPartialUpdate` is watch-face-and-MIP-only, so it is unavailable here, and the `Dc` is not guaranteed to preserve the previous frame. `Dc.setClip` is the only lever — and the 320×320 canvas is exactly 50% of the panel's pixels. The absolute cost of a 454×454 redraw is **undocumented and must be measured**; the findings bracket it with Garmin's own figures (700 ms worst case for a complex screen; 8–84 ms full-screen frame decode on older hardware) and give a measurement recipe.

5. **AMOLED**: the 10%-pixel burn-in budget applies to **always-on watch faces only** and does not constrain a foreground watchApp. What does bite: the Venu 4 manual states the display "turns off after the selected timeout", an app cannot override it, and `Attention.backlight` throws `BacklightOnTooLongException` past ~1 minute *and* suppresses wake-on-gesture. Good news for session length — per the UX guidelines an app launched from the activity list "will run until the user explicitly backs out", so there is **no inactivity timeout** (unlike the glance and widget paths). Therefore: don't ship a glance, tell the player to lengthen Display Timeout, and make a blanked screen recoverable.

Six open items needing hardware or a running simulator are listed at the end of the findings document.

**Consequences for the map:**
- **20 fps is a standing constraint.** [Render pipeline prototype](./06-render-pipeline-prototype.md) and [Animation VM instruction set](./07-animation-vm-instruction-set.md) must both assume a 50 ms tick. The original is a Unity game running at 60 fps; whether its animations read correctly at 20 fps is now a fidelity question, not just a performance one.
- **The 4 MB graphics pool changes the asset picture** — runtime `BufferedBitmap`s do not count against the 768 KB. Feeds [Connect IQ binary assets and blitting](./01-ciq-binary-assets-and-blitting.md) and [Sprite blob format and index](./05-sprite-blob-format.md).
- **`(:extendedCode)` makes 12k LOC comfortable**, removing the main feasibility doubt behind [C# to Monkey C port rules](./11-port-rules-csharp-to-monkeyc.md).
