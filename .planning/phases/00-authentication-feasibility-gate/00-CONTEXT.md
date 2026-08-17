# Phase 0: Authentication Feasibility Gate - Context

**Gathered:** 2026-08-17
**Status:** Ready for planning

<domain>
## Phase Boundary

Produce an empirical, trustworthy GO or NO-GO decision for exactly one safe browser-return authentication path on current macOS. The corrected proof establishes profile authentication, a separately bounded entitlement result, visible sign-out absence, and verified cleanup in two ordered runs; it does not establish renewal, tune/key authorization, or audible playback.

Phase 0 may build only a disposable macOS proof harness and sanitized decision artifacts. It does not build the production app shell, public `SiriusXMClient` API, Keychain persistence, catalog/library UI, durable playback coordinator, skins, updater, packaging, or release infrastructure. Those remain in later phases and cannot begin without a Phase 0 GO result.

</domain>

<decisions>
## Implementation Decisions

### Empirical premise and single-path ordering

- **D-01:** The previous documentation-only `NO-GO unsupported` conclusion is superseded. SiriusXM's lack of public third-party authentication documentation is not evidence that an owner-operated path is infeasible.
- **D-02:** Treat the completed owner-authorized capture only as sanitized preliminary evidence: it proved that a legitimate browser-issued session can drive honest native account, tuning, manifest, and key requests, but it did not prove compatibility with macOS `WKWebView`.
- **D-03:** Evaluate purpose-scoped `WKWebView` browser-return first. Evaluate native-direct password authentication only if WebKit is ruled out by the strict fallback threshold below. Never build, retain, or offer both production paths.

### Browser-return proof finish line

- **D-04:** `GO browser-return` requires two separate owner-operated runs through the real current-macOS `WKWebView` harness.
- **D-05:** Superseded by D-19 for browser-return. Tune/key authorization and audible playback are Phase 2 concerns, not owner-visible Phase 0 closure requirements.
- **D-06:** Superseded by D-20. Renewal is not an owner observation or a GO condition.
- **D-07:** Superseded by D-20. No renewal outcome may delay, qualify, or invalidate the corrected Phase 0 decision.
- **D-08:** Only one attempt may be in flight. The owner controls and confirms a conservative cooldown between the two successful runs.

### Native-direct fallback threshold

- **D-09:** Native-direct evaluation is permitted only after a reproducible WebKit-specific incompatibility. Normal browser success plus one owner-operated WebKit failure must be corroborated by a secret-free local diagnostic that reproduces the same runtime limitation.
- **D-10:** Credential rejection, account or subscription errors, CAPTCHA, MFA/challenge behavior, HTTP `403` or `429`, rate limiting, bot/access-control signals, ambiguous outcomes, and transient network failures never unlock native-direct fallback.
- **D-11:** After WebKit is ruled out, present the sanitized failure and explicitly disclose that native-direct exposes the password to the disposable app. Native-direct work or live attempts require a separate owner approval; there is no automatic transition.
- **D-12:** Superseded by D-21. Native-direct remains not-applicable after a verified browser-return result; the corrected finish line does not reopen it.

### Human control, stop behavior, and evidence safety

- **D-13:** The account owner enters credentials and operates every real authentication surface. Automation must not type, inspect, record, or infer credentials and must not solve or evade provider controls.
- **D-14:** Any protected, challenged, rate-limited, suspicious, or ambiguous outcome stops the active evaluation immediately. It does not trigger retry, alternate-path execution, browser/client spoofing, or a workaround.
- **D-15:** The durable feasibility bundle contains only allow-listed semantic outcomes, harness/build revision, rounded dates, opaque run labels, owner-confirmed cooldown, cleanup status, and the single final decision: `GO browser-return`, `GO native-direct`, or `NO-GO unsupported`.
- **D-16:** Raw HAR data, request or response bodies, cookies, credentials, tokens, authorization headers, account identifiers, stream URLs, playback keys, WebKit storage, and other secret-bearing material are never planning artifacts or logs and must be removed after each run. D-18 is the sole narrow in-memory exception.
- **D-17:** Superseded by D-19. Login or token handoff alone is insufficient: each new run separately proves profile authentication, bounded entitlement, visible sign-out absence, and verified cleanup.

### Corrected Phase 0 Authority (Plans 00-14 through 00-16)

- **D-18:** After the owner explicitly initiates the bounded import, the harness may select only the current first-party `AUTH_TOKEN` and consume it once in volatile memory for the approved authentication check. It must never enumerate other browser state, persist or log the value, or retain it after cleanup.
- **D-19:** The corrected browser-return finish line is exactly two ordered `browser-probe-v3` runs: run-1, owner-confirmed cooldown, then run-2. Each has only authentication, separately bounded entitlement, visible sign-out absence, and verified cleanup. Profile success is authentication-only and can never establish entitlement.
- **D-20:** Renewal is not an owner observation, artifact field, or GO condition. It is explicitly deferred from this phase.
- **D-21:** Tune/key authorization, AVFoundation, and audible playback are Phase 2 ownership. Native-direct is not applicable after verified browser-return and does not supply an alternate Phase 0 closure path.
- **D-22:** Historical v2 evidence and any prior owner observation count as zero current complete runs. `owner-result-v3` accepts only current canonical semantic fields and rejects stale or handwritten input.
- **D-23:** No owner activity may begin before a supported entitlement contract and passing synthetic suite. Unsupported entitlement finalizes `NO-GO unsupported` with zero runs and no provider/UI work.

### Agent Discretion

- Exact proof-harness target names, file organization, and internal type names.
- The owner-facing sequence and status copy, provided credential entry stays entirely inside the SiriusXM surface for browser-return and every live transition requires explicit owner action.
- The safe technical mechanism for narrow single-consumption session transfer, profile authentication, bounded entitlement classification, sign-out absence, and cleanup.
- The exact owner-confirmed cooldown guidance; it must not add a playback, renewal, tune/key, or native-direct condition.
- Safe closed vocabularies and deterministic synthetic fixtures that cannot contain provider or account secrets.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Product and phase contract

- `.planning/PROJECT.md` — native scope, core value, secret-handling constraints, and no-bypass policy.
- `.planning/REQUIREMENTS.md` — `FEAS-01` through `FEAS-05` plus downstream authentication, security, client, and playback boundaries.
- `.planning/ROADMAP.md` — Phase 0 goal, hard Phase 1 dependency, success criteria, and scope fence.

### Corrected premise and prior findings

- `.planning/phases/00-authentication-feasibility-gate/.continue-here.md` — blocking anti-patterns, sanitized empirical findings, and the required correction to the documentation-only premise.
- `.planning/phases/00-authentication-feasibility-gate/00-VERIFICATION.md` — historical `gaps_found` verdict for the original offline implementation; use it to avoid repeating the failed evidence model.

### Downstream architecture and safety constraints

- `.planning/phases/01-safe-interoperability-foundation/01-CONTEXT.md` — single-path production authentication, owner control, and reusable-client boundary decisions.
- `.planning/phases/01-safe-interoperability-foundation/01-RESEARCH.md` — platform guidance and unresolved provider-specific feasibility facts.
- `.planning/research/ARCHITECTURE.md` — reusable-client and volatile-adapter boundaries.
- `.planning/research/PITFALLS.md` — upstream-change, secret-handling, access-control, and playback risks.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- `Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityCore/EvidenceContract.swift`: strict canonical parsing and allow-listed decision fields can be revised for empirical runtime evidence.
- `Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityCore/CandidateSelection.swift`: single-candidate derivation and latching provide a useful no-fallback-by-accident pattern.
- `Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityCore/DecisionGate.swift`: two-run validation, terminal stop outcomes, cooldown confirmation, cleanup confirmation, and deterministic final-decision derivation remain useful.
- `Spikes/AuthenticationFeasibility/Tests/AuthFeasibilityCoreTests/`: existing deterministic tests provide a base for revised contracts and stop-policy coverage.

### Established Patterns

- Fail closed on unknown or protected provider behavior.
- Persist semantic classifications only; reject unknown fields and raw provider data.
- Derive the terminal decision from validated evidence rather than allowing manual edits to unlock Phase 1.
- Keep live subscriber activity owner-initiated, sequential, bounded, and outside CI.

### Integration Points

- Add a disposable current-macOS GUI proof harness beside the offline tracer; no WebKit, AppKit/SwiftUI, or AVFoundation harness exists yet.
- The browser-return harness uses the SiriusXM web surface for owner credential entry, then consumes only the named current first-party `AUTH_TOKEN` once in ephemeral memory for profile authentication and bounded entitlement classification before sign-out and cleanup.
- The existing evidence schema's public-reference premise and canonical unsupported bundle are historical implementation details, not authoritative feasibility results; planning must revise or replace them.
- The resulting sanitized decision bundle remains the hard input gate for every Phase 1 plan.

</code_context>

<specifics>
## Specific Ideas

- The corrected phase is a real experiment, not a documentation eligibility review.
- Prefer a purpose-scoped `WKWebView` because it keeps the subscriber password in the SiriusXM web surface while allowing a native session handoff.
- Prove the corrected authentication-only closure: profile authentication plus separately bounded entitlement, visible sign-out absence, and cleanup—not merely that a token exists.
- Preserve only sanitized protocol shapes and typed outcomes. The prior raw capture was deleted and must not be recreated as a durable artifact.

</specifics>

<deferred>
## Deferred Ideas

- Production client APIs, Keychain persistence, full catalog behavior, durable playback/recovery architecture, macOS listening UI, skins, and release infrastructure remain in Phases 1–5.
- Phase 0 proves no playback path. Phase 2 owns tune/key, playback, catalog, metadata, recovery, and the general listening feature set.

</deferred>

---

*Phase: 00-authentication-feasibility-gate*
*Context gathered: 2026-08-17*
