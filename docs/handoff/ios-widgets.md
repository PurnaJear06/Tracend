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

**Known limits:** no buttons until D1 (tapping opens the app); no push, so nothing changes it
from the server; iOS ends any activity after 8 hours; the free team's profiles expire after 7
days like the app's.

## Next agent starts here

Take D1 (Done / Skip / +30s), Phase 2; the brief is in the program doc.
