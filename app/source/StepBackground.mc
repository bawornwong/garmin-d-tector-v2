import Toybox.Application.Storage;
import Toybox.Background;
import Toybox.Lang;
import Toybox.Notifications;
import Toybox.System;

(:background)
class StepBackground extends System.ServiceDelegate {
    function initialize() {
        ServiceDelegate.initialize();
    }

    function onTemporalEvent() as Void { run(); }
    function onSteps() as Void { run(); }

    function run() as Void {
        if (!BackgroundStepSetting.enabled()) { Background.exit(null); return; }
        var access = new StepAccess();
        if (!access.beginBackground()) { Background.exit(null); return; }
        try {
            var bytes = Storage.getValue("slot0") as ByteArray?;
            if (bytes != null) {
                var header = new StepHeader();
                if (header.decode(bytes)) {
                    var reading = (new GarminStepReader()).read(true);
                    var changed = (new StepLedger()).observe(header.sync, reading);
                    if (changed) {
                        bytes = header.replacePrefix(bytes);
                        Storage.setValue("slot0", bytes);
                    }
                    if (shouldNotify(header)) {
                        Notifications.showNotification("D-Tector", "Detected", {
                            :body => "Open the game to continue your journey",
                            :data => { "generation" => header.sync.gameGeneration,
                                       "gate" => header.sync.gateEpoch },
                            :actions => [{ :label => "Open game", :data => 1 }],
                            :dismissPrevious => true
                        });
                        header.sync.notifiedGateEpoch = header.sync.gateEpoch;
                        Storage.setValue("slot0", header.replacePrefix(bytes));
                    }
                }
            }
        } catch (e) {
            System.println("StepBackground: " + e.getErrorMessage());
        }
        access.endBackground();
        Background.exit(null);
    }

    function shouldNotify(h as StepHeader) as Boolean {
        var sync = h.sync;
        if (h.gameChar < 0 || h.defeated || !sync.cursorInitialized
                || sync.notifiedGateEpoch == sync.gateEpoch) { return false; }
        if (h.pendingEvent != 0) { return true; }
        var needed = h.distance == 1 ? 1 : h.distance - 1;
        if (needed < 1) { return false; }
        var eventSteps = h.stepsToEvent;
        if (eventSteps < 1) { eventSteps = 1; }
        if (h.distance > 1 && eventSteps < needed) { needed = eventSteps; }
        return sync.sourceTotal - sync.creditedSourceTotal >= needed.toLong();
    }
}
