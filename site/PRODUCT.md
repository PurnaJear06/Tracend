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
  The morning check-in leads; the recovery score alone never changes a session (D9). The page's
  exact-load call ("Deadlift 3 × 3 at 140 kg, effort 7 at most") is the owner's pre-launch build
  (owner, 2026-11-27); until it ships the app words the change ("lighter", "one set fewer").
- Coach answers questions using your own numbers, and can look up any day the athlete logged
  (sets, meals, sleep, weight, past plans), with the evidence it used and the gaps.
- Plan changes asked for in chat (away or travel, diet break, swap an exercise, take a break): the
  Coach card shows Now and After, nothing applies until Approve, and Undo works for 7 days.
- Lock Screen and Dynamic Island set logging (Live Activity): the next set and a rest timer with
  +30s and Skip; Log set logs the pre-filled values. Never promise editing weight or reps there.
- Next-session targets from logged sets (top of the rep range on every set moves the load up),
  with "Last time" and "Your best".
- Meal photos that read nutrition labels, check the label's maths, and let the athlete pick the
  portion; each item says "From label" or "Estimated".
- The pain check: where, how strong, when; today's exercise is swapped or shortened for that joint,
  only today changes, and it says when to see a professional. No injury, rehab or medical wording.
- Facts the athlete confirms are remembered and re-checked later ("Still true?").
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
| Onboarding: goal, about you, schedule, equipment, limits, current lifts; Apple Health usual months; up to three coach questions; proposal with reasons; approve | "Your plan, in three steps" |
| Set logging with effort, new bests | Story, "You train hard" |
| Morning check-in leads the daily call | Story, "You check in"; demo note |
| Sleep and recovery score from five drivers | Story, "You sleep short", "Your body answers"; demo |
| Today's session adjusted, with the reason | Hero (the Coach's call); story, "Today, adjusted"; demo |
| Plan changes from chat, Now and After, Approve, Undo 7 days; versions kept | "Nothing changes until you say yes." |
| Lock Screen / Dynamic Island set logging | "Small jobs", card 1 |
| Next-session targets from logged sets | "Small jobs", card 2 |
| Meal photo and nutrition labels, portion, confirm | "Small jobs", card 4 |
| Pain check, today's swap | "Small jobs", card 3 |
| Remembered facts, "Still true?"; profile limits and preferences | "Small jobs", card 5 |
| Coach chat with lookups across history, evidence and data gaps | "Ask your Coach anything. It knows your history." |
| Weight trend and measurements, strength, weekly review (no AI), physique check (AI visual estimate, not a measurement) | "It checks your progress" |
| Export and delete your data; AI only after consent, turn AI off | Join section trust lines; privacy page |
| Plan works when AI, Apple Health or network is down | Not on the page since 2026-11-27 (true; say it again only where it earns its place) |

## Coming next (owner decision, 2026-10-13)

Only ever under a label reading "Coming next. Not in the beta yet.", never with a date. Since
2026-11-27 the page shows no coming-next row: Live Activity set logging shipped (#161) and is a
card in "Small jobs". Still not built: an Apple Watch app for logging sets.

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
- An Approve tap on today's adjustment: it is advice shown with its reason. Approve belongs to plan
  changes asked for in chat.
- Cause and effect between a session and a night ("shown alongside", not "caused").
- "Tracks 24/7 without a watch", "no subscription", medical or diagnostic wording.
- The physique check as open to every tester: the server runs it only for accounts on its allow-list
  (`PHYSIQUE_VISION_ALLOWED_USERS`, owner-only until the AI_SAFETY_SPEC §9 evaluation passes). The
  page keeps it under "It checks your progress"; widen the allow-list or relabel it before testers
  expect it (owner, 2026-11-27).
- Ratings, testimonials, user counts or press that don't exist.

## Page structure (2026-11-27)

The page is a pitch, in this order: hero (headline, one line, the form, the Coach's call) → the
story → try it (the sliders) → "Nothing changes until you say yes." → "The small jobs a coach does, done for you."
→ Coach → progress → three steps → join. About 18 phone screens; keep it from growing.
Every "Small jobs" card uses the same parts (stage, phone top, title, one line); a new job is a
new card in that rail, never a different layout.

- The hero headline names the morning moment ("Know what to lift today. And why."). A reel can
  link to its own headline with `?v=sleep`, `?v=log` or `?v=coach` (an inline script swaps it
  before first paint; set the reel's `utm_content` to the same word so signups can be compared).
- The hero copy sits outside the pinned stage. On a phone it scrolls like the page and never
  fades, so a form someone is typing in stays put; the phone peeks out under it and rises into the
  stage. On a laptop it lies over the stage's left column and fades as it scrolls off.
- The story answers one question, "How did it know to go lighter?", in five moments of one day:
  train, sleep, check in, recovery, adjust. Sam's numbers meet the app's rules (sleep under 6 h,
  check-in sore, recovery under 35). Do not add moments that are not part of that answer.
- The hero copy and form never wait for a script, and on a phone the form and the Coach's call are
  on the first screen.
- One primary action, "Join the beta", always lime (`.btn-primary`, the nav button, the form
  button, the docked button). White is for selected states (tabs, segmented controls) only.
- On phones a docked "Join the beta" button slides up once the hero form has scrolled away and
  steps aside near the closing form and while the keyboard is up; the nav button hides meanwhile.
- Time is a small label on each moment, never the largest thing on screen.
- Anything shown beside the hero phone lives in the phone's own tilt and light (inside
  `.dev-tilt`): what it read sits behind its left edge, its answer in front. Never lay a flat card
  over the tilted phone. On a phone the answer is a notification on the phone's screen.
- On a phone nothing scrolls visibly behind the menu, and anything that sticks or docks slides in
  and out; it never snaps.
- Mock UIs in the new sections are rebuilt from the shipped app's code (the file each one follows
  is listed in Change.astro and Extras.astro); change them when the app changes.

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
