import Toybox.Lang;

const STEP_HEADER_SIZE = 163;
const STEP_HEADER_VERSION = 3;

// Fixed prefix of save version 3. A background service can read and replace
// this prefix without constructing GameData or touching the positional game
// payload that follows it.
(:background)
class StepHeader {

    var sync as StepState = new StepState();
    var gameChar as Number = -1;
    var pendingEvent as Number = 0;
    var defeated as Boolean = false;
    var distance as Number = 0;
    var stepsToEvent as Number = 0;

    function fromRecord(r as SaveRecord) as Void {
        sync = r.stepSync;
        gameChar = r.gameChar;
        pendingEvent = r.pendingEvent;
        defeated = r.isPlayerDefeated;
        distance = r.currentDistance;
        stepsToEvent = r.stepsToNextEvent;
    }

    function encode() as ByteArray {
        var b = []b;
        u8(b, STEP_HEADER_VERSION); u8(b, STEP_HEADER_SIZE);
        u64(b, sync.gameGeneration);
        u32(b, sync.gateEpoch); u32(b, sync.notifiedGateEpoch);
        u8(b, (sync.cursorInitialized ? 1 : 0) | (sync.historyGap ? 2 : 0));
        u8(b, gameChar & 0xff); u8(b, pendingEvent); u8(b, defeated ? 1 : 0);
        u32(b, distance); u32(b, stepsToEvent);
        u64(b, sync.sourceTotal); u64(b, sync.creditedSourceTotal);
        u64(b, sync.watchStepsCredited); u64(b, sync.archivedTotal);
        u32(b, sync.archivedThrough); u32(b, sync.lastInfoDay);
        u32(b, sync.lastInfoSteps); u32(b, sync.lastObservation);
        u32(b, sync.quarantineThrough);
        var count = sync.days.size();
        if (count > STEP_RECENT_DAYS) { count = STEP_RECENT_DAYS; }
        u8(b, count);
        for (var i = 0; i < STEP_RECENT_DAYS; i += 1) {
            u32(b, i < count ? sync.days[i] : 0);
            u32(b, i < count ? sync.maxima[i] : 0);
        }
        return b;
    }

    function decode(bytes as ByteArray) as Boolean {
        if (bytes.size() < STEP_HEADER_SIZE || bytes[0] != STEP_HEADER_VERSION
                || bytes[1] != STEP_HEADER_SIZE) {
            return false;
        }
        var o = 2;
        sync = new StepState();
        sync.gameGeneration = r64(bytes, o); o += 8;
        sync.gateEpoch = r32(bytes, o); o += 4;
        sync.notifiedGateEpoch = r32(bytes, o); o += 4;
        var flags = bytes[o]; o += 1;
        sync.cursorInitialized = (flags & 1) != 0;
        sync.historyGap = (flags & 2) != 0;
        gameChar = bytes[o] == 0xff ? -1 : bytes[o]; o += 1;
        pendingEvent = bytes[o]; o += 1;
        defeated = bytes[o] != 0; o += 1;
        distance = r32(bytes, o); o += 4;
        stepsToEvent = r32(bytes, o); o += 4;
        sync.sourceTotal = r64(bytes, o); o += 8;
        sync.creditedSourceTotal = r64(bytes, o); o += 8;
        sync.watchStepsCredited = r64(bytes, o); o += 8;
        sync.archivedTotal = r64(bytes, o); o += 8;
        sync.archivedThrough = r32(bytes, o); o += 4;
        sync.lastInfoDay = r32(bytes, o); o += 4;
        sync.lastInfoSteps = r32(bytes, o); o += 4;
        sync.lastObservation = r32(bytes, o); o += 4;
        sync.quarantineThrough = r32(bytes, o); o += 4;
        var count = bytes[o]; o += 1;
        if (count > STEP_RECENT_DAYS) { return false; }
        for (var i = 0; i < STEP_RECENT_DAYS; i += 1) {
            var day = r32(bytes, o); o += 4;
            var max = r32(bytes, o); o += 4;
            if (i < count) { sync.days.add(day); sync.maxima.add(max); }
        }
        return true;
    }

    function replacePrefix(bytes as ByteArray) as ByteArray {
        var b = encode();
        for (var i = STEP_HEADER_SIZE; i < bytes.size(); i += 1) { b.add(bytes[i]); }
        return b;
    }

    function u8(b as ByteArray, v as Number) as Void { b.add(v & 0xff); }
    function u32(b as ByteArray, v as Number) as Void {
        b.add(v & 0xff); b.add((v >> 8) & 0xff);
        b.add((v >> 16) & 0xff); b.add((v >> 24) & 0xff);
    }
    function u64(b as ByteArray, v as Long) as Void {
        u32(b, v.toNumber());
        u32(b, (v >> 32).toNumber());
    }
    function r32(b as ByteArray, o as Number) as Number {
        return b.decodeNumber(Lang.NUMBER_FORMAT_UINT32,
            { :offset => o, :endianness => Lang.ENDIAN_LITTLE }).toNumber();
    }
    function r64(b as ByteArray, o as Number) as Long {
        var lo = b.decodeNumber(Lang.NUMBER_FORMAT_UINT32,
            { :offset => o, :endianness => Lang.ENDIAN_LITTLE }) as Long;
        var hi = b.decodeNumber(Lang.NUMBER_FORMAT_UINT32,
            { :offset => o + 4, :endianness => Lang.ENDIAN_LITTLE }) as Long;
        return (hi << 32) | lo;
    }
}
