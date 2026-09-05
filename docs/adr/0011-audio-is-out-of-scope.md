# 11. Audio is out of scope

Date: 2026-09-06

## Status

Accepted

## Context

The source ships 51 MP3s, 12 MB, played from 64 call sites. A Connect IQ watchApp cannot play audio files at all — only `Attention.playTone` profiles and vibration. Approximating 51 sounds as tone profiles is a project of its own, and an approximation is not a reproduction.

## Decision

Audio is **out of scope for this port**. The 44 `PlaySound` and 20 `PlayButtonA` calls are translated as calls to empty methods.

## Consequences

- This is a hardware ceiling, not a content change: the platform cannot do it, so nothing was chosen away.
- Keeping the call sites means the files still diff against the original, and a later tone or vibration effort fills in one place rather than re-deriving 64 call sites.
- Nothing about the game's timing depends on sound, so the animations are unaffected.
