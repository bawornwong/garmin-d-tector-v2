# Connect IQ memory and timing budget

Type: research
Status: open
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
