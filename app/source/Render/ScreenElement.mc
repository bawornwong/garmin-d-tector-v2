import Toybox.Lang;
import Toybox.Math;

// The display list (SPEC step 2). A literal translation of the source's
// Screen/ layer -- ScreenElement plus its four builders -- with the same
// operations under the same names, because every animation and every app in
// the port drives it exactly as the C# does (ADR 2). Animations mutate this
// tree; Renderer draws it whole each frame.
//
// Two things replace Unity rather than translate it:
//
//   - a GameObject's RectTransform becomes plain fields. The prefabs anchor
//     and pivot at (0, 1) with sizeDelta in Unity units, so `PlaceInPosition`
//     is just "x right, y DOWN from the parent's top-left, in game pixels"
//     and Constants.PIXEL_SIZE disappears entirely: this tree is in game
//     pixels and the renderer scales by 10 when it draws.
//   - Destroy/Instantiate become add/remove on a child list. Dispose()
//     unlinks the element from its parent, which is what makes it stop
//     drawing; the source's Destroy() is deferred to end of frame, ours is
//     immediate, and no call site depends on the difference (they all drop
//     the reference at the same time).
// DFont maps straight onto Kaisa.Font's face ids, so a TextBoxBuilder's
// `font` field is the same number FontMetrics indexes by and no translation
// table exists to fall out of step.
class ScreenElement {
    var name as String = "";
    var x as Number = 0;
    var y as Number = 0;
    var width as Number = 0;
    var height as Number = 0;
    var active as Boolean = true;
    // ScreenElement.background is an Image that is enabled unless the element
    // is transparent; the container prefab starts transparent, the rest do not.
    var transparent as Boolean = false;
    var inverted as Boolean = false;
    var parent as ScreenElement? = null;
    var children as Array<ScreenElement> = [];

    function initialize() {
    }

    // --- the source's Base* methods, in ScreenElement.cs order ---

    function setName(n as String) as Void {
        name = n;
    }

    function dispose() as Void {
        if (parent != null) {
            parent.children.remove(self);
            parent = null;
        }
    }

    function baseSetActive(a as Boolean) as Void {
        active = a;
    }

    function baseSetTransparent(val as Boolean) as Void {
        transparent = val;
    }

    function baseInvertColors(val as Boolean) as Void {
        inverted = val;
    }

    function baseSetSize(w as Number, h as Number) as Void {
        width = w;
        height = h;
    }

    function baseSetPosition(px as Number, py as Number) as Void {
        x = px;
        y = py;
    }

    function baseSetX(px as Number) as Void {
        x = px;
    }

    function baseSetY(py as Number) as Void {
        y = py;
    }

    // Mathf.RoundToInt on a positive half rounds to even in C#, but every
    // (SCREEN - size) here is even for the sizes the game centres, so plain
    // integer division matches. Sizes are small and non-negative.
    function baseCenter() as Void {
        baseSetPosition((Kaisa.Constants.SCREEN_WIDTH - width) / 2,
                        (Kaisa.Constants.SCREEN_HEIGHT - height) / 2);
    }

    function basePlaceOutside(direction as Number) as Void {
        if (direction == Kaisa.DIR_UP) { baseSetY(-height); }
        else if (direction == Kaisa.DIR_DOWN) { baseSetY(Kaisa.Constants.SCREEN_HEIGHT); }
        else if (direction == Kaisa.DIR_LEFT) { baseSetX(-width); }
        else if (direction == Kaisa.DIR_RIGHT) { baseSetX(Kaisa.Constants.SCREEN_WIDTH); }
    }

    function baseMove(direction as Number, amount as Number) as Void {
        if (direction == Kaisa.DIR_UP) { y -= amount; }
        else if (direction == Kaisa.DIR_DOWN) { y += amount; }
        else if (direction == Kaisa.DIR_LEFT) { x -= amount; }
        else if (direction == Kaisa.DIR_RIGHT) { x += amount; }
    }

    // --- tree ---

    function addChild(child as ScreenElement) as Void {
        child.parent = self;
        children.add(child);
    }

    // ContainerBuilder.GetChildBuilder
    function getChildBuilder(index as Number) as ScreenElement {
        return children[index];
    }

    // Elements are drawn in the order they were added, which is Unity's
    // sibling order, so a later child is on top.
    function absX() as Number {
        return (parent == null) ? x : parent.absX() + x;
    }

    function absY() as Number {
        return (parent == null) ? y : parent.absY() + y;
    }
}

// SpriteBuilder: a sprite drawn inside an element that can be a different
// size from it. The component's own position is what animations slide about
// (SnapComponentToSide, CenterComponent), while the element's position is
// what moves the whole thing.
class SpriteBuilder extends ScreenElement {
    var sprite as Array<Number>? = null;    // GameData sprite ref, or null
    var componentX as Number = 0;
    var componentY as Number = 0;
    var componentWidth as Number = 0;
    var componentHeight as Number = 0;
    var flipH as Boolean = false;
    var flipV as Boolean = false;

    function initialize() {
        ScreenElement.initialize();
    }

    // BaseSetSize is overridden in the source to resize the component too.
    function setSize(w as Number, h as Number) as SpriteBuilder {
        baseSetSize(w, h);
        setComponentSize(w, h);
        return self;
    }

    function center() as SpriteBuilder { baseCenter(); return self; }
    function invertColors(val as Boolean) as SpriteBuilder { baseInvertColors(val); return self; }
    function move(direction as Number, amount as Number) as SpriteBuilder { baseMove(direction, amount); return self; }
    function placeOutside(direction as Number) as SpriteBuilder { basePlaceOutside(direction); return self; }
    function setActive(a as Boolean) as SpriteBuilder { baseSetActive(a); return self; }
    function setPosition(px as Number, py as Number) as SpriteBuilder { baseSetPosition(px, py); return self; }
    function setTransparent(val as Boolean) as SpriteBuilder { baseSetTransparent(val); return self; }
    function setX(px as Number) as SpriteBuilder { baseSetX(px); return self; }
    function setY(py as Number) as SpriteBuilder { baseSetY(py); return self; }

    function setSprite(ref as Array<Number>?) as SpriteBuilder {
        sprite = ref;
        return self;
    }

    function setComponentSize(w as Number, h as Number) as SpriteBuilder {
        componentWidth = w;
        componentHeight = h;
        return self;
    }

    function setComponentPosition(px as Number, py as Number) as SpriteBuilder {
        componentX = px;
        componentY = py;
        return self;
    }

    function setComponentX(px as Number) as SpriteBuilder {
        componentX = px;
        return self;
    }

    function setComponentY(py as Number) as SpriteBuilder {
        componentY = py;
        return self;
    }

    function centerComponent() as SpriteBuilder {
        return setComponentPosition((width - componentWidth) / 2,
                                    (height - componentHeight) / 2);
    }

    function snapComponentToSide(side as Number, center as Boolean) as SpriteBuilder {
        if (center) { centerComponent(); }
        if (side == Kaisa.DIR_LEFT) { setComponentX(0); }
        else if (side == Kaisa.DIR_RIGHT) { setComponentX(width - componentWidth); }
        else if (side == Kaisa.DIR_UP) { setComponentY(0); }
        else if (side == Kaisa.DIR_DOWN) { setComponentY(height - componentHeight); }
        return self;
    }

    // The source flips by rotating the component 180 degrees about an axis
    // and then re-applying its position, because a rotated RectTransform's
    // anchoredPosition moves with it. Nothing of that survives translation:
    // the flip is a property of the blit here, and the component position is
    // unaffected -- which is also why the source's "TODO: fix a bug in which
    // CenterComponent bugs if used after FlipHorizontal" has no counterpart.
    function flipHorizontal(flip as Boolean) as SpriteBuilder {
        flipH = flip;
        return self;
    }

    function flipVertical(flip as Boolean) as SpriteBuilder {
        flipV = flip;
        return self;
    }
}

// TextBoxBuilder: a line (or lines) of bitmap text. The rect is what the
// alignment is measured against; the text itself is not clipped by it
// (HorizontalOverflow: Overflow in the prefab).
class TextBoxBuilder extends ScreenElement {
    var text as String = "";
    var font as Number = Kaisa.Font.REGULAR;
    var alignment as Number = Kaisa.Text.ANCHOR_UPPER_LEFT;
    var componentX as Number = 0;
    var componentY as Number = 0;
    var componentWidth as Number = 0;
    var componentHeight as Number = 0;

    function initialize() {
        ScreenElement.initialize();
    }

    function setSize(w as Number, h as Number) as TextBoxBuilder {
        baseSetSize(w, h);
        setComponentSize(w, h);
        return self;
    }

    function center() as TextBoxBuilder { baseCenter(); return self; }
    function invertColors(val as Boolean) as TextBoxBuilder { baseInvertColors(val); return self; }
    function move(direction as Number, amount as Number) as TextBoxBuilder { baseMove(direction, amount); return self; }
    function placeOutside(direction as Number) as TextBoxBuilder { basePlaceOutside(direction); return self; }
    function setActive(a as Boolean) as TextBoxBuilder { baseSetActive(a); return self; }
    function setPosition(px as Number, py as Number) as TextBoxBuilder { baseSetPosition(px, py); return self; }
    function setTransparent(val as Boolean) as TextBoxBuilder { baseSetTransparent(val); return self; }
    function setX(px as Number) as TextBoxBuilder { baseSetX(px); return self; }
    function setY(py as Number) as TextBoxBuilder { baseSetY(py); return self; }

    function setText(t as String) as TextBoxBuilder {
        text = t;
        return self;
    }

    function setFont(f as Number) as TextBoxBuilder {
        font = f;
        return self;
    }

    function setAlignment(a as Number) as TextBoxBuilder {
        alignment = a;
        return self;
    }

    function setComponentPosition(px as Number, py as Number) as TextBoxBuilder {
        componentX = px;
        componentY = py;
        return self;
    }

    function setComponentSize(w as Number, h as Number) as TextBoxBuilder {
        componentWidth = w;
        componentHeight = h;
        return self;
    }
}

// RectangleBuilder: a filled rectangle, optionally flicking. The flick is a
// cursor blink -- the source runs it off Time.deltaTime in Update, so it is
// advanced here once per frame with the frame's own elapsed milliseconds
// rather than from the wall clock.
class RectangleBuilder extends ScreenElement {
    var activeColor as Boolean = true;      // SetColor(true) = ink, false = field
    var flickPeriodMs as Number = 0;
    var flickOn as Boolean = true;
    var _flickElapsedMs as Number = 0;

    function initialize() {
        ScreenElement.initialize();
    }

    function center() as RectangleBuilder { baseCenter(); return self; }
    function invertColors(val as Boolean) as RectangleBuilder { baseInvertColors(val); return self; }
    function move(direction as Number, amount as Number) as RectangleBuilder { baseMove(direction, amount); return self; }
    function placeOutside(direction as Number) as RectangleBuilder { basePlaceOutside(direction); return self; }
    function setActive(a as Boolean) as RectangleBuilder { baseSetActive(a); return self; }
    function setPosition(px as Number, py as Number) as RectangleBuilder { baseSetPosition(px, py); return self; }
    function setSize(w as Number, h as Number) as RectangleBuilder { baseSetSize(w, h); return self; }
    function setTransparent(val as Boolean) as RectangleBuilder { baseSetTransparent(val); return self; }
    function setX(px as Number) as RectangleBuilder { baseSetX(px); return self; }
    function setY(py as Number) as RectangleBuilder { baseSetY(py); return self; }

    function setColor(useActiveColor as Boolean) as RectangleBuilder {
        activeColor = useActiveColor;
        return self;
    }

    // The source takes seconds as a float; milliseconds are exact at 20 fps
    // and avoid a float compare in the frame loop.
    function setFlickPeriodMs(periodMs as Number, startEnabled as Boolean) as RectangleBuilder {
        flickPeriodMs = periodMs;
        flickOn = startEnabled;
        return self;
    }

    function resetFlick(startEnabled as Boolean) as RectangleBuilder {
        _flickElapsedMs = 0;
        flickOn = startEnabled;
        return self;
    }

    // RectangleBuilder.Update: a period of 0 means "always on", and a period
    // that has elapsed toggles.
    function advanceFlick(elapsedMs as Number) as Void {
        if (flickPeriodMs == 0) {
            flickOn = true;
            return;
        }
        _flickElapsedMs += elapsedMs;
        if (_flickElapsedMs >= flickPeriodMs) {
            _flickElapsedMs = 0;
            flickOn = !flickOn;
        }
    }
}

// ContainerBuilder: groups children, optionally clipping them (RectMask2D)
// and optionally drawing an ink-coloured background (SetBackgroundBlack).
class ContainerBuilder extends ScreenElement {
    var maskActive as Boolean = true;
    var backgroundBlack as Boolean = false;

    function initialize() {
        ScreenElement.initialize();
    }

    function center() as ContainerBuilder { baseCenter(); return self; }
    function move(direction as Number, amount as Number) as ContainerBuilder { baseMove(direction, amount); return self; }
    function placeOutside(direction as Number) as ContainerBuilder { basePlaceOutside(direction); return self; }
    function setActive(a as Boolean) as ContainerBuilder { baseSetActive(a); return self; }
    function setPosition(px as Number, py as Number) as ContainerBuilder { baseSetPosition(px, py); return self; }
    function setSize(w as Number, h as Number) as ContainerBuilder { baseSetSize(w, h); return self; }
    function setTransparent(val as Boolean) as ContainerBuilder { baseSetTransparent(val); return self; }
    function setX(px as Number) as ContainerBuilder { baseSetX(px); return self; }
    function setY(py as Number) as ContainerBuilder { baseSetY(py); return self; }

    function setChildPosition(index as Number, px as Number, py as Number) as ContainerBuilder {
        var child = children[index];
        child.baseSetPosition(px, py);
        return self;
    }

    function setChildActive(index as Number, a as Boolean) as ContainerBuilder {
        children[index].baseSetActive(a);
        return self;
    }

    function setMaskActive(a as Boolean) as ContainerBuilder {
        maskActive = a;
        return self;
    }

    function setBackgroundBlack(val as Boolean) as ContainerBuilder {
        backgroundBlack = val;
        return self;
    }
}
