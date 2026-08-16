# Phase 0: Authentication Feasibility Gate - Research

**Researched:** 2026-08-16  
**Domain:** Safe, human-operated authentication feasibility assessment for a native macOS app  
**Confidence:** MEDIUM — Apple and SwiftPM mechanics are documented; whether SiriusXM exposes a qualifying public return or native contract is deliberately unproven.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- Evaluate a clean first-party, app-bound real-browser return first.
- Browser feasibility requires explicit first-party evidence for a fixed callback/return contract. A visible website sign-in, browser cookie, copied token, or inspectable redirect is not sufficient.
- If browser return is safely ruled out, evaluate one minimal native direct-to-SiriusXM path that identifies itself honestly.
- Do not build, retain, or offer both methods. There is no selector, automatic fallback, or preference-based choice.
- If neither candidate works safely, the decision is `NO-GO unsupported`.
- The account owner—not an agent—initiates every live authentication attempt and operates any real browser or account surface.
- A GO result requires two separate runs through the same sole path.
- Each run must explicitly reach authenticated-and-entitled state and then clean sign-out.
- Only one attempt may be in flight. There is no automatic retry, polling, concurrency, rapid repetition, scheduled execution, or CI integration.
- The account owner chooses and confirms a conservative cooldown between the two runs.
- Stop immediately on CAPTCHA, interstitial challenge, MFA requirement that cannot be completed normally, HTTP 403 or 429, explicit rate limiting, unexpected redirect, suspected bot response, device/geographic/subscription/DRM control, or ambiguous entitlement evidence.
- Do not spoof a browser, user agent, device, client identity, or request fingerprint.
- Do not inspect or export browser cookies, storage, profiles, tokens, authenticated developer-tools data, raw request/response bodies, or account identifiers.
- A stop signal produces `NO-GO unsupported`; it does not trigger another method or workaround.
- Produce exactly one sanitized result: `GO browser-return`, `GO native-direct`, or `NO-GO unsupported`.
- Phase 1 can execute only after a GO result backed by both proof runs. NO-GO ends production implementation rather than degrading into speculative app work.
- Reuse Foundation, SwiftPM, Swift Testing, and OS logging/privacy primitives; add no third-party dependency unless a concrete gap is proven and reviewed.
- Keep POC code isolated from production targets and easy to delete or promote selectively after the decision.
- The harness must expose semantic outcomes and stop conditions, never raw provider data.

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
| FEAS-01 | Determine whether a clean first-party app-bound browser return exists without browser-state inspection. | Public-evidence checklist, Apple callback contract, and fail-closed browser eligibility rule. |
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

Phase 0 should be a disposable, isolated SwiftPM harness that proves its own safety and decision logic with synthetic inputs before any account-owner interaction. The harness must not contain a production client, storage layer, endpoint reverse engineering, browser automation, or a raw-response recorder. Its output is a sanitized feasibility artifact with a closed decision value, not session material or protocol knowledge. [VERIFIED: .planning/phases/00-authentication-feasibility-gate/00-CONTEXT.md]

Apple’s web-authentication API is capable of returning a provider-defined callback to the calling macOS app, but it does not create a provider’s callback contract. A browser route is therefore eligible only when a public first-party SiriusXM source explicitly identifies the authorization URL, callback/return shape, and permitted exchange/verification behavior. Public official-site searches performed for this research did not surface such a contract; that absence is not proof of impossibility and must be represented as unproven rather than reverse engineered from a logged-in browser. [CITED: https://developer.apple.com/documentation/authenticationservices/authenticating-a-user-through-a-web-service] [ASSUMED: public SiriusXM documentation discovery remains incomplete]

**Primary recommendation:** Build the offline safety/decision harness first, then permit one human-operated attempt path only when public evidence makes that path precise; otherwise emit `NO-GO unsupported` without contacting a protected provider surface.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|---|---|---|---|
| Public-provider-evidence review | Maintainer process | Local harness | Evidence is a human review input; the harness validates that it contains a complete, non-secret candidate description. |
| Browser callback attempt | Native macOS client | Human-operated browser | `ASWebAuthenticationSession` can receive a provider-defined callback, while the account owner alone operates the real browser. [CITED: https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession] |
| Native-direct candidate | Native macOS client | Provider boundary | A client-owned ephemeral session is permitted only after browser return is ruled out and a public contract specifies the request honestly. [CITED: https://developer.apple.com/documentation/foundation/urlsessionconfiguration/ephemeral] |
| Stop-condition classification | Local harness | Human owner | The harness records only a closed semantic disposition and immediately terminates the run; the human observes any protected page or service response. |
| Sanitized decision artifact | Local filesystem | Phase 1 planning gate | A small versioned JSON/Markdown result is the only persistent Phase 0 output and contains no secret-bearing data. |

## Standard Stack

### Core

| Library / Tool | Version | Purpose | Why Standard |
|---|---:|---|---|
| Swift + SwiftPM | Swift 6.3.3 installed | Compile a minimal isolated executable and its tests. | SwiftPM supports executable and test targets; keeping tests separate prevents test frameworks from entering a shipped executable. [VERIFIED: `swift --version` returned `Apple Swift version 6.3.3`] [CITED: https://docs.swift.org/swiftpm/documentation/packagedescription/target/] |
| Foundation | OS-bundled | Candidate-local `URLSession`, URL parsing, `Codable`, and cancellation. | `URLSessionConfiguration.ephemeral` keeps caches, cookies, and credential storage out of persistent disk state. [CITED: https://developer.apple.com/documentation/foundation/urlsessionconfiguration/ephemeral] |
| AuthenticationServices | OS-bundled | App-bound browser return only if SiriusXM supplies a documented callback contract. | `ASWebAuthenticationSession` directs a provider-defined callback to the originating app session. [CITED: https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession] |
| Swift Testing | Toolchain-bundled | Synthetic tests for no-retry, terminal stop, artifact schema, and decision selection. | SwiftPM supports test targets; testing-only libraries must terminate at test targets. [CITED: https://docs.swift.org/swiftpm/documentation/packagedescription/target/] |
| OSLog | OS-bundled | Static, allow-listed local diagnostic categories during a live owner-operated run. | Use static event identifiers; do not send callback URL, service error text, headers, or response values to logging. [VERIFIED: .planning/phases/00-authentication-feasibility-gate/00-CONTEXT.md]

### Supporting

| Library / Tool | Purpose | When to Use |
|---|---|---|
| `URLSessionConfiguration.ephemeral` | In-memory-only session configuration. | Only for the single evidence-qualified native-direct candidate; invalidate on cancellation, stop, or sign-out. [CITED: https://developer.apple.com/documentation/foundation/urlsessionconfiguration/ephemeral] |
| `ASWebAuthenticationSession` | Real-browser handoff with a callback. | Only after explicit first-party provider documentation supplies the callback contract; never to inspect cookies or browser state. [CITED: https://developer.apple.com/documentation/authenticationservices/authenticating-a-user-through-a-web-service] |
| `JSONEncoder` / `JSONDecoder` | Versioned sanitized decision artifact. | Use strictly for allow-listed semantic labels and build/run metadata; do not serialize a `URL`, raw error, or provider response. [VERIFIED: .planning/phases/00-authentication-feasibility-gate/00-CONTEXT.md]

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|---|---|---|
| Isolated SwiftPM harness | Production app/SDK target | Rejected: it would couple a provisional feasibility outcome to Phase 1 production architecture. [VERIFIED: .planning/phases/00-authentication-feasibility-gate/00-CONTEXT.md] |
| System browser authentication session | WKWebView/browser automation | Rejected: it turns browser-state access and challenge handling into product behavior, contradicting the native/no-bypass boundary. [VERIFIED: .planning/PROJECT.md] |
| One evidence-selected method | Browser/native selector or fallback | Rejected: it would mask viability evidence and violate the locked single-path decision. [VERIFIED: .planning/phases/00-authentication-feasibility-gate/00-CONTEXT.md] |

**Installation:** No external package installation. [VERIFIED: .planning/phases/00-authentication-feasibility-gate/00-CONTEXT.md]

## Package Legitimacy Audit

No external packages are recommended or installed in Phase 0; the package-legitimacy gate is not applicable. [VERIFIED: .planning/phases/00-authentication-feasibility-gate/00-CONTEXT.md]

## Architecture Patterns

### System Architecture Diagram

```text
public first-party sources ──> maintainer evidence review
                                      │
                               complete / incomplete
                                      │
                                      v
synthetic fixtures ───────> FeasibilityHarness ──> sanitized artifact
                                  │      │                  │
                                  │      └─ incomplete ─> NO-GO unsupported
                                  v
                    one evidence-selected candidate
                       │                         │
       browser-return (first choice)       native-direct (only if browser ruled out)
                       │                         │
                       └──────── human account owner ───────┘
                                           │
                   authenticated + entitled + clean sign-out twice?
                           │ yes                          │ no / stop / ambiguous
                           v                              v
               GO browser-return / native-direct     NO-GO unsupported
                           │                              │
                           └────── Phase 1 execution gate ┘
```

### Recommended Project Structure

```text
Package.swift                             # isolated, non-product feasibility package
Sources/
  AuthFeasibilityCore/                    # pure state machine and artifact schema
  AuthFeasibilityRunner/                  # explicit local command; no scheduled work
  AuthFeasibilityBrowserBridge/           # only if public callback contract qualifies
  AuthFeasibilityNativeCandidate/         # only one evidence-selected direct candidate
Tests/
  AuthFeasibilityCoreTests/               # synthetic sequence and schema tests
  Fixtures/                               # synthetic semantic cases only
Docs/
  AUTHENTICATION-FEASIBILITY.md           # owner runbook and evidence checklist
Artifacts/
  .gitkeep                                # decision artifact created manually, ignored if local
```

The browser bridge and native candidate must be mutually exclusive at build/run configuration, not simply hidden by UI. A `CandidateSelection` load must reject zero or multiple candidates before it can create any session object. [VERIFIED: .planning/phases/00-authentication-feasibility-gate/00-CONTEXT.md]

### Pattern 1: Evidence first, attempt second

**What:** Model the provider contract as a local, hand-reviewed `EvidenceRecord` that has only public reference URLs, an exact candidate kind, a fixed callback matcher or a documented direct-operation name, and an explicit reviewer acknowledgement. It must not accept cookies, copied URL strings, auth tokens, headers, client fingerprints, or request bodies. [VERIFIED: .planning/phases/00-authentication-feasibility-gate/00-CONTEXT.md]

**When to use:** Before enabling either candidate. An incomplete record produces `NO-GO unsupported` before any live call. [ASSUMED: exact local type naming]

**Required browser evidence:** The first-party source must define the provider’s authorization entry, callback matching rule, result semantics, and permitted post-callback action. Apple explicitly tells apps to use the URL and callback scheme specified by the authorization provider. [CITED: https://developer.apple.com/documentation/authenticationservices/authenticating-a-user-through-a-web-service]

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
| Browser automation | WebView scraper, cookie exporter, DevTools parser, browser-profile reader | `ASWebAuthenticationSession` only when the provider documents an app callback; otherwise no browser integration | Apple’s API delivers a provider-defined callback without app access to browser state. [CITED: https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession] |
| Persistent credential/cookie handling | Cookie jar, local token file, Keychain behavior | No persistent credentials in Phase 0; ephemeral session memory only where native-direct evidence qualifies | The phase is a disposable feasibility gate and its locked data boundary forbids retaining secrets. [VERIFIED: .planning/phases/00-authentication-feasibility-gate/00-CONTEXT.md] |
| Native HTTP stack | Socket/client-fingerprint emulation | Foundation `URLSession` with an ephemeral configuration | It offers OS-managed TLS and avoids persistent cache/cookie/credential stores. [CITED: https://developer.apple.com/documentation/foundation/urlsessionconfiguration/ephemeral] |
| Retry/cooldown automation | Retry engine, scheduler, polling loop | Human-confirmed pause between separately initiated runs | The user’s single-attempt and human-controlled-cooldown requirement is a safety control, not a performance issue. [VERIFIED: .planning/phases/00-authentication-feasibility-gate/00-CONTEXT.md] |
| Raw evidence recorder | HAR, request/response archive, screenshot bundle | Closed semantic event vocabulary and synthetic fixtures | Raw capture conflicts with the no-secret/no-browser-state boundary. [VERIFIED: .planning/phases/00-authentication-feasibility-gate/00-CONTEXT.md] |

**Key insight:** The feasibility harness validates decisions, not provider protocol. An unknown provider fact is a reason to stop, never a reason to instrument more deeply. [VERIFIED: .planning/phases/00-authentication-feasibility-gate/00-CONTEXT.md]

## Common Pitfalls

### Pitfall 1: Confusing API capability with provider eligibility

**What goes wrong:** A developer sees that macOS supports `ASWebAuthenticationSession` and assumes a SiriusXM browser login can return to the app.

**Why it happens:** Apple’s API takes a callback rule, but the authorization provider defines the URL and callback scheme. [CITED: https://developer.apple.com/documentation/authenticationservices/authenticating-a-user-through-a-web-service]

**How to avoid:** Require public first-party provider evidence before constructing a browser candidate. If it is absent or ambiguous, do not harvest a redirect or inspect the browser; record the browser route as unproven. [VERIFIED: .planning/phases/00-authentication-feasibility-gate/00-CONTEXT.md]

**Warning signs:** The proposed solution needs a custom web view, browser console, copied address-bar token, cookie, or user-agent override.

### Pitfall 2: Native-direct speculation

**What goes wrong:** The project begins guessing endpoints, headers, request sequences, or app identity after browser evidence is absent.

**Why it happens:** An unsupported integration looks technically close to a normal HTTP client.

**How to avoid:** Native-direct is eligible only from a documented public contract and only after browser return is safely ruled out. Unknown request details produce NO-GO, not a reverse-engineering exercise in this phase. [VERIFIED: .planning/phases/00-authentication-feasibility-gate/00-CONTEXT.md]

**Warning signs:** More than one candidate, request replay, spoofed identifiers, a proxy, or “try again with a different header.”

### Pitfall 3: Letting a harmless log become an evidence leak

**What goes wrong:** A callback URL, service error, response status context, or `Error` description lands in a console, test failure, or artifact.

**Why it happens:** Raw Foundation values are convenient to print during an early proof of concept.

**How to avoid:** Make the diagnostic and artifact APIs accept only closed enums/static strings; test that raw networking and callback types cannot be passed to them. [VERIFIED: .planning/phases/00-authentication-feasibility-gate/00-CONTEXT.md]

**Warning signs:** `print`, `debugPrint`, `localizedDescription`, `absoluteString`, JSON snapshots from a live run, or a source-controlled output directory.

### Pitfall 4: Treating login as entitlement proof

**What goes wrong:** A technically completed authentication operation becomes GO without explicit authorized-and-entitled evidence and clean sign-out.

**Why it happens:** Authentication, subscription entitlement, and session cleanup are distinct states.

**How to avoid:** A GO writer requires two completed runs with all three semantic confirmations: authenticated, entitled, and signed out. Any absence, mismatch, or ambiguity is terminal NO-GO. [VERIFIED: .planning/REQUIREMENTS.md]

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

This pattern is valid only after the native-direct path has passed the public-evidence gate. It does not authorize a request, select a user agent, read browser data, or change the one-attempt rule. [CITED: https://developer.apple.com/documentation/foundation/urlsessionconfiguration/ephemeral]

### Provider-defined browser callback boundary

```swift
// Source: https://developer.apple.com/documentation/authenticationservices/authenticating-a-user-through-a-web-service
let session = ASWebAuthenticationSession(
    url: providerAuthorizationURL,
    callbackURLScheme: providerCallbackScheme
) { _, _ in
    // Convert to an allow-listed semantic outcome; never log the callback URL.
}
```

`providerAuthorizationURL` and `providerCallbackScheme` are placeholders sourced only from explicit first-party provider documentation. They are not values to discover from a login page, an authenticated browser, or network inspection. [CITED: https://developer.apple.com/documentation/authenticationservices/authenticating-a-user-through-a-web-service] [VERIFIED: .planning/phases/00-authentication-feasibility-gate/00-CONTEXT.md]

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|---|---|---|---|
| Callback URL-scheme initializer only | `ASWebAuthenticationSession` also exposes callback matching APIs; the older scheme initializer is documented as deprecated. | Current Apple documentation | Implement only a provider-defined fixed callback matcher/contract; do not infer callback details from the platform API. [CITED: https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession] |
| Persistent/default URLSession for a proof | Ephemeral URLSession configuration | Current Apple documentation | Candidate-native traffic has no persistent cache/cookie/credential storage, and cleanup invalidates its memory state. [CITED: https://developer.apple.com/documentation/foundation/urlsessionconfiguration/ephemeral] |

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|---|---|---|
| A1 | Public official-site searches did not surface a SiriusXM app callback or native-direct authentication contract. | Summary | Do not treat this as a definitive absence; browser/native eligibility remains unproven until a first-party source is provided. |
| A2 | The suggested target names, schema field names, and actor type names are suitable. | Architecture Patterns | Low: names can change without changing the safety contract. |
| A3 | A local explicit non-CI executable configuration can be enforced as a guardrail. | Common Pitfalls | Medium: planner must specify the exact build/run guard and test it. |

## Open Questions

1. **Does SiriusXM publicly document a fixed, app-bound browser callback contract?**
   - What we know: Apple supports such a callback model, but it requires provider-specified authorization and callback details. [CITED: https://developer.apple.com/documentation/authenticationservices/authenticating-a-user-through-a-web-service]
   - What’s unclear: No qualifying first-party SiriusXM developer document was found in this public-only research pass. [ASSUMED]
   - Recommendation: Require a public first-party URL that specifies all callback/verification behavior; otherwise close the browser branch as unproven.

2. **Does SiriusXM publicly document an honest native-direct application auth contract?**
   - What we know: Foundation can use an ephemeral request session without persistent state. [CITED: https://developer.apple.com/documentation/foundation/urlsessionconfiguration/ephemeral]
   - What’s unclear: The provider’s supported direct contract and service-protection expectations are unknown. [ASSUMED]
   - Recommendation: Do not invent or probe a contract. If none is public after browser is ruled out, record NO-GO.

3. **What semantic signal will qualify as explicit entitlement?**
   - What we know: Phase 0 requires explicit authenticated-and-entitled state, but refuses raw provider data. [VERIFIED: .planning/REQUIREMENTS.md]
   - What’s unclear: Provider-specific semantic mapping cannot be known before an evidence-qualified candidate exists. [ASSUMED]
   - Recommendation: Define the semantic mapping in the evidence record before the first owner-run; ambiguity is terminal.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|---|---|---:|---|---|
| Swift compiler / SwiftPM | Harness and synthetic tests | ✓ | Swift 6.3.3 | — [VERIFIED: `swift --version`] |
| Xcode IDE / `xcodebuild` | Optional native browser bridge build | ✗ | Command Line Tools only | SwiftPM command-line core first; install/enable Xcode only if an evidence-qualified browser bridge needs it. [VERIFIED: `xcodebuild -version` produced no version; `xcrun --find swift` returned CommandLineTools path] |
| AuthenticationServices framework | Browser candidate | Unknown until full Xcode SDK availability | — | Keep browser candidate as a planned conditional module; no live run occurs until the required Apple SDK/tooling is confirmed. [ASSUMED] |
| Public first-party provider contract | Any live candidate | ✗ / unproven | — | NO-GO unsupported; do not substitute browser inspection or endpoint guessing. [ASSUMED] |

**Missing dependencies with no fallback:** An explicit public SiriusXM contract is necessary for any GO attempt; lack of one is an intentional NO-GO outcome, not an installation task. [VERIFIED: .planning/phases/00-authentication-feasibility-gate/00-CONTEXT.md]

**Missing dependencies with fallback:** Full Xcode is not needed for the pure SwiftPM state machine and tests; it becomes necessary only for the conditional Apple browser bridge. [ASSUMED]

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
| FEAS-01 | Browser candidate cannot be enabled without complete public evidence; no browser-state input exists in the model. | Unit | `swift test --filter EvidenceGateTests` | ❌ Wave 0 |
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
| V2 Authentication | Yes | One evidence-selected path, owner initiation, typed terminal results, and no fallback. [VERIFIED: .planning/phases/00-authentication-feasibility-gate/00-CONTEXT.md] |
| V3 Session Management | Yes | Use no persistent session/cookie/credential state in Phase 0; ephemeral session memory is invalidated on stop/sign-out. [CITED: https://developer.apple.com/documentation/foundation/urlsessionconfiguration/ephemeral] |
| V4 Access Control | Yes | Treat CAPTCHA, MFA, subscription/device/geographic/DRM controls, 403/429, and ambiguity as terminal NO-GO. [VERIFIED: .planning/phases/00-authentication-feasibility-gate/00-CONTEXT.md] |
| V5 Input Validation | Yes | Strict decode/validation of a closed public-evidence and artifact schema; reject free text/raw objects. [ASSUMED: implementation mechanism] |
| V6 Cryptography | Yes | Do not implement cryptography or secret storage in Phase 0. [VERIFIED: .planning/phases/00-authentication-feasibility-gate/00-CONTEXT.md] |

### Known Threat Patterns for This Phase

| Pattern | STRIDE | Standard Mitigation |
|---|---|---|
| Cookie/token/browser-profile extraction | Information disclosure / elevation | Never read browser state; accept only provider-defined callback behavior and discard raw callback values. [VERIFIED: .planning/phases/00-authentication-feasibility-gate/00-CONTEXT.md] |
| User-agent/device/client spoofing | Spoofing | No custom client identity or fingerprint emulation; honest native candidate only. [VERIFIED: .planning/phases/00-authentication-feasibility-gate/00-CONTEXT.md] |
| Challenge/rate-limit retry | Denial of service / policy evasion | Immediate terminal stop, cancellation, and NO-GO; no retry timer or fallback. [VERIFIED: .planning/phases/00-authentication-feasibility-gate/00-CONTEXT.md] |
| Raw diagnostics or fixtures | Information disclosure | Type-level allow-list boundary; synthetic fixtures only; do not serialize provider transport values. [VERIFIED: .planning/phases/00-authentication-feasibility-gate/00-CONTEXT.md] |
| False GO with partial evidence | Tampering | Artifact validation requires two complete semantic runs, cooldown, cleanup, and a single locked decision. [VERIFIED: .planning/REQUIREMENTS.md] |

## Sources

### Primary

- [ASWebAuthenticationSession](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession) — macOS browser launch and app-bound callback behavior.
- [Authenticating a User Through a Web Service](https://developer.apple.com/documentation/authenticationservices/authenticating-a-user-through-a-web-service) — provider-defined authorization URL/callback contract, cancellation, and optional ephemeral browser session.
- [URLSessionConfiguration.ephemeral](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/ephemeral) — no persistent cache, cookie, or credential storage.
- [SwiftPM Target documentation](https://docs.swift.org/swiftpm/documentation/packagedescription/target/) — executable and test target boundaries.

### Secondary

- [SwiftPM creating a package](https://docs.swift.org/swiftpm/documentation/packagemanagerdocs/creatingswiftpackage/) — standard executable package layout and `swift build` / `swift test` workflow.

### Tertiary

- Public official SiriusXM-site search for app authentication/callback documentation — no qualifying result surfaced; treated solely as an unproven discovery gap, not a negative fact. [ASSUMED]

## Metadata

**Confidence breakdown:**

- Standard stack: HIGH — only OS/toolchain components, with the installed Swift compiler and official docs checked.
- Architecture: MEDIUM — safety boundary follows locked project decisions and documented Apple behavior; provider-specific contract is unproven.
- Pitfalls: HIGH — they derive from locked no-bypass, no-secret, one-attempt constraints.

**Research date:** 2026-08-16  
**Valid until:** Apple/SwiftPM platform findings: 30 days; SiriusXM contract discovery: revisit immediately before any human-operated attempt.
