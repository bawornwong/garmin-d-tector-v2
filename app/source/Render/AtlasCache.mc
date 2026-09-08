import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// Row-buffer cache. ADR 3 / ticket 06: `drawBitmap2` refuses a palettised
// source outright ("Source must not use a color palette"), and every atlas
// resource is a 1-bpp palette bitmap, so a cell can never be blitted
// straight out of the resource. Instead, one row is copied at a time into a
// plain BufferedBitmap with the classic `drawBitmap` (which DOES accept a
// palette source) and a negative offset that shifts the wanted row up to
// y=0 -- the same mechanism ticket 16 validated for extracting a single
// cell by x-offset, applied here to a whole row by y-offset.
//
// Blit cost tracks the SOURCE buffer's area, not the output size (ticket
// 06): a 576x24 row costs ~0.3 ms/sprite against ~6.8 ms/sprite from a
// whole-atlas buffer. Rows are therefore the unit of caching, capped at 16
// (ticket 16 measured the pool's real ceiling at ~829,000 px regardless of
// buffer shape, and overcommitting throws rather than purging).
//
// The row buffer is created with NO :palette option, and that is load-bearing
// twice over (both measured):
//   - a BufferedBitmap created WITH a palette is itself a palettised bitmap,
//     so drawBitmap2 rejects it as a source with the same "Source must not use
//     a color palette" that rules out the resource. A palette-free buffer is
//     the only kind that can be blitted from.
//   - a palette-free buffer starts fully transparent and preserves the atlas's
//     alpha through the copy, which is what lets a sprite composite over what
//     is beneath it instead of stamping a rectangle of screen colour over it.
//     Verified by drawing a cell over a blue field: 262 ink pixels landed,
//     314 field pixels stayed blue.
class AtlasCache {
    const CAP = 16;

    // atlasClass -> [cellW, cellH, cols] for the three grid atlases.
    const GEOM = {
        0 => [24, 24, 24],
        1 => [32, 32, 24],
    };
    // The gridless atlases -- class 3 is the odd-size sprite strip, 4 to 6 the
    // three font faces (Kaisa.Font.ATLAS_CLASS). Each is one row: short enough
    // that the whole thing is the row buffer, which is the point of packing
    // every glyph of a face into a single strip. Class 2 (14x16) is a grid in
    // name only -- the sheet is exactly one cellH tall, so it too has a single
    // row, y=0 always.
    const STRIP = {
        2 => [336, 16],
        3 => [1011, 82],
        4 => [185, 7],
        5 => [145, 5],
        6 => [138, 5],
    };

    var _atlas as Array = [null, null, null, null, null, null, null];
    var _rows as Dictionary = {};
    var _order as Array<String> = [];
    // The five single-row atlases (~91,000 px between them, against the
    // ~829,000 px pool ceiling ticket 16 measured) never change and are cheap
    // enough to hold for the app's whole life, so they are loaded once here
    // rather than through the LRU below. Sharing the LRU with classes 0/1 was
    // a stutter waiting to happen: those two hold 70 and 31 DISTINCT rows
    // between them, and any scene that cycled through more than a handful of
    // them evicted the fonts and the misc strip along with them -- so the very
    // next glyph or effect sprite paid a fresh ~166,000 px blit mid-animation.
    // A cutscene's background slide and a battle's attack pose are exactly
    // the moments that draw a rarely-used row while several others are also
    // in play, which is what made the stall visible there in particular.
    var _pinned as Dictionary = {};

    function initialize() {
    }

    function load() as Void {
        _atlas[0] = WatchUi.loadResource(Rez.Drawables.Atlas24);
        _atlas[1] = WatchUi.loadResource(Rez.Drawables.Atlas32);
        _atlas[2] = WatchUi.loadResource(Rez.Drawables.Atlas14x16);
        _atlas[3] = WatchUi.loadResource(Rez.Drawables.AtlasOdd);
        _atlas[4] = WatchUi.loadResource(Rez.Drawables.FontBig);
        _atlas[5] = WatchUi.loadResource(Rez.Drawables.FontRegular);
        _atlas[6] = WatchUi.loadResource(Rez.Drawables.FontSmall);
        var keys = STRIP.keys();
        for (var i = 0; i < keys.size(); i += 1) {
            var cls = keys[i] as Number;
            var dim = STRIP[cls] as Array<Number>;
            _pinned[cls] = materialise(cls, 0, dim[0], dim[1]);
        }
    }

    // Returns [BufferedBitmap, localX, localY] to blit from, or null if the
    // row could not be materialised (pool overcommitted this frame).
    function locate(cls as Number, x as Number, y as Number) as Array? {
        var pinned = _pinned[cls];
        if (pinned != null) {
            return [pinned, x, y];
        }
        var geom = GEOM[cls];
        if (geom == null) { return null; }
        var cellH = geom[1];
        var cols = geom[2];
        var cellW = geom[0];
        var rowY = (y / cellH) * cellH;
        var buf = rowBuffer(cls, rowY, cellW * cols, cellH);
        return (buf == null) ? null : [buf, x, y - rowY];
    }

    // The one-shot version used at load() time: no key, no LRU bookkeeping,
    // since a pinned row is never looked up again through this path.
    function materialise(cls as Number, rowY as Number, width as Number,
                         height as Number) as Graphics.BufferedBitmap? {
        var atlas = _atlas[cls] as WatchUi.BitmapResource?;
        if (atlas == null) { return null; }
        var ref = Graphics.createBufferedBitmap({ :width => width, :height => height });
        var buf = ref.get();
        buf.getDc().drawBitmap(0, -rowY, atlas);
        return buf;
    }

    function rowBuffer(cls as Number, rowY as Number, width as Number, height as Number)
            as Graphics.BufferedBitmap? {
        var key = cls.toString() + ":" + rowY.toString();
        if (_rows.hasKey(key)) {
            _order.remove(key);
            _order.add(key);
            return _rows[key];
        }
        var atlas = _atlas[cls] as WatchUi.BitmapResource?;
        if (atlas == null) { return null; }
        try {
            var ref = Graphics.createBufferedBitmap({ :width => width, :height => height });
            var buf = ref.get();
            buf.getDc().drawBitmap(0, -rowY, atlas);
            _rows[key] = buf;
            _order.add(key);
            if (_order.size() > CAP) {
                var evict = _order[0];
                _order.remove(evict);
                _rows.remove(evict);
            }
            return buf;
        } catch (e) {
            if (_order.size() > 0) {
                var evict = _order[0];
                _order.remove(evict);
                _rows.remove(evict);
            }
            return null;
        }
    }
}
