import Toybox.Lang;
import Toybox.Test;

(:test)
function touchSectorsFollowDiagonals(logger as Test.Logger) as Boolean {
    var input = new InputDelegate(new InputQueue());
    var points = [
        [30, 227, input.REGION_LEFT],
        [420, 227, input.REGION_RIGHT],
        [227, 30, input.REGION_TOP],
        [227, 420, input.REGION_BOTTOM],
        [127, 127, input.REGION_TOP],
        [126, 127, input.REGION_LEFT],
        [327, 127, input.REGION_TOP],
        [328, 127, input.REGION_RIGHT],
        [127, 327, input.REGION_BOTTOM],
        [126, 327, input.REGION_LEFT],
        [327, 327, input.REGION_BOTTOM],
        [328, 327, input.REGION_RIGHT],
        [227, 227, input.REGION_BOTTOM]
    ];
    for (var i = 0; i < points.size(); i += 1) {
        var point = points[i];
        if (input.regionOf(point[0], point[1]) != point[2]) {
            return false;
        }
    }
    return true;
}

(:test)
function touchZonesHoldAndReleaseOnce(logger as Test.Logger) as Boolean {
    var queue = new InputQueue();
    var input = new InputDelegate(queue);
    var xs = [30, 420, 227, 227];
    var ys = [227, 227, 420, 30];
    var downs = [Kaisa.Input.EVT_LEFT_DOWN, Kaisa.Input.EVT_RIGHT_DOWN,
                 Kaisa.Input.EVT_A_DOWN, Kaisa.Input.EVT_B_DOWN];
    var ups = [Kaisa.Input.EVT_LEFT_UP, Kaisa.Input.EVT_RIGHT_UP,
               Kaisa.Input.EVT_A_UP, Kaisa.Input.EVT_B_UP];
    var actions = [Kaisa.Input.EVT_LEFT, Kaisa.Input.EVT_RIGHT,
                   Kaisa.Input.EVT_A, Kaisa.Input.EVT_B];
    for (var i = 0; i < xs.size(); i += 1) {
        input.touchDown(xs[i], ys[i]);
        // Repeated down/hold callbacks in another zone must not switch input.
        var next = (i + 1) % xs.size();
        input.touchDown(xs[next], ys[next]);
        var held = queue.drain();
        if (held.size() != 1 || held[0] != downs[i]) { return false; }
        input.touchUp();
        input.touchUp(); // DRAG_STOP followed by RELEASE must not double-fire.
        var released = queue.drain();
        if (released.size() != 2 || released[0] != ups[i]
                || released[1] != actions[i]) { return false; }
    }
    return true;
}
