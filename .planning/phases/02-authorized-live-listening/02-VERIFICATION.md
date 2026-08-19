---
phase: 02-authorized-live-listening
verified: 2026-08-19T21:34:16Z
status: gaps_found
score: 0/5
behavior_unverified: 1
overrides_applied: 0
gaps:
  - truth: "A subscriber can tune an entitled linear channel and start, pause, resume, or stop one live stream."
    status: failed
    reason: "The production AVFoundation path observes an item before installing it, but the readiness callback that installs it requires the item to become ready first. The player therefore has no current item to load. Native AVFoundation success is also explicitly NOT OBSERVED."
    artifacts:
      - path: "SiriusMac/Listening/PlaybackCoordinator.swift"
        issue: "resolveAndInstall and installRecoveredItem defer runtime.install until onReady; AVFoundationItemObservation only emits ready after item status changes."
    missing:
      - "Install the current-generation item before awaiting readiness, then request play only after readiness and retain supersession guards."
      - "Add a production-runtime-shaped regression that cannot manually fire readiness before install."
  - truth: "Catalog, authorization, entitlement, resolution, network, decoder, buffering, and unsupported-upstream failures remain distinct and actionable without incorrectly signing the subscriber out."
    status: failed
    reason: "Current entitlement revalidation clears the active transient credential and changes state to signedOut for every non-entitled inspection result, including ordinary compatibility/control outcomes. This violates the session-preservation contract and turns an actionable operation failure into sign-out."
    artifacts:
      - path: "Packages/SiriusXMClient/Sources/SiriusXMClient/Session/SessionCoordinator.swift"
        issue: "withCurrentEntitledCredential clears transientCredential and assigns signedOut after any non-entitled result."
      - path: "Packages/SiriusXMClient/Sources/SiriusXMClient/InternalAdapters/LiveListeningAdapter.swift"
        issue: "CurrentSessionFixedLiveOperations stores mutable resource and handoff state across awaits, so overlapping live resolutions can use another command's context."
    missing:
      - "Keep the active session for inconclusive, ordinary 4xx, rate-limit, protected-control, and unsupported outcomes; only explicit local sign-out/clear may retire credentials."
      - "Make tune/resource/key context operation-scoped and add an out-of-order concrete-operations regression."
  - truth: "Recoverable expiry, network interruption, sleep/wake, and stalls make bounded, cancellation-aware same-channel recovery without infinite retry or synthesized listener activity."
    status: failed
    reason: "The coordinator has finite policy and cancellation code, but every successful recovery follows the same observe-before-install AVFoundation cycle, so recovery cannot actually restore an installed live item in production."
    artifacts:
      - path: "SiriusMac/Listening/PlaybackCoordinator.swift"
        issue: "installRecoveredItem also waits for onReady before runtime.install."
    missing:
      - "Repair the production installation order and cover recovery with a runtime double whose ready event is impossible before installation."
  - truth: "While listening, a subscriber sees the active channel, best available artwork, and current program or song text; stale or unavailable metadata is explicit and does not interrupt healthy audio."
    status: failed
    reason: "The actual SwiftUI selection binding writes selectedChannelID directly and never calls ListeningPresentationModel.select, artwork bytes are never fetched or rendered, and a hung metadata request never advances current data to stale or unavailable."
    artifacts:
      - path: "SiriusMac/Catalog/ListeningView.swift"
        issue: "List selection binds directly to model.selectedChannelID and renders an artwork status label instead of image data."
      - path: "SiriusMac/Metadata/MetadataPresentationModel.swift"
        issue: "refresh only marks artwork available and awaits metadata indefinitely; it never invokes flow.artwork or independently schedules freshness expiry."
      - path: "Packages/SiriusXMClient/Sources/SiriusXMClient/InternalAdapters/LiveListeningAdapter.swift"
        issue: "Metadata transport has no explicit request/resource timeout; artwork invalidation is not tied to client sign-out."
    missing:
      - "Route List selection through model.select, fetch and retain validated ArtworkData in a separate generation-bound task, render it natively, and cancel/invalidate on selection and sign-out."
      - "Use an injected clock/expiry task plus bounded transport timeout so a blocked refresh becomes stale at 90 seconds and unavailable at five minutes."
behavior_unverified_items:
  - truth: "A subscriber can refresh and browse only their entitled standard and app-only channel-linear lineup with identity, available presentation details, entitlement, and freshness visible."
    test: "In an entitled native session, refresh the Channels view and inspect standard/app-only, filtered, stale, empty, and failure states."
    expected: "Only admitted channel-linear records appear, with stable identity and visible freshness; Xtra/replay/on-demand never appear and a failed refresh retains only visibly stale browse data."
    why_human: "Static tracing shows catalog decoder -> SiriusXMClient.catalog -> ListeningPresentationModel -> ListeningView, but this verifier was instructed not to launch the app, run tests, or make a provider request."
---

# Phase 02: Authorized Live Listening Verification Report

**Phase Goal:** Subscribers can find their entitled linear SiriusXM channels and reliably listen to one live stream with clear state and current metadata.
**Verified:** 2026-08-19T21:34:16Z
**Status:** gaps_found
**Re-verification:** No — initial verification

## MVP Mode Prerequisite

Phase 02 is marked `mvp`, but its roadmap goal is not a valid user story. The canonical user-story validator returned `valid: false` because the goal has no `As a …, I want to …, so that …` structure. Consequently a standards-compliant MVP UAT flow cannot be generated from the goal; the coverage below uses the roadmap success criteria directly. This is a workflow-definition discrepancy, not an acceptance of the implementation.

## User Flow Coverage

| Step | Expected | Evidence in codebase | Status |
| --- | --- | --- | --- |
| Refresh lineup | Native Channels view refreshes semantic catalog state | `AuthenticationView` composes a shared `SiriusXMClient`; `ListeningPresentationModel.refresh` calls `ListeningFlow.catalog`; `ListeningView` renders the resulting snapshot | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED |
| Select a channel | Selection starts independent metadata work for that identity | `ListeningView` writes directly to `selectedChannelID`; metadata startup exists only in `ListeningPresentationModel.select` | ✗ FAILED |
| Tune and hear live stream | A current AVPlayer item loads, then reaches confirmed playing state | `PlaybackCoordinator.resolveAndInstall` observes before `runtime.install`; production observation can only report ready after loading starts | ✗ FAILED |
| Recover from interruption | Same selected channel re-resolves within the bounded policy | Recovery repeats the same observe-before-install sequence | ✗ FAILED |
| See current text and artwork | Text/artwork render, age independently, and do not control audio | Metadata model never calls `flow.artwork`; view renders a label; blocked metadata awaits forever | ✗ FAILED |

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
| --- | --- | --- | --- |
| 1 | Subscriber can refresh and browse only entitled standard/app-only `channel-linear` records with identity and freshness. | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | Static data flow is substantive: strict catalog decoder and `SiriusXMClient.catalog()` feed `ListeningPresentationModel` and `ListeningView`. No app/runtime/provider check was permitted in this verification. |
| 2 | Subscriber can tune, start, pause, resume at live edge, and stop one live stream. | ✗ FAILED | `PlaybackCoordinator.swift:518-547` waits for `onReady` before `runtime.install`; `AVFoundationItemObservation` receives ready from item status after loading begins. Native AVFoundation remains `NOT OBSERVED` in `02-LIVE-CONTRACT.md`. |
| 3 | Failure domains remain distinct and actionable; cached browse presence never authorizes playback. | ✗ FAILED | Catalog snapshots correctly expose `allowsPlaybackAuthorization == false`, but `SessionCoordinator.swift:166-171` clears the active credential and signs out on non-entitled revalidation results; concrete tune state is also shared across awaits at `LiveListeningAdapter.swift:502-571`. |
| 4 | Recovery is bounded, cancellation-aware, same-channel, and non-synthetic. | ✗ FAILED | Finite policy/guards exist, but `PlaybackCoordinator.swift:637-663` repeats the broken readiness-before-install path, preventing actual recovery installation. |
| 5 | Active channel, current program/song text, and best available artwork are shown with honest stale/unavailable metadata. | ✗ FAILED | `ListeningView.swift:41` bypasses metadata selection; `MetadataPresentationModel.swift:64-76` never fetches artwork; `55-60` awaits a hung request without independent expiry. |

**Score:** 0/5 truths verified (1 present, behavior-unverified)

### Required Artifacts

| Artifact | Expected | Status | Details |
| --- | --- | --- | --- |
| `Packages/SiriusXMClient/Sources/SiriusXMClient/Public/LiveListeningModels.swift` | Closed semantic catalog/playback/metadata models and opaque handoff | ✓ SUBSTANTIVE | Defines opaque handoff, catalog/metadata/artwork values, closed failures, and browse-only catalog authorization. |
| `Packages/SiriusXMClient/Sources/SiriusXMClient/InternalAdapters/LiveListeningAdapter.swift` | Strict fixed catalog/live/metadata adapters | ⚠️ PARTIAL | Wired through `SiriusXMClient`, but live resolution has actor-reentrancy corruption and metadata transport/artwork invalidation defects. |
| `Packages/SiriusXMClient/Sources/SiriusXMClient/Session/SessionCoordinator.swift` | Current-session authorization that preserves credentials on ordinary operation failure | ✗ FAILED | Revalidation mutates the session to signed out for all non-entitled classifications. |
| `SiriusMac/Listening/PlaybackCoordinator.swift` | One current AVPlayer owner with confirmed command and recovery path | ✗ FAILED | One runtime is composed, but production installation cannot reach readiness. |
| `SiriusMac/Catalog/ListeningPresentationModel.swift` and `SiriusMac/Catalog/ListeningView.swift` | Native catalog selection and metadata handoff | ✗ FAILED | The view bypasses `select(_:)`, leaving the metadata task orphaned in the ordinary selection path. |
| `SiriusMac/Metadata/MetadataPresentationModel.swift` | Independent metadata/artwork/freshness presentation | ✗ FAILED | No artwork data flow and no expiry while a fetch is suspended. |
| `SiriusMacTests/ListeningCompositionTests.swift` and `SiriusMacTests/MetadataPresentationTests.swift` | Behavioral regression coverage for native wiring | ⚠️ INSUFFICIENT | Tests are substantive but use a runtime that manually emits ready before install and call `model.select` directly; the two production wiring failures are not exercised. |

### Key Link Verification

| From | To | Via | Status | Details |
| --- | --- | --- | --- | --- |
| `AuthenticationComposition` | `SiriusXMClient` / one `PlaybackCoordinator` | Production composition | ✓ WIRED | `AuthenticationView.swift:152-167` builds one client and injects it into one coordinator. |
| `ListeningPresentationModel.refresh` | `SiriusXMClient.catalog` | `ListeningFlow.catalog` | ✓ WIRED | `ListeningPresentationModel.swift:67-84` awaits catalog and publishes current-generation state. |
| `ListeningView` selection | `ListeningPresentationModel.select` / metadata lifecycle | List binding | ✗ NOT_WIRED | `ListeningView.swift:41` binds `$model.selectedChannelID`; only `ListeningPresentationModel.select` at lines 87-90 starts metadata. |
| `PlaybackCoordinator.tune` | `SiriusXMClient.resolveLiveStream` then `AVPlayer.replaceCurrentItem` | Resolver and runtime | ✗ FAILED | Resolver call is wired, but `replaceCurrentItem` is deferred until an unavailable readiness event. |
| `SiriusXMClient.artwork` | `MetadataPresentationModel` then native image | Opaque artwork reference | ✗ NOT_WIRED | Client/fetcher seam exists, but `MetadataPresentationModel` never calls `flow.artwork`, and the view never renders `ArtworkData`. |
| `SiriusXMClient.signOut` | in-flight metadata/artwork invalidation | Session generation | ⚠️ PARTIAL | Sign-out invalidates live resolution, not `CurrentSessionMetadataFetcher`; artwork only checks metadata-fetch generation. |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
| --- | --- | --- | --- | --- |
| `ListeningView` | `model.state.snapshot.channels` | Fixed catalog transport → strict decoder → `SiriusXMClient.catalog` → model state | Yes, subject to authorized runtime observation | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED |
| `PlaybackCoordinator` | AVPlayer current item / `state` | Resolver → opaque handoff → item observation/install | No: item installation is gated on the item becoming ready before it is installed | ✗ DISCONNECTED |
| `ListeningView` metadata | `model.metadataPresentation.state` | Intended selection → metadata task | No: ordinary List selection bypasses the only task-starting method | ✗ HOLLOW_PROP |
| `ListeningView` artwork | artwork display | Intended `ArtworkData` from `flow.artwork` | No: no invocation or image rendering exists | ✗ DISCONNECTED |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
| --- | --- | --- | --- |
| App, package, and live playback behavior | Not run by delegated verification constraints | No tests, app launch, provider/network, Keychain, or AVFoundation actions were allowed | SKIPPED |

### Probe Execution

No Phase 02 probe scripts are declared by its plans or summaries. No probes were run.

### Requirements Coverage

| Requirement | Source Plan(s) | Description | Status | Evidence |
| --- | --- | --- | --- |
| CAT-01 | 01, 02, 03, 04 | Refresh and browse only entitled standard/app-only `channel-linear` lineup | ? NEEDS HUMAN | Strict filter and native list are wired, but live/native behavior was not runnable under this verification. |
| CAT-02 | 01, 02, 03, 04 | Stable identity, presentation fields, entitlement, freshness | ? NEEDS HUMAN | Semantic models/decoder carry fields and freshness; the actual entitled runtime flow was not exercised. |
| CAT-03 | 01, 04, 05 | Catalog/entitlement failures visible; cache never authorizes playback | ✗ BLOCKED | Browse cache is non-authoritative, but ordinary revalidation can force signed-out state and loses the active session. |
| PLAY-01 | 01, 02, 03, 05 | Tune/start/pause/resume/stop one live stream | ✗ BLOCKED | Production AVPlayer readiness/install dependency cycle; no native AVFoundation proof. |
| PLAY-02 | 01, 05 | One coordinator serializes all playback controls | ✗ BLOCKED | One coordinator exists, but its sole production player cannot install the resolved item. |
| PLAY-03 | 01, 06 | Bounded cancellation-aware recovery | ✗ BLOCKED | Bounded policy exists but recovery uses the same broken item-install path. |
| PLAY-04 | 01, 02, 03, 05, 06 | Distinct actionable closed failures | ✗ BLOCKED | Revalidation incorrectly collapses ordinary operation outcomes into sign-out; concurrent resolution can corrupt operation context. |
| META-01 | 01, 02, 03, 07 | Active channel/current text/artwork while listening | ✗ BLOCKED | UI selection does not start metadata; artwork is only advertised, never fetched/rendered. |
| META-02 | 01, 07 | Metadata independent from audio and explicit stale/unavailable state | ✗ BLOCKED | Metadata has no playback mutator, but a hung fetch can leave values current forever and sign-out does not invalidate artwork. |

All nine requirement IDs declared in Phase 02 PLAN frontmatter are mapped above. No orphaned Phase 02 requirement IDs were found in `REQUIREMENTS.md`.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
| --- | --- | --- | --- | --- |
| `SiriusMac/Listening/PlaybackCoordinator.swift` | 518-547, 637-663 | Readiness-before-install dependency cycle | BLOCKER | Prevents initial playback and recovery from installing a live item in the real AVFoundation runtime. |
| `Packages/SiriusXMClient/Sources/SiriusXMClient/Session/SessionCoordinator.swift` | 166-171 | Ordinary revalidation mutates active session to signed out | BLOCKER | Breaks token/session preservation and conflates compatibility failures with logout. |
| `Packages/SiriusXMClient/Sources/SiriusXMClient/InternalAdapters/LiveListeningAdapter.swift` | 502-571 | Actor-wide mutable resolution context across awaits | BLOCKER | Out-of-order tunes can use another command's resource/key state. |
| `SiriusMac/Catalog/ListeningView.swift` | 41 | Direct selection binding bypasses lifecycle method | BLOCKER | Normal user selection does not initiate metadata. |
| `SiriusMac/Metadata/MetadataPresentationModel.swift` | 55-86 | No independent freshness expiry; no artwork fetch | BLOCKER | Metadata can lie about freshness and no actual artwork reaches the view. |
| Phase 02 source files reviewed | — | `TBD`/`FIXME`/`XXX` debt-marker scan | INFO | No unreferenced debt markers found in the inspected phase implementation files. |

### Prohibition Audit

The Phase 02 plans carry judgment-tier safety prohibitions. Source inspection confirms that runtime provider work is not performed by SwiftUI and no live actions were taken in this verification. Two prohibitions are materially violated by code: ordinary operation failure can sign the active session out, and metadata can remain current past its freshness ceiling while a request hangs. These are included as blocking gaps above; no prohibition override exists.

### Gaps Summary

The phase goal is not achieved. Four root concerns block it: the AVFoundation readiness/install cycle prevents live playback and recovery; session revalidation discards the active session for ordinary non-entitled outcomes; shared resolution context is unsafe under concurrent tunes; and the shipped SwiftUI/metadata path neither starts metadata on normal selection nor fetches/renders artwork or expires hung data.

No later roadmap phase explicitly takes ownership of these Phase 02 contract failures, so none are deferred.

## Escalation Gate

Do not proceed to Phase 03 on this implementation. Return the gaps to planning/fix work, then re-verify with production-shaped offline regressions. A new live playback attempt requires separate user authorization; it is not part of this verification.

_Verified: 2026-08-19T21:34:16Z_
_Verifier: the agent (gsd-verifier)_
