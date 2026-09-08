import Toybox.Graphics;
import Toybox.Lang;

// Walks the display list once per frame and draws it (SPEC step 2). Unity
// drew this tree with a Canvas; the rules being reproduced are its rules:
//
//   - a child's position is relative to its parent's top-left, y downward
//   - siblings paint in the order they were added, so later is on top
//   - an inactive element hides its whole subtree
//   - a Container with its RectMask2D enabled clips its descendants to its
//     own rect; nested masks intersect
//   - an element's background paints unless it is transparent, and
//     InvertColors swaps the element's ink and field colours
//
// Colours arrive as a pair rather than as constants because the original
// exposes them as ConfigActiveColor/ConfigBackgroundColor, and the alpha
// atlases make them a draw-time choice (ADR 3).
class Renderer {
    var _atlas as AtlasCache;
    var _text as TextRenderer;
    var _scale as Number;
    var _originX as Number;
    var _originY as Number;
    var _ink as Number;
    var _field as Number;
    // Whether to rule the canvas into cells, the way the toy's screen is.
    var gridVisible as Boolean = true;

    function initialize(atlas as AtlasCache, text as TextRenderer,
                        originX as Number, originY as Number, scale as Number,
                        ink as Number, field as Number) {
        _atlas = atlas;
        _text = text;
        _originX = originX;
        _originY = originY;
        _scale = scale;
        _ink = ink;
        _field = field;
    }

    function setColors(ink as Number, field as Number) as Void {
        _ink = ink;
        _field = field;
    }

    // Draws the whole canvas: the screen's field, then the tree.
    // A debug dump of what a frame actually draws, in draw order, so a
    // rendering question can be answered with the frame rather than a guess.
    (:debug) var dumpFrame as Boolean = false;

    (:debug)
    function dump(el as ScreenElement, depth as Number) as Void {
        var pad = "";
        for (var i = 0; i < depth; i += 1) { pad += "  "; }
        var what = "";
        if (el instanceof SpriteBuilder) {
            what = " sprite=" + Kaisa.Sprites.nameOf((el as SpriteBuilder).sprite);
        } else if (el instanceof TextBoxBuilder) {
            what = " text='" + (el as TextBoxBuilder).text + "'";
        }
        System.println("DRAW " + pad + el.name + " (" + el.x + "," + el.y + " "
            + el.width + "x" + el.height + ")"
            + (el.active ? "" : " INACTIVE") + (el.transparent ? " transparent" : "")
            + (el.inverted ? " inverted" : "") + what);
        if (!el.active) { return; }
        for (var i = 0; i < el.children.size(); i += 1) {
            dump(el.children[i], depth + 1);
        }
    }

    function draw(dc as Dc, root as ScreenElement) as Void {
        dc.setColor(_field, _field);
        dc.fillRectangle(_originX, _originY,
                         Kaisa.Constants.SCREEN_WIDTH * _scale, Kaisa.Constants.SCREEN_HEIGHT * _scale);
        // The canvas itself is the outermost clip: the game's 32x32 screen is
        // a window onto elements that are routinely parked outside it
        // (PlaceOutside), and text is explicitly allowed to overflow its own
        // rect but never the screen.
        drawElement(dc, root, _originX, _originY,
                    _originX, _originY,
                    Kaisa.Constants.SCREEN_WIDTH * _scale, Kaisa.Constants.SCREEN_HEIGHT * _scale);
        dc.clearClip();
        drawGrid(dc);
    }

    // The toy's screen is a dot matrix: every game pixel is its own cell with
    // a gap around it, and the gaps are what make it read as a device rather
    // than as a drawing of one. The canvas is ten device pixels per game
    // pixel, so a one-pixel gutter in the field colour turns each cell into a
    // 9x9 dot -- drawn over the finished frame, which costs 64 thin lines
    // rather than a different blit for every sprite.
    function drawGrid(dc as Dc) as Void {
        if (!gridVisible) { return; }
        dc.setColor(_field, Graphics.COLOR_TRANSPARENT);
        var w = Kaisa.Constants.SCREEN_WIDTH * _scale;
        var h = Kaisa.Constants.SCREEN_HEIGHT * _scale;
        for (var i = 1; i < Kaisa.Constants.SCREEN_WIDTH; i += 1) {
            dc.fillRectangle(_originX + i * _scale - 1, _originY, 1, h);
        }
        for (var i = 1; i < Kaisa.Constants.SCREEN_HEIGHT; i += 1) {
            dc.fillRectangle(_originX, _originY + i * _scale - 1, w, 1);
        }
    }

    // (parentX, parentY) is where this element's parent starts, in device
    // pixels; (clipX, clipY, clipW, clipH) is the current clip rect, also in
    // device pixels.
    function drawElement(dc as Dc, el as ScreenElement,
                         parentX as Number, parentY as Number,
                         clipX as Number, clipY as Number,
                         clipW as Number, clipH as Number) as Void {
        if (!el.active) { return; }

        var x = parentX + el.x * _scale;
        var y = parentY + el.y * _scale;
        var w = el.width * _scale;
        var h = el.height * _scale;

        var ink = el.inverted ? _field : _ink;
        var field = el.inverted ? _ink : _field;

        setClip(dc, clipX, clipY, clipW, clipH);

        if (!el.transparent) {
            var bg = field;
            if (el instanceof ContainerBuilder) {
                bg = (el as ContainerBuilder).backgroundBlack ? _ink : _field;
            }
            dc.setColor(bg, bg);
            dc.fillRectangle(x, y, w, h);
        }

        if (el instanceof SpriteBuilder) {
            drawSprite(dc, el as SpriteBuilder, x, y, ink);
        } else if (el instanceof TextBoxBuilder) {
            drawText(dc, el as TextBoxBuilder, x, y, ink);
        } else if (el instanceof RectangleBuilder) {
            var rect = el as RectangleBuilder;
            if (rect.flickOn) {
                var c = rect.activeColor ? ink : field;
                dc.setColor(c, c);
                dc.fillRectangle(x, y, w, h);
            }
        }

        var childClipX = clipX;
        var childClipY = clipY;
        var childClipW = clipW;
        var childClipH = clipH;
        if (el instanceof ContainerBuilder && (el as ContainerBuilder).maskActive) {
            var r = intersect(clipX, clipY, clipW, clipH, x, y, w, h);
            childClipX = r[0];
            childClipY = r[1];
            childClipW = r[2];
            childClipH = r[3];
        }

        for (var i = 0; i < el.children.size(); i += 1) {
            drawElement(dc, el.children[i], x, y,
                        childClipX, childClipY, childClipW, childClipH);
        }
    }

    function drawSprite(dc as Dc, el as SpriteBuilder, x as Number, y as Number,
                        ink as Number) as Void {
        // A runtime bitmap (the Maze's walls) draws in place of the sprite,
        // through the same tinted, point-filtered path as an atlas cell.
        if (el.runtimeBitmap != null) {
            Render.blitFlipped(dc, el.runtimeBitmap, 0, 0,
                               el.runtimeWidth, el.runtimeHeight,
                               x + el.componentX * _scale, y + el.componentY * _scale,
                               _scale.toFloat(), _scale.toFloat(), ink,
                               el.flipH, el.flipV);
            return;
        }
        var ref = el.sprite;
        if (ref == null) { return; }
        var located = _atlas.locate(ref[0], ref[1], ref[2]);
        if (located == null) { return; }
        var cellW = ref[3];
        var cellH = ref[4];
        // Unity stretches the Image to its rect; a component the same size as
        // the cell (the usual case) leaves both factors at the plain scale.
        var sx = (_scale * el.componentWidth).toFloat() / cellW;
        var sy = (_scale * el.componentHeight).toFloat() / cellH;
        Render.blitFlipped(dc, located[0], located[1], located[2], cellW, cellH,
                           x + el.componentX * _scale, y + el.componentY * _scale,
                           sx, sy, ink, el.flipH, el.flipV);
    }

    function drawText(dc as Dc, el as TextBoxBuilder, x as Number, y as Number,
                      ink as Number) as Void {
        if (el.text.length() == 0) { return; }
        _text.draw(dc, el.font, el.text,
                   x + el.componentX * _scale, y + el.componentY * _scale,
                   el.componentWidth, el.alignment, _scale, ink);
    }

    // Dc.setClip takes a rect, not a stack, so nested masks are intersected
    // here. A mask that clips everything away collapses to a zero-size rect,
    // which the device accepts and draws nothing through.
    function setClip(dc as Dc, x as Number, y as Number, w as Number, h as Number) as Void {
        dc.setClip(x, y, w, h);
    }

    function intersect(ax as Number, ay as Number, aw as Number, ah as Number,
                       bx as Number, by as Number, bw as Number, bh as Number) as Array<Number> {
        var x0 = (ax > bx) ? ax : bx;
        var y0 = (ay > by) ? ay : by;
        var x1 = ((ax + aw) < (bx + bw)) ? (ax + aw) : (bx + bw);
        var y1 = ((ay + ah) < (by + bh)) ? (ay + ah) : (by + bh);
        var w = (x1 > x0) ? (x1 - x0) : 0;
        var h = (y1 > y0) ? (y1 - y0) : 0;
        return [x0, y0, w, h];
    }
}
