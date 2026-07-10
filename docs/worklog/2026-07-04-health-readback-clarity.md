# Health readback and training clarity — 2026-07-04

The owner reported that partial HealthKit status and the existing charts did
not explain what data was working. Read-only hosted inspection confirmed seven
stored summary days. Steps, active energy, workouts, resting heart rate, and
HRV had samples; sleep and HealthKit weight did not. The latest hosted sync was
still the earlier seven-day request, not the new 31-day backfill.

Flutter now reads owner-scoped `daily_health_summaries` into Today. It shows a
dated metric grid, renders sleep and steps only from at least two stored values,
and explains missing sleep without inferring permission denial from an empty
HealthKit query. Partial status now names categories found and absent.

Train no longer draws a static fixture curve or claims a fictional week,
schedule, or recent load. Hosted workout selection explicitly joins the active
plan and prefers the current weekday. Comparable completed-set analytics remain
a future evidence-backed slice rather than a placeholder chart.

Verification: Flutter formatting and analysis pass; 57 widget/unit tests pass.
Unsigned and hosted-config release builds pass. Automatic signing, strict
code-sign verification, and physical iPhone installation pass; CLI launch was
blocked only because the device was locked. No backend mutation, provider call,
or private value was added to source files.

The complete current tree was rebuilt again after the owner requested an
unambiguous device refresh. Format, clean analysis, 57/57 tests, the unsigned
19 MB device build, automatic signing, and strict code-sign verification pass.
The hosted-config app was freshly installed on the paired iPhone 12; only the
first automatic launch was denied because the phone was locked. A subsequent
unlocked CLI launch succeeded.
