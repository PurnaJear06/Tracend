# Review: Phase 5 v2 Chunk 5 — Motion + A11y + Copy Audit — 2026-08-24

Scope: commit `c90bf9e` vs `53a26ef` on `feature/feature-engine-phase-5-v2`. 20 files,
+462/−121. UI-only: `MicroMotionCountUp` + RecoveryRing wiring, nine staggered Today
entrances, `_DriverBar` semantics, extended contrast asserts, padded chip tap targets,
tab-label scale clamp, `_CardTag` wrap fix, Dynamic Type regression test, docs/handoff
updates. No migrations, no RPC/Edge changes, no contract fixtures in scope.

Verdict: **PASS WITH FINDINGS**

Reviewed fully: every file in the diff was read (diff + full files where context
mattered, including the pinned Flutter 3.41.7 SDK sources for `TweenAnimationBuilder`,
`ImplicitlyAnimatedWidgetState`, and `FutureBuilder`). Nothing in the diff was skipped.

## Findings

1. [MINOR] `lib/features/today/today_screen.dart:132-172` (+ `recovery_ring.dart:56`,
   `micro_motion.dart:95-119`) — **the count-up can never fire in the app flow, and all
   nine entrances re-fire on every brief reload.** Root cause is the pre-existing
   FutureBuilder waiting-swap, which this chunk's motion is built on top of:
   - `_openCheckIn` (today_screen.dart:86-91) and `_reloadBriefAndHealth` (:81-84)
     replace `_brief` with a new future. Verified against the pinned SDK
     (`.tooling/flutter-sdk/.../widgets/async.dart:612-622`): on future change,
     FutureBuilder resets the snapshot to `ConnectionState.waiting` (retaining stale
     data), and the builder (today_screen.dart:135-140) discards retained data for
     `waiting` and returns the loading card. `_BriefContent` — and with it every
     `MicroMotionEntrance` state and the `MicroMotionCountUp` state — is unmounted,
     then re-created when the new brief resolves (one frame later in fixture mode, the
     full RPC round-trip in production).
   - Effect A: after every check-in and every health sync, the whole brief flashes to
     the loading card and the full 0–8 stagger replays. The focus-item hypothesis
     "widget state persists" does not hold — the waiting branch swaps the subtree out.
   - Effect B: `MicroMotionCountUp` renders statically on every mount (verified in SDK
     `tween_animation_builder.dart:185-192`: `initState` only calls `forward()` when
     `begin != end`). Since the score element is always re-created with the new score,
     the count-up never animates in production. It animates only in
     `test/recovery_ring_test.dart:137-151`, where the element is artificially kept
     alive across pumps. Plan anti-failure rule 4 ("wire it or delete it") is nudged:
     the feature is wired but unreachable in the real flow.
   - Suggested fix (report only, not applied): keep showing the previous brief during
     reload (branch on `snapshot.hasData` / hold the last brief in state; show the
     loading card only on first load) so the subtree persists — entrances then fire
     once on mount and the count-up animates genuine score changes. Tab switching is
     not a trigger (IndexedStack keeps Today alive — app_shell.dart:114).

2. [NIT] `docs/DESIGN_SYSTEM.md` §8 ("Contrast is asserted in tests: body text ≥4.5:1
   on surface and canvas … in both themes") vs `test/theme_test.dart:19-29,74-81` —
   light-theme `textSecondary` on canvas is **not** asserted (the canvas secondary-text
   test is dark-only; the new both-themes canvas test covers `textPrimary` only). The
   pairing passes by calculation (≈5.8:1), so this is doc overstatement, not a contrast
   failure. Fix: add the light `textSecondary`/canvas assert, or narrow the sentence.

3. [NIT] `test/dynamic_type_test.dart:18-40` — coverage gap + latent hazard. The
   full-app pump uses `FixtureDailyBriefRepository`
   (`daily_brief_repository.dart:89-102`), which returns no `computed`, so the Today
   tab renders the cold-start variant: RecoveryRing, SleepArchitectureCard, and the
   TrajectoryLens bezier (the data-viz this chunk touches) are never exercised at
   1.3×/2.0×. The other four tabs are covered as claimed. Latent hazard: if the fixture
   ever gains `computed` data, the NOW-dot pulse (infinite repeat) makes
   `pumpAndSettle()` here and in `frontend_smoke_test.dart` hang until timeout — the
   trajectory/today tests correctly use bounded pumps for exactly this reason
   (`trajectory_lens_test.dart:34-35`). Fix: pump a data-rich TodayScreen variant
   directly (as the new stagger test does with `_ComputedBriefRepository`) under the
   scale matrix, or set `disableAnimations` in the full-app pump.

4. [NIT] `lib/features/today/recovery_ring.dart:278` — the semantics label reports the
   raw z-score (`zScore.toStringAsFixed(1)`) while the bar fill clamps to ±2
   (recovery_ring.dart:274). For |z| > 2 VoiceOver announces a value the visual bar
   cannot display. The raw value is real data (not fabricated), so this is a mismatch
   nuance; optionally state the clamp or clamp the spoken value. `excludeSemantics`
   itself hides nothing the user needs (see focus item 5).

## Focus-item verification

1. **`MicroMotionCountUp` correctness — VERIFIED.** Read the pinned SDK
   (`tween_animation_builder.dart:180-214`, `implicit_animations.dart:358-441`):
   - First build: `initState` sets `_currentTween = widget.tween`; `begin == end` so
     `controller.forward()` is not called, and `_constructTweens` finds
     `targetValue == tween.end` → no animation. Static. ✓
   - Value change: `didUpdateWidget` → `_constructTweens` detects
     `targetValue != tween.end`, then rewrites the tween to
     `begin = tween.evaluate(_animation)` (the currently displayed value) →
     `end = targetValue` and runs `controller.forward(from: 0)`. Animates from the old
     value, correct even when interrupted mid-flight. ✓
   - Rebuild with the same value compares `end` by value (not tween identity), so no
     spurious animation. ✓
   - Reparenting/remount: fresh `initState` with begin==end → static; no mount
     animation in any path. ✓ (This is precisely why it never fires in the app — see
     finding 1.) Reduce Motion returns `builder(context, value)` directly. ✓

2. **Stagger re-fire + timer hazards — RE-FIRE CONFIRMED (finding 1); timers safe.**
   `Future.delayed(widget.delay)` in `_MicroMotionEntranceState.didChangeDependencies`
   (micro_motion.dart:60-63) is guarded by `mounted`, capped at 480ms
   (`MicroMotion.stagger` clamps index to 0–8), and every new test advances time past
   all timers (stagger test: pump 2s + 1s; dynamic/smoke tests: `pumpAndSettle`). No
   test ends with a pending entrance timer. The infinite-pulse interaction is handled
   by bounded pumps where the pulse is live (today_widgets_test.dart:385-389) — except
   the latent hazard noted in finding 3. Entrances do not re-fire on tab switches
   (IndexedStack, app_shell.dart:114); they re-fire only on the reload remount
   (finding 1).

3. **Removed inner entrance from today_hero — nothing relied on it.** Grep across
   `lib/` and `test/`: `MicroMotionEntrance` now appears only in today_screen.dart;
   TodayHero tests (today_widgets_test.dart:91-152) never referenced it; the component
   gallery uses `TrajectoryLens` directly (dev/component_gallery_app.dart:45). No
   double-wrapping anywhere (no other widget embeds its own entrance). ✓

4. **Contrast math — recomputed by hand (WCAG relative luminance, same formula as
   `Color.computeLuminance`); all new asserts are true with real margin:**
   - dark `stateAttention`/`stateDanger` `#FF887D` vs canvas `#080B10` ≈ **8.5:1** (≥3 ✓)
   - light `actionPrimary` `#4A57E8` vs canvas `#F3F6F8` ≈ **5.1:1** (≥3 ✓)
   - light `stateStable` `#00796B` vs canvas ≈ **4.9:1** (≥3 ✓)
   - light `stateAttention` `#C43C31` vs canvas ≈ **4.8:1** (≥3 ✓)
   - light `stateDanger` `#A92F28` vs canvas ≈ **6.2:1** (≥3 ✓)
   - light `textPrimary` `#10151D` vs canvas ≈ **16.9:1**; dark `textPrimary`
     `#F4F7FB` vs canvas ≈ **18.3:1** (≥4.5 ✓)
   - light `actionOnPrimary` `#FFFFFF` on `actionPrimary` ≈ **5.5:1**; dark
     `#10151D` on `#8A94F5` ≈ **6.7:1** (≥4.5 ✓)
   Not passing by luck. (Observation, not a finding: dark `stateAttention` and
   `stateDanger` are the same hex `#FF887D`.)

5. **`excludeSemantics: true` on `_DriverBar` — hides nothing needed.** The excluded
   children are two decorative Containers and the visible label `Text`, whose content
   is fully duplicated in the semantics label ("HRV driver, z-score 0.5") — VoiceOver
   users get the label plus the numeric z-score the visual bar only implies. No loss;
   net gain. See finding 4 for the ±2 clamp nuance.

6. **Dynamic Type test — 2.0 claim acceptable; one clip-vs-wrap exception documented.**
   iOS's largest accessibility size maps to ≈2.0× body text in Flutter, so "largest iOS
   scale (~2.0)" is fair (docs hedge with "~"). `textScaleFactorTestValue` is not
   deprecated in the pinned SDK (flutter_test `window.dart:321`), consistent with the
   pre-existing frontend_smoke_test usage. Clip-vs-wrap: the tab label clamp
   (app_shell.dart:265-282) truncates with `TextOverflow.fade` rather than wrapping —
   a motivated, documented iOS-tab-bar exception (DESIGN_SYSTEM §6 now records it);
   `_CardTag` (session_plan_card.dart:129-145) sits inside `Expanded > Column`, so the
   new `Flexible` genuinely wraps instead of overflowing. Coverage gap in finding 3.

7. **Doc accuracy — DESIGN_SYSTEM.md §6/§8 match the implementation, with one
   overstatement (finding 2).** Verified line-by-line: 60ms/index stagger capped at 8
   (`micro_motion.dart:22-23`); spring rise + fade once on mount (:48-90); 1.5s path
   draw (`trajectory_lens.dart:51`); single idle loop = `MicroMotionPulse` only
   (grep: the sole `.repeat(` in `lib/` is micro_motion.dart:149; the accordion
   controller is state-driven); count-up 600ms ease-out, static first render, tabular
   figures (`recovery_ring.dart:24-28`); tab morph 160ms (`TracendMotion.quick`,
   tokens:170) with 1.3× label clamp and 70pt capsule (app_shell.dart:183,271-273).
   §8: data-viz semantics exist for ring/driver bars (this chunk), sparkline, trend
   chart, trajectory lens, intensity bar, targets grid, measurement deltas (prior
   chunks, spot-checked); all five chips in the app are padded (grep: exactly 5 chip
   sites, all with `MaterialTapTargetSize.padded`), Wrap spacing `xs` = 8pt satisfies
   the ≥8pt gap; bubble semantics "Coach said"/"You said" present
   (coach_message_bubble.dart:34-35); notification-sheet copy matches the native
   scheduler ("Every day at 7:00 PM" ↔ `DateComponents(hour: 19)`, "Sunday at 6:00 PM"
   ↔ `DateComponents(hour: 18, weekday: 1)` — SceneDelegate.swift:131,150; weekday 1 is
   Sunday). Handoff/PROGRESS_CONTEXT claims checked against the diff and found accurate.

8. **AGENTS.md / plan compliance — clean apart from finding 1.** No migrations/RPCs
   (UI-only phase boundary held; no supabase/ files touched); no secrets; wrapper
   commands only (the plan's gate update to
   `./scripts/deno.sh test --allow-env --allow-net supabase/functions` aligns the local
   gate with ci.yml:41 / deploy.yml:31 — still via wrapper); glass budget still 2
   visible `TracendGlass` sites (app_shell.dart:181, today_hero.dart:211); no
   placeholders/TODOs/dead code in the new code; motion rules hold (all new motion
   reduceMotion-gated; only idle loop remains the NOW-dot pulse); tests written from
   code behavior (count-up static/animating/reduce-motion, ring count-up, stagger count
   of 9, contrast, overflow matrix). New inline comment at app_shell.dart:269-270 is
   consistent with existing repo precedent for short explanatory comments
   (app.dart:35,84) — not flagged. Copy audit: the diff adds no visible copy (only a
   semantics label); spot checks above support the handoff's audit claims.

## Checklist results

- Migrations (forward-only, additive): n/a — none in diff.
- RPCs consumed by Flutter / schema_version: n/a — no RPC changes.
- Contract fixtures: n/a — no response-shape changes.
- RLS on new user-owned tables: n/a — no schema changes.
- Secrets: ok — none introduced; no `RETENTION_WORKER_SECRET` movement.
- Wrappers (no direct tool invocations): ok — plan gate still `./scripts/*.sh`.
- MVP boundaries: ok — no excluded features/infra.
- No placeholders/dead code: ok — finding 1 is an integration gap, not a placeholder.
- Docs amended with behavior change: finding #2 (one overstatement); otherwise ok.
- Tests proportional to new logic: ok — finding #3 notes a coverage gap (NIT).

## Gate results

Not run (read-only review per instructions; flutter/deno wrappers not invoked).
Commit message claims, taken unverified: 284 Flutter tests pass (was 274; +10 new:
3 count-up, 1 ring count-up, 1 stagger, 2 dynamic-type, 3 contrast tests), deno 94
pass, iOS release build 25.2 MB, 0 analysis issues. Test-count arithmetic is
consistent with the diff. Recommend the standard Chunk 5 final gate
(`./scripts/pre-deploy.sh` equivalent per plan §8.4) before merge.
