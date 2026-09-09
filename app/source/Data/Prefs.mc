import Toybox.Application.Storage;
import Toybox.Lang;

// The Configure menu's settings.
//
// Deliberately NOT in the save record. That blob is positional and versioned
// (ADR 8), version 2 refuses a version 1 slot outright because the world
// arrays are sized from the packed data, and there is no migration -- so
// adding a field there would cost a version bump and throw away any save
// that already exists. These are preferences rather than game state, they do
// not belong to a slot, and they survive a reset, so they get their own
// Storage key instead.
//
// One Number, one bit each: a single read at startup and a single write per
// toggle. Absent (a fresh install) reads as every bit clear, so the defaults
// are expressed as "on" bits meaning OFF -- see DEFAULTS below.
module Kaisa {
    module Prefs {
        const KEY = "prefs";

        // Stored INVERTED: the bit is set when the setting is OFF. A device
        // with nothing stored yet returns null -> 0 -> every bit clear ->
        // everything on, which is the state the game had before this menu
        // existed. Storing "on" bits instead would silently start a fresh
        // install with sound and vibration disabled.
        const BIT_SOUND_OFF = 1;
        const BIT_VIBRATION_OFF = 2;
        const BIT_GRID_OFF = 4;

        var _bits as Number = 0;

        function load() as Void {
            var v = Storage.getValue(KEY);
            _bits = (v == null) ? 0 : (v as Number);
        }

        function save() as Void {
            Storage.setValue(KEY, _bits);
        }

        function soundOn() as Boolean { return (_bits & BIT_SOUND_OFF) == 0; }
        function vibrationOn() as Boolean { return (_bits & BIT_VIBRATION_OFF) == 0; }
        function gridOn() as Boolean { return (_bits & BIT_GRID_OFF) == 0; }

        function toggle(bit as Number) as Void {
            _bits = _bits ^ bit;
            save();
        }
    }
}
