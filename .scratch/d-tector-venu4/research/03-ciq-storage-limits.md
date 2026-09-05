# Connect IQ storage limits for save games (`venu445mm`)

Research output for [issue 03](../issues/03-ciq-storage-limits.md). Target: Venu 4 45mm, Connect IQ 6.0.2, SDK 9.2.0.

## TL;DR

- Use **`Application.Storage`**, one key per save slot, value = a single packed **`Lang.ByteArray`**.
- A fully-completed save slot packs to **~1.1 KB** — fixed size, independent of progress.
- Even the most conservative documented budget (128 KB total, 8 KB per key) leaves room for **dozens of slots**. Venu 4's own device profile advertises **10 MB** of app storage capacity. Slot count is a UX decision, not a storage one.
- `Storage.setValue()` writes to disk **immediately and synchronously**. It is a file-system hit and is expensive — do not autosave per frame. The original game saves on *every* property setter; that must be replaced by a dirty-flag + throttled/explicit save.
- `Application.Properties` is the **wrong tool** for game state: keys must be declared at build time, values are user-editable from the phone, and they are flushed only at `onStop()`.

---

## 1. `Application.Storage`

### Existence on `venu445mm`

Confirmed present in the device's own API surface (`venu445mm.api.debug.xml`):

- `<entry id="8390424" module="true" symbol="Storage"/>`
- `<dataEntry label="Toybox_Application_Storage" … type="module"/>`
- `functionEntry` for `Storage.getValue`, `Storage.setValue`, `Storage.deleteValue`, `Storage.clearValues`
- `Toybox_Lang_StorageFullException` class is present in the device binary
- `AppBase.onStorageChanged()` is present

So the full 2.4.0+ Storage API is available. (`AppBase.getProperty`/`setProperty`/`saveProperties`/`clearProperties` also still exist on the device, but the docs mark them `@deprecated This method may be removed after System 4.` — do not use them.)

### Supported value types

From the online API reference (`Toybox.Application.Storage`), `Storage.ValueType` is:

> `Lang.Number` or `Lang.Float` or `Lang.Long` or `Lang.Double` or `Lang.String` or `Lang.Boolean` or `Lang.Char` or **`Lang.ByteArray`** or `Graphics.BitmapReference` or `WatchUi.BitmapResource` or `WatchUi.AnimationResource` or `BluetoothLowEnergy.ScanResult` or `Complications.Id` or `WatchFaceConfig.Id` or `Lang.Array<Storage.ValueType>` or `Lang.Dictionary<Storage.KeyType, Storage.ValueType>` or `Null`

`Storage.KeyType` is: `Number`, `Float`, `Long`, `Double`, `String`, `Boolean`, `Char`. **Not `Symbol`** — the docstring warns explicitly: *"Symbols can change from build to build and are not to be used for Keys or Values."*

Arrays and dictionaries nest arbitrarily, and `ByteArray` is a first-class value type. That is the whole toolkit we need.

Note a **documentation conflict**: the Core Topics article lists only `Number/Float/Long/Double/Char/String/Boolean/Array/Dictionary` and says *"it is not possible to store a `Lang.Symbol` in an `Lang.Array` or `Lang.Dictionary` in Storage."* It omits `ByteArray`. The API reference (which is generated from the same doc comments that ship in the device XML) includes it. The API reference is the newer and more specific source; the device XML's `setValue` docstring also enumerates a list of *added* types over time that matches the API reference. Treat `ByteArray` as supported but **verify in the simulator on first spike** (see §6).

### Size limits — this is where the sources disagree

Three primary numbers exist, and they do not agree:

| Source | Per-key/value limit | Total per app |
|---|---|---|
| Core Topics → *Persisting Data* (developer.garmin.com) | *"Keys and values are limited to **8 KB** each"* | *"a total of **128 KB** of storage is available"* |
| API reference + the docstring baked into `venu445mm.api.debug.xml` | *"values are limited to **32 KB** in size"* | *"There is a limit on the size of the Object Store that **can vary between devices**"* |
| Forum (community, older-era) | 8 KB per key with the Storage API; 8 KB **total** for the legacy `.str` object store | "~100 kB with the new Storage API" |

**The device XML is authoritative for this device** and it says 32 KB per value and that the total varies per device. The 8 KB / 128 KB pair in Core Topics reads as a CIQ-2.4-era figure that was never revised.

### A device-specific total limit *is* discoverable, but it is not documented

`~/Library/Application Support/Garmin/ConnectIQ/Devices/venu445mm/simulator.json` contains:

```json
"appStorageCapacity": 10485760
```

= **10,485,760 bytes (10 MB)**.

Across the 173 device profiles installed with SDK 9.2.0, this key takes exactly four values:

| `appStorageCapacity` | Devices |
|---|---|
| absent | 17 (CIQ 1 era — no Storage API at all) |
| 131,072 (128 KB) | 29 |
| 262,144 (256 KB) | 3 |
| 10,485,760 (10 MB) | 124 — including `venu445mm` |

The 128 KB bucket matching the Core Topics figure exactly is strong evidence that `appStorageCapacity` **is** the per-app object-store quota, and that the doc's "128 KB" is simply the value that was universal when the doc was written. Corroborating: the string `appStorageCapacity` appears in the simulator binary (`ConnectIQ.app/Contents/MacOS/simulator`) immediately adjacent to `.STR`, `Modify Object Store`, `Sim::ObjectStoreWindow`, and `TVM_cls_Toybox_Lang_StorageFullException`.

**Stated explicitly: this is inference, not documentation.** Garmin has never published a per-device object-store quota table, and forum threads asking for one go unanswered. `appStorageCapacity` is not documented anywhere in the SDK, the Core Topics articles, or the API reference.

**Planning posture:** budget against the conservative documented pair — **8 KB per key, 128 KB total** — and treat the 10 MB as unearned headroom. At ~1.1 KB per packed slot (§5) that is still ~100 slots, so the conservative number costs us nothing.

### Empirical determination (the only way to be certain)

Write a throwaway app that loops `Storage.setValue(i, <1 KB ByteArray>)` inside `try/catch (e instanceof Lang.StorageFullException)`, counting bytes until it throws, then binary-search the last value's size for the per-key cap. Run it both in the simulator (which enforces `appStorageCapacity`) and on the physical watch — they may not agree.

---

## 2. `Application.Properties` — not for game state

From Core Topics → *Persisting Data* and *Properties and App Settings*:

- *"**Properties** are constant values defined at build time and included in the executable."* Every key must be declared in a `<properties>` resource XML element at compile time.
- *"`Properties.getValue()` … If a key that is not present in application properties is passed to `Properties.getValue()`, an exception will be thrown"* — `Properties.InvalidKeyException`, which is present in the `venu445mm` device binary.
- Property types are restricted to `number`, `long`, `float`, `double`, `boolean`, `string`, `array`. **No dictionary, no byte array, no nesting.** (Array properties are for *settings* arrays and come back as `Array<Dictionary>` shaped by the setting definition.)
- *"Information is automatically saved on disk when `AppBase.onStop()` is called."* — Properties are **not** flushed on write. A crash between the write and `onStop()` loses them.
- A property is the backing store for a user-facing **Setting**, editable from Garmin Connect Mobile / Garmin Express, with `AppBase.onSettingsChanged()` firing when the user changes it.
- Storage and Properties are separate namespaces. Forum consensus, unchallenged: *"`Storage.setValue()` and `Storage.getValue()` are for data that is only accessible within the application. `Properties.getValue()` and `Properties.setValue()` are for properties/settings."* Data written to one is not readable from the other.

**Verdict:** Properties is for user-tunable settings only. In D-Tector terms, the `config_*` keys in `SavedGame.cs` (`config_volume`, `config_localization`, `config_active_color_*`, `config_background_color_*`) are a natural fit for Properties+Settings — they are exactly the "user preference" shape, and exposing them on the phone is a bonus. Everything under `SavedGameFile` goes in Storage. (Volume is moot — audio is out of scope per the map.)

---

## 3. Write cost

**Storage writes are synchronous and immediate.** Core Topics: *"Information is automatically saved on disk when `Storage.setValue()` is called."* There is no explicit flush, no `saveStorage()`, and no documented write-behind cache. (Contrast Properties, flushed at `onStop()`, and the legacy object store, which *"lives in memory until your app terminates, at which point it is saved to disk."*)

**They are expensive.** No Garmin staff post quantifies the cost in milliseconds, but the guidance is consistent across the forum:

- *"you only want to make calls that hit the file system as infrequently as possible as those calls are expensive"*
- *"you could save them as an array of the 8 colors (1 file system hit to read all 8)"* — batch multiple values into one key rather than issuing N calls.
- A developer writing every 5 minutes from a background service was told the operation *"is very expensive"*; nobody from Garmin confirmed whether the flash layer does wear levelling or deferred writes. **Undocumented.**
- Empirically there is also a reliability tail: multiple open bug reports of `System Error` / `File Not Found` thrown from `Storage.setValue()` on recent firmware (Venu 3, FR965, FR265, Edge 540/840/1040). Wrap saves in `try/catch` and do not assume a save can never fail.

**Implication for the port — this is the load-bearing finding.**

`SavedGame.cs` calls `SaveGame()` → `lg.WriteToFile()` → a full `BinaryFormatter` serialise **from the setter of nearly every property**. `CurrentDistance`, `Steps`, `PlayerExperience`, `SpiritPower`, `SetDigimonLevel`, `JackpotValue` — all of them rewrite the entire save file on assignment. On a PC that is a few hundred microseconds. On a Garmin watch, at the rate `Steps` changes during a walk, it is a battery and flash-wear problem and will visibly stall the render loop.

The port must break that coupling:

- Hold the whole save in RAM (~1.1 KB packed, or a few KB as live Monkey C objects — negligible against the 768 KB app limit).
- Mark dirty on mutation; never write from a setter.
- Flush at natural boundaries: `AppBase.onStop()`, leaving a minigame, completing a battle, and a coarse timer (e.g. no more than once every 60–120 s while dirty).
- One `setValue` per flush — the whole slot as one packed value, not per-field keys.

Frequent autosave is *not* viable at the original's granularity. Batched saves at exit + checkpoints are.

---

## 4. Durability

**App crash / uncaught exception.** Everything written with `Storage.setValue()` before the crash is on disk (writes are immediate). Anything only in RAM since the last flush is lost. Properties written since the last `onStop()` are lost. → Checkpoint at meaningful boundaries, not just `onStop()`.

**Watch reboot / battery death.** Same story: committed Storage values survive; unflushed RAM does not. `onStop()` is not guaranteed to run on a hard power loss.

**App update / reinstall.** Persistent data lives in `\GARMIN\APPS\DATA` on the device's mass-storage volume, in files derived from the `.prg`. Historically one `.str` per app; with `Application.Storage` a forum post describes it as *"replaced by 3 files (index/data/something else)"*. Behaviour on update is **not documented by Garmin** and is reported to differ by install path:

- Store update via Garmin Connect Mobile: reported to be an **uninstall/reinstall**, which loses persisted data and settings. Multiple user reports of CIQ data-field settings being wiped by an update.
- Update via Garmin Express: reported to preserve data.

Neither is a Garmin-staff statement. For this project it barely matters — **sideload only**, per the map.

**Re-sideload of the same app — the one that matters here.** For a sideloaded `.prg`, the data file is named after the `.prg` filename: *"if you sideload a `.prg` (say `abcdef.prg`), the OS will be `abcdef.str`. But … if you sideload `abcdefabc.prg` the `.str` will be turned into an 8.3 name (like `abcdef~1.str`)."*

Practical rules for the build/deploy loop:

1. **Keep the `.prg` filename byte-identical** across sideloads. Copying `DTector.prg` over the old `DTector.prg` preserves the data files. Renaming it (`DTector-v2.prg`, `DTector-dev.prg`) orphans the old data and starts fresh.
2. Keep the filename **≤ 8 characters** before `.prg` to avoid 8.3 mangling ambiguity, which is where the collision risk lives.
3. **Do not delete the app from the watch** between iterations — copy over it.
4. The app UUID in `manifest.xml` identifies the app to the store; do not regenerate it.
5. Version the save format from day one: put a format-version byte at offset 0 of the packed blob and migrate on read. Sideload iterations will change the layout, and a stale blob decoded with a new layout is a silent corruption, not an exception.
6. `Storage.clearValues()` exists — wire a debug "wipe" path so a bad blob is recoverable without a re-sideload.

---

## 5. Original save shape and size

### Fields

`SavedGameFile` (in `Assets/Scripts/SavedGame/SavedGame.cs`) is a `[System.Serializable]` class written with `BinaryFormatter`. 26 fields:

| Group | Fields |
|---|---|
| Technical | `filePath` (string), `name` (string), `gameChar` (int), `cheatsUsed` (bool) |
| Volatile | `pendingEvent` (int), `isPlayerInsured` (bool), `isLeaverBusterActive` (bool), `leaverBusterExpLoss` (int), `leaverBusterDigimonLoss` (string), `isPlayerDefeated` (bool), `jackpotValue` (int) |
| Current situation | `currentMap`, `currentArea`, `currentDistance`, `steps`, `stepsToNextEvent`, `playerExperience`, `spiritPower` (int), `battleSeed` (`int[3]`), `totalBattles`, `totalWins` (int), `ddockDigimon` (`string[4]`), `lostSpirits` (`List<string>`) |
| Progress | `digimonLevel` (`Dictionary<string,int>`), `digicodeUnlocked` (`Dictionary<string,bool>`), `areasCompleted` (`bool[9][]`) |
| Adventure | `bosses` (`string[9][]`), `semibossGroup` (`int[9]`) |

`EncryptedPlayerPrefs.cs` (113 LOC) is **dead weight for the port**. It is a copy-pasted community snippet (credited to "Sven Magnus") that stores an MD5 checksum alongside each `PlayerPrefs` value to detect tampering. It is not referenced anywhere by `SavedGame.cs` — `SavedGame` calls plain `PlayerPrefs` directly. Even if it were live, the threat model (a user editing their own save on their own watch) does not exist for a personal sideload, and `Toybox.Cryptography` MD5 work per save would be pure cost. **Drop it.**

### Dimensions, from the shipped data

Measured from `Assets/Resources/digimonDB.json` and `worlds.json`:

- **593** Digimon; mean name length **10.2** chars, max 24
- **9** worlds; **52** areas total (12/1/12/1/10/3/8/1/4)
- **55** boss slots total after `Fill` semibosses are appended and the player's own spirit is removed from world 0
- **104** Digimon with a spirit type (upper bound on `lostSpirits`)
- Max stored `digimonLevel` value is **51** (`MaxExtraLevel + 1`; computed from `Digimon.MaxExtraLevel` over the whole DB) → **fits in one byte**

### Measured reference: a real save file

The checkout contains an actual save at the repo root, `game0.disabled` (a `DeleteSavedGame()` rename of `game0.digivice`): **4,328 bytes**. Its string table contains 48 unique Digimon names, i.e. an early-game save with boss assignment done and a handful of Digimon owned. Of those 4,328 bytes, roughly 1.7–1.9 KB is `BinaryFormatter` type metadata — the assembly header, the 26 field-name strings, and four ~160–230-byte fully-qualified generic type names (`System.Collections.Generic.Dictionary\`2[[System.String, mscorlib, Version=4.0.0.0, …]]` and friends). Actual game payload: **~2.4–2.6 KB** at that stage of progress.

(Note this file predates `lostSpirits` — its header declares 25 fields, not 26.)

### Port sizing

**(A) Naive port — dictionaries keyed by Digimon name.** Worst case (all 593 Digimon known and code-unlocked), with a conservative per-element overhead assumption:

| Field | Estimate |
|---|---|
| `digimonLevel` — 593 × (~13 B key + ~5 B value + ~4 B slot) | ~13 KB |
| `digicodeUnlocked` — 593 × ~19 B | ~11 KB |
| `bosses` — 55 names | ~0.8 KB |
| `lostSpirits` — up to 104 names | ~1.5 KB |
| `areasCompleted`, `ddockDigimon`, scalars | ~0.5 KB |
| **Total** | **~27 KB per slot** |

Under the device XML's 32 KB per-value cap, but **over** the Core Topics 8 KB figure, and four slots (~108 KB) would nearly exhaust the conservative 128 KB total. This shape forces chunking across keys and burns budget on repeated name strings. Reject it.

**(B) Recommended — one packed `ByteArray` per slot.** Digimon are referenced by their index in `digimonDB.json` (0–592, 2 bytes, or 10 bits) rather than by name:

| Field | Encoding | Bytes |
|---|---|---|
| format version + `gameChar` + flag bits (`cheatsUsed`, `isPlayerInsured`, `isLeaverBusterActive`, `isPlayerDefeated`) | 1 + 1 + 1 | 3 |
| `name` | length-prefixed, ≤16 chars | 17 |
| `pendingEvent`, `currentMap`, `currentArea` | u8 ×3 | 3 |
| `leaverBusterDigimonLoss` | u16 index | 2 |
| `leaverBusterExpLoss`, `jackpotValue`, `currentDistance`, `steps`, `stepsToNextEvent`, `playerExperience`, `spiritPower`, `totalBattles`, `totalWins` | i32 ×9 | 36 |
| `battleSeed` | i32 ×3 | 12 |
| `ddockDigimon` | u16 ×4 | 8 |
| `digimonLevel` | u8 ×593 (0 = locked) | 593 |
| `digicodeUnlocked` | bitfield, ceil(593/8) | 75 |
| `areasCompleted` | bitfield, ceil(52/8) | 7 |
| `bosses` | 9 length bytes + 55 × u16 | 119 |
| `semibossGroup` | u8 ×9 | 9 |
| `lostSpirits` | 1 count byte + ≤104 × u16 | ≤209 |
| **Total, worst case** | | **~1,100 B (~1.1 KB)** |

Essentially fixed-size: only `lostSpirits` varies, and a typical slot lands ~900 B–1.1 KB. `digicodeUnlocked` could fold into the high bit of the level byte (levels only reach 51) to shave 75 B, but there is no need.

### How many slots fit

| Budget | Slots at 1.1 KB |
|---|---|
| Core Topics conservative total (128 KB) | ~116 |
| `venu445mm` `appStorageCapacity` (10 MB) | thousands |
| Per-key cap, 8 KB (conservative) | 1 slot per key — never pack slots together |

Storage is **not** the binding constraint. The constraint is UI (a slot picker on a 454 px round display) and the 768 KB RAM budget shared with sprites and the animation VM. **Recommendation: 3–4 slots**, matching the original's practical usage, each under its own Storage key (`"save0"`, `"save1"`, …), plus a small separate `"slots"` index key holding the `BriefSavedGame` summary (name, character, derived level) for the picker so listing slots costs **one** file-system hit rather than N.

Note `BriefSavedGame` derives level as `floor(pow(experience, 1/3))` — so the index key only needs name + `gameChar` + `playerExperience` per slot: ~24 B × 4 ≈ 100 B.

---

## 6. Open items to verify empirically

Undocumented; must be measured before the save format is frozen.

1. **`ByteArray` in Storage on `venu445mm`.** Round-trip a 1 KB `ByteArray` through `setValue`/`getValue` in the simulator and on hardware. The API reference lists it in `ValueType`; the Core Topics article does not.
2. **Real total quota.** Fill until `Lang.StorageFullException`. Confirm whether `appStorageCapacity` (10 MB) is what is enforced.
3. **Real per-value cap.** Binary-search the largest value that writes: 8 KB or 32 KB.
4. **Write latency.** Time `setValue` of a 1.1 KB `ByteArray` against the frame budget. If it is a multi-frame stall, saves must be scheduled outside the render loop (e.g. immediately before a view transition, under a "Saving…" frame).
5. **Re-sideload durability.** Sideload, save, rebuild, re-sideload with an identical `.prg` name, confirm the slot survives. Then confirm a renamed `.prg` starts fresh — so the failure mode is known rather than discovered late.
6. **`Storage.setValue()` firmware reliability** on Venu 4 specifically, given the open bug reports on Venu 3 / FR965 / FR265.

---

## Sources

### Official Garmin documentation
- Connect IQ Core Topics — Persisting Data: https://developer.garmin.com/connect-iq/core-topics/persisting-data/ (content served from https://developer.garmin.com/connect-iq/articles/core-topics/Persisting_Data.html)
- Connect IQ Core Topics — Properties and App Settings: https://developer.garmin.com/connect-iq/core-topics/properties-and-app-settings/ (content: https://developer.garmin.com/connect-iq/articles/core-topics/Properties_and_App_Settings.html)
- Connect IQ API reference — `Toybox.Application.Storage`: https://developer.garmin.com/connect-iq/api-docs/Toybox/Application/Storage.html

### Garmin developer forum (community; no Garmin-staff post found that quantifies a per-device quota)
- storage and properties: https://forums.garmin.com/developer/connect-iq/f/discussion/325141/storage-and-properties/1578479
- Application.Storage vs. Object Store (and User Settings): https://forums.garmin.com/developer/connect-iq/f/discussion/231825/application-storage-vs-object-store-and-user-settings
- Where/when to use Application.storage getvalue/setvalue: https://forums.garmin.com/developer/connect-iq/f/discussion/348257/where-when-to-use-application-storage-getvalue-setvalue
- Flash memory wear out upon using Storage.set() in high rate background applications: https://forums.garmin.com/developer/connect-iq/f/discussion/320690/flash-memory-wear-out-upon-using-storage-set-in-high-rate-background-applications/1555080
- Persistent Storage / App.Setproperty - where is data stored?: https://forums.garmin.com/developer/connect-iq/f/discussion/1191/persistent-storage-app-setproperty---where-is-data-stored
- Storage available: https://forums.garmin.com/developer/connect-iq/f/discussion/2661/storage-available
- Storage/Memory Limits: https://forums.garmin.com/developer/connect-iq/f/discussion/259/storage-memory-limits
- Bug report — System Error calling Storage.setValue() latest FW: https://forums.garmin.com/developer/connect-iq/i/bug-reports/system-error-calling-storage-setvalue-lastest-fw
- Bug report — File Not Found Error after calling Storage.setValue on some devices: https://forums.garmin.com/developer/connect-iq/i/bug-reports/file-not-found-error-after-calling-storage-setvalue-on-some-devices
- Connect IQ data field settings reset after update: https://forums.garmin.com/sports-fitness/sports-fitness/f/forerunner-935/148495/connect-iq-data-field-settings-reset-after-update

### Local — Connect IQ SDK 9.2.0 / device profile
- `~/Library/Application Support/Garmin/ConnectIQ/Devices/venu445mm/venu445mm.api.debug.xml` — Storage/Properties module and function entries, `StorageFullException`, `Properties.InvalidKeyException`, and the doc comments quoted above
- `~/Library/Application Support/Garmin/ConnectIQ/Devices/venu445mm/simulator.json` — `appStorageCapacity: 10485760`
- `~/Library/Application Support/Garmin/ConnectIQ/Devices/venu445mm/compiler.json` — `memoryLimit: 786432` (watchApp), `maxPrgFilespace: 67108864`, `codePageSize: 4096`; no storage-quota key
- `~/Library/Application Support/Garmin/ConnectIQ/Devices/*/simulator.json` — 173 profiles surveyed for `appStorageCapacity` distribution
- `~/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.2.0-2026-06-09-92a1605b2/bin/ConnectIQ.app/Contents/MacOS/simulator` — `appStorageCapacity` string colocated with `.STR`, `Modify Object Store`, `Sim::ObjectStoreWindow`, `TVM_cls_Toybox_Lang_StorageFullException`

### Local — D-Tector v2 source checkout
Checkout root: `/private/tmp/claude-502/-Users-tiscomacnb2227-Workspace-garmin-d-tector/2cfbef5b-836a-439a-b7ec-c70531a6572c/scratchpad/dtector` (from https://github.com/kaisadilla/D-Tector-v2)

- `Assets/Scripts/SavedGame/SavedGame.cs` — `SavedGameFile` field list, save-on-every-setter pattern, `BinaryFormatter` I/O, `BriefSavedGame`
- `Assets/Scripts/SavedGame/EncryptedPlayerPrefs.cs` — MD5-checksummed `PlayerPrefs` wrapper; unreferenced by `SavedGame.cs`
- `Assets/Scripts/Logic/WorldManager.cs` — `SetupWorlds()`, shapes of `areasCompleted`, `bosses`, `semibossGroup`
- `Assets/Scripts/Logic/LogicManager.cs` — sparse population of `digimonLevel` / `digicodeUnlocked`, `lostSpirits`, `ddockDigimon`
- `Assets/Scripts/Logic/Models/Digimon.cs` — `MaxExtraLevel`, `Stage` / `SpiritType` enums
- `Assets/Resources/digimonDB.json` — 593 entries, name lengths, `baseLevel`, `stage`, `spiritType`
- `Assets/Resources/worlds.json` — 9 worlds, 52 areas, 55 boss slots, semiboss groups
- `game0.disabled` — a real 4,328-byte `BinaryFormatter` save file at the repo root
