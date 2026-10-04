import Toybox.Lang;
import Toybox.Sensor;

// Turns foreground accelerometer samples into deliberate wrist shakes. The
// 2 g high-pass threshold follows the source game's ShakeDetector; the
// 25 Hz filter and cooldown adapt its 60 fps loop to Garmin sample batches.
class ShakeDetector {
    const THRESHOLD_SQUARED = 4000000l;
    const FILTER_WIDTH = 25;
    const COOLDOWN_SAMPLES = 3;

    var _ready as Boolean = false;
    var _lowX as Number = 0;
    var _lowY as Number = 0;
    var _lowZ as Number = 0;
    var _cooldown as Number = 0;
    function reset() as Void {
        _ready = false;
        _cooldown = 0;
    }

    function count(data as Sensor.AccelerometerData) as Number {
        return countSamples(data.x, data.y, data.z);
    }

    function countSamples(xs as Array<Number>, ys as Array<Number>,
                          zs as Array<Number>) as Number {
        var n = xs.size();
        if (ys.size() < n) { n = ys.size(); }
        if (zs.size() < n) { n = zs.size(); }
        var shakes = 0;
        for (var i = 0; i < n; i += 1) {
            var x = xs[i];
            var y = ys[i];
            var z = zs[i];
            if (!_ready) {
                _lowX = x; _lowY = y; _lowZ = z;
                _ready = true;
                continue;
            }
            _lowX += (x - _lowX) / FILTER_WIDTH;
            _lowY += (y - _lowY) / FILTER_WIDTH;
            _lowZ += (z - _lowZ) / FILTER_WIDTH;
            var dx = (x - _lowX).toLong();
            var dy = (y - _lowY).toLong();
            var dz = (z - _lowZ).toLong();
            if (_cooldown > 0) {
                _cooldown -= 1;
            } else if (dx * dx + dy * dy + dz * dz >= THRESHOLD_SQUARED) {
                shakes += 1;
                _cooldown = COOLDOWN_SAMPLES;
            }
        }
        return shakes;
    }
}
