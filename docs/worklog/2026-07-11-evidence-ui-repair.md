# Evidence UI and Truth Repair — 2026-07-11

Repaired repeated HealthKit matching and same-day measurement ambiguity. Rebuilt
Today around one action and a compact Signal Rail, combined Apple Health status
and useful evidence, and replaced unlabeled curved steps/weight charts with a
shared date-aware linear chart. Image generation was intentionally not used;
the distinctive identity comes from live coaching evidence rather than artwork.

Local verification: Flutter analysis clean, 69/69 Flutter tests, and 313/313
PostgreSQL/RLS checks.

Hosted rollout: migration `20260711220000` deployed with local/remote parity.
The signed hosted 20.1 MB iOS release build installed and launched on the
owner's iPhone, and strict code-signature verification passed.

Owner visual follow-up replaced the confusing Signal Rail with a generated
coaching horizon and tappable Recovery, Training, and Nutrition readiness
factors. Progress now derives its headline and unsmoothed chart from the same
ordered effective measurement list, clips all custom painting, and leaves more
floating-tab clearance. Profile and goals and AI usage are functional detail
routes backed by RLS-scoped PostgreSQL/RPC data. Flutter analysis is clean and
70/70 tests pass, including 320-point and Dynamic Type layouts. The optimized
496 KB project asset is `assets/visuals/tracend-coaching-horizon-v1.jpg`; the
signed hosted 20.7 MB replacement installed/launched and passed strict signing.
