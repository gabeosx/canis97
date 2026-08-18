---
phase: 01-safe-interoperability-foundation
verified: 2026-08-18T15:03:46Z
status: gaps_found
score: 6/7 must-haves verified
behavior_unverified: 0
overrides_applied: 0
re_verification:
  previous_status: gaps_found
  previous_score: 6/7
  gaps_closed:
    - "Overlapping explicit WebView selections now reserve before cookie-store suspension and deliver exactly one credential."
  gaps_remaining:
    - "The production native-response adapter accepts success only from one-field synthetic JSON objects, leaving no usable real profile or entitlement success contract."
  regressions: []
gaps:
  - truth: "A subscriber can establish an authorized session through the native WebView-token and native-verification sequence."
    status: failed
    reason: "The production adapter rejects every JSON object with more than one top-level field and recognizes success only from the synthetic keys authenticated/entitled. The actual request endpoints have no versioned success-response decoder or representative redacted fixtures, so a normal profile or entitlement payload cannot produce active state."
    artifacts:
      - path: "Packages/SiriusXMClient/Sources/SiriusXMClient/InternalAdapters/AuthenticationFlowAdapter.swift"
        issue: "exactJSONObject requires dictionary.count == 1 before success classification."
      - path: "Packages/SiriusXMClient/Tests/SiriusXMClientTests/AuthenticationOutcomeTests.swift"
        issue: "All success cases use one-field synthetic payloads; there is no representative multi-field/unknown-field contract test."
    missing:
      - "Implement a versioned internal decoder for the settled profile and subscription success evidence that tolerates unrelated fields while retaining fail-closed control detection."
      - "Add sanitized, representative multi-field fixtures and native transaction tests proving an authorized session reaches entitlement and active state."
---

# Phase 1: Safe Interoperability Foundation Verification Report

**Phase Goal:** As a SiriusXM subscriber, I want to establish or end an authorized session, so that I can listen safely on my Mac.
**Verified:** 2026-08-18T15:03:46Z
**Status:** gaps_found
**Re-verification:** Yes — after gap closure

## User Flow Coverage

| Step | Expected | Evidence in codebase | Status |
| --- | --- | --- | --- |
| Open Sirius Mac | The native authentication surface is the root app scene. | `SiriusMacApp` renders `AuthenticationView`; its initializer composes one bridge, client, Keychain store, and residue cleaner. | ✓ VERIFIED |
| Start sign-in | A user action loads an app-owned nonpersistent WebView. | `AuthenticationPresentationModel.signIn()` reaches `WebAuthenticationBridge.beginUserOperatedSignIn()`; its configuration uses `.nonPersistent()`. | ✓ VERIFIED |
| Confirm the logged-in session | One current first-party token is selected once and transferred only in volatile memory. | Available/selecting/consumed state is set before its awaits; the controlled-suspension XCTest passed with one cookie read and one consumer invocation. | ✓ VERIFIED |
| Verify authorization | Native authentication and entitlement can turn a valid direct provider response into active state. | `SessionCoordinator` sequences both verifiers, but `AuthenticationFlowAdapter.exactJSONObject` rejects any response with more than one key; its only success fixtures are one-field synthetics. | ✗ FAILED |
| End or clear the session | Memory is retired, then Keychain material and exact matching WebView cookies are cleared or failures are exposed. | `clearLocalSession()` reaches `SessionCoordinator.signOut()`; it invokes both injected cleaners after state retirement and reports aggregate failure. | ✓ VERIFIED |
| Outcome | A subscriber can reach a safely authorized session. | The bridge race is closed, but the native response contract cannot establish the active state from a real multi-field response. | ✗ BLOCKED |

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
| --- | --- | --- | --- |
| 1 | A subscriber can sign in through the app's nonpersistent WKWebView; after explicit confirmation, the app extracts exactly one current first-party `AUTH_TOKEN`, decodes only `session.accessToken`, and transfers it once in volatile memory to the client. | ✓ VERIFIED | `WebAuthenticationBridge` reserves `.selecting` before `await cookieStore.allCookies()`, commits `.consumed` before delivery, and the named concurrent-selection XCTest passed. |
| 2 | Unknown, changed, or prohibited-control flows produce an explicit unsupported/challenge result and stop without a bypass. | ✓ VERIFIED | Preflight rejects redirects/non-JSON/unknown statuses; classifier maps 403/429/control signals to terminal semantic states; no fallback adapter, JavaScript extraction, or shared session path found. |
| 3 | Only a runtime-owned native sequence verifies the token, confirms entitlement, and atomically activates session state; caller-authored success claims and planning artifacts cannot create an authenticated session. | ✓ VERIFIED | `SessionCoordinator` alone sets `.active`, after both internal classifications; the named ordered-transaction test passed, and no production `.planning` or caller-claim path exists. |
| 4 | Sign-out clears actor-held session material, Keychain material, and every cookie matching the exact extraction predicate, or reports cleanup failure explicitly. | ✓ VERIFIED | `signOut()` retires actor state before awaiting both injected cleaners; bridge cleanup deletes predicate matches and rescans; focused cleanup regressions are substantive. |
| 5 | Credentials are Keychain-backed; session/stream material is ephemeral and direct-only; diagnostics, fixtures, tests, and local app data exclude secrets and raw sensitive responses. | ✓ VERIFIED | The app uses direct `SecItem` CRUD; transport is client-owned ephemeral with nil cookie/credential stores; public credential rendering is redacted and fixture promotion rejects sensitive structure. |
| 6 | An Apple-platform developer can consume the SwiftPM `SiriusXMClient` product and typed async capabilities without SiriusXM endpoints, cookies, headers, or raw schemas. | ✓ VERIFIED | `Package.swift` exposes the library product; the independent-consumer test imports it and uses only semantic public models/capabilities. |
| 7 | Deterministic WebView-bridge, native-authentication, entitlement, sign-out, and redaction tests compile and run independently of mutable `.planning` artifacts. | ✓ VERIFIED | Xcode project includes the active `SiriusMacTests` sources unconditionally; source scan found no production planning-artifact build condition; focused bridge test and one package test passed. |

**Score:** 6/7 truths verified (0 present, behavior-unverified)

### Required Artifacts

| Artifact | Expected | Status | Details |
| --- | --- | --- | --- |
| `SiriusMac.xcodeproj/project.pbxproj`, `Package.swift`, public-consumer test | Native app plus independently consumable library product | ✓ VERIFIED | All Plan 01-01 artifacts are substantive; the project has one active `SiriusMacTests` target and the package exposes the library product. |
| `SessionCoordinator.swift`, coordinator tests | Runtime-owned authentication → entitlement → atomic session state | ✓ VERIFIED | State transition and injected collaborator wiring are substantive; named ordered-transaction test passed. |
| `WebAuthenticationBridge.swift`, bridge tests | Nonpersistent, single-consumption WebView handoff | ✓ VERIFIED | Three-level inspection and the controlled concurrency regression prove the previous handoff race is closed. |
| `AuthenticationFlowAdapter.swift`, outcome tests | Internal response compatibility adapter | ✗ STUB FOR PRODUCTION SUCCESS | The implementation is wired to real transport but only understands one-field synthetic success objects; tests encode the same limitation. |
| `KeychainCredentialStore.swift`, `SignOutTests.swift` | Keychain-backed, memory-first aggregate cleanup | ✓ VERIFIED | Direct Security.framework CRUD is used and both cleanup seams are injected and awaited. |
| `AuthenticationView.swift`, presentation model, composition tests | Native semantic user flow | ⚠️ HOLLOW AT AUTHORIZATION STEP | View → bridge → client wiring is real, but active UI cannot be reached from a multi-field native response because the adapter fails closed. |

### Key Link Verification

| From | To | Via | Status | Details |
| --- | --- | --- | --- | --- |
| `SiriusMacApp` | `AuthenticationView` | root `WindowGroup` | ✓ WIRED | The app root instantiates the native authentication view. |
| `AuthenticationView` | bridge + `SiriusXMClient` | composition initializer | ✓ WIRED | One bridge is supplied as both credential source and residue cleaner; the Keychain store is app-owned. |
| bridge | `WebAuthenticationCookieStore` + `credentialConsumer` | reserved selection lifecycle | ✓ WIRED | Source orders `.selecting` before the cookie await and `.consumed` before the consumer await; targeted test passed. |
| `SessionCoordinator` | `AuthenticationFlowAdapter` | raw transport responses → ordered classifiers | ⚠️ PARTIAL | The calls at lines 100 and 116 are present, but their adapter cannot classify a realistic multi-field success response. |
| client | direct transport | `NativeRequestVerifier` + `EphemeralURLSessionTransport` | ✓ WIRED | The production initializer owns this path and request construction is restricted to exact HTTPS contracts. |
| explicit cleanup UI | client coordinator cleaners | view → model → flow → `signOut()` | ✓ WIRED | Fresh-state Clear Local Session invokes both cleaners through the composed client. |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
| --- | --- | --- | --- | --- |
| `AuthenticationView` | `model.state` | composed bridge/client flow | No at authorization success | ⚠️ HOLLOW |
| `WebAuthenticationBridge` | opaque `AuthenticationCredential` | one current matching WebView cookie | Yes, in memory only | ✓ FLOWING |
| `SessionCoordinator` | `state` / `lastEntitlement` | direct native transport through response adapter | No usable success interpretation for multi-field responses | ✗ DISCONNECTED |
| cleanup flow | signed-out/cleanup-failed presentation state | Keychain and browser-residue cleaner outcomes | Yes | ✓ FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
| --- | --- | --- | --- |
| One transfer during concurrent WebView selection | `xcodebuild ... -only-testing:SiriusMacTests/WebAuthenticationBridgeTests/testConcurrentSelectionsReserveOneCookieReadAndOneCredentialTransfer test` | 1 XCTest passed. | ✓ PASS |
| Runtime authentication → entitlement ordering | `swift test --package-path Packages/SiriusXMClient --filter 'SiriusXMClientTests.SessionCoordinatorTests/performsAuthenticationThenEntitlementOnce'` | 1 Swift Testing test passed. | ✓ PASS |
| A real/profile-shaped response can activate a session | Static trace plus adapter-coverage audit | `exactJSONObject` requires `dictionary.count == 1`; all success tests use a one-field synthetic object. | ✗ FAIL |

### Requirements Coverage

| Requirement | Source Plan(s) | Description | Status | Evidence |
| --- | --- | --- | --- | --- |
| AUTH-01 | 01-02, 01-05–09, 01-12 | Direct sign-in with explicit outcomes | ✗ BLOCKED | Native success decoding is restricted to one-field synthetic payloads, preventing the required authorized session. |
| AUTH-02 | 01-02, 01-03, 01-05–08 | Unknown/changed flow fails closed without bypass | ✓ SATISFIED | Strict preflight/classification returns terminal semantic results and no bypass path exists. |
| AUTH-03 | 01-04, 01-06–08, 01-10 | Sign-out clears active and stored material | ✓ SATISFIED | Memory-first aggregate cleanup and exact-cookie rescan are wired and tested. |
| SECR-01 | 01-04, 01-07, 01-10 | Credentials use a Keychain-backed app adapter only | ✓ SATISFIED | Direct `SecItem` store; scans found no preferences, SwiftData, file, or fallback secret store. |
| SECR-02 | 01-02–04, 01-06–10, 01-12 | Tokens/resources are ephemeral and direct-only | ✓ SATISFIED | Volatile opaque handoff, one-consumption lifecycle, and client-owned exact-host ephemeral transport. |
| SECR-03 | 01-03, 01-05–08 | Diagnostics and fixtures exclude sensitive material | ✓ SATISFIED | Closed diagnostic events and redaction fixture tests provide no raw secret sink. |
| CLNT-01 | 01-01, 01-05, 01-07–08 | Independently consumable SwiftPM product | ✓ SATISFIED | Public consumer target imports and exercises `SiriusXMClient` without the app target. |
| CLNT-02 | 01-01–02, 01-07–08 | Typed public async domain API | ✓ SATISFIED | Public models/capabilities are semantic and opaque; wire details remain absent. |
| CLNT-03 | 01-02–03, 01-07–08 | Wire details stay in internal replaceable adapters | ✓ SATISFIED | Endpoint/headers/transport response types are internal; public types expose no raw schema. |
| CLNT-04 | 01-01–12 | Injectable collaborators for deterministic tests/app-owned secrets | ✓ SATISFIED | Internal coordinator/bridge seams accept injected credential, verifier, clock, diagnostic, cookie-store, and cleanup collaborators. |

No Phase 1 requirement is orphaned: every Phase 1 ID in `REQUIREMENTS.md` is claimed by one or more plan frontmatters and assessed above.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
| --- | --- | --- | --- | --- |
| `AuthenticationFlowAdapter.swift` | 87–92, 115–120, 135–142 | Production success requires a JSON dictionary with exactly one field and synthetic `authenticated`/`entitled` keys. | 🛑 BLOCKER | The direct profile/subscription path cannot establish an active session from a representative real response. |
| `AuthenticationOutcomeTests.swift` | 7–20, 23–43 | Success tests use only the same one-field synthetic shape; the multi-field case is deliberately treated as terminal. | 🛑 BLOCKER | Passing suite does not test the subscriber-success behavior claimed by AUTH-01. |
| `SiriusMac.xcodeproj/project.pbxproj` | 76–79 | Release signing is disabled. | ℹ️ DEFERRED | This is a release-distribution concern explicitly covered by Phase 5, not a Phase 1 success criterion. |

No unreferenced `TBD`, `FIXME`, or `XXX` markers were found in Phase 1 Swift sources. Static scans also found no shared URL session/cookie store, JavaScript injection, production `.planning` dependency, or alternate secret store.

### Gaps Summary

The prior WebView concurrency blocker is closed and has a passing controlled-interleaving regression. Phase 1 nevertheless does not achieve its user-story outcome: its live native transport requests the real profile and subscription endpoints, while its downstream adapter accepts success only from a test-only one-key JSON body. This is not a missing live probe; it is a visible implementation contract mismatch. The escalation decision is to define the settled, sanitized response evidence and implement a versioned internal adapter with fixture coverage, while preserving fail-closed handling for changed/control responses.

The review's signing observation is deliberately not counted as a Phase 1 gap because the roadmap assigns signed/notarized public releases to Phase 5. Its response-adapter finding was independently reproduced above and is the blocking Phase 1 gap.

---

_Verified: 2026-08-18T15:03:46Z_
_Verifier: the agent (gsd-verifier)_
