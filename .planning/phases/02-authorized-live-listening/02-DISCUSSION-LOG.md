# Phase 02: Authorized Live Listening - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-08-19
**Phase:** 02-authorized-live-listening
**Areas discussed:** Lineup organization, Live control semantics, Recovery experience, Metadata freshness

---

## Lineup Organization

| Option | Description | Selected |
|--------|-------------|----------|
| Use conservative defaults | Predictable channel-number/category organization, explicit catalog freshness, and current authorization checked before playback. | ✓ |
| Discuss selected user-visible choices | Ask the owner to choose lineup and cache presentation details individually. | |

**User's choice:** Use conservative defaults.
**Notes:** The owner said they are not an expert in SiriusXM online-player behavior and delegated provider-dependent decisions. Provider contracts remain research questions rather than owner preference questions.

---

## Live Control Semantics

| Option | Description | Selected |
|--------|-------------|----------|
| Use conservative defaults | Treat playback as live radio, with resume at the current live edge and no rewind promise. | ✓ |
| Discuss selected user-visible choices | Ask the owner to define provider-specific pause and resume behavior. | |

**User's choice:** Use conservative defaults.
**Notes:** Actual stream behavior must be tested with authorized playback and AVFoundation. The decision does not assume website behavior or promise time-shifting.

---

## Recovery Experience

| Option | Description | Selected |
|--------|-------------|----------|
| Use conservative defaults | Bounded same-channel recovery with distinct failure classes and no infinite retry or silent channel switch. | ✓ |
| Discuss selected user-visible choices | Ask the owner to choose retry counts, timeouts, and provider-specific recovery triggers. | |

**User's choice:** Use conservative defaults.
**Notes:** Research and planning own exact retry limits and triggers based on empirical and platform evidence.

---

## Metadata Freshness

| Option | Description | Selected |
|--------|-------------|----------|
| Use conservative defaults | Keep audio independent, mark last-known data stale, then show unavailable rather than invented values. | ✓ |
| Discuss selected user-visible choices | Ask the owner to choose provider-specific cadence and artwork precedence. | |

**User's choice:** Use conservative defaults.
**Notes:** Research determines actual metadata cadence and the fields/artwork SiriusXM makes available.

---

## the agent's Discretion

- Current catalog, tuning, authorization, stream-resolution, and metadata contracts.
- AVFoundation compatibility and any evidence gate for considering a fallback engine.
- Exact bounded retry, backoff, timeout, stall, sleep/wake, polling, and freshness parameters.
- Minimal Phase 02 native presentation, semantic type names, adapter boundaries, error copy, and artwork precedence.

## Deferred Ideas

None.
