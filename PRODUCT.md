# Product

<!-- impeccable:product-schema 1 -->

## Platform

ios

## Users

Healthy adults 18+ following a personalized training and nutrition plan over a five-to-six-month
transformation. Two confirmed audiences: beginners who need guidance, and experienced lifters who
want valid current practices respected. Primary user today is the solo owner and private-beta
testers on TestFlight. *(Derived from `DESIGN.md` Product and Audience.)*

## Product Purpose

Tracend is an evidence-driven AI personal trainer. It combines approved plans, workout execution,
confirmed meals, check-ins, optional HealthKit summaries, measurements, and progress evidence into
one clear next action. Success means the user always knows what to do now, why it is right, and
where to look deeper — even when evidence is incomplete.

## Positioning

A precise coaching instrument that becomes calm when the next action is clear. Honest about missing
data, AI estimation, and persistent plan changes where competitors fabricate scores and readiness
rings. Every number traces to a real repository/RPC field; nothing is invented for the interface.

## Operating Context

Daily use on iPhone (designed 390×844pt, validated from 375pt), often mid-day or at the gym.
Apple Watch supplies health data (HRV, resting HR, sleep) via HealthKit sync. Plans are
approval-gated: Coach proposes, the owner accepts. Flutter app over Supabase RPCs; production DB
access is read-only from design sessions.

## Capabilities and Constraints

- Five-tab shell: Today · Train · Coach · Nutrition · Progress. Account is a detail route from
  Today, never a sixth tab.
- Train owns: active plan, per-day workout prescription and execution, training history.
- Training load metrics (ACWR ratio, day strain, monotony) are server-computed per day from
  completed sessions; currently no list-RPC exposes a week of per-day strain.
- Plan changes are persistent decisions that require an explicit Accept; nothing preselects.
- AI usage shows real RPC fields only. Provider credentials never appear on device.
- Honesty gates: missing data reads "No data"/"Not enough data", never a fabricated zero or score.
- Voice: direct, calm, specific, nonjudgmental. Buttons use outcome verbs (Start workout,
  Confirm meal, Accept change). No streak anxiety, shame, or fake urgency.
- Anti-patterns (owner-ratified): no neon gym styling, no activity rings/readiness-score radial
  dashboards, no KPI-card walls, no chat-first coaching, no glass content cards, no emoji icons.

## Brand Commitments

Working name "Tracend" pending trademark/App Store clearance. Tagline: "Your body. Your data.
Your next move." Visual direction "Kinetic Precision" (training-log discipline + instrument
readout + forward momentum), ratified as the dark "Precision Pro" implementation in
`docs/DESIGN_SYSTEM.md`: semantic tokens, Spline Sans display + IBM Plex Mono tabular data,
12/24/28pt radii, tonal gradient cards with chrome-only glass. The Today tab is the reference
implementation of the committed world.

## Evidence on Hand

Real data in production Supabase (28 days of sessions, computed metrics, adherence); sample
content must be plainly marked and never passed off as the owner's live numbers. Stitch screen
references imported under `design/stitch/` — implementation references, not product authority.

## Product Principles

1. Answer "What should I do now?" before "Why?" before "Review or change?" — on every screen.
2. Evidence expands on demand; the first view is decisive and quiet.
3. Never hide missing data, stale evidence, AI estimation, or a persistent plan change.
4. One primary action per screen.
5. Familiar over novel in interaction; precision and honesty are the product.

## Accessibility & Inclusion

WCAG AA contrast, 44pt targets, VoiceOver labels on custom controls, Dynamic Type to the largest
accessibility sizes, Reduce Motion honored. *(From DESIGN.md Accessibility section.)*
