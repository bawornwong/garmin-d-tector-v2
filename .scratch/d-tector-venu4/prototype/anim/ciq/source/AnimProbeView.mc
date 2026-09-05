import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

class AnimProbeView extends WatchUi.View {
    var _rt as Runner?;
    var _timer as Timer.Timer?;
    var _case as Number = 0;
    var _names as Array<String> = ["CharHappy", "LaunchAttack_a0",
        "LaunchAttack_a1_disobey", "LaunchAttack_a3"];

    function initialize() { View.initialize(); }

    function onShow() as Void {
        startCase();
        _timer = new Timer.Timer();
        _timer.start(method(:tick), 50, true);
    }
    function onHide() as Void { if (_timer != null) { _timer.stop(); } }

    function startCase() as Void {
        _rt = new Runner();
        System.println("=== " + _names[_case] + " ===");
        if (_case == 0)      { _rt.call(new CharHappy()); }
        else if (_case == 1) { _rt.call(new LaunchAttack(0, false, false)); }
        else if (_case == 2) { _rt.call(new LaunchAttack(1, true, true)); }
        else                 { _rt.call(new LaunchAttack(3, false, false)); }
    }

    function tick() as Void {
        if (_rt == null) { return; }
        _rt.advance(50.0);
        if (!_rt.isRunning()) {
            System.println("--- " + _names[_case] + " end=" +
                _rt.nowMs.format("%.4f") + "ms ticks=" + _rt.tick +
                " steps=" + _rt.steps);
            _case += 1;
            if (_case >= _names.size()) {
                System.println("ALLDONE");
                _timer.stop();
                _rt = null;
                return;
            }
            startCase();
        }
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var label = (_case < _names.size()) ? _names[_case] : "done";
        dc.drawText(dc.getWidth() / 2, dc.getHeight() / 2, Graphics.FONT_SMALL,
            label, Graphics.TEXT_JUSTIFY_CENTER);
    }
}
