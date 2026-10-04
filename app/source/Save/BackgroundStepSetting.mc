import Toybox.Application.Storage;
import Toybox.Lang;

// Device preference, separate from the game save so Reset does not change it.
// Missing storage means ON, preserving the behavior of existing installs.
(:background)
module BackgroundStepSetting {
    const KEY = "bgStepSyncOff";

    function enabled() as Boolean {
        return Storage.getValue(KEY) != true;
    }

    function setEnabled(value as Boolean) as Void {
        Storage.setValue(KEY, !value);
    }
}
