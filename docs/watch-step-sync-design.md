# Watch steps and story progress

Status: implemented for the Venu 4 target; debug and release builds pass.
The new shake and foreground/background sync tests have not run because
the local simulator is unavailable. Sensor feel, background scheduling,
notification UX, storage handoff, and time-zone behavior still need validation
on a physical Venu 4 before release.

## Player behavior

- While the app is visible, deliberate wrist shakes and Garmin steps both add
  game steps. The accelerometer listener runs only while the view is shown.
  If it cannot start, visible play still receives Garmin steps.
- While the app is closed, device-recorded steps sync through the background
  service and are credited on the next opening. Shakes are not monitored while
  the app is closed. New, reset, and migrated version 2 games take their
  baseline from the first valid live watch reading. They do not import earlier
  steps.
- Config → BG STEP defaults to ON. OFF removes the temporal and steps wake
  registrations, stops background ledger updates and notifications, and
  checkpoints the watch counter on the next opening without travel credit.
  A queued wake also checks the setting before touching the save. Turning the
  option back ON resumes credit from the latest foreground checkpoint. The
  setting survives a game reset; an alert already posted to the watch may
  remain visible until the watch dismisses it.
- On the next opening, the game credits recorded steps once and shows the
  first reached story event. All credited watch steps increase the lifetime
  game statistic. Only steps through the first event or boss stop move the
  character; excess steps are discarded for travel rather than carried into
  the next gate.
- A background crossing of a gate posts a Garmin app notification saying
  **Detected** with an **Open game** action. Dismissing it leaves the event for
  the next opening.
  Notification timing is best effort.
- An open event prompt repeats its four-beat vibration every 1.6 seconds until the
  player presses an action. The Data Storm cut scene adds spaced double beats.

## Data flow

`GarminStepReader` reads `ActivityMonitor.getInfo().steps` between two
`Time.today()` calls, discarding a sample that straddles midnight. On app
opening, return, day rollover, and hourly while visible it also reads the
available `getHistory()` rows. Background reads both on every wake. Garmin
provides at most seven history objects and nullable fields, so absent data
cannot be inferred as zero or reconstructed after a sufficiently long outage.
If history retrieval fails, the wake still uses the current step reading to
check whether the next event has been reached.

`StepLedger.observe(state, reading)` merges per-day maxima. It stores up to ten
recent days, an archived total and day watermark, and a monotonic source
total. An old or downward-corrected reading cannot lower that total. A missing
day sets `historyGap`; no steps are fabricated for it. If the current day ID
changes by an interval other than 24 hours, the new day is quarantined rather
than counted as a second copy of one counter period. Device behavior during
time-zone travel remains a release validation item.

`JourneyStepSync.reconcile(game, reading, fromResume)` compares the source
total with the saved 64-bit credit cursor. Visible watch steps and shakes are
additive. On resume, watch steps accumulated while the app was closed apply model steps only until
the first pending event or boss stop, then add the rest only to the game-step
and physical watch-step statistics. Walking disabled by defeat or a pending
event also credits statistics without travel. A warm return may travel through
a loaded menu and closes that menu if an event is reached.
The model, source ledger, and credit cursor are committed together before a
new event is presented. Failed writes retain the dirty model and suspend
further reconciliation until retry succeeds.

An opened event retains a durable active marker until its battle ends or the
Data Storm cut scene finishes. Relaunching during the event offers the same
kind of event from its start; a random battle may draw a different opponent.
An interrupted event battle does not apply the quit penalty on relaunch. The
storm marker also records whether its world move already happened, so replay
does not move twice. Winning, losing, or escaping consumes a battle event.
A defeated character can recover at Camp without the lost battle prompting
again. The watch counter is sampled before a battle action can end an event,
so steps taken during that event cannot open the next one.

## Save and writer handoff

Save version 3 puts a 163-byte fixed journey header before the positional game
payload. The header includes the game generation, gate epoch, notified gate,
source ledger, credit cursor, watch-step statistic, and a projection of the
next gate. The background process reads and patches only this header; it never
loads `GameData` or mutates gameplay. Version 2 payloads are decoded and
migrated without resetting the game. The existing signed 32-bit game-step
statistic saturates at 2,147,483,647; source and watch counters are 64-bit.

There is one durable ledger, inside `slot0`. Foreground writes a `stepFgLease`
intent before checking `stepBgBusy`, renews it within 30 seconds, and holds it
while visible. Background writes `stepBgBusy` before checking the foreground
lease; it exits if that lease is fresh. Foreground waits for a running service
to finish and may recover an abandoned busy flag after 35 seconds, beyond
Connect IQ's 30-second service limit. If either intent write fails, that
process does not access `slot0`. Foreground flushes before releasing its lease
on hide or stop and rereads the background header on return. This protocol
depends on cross-process Storage write visibility and needs an interleaving
test on the watch; Storage does not document a transaction or compare-and-swap.

## Background wake and notification

The app registers a repeating five-minute temporal event and the Garmin steps
event, which fires at fixed 1,000-device-step multiples. There is no 100-step
background trigger. Each wake merges the source checkpoint, then compares
uncredited steps with the first gate: one step at the boss stop, otherwise
`min(max(1, stepsToNextEvent), currentDistance - 1)`. A saved pending event
also qualifies if it has not already been presented. No notification is sent
for a game without a character, an uninitialized baseline, a defeated player,
or an already notified gate. The notification marker is written after posting;
if that write fails, a later post replaces the previous notification. A gate
epoch advances when an event is resolved, and a new game gets a new generation.

The notification carries generation and gate data. Opening the app always
reconciles current steps and checks the saved gate, so selecting an old
notification cannot resurrect an event. The SDK does not expose a method to
remove a previously posted notification; a later post replaces prior app
notifications. Showing an event prompt in the app does not mark its gate as
notified; closing the app before acting still leaves the background alert
eligible.

## Verification

Monkey C simulator tests cover duplicate and corrected readings, midnight,
ten-day archiving, nullable readings, time-zone quarantine, the version 2
decoder, header round-trip, new-game baseline, statistic saturation, the
360-step/300-step gate, notification eligibility, and the foreground/background
handoff. Debug and release builds must both compile, and simulator background
callbacks must run without an illegal-access error.

Before release, verify on Venu 4 hardware: actual five-minute and steps-event
scheduling, notification display/select/dismiss, background memory, midnight
and time-zone behavior, and foreground/background write interleavings. The
simulator's manual callback trigger does not prove that a registered wake is
scheduled by the watch.

## Garmin references

- [ActivityMonitor](https://developer.garmin.com/connect-iq/api-docs/Toybox/ActivityMonitor.html)
  and [Info](https://developer.garmin.com/connect-iq/api-docs/Toybox/ActivityMonitor/Info.html)
- [Background](https://developer.garmin.com/connect-iq/api-docs/Toybox/Background.html)
  and [AppBase](https://developer.garmin.com/connect-iq/api-docs/Toybox/Application/AppBase.html)
- [Notifications](https://developer.garmin.com/connect-iq/api-docs/Toybox/Notifications.html)
  and [Storage](https://developer.garmin.com/connect-iq/api-docs/Toybox/Application/Storage.html)
