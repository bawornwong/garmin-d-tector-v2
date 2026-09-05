# 5. Preserve the original schedule, not the frame cadence

Date: 2026-09-06

## Status

Accepted

## Context

Connect IQ's timer floor on this device is 50 ms, a hard ceiling of **20 fps**. The source is a Unity game running at 60. Its animations are written as sequences of `WaitForSeconds`.

Measuring every wait in the codebase: **434 of 531 (82%) are exact multiples of 50 ms** — the game was authored on a 0.05 s grid, and `Constants.ATTACK_TRAVEL_SPEED` is exactly 0.05. But 69 waits would drift more than 10% if each were rounded to whole ticks, and **36 waits are shorter than one tick**, the fast per-frame motion loops. Rounding those up slows their animations by as much as 220%.

Something has to give: either smoothness or duration.

## Decision

The runner keeps the original schedule in floating-point milliseconds. Each tick advances a budget by 50 ms and executes **every step whose scheduled time has arrived** — so sub-tick waits still happen, several within one frame, and an animation's total duration matches the original exactly.

## Consequences

- Durations are exact. Measured across four cases: 4000.0000 ms, 2518.7500 ms, 3000.0000 ms, 2600.0000 ms, all matching the reference.
- Motion loops that advanced one pixel per 0.0375 s now advance one or two pixels per frame. This is the unavoidable consequence of showing a 60 fps original at 20 fps; duration was chosen over smoothness because it is the more perceptible of the two.
- Up to 11 animation events were observed landing in a single frame.
