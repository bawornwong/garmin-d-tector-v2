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

    // Replacing the record wholesale: a new game starts from a default record
    // and a deleted one leaves nothing behind, and both need the same slot
    // and format the old record had.
    function replaceRecord(rec as SaveRecord) as Void {
        record = rec;
        _dirty = true;
    }

    function eraseSlot() as Void {
        _format.deleteSlot(_slot);
        _dirty = false;
    }

    function commit() as Void {
        if (!_dirty) { return; }
        _format.writeSlot(_slot, record);
        _dirty = false;
    }

    // --- the properties the ported logic reads, in SavedGame.cs order ---

    function playerName() as String { return record.name; }
    function playerChar() as Number { return record.gameChar; }

    function isPlayerInsured() as Boolean { return record.isPlayerInsured; }
    function setPlayerInsured(v as Boolean) as Void {
        record.isPlayerInsured = v;
        touch();
    }

    // The three seeds a game is created with; a battle draws one of them so
    // the enemy's attack sequence is fixed for that battle.
    function randomSeed(index as Number) as Number {
        return record.battleSeed[index];
    }

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

    function stepsToNextEvent() as Number { return record.stepsToNextEvent; }
    function setStepsToNextEvent(v as Number) as Void {
        record.stepsToNextEvent = v;
        touch();
    }

    function savedEvent() as Number { return record.pendingEvent; }
    function setSavedEvent(v as Number) as Void {
        record.pendingEvent = v;
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

    // SavedGame.GetDigimonLevel: the RAW level, where 0 means the player does
    // not have the Digimon at all and 1 means they have it at its base level.
    // LogicManager is where that becomes "unlocked" and "extra level" -- the
    // off-by-one lives there in the original too.
    function digimonLevel(digimonIndex as Number) as Number {
        // The original is a DICTIONARY read with a miss guard:
        //
        //     if (lg.digimonLevel.TryGetValue(digimon, out int level)) return level;
        //     return 0;
        //
        // ADR 7 turns the key from a name into an index, and an array index
        // has no equivalent of a dictionary miss -- so the guard has to be
        // written out, or it is lost in translation. It is load-bearing:
        // an empty D-Dock holds "" in the original and -1 here, and Battle
        // reads the level of whatever the chosen dock holds. Without this,
        // choosing an empty D-Dock crashed with an Array Out Of Bounds
        // (found by driving the release build through a scripted battle).
        // 0 is exactly what the original returns for that case, and
        // getDigimonExtraLevel's -1 follows from it as it does there.
        if (digimonIndex < 0 || digimonIndex >= record.digimonLevel.size()) {
            return 0;
        }
        return record.digimonLevel[digimonIndex];
    }
    function setDigimonLevel(digimonIndex as Number, v as Number) as Void {
        record.digimonLevel[digimonIndex] = v;
        touch();
    }

    // The spirits the player has lost, as Digimon indices. SaveFormat caps
    // the list at 20; the cap is inferred rather than verified against the
    // game's own maximum (SPEC section 8).
    function lostSpirits() as Array<Number> {
        return record.lostSpirits;
    }

    function addLostSpirit(digimonIndex as Number) as Void {
        record.lostSpirits.add(digimonIndex);
        touch();
    }

    function removeLostSpiritAt(index as Number) as Void {
        var head = record.lostSpirits.slice(0, index);
        record.lostSpirits = head.addAll(record.lostSpirits.slice(index + 1, null));
        touch();
    }

    function currentWorld() as Number { return record.currentMap; }
    function setCurrentWorld(v as Number) as Void {
        record.currentMap = v;
        touch();
    }

    function currentArea() as Number { return record.currentArea; }
    function setCurrentArea(v as Number) as Void {
        record.currentArea = v;
        touch();
    }

    // The positional arrays SaveFormat packs across all worlds at once; the
    // per-world offset comes from WorldManager, which is where the world
    // layout lives.
    function areaCompleted(flatIndex as Number) as Boolean {
        return record.areasCompleted[flatIndex];
    }
    function setAreaCompleted(flatIndex as Number, v as Boolean) as Void {
        record.areasCompleted[flatIndex] = v;
        touch();
    }

    function bossAtSlot(flatIndex as Number) as Number {
        return record.bosses[flatIndex];
    }
    function setBossAtSlot(flatIndex as Number, digimonIndex as Number) as Void {
        record.bosses[flatIndex] = digimonIndex;
        touch();
    }

    function semibossGroup(world as Number) as Number {
        return record.semibossGroup[world];
    }
    function setSemibossGroup(world as Number, group as Number) as Void {
        record.semibossGroup[world] = group;
        touch();
    }

    function digicodeUnlocked(digimonIndex as Number) as Boolean {
        // Same dictionary-miss guard as digimonLevel above, and for the same
        // reason: the original returns false for a name it does not hold.
        if (digimonIndex < 0 || digimonIndex >= record.digicodeUnlocked.size()) {
            return false;
        }
        return record.digicodeUnlocked[digimonIndex];
    }
    function setDigicodeUnlocked(digimonIndex as Number, v as Boolean) as Void {
        record.digicodeUnlocked[digimonIndex] = v;
        touch();
    }
}
