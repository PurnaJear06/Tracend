# ADR 0004: Versioned Meal Schedules

**Status:** Accepted\
**Date:** 2026-07-04

## Decision

Store meal timing and planned foods in versioned schedule headers/items, independent of nutrition
targets. Exactly one schedule is active per owner. Activation is transactional and audited;
confirmed meals may link to a slot.

## Consequences

Nutrition can state what and when to eat while keeping planned, AI-estimated, and confirmed-consumed
data distinct. Editing preserves history and cannot silently rewrite the approved schedule.
