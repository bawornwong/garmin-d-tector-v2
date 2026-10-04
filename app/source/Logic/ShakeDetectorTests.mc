import Toybox.Lang;
import Toybox.Test;

(:test)
function shakeDetectorCountsPulseOnce(logger as Test.Logger) as Boolean {
    var detector = new ShakeDetector();
    var flat = [0, 0, 0, 0, 0, 0];
    var gravity = [1000, 1000, 1000, 1000, 1000, 1000];
    if (detector.countSamples(flat, flat, gravity) != 0) { return false; }
    var pulse = [0, 2500, 0, 0, 0, 0];
    return detector.countSamples(pulse, flat, gravity) == 1;
}

(:test)
function shakeDetectorKeepsCooldownAcrossBatches(logger as Test.Logger) as Boolean {
    var detector = new ShakeDetector();
    detector.countSamples([0], [0], [1000]);
    if (detector.countSamples([2500], [0], [1000]) != 1) { return false; }
    if (detector.countSamples([0, 2500, 0], [0, 0, 0],
                              [1000, 1000, 1000]) != 0) { return false; }
    return detector.countSamples([2500], [0], [1000]) == 1;
}
