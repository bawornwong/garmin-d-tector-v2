import Toybox.Lang;

// port of ScreenElement.cs's static creator methods, plus the screen helpers
// GameManager.cs keeps next to them (GetDDockScreenElement and friends).
//
// In Unity these instantiate prefabs; here they just build display-list
// elements and attach them, which is the whole of what the prefabs carried
// once the RectTransform was gone.
module Kaisa {
    module ScreenBuilder {
        function buildSprite(name as String, parent as ScreenElement) as SpriteBuilder {
            var sb = new SpriteBuilder();
            sb.setName(name);
            Kaisa.Trace.event("build sprite " + name);
            parent.addChild(sb);
            return sb;
        }

        function buildRectangle(name as String, parent as ScreenElement) as RectangleBuilder {
            var rb = new RectangleBuilder();
            rb.setName(name);
            Kaisa.Trace.event("build rectangle " + name);
            parent.addChild(rb);
            return rb;
        }

        function buildTextBox(name as String, parent as ScreenElement,
                              font as Number) as TextBoxBuilder {
            var tb = new TextBoxBuilder();
            tb.setName(name);
            Kaisa.Trace.event("build textBox " + name);
            tb.setFont(font);
            parent.addChild(tb);
            return tb;
        }

        // The container prefab starts transparent, which is why the C# default
        // for this argument is true.
        function buildContainer(name as String, parent as ScreenElement,
                                transparent as Boolean) as ContainerBuilder {
            var cb = new ContainerBuilder();
            cb.setName(name);
            Kaisa.Trace.event("build container " + name);
            cb.setTransparent(transparent);
            parent.addChild(cb);
            return cb;
        }

        // ScreenElement.BuildBackground
        function buildBackground(parent as ScreenElement) as RectangleBuilder {
            return buildRectangle("Parent", parent).setSize(32, 32).setColor(false);
        }

        // ScreenElement.BuildStatSign: a black band with a label on the left
        // and a value slot on the right. The value box is left empty here, as
        // in the original, and filled by the caller through getChildBuilder(1).
        function buildStatSign(message as String, parent as ScreenElement) as ContainerBuilder {
            var cbSign = buildContainer("Sign", parent, false)
                .setBackgroundBlack(true).setSize(32, 17).setPosition(0, 15);
            buildTextBox("Sign", cbSign, Kaisa.Font.SMALL)
                .setText(message)
                .setSize(28, 5)
                .setPosition(2, 2)
                .invertColors(true);
            buildTextBox("Sign", cbSign, Kaisa.Font.SMALL)
                .setSize(28, 5)
                .setPosition(2, 10)
                .setAlignment(Kaisa.Text.ANCHOR_UPPER_RIGHT)
                .invertColors(true);
            return cbSign;
        }

        // GameManager.GetDDockScreenElement: the dock's name plate, with the
        // Digimon standing in it -- or the empty-dock sprite when the dock
        // holds nothing (index -1).
        function buildDDockScreenElement(ddock as Number, digimonSprite as Array<Number>?,
                                         parent as ScreenElement) as SpriteBuilder {
            // SOURCE ODDITY, reproduced: the original names this element with
            // an uninterpolated C# format string, so its name really is the
            // literal "$DDock{ddock}" for every dock. Names are debug- and
            // trace-visible only, and ADR 2 says the original wins.
            var sbDDockName = buildSprite("$DDock{ddock}", parent)
                .setSprite(Kaisa.Sprites.STATUS_DDOCK[ddock]);
            var dockDigimon = digimonSprite;
            if (dockDigimon == null) { dockDigimon = Kaisa.Sprites.STATUS_DDOCK_EMPTY; }
            return buildSprite("DigimonDDock" + ddock, sbDDockName)
                .setSize(24, 24).setPosition(4, 8).setSprite(dockDigimon);
        }
    }
}
