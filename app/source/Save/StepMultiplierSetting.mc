import Toybox.Application.Storage;
import Toybox.Lang;

// Shared by foreground credit and background gate detection. A separate
// preference keeps existing saves compatible and survives a game reset.
(:background)
module StepMultiplierSetting {
    const KEY = "stepMultiplier";
    const MIN = 1;
    const MAX = 5;

    function value() as Number {
        var stored = Storage.getValue(KEY);
        if (stored instanceof Number && stored >= MIN && stored <= MAX) {
            return stored;
        }
        return MIN;
    }

    function setValue(multiplier as Number) as Void {
        Storage.setValue(KEY, multiplier >= MIN && multiplier <= MAX ? multiplier : MIN);
    }

    function advance() as Void {
        var current = value();
        setValue(current == MAX ? MIN : current + 1);
    }
}
