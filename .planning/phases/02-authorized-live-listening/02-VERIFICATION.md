---
phase: 02-authorized-live-listening
verified: 2026-08-20T13:09:29Z
status: gaps_found
score: 2/5 must-haves verified
behavior_unverified: 0
overrides_applied: 0
re_verification:
  previous_status: gaps_found
  previous_score: 0/5
  gaps_closed:
    - "Ordinary live-operation revalidation no longer signs out or erases the active session."
    - "Live tune/resource/key material is operation-scoped, and redirect classification is per request."
    - "SwiftUI channel selection now starts metadata; validated artwork is fetched and rendered; blocked metadata ages to stale and unavailable."
    - "Playback items are installed before normal readiness callbacks can request play."
  gaps_remaining:
    - "A pre-ready AVFoundation item has no readiness callback because the production observer uses .new only."
    - "A sign-out cleanup task can erase credentials saved by a later successful sign-in."
  regressions: []
gaps:
  - truth: "A subscriber can tune an entitled linear channel and start, pause, resume, or stop its live stream."
    status: failed
    reason: "The production AVFoundation observer subscribes to AVPlayerItem.status with .new only. An item already ready before observation produces no callback, so it is installed but never receives requestPlay()."
    artifacts:
      - path: "SiriusMac/Listening/PlaybackCoordinator.swift"
        issue: "AVFoundationItemObservation at line 292 omits .initial; requestPlayForReadyItem is therefore never reached for an already-ready item."
    missing:
      - "Handle the initial item status and stage an early ready signal until the observation identity and installation are complete."
      - "Add a production-shaped runtime regression that emits ready during observation setup and asserts exactly one post-install play request."
  - truth: "Catalog, authorization, entitlement, stream-resolution, network, decoder, buffering, and unsupported-upstream failures remain distinct and actionable without losing a valid subsequent session."
    status: failed
    reason: "An older explicit sign-out's detached cleanup can erase Keychain and browser residue after a newer successful attempt has saved a credential, leaving the new active session non-durable."
    artifacts:
      - path: "Packages/SiriusXMClient/Sources/SiriusXMClient/Session/SessionCoordinator.swift"
        issue: "attemptSession() does not await or invalidate cleanupTask; signOut() starts cleanup in Task.detached, whose erase can race a newer save."
    missing:
      - "Serialize new attempts behind outstanding cleanup or make cleanup generation-aware so it cannot erase material written by a newer session."
      - "Add a blocking CredentialStore.erase regression that proves a fresh successful attempt remains persisted after the prior cleanup completes."
  - truth: "Recoverable expiry, network interruption, sleep/wake, and stalls make bounded, cancellation-aware recovery attempts without infinite retry or synthesized listener activity."
    status: failed
    reason: "Recovered AVFoundation items use the same production observer; an already-ready recovered item can remain idle forever, so bounded recovery does not reliably restore listening."
    artifacts:
      - path: "SiriusMac/Listening/PlaybackCoordinator.swift"
        issue: "installRecoveredItem calls observeAndInstall, which inherits the missing initial-ready handling."
    missing:
      - "Use the corrected initial-ready/install ordering for recovery as well as initial tune, with a recovered-item regression."
---

# Phase 02: Authorized Live Listening Verification Report

**Phase Goal:** Subscribers can find their entitled linear SiriusXM channels and reliably listen to one live stream with clear state and current metadata.
**Verified:** 2026-08-20T13:09:29Z
**Status:** gaps_found
**Re-verification:** Yes — after gap-closure plans 02-08 through 02-11

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
| --- | --- | --- | --- |
| 1 | Subscriber can refresh and browse only entitled standard/app-only `channel-linear` records with identity, presentation details, entitlement, and freshness. | ✓ VERIFIED | Strict decoder/filter and stale non-authority behavior are exercised by the recorded passing `LiveCatalogAdapterTests`; `ListeningPresentationModel.refresh` feeds `ListeningView` rows and freshness UI. |
| 2 | Subscriber can tune, start, pause, resume at live edge, and stop one live stream. | ✗ FAILED | Install-before-ready repair is present, but `AVFoundationItemObservation` listens only for `.new` status at `PlaybackCoordinator.swift:292`; an already-ready item never requests play. |
| 3 | Catalog, authorization, entitlement, resolution, network, decoder, buffering, and unsupported-upstream failures remain distinct and actionable; cached channel presence never authorizes playback. | ✗ FAILED | Closed operation failures and cache non-authority are implemented, but the older detached explicit sign-out cleanup can erase credentials from a new successful session. |
| 4 | Recovery is bounded, cancellation-aware, same-channel, and non-synthetic. | ✗ FAILED | Finite recovery, generation guards, and cancellation code exist, but recovered items share the unhandled already-ready AVFoundation race. |
| 5 | Active channel, current program/song text, and best available artwork are shown with explicit stale/unavailable metadata that does not interrupt healthy audio. | ✓ VERIFIED | `ListeningView.channelSelection` calls `select`; `MetadataPresentationModel` starts generation-bound text/artwork/expiry tasks; recorded passing `MetadataPresentationTests` exercise selection, rendering bytes, and 90/300-second expiry. |

**Score:** 2/5 truths verified

## Re-verification Findings

The prior four gap concerns were inspected against the current source, not accepted from summaries:

| Previous concern | Current evidence | Result |
| --- | --- | --- |
| Ordinary operation failure signed out the active user | `SessionCoordinator.withCurrentEntitledCredential` now maps transport/control/entitlement outcomes without mutating `state` or `transientCredential` (lines 142-192); the passing preservation-matrix test covers subsequent reuse. | Closed |
| Concurrent resolutions shared resource/key/handoff state | `CurrentSessionLiveOperationContext` holds per-operation material and `CurrentSessionFixedLiveOperations` has no actor-wide resource/handoff slots (adapter lines 511-588); an out-of-order regression exists. | Closed |
| List selection bypassed metadata and artwork never rendered/aged | The view binding calls `select`/`clearSelection`; `NativeArtworkImage` receives `ArtworkData`; focused metadata tests cover this path and expiry. | Closed |
| Readiness was awaited before installing an item | `observeAndInstall` stores the observation identity, sets `installedItemGeneration`, and calls `runtime.install` before a normal ready callback requests play (lines 538-610). | Partially closed — a distinct already-ready timing race remains. |

### Required Artifacts

| Artifact | Expected | Status | Details |
| --- | --- | --- | --- |
| `SessionCoordinator.swift` | Preserve active sessions through ordinary operation failures | ✓ VERIFIED | Revalidation is non-mutating; closed results retain the actor-owned credential. A separate explicit-cleanup/new-login race remains a blocker. |
| `LiveListeningAdapter.swift` | Operation-scoped live context and task-local redirects | ✓ VERIFIED | Context owns resource/key/handoff; per-request delegates are used for catalog, live, and metadata transports. |
| `PlaybackCoordinator.swift` | One active AVPlayer owner with confirmed start and recovery | ✗ FAILED | One coordinator is wired, but `AVFoundationItemObservation` misses an already-ready item. |
| `ListeningPresentationModel.swift` and `ListeningView.swift` | Semantic browse/selection, metadata handoff, and controls | ✓ VERIFIED | The selection binding calls the lifecycle method; controls route through the composition-owned coordinator. |
| `MetadataPresentationModel.swift` | Independent text/artwork/freshness lifecycle | ✓ VERIFIED | Separate generation-bound tasks and fixed expiry schedule drive current, stale, fallback, and unavailable presentation. |
| `PlaybackInstallationOrderTests.swift` | Production-shaped playback order coverage | ⚠️ INSUFFICIENT | Tests cover readiness after installation and stale callbacks, but not readiness that already occurred before observer registration. |
| `SignOutTests.swift` | Explicit cleanup lifecycle coverage | ⚠️ INSUFFICIENT | Tests cover memory-first cleanup and blocked revalidation, but not a new successful attempt while a prior `erase()` remains blocked. |

### Key Link Verification

| From | To | Via | Status | Details |
| --- | --- | --- | --- | --- |
| Catalog transport | `ListeningPresentationModel.refresh` → `ListeningView` | semantic snapshot state | ✓ WIRED | Current/stale snapshot flows to the native list and freshness label. |
| List selection | `ListeningPresentationModel.select` → `MetadataPresentationModel.select` | explicit `channelSelection` binding | ✓ WIRED | Binding setter at `ListeningView.swift:10-20` invokes the lifecycle method. |
| Metadata reference | `SiriusXMClient.artwork` → native image | generation-bound artwork task | ✓ WIRED | Artwork is requested only after accepted metadata and rendered by `NativeArtworkImage`. |
| Resolver | `PlaybackCoordinator` → `AVFoundationPlaybackRuntime` | observe, install, ready, request play | ✗ FAILED | The final KVO transition is incomplete for an already-ready `AVPlayerItem`. |
| Recovery | resolver → recovered AVPlayer item → confirmed play | `installRecoveredItem` | ✗ FAILED | Uses the same incomplete KVO path as initial playback. |
| Explicit sign-out | cleanup task → credential/residue stores | detached concurrent cleanup | ✗ FAILED | Cleanup is not ordered against the subsequent `attemptSession` persistence write. |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
| --- | --- | --- | --- | --- |
| `ListeningView` | `state.snapshot.channels` | Fixed catalog transport → strict decoder → client → presentation model | Yes | ✓ FLOWING |
| `ListeningView` | metadata text/artwork | selected identity → metadata/artwork flows → validated `ArtworkData` | Yes | ✓ FLOWING |
| `PlaybackCoordinator` | current AVPlayer item | fixed resolver → opaque handoff → runtime install/play | No, on already-ready status timing | ✗ DISCONNECTED |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
| --- | --- | --- | --- |
| Package catalog/session/live/metadata behaviors | Existing recorded full package-suite evidence | Passed after source changes; not rerun by explicit user constraint | ✓ PASS (existing evidence) |
| Native composition/install/metadata behaviors | Existing recorded macOS app-suite evidence | Passed after source changes; not rerun by explicit user constraint | ✓ PASS (existing evidence) |
| Native provider-backed browse/playback | Bounded UAT | One user-operated sign-in was rejected; no catalog/tune/retry was authorized | BLOCKED, truthfully unobserved |

### Probe Execution

No Phase 02 probe scripts are declared. No probes were run.

### Requirements Coverage

| Requirement | Source Plan(s) | Description | Status | Evidence |
| --- | --- | --- | --- | --- |
| CAT-01 | 01, 02, 03, 04, 11 | Browse entitled standard/app-only linear channels only | ✓ SATISFIED | Strict positive filtering, native catalog path, and deterministic decoder/composition coverage. |
| CAT-02 | 01, 02, 03, 04, 11 | Stable identity and available presentation/entitlement/freshness | ✓ SATISFIED | Semantic channel model and catalog tests cover identity, optional presentation, entitlement, ordering, and freshness. |
| CAT-03 | 01, 04, 05, 08, 11 | Visible catalog/entitlement failures; cache never authorizes playback | ✓ SATISFIED | Stale catalog's playback authorization is false; ordinary operation revalidation preserves active sessions. |
| PLAY-01 | 01, 02, 03, 05, 09, 11 | Tune/start/pause/resume/stop one live stream | ✗ BLOCKED | Already-ready production AVFoundation item can remain idle. |
| PLAY-02 | 01, 05, 09, 11 | One coordinator serializes playback controls | ✗ BLOCKED | One coordinator exists, but does not reliably start every installed item. |
| PLAY-03 | 01, 06, 08, 09, 11 | Bounded cancellation-aware recovery | ✗ BLOCKED | Recovery installation inherits the already-ready item failure. |
| PLAY-04 | 01, 02, 03, 05, 06, 08, 09, 11 | Distinct actionable closed failures | ✓ SATISFIED | Closed failure mapping and per-operation/revalidation isolation are present and regression-covered. |
| META-01 | 01, 02, 03, 07, 10, 11 | Active channel, current text, and artwork | ✓ SATISFIED | Semantic selection, artwork fetch, byte validation, and native rendering are wired and tested. |
| META-02 | 01, 07, 10, 11 | Independent metadata with honest stale/unavailable state | ✓ SATISFIED | Generation-bound metadata has no playback mutator and expires during a blocked refresh. |

All nine requirement IDs declared by Phase 02 plans are accounted for. No orphaned Phase 02 requirement IDs were found in `REQUIREMENTS.md`.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
| --- | --- | --- | --- | --- |
| `SessionCoordinator.swift` | 59-79, 223-260 | Detached cleanup can erase a newer successful session | BLOCKER | A valid new session can lose persisted credential/residue after an older explicit sign-out completes. |
| `PlaybackCoordinator.swift` | 292-296 | KVO observes only future status changes | BLOCKER | Cached/rapidly-ready media can install without ever requesting playback. |
| `SiriusMac.xcodeproj/project.pbxproj` | 69 | Dangling group child object ID for `MetadataPresentationTests.swift` | WARNING | Xcode presents a broken test-group reference despite correct build-phase inclusion. |
| Phase implementation sources | — | `TBD`/`FIXME`/`XXX` scan | INFO | No unreferenced debt markers found. |

### Prohibition Audit

The phase's no-bypass, bounded-operation, no-synthesized-listener, and redaction constraints were preserved by this verification; no provider/UI action was taken. The explicit-session-retirement prohibition is not fully met under the older-cleanup/new-login race, and the reliable-playback contract is not fully met under the already-ready item race. No override is present.

### Human Verification Required

The one authorized native UAT is already closed and recorded as blocked: the user-operated sign-in was rejected, and no catalog/playback/metadata retry is authorized. It cannot supply a pass for live behavior, and this report does not request another attempt.

### Gaps Summary

Two root causes block the phase goal:

1. The AVFoundation KVO observer does not consume an already-ready item's status, so initial playback and recovery can remain permanently idle.
2. Cleanup from an earlier explicit sign-out is not sequenced against a new sign-in, so it can erase the newer session's persisted material.

The bounded UAT also stopped correctly at rejected authentication; it is evidence of an unresolved external authentication block, not evidence that catalog or playback worked.

No later roadmap phase explicitly owns these Phase 02 defects, so none are deferred.

## Escalation Gate

Do not proceed to Phase 03. Plan and implement the two blocker fixes, add the described regressions, then re-verify without launching another UAT or provider attempt unless separately authorized.

_Verified: 2026-08-20T13:09:29Z_
_Verifier: the agent (gsd-verifier)_
