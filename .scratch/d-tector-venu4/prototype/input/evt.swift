// Minimal synthetic input for driving the Connect IQ simulator during the
// ticket 13 spike: mouse press-and-hold, mouse drag, and key press-and-hold
// with a real key code (AppleScript cannot hold a non-character key).
import Foundation
import CoreGraphics

func sleepMs(_ ms: Int) { usleep(UInt32(ms) * 1000) }

func mouse(_ type: CGEventType, _ p: CGPoint) {
    let e = CGEvent(mouseEventSource: nil, mouseType: type,
                    mouseCursorPosition: p, mouseButton: .left)
    e?.post(tap: .cghidEventTap)
}

func key(_ code: CGKeyCode, down: Bool) {
    let e = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)
    e?.post(tap: .cghidEventTap)
}

let a = CommandLine.arguments
switch a.count > 1 ? a[1] : "" {
case "press":
    let p = CGPoint(x: Double(a[2])!, y: Double(a[3])!)
    mouse(.mouseMoved, p); sleepMs(60)
    mouse(.leftMouseDown, p)
    sleepMs(Int(a[4])!)
    mouse(.leftMouseUp, p)
case "drag":
    let p1 = CGPoint(x: Double(a[2])!, y: Double(a[3])!)
    let p2 = CGPoint(x: Double(a[4])!, y: Double(a[5])!)
    let steps = Int(a[6])!, hold = Int(a[7])!
    mouse(.mouseMoved, p1); sleepMs(60)
    mouse(.leftMouseDown, p1); sleepMs(hold)
    for i in 1...steps {
        let t = Double(i) / Double(steps)
        mouse(.leftMouseDragged,
              CGPoint(x: p1.x + (p2.x - p1.x) * t, y: p1.y + (p2.y - p1.y) * t))
        sleepMs(hold)
    }
    mouse(.leftMouseUp, p2)
case "key":
    let code = CGKeyCode(UInt16(a[2])!)
    key(code, down: true)
    sleepMs(Int(a[3])!)
    key(code, down: false)
default:
    print("usage: evt press X Y HOLDMS | drag X1 Y1 X2 Y2 STEPS STEPMS | key CODE HOLDMS")
}
