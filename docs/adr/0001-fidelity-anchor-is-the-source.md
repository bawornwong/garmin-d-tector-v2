# 1. The fidelity anchor is the source, not the toy

Date: 2026-09-06

## Status

Accepted

## Context

This is a port of [kaisadilla/D-Tector-v2](https://github.com/kaisadilla/D-Tector-v2), a Unity emulator of the physical D-Tector toy. The two differ in places, and the watch happens to have hardware the toy had and the emulator could not use.

The clearest case: the toy counted real steps with a pedometer. The emulator, running on a PC with no legs, substituted a shake gesture — `ShakeDetector.cs` turns five detected shakes into one step. The watch has a real pedometer, so `ActivityMonitor.getInfo().steps` would arguably be *more* faithful to the toy than the emulator is.

## Decision

**Where the toy and the source disagree, the source wins.** The port reproduces the emulator's behaviour, not the toy's.

Shake is therefore a faithful translation of `ShakeDetector.cs` — low-pass filter, threshold 2.0 squared, five detections per step, active only inside the Status app — polling `Sensor.getInfo().accel` from the game timer. The watch's pedometer is not used.

## Consequences

- Walking with the app closed does not advance distance, exactly as in the source.
- Accelerometer polling costs nothing outside Status, where shake is the only place `ShakeDisabled()` returns false.
- Every later "the real device did X" argument is settled the same way, without reopening the question.
- If someone later wants toy-faithful behaviour, that is a different product and a different effort.
