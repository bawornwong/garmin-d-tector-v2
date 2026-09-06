import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// Bitmap text (SPEC step 5, ticket 15). Unity's `Text` component draws the
// three .fontsettings faces glyph by glyph; so does this, out of the same
// font strips, through the same row-buffer path the sprites use.
//
// Everything about a glyph comes from Render/FontMetrics.mc, which
// tools/pack_fonts.py generates from the .fontsettings themselves (ADR 12).
// The two metrics that are easy to lose and both matter:
//
//   - the ADVANCE is not the glyph's width. Big is monospaced at 6 px with
//     5 px art; Regular and Small are proportional, 2-6 px advance over 1-5
//     px art.
//   - the vertical BEARING (Unity's vert.y) drops Big's letters 2 px below
//     its digits. Ignoring it renders "LV 12" with the letters floating.
//
// The prefab's Text is Overflow horizontally and Truncate vertically with
// ConvertCase upper, so: uppercase first, break lines only on '\n', never
// wrap, and let the canvas do the clipping (ADR 10 for missing glyphs -- the
// faces carry space, '!', the digits and A-Z, nothing else).
module Kaisa {
    module Text {
        // Unity TextAnchor, only the values the source actually uses
        // (25 UpperRight, 4 UpperCenter, and the prefab default UpperLeft).
        const ANCHOR_UPPER_LEFT = 0;
        const ANCHOR_UPPER_CENTER = 1;
        const ANCHOR_UPPER_RIGHT = 2;
    }
}

// Measuring is separate from drawing: TextBoxBuilder.SetFitSizeToContent has
// to know how wide a string is before anything is on screen, and the metrics
// table is static data with no atlas or Dc behind it.
module Kaisa {
    module TextMetrics {
        // [x, w, h, advance, offsetY] for one character, or null if this face
        // has no glyph for it. The caller has already uppercased.
        function glyph(face as Number, code as Number) as Array<Number>? {
            if (code < Kaisa.Font.FIRST_CODE || code > Kaisa.Font.LAST_CODE) { return null; }
            var table = Kaisa.Font.glyphs(face);
            var base = (code - Kaisa.Font.FIRST_CODE) * Kaisa.Font.FIELDS;
            if (table[base] < 0) { return null; }
            return [table[base], table[base + 1], table[base + 2],
                    table[base + 3], table[base + 4]];
        }

        // Width in game pixels of one line, summing advances. A character with
        // no glyph contributes nothing at all -- not even its advance --
        // because it is skipped entirely (ADR 10).
        function lineWidth(face as Number, line as String) as Number {
            var chars = line.toCharArray();
            var w = 0;
            for (var i = 0; i < chars.size(); i += 1) {
                var g = glyph(face, chars[i].toNumber());
                if (g != null) { w += g[3]; }
            }
            return w;
        }

        // The widest line of a (possibly multi-line) string, which is what
        // Unity's ContentSizeFitter reports as the component's width.
        function width(face as Number, text as String) as Number {
            var upper = Kaisa.Font.CONVERT_CASE[face] ? text.toUpper() : text;
            var chars = upper.toCharArray();
            var best = 0;
            var w = 0;
            for (var i = 0; i < chars.size(); i += 1) {
                if (chars[i] == '\n') {
                    if (w > best) { best = w; }
                    w = 0;
                } else {
                    var g = glyph(face, chars[i].toNumber());
                    if (g != null) { w += g[3]; }
                }
            }
            return (w > best) ? w : best;
        }
    }
}

class TextRenderer {
    var _atlas as AtlasCache;

    function initialize(atlas as AtlasCache) {
        _atlas = atlas;
    }

    function glyph(face as Number, code as Number) as Array<Number>? {
        return Kaisa.TextMetrics.glyph(face, code);
    }

    function lineWidth(face as Number, line as String) as Number {
        return Kaisa.TextMetrics.lineWidth(face, line);
    }

    // Draws `text` with its top-left at the DEVICE pixel (x, y), aligned
    // inside a box `boxWidth` GAME pixels wide, at `scale` device pixels per
    // game pixel, tinted `tint`. Device pixels in, because the canvas origin
    // is not a multiple of the scale (the 320 px canvas sits at 67 on a 454 px
    // screen) and rounding it into game pixels would shift every string.
    // Nothing clips here: text clips at the canvas, not at its own rect --
    // the rect is only what the alignment is measured against.
    function draw(dc as Dc, face as Number, text as String,
                  x as Number, y as Number, boxWidth as Number,
                  anchor as Number, scale as Number, tint as Number) as Void {
        var upper = Kaisa.Font.CONVERT_CASE[face] ? text.toUpper() : text;
        var lineSpacing = Kaisa.Font.LINE_SPACING[face];
        var lineY = y;

        var lines = splitLines(upper);
        for (var l = 0; l < lines.size(); l += 1) {
            var line = lines[l];
            var penX = x;
            if (anchor == Kaisa.Text.ANCHOR_UPPER_RIGHT) {
                penX = x + (boxWidth - lineWidth(face, line)) * scale;
            } else if (anchor == Kaisa.Text.ANCHOR_UPPER_CENTER) {
                // Halved in DEVICE pixels, not game pixels. The scene canvas
                // has m_PixelPerfect: 0, so Unity centres a line at the exact
                // half of whatever is left over -- a line 3 game pixels wider
                // than its box sits at -1.5 game pixels, not -1 or -2. At a
                // 10x scale that half is a whole device pixel, so the port can
                // land on it; rounding in game pixels instead shifted every
                // odd-overflow line by one, which is how this was found.
                penX = x + ((boxWidth - lineWidth(face, line)) * scale) / 2;
            }
            drawLine(dc, face, line, penX, lineY, scale, tint);
            lineY += lineSpacing * scale;
        }
    }

    function splitLines(text as String) as Array<String> {
        var out = [] as Array<String>;
        var chars = text.toCharArray();
        var current = "";
        for (var i = 0; i < chars.size(); i += 1) {
            if (chars[i] == '\n') {
                out.add(current);
                current = "";
            } else {
                current += chars[i].toString();
            }
        }
        out.add(current);
        return out;
    }

    // x and y are device pixels; advances and bearings are game pixels and
    // are scaled as they are applied.
    function drawLine(dc as Dc, face as Number, line as String,
                      x as Number, y as Number, scale as Number,
                      tint as Number) as Void {
        var cls = Kaisa.Font.ATLAS_CLASS[face];
        var chars = line.toCharArray();
        var penX = x;
        for (var i = 0; i < chars.size(); i += 1) {
            var g = glyph(face, chars[i].toNumber());
            if (g == null) { continue; }
            var sx = g[0];
            var w = g[1];
            var h = g[2];
            var advance = g[3];
            var offsetY = g[4];

            var located = _atlas.locate(cls, sx, 0);
            if (located != null) {
                Render.blit(dc, located[0], located[1], located[2], w, h,
                            penX, y + offsetY * scale, scale, tint);
            }
            penX += advance * scale;
        }
    }
}
