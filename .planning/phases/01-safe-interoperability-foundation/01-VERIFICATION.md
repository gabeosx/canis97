---
phase: 01-safe-interoperability-foundation
verified: 2026-08-18T13:54:11Z
status: gaps_found
score: 6/7 must-haves verified
behavior_unverified: 0
overrides_applied: 0
re_verification:
  previous_status: gaps_found
  previous_score: 5/7
  gaps_closed:
    - "Phase 1's MVP goal is now a valid user story."
    - "An explicit retry or new login re-arms the same WebView handoff after a terminal result or sign-out."
    - "A fresh composition can explicitly remove Keychain material and matching browser residue."
    - "The detached duplicate Xcode test graph has been removed."
  gaps_remaining:
    - "Concurrent explicit WebView selections can each transfer a credential within one attempt."
  regressions: []
gaps:
  - truth: "After explicit confirmation, each native WebView attempt transfers exactly one current first-party credential in volatile memory to the client."
    status: failed
    reason: "WebAuthenticationBridge checks didTransferCredential before awaiting the cookie store, then marks it consumed only after the await. A second main-actor task can pass the same false latch while the first cookie read is suspended, so both can invoke credentialConsumer and overwrite the handoff."
    artifacts:
      - path: "SiriusMac/Authentication/WebAuthenticationBridge.swift"
        issue: "Lines 84-88 reserve no selecting state before await cookieStore.allCookies(); lines 115-117 consume too late."
      - path: "SiriusMacTests/WebAuthenticationBridgeTests.swift"
        issue: "Covers sequential double selection only; no controlled-suspension concurrent-selection regression exists."
    missing:
      - "Reserve an in-progress handoff state before the first suspension, reset it only for non-transfer outcomes, and retain consumed after a successful transfer."
      - "Add a controlled-suspension cookie-store regression that concurrently starts two selections and proves exactly one credential-consumer invocation."
---

# Phase 1: Safe Interoperability Foundation Verification Report

**Phase Goal:** As a SiriusXM subscriber, I want to establish or end an authorized session, so that I can listen safely on my Mac.
**Verified:** 2026-08-18T13:54:11Z
**Status:** gaps_found
**Re-verification:** Yes — after gap closure

## User Flow Coverage

| Step | Expected | Evidence in codebase | Status |
| --- | --- | --- | --- |
| Open Sirius Mac | Native authentication surface is the only root scene. | `SiriusMacApp` renders `AuthenticationView`; focused macOS XCTest compiles and runs the app target. | ✓ VERIFIED |
| Start sign-in | An explicit Sign In action loads the app-owned nonpersistent WebView. | `AuthenticationPresentationModel.signIn()` → composed flow → `WebAuthenticationBridge.beginUserOperatedSignIn()`; bridge config uses `.nonPersistent()`. | ✓ VERIFIED |
| Confirm the logged-in session | One current first-party token is selected, decoded minimally, and handed to the client once for this attempt. | Predicate and sequential tests are present, but the bridge does not reserve its latch before awaiting the cookie store. | ✗ FAILED |
| Verify authorization | Authentication then entitlement determine active state; a caller cannot assert success. | `SessionCoordinator` calls the two internal classifiers in order and assigns `.active` only after entitlement; 29-package-test run passed. | ✓ VERIFIED |
| End/clear the session | Memory is retired, then Keychain and matching WebView residue are cleared or failure is exposed. | `clearLocalSession()` reaches `SessionCoordinator.signOut()`; fresh-composition XCTest exercises removal. | ✓ VERIFIED |
| Outcome | The app reaches a safe, entitled-ready state only through the native verification path. | Semantic entitled state is rendered only after the above sequence; live playback itself is deliberately Phase 2 scope. | ✗ BLOCKED by credential-cardinality failure |

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
| --- | --- | --- | --- |
| 1 | A subscriber can sign in through the nonpersistent WebView, extract exactly one current first-party token after explicit confirmation, and transfer it once in volatile memory. | ✗ FAILED | `WebAuthenticationBridge.useLoggedInSession()` checks `didTransferCredential` at line 84, suspends at line 87, and sets it only at line 116. Concurrent explicit calls can both transfer. |
| 2 | Unknown, changed, or prohibited-control flows return explicit unsupported/challenge results and stop without a bypass. | ✓ VERIFIED | Strict response preflight/classification in `AuthenticationFlowAdapter`; no fallback or shared-browser path found; package classification tests passed. |
| 3 | Only native authentication plus entitlement atomically create active state; claims/planning artifacts cannot. | ✓ VERIFIED | `SessionCoordinator` verifies authentication then entitlement and assigns active state only at lines 129-131; transaction tests passed. |
| 4 | Sign-out clears actor state, Keychain material, and exact matching browser cookies, or reports cleanup failure. | ✓ VERIFIED | `SessionCoordinator.signOut()` retires state before both injected cleaners; focused XCTest covers fresh cleanup and package tests cover coalescing/failure. |
| 5 | Persistent credentials are Keychain-backed; session material is ephemeral/direct-only; diagnostics and fixtures exclude secrets. | ✓ VERIFIED | Direct `SecItem` adapter, ephemeral URL session/exact host policy, closed diagnostics, and redaction tests all passed. |
| 6 | Independent Apple-platform consumers use the SwiftPM product's typed API without wire details. | ✓ VERIFIED | Public consumer package test passed; `Package.swift` exposes only the `SiriusXMClient` library product and public models are semantic. |
| 7 | WebView, native-authentication, entitlement, sign-out, and redaction tests compile independently of `.planning`. | ✓ VERIFIED | Full SwiftPM suite passed 29 tests; focused macOS suite passed 14 tests; static scan found no production planning-artifact build condition. |

**Score:** 6/7 truths verified (0 present, behavior-unverified)

### Must-Have Audit by Plan

| Plan | Actual implementation check | Verdict |
| --- | --- | --- |
| 01-01 | Native app, local SwiftPM product, semantic public boundary, unavailable content capabilities, and no Phase 0 runtime dependency are present. | ✓ VERIFIED |
| 01-02 | Actor-owned authentication → entitlement sequencing, atomic state, and terminal clearing are implemented and package-tested. | ✓ VERIFIED |
| 01-03 | Exact direct-host ephemeral transport and closed diagnostic/redaction boundaries are substantive and tested. | ✓ VERIFIED |
| 01-04 | Keychain-only storage and memory-first aggregate sign-out are wired through injected cleaners. | ✓ VERIFIED |
| 01-05 | One semantic WebView/native presentation path, fixed safe states, and explicit actions are wired. | ✓ VERIFIED |
| 01-06 | Nonpersistent WebView, shared predicate, minimal decode, and cleanup rescan are implemented; per-attempt concurrent selection is not safe. | ✗ FAILED |
| 01-07 | Bridge/client composition and native authentication then entitlement wiring are present and exercised synthetically. | ✓ VERIFIED |
| 01-08 | Phase 0 review regressions are represented by current synthetic tests and no active Phase 0 authority was found. | ✓ VERIFIED |
| 01-09 | Explicit re-arm/re-login works sequentially, but the promised one-transfer-per-attempt invariant fails under concurrent selection. | ✗ FAILED |
| 01-10 | Fresh-composition cleanup is explicit, coalesced, memory-first, and tested. | ✓ VERIFIED |
| 01-11 | The E4/E1 project graph is parseable, singular, and contains the canonical four test sources. | ✓ VERIFIED |

### Required Artifacts

| Plans | Artifact(s) | Status | Details |
| --- | --- | --- | --- |
| 01-01 | Xcode project, `Package.swift`, public-consumer test | ✓ VERIFIED | All exist, are substantive, and package/product linkage is active. |
| 01-02 | `SessionCoordinator.swift`, coordinator tests | ✓ VERIFIED | State machine is implemented and calls strict internal classifiers. |
| 01-03 | request contract, redaction tests | ✓ VERIFIED | Direct request contract and canary-exclusion coverage are substantive. |
| 01-04 | Keychain store, sign-out tests | ✓ VERIFIED | App-owned `SecItem` CRUD and cleanup ordering are real code, not stubs. |
| 01-05 | presentation model, authentication view | ✓ VERIFIED | Root view uses model state and semantic flow rather than static placeholder data. |
| 01-06/09 | token policy, bridge, bridge/composition tests | ✗ FAILED | Artifacts are wired, but `useLoggedInSession()` has an async latch race and tests omit the critical interleaving. |
| 01-07 | transaction and composition tests | ✓ VERIFIED | Client sequence and app composition are executable native test members. |
| 01-08 | acceptance summary | ✓ VERIFIED | Required synthetic-acceptance fields exist; it is not used as runtime authority. |
| 01-10 | coordinator, cleanup view, package/app lifecycle tests | ✓ VERIFIED | Fresh cleanup action reaches both production cleanup seams. |
| 01-11 | `project.pbxproj` | ✓ VERIFIED | `plutil`/`jq` assertions and target listing confirm one active test graph. |

### Key Link Verification

| From | To | Via | Status | Details |
| --- | --- | --- | --- | --- |
| `SiriusMacApp` | `AuthenticationView` | root `WindowGroup` | ✓ WIRED | The native app launches the authentication surface. |
| `AuthenticationView` | bridge + client | composed flow initializer | ✓ WIRED | The view constructs one bridge, Keychain store, client, and semantic model. |
| bridge | client | opaque `CredentialSource` | ⚠️ WIRED, BEHAVIOR FAILED | The call chain exists, but concurrent cookie reads can create two handoffs. |
| `SessionCoordinator` | `AuthenticationFlowAdapter` | ordered internal classifications | ✓ WIRED | Lines 100 and 116 classify native authentication/entitlement before active publication. |
| client | direct transport | `NativeRequestVerifier` | ✓ WIRED | Production client uses `EphemeralURLSessionTransport` and exact request contracts. |
| explicit cleanup UI | coordinator cleaners | model → client → `signOut()` | ✓ WIRED | Both Keychain erase and bridge residue cleanup are awaited after memory retirement. |
| Xcode root E4 | test target E1 | project object graph | ✓ WIRED | `plutil`/`jq` and `xcodebuild -list -json` report the one canonical graph. |

### Data-Flow Trace (Level 4)

| Artifact | Data variable | Source | Status |
| --- | --- | --- | --- |
| `AuthenticationView` | `model.state` | semantic results from composed bridge/client flow | ✓ FLOWING |
| `WebAuthenticationBridge` | opaque handoff | one matching WebView-owned first-party cookie | ✗ CARDINALITY RACE |
| `SessionCoordinator` | `state` / entitlement | sequential native verifier responses | ✓ FLOWING |
| cleanup UI | signed-out / cleanup-failed state | aggregate Keychain + residue-cleaner outcomes | ✓ FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
| --- | --- | --- | --- |
| Client sequencing, cleanup, transport, redaction, and public API | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/SiriusXMClient` | 29 tests passed | ✓ PASS |
| WebView bridge/retry and fresh-composition cleanup | `xcodebuild ... -destination 'platform=macOS' -only-testing:SiriusMacTests/WebAuthenticationBridgeTests -only-testing:SiriusMacTests/SelectedAuthenticationCompositionTests test` | 14 tests passed | ✓ PASS |
| Concurrent selection within one bridge attempt | Controlled-suspension test | No test exists; source inspection proves latch is set after the first suspension. | ✗ FAIL |
| Consolidated Xcode graph | `plutil -lint` + `plutil|jq` + `xcodebuild -list -json` | Parsed; canonical records asserted; one `SiriusMacTests` target. | ✓ PASS |

### Requirements Coverage

| Requirement | Source Plan(s) | Status | Evidence |
| --- | --- | --- | --- |
| AUTH-01 | 01-02, 05-10 | ✗ BLOCKED | Exact one-transfer-per-attempt fails for concurrent explicit selections. |
| AUTH-02 | 01-02, 03, 05-08 | ✓ SATISFIED | Strict classifications, explicit terminal UI, and no fallback/bypass path. |
| AUTH-03 | 01-04, 06-08, 10 | ✓ SATISFIED | Fresh and active-session cleanup retire memory and clear/report both local stores. |
| SECR-01 | 01-04, 07, 10 | ✓ SATISFIED | Only the app-owned Keychain adapter persists approved material; no production read/restore path. |
| SECR-02 | 01-02-04, 06-10 | ✓ SATISFIED | Ephemeral direct-host transport and volatile handoff are present; the AUTH-01 race still requires repair. |
| SECR-03 | 01-03, 05-08 | ✓ SATISFIED | Closed event types and redaction tests exclude synthetic secret canaries. |
| CLNT-01 | 01-01, 05, 07-08 | ✓ SATISFIED | Independent SwiftPM product/import test passed. |
| CLNT-02 | 01-01-02, 07-08 | ✓ SATISFIED | Public API exposes typed semantic capabilities and no wire-schema fields. |
| CLNT-03 | 01-02-03, 07-08 | ✓ SATISFIED | Transport and response details remain under internal adapters. |
| CLNT-04 | 01-01-11 | ⚠️ PARTIAL | Required collaborators are injectable, but the bridge's injectable cookie store lacks the required concurrent-selection regression. |

No Phase 1 requirement is orphaned: every listed ID appears in one or more Phase 1 plan frontmatters.

### Prohibition and Anti-Pattern Scan

| File | Line | Pattern | Severity | Impact |
| --- | --- | --- | --- |
| `SiriusMac/Authentication/WebAuthenticationBridge.swift` | 84-117 | Latch is checked before async cookie access and marked consumed only afterward. | 🛑 BLOCKER | Violates the required one-transfer-per-attempt invariant. |

Static scans found no Phase 1 production dependency on `.planning`, Phase 0 authority artifacts, shared `URLSession`, shared cookie storage, JavaScript injection, or debt-marker comments. `readStoredCredential()` exists only on the Keychain adapter and has no production caller. The prior review warning about an inert unsupported-state retry is not present in the current code: `.unsupported` is now retryable in `AuthenticationPresentationModel` and the view's Retry button reaches that path.

### Gaps Summary

Phase 1 is not verified complete. The user-story formatting, sequential retry/re-login, fresh-composition cleanup, and Xcode graph gaps are closed, but the single-consumption handoff is still unsafe under concurrent explicit selections. The exact sequence is visible in the code: both tasks pass the `didTransferCredential == false` guard before either returns from `await cookieStore.allCookies()`, then both may invoke `credentialConsumer`. Because the selected token is the authorization boundary, this is a blocker rather than a warning.

No later roadmap phase explicitly covers bridge handoff concurrency, so this is not deferred work.

---

_Verified: 2026-08-18T13:54:11Z_
_Verifier: the agent (gsd-verifier)_
