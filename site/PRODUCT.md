# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Surface

The Tracend marketing site and waitlist (`site/`). Visitor mode: **Persuade**. The app's own
product truth lives in `docs/PRD.md`, `docs/UX_FLOWS.md` and `docs/DESIGN_SYSTEM.md`; this file
covers only what the website may say and how it speaks.

## Users

Adults who train in a gym, own an iPhone and an Apple Watch, and want a personal trainer they don't
pay for. Most arrive from a short video inside the Instagram or TikTok in-app browser, on a phone,
in the evening or between sets. They give the page a few seconds before deciding whether to read
on.

## Product Purpose

Tracend reads training, food, sleep and recovery from the iPhone and Apple Watch the visitor
already owns, and every morning turns them into what to do today, with the reason. The page's job
is a waitlist signup from someone who understands that loop.

## Positioning

- What pros get from a trainer and a nutritionist: a plan for your goal, read against your recovery
  every day and adjusted so you stay on course. The goal comes first; everything serves it.
- One app that covers the day and the night: training, food, sleep and recovery.
- Others stop at a score. Tracend turns the score into today's session, with its reason.
- Nothing new to buy: it uses the iPhone and Apple Watch you already own.
- Your plan only changes when you approve it.
- Sees what a trainer can't: how your body responded overnight. Never "better than a trainer".

## Claims the site may make (match the shipped app)

- The recovery score (0–100) and its band words, from HRV, resting heart rate, sleep and breathing
  rate against your own normal, plus recent training.
- Sleep quality, logged workouts (sets, reps, load, effort), training load and its trend, meals
  from a photo with protein and calories, weight trend, progress photos.
- A daily decision on Today: today's session as planned or adjusted, with the reason in plain words.
- Coach answers questions using your own numbers.
- Plans are approved by you and saved as versions; nothing in the plan changes without that.
- The plan still works when the AI, Apple Health or the network is down.
- Platforms: iPhone; Apple Watch recommended, never required; Android in testing. Say "For
  iPhone, best with Apple Watch", never Watch-only. Android and other smartwatches stay "in
  testing" (never "available" or a date) until they ship (owner, 2026-10-15).
- AI and privacy: AI features send data only after the athlete agrees, to a company the app names
  first; progress photos stay private to the account and go to AI only if the athlete uses the
  physique check and agrees to its notice; AI can be turned off and the plan keeps working.

## Feature coverage (check before any page change)

Shipped features from docs/PRD.md and docs/UX_FLOWS.md, and where the page shows them.

| Feature | Where on the page |
| --- | --- |
| Plans shaped by age, sex, history and limits; the profile remembers answers, limits, preferences | "Made for you. Never a template." (and the hero) |
| Onboarding: goal, about you, schedule, equipment, limits, current lifts, focus | "Your plan, in three steps", step 1 |
| Apple Health usual months, coach questions (0 to 3), experienced path keeps what works | "Your plan, in three steps", step 2 |
| Plan proposal: training week, starting loads, nutrition targets, reasoning; approve, request changes, reject | "Your plan, in three steps", step 3 |
| Set logging with effort, new bests | Story, "You train hard"; bento |
| Meal photo, then confirm | Bento, "Food"; the hero's dinner card on wide screens |
| Sleep and recovery score from five drivers, morning check-in | Story, "You sleep short", "Your body answers"; demo |
| Today's session adjusted, with the reason | Story, "Today, adjusted"; "Other apps stop at the score" |
| Muscle map for the plan's week | "Every workout, mapped to your body" |
| Weight trend and body measurements (waist, chest, hip, arm, thigh) toward the goal, strength (workouts done, best lifts) | "It checks your progress" |
| Weekly review, calculated from logs, no AI | "It checks your progress" |
| Progress photos (private) and physique check setting focus muscles (owner, 2026-10-13: live, no "testing" label; keep "AI visual estimate, not a measurement"; confirmed 2026-10-15) | "It checks your progress" |
| Coach chat with evidence and data gaps | "Ask your Coach anything" |
| Plan changes need approval; versions kept | Bento line; "Other apps stop at the score" |
| Plan works when AI, Apple Health or network is down | Bento line |
| Export and delete your data; AI only after consent, turn AI off | Join section trust line; privacy page |

## Coming next (owner decision, 2026-10-13)

Shown only under a label reading "Coming next. Not in the beta yet.", never with a date. Since
2026-11-15 it is one short row at the end of "Five apps that never talk to each other", not a
section of its own: the page sells what the beta has.
- Live Activity for a workout in progress: the Dynamic Island keeps the session after you leave
  the app, and you log sets (weight, reps) from the Dynamic Island or the Lock Screen.
- An Apple Watch app for logging sets.

## Claims the site must not make

- Any AI model name, anywhere (decision D11, 2026-10-15). AI companies (Anthropic, DeepSeek, Groq)
  are named only in the privacy page's processor list; the app's consent notice names the company
  for each feature.
- "Progress photos are never sent to AI": the physique check sends the photos the athlete
  chooses, after its notice.
- Apple Watch as required, or the app as Watch-only.
- Per-muscle readiness or recovery (recovery is whole-body). The body map shows what you trained and
  what is planned.
- Heart rate during sets, per-set response, streaks, or a 3D body model, until they ship. The body
  map is the app's 2D front and back muscle map.
- Automatic daily plan swaps that need an Approve tap, until persistent proposals ship. Today's
  adjustment is advice shown with its reason.
- Cause and effect between a session and a night ("shown alongside", not "caused").
- "Tracks 24/7 without a watch", "no subscription", medical or diagnostic wording.
- Ratings, testimonials, user counts or press that don't exist.

## Page structure (2026-11-15)

The page is a pitch, in this order: hero (headline, one line, the form, the Coach's call) → the
story → try it (the sliders) → five apps in one → made for you → Coach → progress → muscle map →
"Other apps stop at the score" → three steps to a plan → join.

- The story answers one question, "How did it know to go lighter?", in four moments of one day:
  train, sleep, recovery, adjust. Each moment rests long enough to read. Do not add moments that
  are not part of that answer; other features have their own sections.
- The hero copy and form never wait for a script, and on a phone the form is on the first screen.
- One primary action, "Join the beta", always lime (`.btn-primary`, the nav button, the form
  button). White is for selected states (tabs, segmented controls) only.
- Time is a small label on each moment, never the largest thing on screen.
- Anything shown beside the hero phone lives in the phone's own tilt and light (inside
  `.dev-tilt`): what it read sits behind its left edge, its answer in front. Never lay a flat card
  over the tilted phone. On a phone the answer is a notification on the phone's screen.
- On a phone nothing scrolls visibly behind the menu, and anything that sticks or docks slides in
  and out; it never snaps.

## Voice

Short verbs. 5th–7th grade reading level. Specific numbers over adjectives. Calm, direct, a little
dry. Never "AI coach" as the lead, never hype, never shame. Buttons name the outcome ("Join the
beta").

## Evidence on Hand

Every number on the page is a labelled example for a synthetic athlete. App screens are rebuilt
from the Flutter widgets with example data, never screenshots carrying real health values.

## Accessibility & Inclusion

WCAG 2.2 AA. Keyboard and screen reader complete. 44 px targets. Reduced motion gives a complete
static page. Works in iOS in-app browsers at 375 px.
