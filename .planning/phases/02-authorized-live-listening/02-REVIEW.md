---
phase: 02-authorized-live-listening
reviewed: 2026-08-19T00:00:00Z
depth: standard
files_reviewed: 32
files_reviewed_list:
  - Packages/SiriusXMClient/Sources/SiriusXMClient/Diagnostics/SafeDiagnosticEvent.swift
  - Packages/SiriusXMClient/Sources/SiriusXMClient/InternalAdapters/LiveListeningAdapter.swift
  - Packages/SiriusXMClient/Sources/SiriusXMClient/InternalAdapters/SiriusXMRequestContract.swift
  - Packages/SiriusXMClient/Sources/SiriusXMClient/Public/AuthenticationModels.swift
  - Packages/SiriusXMClient/Sources/SiriusXMClient/Public/LiveListeningModels.swift
  - Packages/SiriusXMClient/Sources/SiriusXMClient/Public/SiriusXMClient.swift
  - Packages/SiriusXMClient/Sources/SiriusXMClient/Session/SessionCoordinator.swift
  - Packages/SiriusXMClient/Sources/SiriusXMClient/Session/SessionState.swift
  - Packages/SiriusXMClient/Sources/SiriusXMClient/Transport/DirectHostPolicy.swift
  - Packages/SiriusXMClient/Tests/PublicAPITests/PublicConsumerTests.swift
  - Packages/SiriusXMClient/Tests/SiriusXMClientTests/EphemeralSessionTests.swift
  - Packages/SiriusXMClient/Tests/SiriusXMClientTests/LiveCatalogAdapterTests.swift
  - Packages/SiriusXMClient/Tests/SiriusXMClientTests/LivePlaybackCoordinatorTests.swift
  - Packages/SiriusXMClient/Tests/SiriusXMClientTests/MetadataRefreshCoordinatorTests.swift
  - SiriusMac.xcodeproj/project.pbxproj
  - SiriusMac/Authentication/AuthenticationPresentationModel.swift
  - SiriusMac/Authentication/AuthenticationView.swift
  - SiriusMac/Authentication/RestorableAuthenticationCredentialSource.swift
  - SiriusMac/Catalog/ListeningPresentationModel.swift
  - SiriusMac/Catalog/ListeningView.swift
  - SiriusMac/Listening/ClosedLiveObservationAdapter.swift
  - SiriusMac/Listening/LiveContractObservation.swift
  - SiriusMac/Listening/PlaybackCoordinator.swift
  - SiriusMac/Metadata/MetadataPresentationModel.swift
  - SiriusMac/Security/KeychainCredentialStore.swift
  - SiriusMac/SiriusMacApp.swift
  - SiriusMacTests/AuthenticationPresentationModelTests.swift
  - SiriusMacTests/KeychainCredentialStoreTests.swift
  - SiriusMacTests/ListeningCompositionTests.swift
  - SiriusMacTests/MetadataPresentationTests.swift
  - SiriusMacTests/SelectedAuthenticationCompositionTests.swift
  - script/live_compatibility_checkpoint.sh
findings:
  critical: 6
  warning: 2
  info: 0
  total: 8
status: issues_found
---

# Phase 02: Code Review Report

**Reviewed:** 2026-08-19T00:00:00Z
**Depth:** standard
**Files Reviewed:** 32
**Status:** issues_found

## Summary

The review found six ship-blocking failures in the native playback, session-preservation, and metadata paths. The focused tests exercise fakes and source-presence checks but do not cover the actual AVFoundation install sequence, direct selection binding, real artwork presentation, a hung metadata request, or concurrent concrete resolver operations.

## Narrative Findings (AI reviewer)

## Critical Issues

### CR-01: AVPlayer item is never installed until after it reports ready

**File:** `SiriusMac/Listening/PlaybackCoordinator.swift:518`

**Issue:** `resolveAndInstall` observes a newly-created `AVPlayerItem` but does not call `runtime.install(_:)` until the `onReady` callback at lines 520-522. The production observer considers an item ready only after its status changes (lines 292-295), while the item has not been associated with the `AVPlayer` yet. This creates a readiness/install dependency cycle: the player has no current item to load, and the item is never installed because it never reports ready. The recovery path repeats the same pattern at lines 637-644. Fake runtimes manually invoke `onReady`, so the current tests cannot detect this production failure.

**Fix:** Install the item before waiting for readiness, then observe that installed item and request play only after the ready callback. Preserve generation checks around both installation and callbacks; the old item must be cleared/cancelled on supersession.

### CR-02: Ordinary revalidation failures discard the active in-memory credential and mark the session signed out

**File:** `Packages/SiriusXMClient/Sources/SiriusXMClient/Session/SessionCoordinator.swift:166-171`

**Issue:** Any non-entitled entitlement inspection—including an unsupported 400 response, a rate limit, or a protected-control classification—sets `transientCredential = nil` and `state = .signedOut`. This directly violates the phase contract’s requirement to preserve the Keychain/session material for ordinary tune 4xx outcomes. It forces the user out of the current native session even though a malformed or volatile provider request is not evidence that the credential is invalid.

**Fix:** Keep the active session and transient credential for all inconclusive, compatibility, control, network, and ordinary 4xx outcomes. Return the closed operation failure without mutating authentication state. Only an explicit user sign-out/clear-local-session should erase material; if a confirmed authentication rejection must be represented, model it separately and retain the stored credential until that explicit action.

### CR-03: Concurrent live resolutions corrupt the shared tune resource/key state

**File:** `Packages/SiriusXMClient/Sources/SiriusXMClient/InternalAdapters/LiveListeningAdapter.swift:502-571`

**Issue:** `CurrentSessionFixedLiveOperations` stores `resource` and `handoff` as actor-wide mutable properties. Actors are re-entrant across each network `await`: an older tune can resume after a newer tune and overwrite these properties. The newer resolver generation then calls `resolveResource` or `authorizePlaybackKey` against the older channel/key, causing a false resource failure or authorizing the wrong selection. `FixedLiveStreamResolver`’s outer generation check cannot repair the mutation because it occurs inside this shared operations actor.

**Fix:** Make tune state operation-scoped. Return an opaque resolution context from the tune step and require that same context for resource/key steps, or bind every internal mutation to a resolver-issued command generation and reject stale writes before storing. Add an out-of-order concrete-operations test where an older tune completes after a newer one.

### CR-04: SwiftUI row selection bypasses the metadata generation entirely

**File:** `SiriusMac/Catalog/ListeningView.swift:41`

**Issue:** The `List` writes directly to `$model.selectedChannelID`, but metadata startup lives only in `ListeningPresentationModel.select(_:)` at lines 87-90. A normal user clicking a row changes the selected ID without starting `MetadataPresentationModel`, so the required selected-channel metadata loop and fallback reset never occur. Tests invoke `model.select` directly and therefore miss the actual view wiring.

**Fix:** Bind `List` through an explicit `Binding` whose setter calls `model.select(_:)` (and clears intentionally), or use an `onChange` that calls `select` exactly once per selection change. Add a view/model integration test covering binding-originated selection.

### CR-05: Artwork is advertised but neither fetched nor rendered

**File:** `SiriusMac/Metadata/MetadataPresentationModel.swift:67-75`

**Issue:** On metadata success the model changes artwork to `.current("Artwork available")` merely when an opaque reference exists. It never calls `flow.artwork(for:)`, retains validated `ArtworkData`, or supplies image data to the view. `ListeningView` consequently renders only a text label at lines 80-107. This does not deliver the required current artwork and makes the bounded artwork API dead in the app’s production flow.

**Fix:** Start a separately generation-bound artwork task after accepting a metadata reference, call the semantic `artwork(for:)` API once, and retain only its validated bytes/media type for native image rendering. Keep text and artwork failures independent, cancel both tasks on channel switch/sign-out, and render the decoded image rather than an availability label.

### CR-06: Metadata can remain marked current forever when a refresh hangs

**File:** `SiriusMac/Metadata/MetadataPresentationModel.swift:55-86`

**Issue:** Freshness advances only when `flow.metadata(for:)` returns `.unavailable` or `.failed`. If the next request stalls indefinitely, `refreshLoop` is suspended at line 64 and never executes `advanceFreshness`; the previous successful text/artwork stays `.current` beyond the 90-second stale and five-minute unavailable ceilings. The concrete metadata transport also uses a bare `.ephemeral` configuration with no request/resource timeout at `LiveListeningAdapter.swift:395`, so this is a reachable production path.

**Fix:** Inject a clock/sleeper and schedule freshness expiry independently of the request result, with a bounded transport timeout. On each expiry, recheck the metadata generation and downgrade current state to stale/unavailable even while a request is outstanding. Add deterministic tests for a blocked refresh after a successful snapshot.

## Warnings

### WR-01: Artwork completion can publish after sign-out

**File:** `Packages/SiriusXMClient/Sources/SiriusXMClient/InternalAdapters/LiveListeningAdapter.swift:468-473`

**Issue:** `artwork(for:)` bypasses `SessionCoordinator` and only compares the fetcher’s `generation`, which changes on a subsequent metadata request but not on `SiriusXMClient.signOut()`. An artwork request already in flight can therefore complete and return image bytes after the session has been signed out. This misses the plan’s explicit session-generation check for stale artwork.

**Fix:** Give `LiveMetadataFetching` an invalidation/session-generation mechanism and invoke it from `SiriusXMClient.signOut()`. Capture that generation before the artwork await and return `.unavailable` if sign-out or a channel switch occurred.

### WR-02: Shared redirect flags make concurrent transport classification unreliable

**File:** `Packages/SiriusXMClient/Sources/SiriusXMClient/InternalAdapters/LiveListeningAdapter.swift:391-442`

**Issue:** `FixedMetadataURLSessionTransport` stores one `redirectObserved` boolean for all tasks. Concurrent metadata/artwork requests can reset or set the flag for one another, so a redirected request may be reported as a generic transport error, or an unrelated error may be reported as a redirect. The same shared-flag pattern appears in the concrete catalog and live transports.

**Fix:** Track redirect state per `URLSessionTask` (for example, an identifier-keyed, lock-protected set removed on completion), or use a fresh single-task delegate/session per request. Add a concurrent redirect/non-redirect test to ensure each semantic result reflects only its own task.

---

_Reviewed: 2026-08-19T00:00:00Z_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: standard_
