# iOS Widgets and Live Activity Handoff

**As of:** 2026-10-15

Part of the coaching platform program:
[`docs/plans/coaching-platform-2026-10/README.md`](../plans/coaching-platform-2026-10/README.md).
Read it first; it holds the contracts, file owners and migration codes.

## Goal

A WidgetKit extension: a rest-timer Live Activity on the Lock Screen and Dynamic Island, then Done / Skip / +30s, then Today and Lock Screen widgets.

## Chunks

D0 (Phase 1); D1 (Phase 2); D2 (Phase 3)

## State

**D0 live** (PR #112; build 395 on the owner's iPhone 18). The owner's Lock Screen and Dynamic
Island check passed on 2026-10-15. What exists:

- **Extension target** `TracendWidgets` (WidgetKit, `com.tracend.app.TracendWidgets`, team
  `CGLRSQ8G95`, iOS 17.0, Swift 5), embedded in Runner by an "Embed Foundation Extensions" phase
  placed before "Thin Binary". Its version comes from `ios/TracendWidgets/TracendWidgets.xcconfig`,
  which includes Flutter's `Generated.xcconfig` only (the Runner xcconfigs would link the app's
  pods). The Podfile is unchanged: the extension uses no pods. Runner's `Info.plist` has
  `NSSupportsLiveActivities = YES`. No entitlements, App Group or push.
- **`ios/Shared/RestActivityAttributes.swift`** (both targets): no static fields; content state
  `endsAt`, `nextLabel`, `exerciseName`. The stale date is `endsAt`. What it may show is the
  owner's 2026-10-15 exception in `SECURITY_PRIVACY.md` §10: the exercise name and the next-set
  label only.
- **Presentations** (`ios/TracendWidgets/RestLiveActivity.swift`, colors and number face in
  `TracendStyle.swift`): always on graphite (`#18191B`) with off-white text and lime
  (`#C8F05A`), so it reads the same in light and dark mode. Lock Screen and banner: "Rest" with a
  lime timer glyph, the exercise in Archivo SemiCondensed ExtraBold, "Next: …", and a 44 pt lime
  countdown on the right. Dynamic Island compact: lime timer glyph | lime countdown; minimal: the
  countdown (max 36 pt wide); expanded: "Rest" (leading), 34 pt countdown (trailing), exercise
  and "Next: …" (bottom). Once stale every presentation reads "Rest done" with a lime check.
  Empty labels fall back to "Between sets" and no "Next" line. The font file
  (`assets/fonts/ArchivoSemiCondensed-ExtraBold.ttf`) is an extension resource listed in its
  `UIAppFonts`; its name is read from the file at runtime because the file's internal name
  ("Archivo-SemiBold") is shared by every Archivo cut. The condensed system face is the fallback.
- **Bridge** `ios/Runner/Native/WorkoutActivityBridge.swift`, registered in `SceneDelegate` on
  `tracend/live_activity`. Calls run one after another in arrival order.
  - On registration (each launch) it ends the running rest activities whose end has passed:
    `.after(endsAt + 2 min)`, or `.immediate` once that has passed. A still-running one is left
    for the app's restore.
  - `startRest` (`ends_at_millis`, `next_label`, `exercise_name`) ends every earlier rest
    activity that is not dismissed, ended ones lingering as "Rest done" included, with
    `.immediate`, then requests the new one. A refused request answers `FlutterError` code
    `request_failed` (no values).
  - `updateRest` (`ends_at_millis`, optional `next_label`) moves the running one.
  - `end` ends the running ones: `.immediate` when cut short, `.after(endsAt + 2 min)` when the
    rest ran out.
  - With Live Activities off every call shows nothing and answers false.
- **Dart** `lib/shared/live_activity/workout_activity_bridge.dart`: `WorkoutActivityBridge`
  (`startRest`, `updateRest`, `end`) and `MethodChannelWorkoutActivityBridge`, which swallows
  `PlatformException` (logging only its code) and `MissingPluginException`, and leaves a
  `workout` breadcrumb with the method and `showing` only.
- **Who drives it.** `RestTimerController` (`activity:`, default the channel bridge) is the only
  driver during a workout: `start` (with `nextLabel`, `exerciseName`) starts it, `adjust` updates
  it, `stop`/`skip` end it, `restore` moves it to the stored end or ends an expired one, and
  `detach` (called from `ActiveWorkoutScreen.dispose`) ends a running rest's activity when the
  screen goes without Leave/Finish/Discard (those already stop the rest); the stored rest and its
  alert stay. Each activity call is sent before the rest alert is scheduled or cancelled and is
  never awaited, so a stop right after a start cannot overtake it. `ActiveWorkoutScreen` passes
  `nextLabel` (the existing "Set 2 of Bench press" label) and `exerciseName` (the exercise of the
  set just done) and takes the bridge as `activity:`. `Phase2Gate` calls `end` on sign-out (which
  account deletion also goes through, from Account) and when Auth refuses the session.
- **Tests:** `test/live_activity/rest_timer_live_activity_test.dart` (controller ↔ fake bridge,
  including the stop-during-pending-alert race and `detach`),
  `test/contract/live_activity_channel_contract_test.dart` (mock channel),
  `test/phase_3_workout_flow_test.dart` (the screen sends the labels; tear-down ends only the
  activity), `test/account_session_test.dart` (a refused session ends it). The fake is
  `test/live_activity/fake_workout_activity_bridge.dart`.

**D1 in review** (branch `claude/d1-live-activity-buttons`): Done, Skip and +30s.

- **Intents** `ios/Shared/RestActivityIntents.swift` (both targets): `CompleteSetIntent`,
  `SkipRestIntent`, `AddRestIntent`, all `LiveActivityIntent` and hidden from Shortcuts
  (`isDiscoverable = false`). iOS runs them in the app's process; `AppDelegate` points
  `RestActivityButtons.handler` at `WorkoutActivityBridge.press` before any scene connects, because
  a background launch for a press may have no scene and no Flutter engine.
- **Bridge.** `press` sends `press` (`{"button": "done" | "skip" | "add_rest", "seconds": 30}`) to
  Dart only while a workout screen has called `attachButtons`; it waits up to 8 s for the answer,
  then for every queued activity call, so iOS does not suspend the app halfway. A press that no
  workout took sets the content's `needsApp` ("Open Tracend to continue"); `updateRest` and a new
  rest clear it. `startRest` now moves a running activity (counting down or "Rest done") in place
  instead of ending it and requesting a new one, so a Done from the Lock Screen never needs a
  request from the background (Apple forum reports say background requests can fail with
  "Target is not foreground" while another activity exists). `end` is always `.immediate`; the
  two-minute linger now lives in Dart, and the launch sweep keeps it.
- **No App Group.** The intent runs in the app's own process, where the Flutter engine and the
  channel already are, so nothing is shared between processes.
- **Dart.** `WorkoutActivityBridge.attachButtons/detachButtons` and `LiveActivityButton`
  (`lib/shared/live_activity/`); `workoutCommandFor` maps a button to its Contract 3 command;
  `WorkoutEventHub.send` answers once `ActiveWorkoutScreen` has acted (`handleCommands` replaced
  `incomingCommands`; `commands.add` still works). The screen attaches once ready, detaches on
  dispose, and saves the local draft before it answers. A press after the rest ran out unnoticed
  counts that rest as ended at its stored end. Done ticks the set the "Next" line names (the page's
  exercise, else the next open one after it).
- **Lifecycle change** (`RestTimerController`): Skip and −15 past the end send `updateRest(now)`
  ("Rest done") instead of `end`; a rest that ran out sends nothing (`ranOut`); `tick` ends "Rest
  done" two minutes after the rest's end and the screen calls it only while the app is resumed; a
  set with no rest after it ends the activity; `detach` also ends "Rest done". SECURITY_PRIVACY §10
  is updated to match (owner to confirm).
- **Tests:** contract test (press, attach/detach, refused arguments, the answer waiting),
  `test/live_activity/live_activity_commands_test.dart`, the controller tests, and a whole workout
  from the buttons in `test/phase_3_workout_flow_test.dart`.

**Test D1 on the device** (signed build from the branch):

1. Start a workout, tick set 1 in the app, lock the phone. The card shows +30s and Skip.
2. Tap +30s: the countdown jumps 30 s. Tap Skip: "Rest done", a lime Done set button.
3. Tap Done set: a new rest starts in the same card with the next set. Let that one run out on the
   Lock Screen, then tap Done set.
4. Go home and long-press the Dynamic Island: the same buttons work there.
5. Finish the workout from the Lock Screen to the last set: the card goes. Open the app: every set
   is ticked with the suggested kg and reps, rests match what you did.
6. Mid-rest, swipe the app away, then tap Skip: "Open Tracend to continue". Tap the card: the app
   opens, reopen the workout, the countdown is back and the buttons return.
7. Skip in the app and stay on screen: "Rest done" goes after two minutes.

**S3 choice.** A new rest ends every earlier rest activity with `.immediate`, including an ended
one still showing "Rest done"; the two-minute linger stays. If the device check shows "Rest done"
staying next to a new countdown (ActivityKit ignoring `end` on an ended activity), the fallback is
to shorten `doneLinger` to 30 s.

**For D1.** C1's Contract 3 events (`RestStarted`, `RestAdjusted`) are emitted next to the
controller calls, but the activity is driven only by `RestTimerController`. D1 must keep it that
way: feed the Live Activity's buttons into C1's command sink (`SkipRest`, `AddRest`,
`CompleteCurrentSet`), whose handlers already go through the controller, and never start or
update the activity from the event stream as well.

**Test on the device** (signed build from the branch, `./scripts/install-device.sh`; the free team
registers the new App ID on first signing):

1. Start a workout and tick a set with rest. Lock the phone: the card shows the exercise, "Next:
   Set 2 of …" and the countdown, in light and dark mode, with the Archivo number face.
2. Go home: the Dynamic Island shows the lime glyph and the countdown; a long press expands it.
3. ±15 moves it; Skip removes it at once.
4. Let a rest run out with the app open: "Rest done". Tick the next set within two minutes:
   "Rest done" goes and only the new countdown shows (S3).
5. Let a rest run out with the app closed (swipe it away): "Rest done". Relaunch: it goes within
   two minutes of the end (launch sweep).
6. Kill the app mid-rest and reopen the workout: the countdown is still right.
7. Finish, Discard, and Save and leave each remove it at once. Sign out mid-rest: it goes.
8. Settings › Tracend › Live Activities off: the in-app timer and the rest alert work; nothing
   shows.

**Known limits:** a press with the app closed cannot reach a workout (the card asks to open the
app); "Rest done" stays past two minutes while the app is away; Done logs the suggested kg and
reps; no push, so nothing changes it
from the server; iOS ends any activity after 8 hours; the free team's profiles expire after 7
days like the app's.

## Next agent starts here

After the owner's D1 device check: D2 (Today and Lock Screen widgets), Phase 3. C2 stacks on the
D1 branch; its listener uses `WorkoutEventHub.events` only (the command sink is D1's).
