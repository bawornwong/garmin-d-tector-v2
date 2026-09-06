import Toybox.Lang;

// port of Logic/Apps/Games/Battle.cs
//
// The heaviest surface in the game: eight screens, four ways to bring a
// Digimon into the fight (a D-Dock call, a digicode, a spirit evolution, an
// ancient evolution), digivolution and boosting mid-battle, and a turn loop
// of energy/crush/ability against an enemy whose choices come from
// AttackChooser.
//
// The rules are in SPEC section 8. The shape worth keeping in mind while
// reading: `originalDigimon` is the Digimon the player CALLED and is what the
// disobey rolls and the punishment on defeat use, while `friendlyDigimon` is
// what is currently on the field after any evolution.
//
// Battle is also an IAppController: it loads the CodeInput app inside itself
// for the digicode call, so it implements closeLoadedApp the way the host
// does.
class Battle extends DigiviceApp {
    const TIE_DAMAGE_THRESHOLD = 5;

    // BattleScreen
    const SCREEN_MAIN_MENU = 0;
    const SCREEN_DDOCKS = 1;
    const SCREEN_SPIRIT_ELEMENTS = 2;
    const SCREEN_SPIRIT_LIST = 3;
    const SCREEN_DIGITS_APP = 4;
    const SCREEN_COMBAT_MENU = 5;
    const SCREEN_ATTACK_MENU = 6;
    const SCREEN_REGULAR_EVOLVE = 7;

    // CallType
    const CALL_REGULAR = 0;
    const CALL_CODE = 1;
    const CALL_DIGIVOLUTION = 2;
    const CALL_ARMOR = 3;
    const CALL_SPIRIT = 4;
    const CALL_ANCIENT = 5;

    // EndBattleAnimation
    const END_ANIM_NONE = 0;
    const END_ANIM_ENEMY_ESCAPES = 1;

    var enemyAttackChooser as AttackChooser?;
    var victoryExp as Number = 0;
    var defeatExp as Number = 0;
    var playerLevel as Number = 1;

    var isDDockUsed as Array<Boolean> = [false, false, false, false];
    var _currentCallPoints as Number = 10;

    var originalDigimon as Digimon?;    // the one that was called; never evolves
    var friendlyDigimon as Digimon?;
    var friendlyStats as MutableCombatStats?;
    var attacksAwardSP as Boolean = false;
    var attacksCostSP as Boolean = false;

    var enemyDigimon as Digimon?;
    var enemyStats as MutableCombatStats?;

    var currentScreen as Number = 0;
    var menuIndex as Number = 0;        // 0 battle call, 1 spirit on, 2 digits, 3 escape
    var ddockIndex as Number = 0;
    var ddockPurpose as Number = 0;     // 0 battle call, 1 boost sacrifice

    var availableMenuOptions as Array<Number> = [];  // 0 attack 1 digivolve 2 card 3 boost 4 deport
    var combatMenuIndex as Number = 0;
    var attackIndex as Number = 0;      // 0 energy, 1 crush, 2 ability
    var callPointsForEvolution as Number = 0;
    var blockBattleMenuNavigation as Boolean = false;

    var availableElements as Array<Number> = [];
    var elementIndex as Number = 0;
    var galleryList as Array<Number> = [];
    var galleryIndex as Number = 0;

    var loadedApp as DigiviceApp?;

    var alterDistance as Boolean = false;
    var isBossBattle as Boolean = false;
    var rewardEnemy as Number = -1;     // -1 unset, 0 no, 1 yes (the C# bool?)
    var winAnimation as Number = 0;
    var effect as Number = 0;
    var bossLevel as Number = 0;

    function initialize(gmIn as GameManager, controllerIn, parent as ScreenElement) {
        DigiviceApp.initialize(gmIn, controllerIn, parent);
    }

    // Battle.Initialize
    function setup(enemyIndex as Number, alterDistanceIn as Boolean,
                   isBossBattleIn as Boolean) as Battle {
        enemyDigimon = gm.db.getDigimon(enemyIndex);
        alterDistance = alterDistanceIn;
        isBossBattle = isBossBattleIn;
        return self;
    }

    function selectedMenuOption() as Number {
        return availableMenuOptions[combatMenuIndex];
    }

    function selectedElement() as Number {
        return availableElements[elementIndex];
    }

    function areAllDDocksUsed() as Boolean {
        return isDDockUsed[0] && isDDockUsed[1] && isDDockUsed[2] && isDDockUsed[3];
    }

    function currentCallPoints() as Number {
        return _currentCallPoints;
    }

    function setCurrentCallPoints(v as Number) as Void {
        _currentCallPoints = v;
        if (_currentCallPoints < 0) { _currentCallPoints = 0; }
    }

    function spiritPower() as Number {
        return gm.logicMgr.spiritPower();
    }

    function setSpiritPower(v as Number) as Void {
        gm.logicMgr.setSpiritPower(v);
    }

    // --- Input ---

    function inputA() as Void {
        if (currentScreen == SCREEN_MAIN_MENU) {
            if (menuIndex == 0) {
                if (areAllDDocksUsed()) {
                    // "So no ddock is selected and DEFAULT_DIGIMON is summoned."
                    ddockIndex = 255;
                    chooseCurrentDDock();
                } else {
                    gm.audioMgr.playButtonA();
                    ddockPurpose = 0;
                    openDDocks();
                }
            } else if (menuIndex == 1) {
                galleryList = gm.getAllUnlockedDigimonInStage(Kaisa.STAGE_SPIRIT);
                if (galleryList.size() > 0) {
                    gm.audioMgr.playButtonA();
                    openSpiritMenu();
                } else {
                    gm.audioMgr.playButtonB();
                }
            } else if (menuIndex == 2) {
                gm.audioMgr.playButtonA();
                openDigits();
            } else if (menuIndex == 3) {
                gm.audioMgr.playButtonA();
                escapeBattle();
            }
        } else if (currentScreen == SCREEN_DDOCKS) {
            if (isDDockUsed[ddockIndex]) {
                gm.audioMgr.playButtonB();
            } else {
                if (ddockPurpose == 1 && gm.logicMgr.isDDockEmpty(ddockIndex)) {
                    gm.audioMgr.playButtonB();
                    return;
                }
                gm.audioMgr.playButtonA();
                chooseCurrentDDock();
            }
        } else if (currentScreen == SCREEN_COMBAT_MENU) {
            if (selectedMenuOption() == 0) {
                gm.audioMgr.playButtonA();
                currentScreen = SCREEN_ATTACK_MENU;
                attackIndex = 0;
            } else if (selectedMenuOption() == 1) {
                if (currentCallPoints() > 0) {
                    gm.audioMgr.playButtonA();
                    openDigivolve();
                } else {
                    gm.audioMgr.playButtonB();
                }
            } else if (selectedMenuOption() == 3) {
                gm.audioMgr.playButtonA();
                ddockPurpose = 1;
                openDDocks();
            } else if (selectedMenuOption() == 4) {
                gm.audioMgr.playButtonA();
                deportCurrentDigimon();
            }
        } else if (currentScreen == SCREEN_SPIRIT_ELEMENTS) {
            gm.audioMgr.playButtonA();
            openSpiritGallery();
        } else if (currentScreen == SCREEN_SPIRIT_LIST) {
            // "Check if the player has the necessary spirit forms to evolve
            // into the Digimon they chose."
            //
            // SOURCE BUG, reproduced: the first test is
            // `spiritType == Hybrid && spiritType == Ancient`, which is never
            // true, so a hybrid's both-forms requirement is never checked and
            // the else branch allows it.
            var attempted = gm.db.getDigimon(galleryList[galleryIndex]);
            var canChoose = false;
            if (attempted.spiritType == Kaisa.SPIRIT_HYBRID
                    && attempted.spiritType == Kaisa.SPIRIT_ANCIENT) {
                canChoose = gm.hasBothFormsOfSpirit(attempted.element);
            } else if (attempted.spiritType == Kaisa.SPIRIT_FUSION) {
                canChoose = gm.hasAllSpiritsForFusion(attempted.index);
            } else {
                canChoose = true;
            }

            if (canChoose) {
                gm.audioMgr.playButtonA();
                chooseSpiritFromGallery();
            } else {
                gm.audioMgr.playButtonB();
            }
        } else if (currentScreen == SCREEN_ATTACK_MENU) {
            gm.audioMgr.playButtonA();
            submitTurn(attackIndex);
            blockBattleMenuNavigation = false;
        } else if (currentScreen == SCREEN_REGULAR_EVOLVE) {
            gm.audioMgr.playButtonA();
            attemptRegularDigivolve();
            blockBattleMenuNavigation = true;
            combatMenuIndex = 0;
        } else if (currentScreen == SCREEN_DIGITS_APP) {
            loadedApp.inputA();
        }
    }

    function inputB() as Void {
        if (currentScreen == SCREEN_MAIN_MENU || currentScreen == SCREEN_COMBAT_MENU) {
            // B on either menu shows the spirit power rather than backing out:
            // there is no leaving a battle except by escaping it.
            gm.enqueueAnimation(new PaySpiritPower(gm, spiritPower(), spiritPower()));
        } else if (currentScreen == SCREEN_DDOCKS) {
            closeDDocks();
            gm.audioMgr.playButtonB();
        } else if (currentScreen == SCREEN_SPIRIT_ELEMENTS) {
            gm.audioMgr.playButtonB();
            currentScreen = SCREEN_MAIN_MENU;
        } else if (currentScreen == SCREEN_SPIRIT_LIST) {
            gm.audioMgr.playButtonB();
            currentScreen = SCREEN_SPIRIT_ELEMENTS;
        } else if (currentScreen == SCREEN_ATTACK_MENU) {
            gm.audioMgr.playButtonB();
            currentScreen = SCREEN_COMBAT_MENU;
        } else if (currentScreen == SCREEN_REGULAR_EVOLVE) {
            gm.audioMgr.playButtonB();
            closeDigivolve();
        } else if (currentScreen == SCREEN_DIGITS_APP) {
            loadedApp.inputB();
        }
    }

    function inputLeft() as Void { side(-1); }
    function inputRight() as Void { side(1); }

    // InputLeft and InputRight differ only in the sign and in which end of a
    // range refuses to move.
    function side(delta as Number) as Void {
        if (currentScreen == SCREEN_MAIN_MENU) {
            gm.audioMgr.playButtonA();
            menuIndex = Kaisa.MathExt.circularAdd(menuIndex, delta, 3, 0);
        } else if (currentScreen == SCREEN_DDOCKS) {
            gm.audioMgr.playButtonA();
            ddockIndex = Kaisa.MathExt.circularAdd(ddockIndex, delta, 3, 0);
        } else if (currentScreen == SCREEN_COMBAT_MENU) {
            if (blockBattleMenuNavigation) {
                gm.audioMgr.playButtonB();
            } else {
                gm.audioMgr.playButtonA();
                combatMenuIndex = Kaisa.MathExt.circularAdd(
                    combatMenuIndex, delta, availableMenuOptions.size() - 1, 0);
            }
        } else if (currentScreen == SCREEN_SPIRIT_ELEMENTS) {
            if (availableElements.size() > 1) {
                gm.audioMgr.playButtonA();
                elementIndex = Kaisa.MathExt.circularAdd(
                    elementIndex, delta, availableElements.size() - 1, 0);
            } else {
                gm.audioMgr.playButtonB();
            }
        } else if (currentScreen == SCREEN_SPIRIT_LIST) {
            if (galleryList.size() > 1) {
                gm.audioMgr.playButtonA();
                galleryIndex = Kaisa.MathExt.circularAdd(
                    galleryIndex, delta, galleryList.size() - 1, 0);
            } else {
                gm.audioMgr.playButtonB();
            }
        } else if (currentScreen == SCREEN_ATTACK_MENU) {
            gm.audioMgr.playButtonA();
            attackIndex = Kaisa.MathExt.circularAdd(attackIndex, delta, 2, 0);
        } else if (currentScreen == SCREEN_REGULAR_EVOLVE) {
            // The call points spent on an evolution attempt run from 1 to
            // whatever the player has left.
            if (delta < 0) {
                if (callPointsForEvolution <= 1) { gm.audioMgr.playButtonB(); }
                else { gm.audioMgr.playButtonA(); callPointsForEvolution -= 1; }
            } else {
                if (callPointsForEvolution >= currentCallPoints()) { gm.audioMgr.playButtonB(); }
                else { gm.audioMgr.playButtonA(); callPointsForEvolution += 1; }
            }
        } else if (currentScreen == SCREEN_DIGITS_APP) {
            if (delta < 0) { loadedApp.inputLeft(); } else { loadedApp.inputRight(); }
        }
    }

    // The down/up halves reach the loaded CodeInput app, which uses them.
    function inputLeftDown() as Void {
        if (currentScreen == SCREEN_DIGITS_APP) { loadedApp.inputLeftDown(); }
    }
    function inputRightDown() as Void {
        if (currentScreen == SCREEN_DIGITS_APP) { loadedApp.inputRightDown(); }
    }
    function inputLeftUp() as Void {
        if (currentScreen == SCREEN_DIGITS_APP) { loadedApp.inputLeftUp(); }
    }
    function inputRightUp() as Void {
        if (currentScreen == SCREEN_DIGITS_APP) { loadedApp.inputRightUp(); }
    }

    function startApp() as Void {
        playerLevel = gm.logicMgr.getPlayerLevel();
        assignEnemyDigimon();
        gm.updateLeaverBuster(defeatExp, -1);
        drawScreen();
    }

    // InvokeRepeating("DrawScreen", 0f, 0.05f) -- every frame.
    function tick(elapsedMs as Number) as Void {
        drawScreen();
    }

    function drawScreen() as Void {
        clearScreen();

        if (currentScreen == SCREEN_MAIN_MENU) {
            setScreen(Kaisa.Sprites.BATTLE_MAIN_MENU[menuIndex]);
        } else if (currentScreen == SCREEN_DDOCKS) {
            gm.buildDDockScreenElement(ddockIndex, screen);
        } else if (currentScreen == SCREEN_COMBAT_MENU) {
            setScreen(Kaisa.Sprites.BATTLE_COMBAT_MENU[selectedMenuOption()]);
        } else if (currentScreen == SCREEN_ATTACK_MENU) {
            setScreen(Kaisa.Sprites.BATTLE_ATTACK_MENU[attackIndex]);
        } else if (currentScreen == SCREEN_REGULAR_EVOLVE) {
            setScreen(Kaisa.Sprites.BATTLE_CALL_POINTS_CHOOSER);
            Kaisa.ScreenBuilder.buildRectangle("EvolutionCP", screen)
                .setSize(3 * callPointsForEvolution, 3).setPosition(1, 27);
        } else if (currentScreen == SCREEN_SPIRIT_ELEMENTS) {
            if (selectedElement() < 10) {
                setScreen(Kaisa.Sprites.ELEMENTS[selectedElement()]);
            } else {
                setScreen(Kaisa.Sprites.DATABASE_SPIRIT_FUSION);
            }
        } else if (currentScreen == SCREEN_SPIRIT_LIST) {
            var displayDigimon = galleryList[galleryIndex];
            setScreen(Kaisa.Sprites.ARROWS_SMALL);
            // An ancient spirit shows its own art; the rest show their spirit
            // form.
            var action = (gm.data.spiritType(displayDigimon) != Kaisa.SPIRIT_ANCIENT)
                ? gm.data.ACTION_SP : gm.data.ACTION_BASE;
            Kaisa.ScreenBuilder.buildSprite("DigimonDisplay", screen)
                .setSize(24, 24).setSprite(gm.data.spriteRef(displayDigimon, action)).center();
        }
    }

    function assignEnemyDigimon() as Void {
        if (isBossBattle) {
            gm.enqueueAnimation(null);          // Animations.EncounterBoss
            bossLevel = gm.logicMgr.getPlayerLevel();
            enemyStats = enemyDigimon.getBossStats(bossLevel);
            victoryExp = gm.logicMgr.getExperienceGained(playerLevel, bossLevel);
            defeatExp = gm.logicMgr.getExperienceGained(bossLevel, playerLevel);
        } else {
            gm.enqueueAnimation(null);          // Animations.EncounterEnemy
            enemyStats = enemyDigimon.getRegularStats();
            victoryExp = gm.logicMgr.getExperienceGained(playerLevel, enemyDigimon.baseLevel);
            defeatExp = gm.logicMgr.getExperienceGained(enemyDigimon.baseLevel, playerLevel);
        }
        enemyAttackChooser = new AttackChooser(gm.getRandomSavedSeed(),
                                               enemyDigimon.index, enemyStats);
    }

    // --- Screens ---

    function openDDocks() as Void {
        currentScreen = SCREEN_DDOCKS;
        ddockIndex = 0;
    }

    function closeDDocks() as Void {
        currentScreen = (ddockPurpose == 0) ? SCREEN_MAIN_MENU : SCREEN_COMBAT_MENU;
    }

    function chooseCurrentDDock() as Void {
        if (ddockPurpose == 0) {
            // "If the player has no call points left, he will summon Numemon
            // regardless of their choice."
            var digimon = (currentCallPoints() > 0 && ddockIndex < 4)
                ? gm.logicMgr.getDDockDigimon(ddockIndex)
                : Kaisa.WellKnown.DEFAULT_DIGIMON;
            var callPointsBefore = currentCallPoints();
            if (ddockIndex < 4) { isDDockUsed[ddockIndex] = true; }

            currentScreen = SCREEN_COMBAT_MENU;
            availableMenuOptions = [0, 1, 4];   // "2: Battle-card temporarily disabled."
            combatMenuIndex = 0;

            assignFriendlyDigimon(digimon, CALL_REGULAR);

            gm.enqueueAnimation(null);          // Animations.SpendCallPoints
            gm.enqueueAnimation(null);          // Animations.SummonDigimon
        } else if (ddockPurpose == 1) {
            currentScreen = SCREEN_COMBAT_MENU;
            combatMenuIndex = 0;
            blockBattleMenuNavigation = true;
            attemptBoost(gm.logicMgr.getDDockDigimon(ddockIndex));
        }
    }

    function openDigivolve() as Void {
        currentScreen = SCREEN_REGULAR_EVOLVE;
        callPointsForEvolution = 1;
    }

    function closeDigivolve() as Void {
        currentScreen = SCREEN_COMBAT_MENU;
    }

    // "Todo: Merge this with App.Database, as it's the same code." -- and it
    // is: the same set-then-sort of the elements present in the gallery.
    function openSpiritMenu() as Void {
        availableElements = [];
        for (var i = 0; i < galleryList.size(); i += 1) {
            addElement(gm.data.element(galleryList[i]));
        }
        if (gm.getAllUnlockedFusionDigimon().size() > 0) { addElement(10); }
        elementIndex = 0;
        currentScreen = SCREEN_SPIRIT_ELEMENTS;
    }

    function addElement(element as Number) as Void {
        for (var i = 0; i < availableElements.size(); i += 1) {
            if (availableElements[i] == element) { return; }
            if (availableElements[i] > element) {
                var head = availableElements.slice(0, i);
                head.add(element);
                availableElements = head.addAll(availableElements.slice(i, null));
                return;
            }
        }
        availableElements.add(element);
    }

    function openSpiritGallery() as Void {
        galleryIndex = 0;
        currentScreen = SCREEN_SPIRIT_LIST;
        if (selectedElement() < 10) {
            galleryList = gm.getAllUnlockedSpiritsOfElement(selectedElement());
        } else {
            galleryList = gm.getAllUnlockedFusionDigimon();
        }
    }

    function chooseSpiritFromGallery() as Void {
        var chosen = galleryList[galleryIndex];
        var chosenDigimon = gm.db.getDigimon(chosen);

        // Not enough spirit power falls back to the default spirit Digimon.
        if (chosenDigimon.getSpiritCost(playerLevel) > spiritPower()) {
            chosen = Kaisa.WellKnown.DEFAULT_SPIRIT_DIGIMON;
            chosenDigimon = gm.db.getDigimon(chosen);
        }

        if (chosen == Kaisa.WellKnown.DEFAULT_SPIRIT_DIGIMON) {
            assignFriendlyDigimon(chosen, CALL_ANCIENT);
            gm.enqueueAnimation(null);          // Animations.SpiritEvolution
        } else if (chosenDigimon.spiritType == Kaisa.SPIRIT_ANCIENT) {
            var spBefore = spiritPower();
            assignFriendlyDigimon(chosen, CALL_ANCIENT);
            gm.enqueueAnimation(new PaySpiritPower(gm, spBefore, spiritPower()));
            gm.enqueueAnimation(null);          // Animations.AncientEvolution
        } else {
            assignFriendlyDigimon(chosen, CALL_SPIRIT);
            // SpiritEvolution / FusionSpiritEvolution / SusanoomonEvolution,
            // none converted yet.
            gm.enqueueAnimation(null);
        }

        availableMenuOptions = [0, 3, 4];
        currentScreen = SCREEN_COMBAT_MENU;
        combatMenuIndex = 0;
    }

    function openDigits() as Void {
        currentScreen = SCREEN_DIGITS_APP;
        loadedApp = new CodeInput(gm, self, screen).setSubmitError(true);
        loadedApp.startApp();
    }

    function submitCode(digimon as Number) as Void {
        var d = gm.db.getDigimon(digimon);
        var chosen = digimon;
        // "You can't summon Armor- or Spirit-Stage digimon from here."
        if (d != null && (d.stage == Kaisa.STAGE_ARMOR || d.stage == Kaisa.STAGE_SPIRIT)) {
            chosen = Kaisa.WellKnown.DEFAULT_DIGIMON;
        }
        gm.logicMgr.setDigimonUnlocked(chosen, true);
        gm.logicMgr.setDigicodeUnlocked(chosen, true);

        currentScreen = SCREEN_COMBAT_MENU;
        availableMenuOptions = [0, 1, 4];
        combatMenuIndex = 0;

        assignFriendlyDigimon(chosen, CALL_CODE);
        gm.enqueueAnimation(null);              // Animations.SummonDigimon
    }

    // IAppController, for the CodeInput app this one loads.
    function closeLoadedApp(newScreen as Number) as Void {
        if (loadedApp instanceof CodeInput) {
            var result = (loadedApp as CodeInput).returnedDigimon;
            if (result >= 0) {
                submitCode(result);
            } else {
                currentScreen = SCREEN_MAIN_MENU;
            }
        }
        loadedApp.dispose();
        loadedApp = null;
    }

    // --- Calling and evolving ---

    function assignFriendlyDigimon(digimon as Number, callType as Number) as Void {
        friendlyDigimon = gm.db.getDigimon(digimon);
        if (friendlyDigimon == null) {
            friendlyDigimon = gm.db.getDigimon(Kaisa.WellKnown.DEFAULT_DIGIMON);
        }

        if (callType == CALL_REGULAR) {
            attacksAwardSP = true;
            setCurrentCallPoints(currentCallPoints() - friendlyDigimon.getCallCost(playerLevel));
            summonRegularDigimon(digimon);
        } else if (callType == CALL_CODE) {
            setSpiritPower(spiritPower() - 20);
            summonRegularDigimon(digimon);
        } else if (callType == CALL_DIGIVOLUTION) {
            // "Store the missing HP to apply it to the new digimon."
            var missingHP = friendlyStats.getMissingHP();
            var extraLevel = gm.logicMgr.getDigimonExtraLevel(friendlyDigimon.index);
            friendlyStats = friendlyDigimon.getFriendlyStats(extraLevel);
            friendlyStats.applyMissingHP(missingHP);

            if (!gm.logicMgr.getDigimonUnlocked(friendlyDigimon.index)) {
                gm.logicMgr.setDigimonUnlocked(friendlyDigimon.index, true);
            }
        } else if (callType == CALL_SPIRIT) {
            attacksCostSP = true;
            originalDigimon = friendlyDigimon;
            friendlyStats = friendlyDigimon.getBossStats(playerLevel);
        } else if (callType == CALL_ANCIENT) {
            setSpiritPower(spiritPower() - friendlyDigimon.getSpiritCost(playerLevel));
            originalDigimon = friendlyDigimon;
            friendlyStats = friendlyDigimon.getBossStats(playerLevel);
        }

        gm.updateLeaverBuster(defeatExp,
            (originalDigimon == null) ? -1 : originalDigimon.index);
    }

    // The original's local function SummonRegularDigimon.
    function summonRegularDigimon(digimon as Number) as Void {
        originalDigimon = friendlyDigimon;
        var extraLevel = gm.logicMgr.getDigimonExtraLevel(digimon);
        friendlyStats = friendlyDigimon.getFriendlyStats(extraLevel);
    }

    function attemptRegularDigivolve() as Void {
        var callPointsBefore = currentCallPoints();
        var target = (friendlyDigimon.evolutionIndex >= 0)
            ? gm.db.getDigimon(friendlyDigimon.evolutionIndex) : null;

        setCurrentCallPoints(currentCallPoints() - callPointsForEvolution);
        // "(int) < null always evaluates to false" -- a Digimon with no
        // evolution simply fails the roll.
        if (target != null
                && Kaisa.Rand.rangeFloat(0.0, 1.0)
                    < target.getEvolveChance(playerLevel, callPointsForEvolution)) {
            if (!gm.logicMgr.getDigimonUnlocked(target.index)) {
                gm.logicMgr.setDigimonUnlocked(target.index, true);
            }
            assignFriendlyDigimon(target.index, CALL_DIGIVOLUTION);
        }

        gm.enqueueAnimation(null);              // Animations.SpendCallPoints
        gm.enqueueAnimation(null);              // Animations.RegularEvolution
        closeDigivolve();
    }

    // Sacrificing a Digimon from a D-Dock to boost the one fighting.
    function attemptBoost(sacrificeIndex as Number) as Void {
        var sacrifice = gm.db.getDigimon(sacrificeIndex);
        if (sacrificeIndex >= 0) {
            gm.logicMgr.setDigimonUnlocked(sacrificeIndex, false);
        }
        var rng;
        if (sacrifice == null) {
            sacrifice = gm.db.getDigimon(Kaisa.WellKnown.DEFAULT_DIGIMON);
            rng = 1.0;
        } else {
            rng = Kaisa.Rand.rangeFloat(0.0, 1.0);
        }

        if (rng < sacrifice.getObeyChance(playerLevel)) {
            var sacrificeStats = sacrifice.getFriendlyStats(
                gm.logicMgr.getDigimonExtraLevel(sacrifice.index));
            var halfHP = Kaisa.MathExt.ceilToInt(sacrificeStats.hp / 2.0);
            friendlyStats.hp += halfHP;
            friendlyStats.maxHP += halfHP;
            friendlyStats.en += sacrificeStats.en;
            friendlyStats.cr += sacrificeStats.cr;
            friendlyStats.ab += sacrificeStats.ab;
            gm.enqueueAnimation(null);          // Animations.BoostSucceed
        } else {
            gm.enqueueAnimation(null);          // Animations.BoostFailed
        }
    }

    function deportCurrentDigimon() as Void {
        playAnimationDeportDigimon();

        friendlyDigimon = null;
        originalDigimon = null;
        friendlyStats = null;
        attacksAwardSP = false;
        attacksCostSP = false;

        currentScreen = SCREEN_MAIN_MENU;
        gm.updateLeaverBuster(defeatExp, -1);
    }

    function playAnimationDeportDigimon() as Void {
        // DeportSpirit for a spirit, DeportDigimon otherwise; neither is
        // converted yet.
        gm.enqueueAnimation(null);
    }

    // --- The turn ---

    function submitTurn(friendlyAttack as Number) as Void {
        var spBefore = spiritPower();
        if (attacksAwardSP) {
            setSpiritPower(spBefore + 3);
        } else if (attacksCostSP) {
            setSpiritPower(spBefore - friendlyDigimon.getSpiritCost(playerLevel));
            gm.enqueueAnimation(new PaySpiritPower(gm, spBefore, spiritPower()));
        }

        var enemyAttack = enemyAttackChooser.next();
        var turn = executeTurn(friendlyAttack, enemyAttack);
        var chosenAttack = turn[0];
        var winner = turn[1];
        var loserHPbefore = turn[2];
        var loserHPnow = (winner == 0) ? enemyStats.hp : friendlyStats.hp;

        gm.enqueueAnimation(null);              // Animations.DisplayTurn

        var battleEnded = (loserHPnow == 0);

        if (battleEnded && winner == 0 && winAnimation == END_ANIM_ENEMY_ESCAPES) {
            gm.enqueueAnimation(null);          // Animations.EnemyEscapes
        }

        if (attacksAwardSP) {
            gm.enqueueAnimation(new AWardSpiritPower(gm, spBefore));
        }

        currentScreen = SCREEN_COMBAT_MENU;

        if (battleEnded) {
            if (winner == 0) { winBattle(); } else { loseBattle(); }
        } else if (attacksCostSP
                && spiritPower() < friendlyDigimon.getSpiritCost(playerLevel)) {
            deportCurrentDigimon();
        }
    }

    // ExecuteTurn: the C# takes friendlyAttack by reference and may change it
    // when the Digimon disobeys, so the port returns it:
    // [friendlyAttack, winner, loserHPbefore, disobeyed].
    function executeTurn(friendlyAttackIn as Number, enemyAttack as Number) as Array<Number> {
        var friendlyAttack = friendlyAttackIn;
        var disobeyed = 0;

        if (Kaisa.Rand.rangeFloat(0.0, 1.0) > originalDigimon.getIdleChance(playerLevel)) {
            friendlyAttack = 3;                 // it does not attack at all
            disobeyed = 1;
        } else if (Kaisa.Rand.rangeFloat(0.0, 1.0) > originalDigimon.getObeyChance(playerLevel)) {
            friendlyAttack = Kaisa.Rand.rangeInt(0, 3);
            disobeyed = 1;
        }

        var chosen = chooseWinner(friendlyAttack, enemyAttack);
        var winner = chosen[0];
        var damageDealt = chosen[1];

        var loserHPbefore = (winner == 0) ? enemyStats.hp : friendlyStats.hp;

        if (winner == 0) { damageDigimon(1, damageDealt); }
        if (winner == 1) { damageDigimon(0, damageDealt); }

        return [friendlyAttack, winner, loserHPbefore, disobeyed];
    }

    // Returns [winner, damageDealt]; winner 2 is a tie.
    function chooseWinner(friendlyAttack as Number, enemyAttack as Number) as Array<Number> {
        var friendlyDamage = friendlyStats.getAttackDamage(friendlyAttack);
        var enemyDamage = enemyStats.getAttackDamage(enemyAttack);

        if (friendlyAttack == 3) {              // the Digimon did not attack
            return [1, enemyDamage];
        }

        if (friendlyAttack == enemyAttack) {
            var difference = friendlyDamage - enemyDamage;
            var damageDealt = (difference < 0) ? -difference : difference;

            // "If both Digimons used Energy and their Energies have different
            // rank (have different sprite), the higher rank energy always
            // wins."
            if (friendlyAttack == 0 && friendlyStats.getEnergyRank() != enemyStats.getEnergyRank()) {
                return [(friendlyStats.getEnergyRank() > enemyStats.getEnergyRank()) ? 0 : 1,
                        damageDealt];
            }
            if (difference <= -TIE_DAMAGE_THRESHOLD) { return [1, damageDealt]; }
            if (difference >= TIE_DAMAGE_THRESHOLD) { return [0, damageDealt]; }
            return [2, damageDealt];
        }

        // Energy beats ability, crush beats energy, ability beats crush.
        if (friendlyAttack == 0) {
            if (enemyAttack == 2) { return [0, friendlyDamage]; }
            if (enemyAttack == 1) { return [1, enemyDamage]; }
        } else if (friendlyAttack == 1) {
            if (enemyAttack == 0) { return [0, friendlyDamage]; }
            if (enemyAttack == 2) { return [1, enemyDamage]; }
        } else if (friendlyAttack == 2) {
            if (enemyAttack == 1) { return [0, friendlyDamage]; }
            if (enemyAttack == 0) { return [1, enemyDamage]; }
        }

        return [2, -1];
    }

    function damageDigimon(digimon as Number, damage as Number) as Void {
        var stats = (digimon == 0) ? friendlyStats : enemyStats;
        stats.hp -= damage;
        if (stats.hp < 0) { stats.hp = 0; }
    }

    // --- Ending the battle ---

    function winBattle() as Void {
        gm.disableLeaverBuster();
        playAnimationDeportDigimon();

        if (gm.logicMgr.addPlayerExperience(victoryExp)) {
            gm.enqueueAnimation(null);          // Animations.LevelUp
        }
        gm.enqueueAnimation(new CharHappy(gm));

        // "50% for regular battles. 0% for boss battles (they get unlocked in
        // TriggerVictoryAgainstBoss)."
        var reward = rewardEnemy;
        if (reward < 0) {
            reward = isBossBattle ? 1 : ((Kaisa.Rand.rangeInt(0, 2) == 1) ? 1 : 0);
        }
        if (reward == 1) {
            gm.logicMgr.rewardDigimon(enemyDigimon.index);
            // ReceiveSpirit / UnlockDigimon / LevelUpDigimon, not converted.
            gm.enqueueAnimation(null);
        } else if (gm.logicMgr.isAnySpiritLost() && Kaisa.Rand.rangeInt(0, 3) == 0) {
            gm.logicMgr.recoverSpirit();
            gm.enqueueAnimation(null);          // Animations.ReceiveSpirit
        }

        if (isBossBattle) {
            triggerVictoryAgainstBoss();
        } else if (alterDistance) {
            var before = gm.worldMgr.currentDistance();
            gm.worldMgr.reduceDistance(300);
            gm.enqueueAnimation(new ChangeDistance(gm, before, gm.worldMgr.currentDistance()));
        }

        gm.logicMgr.increaseTotalWins();
        gm.logicMgr.increaseTotalBattles();
        closeApp(Kaisa.SCREEN_CHARACTER);
    }

    function loseBattle() as Void {
        gm.disableLeaverBuster();
        playAnimationDeportDigimon();

        if (gm.logicMgr.removePlayerExperience(defeatExp)) {
            gm.enqueueAnimation(null);          // Animations.LevelDown
        }
        gm.enqueueAnimation(null);              // Animations.CharSad

        var punishFriendly = Kaisa.Rand.rangeFloat(0.0, 1.0)
            > gm.db.getEraseChance(originalDigimon.index);

        if (originalDigimon.stage != Kaisa.STAGE_SPIRIT) {
            // "If the player has extra levels with that digimon, they will
            // always lose one."
            if (gm.logicMgr.getDigimonExtraLevel(originalDigimon.index) > 0) {
                punishFriendly = true;
            }
            if (punishFriendly) {
                var result = gm.logicMgr.punishDigimon(originalDigimon.index);
                if (result[0] == 1) {           // levelled down rather than erased
                    if (Kaisa.Rand.rangeInt(0, 2) == 0) { gm.setCharacterDefeated(true); }
                    gm.enqueueAnimation(null);  // Animations.LevelDownDigimon
                } else {
                    gm.setCharacterDefeated(true);
                    gm.enqueueAnimation(null);  // Animations.EraseDigimon
                }
            }
        } else {
            // "Lose your Spirit if you were fighting with one."
            gm.setCharacterDefeated(true);
            gm.logicMgr.loseSpirit(originalDigimon.index);
            gm.enqueueAnimation(null);          // Animations.LoseSpirit
        }

        if (alterDistance) {
            var before = gm.worldMgr.currentDistance();
            gm.worldMgr.increaseDistance(isBossBattle ? 500 : 300);
            gm.enqueueAnimation(new ChangeDistance(gm, before, gm.worldMgr.currentDistance()));
        }

        gm.logicMgr.increaseTotalBattles();
        closeApp(Kaisa.SCREEN_CHARACTER);
    }

    function escapeBattle() as Void {
        gm.disableLeaverBuster();
        gm.enqueueAnimation(null);              // Animations.DeportSprite

        if (gm.logicMgr.removePlayerExperience(defeatExp)) {
            gm.enqueueAnimation(null);          // Animations.LevelDown
        }

        var before = gm.worldMgr.currentDistance();
        gm.worldMgr.increaseDistance(2000);

        gm.enqueueAnimation(null);              // Animations.CharSad
        gm.enqueueAnimation(new ChangeDistance(gm, before, gm.worldMgr.currentDistance()));

        gm.logicMgr.increaseTotalBattles();
        closeApp(Kaisa.SCREEN_CHARACTER);
    }

    // SOURCE ODDITY, reproduced: `currentMap` is read from CurrentWorld, not
    // from the current map, and the area is then marked completed against it.
    // With one world per save that is the same number; the port keeps the
    // original's expression rather than the intent.
    function triggerVictoryAgainstBoss() as Void {
        var currentWorld = gm.worldMgr.currentWorld();
        var currentMap = gm.worldMgr.currentWorld();
        var currentArea = gm.worldMgr.currentArea();
        gm.worldMgr.setAreaCompleted(currentMap, currentArea, true);
        var available = gm.worldMgr.getUncompletedAreas(currentMap);

        if (available.size() > 0) {
            var newArea = Kaisa.Tools.getRandomElement(available);
            gm.worldMgr.moveToArea(currentMap, newArea);
            gm.enqueueAnimation(null);          // Animations.ForcedTravelMap
        } else {
            gm.completeWorld(currentWorld);
        }
    }
}
