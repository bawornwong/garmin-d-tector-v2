# Connect IQ storage limits for save games

Type: research
Status: resolved
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

## Context

Findings land at `.scratch/d-tector-venu4/research/03-ciq-storage-limits.md`.

## Answer

Full findings: [research/03-ciq-storage-limits.md](../research/03-ciq-storage-limits.md)

1. **`Application.Storage` is present and complete** on `venu445mm` — verified against the device's own `venu445mm.api.debug.xml`: `getValue`/`setValue`/`deleteValue`/`clearValues`, `StorageFullException`, `onStorageChanged`. `ValueType` covers nested Arrays and Dictionaries **and `ByteArray`**; keys and values may not be `Symbol`. Size limits **conflict across primary sources**: Core Topics says "8 KB each, total of 128 KB"; the API reference and the docstring baked into the device XML say "values are limited to 32 KB" and "a limit … that can vary between devices". The per-device total is undocumented. `venu445mm/simulator.json` carries `"appStorageCapacity": 10485760` (10 MB); across 173 installed device profiles that field takes only four values (absent / 128 KB / 256 KB / 10 MB), and the 128 KB bucket matching the doc exactly — plus the string sitting beside `.STR`, `Modify Object Store` and `StorageFullException` in the simulator binary — makes it very likely the object-store quota. **This is inference, not documentation**; confirm by filling until `StorageFullException`.

2. **`Application.Properties` is the wrong tool for game state.** Keys must be declared in build-time resource XML (`InvalidKeyException` otherwise), types are scalars only (no dictionaries, no `ByteArray`), values are user-editable from the phone, and they flush only at `onStop()`. It is the right home for the original's `config_*` keys.

3. **Writes are synchronous and expensive.** `setValue` commits to disk immediately; forum guidance is consistently to minimise file-system hits and batch into one key. **This is load-bearing**: `SavedGame.cs` triggers a full serialise from *every property setter*, including `Steps` and `CurrentDistance`. Autosave at the original's granularity is not viable — the port needs RAM-resident state, a dirty flag, and checkpointed saves. Also note open Garmin bug reports of `System Error` from `setValue` on recent firmware; wrap it in try/catch.

4. **Durability**: committed Storage survives crash and reboot; unflushed RAM and unflushed Properties do not. For a sideload, data lives in `\GARMIN\APPS\DATA` named after the `.prg` filename — so **keep the `.prg` name byte-identical and ≤8 characters, and copy over the old file**. Renaming orphans the save. (Store updates via Garmin Connect Mobile are reported to be uninstall/reinstall and lose data; that path doesn't apply to us.) Carry a format-version byte from day one.

5. **Save size**: `SavedGameFile` has 26 fields. A real save from the checkout (`game0.disabled`) measures 4,328 bytes, of which ~1.8 KB is `BinaryFormatter` type metadata. Dimensions from the shipped data: 593 Digimon (mean name 10.2 chars), 9 worlds, 52 areas, 55 boss slots, 104 spirits, max stored level 51 (one byte). A naive dictionary-keyed-by-name port costs **~27 KB/slot** — reject it. A packed `ByteArray` keyed by Digimon *index* costs **~1.1 KB/slot**, essentially fixed. That is ~116 slots even against the conservative 128 KB budget. **Storage is not the constraint**; 3–4 slots is comfortable, one Storage key each plus a ~100 B index key for the slot picker.

**Also**: `EncryptedPlayerPrefs.cs` is dead code — unreferenced by `SavedGame.cs`. Drop it rather than porting it.

**Consequence for the map:** multiple save slots are affordable, so the original's structure is preserved. The real decision moving to [Save format mapping](./10-save-format-mapping.md) is the packed-ByteArray encoding and the save-checkpoint policy, not the slot count.

## Follow-up: the quota, measured

The per-device total was inferred here from `simulator.json`. [Save format mapping](./10-save-format-mapping.md) measured it: **9,214 KB written before `Toybox.Application.Storage.setValue() storage limit exceeded`**, confirming `appStorageCapacity: 10485760` and ruling out the Core Topics figure of 128 KB for this device. That ticket also found `setValue` far cheaper than the forum guidance suggested — 1 ms for a 1,024-byte value.
