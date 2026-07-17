# Tracend Vision

**Status:** Authoritative product direction\
**Audience:** Product, design, engineering, AI, safety, and private-beta testers

> **Tracend is an evidence-driven AI personal trainer that turns health, training, nutrition, and
> progress data into clear coaching decisions.**

**Working tagline:** Your body. Your data. Your next move.

Tracend is a working brand pending formal trademark and App Store name clearance.

## 1. Why Tracend Exists

Most fitness applications record activity, generate generic plans, or provide an open-ended chatbot.
They rarely close the coaching loop: understand the person, prescribe a plan, observe execution,
distinguish poor adherence from an ineffective plan, and make justified changes.

Tracend should behave like a competent personal trainer who has access to the user's consented data
and keeps a reliable record. It should tell the user what to do, why it matters, what evidence
informed the decision, and whether the current plan should remain unchanged.

The product is not defined by the number of AI agents it runs. Its value comes from consistent,
explainable decisions that improve as longitudinal evidence accumulates.

## 2. Target Users

The private beta supports healthy adults aged 18 and over who:

- want fat loss, muscle gain, recomposition, strength, or an aesthetic emphasis;
- train at a gym or with known equipment;
- are willing to log workout execution and confirm nutrition estimates;
- may be beginners needing an initial plan or experienced users bringing an active plan;
- use an iPhone and may use Apple Watch or other HealthKit-connected sources; and
- want practical coaching without the price or scheduling constraints of a human trainer.

The first and primary user is the owner during a five-to-six-month transformation. Friends and
family may join later through a private TestFlight beta.

## 3. Core Experience

Tracend operates a continuous coaching loop:

1. **Understand:** collect goals, history, schedule, equipment, preferences, constraints,
   measurements, optional standardized photos, and consented HealthKit summaries.
2. **Plan:** propose a training block and nutrition targets for the user to review and approve.
3. **Guide:** present today's workout, nutrition priorities, and recovery guidance.
4. **Observe:** record workout performance, meals, check-ins, recovery indicators, measurements, and
   adherence.
5. **Reason:** calculate trends deterministically, apply safety policies, and interpret the evidence
   through a controlled AI workflow.
6. **Decide:** maintain the plan or propose a specific, evidence-backed adjustment.
7. **Approve:** require the user to approve persistent changes before activating them.
8. **Learn:** retain confirmed preferences, accepted decisions, outcomes, and longitudinal
   summaries.

The user-facing Coach Room presents:

- **Training Coach:** today's training recommendation and relevant progression or recovery guidance;
- **Nutrition Coach:** today's nutrition priority and adherence guidance; and
- **Head Coach Decision:** one reconciled instruction, its evidence, confidence, missing data, and
  any proposed changes.

These are product perspectives within one controlled workflow, not autonomous agents negotiating
with each other.

## 4. Product Principles

### Evidence before novelty

Do not change a plan merely to appear intelligent. Stable execution is valuable. Every persistent
change must cite sufficient evidence and an explicit reason.

### Calculations before language models

Software calculates weight trends, adherence, training volume, progression, and recovery deviations.
AI interprets prepared facts and communicates a recommendation; it does not invent or silently
recalculate critical metrics.

### Confirmation before persistence

AI suggestions do not directly modify active training plans, nutrition targets, confirmed meals,
goals, limitations, or durable memories. The user reviews and confirms them.

### Useful uncertainty

Tracend must say when data is missing, conflicting, or insufficient. Approximate meal portions,
physique observations, and body-fat ranges always include confidence and limitations.

### Minimum necessary data

Collect, retain, and send only the information required for the feature the user requested. Health
data and progress photos are never advertising inputs.

### One clear decision

Training and nutrition recommendations must resolve into a straightforward next action. The product
must not bury users under competing coach personas, raw analytics, or motivational filler.

### Quality-efficient AI

Optimize model usage through compact context, caching, deterministic preprocessing, and
quality-based routing. Never select a cheaper output that fails the defined quality or safety
threshold.

## 5. Differentiation

Tracend is differentiated by the combination of:

- HealthKit-informed recovery and activity context;
- detailed strength-training execution data;
- photo-first nutrition logging with user confirmation;
- longitudinal measurements and standardized progress-photo comparison;
- stable plans with evidence-gated changes;
- explicit user approval and audit history;
- provider-neutral, evaluated AI rather than dependence on one model brand; and
- safety and privacy boundaries designed with the product rather than added later.

## 6. North-Star Outcome

The north-star outcome is:

> A user consistently follows a personalized plan and can understand, from recorded evidence, why
> the plan stayed stable or changed throughout a meaningful transformation.

Supporting indicators include:

- onboarding-to-approved-plan completion;
- percentage of planned workouts with execution data;
- meal and daily-check-in confirmation rate;
- weekly review completion;
- percentage of persistent changes containing valid evidence and explicit approval;
- user-rated usefulness and clarity of daily decisions;
- low frequency of contradictory, unsupported, or unsafe recommendations; and
- sustained use during the owner's five-to-six-month transformation.

Tracend does not promise a particular physique outcome. Outcomes depend on adherence, biology,
environment, and factors outside the application's control.

## 7. MVP Direction

The MVP is an iOS-first, private TestFlight product with:

- Sign in with Apple;
- beginner and experienced-user onboarding;
- configurable goals and an approved initial plan;
- HealthKit permission and daily-summary sync;
- workout prescription and set-level execution logging;
- daily check-ins;
- meal-photo analysis followed by editing and confirmation;
- manual weight and body measurements;
- private standardized progress photos and cautious comparison;
- daily Coach Room decisions;
- evidence-backed, approval-gated plan changes; and
- weekly progress reviews and decision history.

Detailed requirements are in [PRD.md](./PRD.md). System boundaries are in
[ARCHITECTURE.md](./ARCHITECTURE.md).

## 8. Anti-Goals

The MVP will not become:

- a medical diagnosis, treatment, rehabilitation, or emergency service;
- a generic motivational chatbot;
- an autonomous system that silently changes plans;
- an Android application;
- a trainer marketplace, social network, or competitive leaderboard;
- a subscription or payment product;
- a medical-report interpreter;
- an exercise-video form-correction system;
- a public App Store launch;
- a multi-agent demonstration whose complexity is not justified by measured quality; or
- a vector database added only to claim RAG experience.

## 9. Private-Beta Learning Goal

The private beta exists to validate the complete coaching loop, not market demand. The owner will
dogfood Tracend for at least two weeks before inviting others. Feedback will focus on decision
quality, logging friction, safety, trust, and whether recommendations resemble the behavior of a
careful real trainer.

Technical novelty is secondary to sustained usefulness. Architecture may expand only when observed
product needs or evaluations justify it.

## 10. Related Authority

- [PRD.md](./PRD.md): product behavior, scope, and acceptance criteria
- [ARCHITECTURE.md](./ARCHITECTURE.md): technical boundaries and data flow
- [DATA_MODEL.md](./DATA_MODEL.md): persistent entities and relationships
- [AI_SAFETY_SPEC.md](./AI_SAFETY_SPEC.md): AI responsibilities, decision rules, and safety
- [SECURITY_PRIVACY.md](./SECURITY_PRIVACY.md): consent, protection, retention, and deletion
