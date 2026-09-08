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

## Progress — the sound half is done

Steps 1–4 are done **for sound**, which was safe to write early for one reason the ticket did not anticipate: leaving them undone meant the repo actively *stated something false*. `SPEC.md` listed audio as out of scope while verified, committed code played tones, and ADR 11 said the same. Wrong documentation is worse than missing documentation.

- **[ADR 13](../../../docs/adr/0013-sound-is-tones-generated-from-the-source.md)** written: records the evidence that moved it (monophonic square waves against a square-wave generator), the extraction rule, the ADR 6 packing and *why* it was forced rather than chosen, the fiber/chunk playback model, what `stopSound` can and cannot mean, the interrupt rule, and the untouched trace.
- **ADR 11 marked superseded for sound**, kept rather than deleted — its factual claim about `Toybox.Media` stands permanently, and the record of why the wrong inference was believed is worth keeping.
- **SPEC.md** now has sound in scope and describes what is genuinely still out (playing the files themselves).
- **HANDOFF.md** gained the round-trip row and `SoundData.mc`, plus the batching note for running the verifier on a memory-tight machine.

**Still open, and deliberately so:** the vibration half. ADR 13 says outright that it does not cover vibration, so this ticket stays open until ticket 06 lands and either extends ADR 13 or earns its own. `CONTEXT.md` also has no audio vocabulary yet — worth doing once *note*, *chunk* and *vibration event* have all settled, rather than half now.
