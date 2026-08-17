# Phase 0: Authentication Feasibility Gate - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-08-17
**Phase:** 00-authentication-feasibility-gate
**Areas discussed:** Proof finish line, Native-direct fallback threshold

---

## Why the Existing Context Was Replaced

The 2026-08-16 discussion correctly required authentication feasibility before production investment, exactly one selected authentication path, owner-operated live attempts, and strict access-control safety. Its public-documentation-first evidence premise was later shown to be invalid: it produced `NO-GO unsupported` without testing the intended owner-operated behavior. This discussion preserves the safety constraints while replacing that premise with an empirical current-macOS proof.

---

## Proof Finish Line

### Required scope

| Option | Description | Selected |
|--------|-------------|----------|
| Authentication boundary only | Two WebKit logins, session handoff, account/entitlement, tune/key negotiation, and cleanup; defer renewal and AVPlayer. | |
| Full playback feasibility | Also require legitimate session renewal and real AVPlayer audio before GO. | ✓ |
| Hybrid | Require only user-specified additions beyond authentication handoff. | |

**User's choice:** Full playback feasibility.

### Playback repetition

| Option | Description | Selected |
|--------|-------------|----------|
| Confirmed audio in both runs | Each run proves login through audible playback, sign-out, and cleanup. | ✓ |
| Audio once | Both runs prove authentication, but only one proves playback. | |
| Different threshold | Use a user-defined playback evidence bar. | |

**User's choice:** Confirmed audio in both runs.

### Renewal repetition

| Option | Description | Selected |
|--------|-------------|----------|
| One clean renewal across both runs | Prove the legitimate provider-issued renewal mechanism once without mutation, clock manipulation, or guessed fields. | ✓ |
| Renewal in both runs | Cross a renewal boundary during each proof run. | |
| Continuous playback only | Treat sustained playback across expiry as implicit renewal evidence. | |
| Different requirement | Use a user-defined renewal standard. | |

**User's choice:** One clean renewal across the two runs.

### Unreachable renewal evidence

| Option | Description | Selected |
|--------|-------------|----------|
| Keep Phase 0 incomplete | Missing evidence blocks GO without falsely claiming provider rejection. | ✓ |
| Record NO-GO unsupported | End the project when renewal cannot be proved. | |
| Permit GO without renewal | Defer the gap despite the expanded finish line. | |
| Different outcome | Use a user-defined result. | |

**User's choice:** Keep Phase 0 incomplete.

---

## Native-Direct Fallback Threshold

### Qualifying WebKit failure

| Option | Description | Selected |
|--------|-------------|----------|
| Reproducible WebKit-specific incompatibility only | Require a runtime-specific failure; challenges, account errors, rate limits, ambiguity, and transient failures never unlock fallback. | ✓ |
| Any clean WebKit failure | One non-challenge failure unlocks fallback. | |
| Never permit fallback | Any WebKit failure ends with NO-GO unsupported. | |
| Different threshold | Use a user-defined fallback rule. | |

**User's choice:** Reproducible WebKit-specific incompatibility only.

### Reproducibility evidence

| Option | Description | Selected |
|--------|-------------|----------|
| One owner attempt plus local diagnostics | Corroborate the live failure with a secret-free local WebKit test of the same runtime limitation. | ✓ |
| Two owner attempts | Repeat the same live failure after an owner-controlled cooldown. | |
| One owner attempt alone | Accept the first clearly classified runtime failure. | |
| Different standard | Use a user-defined evidence standard. | |

**User's choice:** One owner attempt plus secret-free local WebKit diagnostics.

### Transition to native-direct

| Option | Description | Selected |
|--------|-------------|----------|
| Separate owner approval gate | Present the sanitized failure and password-exposure disclosure before any native-direct work or attempt. | ✓ |
| Proceed automatically | The WebKit verdict immediately unlocks native-direct execution. | |
| Stop for reassessment | Record WebKit unsupported without evaluating native-direct. | |
| Different transition | Use a user-defined transition. | |

**User's choice:** Separate owner approval gate.

### Native-direct proof bar

| Option | Description | Selected |
|--------|-------------|----------|
| Same full bar | Two owner sign-ins, playback in both, one legitimate renewal, sign-out, and cleanup. | ✓ |
| Authentication only | Rely on earlier browser-token replay for playback feasibility. | |
| One complete run | Reduce password exposure by requiring a single run. | |
| Different proof bar | Use a user-defined native-direct standard. | |

**User's choice:** The same full proof bar.

---

## Agent Discretion

- Proof-harness organization and internal naming.
- Owner-facing sequencing and status copy within the locked human-control boundaries.
- Safe technical mechanisms for semantic completion, session handoff, renewal, authenticated key loading, playback confirmation, and cleanup.
- Bounded playback duration and owner-controlled cooldown guidance.

## Deferred Ideas

- Production authentication, Keychain persistence, catalog, durable playback/recovery, desktop UI, skins, and release work remain in later phases.
