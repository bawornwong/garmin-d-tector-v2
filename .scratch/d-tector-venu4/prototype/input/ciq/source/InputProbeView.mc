import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

class InputProbeView extends WatchUi.View {
    var _lines as Array<String> = [];

    function initialize() { View.initialize(); }

    function note(s as String) as Void {
        _lines.add(s);
        if (_lines.size() > 9) { _lines = _lines.slice(1, null); }
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        dc.setColor(0x819376, Graphics.COLOR_TRANSPARENT);
        dc.drawText(dc.getWidth() / 2, 30, Graphics.FONT_XTINY,
            "INPUT PROBE", Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < _lines.size(); i += 1) {
            dc.drawText(dc.getWidth() / 2, 70 + i * 34, Graphics.FONT_XTINY,
                _lines[i], Graphics.TEXT_JUSTIFY_CENTER);
        }
    }
}
