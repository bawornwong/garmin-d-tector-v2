import Toybox.Background;
import Toybox.Time;

// Foreground-only registration. The service also checks the preference in
// case a wake was already queued when the player turned the option off.
module StepBackgroundSchedule {
    function apply() as Void {
        if (BackgroundStepSetting.enabled()) {
            Background.registerForTemporalEvent(new Time.Duration(300));
            if (!Background.getStepsEventRegistered()) {
                Background.registerForStepsEvent();
            }
        } else {
            Background.deleteTemporalEvent();
            Background.deleteStepsEvent();
        }
    }
}
