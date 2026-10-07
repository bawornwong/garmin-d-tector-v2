import Toybox.Lang;
import Toybox.Test;

(:test)
class RecordingDisplayAwake extends DisplayAwake {
    var requests as Number = 0;
    var reject as Boolean = false;

    function initialize() { DisplayAwake.initialize(); }

    function requestBacklight() as Void {
        requests += 1;
        if (reject) { throw new Lang.Exception(); }
    }
}

(:test)
function displayStaysAwakeForThirtySecondsWithoutInput(logger as Test.Logger) as Boolean {
    var display = new RecordingDisplayAwake();
    display.show(100);
    // Advance real milliseconds, with 20 frames per second and no input.
    for (var now = 150; now <= 30100; now += 50) { display.tick(now); }
    if (display.requests != 31) { return false; }
    display.tick(31100);
    display.tick(60100);
    return display.requests == 31;
}

(:test)
function displayInputExtendsWindowAndHideStopsRequests(logger as Test.Logger) as Boolean {
    var display = new RecordingDisplayAwake();
    display.show(0);
    display.input(29000);
    display.tick(58000);
    display.tick(59000);
    if (display.requests != 4) { return false; }
    display.tick(60000);
    display.hide();
    display.input(61000);
    display.tick(62000);
    if (display.requests != 4) { return false; }
    display.show(63000);
    display.tick(93000);
    return display.requests == 6;
}

(:test)
function displayHonorsFirmwareRejectionUntilShownAgain(logger as Test.Logger) as Boolean {
    var display = new RecordingDisplayAwake();
    display.reject = true;
    display.show(0);
    display.tick(1000);
    display.input(2000);
    if (display.requests != 1) { return false; }
    display.hide();
    display.reject = false;
    display.show(3000);
    return display.requests == 2;
}

(:test)
function displayWindowSurvivesTimerWrap(logger as Test.Logger) as Boolean {
    var display = new RecordingDisplayAwake();
    display.show(0xfffffff0);
    display.tick(0x000003d7); // 999 ms later: too soon to renew.
    if (display.requests != 1) { return false; }
    display.tick(0x000003d8); // 1,000 ms later.
    display.tick(0x00007520); // 30,000 ms later.
    display.tick(0x00007908); // 31,000 ms later: the window expired.
    return display.requests == 3;
}
