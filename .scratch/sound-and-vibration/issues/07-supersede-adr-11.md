# Supersede ADR 11 and update the documents

Type: task
Status: open
Blocked by: 05, 06

## Question

Write the decision down once it is real.

1. **Supersede [ADR 11](../../../docs/adr/0011-audio-is-out-of-scope.md).** Its factual premise was half right and should be preserved as such: a watchApp genuinely cannot play audio files, and that has not changed. What it got wrong is the conclusion — it treated "tone profiles" as necessarily an approximation, when the source sounds turned out to be monophonic square waves and `ToneProfile` is a square-wave generator, so reproduction is achievable. Mark ADR 11 superseded rather than deleting it; the reasoning is worth keeping and the new ADR should say plainly what new evidence moved it.
2. **Write the new ADR**: audio is tones and haptics, generated from the source, round-trip verified. Record the playback model (fibers, chunks, interruption) and the vibration vocabulary as decisions with their reasons.
3. **SPEC.md line 11** currently lists audio under **Out of scope**, citing ADR 11. Move it into scope and point at the new ADR.
4. **HANDOFF.md**: add the extractor's round-trip result to the table of proven checks if it earned a row (see the map's Not-yet-specified), note the new generated file and the tool that writes it in section 2, and put anything the hardware probe cost time to find into section 4.
5. **CONTEXT.md** has no audio vocabulary at all. If terms settled during this effort — what a *note*, a *chunk*, a *motif*, a *vibration event* means here — add them.

## Context

Last, deliberately: written once the shape is real rather than as the effort goes, so it describes what was built instead of what was planned.
