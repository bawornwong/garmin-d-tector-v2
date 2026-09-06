import Toybox.Lang;
import Toybox.StringUtil;

// port of Logic/Apps/CodeInput.cs
//
// The five-character code entry: pick a letter or digit with left/right, push
// it with A, and when five are in, A checks them against the Digimon codes.
//
// The character wheel is stored as its ASCII byte exactly as the original
// does -- 0x41..0x5A then 0x30..0x39, wrapping between 'Z' and '0' and
// between '0' and 'Z' -- because the wrap arithmetic IS the wheel's order.
class CodeInput extends DigiviceApp {
    var submitError as Boolean = false;   // close even when the code is wrong
    var inputStatus as Number = 0;        // 0 inputting, 1 ok?, 2 error, 3 success
    var returnedDigimon as Number = -1;   // a packed-data index, -1 for none

    // UI
    var underscores as Array<RectangleBuilder> = [];
    var selectedInputDisplay as TextBoxBuilder?;
    var currentInputDisplay as TextBoxBuilder?;

    // Code info
    var selectedInput as Number = 0x41;
    var currentInput as Array<Number> = [];    // the Stack<byte>, top last
    var navigation as Fiber?;

    function initialize(gmIn as GameManager, controllerIn, parent as ScreenElement) {
        DigiviceApp.initialize(gmIn, controllerIn, parent);
    }

    // CodeInput.Initialize(bool)
    function setSubmitError(val as Boolean) as CodeInput {
        submitError = val;
        return self;
    }

    function inputIsEmpty() as Boolean {
        return currentInput.size() == 0;
    }

    function inputIsFull() as Boolean {
        return currentInput.size() == 5;
    }

    function selectedInputString() as String {
        return selectedInput.toChar().toString();
    }

    // Encoding.ASCII.GetString(currentInput.Reverse().ToArray()): the stack is
    // stored top-last here, so the string is simply the array in order.
    function currentInputString() as String {
        var bytes = []b;
        for (var i = 0; i < currentInput.size(); i += 1) {
            bytes.add(currentInput[i]);
        }
        return StringUtil.convertEncodedString(bytes, {
            :fromRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY,
            :toRepresentation => StringUtil.REPRESENTATION_STRING_PLAIN_TEXT
        }) as String;
    }

    // --- Input ---

    function inputA() as Void {
        if (!inputIsFull()) {
            gm.audioMgr.playButtonA();
            currentInput.add(selectedInput);
            if (inputIsFull()) { inputStatus = 1; }   // if this byte made five
        } else if (inputStatus == 1) {
            gm.audioMgr.playButtonA();
            checkCode();
        } else if (inputStatus == 2) {
            gm.audioMgr.playButtonA();
            pop();
            inputStatus = 0;
        }
    }

    function inputB() as Void {
        if (inputIsEmpty()) {
            gm.audioMgr.playButtonB();
            closeApp(Kaisa.SCREEN_MAIN_MENU);
        } else {
            gm.audioMgr.playButtonB();
            pop();
            inputStatus = 0;
        }
    }

    function pop() as Void {
        if (currentInput.size() > 0) {
            currentInput = currentInput.slice(0, currentInput.size() - 1);
        }
    }

    function inputLeftDown() as Void {
        startNavigation(Kaisa.DIR_LEFT);
    }

    function inputRightDown() as Void {
        startNavigation(Kaisa.DIR_RIGHT);
    }

    function inputLeftUp() as Void {
        sideUp(Kaisa.DIR_LEFT);
    }

    function inputRightUp() as Void {
        sideUp(Kaisa.DIR_RIGHT);
    }

    function sideUp(dir as Number) as Void {
        stopNavigation();
        if (!inputIsFull()) {
            gm.audioMgr.playButtonA();
            navigateInput(dir);
        } else if (inputIsFull() && inputStatus == 2) {
            gm.audioMgr.playButtonA();
            pop();
            inputStatus = 0;
        }
    }

    function startNavigation(dir as Number) as Void {
        stopNavigation();
        navigation = gm.runner.start(new CodeAutoNavigateDir(self, dir));
    }

    function stopNavigation() as Void {
        if (navigation != null) {
            gm.runner.stop(navigation);
            navigation = null;
        }
    }

    function dispose() as Void {
        stopNavigation();
        DigiviceApp.dispose();
    }

    function startApp() as Void {
        underscores = [];
        for (var i = 0; i < 5; i += 1) {
            underscores.add(Kaisa.ScreenBuilder.buildRectangle("Underscore" + i, screen)
                .setSize(5, 1).setPosition(2 + (6 * i), 25));
        }
        selectedInputDisplay = Kaisa.ScreenBuilder.buildTextBox("Input", screen, Kaisa.Font.BIG)
            .setSize(6, 8).setPosition(14, 8);
        currentInputDisplay = Kaisa.ScreenBuilder.buildTextBox("CurrentCode", screen, Kaisa.Font.BIG)
            .setSize(30, 8).setPosition(2, 17);
        updateScreen();
    }

    // The original's Update(): the app redraws every frame.
    function tick(elapsedMs as Number) as Void {
        updateScreen();
    }

    function updateScreen() as Void {
        currentInputDisplay.setText(currentInputString());

        for (var i = 0; i < underscores.size(); i += 1) {
            if (i == currentInput.size()) {
                // The cursor's underscore blinks; the rest are steady. Setting
                // the period only when it is currently 0 keeps the blink from
                // restarting on every frame.
                if (underscores[i].flickPeriodMs == 0) {
                    underscores[i].setFlickPeriodMs(400, false);
                }
            } else {
                underscores[i].setFlickPeriodMs(0, true);
            }
        }

        if (!inputIsFull()) {
            selectedInputDisplay.setActive(true);
            selectedInputDisplay.setText(selectedInputString());
            setScreen(Kaisa.Sprites.ARROWS);
        } else {
            selectedInputDisplay.setActive(false);
            if (inputStatus == 1) {
                setScreen(Kaisa.Sprites.DIGITS_OK);
            } else if (inputStatus == 2) {
                setScreen(Kaisa.Sprites.DIGITS_ERROR);
            }
        }
    }

    // The wheel: 'A'(0x41)..'Z'(0x5A) then '0'(0x30)..'9'(0x39), wrapping at
    // both seams.
    function navigateInput(dir as Number) as Void {
        if (inputIsFull()) { return; }
        if (dir == Kaisa.DIR_LEFT) {
            if (selectedInput == 0x41) { selectedInput = 0x39; }
            else if (selectedInput == 0x30) { selectedInput = 0x5A; }
            else { selectedInput -= 1; }
        } else {
            if (selectedInput == 0x5A) { selectedInput = 0x30; }
            else if (selectedInput == 0x39) { selectedInput = 0x41; }
            else { selectedInput += 1; }
        }
    }

    function checkCode() as Void {
        var digimon = gm.db.indexOfCode(currentInputString());
        if (digimon < 0) {
            if (submitError) {
                returnedDigimon = Kaisa.WellKnown.DEFAULT_DIGIMON;
                closeApp(Kaisa.SCREEN_MAIN_MENU);
            }
            inputStatus = 2;
        } else {
            returnedDigimon = digimon;
            closeApp(Kaisa.SCREEN_MAIN_MENU);
        }
    }
}

// port of CodeInput.AutoNavigateDir -- hold a side and the wheel spins.
class CodeAutoNavigateDir extends Routine {
    var app as CodeInput;
    var dir as Number;

    function initialize(appIn as CodeInput, dirIn as Number) {
        Routine.initialize();
        app = appIn;
        dir = dirIn;
    }

    function step(rt as Fiber) as Float {
        switch (pc) {
            case 0:
                pc = 1;
                return 0.25;
            case 1:
                pc = 2;
                return 0.1;
            case 2:
                app.gm.audioMgr.playButtonA();
                app.navigateInput(dir);
                pc = 1;                     // while (true)
                return 0.0;
        }
        return Routine.DONE;
    }
}
