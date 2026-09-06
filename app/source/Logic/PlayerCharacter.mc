import Toybox.Lang;

// port of Logic/PlayerCharacter.cs
//
// Picks which of the character's ten sprites is showing. The original drives
// it with InvokeRepeating at 0.5 s; here the host calls updateSprite on the
// same half-second cadence, which the 50 ms frame divides exactly.
//
// 0-3: idle, 4-5: walking, 6: happy, 7: sad, 8: event, 9: evolving.
class PlayerCharacter {
    var gm as GameManager;
    var currentChar as Number;
    var currentSprite as Number = 0;

    var _usedAltSprite as Boolean = false;
    var _lastValue as Number = 0;

    function initialize(gmIn as GameManager, currentCharIn as Number) {
        gm = gmIn;
        currentChar = currentCharIn;
        currentSprite = 0;
    }

    function updateSprite() as Void {
        if (gm.isCharacterDefeated()) {
            currentSprite = 7;
        } else if (gm.isEventActive()) {
            if (_usedAltSprite) {
                _usedAltSprite = false;
                currentSprite = 0;
            } else {
                _usedAltSprite = true;
                currentSprite = 8;
            }
        } else if (gm.isCharacterWalking) {
            if (_usedAltSprite) {
                _usedAltSprite = false;
                currentSprite = 4;
            } else {
                _usedAltSprite = true;
                currentSprite = 5;
            }
        } else {
            // The idle branch only changes the sprite every OTHER call, and
            // then only three times in four: the character mostly stands
            // still and occasionally shifts.
            if (_usedAltSprite) {
                _usedAltSprite = false;
                return;
            }
            _usedAltSprite = true;
            if (Kaisa.Rand.rangeInt(0, 4) == 0) { return; }

            _lastValue = Kaisa.Rand.rangeInt(0, 4);
            currentSprite = _lastValue;
        }
    }
}
