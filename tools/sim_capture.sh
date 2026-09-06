#!/bin/zsh
# Save the Connect IQ simulator's current screen to an absolute path.
#
# The SDK has no CLI for this and macOS screen recording is not granted to
# the terminal, so the only route is the simulator's own File > Save Screen
# Capture. Its Save panel is a native NSSavePanel hosted by a Java app, which
# has two consequences worth writing down:
#
#   - it defaults to "Macintosh HD", which is read-only, so a plain filename
#     fails with "error 30: Read-only file system"
#   - Cmd+Shift+G does not reach it, but typing "/" into the panel does open
#     the Go To sheet, and that is the only way found to reach a directory
#     outside the default
#
# Usage: tools/sim_capture.sh /absolute/path/frame.png
set -e
OUT="$1"
[[ "$OUT" == /* ]] || { echo "need an absolute path" >&2; exit 2; }
DIR="${OUT:h}"
NAME="${OUT:t}"

osascript <<EOF > /dev/null
tell application "System Events" to tell process "simulator"
  set frontmost to true
  click menu item "Save Screen Capture" of menu 1 of menu bar item "File" of menu bar 1
  delay 2
  keystroke "/"
  delay 1.5
  set value of text field 1 of sheet 1 of window "Save" to "$DIR/"
  delay 1
  keystroke return
  delay 2
  set value of text field "Save As:" of splitter group 1 of window "Save" to "$NAME"
  delay 0.5
  click button "Save" of splitter group 1 of window "Save"
end tell
EOF

sleep 2
[[ -f "$OUT" ]] || { echo "capture did not appear at $OUT" >&2; exit 1; }
echo "$OUT"
