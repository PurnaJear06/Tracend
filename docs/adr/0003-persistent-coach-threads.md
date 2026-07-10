# ADR 0003: Persistent Coach Threads

**Status:** Accepted  
**Date:** 2026-07-04

## Decision

Store owner-scoped Coach threads and messages in PostgreSQL under forced RLS.
Send only the latest 20 messages plus bounded deterministic evidence to the
provider. Keep the immutable daily Head Coach decision separate and pinned
above conversation. Thread or account deletion removes messages.

## Consequences

Conversation works like a familiar saved chat without granting the model tools,
database access, or mutation authority. Replies expose evidence and missing
data. Persistent suggestions continue through the existing approval flow.

