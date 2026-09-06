import Toybox.Application.Storage;
import Toybox.Lang;
import Toybox.StringUtil;
import Toybox.System;

// Positional save record (ADR 8, ticket 10): every field of the source's
// `SavedGameFile` (SavedGame.cs:354), packed by Digimon INDEX rather than
// name -- 593 bytes for `digimonLevel` instead of the ~27 KB a name-keyed
// dictionary would cost, matching the same row order as the sprite and
// data tables (ADR 7).
//
// Layout (sizes for the current 593-Digimon, 9-world database; the boss
// and semiboss slot counts, and the area count, are read from GameData at
// runtime rather than hardcoded, so this stays correct if the database
// ever changes):
//
//   u8    version
//   u8    nameLen, name[16]
//   u8    gameChar
//   u8    flags (cheatsUsed | insured<<1 | leaverBusterActive<<2 | defeated<<3)
//   u8    pendingEvent
//   u32   leaverBusterExpLoss
//   s16   leaverBusterDigimonLoss
//   u32   jackpotValue
//   u8    currentMap
//   u8    currentArea
//   u32   currentDistance
//   u32   steps
//   u32   stepsToNextEvent
//   u32   playerExperience
//   u8    spiritPower
//   u32 x3 battleSeed
//   u32   totalBattles
//   u32   totalWins
//   s16 x4 ddockDigimon
//   u8    lostSpiritCount, s16[lostSpiritCount] (cap 20)
//   u8[digimonCount]                digimonLevel, positional
//   bit[digimonCount]               digicodeUnlocked, positional
//   bit[areaTotal]                  areasCompleted
//   s16[bossListTotal]              bosses (the assigned list per world, laid
//                                     out world by world; a world's slice is
//                                     its slot count plus the biggest semiboss
//                                     group it can be filled with)
//   s16[worldCount]                 semibossGroup (the chosen group per world)
//
// NOTE: the source assigns `bosses`/`semibossGroup` "from the Database when
// the game was first created" (SavedGameFile's own comment) via logic in
// WorldManager.cs that this build session did not examine. createDefault()
// below seeds both from the STATIC per-world boss list already packed into
// the data blob (tools/pack_data.py's `worlds` section) as a placeholder --
// this needs checking against WorldManager.cs before it is trusted.
// Bumped when the byte layout changes. Version 2 resized the world arrays:
// `bosses` is now the assigned LIST per world (slots plus the biggest semiboss
// group that can fill it) and `semibossGroup` is one entry per world, matching
// what WorldManager.SetupWorlds actually writes.
const VERSION = 2;
// The cap on the saved lost-spirit list, which bounds the record's size. It
// used to be 20 -- the ten human and ten animal spirits -- but a spirit is
// lost whenever the player was fighting with one, whatever kind it is, and
// each can be in the list at most once because losing it locks it. The real
// ceiling is therefore the number of rows at stage Spirit, which the data
// says is 45 and which gen_wellknown.py counts rather than anyone typing.
const MAX_NAME = 16;

class SaveRecord {
    var version as Number = VERSION;
    var name as String = "";
    var gameChar as Number = 0;
    var cheatsUsed as Boolean = false;
    var isPlayerInsured as Boolean = false;
    var isLeaverBusterActive as Boolean = false;
    var isPlayerDefeated as Boolean = false;
    var pendingEvent as Number = 0;
    var leaverBusterExpLoss as Number = 0;
    var leaverBusterDigimonLoss as Number = -1;
    var jackpotValue as Number = 0;
    var currentMap as Number = 0;
    var currentArea as Number = 0;
    var currentDistance as Number = 0;
    var steps as Number = 0;
    var stepsToNextEvent as Number = 0;
    var playerExperience as Number = 0;
    var spiritPower as Number = 0;
    var battleSeed as Array<Number> = [0, 0, 0];
    var totalBattles as Number = 0;
    var totalWins as Number = 0;
    var ddockDigimon as Array<Number> = [-1, -1, -1, -1];
    var lostSpirits as Array<Number> = [];
    var digimonLevel as Array<Number> = [];       // positional, size = digimonCount
    var digicodeUnlocked as Array<Boolean> = [];  // positional, size = digimonCount
    var areasCompleted as Array<Boolean> = [];    // positional, size = areaTotal
    var bosses as Array<Number> = [];             // positional, size = bossListTotal
    var semibossGroup as Array<Number> = [];      // one per world
}

class SaveFormat {
    var _data as GameData;

    function initialize(data as GameData) {
        _data = data;
    }

    function createDefault(playerName as String) as SaveRecord {
        var r = new SaveRecord();
        r.name = playerName;
        var n = _data.digimonCount();
        r.digimonLevel = [];
        r.digicodeUnlocked = [];
        for (var i = 0; i < n; i += 1) {
            r.digimonLevel.add(0);
            r.digicodeUnlocked.add(false);
        }
        var totals = _data.worldTotals();
        r.areasCompleted = [];
        for (var i = 0; i < totals[0]; i += 1) { r.areasCompleted.add(false); }
        r.bosses = [];
        for (var i = 0; i < totals[1]; i += 1) { r.bosses.add(-1); }
        r.semibossGroup = [];
        for (var i = 0; i < totals[2]; i += 1) { r.semibossGroup.add(-1); }
        return r;
    }

    function encode(r as SaveRecord) as ByteArray {
        var b = []b;
        addU8(b, r.version);
        var nameBytes = stringBytes(r.name, MAX_NAME);
        addU8(b, nameBytes.size());
        for (var i = 0; i < MAX_NAME; i += 1) {
            b.add((i < nameBytes.size()) ? nameBytes[i] : 0);
        }
        addU8(b, r.gameChar);
        var flags = (r.cheatsUsed ? 1 : 0) | (r.isPlayerInsured ? 2 : 0)
            | (r.isLeaverBusterActive ? 4 : 0) | (r.isPlayerDefeated ? 8 : 0);
        addU8(b, flags);
        addU8(b, r.pendingEvent);
        addU32(b, r.leaverBusterExpLoss);
        addS16(b, r.leaverBusterDigimonLoss);
        addU32(b, r.jackpotValue);
        addU8(b, r.currentMap);
        addU8(b, r.currentArea);
        addU32(b, r.currentDistance);
        addU32(b, r.steps);
        addU32(b, r.stepsToNextEvent);
        addU32(b, r.playerExperience);
        addU8(b, r.spiritPower);
        addU32(b, r.battleSeed[0]);
        addU32(b, r.battleSeed[1]);
        addU32(b, r.battleSeed[2]);
        addU32(b, r.totalBattles);
        addU32(b, r.totalWins);
        for (var i = 0; i < 4; i += 1) { addS16(b, r.ddockDigimon[i]); }
        var lost = r.lostSpirits.size();
        if (lost > Kaisa.WellKnown.SPIRIT_ROWS) { lost = Kaisa.WellKnown.SPIRIT_ROWS; }
        addU8(b, lost);
        for (var i = 0; i < lost; i += 1) { addS16(b, r.lostSpirits[i]); }

        for (var i = 0; i < r.digimonLevel.size(); i += 1) { addU8(b, r.digimonLevel[i]); }
        addBits(b, r.digicodeUnlocked);
        addBits(b, r.areasCompleted);
        for (var i = 0; i < r.bosses.size(); i += 1) { addS16(b, r.bosses[i]); }
        for (var i = 0; i < r.semibossGroup.size(); i += 1) { addS16(b, r.semibossGroup[i]); }

        return b;
    }

    function decode(bytes as ByteArray, digimonCount as Number, areaTotal as Number,
                     bossTotal as Number, semibossTotal as Number) as SaveRecord {
        var r = new SaveRecord();
        var o = 0;
        r.version = bytes[o]; o += 1;
        var nameLen = bytes[o]; o += 1;
        r.name = bytesToString(bytes, o, nameLen);
        o += MAX_NAME;
        r.gameChar = bytes[o]; o += 1;
        var flags = bytes[o]; o += 1;
        r.cheatsUsed = (flags & 1) != 0;
        r.isPlayerInsured = (flags & 2) != 0;
        r.isLeaverBusterActive = (flags & 4) != 0;
        r.isPlayerDefeated = (flags & 8) != 0;
        r.pendingEvent = bytes[o]; o += 1;
        r.leaverBusterExpLoss = readU32(bytes, o); o += 4;
        r.leaverBusterDigimonLoss = readS16(bytes, o); o += 2;
        r.jackpotValue = readU32(bytes, o); o += 4;
        r.currentMap = bytes[o]; o += 1;
        r.currentArea = bytes[o]; o += 1;
        r.currentDistance = readU32(bytes, o); o += 4;
        r.steps = readU32(bytes, o); o += 4;
        r.stepsToNextEvent = readU32(bytes, o); o += 4;
        r.playerExperience = readU32(bytes, o); o += 4;
        r.spiritPower = bytes[o]; o += 1;
        r.battleSeed = [readU32(bytes, o), readU32(bytes, o + 4), readU32(bytes, o + 8)];
        o += 12;
        r.totalBattles = readU32(bytes, o); o += 4;
        r.totalWins = readU32(bytes, o); o += 4;
        r.ddockDigimon = [];
        for (var i = 0; i < 4; i += 1) { r.ddockDigimon.add(readS16(bytes, o)); o += 2; }
        var lost = bytes[o]; o += 1;
        r.lostSpirits = [];
        for (var i = 0; i < lost; i += 1) { r.lostSpirits.add(readS16(bytes, o)); o += 2; }

        r.digimonLevel = [];
        for (var i = 0; i < digimonCount; i += 1) { r.digimonLevel.add(bytes[o]); o += 1; }
        var codeBits = readBits(bytes, o, digimonCount); o += bitBytes(digimonCount);
        r.digicodeUnlocked = codeBits;
        var areaBits = readBits(bytes, o, areaTotal); o += bitBytes(areaTotal);
        r.areasCompleted = areaBits;
        r.bosses = [];
        for (var i = 0; i < bossTotal; i += 1) { r.bosses.add(readS16(bytes, o)); o += 2; }
        r.semibossGroup = [];
        for (var i = 0; i < semibossTotal; i += 1) { r.semibossGroup.add(readS16(bytes, o)); o += 2; }
        return r;
    }

    // --- Storage I/O --------------------------------------------------------

    function writeSlot(slot as Number, r as SaveRecord) as Void {
        Storage.setValue("slot" + slot, encode(r));
    }

    // A slot written by an older layout is not readable: the arrays are sized
    // from the packed data, so decoding it would run off the end of the blob.
    // It is treated as absent, which is what the caller does with a missing
    // save anyway -- and the version check happens before any of the
    // length-dependent reads, so a stale slot costs one byte to reject.
    function readSlot(slot as Number) as SaveRecord? {
        var bytes = Storage.getValue("slot" + slot) as ByteArray?;
        if (bytes == null) { return null; }
        if (bytes.size() < 1 || bytes[0] != VERSION) {
            System.println("SaveFormat: slot " + slot + " is version "
                + (bytes.size() > 0 ? bytes[0] : -1) + ", expected " + VERSION);
            return null;
        }
        var totals = _data.worldTotals();
        try {
            return decode(bytes, _data.digimonCount(), totals[0], totals[1], totals[2]);
        } catch (e) {
            System.println("SaveFormat: slot " + slot + " did not decode: "
                + e.getErrorMessage());
            return null;
        }
    }

    // --- byte helpers --------------------------------------------------------

    function addU8(b as ByteArray, v as Number) as Void { b.add(v & 0xFF); }
    function addU32(b as ByteArray, v as Number) as Void {
        b.add(v & 0xFF); b.add((v >> 8) & 0xFF); b.add((v >> 16) & 0xFF); b.add((v >> 24) & 0xFF);
    }
    function addS16(b as ByteArray, v as Number) as Void {
        var u = v & 0xFFFF;
        b.add(u & 0xFF); b.add((u >> 8) & 0xFF);
    }
    function addBits(b as ByteArray, bits as Array<Boolean>) as Void {
        var i = 0;
        while (i < bits.size()) {
            var byte = 0;
            for (var k = 0; k < 8 && i < bits.size(); k += 1) {
                if (bits[i]) { byte |= (1 << k); }
                i += 1;
            }
            b.add(byte);
        }
    }
    function bitBytes(n as Number) as Number { return (n + 7) / 8; }

    function readU32(bytes as ByteArray, o as Number) as Number {
        return bytes.decodeNumber(Lang.NUMBER_FORMAT_UINT32,
            { :offset => o, :endianness => Lang.ENDIAN_LITTLE }).toNumber();
    }
    function readS16(bytes as ByteArray, o as Number) as Number {
        return bytes.decodeNumber(Lang.NUMBER_FORMAT_SINT16,
            { :offset => o, :endianness => Lang.ENDIAN_LITTLE });
    }
    function readBits(bytes as ByteArray, o as Number, n as Number) as Array<Boolean> {
        var out = [] as Array<Boolean>;
        for (var i = 0; i < n; i += 1) {
            var byte = bytes[o + i / 8];
            out.add(((byte >> (i % 8)) & 1) != 0);
        }
        return out;
    }

    function stringBytes(s as String, maxLen as Number) as Array<Number> {
        var chars = s.toUtf8Array();
        var out = [] as Array<Number>;
        for (var i = 0; i < chars.size() && i < maxLen; i += 1) { out.add(chars[i]); }
        return out;
    }
    function bytesToString(bytes as ByteArray, o as Number, len as Number) as String {
        if (len == 0) { return ""; }
        var slice = bytes.slice(o, o + len);
        return StringUtil.convertEncodedString(slice, {
            :fromRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY,
            :toRepresentation => StringUtil.REPRESENTATION_STRING_PLAIN_TEXT
        }) as String;
    }
}
