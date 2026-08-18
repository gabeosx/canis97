---
phase: 01-safe-interoperability-foundation
verified: 2026-08-18T12:09:05Z
status: gaps_found
score: 5/7 must-haves verified
behavior_unverified: 0
overrides_applied: 0
gaps:
  - truth: "MVP user-flow goal can be verified against a valid user story"
    status: failed
    reason: "Phase 1 is marked mode: mvp, but its ROADMAP goal is not a valid `As a ..., I want to ..., so that ...` user story; the mandated MVP verifier cannot derive or verify User Flow Coverage."
    artifacts:
      - path: ".planning/ROADMAP.md"
        issue: "`user-story.validate` returned false for the Phase 1 goal."
    missing:
      - "Reformat the Phase 1 goal with `/gsd mvp-phase 1` before re-verification."
  - truth: "A subscriber can begin a new native WebView sign-in after a terminal result or sign-out."
    status: failed
    reason: "WebAuthenticationBridge permanently retains didTransferCredential after its first transfer, while the UI's Retry Sign In path retains that same bridge."
    artifacts:
      - path: "SiriusMac/Authentication/WebAuthenticationBridge.swift"
        issue: "Lines 75 and 107 return `.alreadyConsumed` forever; `beginUserOperatedSignIn()` at lines 68-71 does not reset the lifecycle."
      - path: "SiriusMac/Authentication/AuthenticationPresentationModel.swift"
        issue: "Retry re-enters the same bridge through beginWebViewSignIn at lines 41-45 and 260-262."
    missing:
      - "An explicit, user-operated new-attempt lifecycle that safely clears the consumed handoff only before a new login."
      - "A regression test for terminal-result retry and sign-out followed by a new login."
  - truth: "A subscriber can sign out and clear persisted credentials after a fresh app composition."
    status: failed
    reason: "A new app composition never reads/restores the stored credential and both its UI and coordinator deny cleanup while in-memory state is signed out."
    artifacts:
      - path: "SiriusMac/Authentication/AuthenticationView.swift"
        issue: "Lines 8-18 create a new empty bridge/client; lines 42-47 expose Sign Out only for an entitled in-memory state."
      - path: "Packages/SiriusXMClient/Sources/SiriusXMClient/Session/SessionCoordinator.swift"
        issue: "Lines 141-144 return `.alreadySignedOut` before calling Keychain or browser cleaners on a fresh coordinator."
      - path: "SiriusMac/Security/KeychainCredentialStore.swift"
        issue: "`readStoredCredential()` exists at lines 46-64 but no production code calls it."
    missing:
      - "A supported restore path, or an always-reachable cleanup path that deletes the Keychain item and browser residue without an active in-memory session."
      - "An app-lifecycle regression that creates a new composition after persistence and proves restore or explicit removal."
---

# Phase 1: Safe Interoperability Foundation Verification Report

**Phase Goal:** Subscribers can establish or end an authorized SiriusXM session without exposing secrets or weakening access controls, through a reusable Apple-platform client boundary.
**Verified:** 2026-08-18T12:09:05Z
**Status:** gaps_found
**Re-verification:** No — initial verification

## MVP Contract Gate

Phase 1 is declared as `mode: mvp`, but `gsd-tools query user-story.validate --story "$PHASE_GOAL" --pick valid` returned `false`. Its goal is not a user story, so the required MVP User Flow Coverage cannot be truthfully derived. This is a blocking planning-contract discrepancy; reformat the goal with `/gsd mvp-phase 1`, then re-run verification.

## User Flow Coverage

Unavailable: the MVP user story is invalid. No user-flow coverage has been inferred from a non-user-story technical goal.

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
| --- | --- | --- | --- |
| 1 | A subscriber can sign in through the nonpersistent WebView and transfer one opaque token into native verification. | ✗ FAILED | Fresh-flow pieces and tests exist, but the same bridge permanently returns `.alreadyConsumed` after its first transfer, so retry/re-login is broken. |
| 2 | Unknown, changed, or prohibited-control flows stop with an explicit unsupported result and no bypass. | ✓ VERIFIED | Closed classifier tests cover 403/429, challenge, bot, malformed, ambiguous, and redirect cases; UI maps bridge failures to `.unsupported`. |
| 3 | Only native authentication plus entitlement can atomically create an active session. | ✓ VERIFIED | `SessionCoordinator` accepts a credential, verifies authentication then entitlement, assigns `.active` only at lines 128-130, and package tests exercise ordering/atomicity. |
| 4 | Sign-out clears actor, Keychain, and exact WebView-cookie material, or reports cleanup failure. | ✗ FAILED | Active-session cleanup is implemented, but a fresh composition cannot restore or erase a persisted Keychain credential; it returns `.alreadySignedOut` before cleaners run. |
| 5 | Credentials are Keychain-backed, session/stream material is ephemeral and direct-only, and diagnostics/fixtures exclude sensitive data. | ✓ VERIFIED | Keychain adapter uses Security APIs; transport uses an ephemeral configuration and exact-host contract; 25-package-test suite includes redaction and transport assertions. |
| 6 | Independent Apple-platform consumers can use typed async client capabilities without wire details. | ✓ VERIFIED | `Package.swift` exports `SiriusXMClient`; `PublicConsumerTests` imports it normally and calls semantic capability methods. |
| 7 | Deterministic bridge, native-authentication, entitlement, sign-out, and redaction tests compile independently of planning artifacts. | ✓ VERIFIED | Full SwiftPM suite passed (25 tests) and Xcode suite passed (19 tests); static scan found no production `.planning` or Phase 0 authority dependency. |

**Score:** 5/7 truths verified (0 present but behavior-unverified)

### Required Artifacts

All declared artifacts exist and are substantive. Manual Level-3 wiring is included because the generic key-link query cannot resolve basename-only plan links.

| Plan | Artifact(s) | Exists / substantive | Wired status | Details |
| --- | --- | --- | --- | --- |
| 01-01 | `Package.swift`, public-consumer test, Xcode project | ✓ | ✓ | SwiftPM product is consumed through `AuthenticationView` and app target. |
| 01-02 | `SessionCoordinator.swift`, coordinator tests | ✓ | ✓ | Calls `AuthenticationFlowAdapter` for both native responses. |
| 01-03 | request contract, redaction tests | ✓ | ✓ | `NativeRequestVerifier` uses `EphemeralURLSessionTransport`; contract and diagnostics are internal. |
| 01-04 | Keychain adapter, sign-out tests | ✓ | ⚠️ partial | Active-session wiring works; fresh-process cleanup is unreachable. |
| 01-05 | presentation model and view | ✓ | ✓ | View owns one bridge/client/composed-flow graph. |
| 01-06 | token policy, bridge, bridge tests | ✓ | ⚠️ partial | Extraction and exact cleanup share the predicate; new-login lifecycle is missing. |
| 01-07 | transaction and composition tests | ✓ | ✓ | Native composition order is exercised synthetically. |
| 01-08 | acceptance summary | ✓ | ✓ | Records acceptance, but its narrative does not supersede the two lifecycle failures above. |

### Key Link Verification

| From | To | Via | Status | Details |
| --- | --- | --- | --- | --- |
| `SiriusMacApp` | `SiriusXMClient` | `AuthenticationView` → composed flow | ✓ WIRED | App renders `AuthenticationView`; its initializer creates bridge, client, Keychain store, and composed flow. |
| `SessionCoordinator` | `AuthenticationFlowAdapter` | strict native-response classification | ✓ WIRED | Lines 99 and 115 classify the two verifier responses before state publication. |
| WebView bridge | `SiriusXMClient` | opaque `CredentialSource` | ⚠️ PARTIAL | Initial handoff is wired, but `didTransferCredential` is never reset for a subsequent explicit login. |
| `SiriusXMClient` | direct native transport | `NativeRequestVerifier` | ✓ WIRED | Client initializes verifier with `EphemeralURLSessionTransport`. |
| sign-out action | Keychain and residue cleaners | `SessionCoordinator.signOut()` | ⚠️ PARTIAL | Cleaners run after an active/in-flight session, but not after app restart. |

### Data-Flow Trace (Level 4)

| Artifact | Data variable | Source | Status |
| --- | --- | --- | --- |
| `AuthenticationView` | `model.state` | Native composed-flow outcomes | ✓ FLOWING for initial attempt; retry path is blocked by bridge state. |
| `SessionCoordinator` | `state` / `lastEntitlement` | Sequential authentication and entitlement verifier responses | ✓ FLOWING; active assignment follows both verified outcomes. |
| `WebAuthenticationBridge` | opaque credential handoff | one selected WebView cookie | ✓ FLOWING once per bridge; no new-attempt reset. |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
| --- | --- | --- | --- |
| Package client/auth/sign-out/redaction regressions | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/SiriusXMClient` | 25 tests passed | ✓ PASS |
| Native bridge/composition/Keychain regressions | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS' test` | 19 tests passed | ✓ PASS |

The green suites do not exercise the failed retry-after-transfer or persisted-credential-after-restart paths. `SelectedAuthenticationCompositionTests` covers one initial transfer and a missing-cookie terminal result, while `KeychainCredentialStoreTests` exercise CRUD in isolation only.

### Requirements Coverage

| Requirement | Source Plan(s) | Status | Evidence |
| --- | --- | --- | --- |
| AUTH-01 | 01-02, 01-05, 01-06, 01-07, 01-08 | ✗ BLOCKED | Initial semantic flow exists, but a retry/new login after transfer cannot succeed. |
| AUTH-02 | 01-02, 01-03, 01-05, 01-06, 01-07, 01-08 | ✓ SATISFIED | Strict classifier, exact host policy, and terminal UI prevent bypass/fallback behavior. |
| AUTH-03 | 01-04 through 01-08 | ✗ BLOCKED | Fresh-process sign-out cannot erase persistent credentials or residue. |
| SECR-01 | 01-04, 01-07, 01-08 | ✓ SATISFIED | Persistent secret storage uses `SecItem` Keychain operations only. |
| SECR-02 | 01-02, 01-03, 01-04, 01-06 through 01-08 | ✓ SATISFIED | Direct ephemeral transport and volatile handoff are implemented and tested. |
| SECR-03 | 01-03, 01-05 through 01-08 | ✓ SATISFIED | Closed diagnostic model and fixture canary-rejection tests pass. |
| CLNT-01 | 01-01, 01-05, 01-07, 01-08 | ✓ SATISFIED | Reusable library product plus normal independent consumer test. |
| CLNT-02 | 01-01, 01-02, 01-07, 01-08 | ✓ SATISFIED | Typed async public outcomes/capabilities expose no endpoint or raw-schema API. |
| CLNT-03 | 01-02, 01-03, 01-07, 01-08 | ✓ SATISFIED | Request contract and response classifiers are internal adapters. |
| CLNT-04 | 01-01 through 01-08 | ✓ SATISFIED | Transport, credential source/store, clock, diagnostics, and residue-cleaner seams are injectable. |

No requirement mapped to Phase 1 is orphaned from all plan frontmatter.

### Code-Review Findings Rechecked

| Finding | Verdict | Evidence |
| --- | --- | --- |
| CR-01: bridge cannot be reused after credential transfer | **CONFIRMED — BLOCKER** | `didTransferCredential` changes to `true` at bridge line 107; retry invokes the same bridge and no reset exists. |
| CR-02: persisted Keychain credential is stranded after restart | **CONFIRMED — BLOCKER** | Keychain reader has no production caller; new app starts unsigned; view hides Sign Out; coordinator returns early while signed out. |
| WR-01: duplicate disconnected Xcode records | **CONFIRMED — WARNING** | `project.pbxproj` contains both active `E1…` and detached `A001…` `SiriusMacTests` targets, two project objects, duplicated test references/source phases. The root project selects only `E1…`. Full XCTest currently passes through the active target. |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
| --- | --- | --- | --- | --- |
| `WebAuthenticationBridge.swift` | 75, 107 | Permanently consumed credential gate with no new-login reset | 🛑 Blocker | Prevents retry and re-login. |
| `SessionCoordinator.swift` | 141-144 | Cleaner guard exits when fresh in-memory state is signed out | 🛑 Blocker | Can strand persisted Keychain credentials after restart. |
| `project.pbxproj` | 66-79 | Duplicate disconnected test-target/project/source records | ⚠️ Warning | Future edits can silently modify inactive test graph. |

Static scans found no debt-marker comments in Phase 1 source, no production `.planning`/Phase 0 authority dependency, and no placeholder UI/API implementation.

## Gaps Summary

Phase 1 is not ready to proceed. The report does not accept Plan 08's claimed regression closure as evidence: its green tests cover only the initial handoff and isolated Keychain CRUD, not the two lifecycle paths that the code review identified. First repair the bridge's explicit new-login lifecycle and the app-restart credential lifecycle, consolidate the inactive Xcode project records, and correct the MVP goal format. Then re-run verification.

---

_Verified: 2026-08-18T12:09:05Z_
_Verifier: the agent (gsd-verifier)_
