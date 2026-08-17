---
phase: 00-authentication-feasibility-gate
reviewed: 2026-08-17T00:00:00Z
depth: standard
files_reviewed: 29
files_reviewed_list:
  - Spikes/AuthenticationFeasibility/Package.swift
  - Spikes/AuthenticationFeasibility/Scripts/verify-current-xcode.sh
  - Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityCore/AuthorizedPlaybackProbe.swift
  - Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityCore/CandidateSelection.swift
  - Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityCore/CleanupCoordinator.swift
  - Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityCore/DecisionGate.swift
  - Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityCore/EvidenceContract.swift
  - Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityCore/PublicAuthContract.swift
  - Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityCore/RenewalObserver.swift
  - Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityCore/RunProtocol.swift
  - Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityCore/SemanticProofClient.swift
  - Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityCore/ToolchainGate.swift
  - Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityHarness/LiveBrowserRuntime.swift
  - Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityHarness/WebLoginSession.swift
  - Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityHarnessLauncher/main.swift
  - Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityRunner/main.swift
  - Spikes/AuthenticationFeasibility/Tests/AuthFeasibilityCoreTests/AuthorizedPlaybackProbeTests.swift
  - Spikes/AuthenticationFeasibility/Tests/AuthFeasibilityCoreTests/BrowserProofPreflightTests.swift
  - Spikes/AuthenticationFeasibility/Tests/AuthFeasibilityCoreTests/BrowserReturnContractTests.swift
  - Spikes/AuthenticationFeasibility/Tests/AuthFeasibilityCoreTests/CandidateSelectionTests.swift
  - Spikes/AuthenticationFeasibility/Tests/AuthFeasibilityCoreTests/CleanupCoordinatorTests.swift
  - Spikes/AuthenticationFeasibility/Tests/AuthFeasibilityCoreTests/ContractTracerTests.swift
  - Spikes/AuthenticationFeasibility/Tests/AuthFeasibilityCoreTests/DecisionGateTests.swift
  - Spikes/AuthenticationFeasibility/Tests/AuthFeasibilityCoreTests/FinalizationGateTests.swift
  - Spikes/AuthenticationFeasibility/Tests/AuthFeasibilityCoreTests/NativeDirectPreflightTests.swift
  - Spikes/AuthenticationFeasibility/Tests/AuthFeasibilityCoreTests/NativeFallbackGateTests.swift
  - Spikes/AuthenticationFeasibility/Tests/AuthFeasibilityCoreTests/PublicAuthContractTests.swift
  - Spikes/AuthenticationFeasibility/Tests/AuthFeasibilityCoreTests/RenewalObserverTests.swift
  - Spikes/AuthenticationFeasibility/Tests/AuthFeasibilityCoreTests/StopConditionTests.swift
findings:
  critical: 5
  warning: 3
  info: 0
  total: 8
status: issues_found
---

# Phase 00: Code Review Report

**Reviewed:** 2026-08-17T00:00:00Z
**Depth:** standard
**Files Reviewed:** 29
**Status:** issues_found

## Summary

The Phase 0 scope has material fail-closed defects: an arbitrary custom-scheme navigation can be accepted as the app-bound return, the owner-ended renewal observation can later be upgraded to renewed, and cleanup can be marked verified without performing or awaiting the promised cleanup. The Phase 1 quartet rederivation itself is substantially stricter, but these defects make upstream browser/proof evidence unreliable.

`swift test` could not be completed in this review environment because the selected Command Line Tools compiler and SDK versions disagree and the sandbox cannot write the user Clang module cache. This is an environment/toolchain failure, not counted as a source finding.

## Narrative Findings (AI reviewer)

## Critical Issues

### CR-01: App-bound return accepts query-bearing and non-main-frame navigations

**File:** `Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityHarness/WebLoginSession.swift:126-135`

**Also affects:** `Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityHarness/WebLoginSession.swift:153-160`, `Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityCore/SemanticProofClient.swift:30-37`

**Issue:** The callback matcher accepts `siriusmac-auth://browser-return?code=...` because neither matcher rejects a query. `decidePolicyFor` also makes no main-frame check before creating `AppBoundReturnResult`. Consequently, any navigation action matching only the scheme/host/path—including a query-bearing OAuth-style callback or an iframe/subframe action—can consume the one-time return and emit `.cleanAppBoundReturn`. This breaks the declared secret-free, exact callback boundary and can turn an untrusted navigation into proof progress.

**Fix:** Require an exact, query-free return shape in one shared matcher and only accept it for the main frame. For example, reject when `url.query != nil` (and reject any other unexpected URL component), then guard `navigationAction.targetFrame?.isMainFrame == true` before invoking the return handler. Add regression tests for query, fragment, userinfo, and subframe callback attempts.

### CR-02: Owner-ended renewal observation is not latched and can later become renewed

**File:** `Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityCore/RenewalObserver.swift:62-75`

**Issue:** `.ownerEnded` returns `.renewalPending` but does not persist that result. A subsequent call with `.ordinaryProviderReplacement` invokes `verifyAuthenticatedReplacement` and can return `.renewed`. That reopens provider observation after the owner has ended the bounded observation window, contradicting the one-opportunity/no-retry contract and allowing renewal-pending evidence to be upgraded after it was retracted.

**Fix:** Store a closed pending result (for example, a `resolvedProof` that includes `.renewalPending`) before returning it, and return that stored result for every later observation. Add a test asserting that `.ownerEnded` followed by `.ordinaryProviderReplacement` remains `.renewalPending` and never invokes the verifier.

### CR-03: Cleanup can claim verified without doing the required teardown, and app exit bypasses cleanup entirely

**File:** `Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityHarness/LiveBrowserRuntime.swift:90-96`

**Also affects:** `Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityHarness/LiveBrowserRuntime.swift:143-150`, `Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityHarnessLauncher/main.swift:137-145`

**Issue:** `BrowserRuntimeCleanupParticipant.perform` returns `true` for sign-out, ephemeral-client cancellation, playback teardown, volatile-state clearing, and absence verification without performing or verifying any of them. `cleanUp()` therefore feeds `.cleanupVerified` into preflight based on no-op steps. Separately, both application termination paths call only `runtime.cancel()` and immediately terminate; they never await `runtime.cleanUp()`. This can create a verified cleanup proof despite an unverified session/runtime teardown, and closing the window skips the coordinator altogether.

**Fix:** Give each volatile collaborator an explicit idempotent teardown/absence-verification operation, invoke it in the participant for its corresponding step, and return `false` when verification cannot be established. Route window close/application termination through an orderly shutdown state that awaits the coordinator before terminating (or records a closed cleanup failure if macOS termination cannot wait). Add tests that fail each concrete hook and verify no complete proof can be serialized.

### CR-04: Playback proof treats item allocation as authorization and audibility

**File:** `Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityCore/AuthorizedPlaybackProbe.swift:59-70`

**Issue:** `prepareExpectedAuthorization()` creates an `AVPlayerItem` and returns `.ready` whenever `currentItem` is non-nil. That is true immediately after allocation even if the asset is unplayable, authorization/content-key handling fails, or no audio is ever rendered; the code does not load/observe playable or item status and never starts playback. `prove` can therefore return `.authorizedAndAudible` solely from the caller-provided enum and owner boolean, producing a false positive for the core feasibility condition.

**Fix:** Make preparation asynchronous and fail closed until the asset and item have reached the required authorized/playable status; bind it to the actual authorized playback path and only accept owner confirmation after bounded playback has begun. Map item/asset failures to a terminal/incomplete result and cover unplayable, failed-key, and no-audio cases in tests.

### CR-05: An unconfirmed playback proof can repeatedly recreate volatile playback work

**File:** `Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityCore/AuthorizedPlaybackProbe.swift:94-112`

**Issue:** When preparation succeeds but the owner does not confirm audibility, `prove` returns `.incomplete` without latching it. The next call repeats `prepareExpectedAuthorization()`, creating another content-key session/player after the first owner-retracted attempt. This violates the class's stated “exactly one bounded proof” and “no retry” guarantees, and can repeatedly exercise volatile authorization material.

**Fix:** Add a consumed/proof result state that is set for every first eligible attempt, including `.incomplete`, and return it before calling the runtime again. Test two `.notConfirmed` calls and assert the runtime preparation count is one.

## Warnings

### WR-01: Concurrent cleanup calls can execute teardown steps twice

**File:** `Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityCore/CleanupCoordinator.swift:33-50`

**Issue:** Although the coordinator is `@MainActor`, `await participant.perform(step)` yields the actor. A second `cleanUp()` call can enter while `proof` is still `nil` and start the entire step sequence concurrently. Double sign-out/browser teardown conflicts with the single canonical cleanup order and makes the cached proof unreliable.

**Fix:** Track an in-flight cleanup task/state before the first suspension and have later callers await the same result. Add a test participant that suspends on the first step and assert concurrent callers execute every step once.

### WR-02: Browser-launch failures exit successfully

**File:** `Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityHarnessLauncher/main.swift:33-35`

**Also affects:** `Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityHarnessLauncher/main.swift:132-134`

**Issue:** Invalid arguments or a failed launch gate print a generic message and return from `main`, yielding exit status 0. If startup later fails, the app calls `NSApp.terminate` and also exits successfully. Automation or the owner workflow can therefore treat a browser run as successfully launched when no valid run occurred.

**Fix:** Terminate with a nonzero status after a launch/preflight failure and arrange for startup failures to propagate a nonzero outcome. Keep successful owner cancellation distinct from launch failure.

### WR-03: Finalization accepts noncanonical supersession artifacts with trailing content

**File:** `Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityRunner/main.swift:97-114`

**Issue:** `validateSupersessionForFinalization` uses `hasPrefix(expected)` rather than exact equality. A supersession artifact with arbitrary appended fields or stale/conflicting authority data is accepted despite the finalization flow claiming machine-field validation and canonical inputs.

**Fix:** Require `text == expected` (or parse a closed ordered schema and compare its canonical rendering) and add a test that appending one line causes finalization validation to fail.

---

_Reviewed: 2026-08-17T00:00:00Z_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: standard_
