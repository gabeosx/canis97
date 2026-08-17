---
phase: 00-authentication-feasibility-gate
reviewed: 2026-08-17T22:24:47Z
depth: standard
files_reviewed: 28
files_reviewed_list:
  - Spikes/AuthenticationFeasibility/Package.swift
  - Spikes/AuthenticationFeasibility/Scripts/verify-current-xcode.sh
  - Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityCore/AuthorizedPlaybackProbe.swift
  - Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityCore/CandidateSelection.swift
  - Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityCore/CleanupCoordinator.swift
  - Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityCore/DecisionGate.swift
  - Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityCore/EntitlementContract.swift
  - Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityCore/EvidenceContract.swift
  - Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityCore/PublicAuthContract.swift
  - Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityCore/RenewalObserver.swift
  - Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityCore/RunProtocol.swift
  - Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityCore/SemanticProofClient.swift
  - Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityCore/ToolchainGate.swift
  - Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityHarness/LiveBrowserRuntime.swift
  - Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityHarness/WebLoginSession.swift
  - Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityHarness/WebSessionBridge.swift
  - Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityHarnessLauncher/main.swift
  - Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityRunner/main.swift
  - Spikes/AuthenticationFeasibility/Tests/AuthFeasibilityCoreTests/BrowserReturnContractTests.swift
  - Spikes/AuthenticationFeasibility/Tests/AuthFeasibilityCoreTests/CandidateSelectionTests.swift
  - Spikes/AuthenticationFeasibility/Tests/AuthFeasibilityCoreTests/ContractTracerTests.swift
  - Spikes/AuthenticationFeasibility/Tests/AuthFeasibilityCoreTests/DecisionGateTests.swift
  - Spikes/AuthenticationFeasibility/Tests/AuthFeasibilityCoreTests/FinalizationGateTests.swift
  - Spikes/AuthenticationFeasibility/Tests/AuthFeasibilityCoreTests/NativeDirectPreflightTests.swift
  - Spikes/AuthenticationFeasibility/Tests/AuthFeasibilityCoreTests/NativeFallbackGateTests.swift
  - Spikes/AuthenticationFeasibility/Tests/AuthFeasibilityCoreTests/PublicAuthContractTests.swift
  - Spikes/AuthenticationFeasibility/Tests/AuthFeasibilityCoreTests/StopConditionTests.swift
  - script/build_and_run.sh
findings:
  critical: 3
  warning: 2
  info: 0
  total: 5
status: issues_found
---

# Phase 00: Code Review Report

**Reviewed:** 2026-08-17T22:24:47Z
**Depth:** standard
**Files Reviewed:** 28
**Status:** issues_found

## Summary

The offline parsing and canonical-byte checks are generally strict, but the live proof path is not the producer of the evidence that authorizes Phase 1. The runner accepts caller-authored success claims, while the app UI never connects its authenticated-session result to an entitlement verification. Sign-out validation also ignores a token that the extraction path accepts. These defects permit a false Phase 1 GO and undermine the stated fail-closed boundaries.

## Narrative Findings (AI reviewer)

## Critical Issues

### CR-01: Phase 1 GO is derived from an untrusted, self-asserted owner-result file

**File:** `Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityRunner/main.swift:169`

**Issue:** `finalize-phase` reads `--owner-result` directly from a caller-selected path and passes it to `V3Finalization`. `OwnerResultV3.parse` verifies only fixed strings, and `V3Finalization.derive` turns two such strings into `GO browser-return` (`DecisionGate.swift:316-403`). No value is emitted by `LiveBrowserRuntime`, no run identity binds the claimed lines to a completed browser run, and no entitlement/cleanup result is carried into the finalizer. A user or invoking process can therefore write a syntactically canonical two-run file and obtain an accepted v3 Phase 1 GO without performing either proof run.

**Fix:** Remove `--owner-result` as an authorization input. Have the live runtime create the only finalizable proof record after its preflight reaches `.complete`, bind it to a fresh per-run identifier and the approved contract/entitlement artifact, and make `finalize-phase` consume and validate that sealed record. If a durable artifact is required, write it from the runtime through a private, single-purpose API and reject records not tied to the current run and cleanup result.

### CR-02: The launched browser flow verifies authentication only, never entitlement, yet allows the run to be finished

**File:** `Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityHarnessLauncher/main.swift:186`

**Issue:** The “Use Logged-In Session” action calls `LiveBrowserRuntime.importAuthenticatedWebSession`, which invokes only `NativeWebSessionVerifier` (`LiveBrowserRuntime.swift:122-130`). On any nonempty 2xx profile response, the launcher enables “Verify Sign-Out & Finish Run” (`main.swift:203-205`). Neither `recordAuthentication()` nor `recordEntitlement()` is invoked by this flow, and the separate `InstrumentedBrowserRun` that does call `NativeEntitlementVerifier` has no caller. Consequently a valid login with no subscription can progress through the operator-facing completion flow, while the actual entitlement predicate is never evaluated.

**Fix:** Make the import action drive one runtime-owned sequence: consume the token once, record successful authentication, call `NativeEntitlementVerifier` using the approved entitlement contract, record entitlement only for `.entitled`, and enable the finishing control only after that sequence succeeds. Remove or wire in `InstrumentedBrowserRun`; do not retain a second uncalled verification implementation.

### CR-03: Sign-out proof ignores valid first-party token cookies on subdomains

**File:** `Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityHarness/WebSessionBridge.swift:103`

**Issue:** Session extraction accepts an unexpired `AUTH_TOKEN` from `siriusxm.com` *or any* `*.siriusxm.com` domain (`lines 122-127`). The sign-out checker, however, considers only the apex `siriusxm.com` cookie (`lines 106-110`). If the live usable token is host-only on `player.siriusxm.com` (or another first-party subdomain), it can remain after attempted sign-out while `signOutPresence()` returns `.absent`; `verifySignOutAndClean()` then reports verified cleanup. This is a false sign-out/cleanup confirmation.

**Fix:** Use one shared, exact first-party AUTH_TOKEN predicate for extraction and sign-out checking, including the same expiry policy and all accepted SiriusXM subdomains. Treat more than one matching cookie, an unsupported domain/path, or any remaining matching token as non-absent and block finalization.

## Warnings

### WR-01: Quartet installation is not atomic across its four public artifact paths

**File:** `Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityRunner/main.swift:158`

**Issue:** `atomicallyInstall` stages and validates a quartet, but then replaces each target one at a time. A crash, permission error, or interrupted process after an early replacement leaves a mixed old/new quartet. The post-write validation cannot run in those cases, so consumers see an inconsistent phase state.

**Fix:** Publish the quartet as one immutable run directory and atomically replace a single current-manifest/directory reference after validation, or use one canonical bundle file as the sole commit point. Preserve the prior complete quartet until that final atomic swap succeeds.

### WR-02: Browser-runtime tests can be silently excluded by mutable planning artifacts

**File:** `Spikes/AuthenticationFeasibility/Package.swift:75`

**Issue:** The harness target is included only when three `.planning` files byte-match embedded values. The browser tests are then conditionally compiled behind `canImport(AuthFeasibilityHarness)` (`BrowserReturnContractTests.swift:5`). On a normal changed, unavailable, or locally absent gate artifact, `swift test` can skip the browser-state and return-boundary tests rather than fail, making a passing test run insufficient evidence for this security-critical source.

**Fix:** Keep the harness executable launch-gated, but always compile the harness target and its deterministic tests with injected fake transports/fixtures. Add an explicit test assertion or CI check that reports when the browser test suite was not compiled.

---

_Reviewed: 2026-08-17T22:24:47Z_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: standard_
