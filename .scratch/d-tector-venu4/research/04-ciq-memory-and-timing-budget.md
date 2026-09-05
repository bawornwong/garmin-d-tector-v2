# Connect IQ memory and timing budget — `venu445mm`

Research for [ticket 04](../issues/04-ciq-memory-and-timing-budget.md). Target: Venu 4 45mm, Connect IQ 6.0.2, SDK 9.2.0.

Everything below is either (a) read out of the installed SDK / device files, (b) measured by actually
building against `venu445mm` on this machine, or (c) quoted from Garmin primary docs / forum staff.
Where a number is undocumented and only knowable empirically, it says so and gives the measurement recipe.

---

## TL;DR

| Question | Answer |
|---|---|
| 1. What counts against 768 KB | The **entire compiled `.prg`** (bytecode + data + all compiled-in resources) is charged up front and enforced *by the compiler*; whatever is left is the runtime heap for live objects. Bitmaps/fonts/BufferedBitmaps loaded at runtime go to a **separate 4 MB graphics pool**. |
| 2. Code ceiling | No separate ceiling — code shares the 768 KB. **But `(:extendedCode)` moves code into a paged 16 MB extended code space that is exempt from the check** (measured: a 1,222,812-byte PRG builds; the same code without the annotation errors at 1,197,785). `codePageSize: 4096` is the page granularity of that space. 12,000 LOC ≈ **200 KB** of code by measurement. |
| 3. Timers | `Timer.Timer` minimum is **50 ms by default** (host-dependent, undocumented per-device) → **20 fps hard ceiling**. 30/60 fps is not reachable from a Timer. Watchdog budget is **240,000 VM instructions** per return-to-system. |
| 4. Redraw | **Full-screen redraw every frame.** `onPartialUpdate` is watch-face-only and MIP-only — unavailable here. `Dc.setClip` limits the pixels touched and is the only partial-update lever. Absolute cost of a 454×454 redraw is undocumented; must be measured. |
| 5. AMOLED | No forced dimming or burn-in pixel budget for a *foreground app* (those rules are watch-face/always-on only). But **the display turns off after the user's Timeout setting**, the app cannot override it, and `Attention.backlight` throws `BacklightOnTooLongException` if held on past ~1 minute. An app launched from the activity list has **no inactivity timeout**. |

---

## 1. The 768 KB limit

### What the number is

`~/Library/Application Support/Garmin/ConnectIQ/Devices/venu445mm/compiler.json`:

```json
"appTypes": [
  { "memoryLimit": 786432, "type": "watchApp" },
  { "memoryLimit": 131072, "type": "watchFace" },
  { "memoryLimit":  65536, "type": "glance" },
  ...
],
"codePageSize": 4096,
"maxPrgFilespace": 67108864,
"bitsPerPixel": 16
```

`~/Library/Application Support/Garmin/ConnectIQ/Devices/venu445mm/simulator.json` adds three
numbers that are **not** in `compiler.json` and are not in the public device-reference page:

```json
"appStorageCapacity":     10485760,   // 10 MB  — Application.Storage
"graphicsResourcePoolSize": 4194304,  //  4 MB  — graphics pool
"watchdogCount":            240000,   //         — VM instructions per callback
"screenProtectionSupport":  true
```

### What counts against it

**The compiled PRG counts, and the compiler enforces it.** Measured on this machine — a build that
overshoots is rejected at build time, not at run time:

```
ERROR: PRG generated exceeds the memory limit of app type 'watch-app' for device id
'venu445mm': 1197785 bytes used out of 786432 available bytes.
```

That matches the SDK 9.2.0 release note "Improve error message when the PRG size exceeds the memory
limit to include the available number of bytes" (`doc/docs/Readme/History.html`).

So the budget decomposes as:

```
786,432 = PRG size (bytecode + data + compiled-in resources, minus extended code pages)
        + runtime heap (live objects, stack, call frames)
```

Garmin's own wording: the heap "is used to hold your code, data, stack and runtime objects"
(*Graphics* core topic, "Graphics Pool" section).

### What does **not** count against it

- **Runtime-loaded bitmaps and fonts.** Since API 4.0.0 these load into the graphics pool, not the
  heap: "API level 4.0.0 introduced a new graphics pool that is separate from your application heap.
  When you load a bitmap or font at runtime, the resource will load into the graphics pool, and you
  will be returned a `Graphics.ResourceReference`." (*Graphics* core topic.) On `venu445mm` that pool is
  **4,194,304 bytes**. `Graphics.BufferedBitmap` objects also live there (via `createBufferedBitmap`).
  The pool "dynamically caches, unloads and reloads your resources behind the scenes based on
  available memory" — and a purged `BufferedBitmap` is **not** restored; you must re-render it.
- **`Application.Storage`** — separate 10 MB quota (`appStorageCapacity`).
- **Extended code space** — see §2.
- **The `.prg` file on flash** — `maxPrgFilespace` is 64 MB, three orders of magnitude looser.

### Debug builds are much fatter than release builds — this is a trap

Same source, same device, `-O 2`, only `-r` (strip debug info) differs:

| Build | Data | Code | Total PRG |
|---|---|---|---|
| debug (17,219 LOC synthetic) | 19,252 | 284,389 | **867,276** |
| release (same source) | 19,252 | 284,389 | **318,236** |
| debug (trivial app) | 333 | 155 | **98,540** |
| release (trivial app) | 333 | 155 | **15,084** |

Debug symbol overhead is ~2.7× the code+data here. The simulator runs the **debug** build, so a port
that is comfortable in release can still hit the ceiling in the simulator. Budget against release,
but expect to need `(:extendedCode)` earlier than you'd think just to keep debugging possible.

### Tooling that reports it

1. **`monkeyc --build-stats 0`** (also `1`; on SDK 9.2.0 both print the same block). Real output:
   ```
   Build Stats:
     Device: venu445mm
     Data:
       Foreground: 19252 bytes
     Code:
       Foreground: 284389 bytes
     Extended Code:
       Page Size: 4096 bytes
       Number of Pages: 0
       Total Size: 0 bytes
     Total PRG Size: 318236 bytes
   ```
   This is the *only* pre-run number, and it is exactly what the limit check uses.
2. **Simulator → File → View Memory.** Reports peak usage. Garmin's developer blog: "peak memory
   usage is visible in the simulator when you select File→View memory"; exceeding it means the app is
   killed by the system.
3. **`System.getSystemStats()`** → `totalMemory`, `usedMemory`, `freeMemory` (bytes). Call it from
   inside the app to log a real on-device figure.
4. **On device**: `GARMIN/Logs/CIQ_LOG.txt` records out-of-memory terminations.
5. **Simulator → File → View Profiler**, or `monkeyc -k` + sideload → `GARMIN/APPS/LOGS/<app>.PRF`
   loaded back into the simulator's profiler. Reports per-function Total/Actual/Average time in µs and
   call counts (*Profiling Applications* core topic).

Note the graphics pool has its own failure mode: SDK release notes record "Update graphics pool memory
allocations to throw an exception if the allocation fails due to being out of shared memory" — pool
exhaustion throws, it does not silently degrade.

---

## 2. Code size, and what `codePageSize: 4096` constrains

### There is no separate code ceiling — until you use `(:extendedCode)`

Everything is one PRG measured against `memoryLimit`. The escape hatch is the `(:extendedCode)`
annotation, API level 5.1.0 (`doc/docs/Monkey_C/Annotations.html`, verbatim):

> `:extendedCode` (API Level 5.1.0) — Code in extended code space is paged in during runtime on
> demand. For supported devices, this provides **16 megabytes of code space** beyond what is loaded
> into the heap. When building for supported products, the compiler will move those functions into
> extended code space. Code in extended code space is paged in memory using a "most recently used"
> strategy, but **there can be a performance penalty if code must be paged in. Code that is
> performance-dependent should be kept out of extended code space** to avoid the additional
> performance hit.

`codePageSize: 4096` is the granularity of that paging: extended code is chopped into 4 KB pages,
loaded and evicted MRU. Measured — 1,132,772 bytes of extended code became **276 pages**
(1,132,772 / 276 = 4,104 B/page).

**`venu445mm` supports it, and extended code is exempt from the 768 KB check.** Proven by building
the identical source twice:

| Variant | Fg data | Fg code | Extended | Total PRG | Result |
|---|---|---|---|---|---|
| ~69k LOC, no annotation | — | — | 0 | 1,197,785 | **rejected** (exceeds 786,432) |
| ~69k LOC, `(:extendedCode)` on every class | 60,694 | 18,839 | 1,132,772 (276 pages) | **1,222,812** | **BUILD SUCCESSFUL** |

A larger PRG built where a smaller one failed. The limit check therefore looks at
foreground code+data+resources only.

The SDK ships a working sample at `samples/ExtendedCodeSpace/`, which toggles the feature through the
jungle file with `base.excludeAnnotations = extendedCode` / `notExtendedCode`.

### What 12,000 LOC of ported logic plausibly costs

Measured directly. I generated a synthetic Monkey C workload shaped like ported game logic
(55 classes × 18 methods each: typed `Number` args, arithmetic, `%`, branching, array member access,
`for` loops over an instance array, string and array members), kept live by a driver that
instantiates every class so nothing is optimised away, and built it release-mode `-O 2` for
`venu445mm`:

| | Lines | Code section | Data section | Release PRG | Δ over baseline |
|---|---|---|---|---|---|
| trivial app | ~20 | 155 | 333 | 15,084 | — |
| synthetic logic | 17,219 | 284,389 | 19,252 | 318,236 | 303,152 |

- **≈ 16.5 bytes of bytecode per source line** (284,389 / 17,219)
- **≈ 17.6 bytes of PRG per source line** including data and constant pool

Extrapolating to the port's ~12,000 LOC of `Logic/`: **≈ 198 KB of code + ~13 KB of data ≈ 210 KB**,
about **27% of the 768 KB budget**, before any resources, before the presentation layer, and before
runtime heap.

Treat that as a central estimate with wide error bars:
- **Downward pressure**: real ported code is less arithmetic-dense than the synthetic workload;
  `-O z` (optimize code space) exists and was not used here; SDK release notes record "Add new opcodes
  to help reduce code space" and "Place constant array and dictionary definitions into the data space
  to reduce code space".
- **Upward pressure**: `Animations.cs` is 2,902 LOC of 60 coroutines with 535 `yield return`s. Any
  hand-rolled state-machine or VM expansion of those inflates line count well past 1:1. Long string
  literals and large constant tables land in data, not code.

**Practical rule for the port**: put `Logic/` (battle math, evolution, database access, the animation
VM's *program data*) behind `(:extendedCode)`, and keep the render loop, the frame timer callback,
`onUpdate`, the sprite blitter, and the animation VM *interpreter* out of it. That is exactly the
split Garmin's own annotation doc recommends.

Cost of the annotation: build time. Measured 5.7 s → 26.8 s for the 17k-LOC set, and 198 s for the
69k-LOC set. Expect slow iteration.

---

## 3. Timers and achievable frame rate

### The documented floor

`Toybox.Timer.Timer` (`doc/Toybox/Timer/Timer.html`), verbatim:

> The number of available timers (**default 3**) and the minimum time value (**default 50 ms**)
> depends on the host system. An error will occur if too many timers are set.

and

> If a repeating `Timer` fails to run before its next execution time, then any missed executions will
> be skipped.

**The per-device values for `venu445mm` are not published** — not in `compiler.json`, not in
`simulator.json`, not in the Device Reference page. Assume the defaults (3 timers, 50 ms) until
measured. *How to measure*: start a repeating timer at 1 ms, 5 ms, 10 ms, 20 ms, 50 ms in turn; in the
callback record `System.getTimer()` deltas over ~200 ticks and report min/mean/max. Separately,
allocate timers in a loop until it throws, to get the count. Run in the simulator **and** on hardware —
they differ substantially (see below).

### So: 30 fps? 60 fps?

**No.** A 50 ms floor is a hard **20 fps** ceiling for a timer-driven loop, and that is before any
work happens in the callback. 30 fps needs 33.3 ms, 60 fps needs 16.7 ms; neither is expressible.

Even 20 fps is optimistic. On the Connect IQ forums, the consistent community finding is that the
simulator flatters real hardware: on
[Doing animations with Timer](https://forums.garmin.com/developer/connect-iq/f/discussion/5986/doing-animations-with-timer)
a 50 ms timer was needed for smoothness in the simulator while "200ms for real device is ok not less";
on [Screen refresh rate](https://forums.garmin.com/developer/connect-iq/f/discussion/323441/screen-refresh-rate)
a 50 ms delay scrolled far too fast in the simulator but smoothly on a vívoactive 4 — i.e. the device
was running well under the requested rate. (Both threads are community, not Garmin staff; both predate
Venu-class AMOLED hardware, which is considerably faster. Treat 200 ms as a pessimistic floor and 50 ms
as the optimistic one, and *measure on the real watch*.)

There is also **no vertical sync**. Monkey Motion Reference, verbatim: "Because Connect IQ devices do
not support vertical synchronization, high frames rates could potentially result in screen tearing."
Garmin's own video-playback tool recommends target frame rates of **1–10 fps**.

### The watchdog: your real per-frame budget

`simulator.json` → `"watchdogCount": 240000`. The watchdog counts **VM bytecode instructions executed
before returning to the system**; blow through it and the app is terminated with *"Watchdog Tripped
Error - Code Executed Too Long"*. Garmin staff (Anshul.ConnectIQ) on
[venu 2 – less time until watchdog fires](https://forums.garmin.com/developer/connect-iq/i/bug-reports/venu-2---less-time-until-watchdog-fires)
confirms it is "related to the VM instruction execution and at the core of the CIQ", not wall-clock,
and that requests to raise it "will most likely be rejected". The counter resets when you return to
the VM, so a frame callback that returns promptly resets it every frame.

**240,000 bytecodes per frame callback** is the real ceiling on how much game logic a single frame can
run. That number is also the reason the ticket-08 coroutine-conversion strategy matters: a `yield`-free
straight-line port of a long Unity coroutine will trip it.

Design consequence for the port: **decouple the logic tick from the render tick.** Run one repeating
`Timer` at the render period, advance the game a fixed number of logic steps per tick, and treat the
original's per-`yield` cadence as a logical frame count, not wall-clock.

---

## 4. The redraw model

### `requestUpdate` → `onUpdate`, and the whole screen goes

`WatchUi.requestUpdate()` is documented as no more than "Request a call to the `onUpdate()` method for
the current View." There is no documented coalescing rule, no documented maximum rate, and Garmin's
Travis has said only that "it should be legal to call `WatchUi.requestUpdate()` at any time (provided
the symbol is available)" ([bug report thread](https://forums.garmin.com/developer/connect-iq/i/bug-reports/when-is-it-not-ok-to-call-watchui-requestupdate)).

**Plan on a full redraw every frame.** Two independent reasons:

1. **`onPartialUpdate` is not available to you.** It is a `WatchUi.WatchFace` method, for
   always-active **MIP** displays only. The UX guidelines describe it as a watch-face mechanism
   ("MIP always active — ... will allow a small portion of the screen to be updated every second ...
   must operate under a 20 millisecond time frame"). `venu445mm` is `"displayType": "amoled"` and this
   is a watchApp, so neither half applies.
2. **The previous frame is not guaranteed to survive.** From
   [How do I work out what to redraw in onUpdate()?](https://forums.garmin.com/developer/connect-iq/f/discussion/347616/how-do-i-work-out-what-to-redraw-in-onupdate):
   "On some devices, the dc is cleared before onUpdate is called - you won't see this in the sim", and
   "the only solution is to update the entire screen when onUpdate is called". System overlays
   (notifications, toasts) can also paint over your view without telling you.

### The one partial-update lever you do have: `Dc.setClip`

`Dc.setClip(x, y, w, h)` (API 2.3.0) — "All pixels outside of this region will be unaffected by any
drawing operations", cleared with `Dc.clearClip()`. This is a genuine cost reduction: the
[Ciantic/GarminPerformanceTests](https://github.com/Ciantic/GarminPerformanceTests) benchmark measured
"display time" halving (54,080 → 27,040) when a vertical-half clip was applied, though *execution* time
went slightly **up** (862 → 1,062) because of the extra bookkeeping — clipping saves display bandwidth,
not VM cycles. Clipping into many small regions was measurably worse than one big draw.

For this port, the useful clip is the 320×320 game canvas inside the 454×454 screen: 320²/454² = **50%
of the pixels**. The D-Tector frame ring outside it is static and need not be repainted.

Beware SDK 9.2.0's bug-fix note: "Fix a bug where `Dc.clearClip()` can fail to properly clear the
clipping area" — i.e. this was broken until very recently. Build against 9.2.0+.

### What a full 454×454 redraw costs

**Undocumented. There is no published per-device figure, and it must be measured.** The available
reference points bracket it loosely:

- Garmin's own developer blog: a complex screen with many polygons and text can take **up to 700 ms**
  ("calculating and drawing of one single screen can take 700 milliseconds"), and initialization
  "should be lower than 300 milliseconds" to feel fluid.
- Monkey Motion Reference measured **full-screen frame decode times** of 8 ms (low complexity),
  26 ms (medium), 39–40 ms (high) on a fēnix 5 Plus (240×240, 8bpp), and 58–84 ms on the original Venu.
  Venu 4 is much faster hardware, but 454×454 is 3.6× the pixels of 240×240.

*How to measure properly*: in `onUpdate`, bracket the draw with `System.getTimer()` (ms) and log the
delta; separately run Simulator → File → View Profiler and read `Actual Time (us)` for `onUpdate`
and for the blit function. Then repeat on hardware with `monkeyc -k` and the resulting
`GARMIN/APPS/LOGS/<app>.PRF`. **Do the simulator and device runs both** — the simulator is not
predictive of device speed (see §3).

### Memory arithmetic for the render pipeline

`bitsPerPixel: 16`, so a raw full-screen buffer is 454 × 454 × 2 = **412,232 bytes**, and the 320×320
game canvas is 320 × 320 × 2 = **204,800 bytes**. Both would be ruinous against a 768 KB heap — but
since API 4.0.0 `Graphics.createBufferedBitmap()` allocates from the **4 MB graphics pool**, not the
heap, so either fits comfortably. `createBufferedBitmap` also accepts `:palette` and `:colorDepth`;
given the map's finding that every sprite is 1-bit, a 2-colour palette buffer should be dramatically
cheaper than 16bpp. (Exact palette-vs-bytes accounting is not documented — measure it via
`System.getSystemStats()` before/after allocation, and watch for the graphics-pool allocation exception.)

The Monkey Motion Reference documents a second, easily-missed cost: if a View mixes an `AnimationLayer`
with native drawables, an **"overlay" layer is created on demand and "takes a full screen's worth of
memory"**. Avoid mixing layers with the hand-drawn canvas.

For the 10× integer scale, `Dc.drawBitmap2()` (API 4.2.0/4.2.2) takes a `:transform`
(`Graphics.AffineTransform`, supports `scale`) — available at CIQ 6.0.2. Whether hardware-scaled blit
beats 1,024 individual 10×10 `fillRectangle` calls is, again, a measurement for ticket 06.

---

## 5. AMOLED constraints on a long play session

### Burn-in protection does **not** apply to your foreground app

`System.DeviceSettings.requiresBurnInProtection` documents the rules, verbatim:

> Some screens require special drawing behavior when rendering content **in always-on mode**. If a
> screen requires burn-in protection the following rules must be followed: A maximum of ten-percent of
> the total available screen pixels can be in use at one time. Individual pixels can be on for no more
> than three update cycles when updating at once-per-minute intervals. If either condition is violated
> all screen pixels will be turned off until the device goes into high-power mode.

Note "always-on mode" and "once-per-minute intervals" — this is the **watch-face low-power** contract.
The UX guidelines confirm the scope: "AMOLED always active (version 2) — The watch face is prevented
from using more than 10% of the screen pixels. When the user gestures to look at the watch face, the
display will turn on, **the pixel limits are disabled**". The SDK history entry likewise reads "Relax
screen burn-in protection rules for Venu 2 and future AMOLED products to only require using less than
10% of screen pixels" in a watch-face context. A watchApp in the foreground is in high-power mode, so
there is **no 10%-pixel budget and no forced dimming** on your 320×320 canvas.

(`simulator.json` does set `"screenProtectionSupport": true`, and the simulator can run a 24-hour
burn-in simulation — that tooling exists for watch faces.)

### What *will* interrupt a long session: the display timeout

Venu 4 Owner's Manual, *About the AMOLED Display*, verbatim:

> Image persistence, or pixel "burn-in," is normal behavior for AMOLED devices. **To minimize burn-in,
> the Venu 4 display turns off after the selected timeout.**

*Display and Brightness Settings* lists the user-side controls: **Brightness**, **Always On Display**,
**Watch Face Seconds**, **Text Size**, **Color Shift**, **Wake On Alert**, **Wake On Gesture**,
**Timeout** ("Sets the length of time before the screen turns off"), **Touch Lock**.

**The app cannot override any of this.** On
[Is it possible to refresh the screen to stay on longer](https://forums.garmin.com/developer/connect-iq/f/discussion/314782/is-it-possible-to-refresh-the-screen-to-stay-on-longer),
jim_m_58: "The only way to change these things is if the user changes them in the watch settings."

The only API that touches it is `Attention.backlight()`, and it is explicitly fenced:

> The backlight will always respect the backlight timeout settings on the device. ... On products that
> use a gesture enabled display, calling this API will **suppress the gesture detection** for the
> period that the backlight is on. Calling this repeatedly can hold the display on, but **if the
> product has burn in protection an exception will be thrown if you attempt to keep the display
> enabled for too long (e.g. over 1 minute)** — `BacklightOnTooLongException`.

`venu445mm` is in `Attention.backlight`'s supported-device list, so the call works — but pumping it to
keep the screen alive through a play session will throw within about a minute *and* will kill
wake-on-gesture while it's on. Not a viable strategy.

**Recommendation for the port**: document that the player should set Display → Timeout to its longest
value (or enable Always On Display) before a session. Wrap any `Attention.backlight` call in
`try/catch` for `BacklightOnTooLongException`. Design the game so a screen blank is recoverable —
persist checkpoint state (per ticket 03) rather than assuming continuous foreground rendering.

### Foreground-app lifetime

There is **no inactivity timeout on the activity-list launch path**. UX guidelines → *Entry Points*,
verbatim:

> **Activity List (Device apps)** — ... When a user launches an app from the activity list, the app
> will run **until the user explicitly backs out from the first page**.

Contrast with the two paths that *do* time out:

> **Glance List** — ... The user can exit by backing out of the base page, but **after a period of
> inactivity, the system will terminate the launched app**, as well.
>
> **Widget Loop** — ... **After a period of inactivity, the widget will be terminated**, and the user
> will return to the home screen.

So: ship it as a watch-app launched from the activity list (which is what `type="watch-app"` gives),
do **not** add a glance, and the app itself will not be reaped mid-session. (Community reports put the
glance/widget inactivity kill at 1–2 minutes depending on device.)

The manual's "Activity Timeout" setting (Normal = 5 min, Extended = 25 min) governs *native activity
mode* waiting to start an activity, not a Connect IQ app's lifetime.

---

## Open items that need hardware or a running simulator

These are the numbers I could not obtain from documentation or a build, listed so ticket 06 can pick
them up:

1. **Actual `Timer` minimum and timer count on `venu445mm`** — not published; measure per §3.
2. **Wall-clock cost of a full 454×454 `onUpdate`**, and of the 320×320 clipped variant — measure per §4.
3. **Cost of the 10× scale blit**: `drawBitmap2` + `AffineTransform` vs. 1,024 `fillRectangle` calls
   vs. a pre-scaled `BufferedBitmap`.
4. **Graphics-pool bytes actually consumed** by a 320×320 palette-limited `BufferedBitmap` — read
   `System.getSystemStats()` before/after, and confirm against the 4,194,304-byte pool.
5. **Bytecodes per logic frame** vs. the 240,000 watchdog budget, once real ported logic exists.
6. **Real PRG size of the ported `Logic/` layer** with and without `(:extendedCode)`, via
   `monkeyc --build-stats 0`, in both debug and release.

Reproduction harness for items 6 (and the §1/§2 numbers) is at
`/private/tmp/claude-502/-Users-tiscomacnb2227-Workspace-garmin-d-tector/2cfbef5b-836a-439a-b7ec-c70531a6572c/scratchpad/mem/`
(throwaway; a self-signed dev key, a minimal `venu445mm` manifest, and a generated-source workload).

---

## Sources

### Local — SDK 9.2.0 (`~/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.2.0-2026-06-09-92a1605b2`)

- `doc/Toybox/Timer/Timer.html` — timer count / minimum interval / missed-tick behaviour
- `doc/Toybox/System/Stats.html` — `totalMemory`, `usedMemory`, `freeMemory`
- `doc/Toybox/System/DeviceSettings.html` — `requiresBurnInProtection` and its rules
- `doc/Toybox/Attention.html` — `backlight()`, `BacklightOnTooLongException`, supported devices
- `doc/Toybox/Graphics.html` — `createBufferedBitmap` options (`:palette`, `:colorDepth`)
- `doc/Toybox/Graphics/Dc.html` — `setClip` / `clearClip`
- `doc/Toybox/WatchUi.html` — `requestUpdate()`
- `doc/Toybox/WatchUi/AnimationLayer.html` — supported devices incl. Venu 4 45mm
- `doc/docs/Core_Topics/Graphics.html` — graphics pool, buffered bitmaps, clipping, `drawBitmap2`, transforms
- `doc/docs/Core_Topics/User_Interface.html` — View lifecycle, Layers
- `doc/docs/Core_Topics/Profiling.html` — simulator profiler, `-k`, `.PRF` files
- `doc/docs/Core_Topics/Debugging.html`
- `doc/docs/Monkey_C/Annotations.html` — **`(:extendedCode)`, 16 MB, MRU paging, performance warning**
- `doc/docs/Readme/History.html` — release notes: PRG-size error message, graphics-pool exceptions, per-device graphics pool size, burn-in rule relaxation, new opcodes for code space
- `doc/docs/Reference_Guides/Monkey_Motion_Reference.html` — frame-rate guidance (1–10 fps), no vsync, decode-time tables, animation/overlay frame-buffer memory
- `doc/docs/User_Experience_Guidelines/Entry_Points.html` — **app lifetime per launch path**
- `doc/docs/User_Experience_Guidelines/Watch_Faces.html` — AMOLED always-on rules, 20 ms partial-update window
- `doc/docs/Device_Reference/venu445mm.html` — device attributes, app-type memory limits, fonts
- `samples/ExtendedCodeSpace/` — working `(:extendedCode)` sample and jungle wiring
- `bin/monkeyc --help` — `--build-stats`, `-O z`, `-k`, `-r`, `-l`

### Local — device files (`~/Library/Application Support/Garmin/ConnectIQ/Devices/venu445mm/`)

- `compiler.json` — `memoryLimit` 786432, `codePageSize` 4096, `maxPrgFilespace` 67108864, `bitsPerPixel` 16, `displayType` amoled, CIQ 6.0.2
- `simulator.json` — **`graphicsResourcePoolSize` 4194304, `watchdogCount` 240000, `appStorageCapacity` 10485760, `screenProtectionSupport` true**
- `venu445mm.api.debug.xml` — API surface grep (`requiresBurnInProtection`, `BacklightOnTooLongException`)

### Measured on this machine (SDK 9.2.0, `-d venu445mm`)

- `monkeyc ... --build-stats 0` outputs for: trivial app (debug/release), 17,219-LOC synthetic workload
  (debug/release/`(:extendedCode)`), and a ~69k-LOC workload with and without `(:extendedCode)`.
  Reproduction harness path given above.

### Garmin first-party web

- <https://www.garmin.com/en-US/blog/developer/improve-your-app-performance/> — compiled size counts against the limit; simulator File→View memory; `CIQ_LOG.txt`; 700 ms complex screen
- <https://www.garmin.com/en-US/blog/developer/app-speed-optimizations/> — <300 ms init; locals ~8× faster than globals; buffered-bitmap strategy; skipping `clear()` for partial updates
- <https://developer.garmin.com/connect-iq/user-experience-guidelines/watch-faces/> — Always On (AMOLED) rules
- <https://developer.garmin.com/connect-iq/api-docs/Toybox/Graphics/Dc.html>
- <https://www8.garmin.com/manuals/webhelp/GUID-2CF5620C-E585-4E0A-9CC3-9565533EEE4D/EN-US/GUID-8ECEF6B4-5257-44E9-BB09-778836BBF700.html> — Venu 4 *About the AMOLED Display* ("display turns off after the selected timeout")
- <https://www8.garmin.com/manuals/webhelp/GUID-2CF5620C-E585-4E0A-9CC3-9565533EEE4D/EN-US/GUID-A3426392-ACFC-465D-B773-263C6C92DCA3.html> — Venu 4 *Display and Brightness Settings*
- <https://www8.garmin.com/manuals/webhelp/GUID-2CF5620C-E585-4E0A-9CC3-9565533EEE4D/EN-US/GUID-7A30002F-B50A-4F1C-84CA-0EADBF4A9759.html> — Venu 4 battery-life tips (timeout / Always On Display)

### Garmin developer forums

- <https://forums.garmin.com/developer/connect-iq/i/bug-reports/venu-2---less-time-until-watchdog-fires> — Anshul.ConnectIQ (Garmin) on the watchdog counting VM instructions
- <https://forums.garmin.com/developer/connect-iq/f/discussion/347616/how-do-i-work-out-what-to-redraw-in-onupdate> — full-screen redraw is mandatory; Dc cleared on some devices; `onPartialUpdate` is MIP watch-face only
- <https://forums.garmin.com/developer/connect-iq/f/discussion/314782/is-it-possible-to-refresh-the-screen-to-stay-on-longer> — cannot extend display timeout from an app
- <https://forums.garmin.com/developer/connect-iq/f/discussion/5986/doing-animations-with-timer> — 50 ms simulator vs 200 ms device
- <https://forums.garmin.com/developer/connect-iq/f/discussion/323441/screen-refresh-rate> — simulator/device frame-rate divergence
- <https://forums.garmin.com/developer/connect-iq/i/bug-reports/when-is-it-not-ok-to-call-watchui-requestupdate> — Travis (Garmin): `requestUpdate()` legal at any time
- <https://forums.garmin.com/developer/connect-iq/f/discussion/252223/avoid-watchdog-tripped-error---code-executed-too-long> — watchdog budgeting technique
- <https://forums.garmin.com/developer/connect-iq/f/discussion/395873/graphic-pool-memory-allocation-failing-despite-memory-showing-ok-in-sim> — graphics-pool exhaustion distinct from heap
- <https://forums.garmin.com/developer/connect-iq/f/discussion/234402/pushing-memory-limit-in-simulator> — simulator memory viewer / peak usage

### Third-party (empirical, flagged as such)

- <https://github.com/Ciantic/GarminPerformanceTests> — `setClip` vs full-bitmap draw benchmark (FR955, simulator, SDK 4.1.4)
