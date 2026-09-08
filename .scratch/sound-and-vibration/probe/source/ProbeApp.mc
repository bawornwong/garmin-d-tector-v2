import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// Ticket 01's instrument. Answers, on a real venu445mm, the questions the
// documentation does not (see ../research/02-what-toneprofile-accepts.md):
// whether a CIQ tone is audible at all, over what frequency range, whether
// playTone blocks, what happens under spam, whether a tone can be stopped,
// and whether duty-cycle gradation is perceptible.
//
// Deliberately NOT the game: the game plays sounds of its own constantly,
// which would sit on top of every measurement.
//
// Build and sideload:
//   cd .scratch/sound-and-vibration/probe
//   "$CIQ_SDK/bin/monkeyc" -f monkey.jungle -o probe.prg \
//       -y ../../keys/developer_key.der -d venu445mm -w
//   copy probe.prg to GARMIN/APPS/ over USB, eject
//
// Every test prints to the console, so run it in the simulator too
// ("$CIQ_SDK/bin/monkeydo" probe.prg venu445mm) to read the output there --
// but the ANSWERS only count from the watch. The simulator on at least one
// dev machine cannot play tones at all (a Core Audio error per call), which
// is itself why this ticket exists.
class ProbeApp extends Application.AppBase {
    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new ProbeView();
        return [view, new ProbeDelegate(view)];
    }
}
