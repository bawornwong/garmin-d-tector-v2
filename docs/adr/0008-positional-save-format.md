# 8. Saves are positional byte records, written at checkpoints

Date: 2026-09-06

## Status

Accepted

## Context

`SavedGameFile` has 26 fields, two of which are dictionaries keyed by Digimon name over all 593 entries (`digimonLevel`, `digicodeUnlocked`). The original serialises the whole object with `BinaryFormatter` from **25 property setters**, including `Steps` and `CurrentDistance`, which fire constantly while walking.

Measured on the device: a 1,024-byte `ByteArray` writes in **1 ms** and reads back byte-identical; the 593-key dictionary form costs **about 40 KB of heap**; the Storage quota is **9,214 KB** — confirming the 10 MB `appStorageCapacity` and refuting the documented 128 KB.

## Decision

A slot is a **963-byte positional record** holding every field of `SavedGameFile`: `digimonLevel` as 593 bytes, `digicodeUnlocked` as 593 bits, `areasCompleted` as 52 bits, and every Digimon-valued field as an index. Four slots, one Storage key each, plus a small index key for the slot picker. A version byte leads the record.

Encryption is dropped: `EncryptedPlayerPrefs.cs` is dead code, unreferenced by `SavedGame.cs`, and a personal sideload has no threat model for it.

State is held in RAM and committed at **checkpoints** — app exit, screen transitions, after a battle, after an event — rather than from every setter.

## Consequences

- **The saved content is identical either way.** Only the write schedule changes, so the fidelity contract is untouched.
- Checkpointing is about flash wear, not latency: at 1 ms a write, the original's cadence would be affordable but would mean thousands of flash writes an hour.
- Storage is nowhere near a constraint; slot count is a product choice, not a budget one.
- **The `.prg` filename becomes part of the format.** Saves live in `\GARMIN\APPS\DATA` named after it, so it must stay byte-identical and at most 8 characters or every save is orphaned.
