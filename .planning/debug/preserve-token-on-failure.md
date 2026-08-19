---
status: awaiting_human_verify
trigger: "Authentication, entitlement, tune, provider, test, and relaunch failures must preserve the reusable Keychain token; only explicit Sign Out or Clear Local Session may erase it."
created: 2026-08-19T20:30:00Z
updated: 2026-08-19T21:19:00Z
---

## Current Focus

reasoning_checkpoint:
  hypothesis: "Two code paths conflate fail-closed runtime authentication with user-authorized persistent cleanup: `completeClientTransaction` calls `eraseRejectedRestore()` for every non-entitled restored attempt, and `loadStoredCredentialForAuthentication()` calls `removeStoredCredential()` for validation failures."
  confirming_evidence:
    - "Focused red test run observed rejected automatic restore erase `approved-restore` and leave the retry in the WebView path."
    - "Focused red test run observed each malformed material case invoke the injected remover exactly once and clear the stored bytes."
    - "Static trace found only `SessionCoordinator.signOut()` as the intended explicit client cleanup authority, reached by Sign Out and Clear Local Session."
  falsification_test: "After replacing the two automatic deletion paths with in-memory attempt retirement/invalid classification, an automatic rejection or invalid material still produces a terminal non-active state but preserves the stored bytes and never invokes a remover; explicit Sign Out/Clear Local Session still delete."
  fix_rationale: "Remove Keychain deletion from validation and restore-rejection paths, reset only `attemptOrigin` for a failed restored attempt, and leave the existing `SessionCoordinator.signOut()` deletion route intact for explicit user cleanup."
  blind_spots: "No live provider flow will be run; provider/catalog/tune/metadata/playback code is verified by call-site isolation rather than a live request. Existing explicit-cleanup tests prove user-driven deletion but need to remain green after the change."
  candidate_causes:
    - "code: `eraseRejectedRestore()` writes persistent state during a non-user terminal authentication result."
    - "code: Keychain validation deletes bytes merely because they fail local shape checks."
    - "environment: XCTest hosted the app before c57c8d2, but its now-inert scene is a trigger that exposed the code defect rather than a remaining deletion path."
    - "data: malformed or stale credential material reaches validation and triggers deletion in the current code."
  and_gate: "no — either automatic deletion path independently accounts for lost material; both are manifestations of the same authority-boundary defect."
test: Focused XCTest run of KeychainCredentialStoreTests and SelectedAuthenticationCompositionTests with agent-authored specified-oracle tests for byte preservation and remover count.
expecting: The red state should show persistent bytes cleared and remover count one before the repair; after the repair, the same terminal states must remain fail-closed without persistence deletion.
next_action: No live request is authorized during this fix. On the user's next deliberate authentication verification, confirm a terminal automatic restore leaves the reusable credential available for a later retry; the code/test evidence is complete now.
bug_class: bohrbug
common_pattern_candidates: error-handling cleanup coupled to a normal failure outcome; state-management conflation of volatile session retirement with persistent credential deletion; data-validation branch deleting input on malformed storage.
sbfl: skipped — no existing failing test or per-test coverage data is available before creating the regression test.
tdd_checkpoint: null

## Symptoms

expected: A reusable credential remains in app-owned Keychain storage across builds, tests, relaunches, HTTP failures, and upstream incompatibility unless the user explicitly signs out or clears the local session.
actual: An app-hosted XCTest launch ran automatic restoration; rejection followed the stored-credential erase path and permanently removed the token, forcing another login. The tune HTTP 400 itself should not sign out or erase anything.
errors: "Fresh app relaunch showed Signed out after the test-host lifecycle."
timeline: Observed on 2026-08-19 after the tune-classification fix and full Xcode test run.
reproduction: Store a reusable credential, run the app-hosted macOS test suite or trigger a rejected automatic restore, then launch the production app and observe that the credential is gone.

## Evidence

- timestamp: 2026-08-19T20:42:00Z
  checked: All app/package Keychain deletion call sites and authentication composition.
  found: `SessionCoordinator.signOut()` is the client-level persistent erase path and is reached by the user-facing Sign Out and Clear Local Session actions. `WebAuthenticationBridge` removes browser cookies only through that explicit sign-out cleaner. `SiriusMacLaunchMode` now makes XCTest-hosted production scenes inert.
  implication: Explicit user cleanup has an isolated deletion authority; the test-host launch issue was separately addressed by c57c8d2 and is not a reason to retain automatic erasure.

- timestamp: 2026-08-19T20:43:00Z
  checked: `RestorableAuthenticationCredentialSource.eraseRejectedRestore()` and `ComposedAuthenticationPresentationFlow.completeClientTransaction`.
  found: Every non-entitled result of a restored credential (rejected, challenge, unsupported, or non-entitled) reaches `eraseRejectedRestore()`, which calls `KeychainCredentialStore.erase()` before returning the terminal UI state.
  implication: A transient upstream error or a provider contract mismatch can permanently remove a reusable credential despite no user sign-out intent.

- timestamp: 2026-08-19T20:44:00Z
  checked: `KeychainCredentialStore.loadStoredCredentialForAuthentication()` and its tests.
  found: Empty, oversized, non-UTF-8, or whitespace-containing material invokes `removeStoredCredential()` and reports `.invalidErased`; existing tests require that deletion.
  implication: Storage validation is a second automatic destructive path and must be changed so fail-closed validation never deletes persistent material.

- timestamp: 2026-08-19T20:45:00Z
  checked: Existing composition tests for automatic restore and user cleanup.
  found: Tests currently assert that rejected restore erases the credential, while separate tests prove Clear Local Session and Sign Out erase the Keychain item.
  implication: The destructive behavior was intentional in current test expectations, so a test-first repair must reverse only the automatic assertions and preserve explicit-cleanup coverage.

- timestamp: 2026-08-19T21:01:00Z
  checked: Focused Xcode run of `KeychainCredentialStoreTests` and `SelectedAuthenticationCompositionTests` after replacing destructive expectations with byte-preservation assertions.
  found: 15 specified-oracle assertion failures: malformed material cleared the injected storage and invoked its remover once; a rejected restored credential was absent on return; explicit retry then opened the WebView instead of reusing the retained item. Unrelated tests in both classes passed.
  implication: The hypothesis is directly reproduced as a deterministic Bohrbug. The added tests are valid regression seeds (not bug-report scripts) and prove the proposed boundary change is required.

- timestamp: 2026-08-19T21:05:00Z
  checked: Minimal source repair diff before post-fix execution.
  found: The loader now returns `.invalid` without invoking `removeStoredCredential()`. Failed restored attempts call `finishRejectedRestore()` to reset only in-memory attempt state. The sole `CredentialStore.erase()` call remains inside `SessionCoordinator.signOut()`.
  implication: The repair changes deletion authority rather than suppressing authentication/entitlement terminal states; explicit sign-out cleanup remains intact.

- timestamp: 2026-08-19T21:09:00Z
  checked: Post-fix focused Xcode test run of `KeychainCredentialStoreTests` and `SelectedAuthenticationCompositionTests`.
  found: All 21 tests passed. Rejected automatic restore remains `.rejected`, invalid material remains `.unsupported`, both leave stored bytes intact and do not read WebView cookies; explicit Clear Local Session and Sign Out tests still erase Keychain/browser residue.
  implication: The fix meets the target behavior at its immediate call sites. A focused mutation/revert check remains before accepting it.

- timestamp: 2026-08-19T21:14:00Z
  checked: Targeted mutation/revert at the invalid-material loader boundary using only injected synthetic storage.
  found: Reintroducing `removeStoredCredential()` caused all invalid-material preservation assertions to fail (stored bytes became nil and remover count became one). Removing that injected line restored the six Keychain tests to green.
  implication: The regression test kills the deletion behavior and proves the repaired loader boundary, rather than merely observing a coincidental pass.

- timestamp: 2026-08-19T21:17:00Z
  checked: Full macOS app suite and full SwiftPM library suite.
  found: `xcodebuild test` completed with 76 app tests passing. `swift test` completed with 45 library tests passing. The first sandboxed SwiftPM invocation could not write the compiler cache; the same local suite passed with normal compiler-cache access. No app was launched outside the XCTest host and no provider request occurred.
  implication: The repair has no observed regression in app or library behavior.

- timestamp: 2026-08-19T21:18:00Z
  checked: Post-fix static deletion and sign-out call-site trace, including listening/catalog/tune sources.
  found: Production `CredentialStore.erase()` is called only inside `SessionCoordinator.signOut()`, reached from `AuthenticationPresentationModel.signOut()` and `clearLocalSession()` user actions. `KeychainCredentialStore.removeStoredCredential()` is now reached only by that erase method. Listening/catalog/tune/metadata sources have no client sign-out or credential-store erase call; their `signOut`-named observation sink only closes in-memory observation state.
  implication: Authentication, entitlement, catalog, tune, metadata, playback, build, test, and relaunch failure paths have no remaining production route to erase the reusable Keychain item automatically.

## Eliminated

## Resolution

root_cause: Automatic non-user failure paths were granted persistent-credential deletion authority: rejected restore erased the Keychain item before returning its terminal state, and local material validation deleted bytes before returning invalid. This conflated volatile session retirement with explicit local-session cleanup.
fix: Remove automatic deletion from rejected-restore and validation paths; keep a fail-closed invalid classification and retire only the in-memory restore attempt. Preserve `SessionCoordinator.signOut()` as the sole production `CredentialStore.erase()` authority, reached by explicit Sign Out or Clear Local Session.
oracle_type: specified
verification:
  target_test: { result: pass, suites_run: ["SiriusMacTests/KeychainCredentialStoreTests", "SiriusMacTests/SelectedAuthenticationCompositionTests"] }
  mutation_check: { result: skipped, reason_if_skipped: "No Stryker or Swift mutation-test configuration exists; targeted injected-deletion mutation failed the specified-oracle preservation tests, then passed after removal." }
  no_op_deletion: { result: pass, deletion_justified_by_rca: true, rationale: "The removed behavior was unauthorized persistent deletion; the replacement retains terminal fail-closed state and adds explicit invalid classification." }
  adjacent_tests: { result: pass, suites_run: ["xcodebuild test (76 app tests)", "swift test (45 library tests)"] }
  revert_and_reconfirm: { result: pass, bug_returned_on_revert: true, fixed_on_reapply: true, detail: "Reintroducing only invalid-material deletion caused eight targeted assertions to fail; removing it restored six Keychain tests to green." }
  guardrail_verdict: accepted
files_changed:
  - SiriusMac/Security/KeychainCredentialStore.swift
  - SiriusMac/Authentication/RestorableAuthenticationCredentialSource.swift
  - SiriusMac/Authentication/AuthenticationPresentationModel.swift
  - SiriusMac/Authentication/AuthenticationView.swift
  - SiriusMacTests/KeychainCredentialStoreTests.swift
  - SiriusMacTests/SelectedAuthenticationCompositionTests.swift

## Prevention

- **Why not caught:** Existing tests encoded deletion as the expected behavior for malformed or rejected restored credentials; the suite did not distinguish volatile attempt retirement from persistent Keychain removal.
- **Recurrence guard:** `KeychainCredentialStoreTests.testAuthenticationLoaderRejectsInvalidMaterialWithoutDeletingIt`, `KeychainCredentialStoreTests.testAuthenticationLoaderRejectsEmptyOversizedAndNonUTF8MaterialWithoutDeletingIt`, and the restored-credential composition tests assert both retained bytes/remover count and fail-closed presentation state. The static authority trace confines production deletion to explicit sign-out.
