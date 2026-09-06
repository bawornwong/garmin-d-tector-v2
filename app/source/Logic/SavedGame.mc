import Toybox.Lang;

// port of SavedGame/SavedGame.cs
//
// The original is a static class over Unity's PlayerPrefs, where every
// property both reads and WRITES a key immediately -- 430 lines of
// `get => EncryptedPlayerPrefs.GetInt(...)` pairs. That shape is wrong here
// twice over: Connect IQ's Storage costs about 1 ms per KB written, and the
// save is one positional blob rather than a key per field (ADR 8).
//
// So the record lives in RAM (SaveRecord, written by SaveFormat) and this is
// the accessor the logic layer talks to. `commit()` is the checkpoint: the
// original's every-assignment write becomes an explicit save at the points
// the game already treats as safe.
class SavedGame {
    var record as SaveRecord;
    var _format as SaveFormat;
    var _slot as Number;
    var _dirty as Boolean = false;

    function initialize(format as SaveFormat, slot as Number, rec as SaveRecord) {
        _format = format;
        _slot = slot;
        record = rec;
    }

    // Every setter marks the record dirty rather than writing through, which
    // is what makes a checkpoint cheap enough to take.
    function touch() as Void {
        _dirty = true;
    }

    function isDirty() as Boolean {
        return _dirty;
    }

    function commit() as Void {
        if (!_dirty) { return; }
        _format.writeSlot(_slot, record);
        _dirty = false;
    }

    // --- the properties the ported logic reads, in SavedGame.cs order ---

    function playerName() as String { return record.name; }
    function playerChar() as Number { return record.gameChar; }

    function playerExperience() as Number { return record.playerExperience; }
    function setPlayerExperience(v as Number) as Void {
        record.playerExperience = v;
        touch();
    }

    function spiritPower() as Number { return record.spiritPower; }
    function setSpiritPower(v as Number) as Void {
        record.spiritPower = v;
        touch();
    }

    function totalBattles() as Number { return record.totalBattles; }
    function setTotalBattles(v as Number) as Void {
        record.totalBattles = v;
        touch();
    }

    function totalWins() as Number { return record.totalWins; }
    function setTotalWins(v as Number) as Void {
        record.totalWins = v;
        touch();
    }

    function currentDistance() as Number { return record.currentDistance; }
    function setCurrentDistance(v as Number) as Void {
        record.currentDistance = v;
        touch();
    }

    function steps() as Number { return record.steps; }
    function setSteps(v as Number) as Void {
        record.steps = v;
        touch();
    }

    // -1 means the dock is empty; the value is a Digimon index (ADR 7).
    function ddockDigimon(ddock as Number) as Number {
        return record.ddockDigimon[ddock];
    }
    function setDDockDigimon(ddock as Number, digimonIndex as Number) as Void {
        record.ddockDigimon[ddock] = digimonIndex;
        touch();
    }

    // The extra levels a Digimon the player owns has gained. 0 means owned at
    // base level; the original stores -1 for "not owned".
    function digimonExtraLevel(digimonIndex as Number) as Number {
        return record.digimonLevel[digimonIndex];
    }
    function setDigimonExtraLevel(digimonIndex as Number, v as Number) as Void {
        record.digimonLevel[digimonIndex] = v;
        touch();
    }

    function digicodeUnlocked(digimonIndex as Number) as Boolean {
        return record.digicodeUnlocked[digimonIndex];
    }
    function setDigicodeUnlocked(digimonIndex as Number, v as Boolean) as Void {
        record.digicodeUnlocked[digimonIndex] = v;
        touch();
    }
}
