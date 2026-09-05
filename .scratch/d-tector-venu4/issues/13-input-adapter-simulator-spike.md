# Input adapter simulator spike

Type: prototype
Status: open
Blocked by: 09

## Question

Do the two unverified assumptions behind the input mapping hold on `venu445mm`?

[Input abstraction layer](./09-input-abstraction-layer.md) decided the mapping — `KEY_ENTER`→A, `KEY_ESC`→B, left/right screen halves held via `onDrag`→Left/Right — but two things could not be settled from documentation.

Build a throwaway Connect IQ app that logs every input event with a timestamp, and answer:

1. **Does `DRAG_TYPE_STOP` always fire on finger lift?** Including a lift near the screen edge, a lift during a system gesture, and a lift while the app is losing focus. If it can be missed, an input latches down forever and Maze becomes unplayable — so establish the timeout fallback empirically.
2. **Does Venu 4 reserve long-press `KEY_ESC` for the system?** If it does, the app cannot use it to exit and needs another route out.
3. **Does holding a host key in the simulator produce one sustained down/up pair, or OS-rate repeats of `onKeyPressed`?** Left open by the input research; it determines whether hold timing can be developed in the simulator at all.
4. **Does swipe-left survive?** It is unbound by the system, so it should reach the app raw — confirm, since the left half of the screen is now Left and a horizontal drag there must not be swallowed as a system gesture.
5. **Does consuming `onBack` actually prevent the app exiting?**

Start from the SDK's own `samples/Input` app, which already prints press/release state live.

The output is a verified event-flow table the adapter is written against, plus the timeout value from question 1.
