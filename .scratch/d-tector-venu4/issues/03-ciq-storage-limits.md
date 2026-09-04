# Connect IQ storage limits for save games

Type: research
Status: open
Blocked by: —

## Question

How much persistent data can a `venu445mm` watchApp store, and in what shape?

Answer all of:

1. **`Application.Storage`** — total quota per app, per-key value size limit, supported value types (dictionaries, arrays, nested structures, byte arrays). Is the quota documented, or only discoverable empirically?
2. **`Application.Properties`** — how it differs, whether it is appropriate for game state or only user settings.
3. **Write cost** — how expensive a save is, whether it blocks, whether frequent autosaves are viable or saves must be batched at app exit.
4. **Durability** — what happens on app crash, watch reboot, or app update. Is stored data preserved across a re-sideload of the same app?
5. **Original shape** — read `Assets/Scripts/SavedGame/SavedGame.cs` (430 LOC) and `EncryptedPlayerPrefs.cs` in the source checkout. Estimate the byte size of one save slot and report how many slots would fit.

Prefer primary sources: Connect IQ API docs, Garmin developer forum posts from Garmin staff.

Ticket [Save format mapping](./10-save-format-mapping.md) waits on this.
