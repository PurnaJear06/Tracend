# 2026-07-01 — Phase 3 Workout and Check-In

Implemented the first Phase 3 vertical slice without using CoreSimulator.

- Added approved-plan workout expansion, prescriptions, sessions, performances, sets, amendments,
  and revisioned daily check-ins.
- Added authenticated, user-derived, idempotent RPCs for start, draft sync, completion, and check-in
  persistence. Direct client mutation remains denied.
- Added Flutter approved-workout reads, local draft restore/autosave, explicit sync state, set
  controls, completion, and the Today check-in sheet.
- Kept HealthKit and live coaching out of Phase 3.
- Verified Flutter formatting, analysis, 24 tests, database pgTAP 61/61, and an unsigned arm64
  iPhone release build (17.6 MB).

After owner approval, the Phase 3 migration was dry-run and deployed. Local and hosted versions
match. Physical-iPhone interruption/reconnection QA is pending.

A hosted-config signed build was produced with all heavy build state on the SSD, installed
successfully on the owner's connected iPhone 12, and verified in the device application inventory.
iOS denied the first terminal launch until the owner completes the one-time Developer App trust
action on the phone. The owner then trusted and launched the app successfully; account creation is
next.
