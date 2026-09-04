# Coroutine conversion strategy

Type: grilling
Status: open
Blocked by: 07

## Question

How do all 60 coroutines in `Animations.cs` get converted into VM step lists, and how is the result verified as visually identical?

Decide:

- **Conversion method** — by hand, by a script that parses the C# and emits step lists, or a hybrid (script does the mechanical bulk, a human resolves what it cannot).
- **Non-mechanical constructs** — inventory the coroutines that do something the VM's vocabulary cannot express directly (conditional branching mid-animation, waiting on input, nested coroutine calls, `yield return` on another coroutine). Each needs a named treatment.
- **Verification** — the fidelity contract says visuals are exact. How is that checked? Frame-by-frame capture from the Unity original against the simulator? Eyeballing? A golden-frame test set? Decide the standard and what "identical enough" means, because a per-frame pixel diff across 60 animations is a project in itself.
- **Ordering** — which animations must be converted for the first vertical slice (Status + Database), and which can wait.

This is the largest single chunk of the port. Getting the method wrong costs weeks.
