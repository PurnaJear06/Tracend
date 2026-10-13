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
- Platforms: iPhone with Apple Watch today; Android and other smartwatches are "in testing" (never
  "available" or a date) until they ship.

## Feature coverage (check before any page change)

Shipped features from docs/PRD.md and docs/UX_FLOWS.md, and where the page shows them.

| Feature | Where on the page |
| --- | --- |
| Plans shaped by age, sex, history and limits; the profile remembers answers, limits, preferences | "Made for you. Never a template." (and the hero) |
| Onboarding: goal, about you, schedule, equipment, limits, current lifts, focus | Film act 1, "You set the goal" |
| Apple Health usual months, coach questions (0 to 3), experienced path keeps what works | Film act 1, "It gets to know you" |
| Plan proposal: training week, starting loads, nutrition targets, reasoning; approve, request changes, reject | Film act 1, "You approve the plan" |
| Set logging with effort, new bests | Film act 2, "You train"; bento |
| Meal photo, then confirm | Film act 2, "You eat"; bento |
| Sleep and recovery score from five drivers, morning check-in | Film act 2, "You sleep", "Your body answers"; demo |
| Today's session adjusted, with the reason | Film act 2, "Today, adjusted"; "Other apps stop at the score" |
| Muscle map for the plan's week | "Every workout, mapped to your body" |
| Weight trend and body measurements (waist, chest, hip, arm, thigh) toward the goal, strength (workouts done, best lifts) | "It checks your progress" |
| Weekly review, calculated from logs, no AI | "It checks your progress" |
| Progress photos (private) and physique check setting focus muscles (owner, 2026-10-13: live, no "testing" label; keep "AI visual estimate, not a measurement") | "It checks your progress" |
| Coach chat with evidence and data gaps | "Ask your Coach anything" |
| Plan changes need approval; versions kept | Bento line; "Other apps stop at the score" |
| Plan works when AI, Apple Health or network is down | Bento line |
| Export and delete your data; photos private | Join section trust line |

## Coming next (owner decision, 2026-10-13)

Shown only inside a section labelled "Coming next" with "Not in the beta yet", never with a date:
- Live Activity for a workout in progress: the Dynamic Island keeps the session after you leave
  the app, and you log sets (weight, reps) from the Dynamic Island or the Lock Screen.
- An Apple Watch app for logging sets.

## Claims the site must not make

- Per-muscle readiness or recovery (recovery is whole-body). The body map shows what you trained and
  what is planned.
- Heart rate during sets, per-set response, streaks, or a 3D body model, until they ship. The body
  map is the app's 2D front and back muscle map.
- Automatic daily plan swaps that need an Approve tap, until persistent proposals ship. Today's
  adjustment is advice shown with its reason.
- Cause and effect between a session and a night ("shown alongside", not "caused").
- "Tracks 24/7 without a watch", "no subscription", medical or diagnostic wording.
- Ratings, testimonials, user counts or press that don't exist.

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
