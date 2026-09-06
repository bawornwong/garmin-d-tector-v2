import Toybox.Lang;
import Toybox.Math;
import Toybox.System;

// port of Logic/Data/Database.cs
//
// The original parses three JSON files at startup and keeps 593 Digimon
// objects, 593 DigimonRarity objects and the worlds alive for the whole run.
// Here the rows already live in the packed blob GameData reads (ADR 6), and
// the rarity table was folded into each row by the packer, so:
//
//   - a Digimon object is built ON DEMAND from GameData and kept in a small
//     LRU. Materialising all 593 up front costs about 1,800 objects against a
//     768 KB budget, for a screen that shows one at a time.
//   - every query that only needs numbers (rarity, base level, stage) reads
//     them straight out of the blob without building anything.
//   - lookups are by index, not by name (ADR 7). The eight literal names the
//     source uses -- the two default Digimon and the six player spirits --
//     are resolved at BUILD time by tools/gen_wellknown.py. Resolving them at
//     runtime tripped the watchdog on the first lookup: a scan of 593 rows,
//     each one a base64-backed string decode.
class Database {
    const CACHE_CAP = 8;

    var _data as GameData;
    var _cacheIndex as Array<Number> = [];
    var _cacheDigimon as Array<Digimon> = [];

    // Resolved once from Constants and the PlayerSpirit table, so that
    // nothing does a name compare at runtime.
    var defaultDigimon as Number = -1;
    var defaultSpiritDigimon as Number = -1;
    var playerSpirit as Array<Number> = [];   // by GameChar

    function initialize(data as GameData) {
        _data = data;
    }

    // Database.LoadDatabases: everything it loaded is already in the blob,
    // and the names it resolved are already indices (Data/WellKnown.mc), so
    // startup does no work at all.
    function load() as Void {
        defaultDigimon = Kaisa.WellKnown.DEFAULT_DIGIMON;
        defaultSpiritDigimon = Kaisa.WellKnown.DEFAULT_SPIRIT_DIGIMON;
        playerSpirit = Kaisa.WellKnown.PLAYER_SPIRIT;
    }

    function count() as Number {
        return _data.digimonCount();
    }

    // Database.GetDigimon(string). Nothing on a frame or startup path may
    // call this: it decodes 593 strings, which is a watchdog trip on its own.
    // It survives for tools and for the debug console.
    (:debug)
    function indexOfName(wantName as String) as Number {
        var n = count();
        for (var i = 0; i < n; i += 1) {
            if (_data.name(i).equals(wantName)) { return i; }
        }
        return -1;
    }

    // Database.Digimons excludes rows marked disabled; callers that walk the
    // whole database must skip them the same way.
    function isDisabled(index as Number) as Boolean {
        return _data.isDisabled(index);
    }

    function getDigimon(index as Number) as Digimon? {
        if (index < 0 || index >= count()) { return null; }
        for (var i = 0; i < _cacheIndex.size(); i += 1) {
            if (_cacheIndex[i] == index) { return _cacheDigimon[i]; }
        }
        var d = buildDigimon(index);
        _cacheIndex.add(index);
        _cacheDigimon.add(d);
        if (_cacheIndex.size() > CACHE_CAP) {
            _cacheIndex = _cacheIndex.slice(1, null);
            _cacheDigimon = _cacheDigimon.slice(1, null);
        }
        return d;
    }

    function buildDigimon(index as Number) as Digimon {
        var stats = new CombatStats(_data.hp(index), _data.en(index),
                                    _data.cr(index), _data.ab(index));
        // The packer stores boss stats only for the rows that have them; the
        // rest fall back to the regular stats inside Digimon's constructor,
        // exactly as the original's null-coalescing assignment does.
        var bossStats = null;
        if (_data.hasBossStats(index)) {
            var bs = _data.bossStats(index);
            if (bs != null) {
                bossStats = new CombatStats(bs[0], bs[1], bs[2], bs[3]);
            }
        }
        return new Digimon(index, _data.number(index), _data.order(index),
                           _data.name(index), _data.stage(index),
                           _data.spiritType(index), _data.abilityIndex(index),
                           _data.element(index), _data.evolutionIndex(index),
                           _data.isDisabled(index), _data.baseLevel(index),
                           stats, bossStats, _data.isPseudo(index),
                           _data.code(index), _data.rarity(index),
                           _data.exclusive(index));
    }

    // DigimonRarity.EligibleForBattle
    function eligibleForBattle(index as Number) as Boolean {
        var r = _data.rarity(index);
        return r == Kaisa.RARITY_COMMON || r == Kaisa.RARITY_RARE
            || r == Kaisa.RARITY_EPIC || r == Kaisa.RARITY_LEGENDARY;
    }

    function getDigimonRarity(index as Number) as Number {
        if (index < 0 || index >= count()) { return Kaisa.RARITY_NONE; }
        return _data.rarity(index);
    }

    // Database.GetRandomDigimonForBattle: a weighted pick over every
    // battle-eligible Digimon whose base level is within a level-dependent
    // threshold of the player's.
    //
    // SOURCE BUG, reproduced: the guard reads
    //     if (thisDigimon != null || thisDigimon.disabled)
    // -- an OR where the intent was "not null AND not disabled", so a disabled
    // row is never actually excluded here. Since exactly one row in
    // digimonDB.json is disabled and the null branch cannot be reached from
    // the rarity table, the observable behaviour is "disabled rows can be
    // picked", and that is what this does (ADR 2).
    function getRandomDigimonForBattle(playerLevel as Number) as Digimon? {
        var candidates = [] as Array<Number>;
        var weightList = [] as Array<Float>;
        var totalWeight = 0.0;

        var threshold;
        if (playerLevel <= 2) { threshold = 3; }
        else if (playerLevel <= 4) { threshold = 4; }
        else if (playerLevel <= 10) { threshold = 7; }
        else if (playerLevel <= 60) { threshold = 10; }
        else if (playerLevel <= 80) { threshold = 20; }
        else { threshold = 40; }

        var n = count();
        for (var i = 0; i < n; i += 1) {
            if (!eligibleForBattle(i)) { continue; }
            var baseLevel = _data.baseLevel(i);
            if (baseLevel > (playerLevel - threshold) && baseLevel < (playerLevel + threshold)) {
                candidates.add(i);

                var baseWeight = 0.0;
                var r = _data.rarity(i);
                if (r == Kaisa.RARITY_COMMON) { baseWeight = 10.0; }
                else if (r == Kaisa.RARITY_RARE) { baseWeight = 6.0; }
                else if (r == Kaisa.RARITY_EPIC) { baseWeight = 3.0; }
                else if (r == Kaisa.RARITY_LEGENDARY) { baseWeight = 1.0; }

                var diff = playerLevel - baseLevel;
                if (diff < 0) { diff = -diff; }
                var thisWeight = (1.1 - (diff.toFloat() / threshold)) * baseWeight;
                weightList.add(thisWeight);
                totalWeight += thisWeight;
            }
        }

        var fChosen = Kaisa.Rand.rangeFloat(0.0, totalWeight);
        var weightSum = 0.0;
        for (var i = 0; i < weightList.size(); i += 1) {
            weightSum += weightList[i];
            if (weightSum > fChosen) {
                return getDigimon(candidates[i]);
            }
        }
        return null;
    }

    // Database.GetAllDigimonOfRarity, returning indices rather than objects:
    // both call sites pick one at random and then read a single field off it.
    function getAllDigimonOfRarity(rarity as Number, maximumLevel as Number) as Array<Number> {
        var candidates = [] as Array<Number>;
        var n = count();
        for (var i = 0; i < n; i += 1) {
            if (_data.rarity(i) == rarity && _data.baseLevel(i) <= maximumLevel) {
                candidates.add(i);
            }
        }
        return candidates;
    }

    // Database.GetEraseChance: the chance a Digimon is erased, by rarity.
    function getEraseChance(index as Number) as Float {
        if (index == defaultDigimon || index == defaultSpiritDigimon) {
            return 0.0;
        }

        var rarity = getDigimonRarity(index);
        if (rarity == Kaisa.RARITY_COMMON) { return 0.75; }
        if (rarity == Kaisa.RARITY_RARE) { return 0.50; }
        if (rarity == Kaisa.RARITY_EPIC) { return 0.25; }
        if (rarity == Kaisa.RARITY_LEGENDARY) { return 0.10; }
        if (rarity == Kaisa.RARITY_BOSS) {
            if (_data.stage(index) == Kaisa.STAGE_SPIRIT) {
                var st = _data.spiritType(index);
                if (st == Kaisa.SPIRIT_HUMAN || st == Kaisa.SPIRIT_ANIMAL) { return 0.50; }
                return 0.0;
            }
            return 0.10;
        }
        return 0.0;
    }

    // Database.GetDigimonFromCode. The codes are five characters, stored one
    // row per Digimon in the packed blob, and the CodeInput app hits this once
    // per entered code -- a single user action, not a frame, but it is still
    // 593 string decodes and will need comparing at the byte level before
    // CodeInput ships (the same watchdog that caught indexOfName).
    function indexOfCode(code as String) as Number {
        var wanted = code.toLower();
        var n = count();
        for (var i = 0; i < n; i += 1) {
            if (_data.code(i).equals(wanted)) { return i; }
        }
        return -1;
    }
}
