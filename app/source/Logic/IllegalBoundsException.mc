import Toybox.Lang;

// port of Logic/Models/IllegalBoundsException.cs
module Kaisa {
    class IllegalBoundsException extends Lang.Exception {
        function initialize(msg as String) {
            Exception.initialize();
            _message = msg;
        }
        var _message as String;
        function getErrorMessage() as String? {
            return _message;
        }
    }
}
