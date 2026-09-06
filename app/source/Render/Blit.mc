import Toybox.Graphics;
import Toybox.Lang;

// The one place that knows how this device actually draws a cell out of a row
// buffer. Both device behaviours below were measured by reading a rendered
// frame back off the simulator and diffing it against the atlas; neither was
// visible at a glance in a screenshot (ADR 3).
module Render {
    // Draws the (srcW x srcH) cell at (srcX, srcY) of `buf` at device pixel
    // (destX, destY), magnified `scale` times, in `tint`.
    //
    //   - with :transform set, drawBitmap2 draws at (x, y) + T * (bitmapX,
    //     bitmapY), NOT at (x, y). The destination is therefore
    //     pre-compensated by scale * (srcX, srcY) here, which is why
    //     AtlasCache is free to return honest source coordinates.
    //   - :tintColor is a MULTIPLY over the source pixel. Every atlas stores
    //     white ink on a transparent field precisely so that white x tint ==
    //     tint, which is what makes both the ink colour and its inversion a
    //     draw-time choice.
    function blit(dc as Graphics.Dc, buf as Graphics.BufferedBitmap,
                  srcX as Number, srcY as Number, srcW as Number, srcH as Number,
                  destX as Number, destY as Number, scale as Number,
                  tint as Number) as Void {
        blitFlipped(dc, buf, srcX, srcY, srcW, srcH, destX, destY,
                    scale.toFloat(), scale.toFloat(), tint, false, false);
    }

    // SpriteBuilder.FlipHorizontal/FlipVertical, which the source uses for
    // every Digimon that faces the other way. A negative scale factor makes
    // the drawn span run backwards from the anchor, so the compensation
    // becomes +scale * (src + size) on the flipped axis instead of -scale *
    // src. Verified against the atlas at 576/576 pixels in all four
    // combinations.
    function blitFlipped(dc as Graphics.Dc, buf as Graphics.BufferedBitmap,
                         srcX as Number, srcY as Number, srcW as Number, srcH as Number,
                         destX as Number, destY as Number, scaleX as Float,
                         scaleY as Float, tint as Number,
                         flipH as Boolean, flipV as Boolean) as Void {
        // The two scale factors are separate because a SpriteBuilder may hold
        // a sprite whose cell is not the size of its component rect, and Unity
        // stretches the Image to the rect. They are equal in the common case.
        var t = new Graphics.AffineTransform();
        t.setToScale(flipH ? -scaleX : scaleX, flipV ? -scaleY : scaleY);
        var dx = flipH ? destX + (scaleX * (srcX + srcW)).toNumber()
                       : destX - (scaleX * srcX).toNumber();
        var dy = flipV ? destY + (scaleY * (srcY + srcH)).toNumber()
                       : destY - (scaleY * srcY).toNumber();
        dc.drawBitmap2(dx, dy, buf, {
            :bitmapX => srcX, :bitmapY => srcY,
            :bitmapWidth => srcW, :bitmapHeight => srcH,
            :transform => t, :filterMode => Graphics.FILTER_MODE_POINT,
            :tintColor => tint
        });
    }
}
