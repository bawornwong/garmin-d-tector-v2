# Save format mapping

Type: grilling
Status: open
Blocked by: 03

## Question

How does the original save game map onto Connect IQ persistence?

The original uses Unity `PlayerPrefs` plus binary serialisation, with multiple save slots and encryption (`SavedGame.cs`, 430 LOC; `EncryptedPlayerPrefs.cs`). Connect IQ offers `Application.Storage` and `Application.Properties`.

Decide:

- **Slot count** — multiple slots as in the original, or one, given the measured storage quota.
- **Encoding** — one dictionary per slot versus many flat keys. Weigh per-key overhead against read/write cost against the quota.
- **Encryption** — the original encrypts saves. On a sideloaded personal build there is no threat model for it. Drop it, or keep it for fidelity?
- **Save points** — when a save is written: every state change, on a timer, on app exit, or a mix. Depends on the measured write cost.
- **Migration** — the original tracks `last_update_version` for save migrations. Is a version field carried forward?
- **Field mapping** — walk `SavedGame.cs` and produce the field-by-field mapping. Anything dropped is a content change and must be justified.
