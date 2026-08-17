# Phase 0: Authentication Feasibility Gate - Research

**Researched:** 2026-08-16
**Domain:** Safe, human-operated authentication feasibility assessment for a native macOS app
**Confidence:** MEDIUM — Apple and SwiftPM mechanics are documented; SiriusXM-specific return, entitlement, renewal, and native-purpose semantics remain empirical questions governed by the locked bounded protocol.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- D-01 supersedes the prior documentation-only conclusion: lack of public third-party auth documentation is not evidence that an owner-operated path is infeasible.
- D-02 permits the sanitized prior owner-authorized findings to define preliminary expectations and safe bounds for the experiment, but raw capture or browser state cannot be reused.
- D-03 requires purpose-scoped owner-operated `WKWebView` first; native-direct is considered only after D-09 strict WebKit-specific rule-out, and both production paths are never retained.
- A GO result requires two separate owner-operated runs through the sole path, with explicit authentication, entitlement, tune/key authorization, audible playback, sign-out, verified cleanup, owner-controlled cooldown, and one legitimate renewal.
- Missing safe renewal evidence is incomplete, not `NO-GO unsupported`.
- Normal-browser success plus one reproducible owner-operated WebKit-specific failure and matching secret-free local corroboration is the only route to the separate native-direct approval decision.
- Protected, challenged, rate-limited, 403/429, bot/access-control, suspicious, or ambiguous behavior is immediately terminal and never triggers retry, fallback, spoofing, or workaround behavior.
- The account owner initiates and operates every live surface. Automation may observe only allow-listed app-bound navigation/return events and sanitized semantic transitions.
- The harness must never enumerate, read, copy, or persist browser cookies, WebKit storage, profiles, developer-tools data, credentials, or raw token/session material.
- A clean handoff may consume only material delivered explicitly through the observed app-bound return/callback contract in memory, then must immediately collapse it to semantic outcomes.
- Native-direct requires an honest purpose-scoped contract derived from allowable sanitized evidence and owner approval; missing public third-party documentation alone is non-dispositive.
- Phase 1 can execute only after a canonical two-run GO bundle; incomplete and NO-GO states remain blocked.

### the agent's Discretion

- Exact harness target/file names and internal protocol/type names.
- Safe closed vocabulary for semantic run dispositions and evidence fields.
- Offline synthetic fixtures and deterministic tests used before any account-owner attempt.
- Conservative cooldown guidance, provided the account owner controls and confirms it.

### Deferred Ideas (OUT OF SCOPE)

- Production client API, Keychain persistence, compatibility UI, catalog, playback, macOS integration, skins, and release work remain in Phases 1–5.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|---|---|---|
| FEAS-01 | Determine whether a clean first-party app-bound browser return exists without browser-state inspection. | Safe entry/provenance checklist, bounded owner-operated WKWebView protocol, explicit-return handoff, and incomplete/terminal routing. |
| FEAS-02 | If browser return is ruled out, evaluate one honest native path without spoofing, bypass, or fallback. | Isolated ephemeral-session candidate shape with a one-path latch and no endpoint guessing. |
| FEAS-03 | Complete two separate owner-initiated authenticated-and-entitled, clean-sign-out runs with cooldown. | Human-only run ledger and terminal decision procedure outside CI. |
| FEAS-04 | Stop on challenge, protection, rate limit, redirect, or ambiguity and retain no secret evidence. | Closed stop vocabulary, cancellation/cleanup protocol, and synthetic-only test fixtures. |
| FEAS-05 | Emit exactly one sanitized GO/NO-GO decision and block Phase 1 without GO. | Versioned decision artifact and Phase 1 handoff precondition. |
</phase_requirements>

## Project Constraints (from AGENTS.md)

- Use the repository’s GSD workflow and planning artifacts for changes; Phase 0 planning is the active workflow. [VERIFIED: AGENTS.md]
- Prefer project-local `.agents/` instructions and skills when present; `.agents/` is absent in this checkout. [VERIFIED: `rg --files .agents` returned no directory]
- The project is a genuine native macOS application, not a web wrapper; volatile SiriusXM behavior stays behind repairable adapters. [VERIFIED: .planning/PROJECT.md]
- Credentials and session tokens stay local and direct-to-SiriusXM; diagnostics are redacted and unknown authentication fails closed. [VERIFIED: .planning/PROJECT.md]
- Do not bypass CAPTCHA, MFA, subscription/device limits, anti-bot controls, DRM, or other service protections. [VERIFIED: .planning/PROJECT.md]

## Summary

Phase 0 should be a disposable, isolated SwiftPM/current-macOS harness that proves its safety and decision logic with synthetic inputs before any account-owner interaction, then runs the D-02/D-03 owner-operated WKWebView experiment. The harness must not contain a production client, persistent storage, endpoint guessing, browser automation, browser-state inspection, or a raw-response recorder. Its output is a sanitized feasibility state and eventual decision, never session material. [VERIFIED: .planning/phases/00-authentication-feasibility-gate/00-CONTEXT.md]

Public first-party evidence remains useful for the login entry surface, ordinary navigation/provenance, and audit trail, but public documentation completeness is not the feasibility gate. The browser question is resolved by a bounded empirical protocol: construct the purpose-scoped WKWebView from safe first-party bounds; let the owner operate it; observe only allow-listed app-bound navigation/return events; consume only explicitly delivered return material in memory; and persist only semantic outcomes. A missing public third-party callback document remains an honest open fact, not `NO-GO unsupported`. [VERIFIED: D-01 through D-03 in .planning/phases/00-authentication-feasibility-gate/00-CONTEXT.md]

**Primary recommendation:** Build the safety/decision core, establish the public entry and bounded observation contract, run the owner-operated WKWebView path first, and route complete, incomplete, strict-ruleout, and protected terminal outcomes exactly as locked.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|---|---|---|---|
| Public-provider-evidence review | Maintainer process | Local harness | Evidence is a human review input; the harness validates that it contains a complete, non-secret candidate description. |
| WKWebView empirical return | Native macOS harness | Account owner | A purpose-scoped WKWebView is the locked first path; the owner operates provider content while code observes only allow-listed app-bound events and semantic state. [VERIFIED: D-03, D-13, D-16] |
| Native-direct candidate | Native macOS harness | Provider boundary | A client-owned ephemeral session is permitted only after strict WebKit-specific rule-out and an honest purpose contract derived from allowable sanitized evidence plus separate owner approval. [CITED: https://developer.apple.com/documentation/foundation/urlsessionconfiguration/ephemeral] [VERIFIED: D-09 through D-12] |
| Stop-condition classification | Local harness | Human owner | The harness records only a closed semantic disposition and immediately terminates the run; the human observes any protected page or service response. |
| Sanitized decision artifact | Local filesystem | Phase 1 planning gate | A small versioned JSON/Markdown result is the only persistent Phase 0 output and contains no secret-bearing data. |

## Standard Stack

### Core

| Library / Tool | Version | Purpose | Why Standard |
|---|---:|---|---|
| Swift + SwiftPM | Swift 6.3.3 installed | Compile a minimal isolated executable and its tests. | SwiftPM supports executable and test targets; keeping tests separate prevents test frameworks from entering a shipped executable. [VERIFIED: `swift --version` returned `Apple Swift version 6.3.3`] [CITED: https://docs.swift.org/swiftpm/documentation/packagedescription/target/] |
| Foundation | OS-bundled | Candidate-local `URLSession`, URL parsing, `Codable`, and cancellation. | `URLSessionConfiguration.ephemeral` keeps caches, cookies, and credential storage out of persistent disk state. [CITED: https://developer.apple.com/documentation/foundation/urlsessionconfiguration/ephemeral] |
| WebKit | OS-bundled | Purpose-scoped owner-operated `WKWebView`, nonpersistent data store, allow-listed navigation/return observation, and teardown. | The locked phase requires testing the actual current-macOS WebKit runtime rather than substituting another browser API. [VERIFIED: D-02, D-03] |
| Swift Testing | Toolchain-bundled | Synthetic tests for no-retry, terminal stop, artifact schema, and decision selection. | SwiftPM supports test targets; testing-only libraries must terminate at test targets. [CITED: https://docs.swift.org/swiftpm/documentation/packagedescription/target/] |
| OSLog | OS-bundled | Static, allow-listed local diagnostic categories during a live owner-operated run. | Use static event identifiers; do not send callback URL, service error text, headers, or response values to logging. [VERIFIED: .planning/phases/00-authentication-feasibility-gate/00-CONTEXT.md]

### Supporting

| Library / Tool | Purpose | When to Use |
|---|---|---|
| `URLSessionConfiguration.ephemeral` | In-memory-only session configuration. | Only for the single evidence-qualified native-direct candidate; invalidate on cancellation, stop, or sign-out. [CITED: https://developer.apple.com/documentation/foundation/urlsessionconfiguration/ephemeral] |
| `WKWebsiteDataStore.nonPersistent()` | Ephemeral WebKit data boundary for the experiment. | Use for the owner-operated WKWebView; never enumerate or query its contents, and destroy the view/store after each run. [VERIFIED: D-03, D-16] |
| `JSONEncoder` / `JSONDecoder` | Versioned sanitized decision artifact. | Use strictly for allow-listed semantic labels and build/run metadata; do not serialize a `URL`, raw error, or provider response. [VERIFIED: .planning/phases/00-authentication-feasibility-gate/00-CONTEXT.md]

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|---|---|---|
| Isolated SwiftPM harness | Production app/SDK target | Rejected: it would couple a provisional feasibility outcome to Phase 1 production architecture. [VERIFIED: .planning/phases/00-authentication-feasibility-gate/00-CONTEXT.md] |
| Purpose-scoped WKWebView | `ASWebAuthenticationSession` or browser automation | The user locked WKWebView because actual WebKit compatibility is the empirical question. Automation remains rejected; narrow navigation/return observation is allowed only under the bounded protocol. [VERIFIED: D-02, D-03, D-13, D-16] |
| One empirically selected method | Browser/native selector or fallback | Rejected: it would mask viability evidence and violate the locked single-path decision. [VERIFIED: .planning/phases/00-authentication-feasibility-gate/00-CONTEXT.md] |

**Installation:** No external package installation. [VERIFIED: .planning/phases/00-authentication-feasibility-gate/00-CONTEXT.md]

## Package Legitimacy Audit

No external packages are recommended or installed in Phase 0; the package-legitimacy gate is not applicable. [VERIFIED: .planning/phases/00-authentication-feasibility-gate/00-CONTEXT.md]

## Architecture Patterns

### System Architecture Diagram

```text
public first-party entry/provenance + sanitized D-02 expectations
                               │
                    safe bounded construction
                               │
synthetic fixtures ───────> FeasibilityHarness ──> semantic-only artifact
                               │
                               v
                 owner-operated WKWebView first
                    │          │            │
             clean return   incomplete   protected/ambiguous
                    │          │            └──> NO-GO unsupported
                    │          └──> Phase 1 blocked; no native unlock
                    v
              complete two-run proof? ──yes──> GO browser-return
                    │
             strict D-09 rule-out only
                    │
       native purpose contract + owner approval
                    │
              complete two-run proof? ──yes──> GO native-direct
```

### Recommended Project Structure

```text
Package.swift                             # isolated, non-product feasibility package
Sources/
  AuthFeasibilityCore/                    # pure state machine and artifact schema
  AuthFeasibilityRunner/                  # explicit local command; no scheduled work
  AuthFeasibilityHarness/                 # bounded WKWebView first; native replaces it only after D-09/D-11
Tests/
  AuthFeasibilityCoreTests/               # synthetic sequence and schema tests
  Fixtures/                               # synthetic semantic cases only
Docs/
  AUTHENTICATION-FEASIBILITY.md           # owner runbook and evidence checklist
Artifacts/
  .gitkeep                                # decision artifact created manually, ignored if local
```

The browser and native live runtimes must be mutually exclusive at build/run configuration, not simply hidden by UI. Before strict rule-out the WKWebView experiment is the only live-capable path; after approved native selection the browser live source is removed and retained only as sanitized diagnostic evidence. [VERIFIED: D-03, D-09 through D-12]

### Pattern 1: Safe construction first, bounded experiment second

**What:** Model the experiment contract as a local, hand-reviewed record containing the public first-party entry surface, ordinary navigation/provenance bounds, sanitized D-02 expectation classes, allow-listed app-bound return shapes, semantic transitions, terminal stop bounds, and explicit owner approval. It cannot represent raw capture values or authenticated browser state. [VERIFIED: D-01, D-02, D-13 through D-16]

**When to use:** Before enabling the WKWebView constructor. Missing safe construction information leaves the experiment incomplete; missing public third-party callback documentation alone does not. [ASSUMED: exact local type naming] [VERIFIED: D-01]

**Required browser evidence:** Public first-party material establishes the entry surface and ordinary provenance. Sanitized owner-authorized findings may define preliminary expected shapes, but only the owner-operated WKWebView experiment establishes whether a clean app-bound return occurs. A matched return may deliver material explicitly in memory; no browser store is queried. [VERIFIED: D-01 through D-03, D-13 through D-16]

### Pattern 2: One terminal actor/state machine

**What:** A single actor owns run state. It accepts one owner-confirmed start, emits a safe semantic observation, and then reaches either `awaitingOwnerCooldown`, `readyForSecondRun`, or a terminal decision. There is no retry loop, background task, timer, polling loop, or concurrent start. [VERIFIED: .planning/phases/00-authentication-feasibility-gate/00-CONTEXT.md]

**When to use:** For both candidate kinds and for synthetic tests. It is the structural control that prevents a later UI/transport change from silently adding retries. [ASSUMED: actor implementation detail]

### Pattern 3: Least-data outcome boundary

**What:** Convert all live observations at the entry point into one allow-listed semantic value, then immediately discard transport/callback details. Persist only a decision record created from those semantic values. [VERIFIED: .planning/phases/00-authentication-feasibility-gate/00-CONTEXT.md]

**When to use:** Every failure, cancellation, sign-out, and artifact write. The decision writer accepts semantic fields, not `Error`, `URL`, `URLRequest`, `HTTPURLResponse`, or `Data`. [ASSUMED: type-level exclusion strategy]

### Pattern 4: Human checkpoint is part of the protocol

**What:** The executable must halt after each owner-confirmed observation and wait for a deliberate local acknowledgement. The code neither opens a second browser/native attempt nor calculates a retry time. [VERIFIED: .planning/phases/00-authentication-feasibility-gate/00-CONTEXT.md]

**When to use:** Two proof runs, cooldown confirmation, and sign-out confirmation. A human may write the cooldown confirmation as `observed`; no duration or account identifier is captured. [VERIFIED: .planning/phases/00-authentication-feasibility-gate/00-CONTEXT.md]

### Decision Artifact Schema

Use a versioned, allow-listed document. It should be valid only if it contains one of the following verbatim values from the source-of-truth context: `GO browser-return`, `GO native-direct`, or `NO-GO unsupported`. [VERIFIED: .planning/phases/00-authentication-feasibility-gate/00-CONTEXT.md]

```json
{
  "schemaVersion": 1,
  "decision": "NO-GO unsupported",
  "candidate": "none",
  "publicEvidence": ["https://first-party.example/reference"],
  "runs": [
    { "label": "run-1", "outcome": "unsupported", "signOut": "not-applicable" }
  ],
  "cooldown": "not-applicable",
  "cleanup": "confirmed",
  "recordedOn": "2026-08-16"
}
```

The JSON is a synthetic shape, not a live artifact. `schemaVersion`, candidate labels, safe outcomes, and cleanup labels are implementation discretion; the three decision strings above are locked. The writer must reject arbitrary strings, URLs outside a public-reference allow-list, free-text notes, provider response data, account identities, timestamps more precise than a date, and an artifact with fewer than two successful GO runs. [ASSUMED: schema field names and rejection mechanics] [VERIFIED: .planning/phases/00-authentication-feasibility-gate/00-CONTEXT.md]

### Downstream Handoff Contract

Phase 1 receives only: decision string, harness version/commit, rounded date, public evidence reference list, two opaque run labels for a GO, cooldown-confirmed boolean, and cleanup-confirmed boolean. It receives no credentials, session material, callback URL, endpoint, header, browser state, response body, or screenshot. [VERIFIED: .planning/phases/00-authentication-feasibility-gate/00-CONTEXT.md]

## Don’t Hand-Roll

| Problem | Don’t Build | Use Instead | Why |
|---|---|---|---|
| Browser automation/state extraction | WebView scraper, cookie exporter, DevTools parser, browser-profile reader | Purpose-scoped owner-operated `WKWebView` with only allow-listed navigation/return observation and semantic transitions | The phase must test WebKit while keeping credentials and authenticated browser state outside automation. [VERIFIED: D-02, D-03, D-13, D-16] |
| Persistent credential/cookie handling | Cookie jar, local token file, Keychain behavior | No persistent credentials in Phase 0; ephemeral session memory only where native-direct evidence qualifies | The phase is a disposable feasibility gate and its locked data boundary forbids retaining secrets. [VERIFIED: .planning/phases/00-authentication-feasibility-gate/00-CONTEXT.md] |
| Native HTTP stack | Socket/client-fingerprint emulation | Foundation `URLSession` with an ephemeral configuration | It offers OS-managed TLS and avoids persistent cache/cookie/credential stores. [CITED: https://developer.apple.com/documentation/foundation/urlsessionconfiguration/ephemeral] |
| Retry/cooldown automation | Retry engine, scheduler, polling loop | Human-confirmed pause between separately initiated runs | The user’s single-attempt and human-controlled-cooldown requirement is a safety control, not a performance issue. [VERIFIED: .planning/phases/00-authentication-feasibility-gate/00-CONTEXT.md] |
| Raw evidence recorder | HAR, request/response archive, screenshot bundle | Closed semantic event vocabulary and synthetic fixtures | Raw capture conflicts with the no-secret/no-browser-state boundary. [VERIFIED: .planning/phases/00-authentication-feasibility-gate/00-CONTEXT.md] |

**Key insight:** The feasibility harness validates decisions, not provider protocol. An unknown required contract fact blocks that action as incomplete; unknown or ambiguous behavior observed during a live attempt is terminal. Neither state authorizes deeper instrumentation. [VERIFIED: D-07, D-10, D-14]

## Common Pitfalls

### Pitfall 1: Repeating the documentation-only feasibility gate

**What goes wrong:** Missing public third-party callback documentation is treated as proof the owner-operated WKWebView path cannot work.

**Why it happens:** Provider documentation completeness is confused with empirical compatibility, despite D-01 superseding that premise.

**How to avoid:** Use public first-party material to establish the entry/provenance boundary, use sanitized D-02 findings only as preliminary expectations, then run the bounded owner-operated WKWebView protocol. Preserve ordinary no-return as incomplete unless strict D-09 rule-out or a locked terminal stop is proven. [VERIFIED: D-01 through D-03, D-09, D-14]

**Warning signs:** The plan requires a complete public callback contract before constructing WKWebView, or maps `documentation-open` directly to `NO-GO unsupported`.

### Pitfall 2: Native-direct speculation

**What goes wrong:** The project begins guessing endpoints, headers, request sequences, or app identity after browser evidence is absent.

**Why it happens:** An unsupported integration looks technically close to a normal HTTP client.

**How to avoid:** Native-direct is eligible only after strict D-09 rule-out, a purpose-scoped honest contract derived from allowable sanitized evidence, and separate D-11 approval. Unknown required request details remain incomplete and block launch; missing public third-party documentation alone does not justify guessing or a terminal decision. [VERIFIED: D-09 through D-12]

**Warning signs:** More than one candidate, request replay, spoofed identifiers, a proxy, or “try again with a different header.”

### Pitfall 3: Letting a harmless log become an evidence leak

**What goes wrong:** A callback URL, service error, response status context, or `Error` description lands in a console, test failure, or artifact.

**Why it happens:** Raw Foundation values are convenient to print during an early proof of concept.

**How to avoid:** Make the diagnostic and artifact APIs accept only closed enums/static strings; test that raw networking and callback types cannot be passed to them. [VERIFIED: .planning/phases/00-authentication-feasibility-gate/00-CONTEXT.md]

**Warning signs:** `print`, `debugPrint`, `localizedDescription`, `absoluteString`, JSON snapshots from a live run, or a source-controlled output directory.

### Pitfall 4: Treating login as entitlement proof

**What goes wrong:** A technically completed authentication operation becomes GO without explicit authorized-and-entitled evidence and clean sign-out.

**Why it happens:** Authentication, subscription entitlement, and session cleanup are distinct states.

**How to avoid:** A GO writer requires two completed runs with the full D-05/D-12/D-17 proof. Missing renewal or an ordinary uncorroborated no-return remains incomplete; protected or ambiguous evidence is terminal NO-GO. [VERIFIED: D-05 through D-07, D-12, D-14, D-17]

### Pitfall 5: Test or CI invoking the live path

**What goes wrong:** A unit test, script, or future CI configuration executes a real provider call after a refactor.

**Why it happens:** Candidate creation is reachable from the default executable or an integration-test helper.

**How to avoid:** Synthetic transport is the default and only test transport. Keep a live owner-operated command behind a local, explicit, non-CI build configuration and require a fresh human acknowledgement before one start. [VERIFIED: .planning/phases/00-authentication-feasibility-gate/00-CONTEXT.md]

## Code Examples

### Ephemeral native-direct boundary

```swift
// Source: https://developer.apple.com/documentation/foundation/urlsessionconfiguration/ephemeral
let configuration = URLSessionConfiguration.ephemeral
let session = URLSession(configuration: configuration)
defer { session.invalidateAndCancel() }
```

This pattern is valid only after strict D-09 rule-out, native purpose-contract qualification from allowable sanitized evidence, and separate D-11 approval. It does not authorize a request, select a user agent, read browser data, or change the one-attempt rule. [CITED: https://developer.apple.com/documentation/foundation/urlsessionconfiguration/ephemeral]

### Empirical WKWebView return boundary

Construct a purpose-scoped `WKWebView` with a nonpersistent website data store only after the public first-party entry/provenance record, sanitized preliminary expectations, stop bounds, and owner approval validate. The navigation delegate may classify only allow-listed first-party navigation and app-bound return shapes. On a match, it may pass explicitly delivered return material once in memory to the semantic client; it cannot query cookies, storage, profiles, developer tools, or unrelated page state. The durable record is only `clean-return`, `no-clean-return`, or a locked terminal class plus sanitized semantic proof states. [VERIFIED: D-01 through D-04, D-13 through D-16]

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|---|---|---|---|
| Documentation-gated system-browser callback | Owner-operated current-macOS WKWebView empirical return | Locked Phase 0 correction | Public documentation bounds provenance but does not answer WebKit compatibility; the experiment does, without browser-state extraction. [VERIFIED: D-01 through D-03] |
| Persistent/default URLSession for a proof | Ephemeral URLSession configuration | Current Apple documentation | Candidate-native traffic has no persistent cache/cookie/credential storage, and cleanup invalidates its memory state. [CITED: https://developer.apple.com/documentation/foundation/urlsessionconfiguration/ephemeral] |

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|---|---|---|
| A1 | Public official-site searches did not surface a SiriusXM third-party callback or native-direct authentication contract. | Summary | This remains an honest discovery gap only; it cannot prevent the bounded WKWebView experiment or become a terminal feasibility result. |
| A2 | The suggested target names, schema field names, and actor type names are suitable. | Architecture Patterns | Low: names can change without changing the safety contract. |
| A3 | A local explicit non-CI executable configuration can be enforced as a guardrail. | Common Pitfalls | Medium: planner must specify the exact build/run guard and test it. |

## Open Questions (RESOLVED)

These questions are resolved as empirical and fail-closed procedures, not as claims that SiriusXM publicly documents a contract this research did not find.

1. **RESOLVED — Does SiriusXM publicly document a fixed, app-bound browser callback contract?**
   - What we know: Apple supports such a callback model, but it requires provider-specified authorization and callback details. [CITED: https://developer.apple.com/documentation/authenticationservices/authenticating-a-user-through-a-web-service]
   - What’s unclear: No qualifying first-party SiriusXM developer document was found in this public-only research pass. [ASSUMED]
   - Recommendation: Use public first-party evidence to establish the login entry/provenance boundary, bind sanitized D-02 expectations and terminal stops, then run the owner-operated WKWebView experiment. Do not inspect browser state.
   - RESOLVED outcome: Public documentation absence is non-dispositive. The bounded empirical protocol records a clean explicit app-bound return, ordinary no-clean-return/incomplete, strict D-09 WebKit rule-out, or locked terminal stop. Only the explicit in-memory return may hand material to native semantic proof.

2. **RESOLVED — Does SiriusXM publicly document an honest native-direct application auth contract?**
   - What we know: Foundation can use an ephemeral request session without persistent state. [CITED: https://developer.apple.com/documentation/foundation/urlsessionconfiguration/ephemeral]
   - What’s unclear: The provider’s supported direct contract and service-protection expectations are unknown. [ASSUMED]
   - Recommendation: Do not invent, spoof, or probe a contract. After strict D-09 rule-out, derive an exact purpose-scoped honest contract only from allowable sanitized D-02 evidence and the approved bounded experiment, then obtain separate D-11 owner approval.
   - RESOLVED outcome: A native-direct candidate exists only after strict rule-out, `native-purpose-qualified`, and separate approval. Missing public third-party documentation alone does not block it; a missing concrete safe contract value remains incomplete and never authorizes a request.

3. **RESOLVED — What semantic signal will qualify as explicit entitlement?**
   - What we know: Phase 0 requires explicit authenticated-and-entitled state, but refuses raw provider data. [VERIFIED: .planning/REQUIREMENTS.md]
   - What’s unclear: The provider-specific semantic mapping must be confirmed by allowable sanitized evidence and the bounded run; public documentation may remain incomplete. [ASSUMED]
   - Recommendation: Encode the preliminary mapping from sanitized D-02 findings, accept it as established only after a bounded authenticated semantic check, and never retain raw provider response content.
   - RESOLVED outcome: Proof acceptance requires a canonical explicit-entitlement semantic mapping established from allowable sanitized evidence and the owner-approved experiment. An ambiguous observed entitlement outcome is terminal `NO-GO unsupported`; an unreached safe check remains incomplete.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|---|---|---:|---|---|
| Swift compiler / SwiftPM | Harness and synthetic tests | ✓ | Swift 6.3.3 | — [VERIFIED: `swift --version`] |
| Xcode IDE / `xcodebuild` | Required current-macOS WKWebView harness | ✗ | Command Line Tools only | Build/test the SwiftPM safety core first; record environment-pending until the exact Xcode/SDK gate passes, then construct the approved experiment. [VERIFIED: `xcodebuild -version` produced no version; `xcrun --find swift` returned CommandLineTools path] |
| WebKit framework | Browser experiment | Unknown until full Xcode SDK availability | — | Keep the WKWebView harness conditional on current-SDK readiness and owner-approved safe construction; tooling absence is incomplete, not provider infeasibility. [ASSUMED] |
| Public first-party entry/provenance | WKWebView construction | Required / bounded | — | Establish the official entry and ordinary navigation boundary; third-party callback documentation may remain open. [VERIFIED: D-01 through D-03] |

**Empirical dependency:** A safe owner-operated WKWebView return and explicit semantic proof must be observed before GO. Missing public third-party documentation is not a dependency failure; missing environment or safe-construction inputs leave execution incomplete, while locked protected/ambiguous outcomes close unsupported. [VERIFIED: D-01 through D-07, D-14]

**Missing dependencies with fallback:** Full Xcode is not needed for the pure SwiftPM state machine and tests; it is required before the owner-operated current-macOS WKWebView experiment. Until then the phase remains incomplete. [ASSUMED]

## Validation Architecture

### Test Framework

| Property | Value |
|---|---|
| Framework | Swift Testing / XCTest if toolchain compatibility requires it. [CITED: https://docs.swift.org/swiftpm/documentation/packagedescription/target/] |
| Config file | `Package.swift` — Wave 0 creates it. [ASSUMED] |
| Quick run command | `swift test` |
| Full suite command | `swift test` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|---|---|---|---|---|
| FEAS-01 | Browser experiment can run with open third-party documentation only when safe entry/provenance and observation bounds validate; no browser-state input exists in the model. | Unit | `swift test --filter PublicAuthContractTests` | ❌ Wave 0 |
| FEAS-02 | Exactly one candidate can be selected; native-direct is unavailable until browser is ruled out and evidence is complete. | Unit | `swift test --filter CandidateSelectionTests` | ❌ Wave 0 |
| FEAS-03 | Two independent synthetic success runs plus owner-confirmed cooldown and sign-out are required before a GO artifact is valid. | Unit | `swift test --filter DecisionGateTests` | ❌ Wave 0 |
| FEAS-04 | Every stop condition is terminal, cancels the candidate, clears transient input, and writes no raw evidence. | Unit | `swift test --filter StopConditionTests` | ❌ Wave 0 |
| FEAS-05 | Artifact accepts exactly the three decision strings and rejects an invalid GO/NO-GO proof state; Phase 1 precondition reader rejects NO-GO/incomplete records. | Unit / contract | `swift test --filter ArtifactSchemaTests` | ❌ Wave 0 |

### Sampling Rate

- **Per task commit:** `swift test`
- **Per wave merge:** `swift test`
- **Phase gate:** full synthetic suite green, then human-only two-run protocol; never run live operations from tests or CI. [VERIFIED: .planning/phases/00-authentication-feasibility-gate/00-CONTEXT.md]

### Wave 0 Gaps

- [ ] `Package.swift` — declares isolated executable/core/test targets.
- [ ] `Tests/AuthFeasibilityCoreTests/EvidenceGateTests.swift` — covers FEAS-01.
- [ ] `Tests/AuthFeasibilityCoreTests/CandidateSelectionTests.swift` — covers FEAS-02.
- [ ] `Tests/AuthFeasibilityCoreTests/DecisionGateTests.swift` — covers FEAS-03 and FEAS-05.
- [ ] `Tests/AuthFeasibilityCoreTests/StopConditionTests.swift` — covers FEAS-04.
- [ ] Synthetic fixture resources with no provider values, URLs, secrets, or live account data.

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---|---|---|
| V2 Authentication | Yes | Browser-first empirical selection, owner initiation, typed incomplete/terminal results, and no automatic fallback. [VERIFIED: D-03, D-09 through D-14] |
| V3 Session Management | Yes | Use no persistent session/cookie/credential state in Phase 0; ephemeral session memory is invalidated on stop/sign-out. [CITED: https://developer.apple.com/documentation/foundation/urlsessionconfiguration/ephemeral] |
| V4 Access Control | Yes | Treat CAPTCHA, MFA, subscription/device/geographic/DRM controls, 403/429, and ambiguity as terminal NO-GO; do not confuse documentation or renewal gaps with those terminal classes. [VERIFIED: D-07, D-10, D-14] |
| V5 Input Validation | Yes | Strict decode/validation of a closed public-evidence and artifact schema; reject free text/raw objects. [ASSUMED: implementation mechanism] |
| V6 Cryptography | Yes | Do not implement cryptography or secret storage in Phase 0. [VERIFIED: .planning/phases/00-authentication-feasibility-gate/00-CONTEXT.md] |

### Known Threat Patterns for This Phase

| Pattern | STRIDE | Standard Mitigation |
|---|---|---|
| Cookie/token/browser-profile extraction | Information disclosure / elevation | Never enumerate browser state; accept only material delivered explicitly through the allow-listed app-bound return in memory and discard it after semantic collapse. [VERIFIED: D-13 through D-16] |
| User-agent/device/client spoofing | Spoofing | No custom client identity or fingerprint emulation; honest native candidate only. [VERIFIED: .planning/phases/00-authentication-feasibility-gate/00-CONTEXT.md] |
| Challenge/rate-limit retry | Denial of service / policy evasion | Immediate terminal stop, cancellation, and NO-GO; no retry timer or fallback. [VERIFIED: .planning/phases/00-authentication-feasibility-gate/00-CONTEXT.md] |
| Raw diagnostics or fixtures | Information disclosure | Type-level allow-list boundary; synthetic fixtures only; do not serialize provider transport values. [VERIFIED: .planning/phases/00-authentication-feasibility-gate/00-CONTEXT.md] |
| False GO with partial evidence | Tampering | Artifact validation requires two complete semantic runs, cooldown, cleanup, and a single locked decision. [VERIFIED: .planning/REQUIREMENTS.md] |

## Sources

### Primary

- [ASWebAuthenticationSession](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession) — comparative Apple callback behavior only; D-03 requires WKWebView for this experiment.
- [Authenticating a User Through a Web Service](https://developer.apple.com/documentation/authenticationservices/authenticating-a-user-through-a-web-service) — comparative explanation that a platform API does not invent provider semantics; not a SiriusXM documentation gate.
- [URLSessionConfiguration.ephemeral](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/ephemeral) — no persistent cache, cookie, or credential storage.
- [SwiftPM Target documentation](https://docs.swift.org/swiftpm/documentation/packagedescription/target/) — executable and test target boundaries.

### Secondary

- [SwiftPM creating a package](https://docs.swift.org/swiftpm/documentation/packagemanagerdocs/creatingswiftpackage/) — standard executable package layout and `swift build` / `swift test` workflow.

### Tertiary

- Public official SiriusXM-site search for app authentication/callback documentation — no qualifying result surfaced; treated solely as an unproven discovery gap, not a negative fact. [ASSUMED]

## Metadata

**Confidence breakdown:**

- Standard stack: HIGH — only OS/toolchain components, with the installed Swift compiler and official docs checked.
- Architecture: MEDIUM — safety boundary follows locked project decisions; provider-specific return and entitlement semantics must be established empirically.
- Pitfalls: HIGH — they derive from locked no-bypass, no-secret, one-attempt constraints.

**Research date:** 2026-08-16
**Valid until:** Apple/SwiftPM platform findings: 30 days; SiriusXM contract discovery: revisit immediately before any human-operated attempt.

## Authority Correction — Plan 00-14

This section supersedes only the earlier absolute prohibition on WebKit state. After an owner presses the explicit in-app control following sign-in in this app-owned nonpersistent `WKWebView`, code may select the single current first-party cookie named `AUTH_TOKEN`, decode only `session.accessToken`, retain it in a non-Codable single-consumption object, and send it only to the exact HTTPS native verifier. The correction does not authorize broad cookie/storage enumeration, JavaScript extraction, developer tools, Chrome/shared-browser state, persistence, diagnostics, fixtures, raw artifacts, retries, or any CAPTCHA/MFA/DRM/subscription/device/anti-bot/rate-limit workaround.

`/profile/v4/profiles/me` remains an authentication-only verifier. It cannot establish subscription entitlement. Entitlement is supported only when separately bounded public first-party evidence names an exact HTTPS request and an allow-listed subscription predicate; otherwise the canonical result is `no-public-bounded-entitlement-predicate`. Renewal and playback are historical Phase 0 context, not part of this corrected authentication-and-entitlement closure predicate.
