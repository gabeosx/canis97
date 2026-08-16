# Phase 0: Authentication Feasibility Gate - Pattern Map

**Mapped:** 2026-08-16  
**Files analyzed:** 4 planned file groups  
**Analogs found:** 2 planning-contract analogs / 4 file groups

> The repository is greenfield: there are no Swift sources, SwiftPM manifests, test targets, or app projects to copy. Phase 0 therefore reuses the established *planning* contracts from Phase 1, while keeping every POC artifact disposable and outside future production targets.

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `Spikes/AuthenticationFeasibility/Package.swift` | config | batch | `Packages/SiriusXMClient/Package.swift` proposed by `01-01-PLAN.md` | structural-only |
| `Spikes/AuthenticationFeasibility/Sources/.../FeasibilityContract.swift` | model / utility | transform | `AuthenticationOutcome.swift` proposed in `01-PATTERNS.md` | conceptual-only |
| `Spikes/AuthenticationFeasibility/Tests/.../FeasibilityContractTests.swift` | test | transform | `RedactionTests.swift` and `SessionCoordinatorTests.swift` proposed in `01-PATTERNS.md` | conceptual-only |
| `.planning/phases/00-authentication-feasibility-gate/00-DECISION.md` | decision artifact | event-driven | `01-06-SUMMARY.md` / `01-08-SUMMARY.md` contracts | exact planning-contract |

### Scope boundary

`Spikes/AuthenticationFeasibility/` is a recommended isolated location, not a required production layout. It must not be named `Packages/SiriusXMClient`, imported by an app target, or treated as the public library. Phase 0 context requires a smallest disposable harness and explicitly defers the app shell, public client API, Keychain, playback, and releases. [Source: `00-CONTEXT.md` lines 9-11, 48-52, 90-91]

## Pattern Assignments

### `Spikes/AuthenticationFeasibility/Package.swift` (config, batch)

**Analog:** The future standalone SwiftPM package shape in `01-PATTERNS.md`, `Packages/SiriusXMClient/Package.swift` assignment.

**Copy the boundary, not the product structure:** if Phase 0 needs code at all, create one dependency-free SwiftPM executable/test package for offline contract evaluation. Do not create `SiriusXMClient`, an Xcode app, Keychain storage, an updater, a playback target, or a provider live transport implementation.

**Planning-derived excerpt** (`00-CONTEXT.md` lines 48-52):

```text
Reuse Foundation, SwiftPM, Swift Testing, and OS logging/privacy primitives.
Keep POC code isolated from production targets and easy to delete or promote selectively.
The harness must expose semantic outcomes and stop conditions, never raw provider data.
```

### `Spikes/AuthenticationFeasibility/Sources/.../FeasibilityContract.swift` (model / utility, transform)

**Analog:** Phase 1’s planned semantic `AuthenticationOutcome.swift` and fail-closed adapter boundary, documented in `01-PATTERNS.md`.

**Core pattern:** use a closed, semantic vocabulary. It should represent only candidate eligibility, terminal stop classes, an owner-confirmed proof disposition, and exactly three terminal decisions:

```text
GO browser-return
GO native-direct
NO-GO unsupported
```

Unknown, missing, duplicated, malformed, or conflicting input maps to `NO-GO unsupported`; it must never select a candidate, retry, create a fallback, or preserve raw provider data.

**Decision rules to copy** (`00-CONTEXT.md` lines 19-24, 36-46):

```text
Browser return requires explicit first-party evidence for a fixed callback/return contract.
Native direct is considered only after browser return is safely ruled out.
A stop signal produces NO-GO unsupported; it does not trigger another method or workaround.
Phase 1 requires a GO result backed by both proof runs.
```

### `Spikes/AuthenticationFeasibility/Tests/.../FeasibilityContractTests.swift` (test, transform)

**Analog:** Phase 1’s planned synthetic canary and one-attempt test strategy in `01-PATTERNS.md`; its validation map assigns synthetic terminal-shape coverage to `AuthenticationOutcomeTests`, one-attempt behavior to `SessionCoordinatorTests`, and redaction to `RedactionTests` (`01-VALIDATION.md` lines 45-48).

**Core test cases:** pure offline tests only.

- Every stop/unknown/ambiguous class yields `NO-GO unsupported`.
- Browser eligibility cannot be inferred from a visible web sign-in, copied token, cookie, or redirect observation.
- Native eligibility is unreachable until browser is explicitly ruled out.
- A GO cannot be formed without two separate `authenticated-entitled-signed-out` proof dispositions, owner-confirmed cooldown, and one shared selected path.
- Synthetic secret canaries cannot appear in diagnostic/event/decision serialization.

No test may contact SiriusXM, open a browser, use account data, inspect storage, or run in a timer/retry loop. The two proof runs are manual-only rather than CI sampling (`00-CONTEXT.md` lines 26-32, 58; `01-VALIDATION.md` lines 83-90).

### `.planning/phases/00-authentication-feasibility-gate/00-DECISION.md` (decision artifact, event-driven)

**Analog:** `01-06-PLAN.md` Task 01-06-02 and `01-08-PLAN.md` final continuation contract.

**Exact contract to reuse:** one authoritative artifact, one exact decision line, closed safe fields, and a mechanically fail-closed malformed-input branch. Phase 1’s result mapper states that a missing, duplicated, malformed, or non-allow-listed classification maps to unsupported without asking for or inferring additional browser/account evidence (`01-06-PLAN.md` lines 96-115).

**Recommended safe schema:**

```text
Feasibility decision: GO browser-return | GO native-direct | NO-GO unsupported
Selected path: browser-return | native-direct | unsupported
Run 1: <allow-listed semantic result>
Cooldown observed: owner-confirmed | not-applicable
Run 2: <allow-listed semantic result>
Phase 1 continuation: unlocked | blocked
```

The artifact may additionally contain harness version, rounded date, opaque run labels, cleanup confirmation, and public first-party URLs. It must not contain credentials, tokens, cookies, account IDs, raw payloads, token-bearing URLs, screenshots, browser/session state, exact timings, or developer-tools data (`00-CONTEXT.md` lines 41-46).

## Shared Patterns

### Human-only live boundary

**Source:** `00-CONTEXT.md` lines 26-39; Phase 1 Task 01-08-02, `01-08-PLAN.md` lines 103-120.

Apply to: all checkpoint tasks and the decision writer.

```text
The account owner alone initiates each live attempt.
The executor accepts only an allow-listed semantic disposition.
Any challenge, control, rejection, missing entitlement, cleanup failure, or ambiguity blocks immediately.
```

The agent/planner/executor must not operate, observe, screenshot, automate, inspect, or extract from account/browser/provider state.

### Fail-closed decision derivation

**Source:** `01-06-PLAN.md` lines 97-115.

```text
Map a single allow-listed classification mechanically.
Missing, duplicate, malformed, or unrecognized input maps to unsupported.
Do not request, infer, or retain another candidate as fallback.
```

Apply to: contract code, tests, and the Phase 0 decision artifact.

### Redaction by construction

**Source:** `00-CONTEXT.md` lines 43-45 and Phase 1 validation map `01-VALIDATION.md` lines 47-48.

Use an allow-list of semantic fields rather than a best-effort scrubber. Synthetic canaries belong only in offline test input. `OSLog` values, if emitted, must be static/semantic or privacy-qualified; raw provider data has no representable API surface.

### Downstream precondition

**Source:** `00-CONTEXT.md` lines 43-46, 88-91.

Phase 0 produces the sole hard gate for Phase 1. A Phase 0 `NO-GO unsupported` is a valid terminal product result, not an invitation to begin Phase 1’s production package or to try another authentication method.

## No Analog Found

| File / Concern | Reason |
|---|---|
| Any actual Swift source, package manifest, or test implementation | No production or POC source exists in the repository. |
| Provider callback/native request implementation | It is evidence-dependent and must not be inferred, hard-coded, or designed from authenticated session material. |
| Browser/account interaction | Intentionally human-only and outside agent/browser automation. |

## Metadata

**Analog search scope:** repository root, Phase 0 context, Phase 1 context/research/validation/pattern map/plans 01-06 through 01-08  
**Files scanned:** 10 planning/instruction artifacts; 0 source files  
**Pattern extraction date:** 2026-08-16
