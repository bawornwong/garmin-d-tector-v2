# 1. The fidelity anchor is the source, not the toy

Date: 2026-09-06

## Status

Accepted as the default for game content and rules. The watch-step input
decision below was later changed at the player's request; see
[README.md](../../README.md) and [watch-step-sync-design.md](../watch-step-sync-design.md).

## Context

This is a port of [kaisadilla/D-Tector-v2](https://github.com/kaisadilla/D-Tector-v2), a Unity emulator of the physical D-Tector toy. The two differ in places, and the watch happens to have hardware the toy had and the emulator could not use.

The clearest case: the toy counted real steps with a pedometer. The emulator, running on a PC with no legs, substituted a shake gesture — `ShakeDetector.cs` turns five detected shakes into one step. The watch has a real pedometer, so `ActivityMonitor.getInfo().steps` would arguably be *more* faithful to the toy than the emulator is.

## Decision

**The Unity source anchors content and game rules.** The initial input plan
also copied its shake-to-step mapping. The watch version subsequently adopted
the watch's recorded steps as its journey input: one recorded step is one
game step, including steps recorded while the app is closed. This is an
explicit input adaptation; the source's world distances and event rules remain.

## Consequences

- Source comparison remains the way to check translated game content and
  rules. Watch input, steps, notifications, and sound are documented as
  adaptations where the implementation differs.
