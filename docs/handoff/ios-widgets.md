# iOS Widgets and Live Activity Handoff

**As of:** 2026-10-18

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
  set just done) and takes the bridge as `activity:`. `Phase2Gate` calls `end` from its auth listener on
  every signed-out transition (sign-out, account deletion, a refused session).
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
- **Bridge.** `press` sends `press` (`{"button": "done" | "skip" | "add_rest", "seconds": 30,
  "exercise_order", "set_number", "pressed_at_millis"}`) to Dart only while a workout screen has
  called `attachButtons`; it waits up to 8 s from the press for the answer, then for every queued
  activity call, so iOS does not suspend the app halfway. A press that no workout handled (answer
  false, timeout, or no workout) sets the content's `needsApp` ("Open Tracend to continue");
  `updateRest` and a new rest clear it. `startRest` moves a running activity (counting down or
  "Rest done") in place instead of ending it and requesting a new one, so a Done from the Lock
  Screen never needs a request from the background (Apple forum reports say background requests
  can fail with "Target is not foreground" while another activity exists). `end` is always
  `.immediate`; the two-minute linger lives in Dart, and the launch sweep keeps it.
- **No App Group.** The intent runs in the app's own process, where the Flutter engine and the
  channel already are, so nothing is shared between processes.
- **Dart.** `WorkoutActivityBridge.attachButtons/detachButtons` and `LiveActivityButton`
  (`lib/shared/live_activity/`); `workoutCommandFor` maps a button to its Contract 3 command;
  `WorkoutEventHub.send` answers (true/false) once `ActiveWorkoutScreen` has handled it
  (`handleCommands` replaced `incomingCommands`; `commands.add` still works). The hub runs commands
  one at a time, so each sees the state the last left. The screen attaches once ready and detaches
  on dispose.
- **Review fixes (PR #121).**
  - *Set identity (Contract 3 change).* `CompleteCurrentSet` now carries `exerciseOrder` and
    `setNumber` (1-based), both required. The set comes from the rest's "Next" label: `startRest`
    sends `next_exercise_order` and `next_set_number` (optional, additive), the activity keeps them
    in its content state (`nextExerciseOrder`, `nextSetNumber`), and the Done button builds
    `CompleteSetIntent(exerciseOrder:setNumber:)` with them. The plan README's Contract 3 block
    still shows the old empty class; update it when D1 merges. Without a set in the state the card
    shows "Open Tracend to continue" instead of Done. Dart refuses a `press` for Done without both
    numbers (`invalid_arguments`, so the card asks to open the app) and never ticks "whatever is
    current".
  - *Guards.* Dart ticks only if that exercise's current unticked set is that set, and ignores Done
    while a rest runs. An ignored press answers true and changes nothing; a running rest's card is
    redrawn with its true end (`RestTimerController.refresh`), which also clears a stuck
    "Open Tracend to continue". It answers false when the workout is closed, finishing or viewing a
    completed one, or the set cannot be ticked (no suggested reps).
  - *Late press.* Swift stamps `pressed_at_millis` when the intent runs. Dart drops a press older
    than 8 s (`LiveActivityButton.pressTimeout`, equal to Swift's `pressTimeout`) twice: on arrival
    and again when the hub's turn comes (a press queued behind a slow save). A dropped press
    answers false and changes nothing.
  - *Server sync.* After a Done tick the press awaits `_save()` (local draft plus
    `sync_workout_draft`, the same call the 250 ms timer makes after an in-app tick), at most 5 s
    so the answer stays inside iOS's 8 s. A failed send is handled inside `_save` exactly as for
    an in-app tick: the set stays logged and the sync state shows Offline. Skip and +30s save the
    local draft only, as in the app.
  - *"Rest done" bound.* ActivityKit cannot dismiss an activity by itself: `staleDate` only marks
    it stale (the card already uses that to flip to "Rest done" at the rest's end), and
    `dismissalPolicy: .after(date)` applies only to `end()`, which needs app code (or a push, which
    D1 does not use). Closest bounds: the screen's `tick` (every second on screen), the launch
    sweep, and now a button press: `WorkoutActivityBridge.press` first ends, at once, any rest
    activity whose end passed more than two minutes ago and does not forward the press. Otherwise
    iOS removes it at its own limit (8 hours after the start). SECURITY_PRIVACY §10 and UX_FLOWS
    say this. A `BGAppRefreshTask` could add a best-effort wake, but iOS decides when; not built.
  - *Card current before the answer.* `RestTimerController` remembers each activity call it sends
    (still not awaited in the app, so the timer never stalls on iOS); a press (`_onCommand`) awaits
    `activityUpdated()` after it acts, at most 1.5 s (so 5 s save + 1.5 s stays inside Swift's 8 s).
    A failed or slow update is logged and the press still answers; it never undoes the change.
  - *`tick` only when resumed.* A button press wakes the app in the background, so it does not run
    `tick`; the docs no longer say a press counts as the app running.
- **Lifecycle change** (`RestTimerController`): Skip and −15 past the end send `updateRest(now)`
  ("Rest done") instead of `end`; a rest that ran out sends nothing (`ranOut`); `tick` ends "Rest
  done" two minutes after the rest's end and the screen calls it only while the app is resumed; a
  set with no rest after it ends the activity; `detach` also ends "Rest done". SECURITY_PRIVACY §10
  is updated to match (owner to confirm).
- **Facts for the other authority docs** (kept out of this PR; fold in when D1 merges):
  ARCHITECTURE §3.1 should say the buttons are iOS 17 `LiveActivityIntent`s in
  `ios/Shared/RestActivityIntents.swift` (both targets), run in the app's process, that the bridge
  forwards `press` to the attached workout screen as a Contract 3 command and waits for its answer
  (8 s at most) and for its queued activity calls, with no App Group. PRD §4 should replace
  "Planned (Phase 2, D1)" with: Done, Skip and +30s on the Live Activity; Done logs the suggested
  kg and reps. TESTING_STRATEGY should list the D1 tests below.
- **Tests:** contract test (press with set identity and press time, attach/detach, refused
  arguments including an old Done without a set, the answer waiting, a late press dropped),
  `test/live_activity/live_activity_commands_test.dart` (button mapping, the command sink's answers,
  one-at-a-time order, expiry), the controller tests, and in `test/phase_3_workout_flow_test.dart` a
  whole workout from the buttons plus a double press, a stale Done after an in-app tick, Done during
  a rest, a late press, the server copy before the answer, and a failed send. The intents run only
  on the owner's iPhone.

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
8. Double-tap Done set on the Lock Screen: one set is ticked, the card shows the next rest.
9. Tick the set in the app while the card shows Done for it, then tap the card's Done: nothing is
   ticked. Tap Done while a rest runs (a stale card): nothing is ticked.
10. Tap Done set on the Lock Screen, then open the app straight away: the set is on the server
    (the sync state reads Saved, not Offline).
11. Let a rest end, leave the phone for five minutes with the app in the background: "Rest done"
    may still show (nothing can dismiss it); tap Done set: the card goes and no set is ticked.

**D2 in review** (branch `claude/d2-widgets`): Today and Lock Screen widgets.

- **New: the App Group `group.com.tracend.app`**, in `Runner.entitlements` and the new
  `TracendWidgets/TracendWidgets.entitlements`. It exists only so the widget process can read the
  snapshot; the Live Activity still uses none. App Groups are supported for this team: on
  2026-10-18 team `CGLRSQ8G95` signed both Runner and TracendWidgets with `group.com.tracend.app`
  (verified with `codesign`). If a build is ever signed without the group, nothing else in the app
  changes: the bridge answers `no_app_group`, the widgets read "Open Tracend to refresh", and Dart
  logs the error code only.
- **Snapshot (Dart)** `lib/shared/home_widgets/today_widget_snapshot.dart`: `TodayWidgetSnapshot.build`
  turns the loaded `DailyBrief`, the plan's `NutritionTargets`, the check-in state and the Lock Screen
  choice into the v1 JSON (`schema_version`, `stale_after_seconds` = 43200, `local_date`, `session`
  with up to three exercise targets, `recovery`, `nutrition`, `check_in_done`, `lock`,
  `generated_at_millis`). Every value is one Today already shows; no free text. `lock` is null while
  Lock Screen numbers are off.
- **Publisher** `today_widget_publisher.dart`: `TodayWidgetPublisher` writes on each brief load
  (`TodayScreen._loadBrief` hands the brief over; the newest publish wins, and a brief load that
  finishes after a newer one started is ignored), skips an unchanged
  snapshot for five minutes, owns the Lock Screen choice (`home_widgets_lock_screen_numbers.<user id>`
  in `SharedPreferencesAsync`, default off; `Phase2Gate` hands `AppShell` the user id, and the
  shell is keyed by it) and clears the snapshot on `dispose` (AppShell going away).
  `Phase2Gate`'s auth listener clears it, and ends the rest activity, on every signed-out
  transition: sign-out, a refused session, and a deletion that settles after its sheet was closed
  (Account then never calls the gate's sign-out). The same listener swaps the gate to sign-in
  (`_showSignedOut`, idempotent) and drops any refresh still running (a refresh commits only if no
  session ended since it began); `_signOut` and `_endRejectedSession` no longer swap screens. `write`
  and `clear` answer a bool through Dart: a failed rewrite on opt-out removes the snapshot, a
  failed clear is tried twice; a clear that fails twice sets a phone-wide flag
  (`HomeWidgetEraser`, preference `home_widgets_clear_pending`) that is retried on every launch and
  resume, blocks any new publish while set, and makes an opt-out that cannot remove the numbers
  report failure: the switch stays On with a toast. The widget extension reads an empty or
  unreadable file as no data (`TodayWidgetStore.read`; `testAnEmptyFileIsNoData`).
  `RunnerTests` loads the snapshot fixture as a bundle resource.
  Nothing else clears it. Sign-out
  (`signOutAthlete`) and a refused session (`LocalAccountData.forgetSession`) forget the athlete's
  Lock Screen choice and the phone-wide key an earlier D2 build used; deleting the account removes
  both with the rest (`LocalAccountData.clear`). A saved check-in republishes the last brief at
  once (`TodayScreen._openCheckIn`), so an offline check-in shows "Checked in" even when the
  reload fails. `TodayScreen` reloads its
  brief, targets and meals when the app resumes (or a widget tap brings it forward) if the last load
  is over 30 minutes old or from another local day, and that load is what gets published.
  `TodaySessionProgress` (`lib/features/today/`) is the one reading of the session's state and sets,
  shared by the session card and the snapshot.
- **Bridge** `home_widget_bridge.dart` + `ios/Runner/Native/HomeWidgetBridge.swift`, channel
  `tracend/home_widgets`: `write` (answers `no_app_group` when the group's container does not exist, refuses anything but v1
  with `invalid_snapshot`, stores it as the file `today_widget_snapshot.json` in the container, excluded
  from backups and protected until first unlock (written to a temporary file in the container,
  excluded there, then `rename`d into place and checked; a snapshot that is not excluded is
  removed), answers `write_failed` if that fails, then
  `WidgetCenter.reloadAllTimelines()`),
  `clear` (removes the file, or empties it when removal fails; answers `clear_failed` only if the
  old data may remain), `takePendingTab`; iOS calls `tabRequested` when a widget is tapped.
- **Deep links.** None existed. `Info.plist` now registers the `tracend` URL scheme and sets
  `FlutterDeepLinkingEnabled` = NO (Flutter would otherwise try to route the URL as a Navigator route).
  `SceneDelegate` passes `connectionOptions.urlContexts` and `scene(_:openURLContexts:)` to
  `HomeWidgetBridge.open`, which accepts `tracend://today` and `tracend://train` only, keeps the tab
  for a minute and nudges Dart; `AppShell` calls `takePendingTab` on start and on each nudge.
- **Swift shared files** (both targets): `ios/Shared/TodayWidgetSnapshot.swift` (Codable model,
  `decode`, `isStale`, `staleDate`; stale from `staleDate` on, that moment included, because the
  timeline's last entry is drawn at exactly it) and `ios/Shared/TodayWidgetStore.swift` (group storage and
  `TracendLink`). **Extension:** `TodayTimeline.swift` (provider, entry; timeline = now plus the
  stale moment, policy `.never`: the app asks for reloads), `TodayWidgets.swift` (small and
  medium), `LockScreenWidgets.swift` (circular, rectangular, inline; only the rectangular one opens
  Train). Visuals: DESIGN_SYSTEM §3.7.
- **Account.** `lib/features/account/widgets/widget_settings.dart`: **Widgets › Health numbers on the
  Lock Screen**, off by default. SECURITY_PRIVACY §10 documents it as a second lock-screen
  exception, approved by the owner on 2026-10-18.
- **Tests:** `test/home_widgets/` (snapshot, publisher, flow, offline check-in), the sign-out and
  per-athlete choice cases in `test/account_session_test.dart`, `test/contract/today_widget_snapshot_contract_test.dart`
  with `fixtures/today_widget_snapshot_v1.json`, and `TodayWidgetSnapshotTests` in `RunnerTests.swift`
  reading the same fixture (not run in CI). The extension, the bridge and the XCTest logic were
  type-checked with `swiftc -typecheck` and the staleness logic exercised in a host script; the
  widgets' look and the App Group are only proven on the iPhone.
- **Known limits.** The exercise lines are the plan's targets from the daily brief (sets, rep range,
  load), not the training hub's progression `next_targets` (that needs the hub, a second read Today
  does not make). The widgets show the last time Today loaded: a meal logged in Nutrition or a set
  logged in Train shows after the next Today load. A medium widget with long exercise names truncates
  the name, not the target.

**Test D2 on the device** (signed build from the branch, `./scripts/install-device.sh`; the team
already signs both targets with the App Group):

1. Install.
2. Open Tracend and let Today load. Add the **Today** widget, small and medium, to the Home Screen
   (long-press, +). Small: session name, status, recovery score. Medium: the first three exercises
   with targets, calories and protein bars, "Checked in" or "Check-in due".
3. Compare every number with Today. Pull to refresh in Today after logging a meal: the widget
   follows within a few seconds.
4. Add the three **Today on the Lock Screen** widgets (Lock Screen › Customize). With Account ›
   Widgets off (the default) they read "Tracend", "Lock Screen numbers are off" and a lock glyph.
   Turn **Health numbers on the Lock Screen** on in Account: circular shows the recovery ring,
   rectangular the session, recovery and protein, inline the session and recovery. Turn it off:
   the numbers go from the Lock Screen at once.
5. Tap each widget: small and medium open Today; the medium exercise list and the rectangular
   Lock Screen widget open Train when a session is planned or started (Today on a rest day or a
   finished session); the circular and inline Lock Screen widgets always open Today. Test with the
   app in the background and with it force-quit.
6. Staleness: turn on Airplane mode, leave the phone 12+ hours (or change the date forward a day):
   every widget reads "Open Tracend to refresh" and shows no number. Open the app: they return.
7. Sign out: all widgets read "Open Tracend to refresh" within a moment. Sign back in and open Today:
   Account › Widgets › Health numbers on the Lock Screen is off again, and the Lock Screen widgets
   read "Lock Screen numbers are off".
8. Offline check-in: with Airplane mode on and the check-in not done, save the check-in. The medium
   widget reads "Checked in" without Today reloading.
9. Rest-timer Live Activity still works (start a workout, tick a set): the App Group changed
   Runner's entitlements.
10. Dark and light mode, and a large Dynamic Type size: the Home Screen widgets stay graphite with
    lime, and no text overlaps.
11. StandBy (iPhone on its side, charging): the Home Screen widget numbers hide or show as iOS
    decides for sensitive content.

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
   the card moves in place to the new countdown (D1 updates the one activity, no second card).
5. Let a rest run out with the app closed (swipe it away): "Rest done". Relaunch: it goes within
   two minutes of the end (launch sweep), or at once if two minutes have passed.
6. Kill the app mid-rest and reopen the workout: the countdown is still right.
7. Finish, Discard, and Save and leave each remove it at once. Sign out mid-rest: it goes.
8. Settings › Tracend › Live Activities off: the in-app timer and the rest alert work; nothing
   shows.

**Known limits:** a press with the app closed cannot reach a workout (the card asks to open the
app); "Rest done" stays past two minutes while the app is away, until the app runs or a button
is pressed (ActivityKit cannot dismiss it without app code or a push); Done logs the suggested kg
and reps; no push, so nothing changes it from the server; iOS ends any activity after 8 hours; the free team's profiles expire after 7
days like the app's.

## Next agent starts here

D2 (Today and Lock Screen widgets) is in review; the owner's device check is the list above. After
it passes, the widgets chunk is done. Follow-ups worth a chunk if the owner wants them: use the
training hub's progression `next_targets` for the medium widget's exercise lines, and a small
interactive widget (iOS 17 buttons) for the check-in.
