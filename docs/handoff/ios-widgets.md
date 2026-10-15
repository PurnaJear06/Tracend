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

**D0 in review** (branch `claude/d0-rest-live-activity`, not merged). What exists:

- **Extension target** `TracendWidgets` (WidgetKit, `com.tracend.app.TracendWidgets`, team
  `CGLRSQ8G95`, iOS 17.0, Swift 5), embedded in Runner by an "Embed Foundation Extensions" phase
  placed before "Thin Binary". Its version comes from `ios/TracendWidgets/TracendWidgets.xcconfig`,
  which includes Flutter's `Generated.xcconfig` only (the Runner xcconfigs would link the app's
  pods). The Podfile is unchanged: the extension uses no pods. Runner's `Info.plist` has
  `NSSupportsLiveActivities = YES`. No entitlements, App Group or push.
- **`ios/Shared/RestActivityAttributes.swift`** (both targets): attributes `workoutTitle`;
  content state `endsAt`, `nextLabel`, `exerciseName`. The stale date is `endsAt`.
- **Presentations** (`ios/TracendWidgets/RestLiveActivity.swift`, colors and number face in
  `TracendStyle.swift`): always on graphite (`#18191B`) with off-white text and lime
  (`#C8F05A`), so it reads the same in light and dark mode. Lock Screen and banner: "Rest" with a
  lime timer glyph (and "· workout" when sent), the exercise in Archivo SemiCondensed ExtraBold,
  "Next: …", and a 44 pt lime countdown on the right. Dynamic Island compact: lime timer glyph |
  lime countdown; minimal: the countdown; expanded: "Rest" (leading), 34 pt countdown (trailing),
  exercise and "Next: …" (bottom). Once stale every presentation reads "Rest done" with a lime
  check. Empty labels fall back to "Between sets" and no "Next" line. The font file
  (`assets/fonts/ArchivoSemiCondensed-ExtraBold.ttf`) is a resource of the extension, registered
  by URL because its internal name ("Archivo-SemiBold") is shared by every Archivo cut; the
  condensed system face is the fallback.
- **Bridge** `ios/Runner/Native/WorkoutActivityBridge.swift`, registered in `SceneDelegate` on
  `tracend/live_activity`: `startRest` (`ends_at_millis`, `next_label`, `exercise_name`, optional
  `workout_title`) ends any earlier rest activity and requests a new one; `updateRest`
  (`ends_at_millis`, optional `next_label`) moves the running one; `end` ends all of them:
  `.immediate` when the rest was cut short, `.after(endsAt + 2 min)` when it ran out. Calls run
  one after another in arrival order. Every call answers whether a rest activity shows; with Live
  Activities off it shows nothing and returns false.
- **Dart** `lib/shared/live_activity/workout_activity_bridge.dart`: `WorkoutActivityBridge`
  (`startRest`, `updateRest`, `end`) and `MethodChannelWorkoutActivityBridge`, which swallows
  `PlatformException`/`MissingPluginException` and leaves a `workout` breadcrumb with the method
  and `showing` only. `RestTimerController` takes it as `activity:` (default the channel one):
  `start` starts it (optional `nextLabel`, `exerciseName`, `workoutTitle`), `adjust` updates it,
  `stop`/`skip` end it, `restore` updates it to the stored end or ends an expired one. The calls
  are not awaited, so the timer never waits on iOS. The rest alert is unchanged.
- **Tests:** `test/live_activity/rest_timer_live_activity_test.dart` (controller ↔ fake bridge),
  `test/contract/live_activity_channel_contract_test.dart` (mock channel); the fake is
  `test/live_activity/fake_workout_activity_bridge.dart`.

**Call site for C1.** `ActiveWorkoutScreen` still calls `_rest.start(seconds)` without labels, so
the activity shows "Between sets" until C1 passes them, for example
`_rest.start(seconds, nextLabel: next.full, exerciseName: draft.exercise.name, workoutTitle:
widget.workout.name)`.

**Open owner decision.** `SECURITY_PRIVACY.md` §10 says lock-screen content never names
workouts; this Live Activity shows the exercise and next set on the Lock Screen (never a load,
reps, effort or health value). The program plan and the D0 brief ask for it, but the rule is the
owner's: either record an exception for the Live Activity in `SECURITY_PRIVACY.md` or send empty
labels.

**Test on the device** (signed build from the branch, `./scripts/install-device.sh`; the free team
registers the new App ID on first signing): start a workout, tick a set with rest, lock the phone:
the card counts down; swipe home: the Dynamic Island shows the glyph and countdown, a long press
expands it. Let a rest run out with the app closed: it reads "Rest done". Reopen: it goes two
minutes after the end. ±15 moves it; Skip, Finish, Discard and Save and leave remove it at once.
Settings › Tracend › Live Activities off: the app's rest timer works and nothing shows.

**Known limits:** no buttons until D1 (tapping opens the app); no push, so a rest changed on
another device is not reflected; iOS ends any activity after 8 hours; the free team's profiles
expire after 7 days like the app's.

## Next agent starts here

D0 is in review. Once it merges and the signed install passes, take D1 (Done / Skip / +30s) when C1
has merged.
