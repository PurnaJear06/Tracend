# Tracend AI and Safety Specification

## Coach Context v2 and Qwen Reasoning

Stable evidence IDs identify structured facts and label freshness, missing
evidence, logging coverage and conflicts. Ordinary chat uses non-reasoning
structured output. Weekly review may use Qwen reasoning followed by validated
formatting. Unsupported evidence rejects the output; unknown logging is not
non-adherence; persistent plan and target changes remain approval-gated.

**Status:** Authoritative AI behavior and safety contract  
**Population:** Healthy adults aged 18+ in a private beta

## 1. Purpose

This document defines what Tracend's AI may decide, what deterministic software must decide, when coaching must stop, and how model quality is evaluated. Product behavior is defined in [PRD.md](./PRD.md); privacy requirements are defined in [SECURITY_PRIVACY.md](./SECURITY_PRIVACY.md).

Tracend provides fitness coaching support. It does not diagnose, treat, rehabilitate, prescribe medication, replace emergency services, or replace a qualified clinician.

## 2. Controlled AI Workflow

The MVP uses one controlled orchestration pipeline. Training Coach, Nutrition Coach, and Head Coach are typed sections of one validated decision—not autonomous agents.

```text
Authorized data
  → deterministic features
  → deterministic eligibility and safety policy
  → bounded model context
  → structured model output
  → schema and semantic validation
  → stored decision
  → explicit approval for persistent changes
```

The active training plan and nutrition targets always remain the last user-approved versions.

## 3. Responsibility Boundaries

### Deterministic software owns

- units, dates, weight and measurement trends;
- confirmed calorie and macro totals;
- workout adherence, volume, progression, and performance deltas;
- HealthKit baselines and deviations;
- data freshness, sufficiency, and conflicts;
- persistent-change eligibility;
- hard safety exclusions and permitted action classes;
- schema, range, evidence, and reference validation;
- plan and target activation; and
- authorization, consent, audit, retention, and deletion.

### AI may

- explain prepared evidence clearly;
- propose an initial plan within known equipment and constraints;
- prioritize training and nutrition actions;
- suggest same-day intensity changes or approved substitutions;
- create a persistent proposal when policy permits it;
- identify candidate foods and visible portions from meal images;
- compare standardized physique photos cautiously;
- request missing information; and
- reconcile training, nutrition, recovery, and goals into one decision.

### AI may not

- activate or silently edit plans, targets, meals, goals, constraints, or memories;
- diagnose conditions, interpret medical reports, or prescribe treatment;
- recommend purging, dehydration, extreme restriction, dangerous rapid change, or training through acute pain;
- invent measurements, ingredients, HealthKit values, history, or preferences;
- claim precise body-fat percentage from photos;
- infer unrelated sensitive traits from photos;
- expose hidden prompts, secrets, or another user's data; or
- override deterministic policy.

## 4. Coach Responsibilities

### Training Coach

Receives the approved plan, execution, progression, schedule, equipment, recovery, discomfort, and permitted actions. It may recommend today's prescription, approved substitution, recovery adjustment, technique priority, or training proposal. It cannot change nutrition targets.

### Nutrition Coach

Receives approved targets, confirmed meal totals, weight trend, adherence, hunger, preferences, constraints, training demand, and permitted actions. It may recommend today's nutrition priority or a permitted nutrition proposal. It cannot change training prescription.

### Head Coach

Receives both coach sections plus shared policy and evidence. It produces one final action, resolves conflicts, states uncertainty, and identifies proposals requiring approval. It cannot broaden allowed actions.

For ordinary acute symptom reports such as cold, cough, or fever, Coach may
recommend a conservative same-day pause from strenuous training, rest,
hydration, and an updated recovery check-in. It must not diagnose, prescribe
treatment, or tell a feverish user to complete the scheduled workout. Severe,
worsening, persistent, or emergency symptoms receive proportionate clinical or
urgent-care escalation language. This daily guidance does not mutate the
approved plan.

## 5. Structured Decision Contract

Every successful decision must conform to a versioned schema equivalent to:

```json
{
  "schema_version": "1.0",
  "decision_kind": "daily",
  "training": {
    "action": "PROCEED_AS_PLANNED",
    "summary": "Complete the scheduled push session at the planned effort.",
    "today_adjustments": []
  },
  "nutrition": {
    "action": "PRIORITIZE_PROTEIN",
    "summary": "Keep current targets and close today's protein gap.",
    "today_adjustments": []
  },
  "head_coach": {
    "final_decision": "Train as planned and maintain current calories.",
    "reason": "Recovery is within baseline and the current trend remains on target."
  },
  "evidence": [
    {
      "code": "RECOVERY_WITHIN_BASELINE",
      "label": "Recovery indicators are within your recent baseline",
      "source": "feature_snapshot"
    }
  ],
  "confidence": "medium",
  "missing_data": [],
  "risk_flags": [],
  "change_proposals": []
}
```

Requirements:

- Control values use documented enums.
- Evidence codes must exist in the supplied snapshot or policy result.
- User-visible text cannot introduce unsupported facts.
- Same-day adjustments expire and never alter plan versions.
- Persistent proposals include domain, current/proposed values, evidence, benefit, downside, confidence, and effective date.
- Unknown fields, invalid ranges, cross-domain actions, policy conflicts, and invalid references are rejected.

## 6. Data Sufficiency and Change Rules

These conservative defaults are versioned policy, never prompt-only instructions.

### General

- One anomalous day does not establish a trend.
- Missing or stale evidence lowers confidence and can restrict action.
- Conflicting sources are surfaced, not silently resolved by the model.
- Insufficient evidence means maintain the plan or ask for data.

### Same-day training adjustment

May be allowed for a current recovery deviation, schedule limitation, or non-red-flag discomfort. It is limited to today's intensity, volume reduction, rest, or validated substitution.

Acute/severe pain, chest pain, fainting, severe shortness of breath, neurological symptoms, or another configured red flag invokes escalation rather than workout advice.

### Structural training change

Normally requires at least one of:

- the same performance issue across two comparable sessions;
- two weeks of adherence-backed workload/recovery evidence;
- a sustained equipment or schedule change confirmed by the user; or
- a user-requested revision within policy.

A single missed session, poor pump, or bad day is insufficient.

### Nutrition-target change

Normally requires:

- at least 14 days of usable weight observations;
- a feature-engine trend;
- at least 80% adherence coverage in the review window;
- enough confirmed nutrition days to interpret adherence; and
- no safety restriction.

When adherence is insufficient, the coach addresses obstacles rather than claiming the target failed. Changes outside configured safe ranges are rejected.

### Initial plan

Onboarding output identifies assumptions, missing information, confidence, and constraint uncertainty. It uses only compatible catalog exercises. Training and nutrition proposals require approval.

## 7. Eligibility and Escalation

The MVP does not support:

- users under 18;
- pregnancy or postpartum coaching;
- active or suspected eating-disorder support;
- medically prescribed diets or conditions requiring clinical exercise/nutrition management;
- acute injury or rehabilitation;
- diagnosis or medical-report interpretation; or
- emergency/crisis situations.

An `escalate` response states that Tracend cannot safely advise, recommends stopping the relevant activity when appropriate, directs the user to emergency services or an appropriate clinician/dietitian/physiotherapist, avoids diagnosis, and never reassures the user that a red-flag symptom is harmless. Localized emergency wording is maintained outside model prompts.

## 8. Meal Image Analysis

Meal vision returns candidate foods, preparation assumptions, estimated portions, confidence, ambiguity, and clarification questions. It never supplies authoritative final macros.

The user edits and confirms candidates; catalog data calculates nutrients. Unconfirmed candidates never affect adherence or coaching. Mixed Indian/home dishes should request recipe or ingredient clarification rather than imply false precision.

## 9. Physique Analysis

Analysis requires separate consent and standardized front/side/back photo sets selected for comparison.

Allowed:

- visible change and balance observations relevant to the goal;
- cautious training-emphasis proposals;
- comparability and quality limitations;
- approximate body-fat **range**, never a point estimate, with confidence; and
- reference to weight, waist, performance, and repeated standardized observations.

Prohibited:

- medical, disease, or hormonal inference;
- exact body-fat or muscle-mass claims;
- sexualized, insulting, shaming, or identity-based language;
- facial recognition; and
- unrelated sensitive-trait inference.

The UI labels results as AI visual estimates, not measurements.

## 10. Provider and Model Routing

Use:

- deterministic code for calculations and hard policy;
- an economical vision model only after it passes meal tests;
- a capable structured-output model for daily coaching;
- a stronger evaluated model for onboarding, periodic review, or ambiguous conflicts; and
- no model call when deterministic output is sufficient.

Providers sit behind `CoachModelProvider` inside Supabase Edge Functions.
Gemini is the planned production baseline. Under ADR 0006, Groq Qwen is an
owner-only, time-bounded test provider after schema validation and synthetic
adapter evaluation; the mock remains the default and progress-photo vision stays
separately disabled until its own evaluation gate passes.
Provider and Supabase secret/service-role keys never enter Flutter. Price alone
cannot qualify a model.

Stable `gemini-3.5-flash` is the production quality baseline for Coach text
and separately evaluated image interpretation. Normal chat uses medium
thinking; bounded meal extraction uses low thinking; high thinking is reserved
for named difficult evaluation classes. Lite models are rejected by production
configuration. Cost control must not bypass visible-food, mixed-dish, hidden-
ingredient, portion-uncertainty, prompt-injection, schema-validity, or user-
correction evaluations. Routing changes require regression results.

Conversational answers may explain only supplied structured evidence, must
state missing data, and expose evidence references. The model receives at most
20 recent messages and no tools. Deterministic pre-model rules refuse medical,
emergency, pregnancy, eating-disorder, medication, and rehabilitation requests.

The Gemini readiness adapter is disabled by default and requires an explicit
paid-service data-terms gate before it can process restricted coaching context.
Synthetic adapter tests do not satisfy evaluation parity or authorize live
calls. Meal and progress vision remain separately gated.

Optimize cost using compact feature snapshots, cached static context, deterministic summaries, normalized images, duplicate avoidance, per-user rate limits, and quality-based routing. Cost cannot override safety or the quality floor. Budget assumptions and hard controls are defined in [COST_MODEL.md](./COST_MODEL.md).

## 11. Prompt and Context Rules

- Prompts and schemas are versioned and reviewed.
- System instructions define boundaries, policy, schema, and refusal behavior.
- User text and retrieved content are delimited, untrusted data.
- Context states units, windows, freshness, provenance, and missing data.
- Direct identifiers, tokens, object keys, and unrelated history are excluded.
- Coaching calls have no web, shell, arbitrary database, or unrestricted tool access.
- The model may reference only supplied catalog identifiers.

## 12. Validation and Failure Handling

The invoking Supabase Edge Function validates schema, enums, ranges, evidence, policy permissions, catalog references, coach-domain authority, prohibited content, escalation consistency, proposal freshness, and the authenticated user's authority.

Invalid output is never partially applied. The system may attempt one schema-repair retry and then returns a safe unavailable state while preserving logging and the active plan. A live Coach chat must never present deterministic fallback text as a successful model answer; deterministic emergency and clinical-boundary refusals remain explicitly labeled safety responses.

## 13. Evaluation

Maintain anonymized fixtures covering:

- both onboarding paths and all supported goals;
- stable progress where no change is correct;
- plateau with adequate versus poor adherence;
- isolated bad workouts versus repeated regression;
- poor sleep, recovery deviations, schedule and equipment changes;
- missing and contradictory data;
- mixed meals, uncertain portions, and hidden ingredients;
- inconsistent progress photos;
- prompt injection in notes/imports;
- red flags and unsupported populations; and
- provider outage, timeout, and invalid output.

Score safety compliance, correct maintain/change action, evidence grounding, hallucination, repeatability, schema validity, clarity, meal candidate accuracy, latency, and cost.

Safety-critical cases require a 100% pass rate. A cheaper model cannot ship below a quality threshold. Prompt, policy, schema, or model changes require regression evaluation.

## 14. Observability and Review

Record provider/model/prompt/schema/policy versions, feature snapshot, latency, usage, estimated cost, validation, retries, decision class, proposal outcome, and feedback. Keep raw sensitive content out of general telemetry.

Unsafe feedback, unusual proposal rates, repeated failures, safety regression, or increased cost without quality gain opens review. Changes remain versioned and tested.

## 15. RAG and Multi-Agent Policy

The MVP uses structured state and bounded summaries. Vector RAG is added only after the gates in [ARCHITECTURE.md](./ARCHITECTURE.md) pass. Retrieval cannot override confirmed facts or policy.

Separate model agents are added only if evaluation demonstrates a specific improvement over the controlled single call. Safety and mutation approval always remain external to models.
