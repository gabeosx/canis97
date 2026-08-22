---
phase: 03-native-mac-listening-experience
verified: 2026-08-22T14:09:58Z
status: gaps_found
score: 84/84 must-haves verified
behavior_unverified: 0
overrides_applied: 0
gaps:
  - truth: "The planned `SiriusMac/Library/PlaybackQueue.swift` artifact provides the captured queue implementation."
    status: partial
    reason: "The file is a three-line explanatory comment, is absent from the app target Sources build phase, and contains none of the advertised `PlaybackQueue` implementation. The working queue lives in `LibraryStore.swift` instead."
    artifacts:
      - path: "SiriusMac/Library/PlaybackQueue.swift"
        issue: "Stub/orphaned planned artifact; `verify.artifacts` reports missing `struct PlaybackQueue`."
    missing:
      - "Either move `PlaybackQueue`, `QueueDirection`, `QueueDirectionAvailability`, and `LibraryRevealRequest` into the named source file and add it to the target Sources phase, or record a developer-approved verification override for the intentional co-location in `LibraryStore.swift`."
prohibition_review:
  - statement: "Local favorites and listening history must not be uploaded, cloud-synchronized, used for recommendations, or transmitted as telemetry."
    evidence: "Source scan of the Phase 3 local-library/UI layers found no CloudKit, telemetry, analytics, upload, or HTTP client call; `LibraryStore` persists only allow-listed SwiftData fields. Judgment-tier sign-off remains required."
  - statement: "App and system surfaces must not claim playback, metadata, or queue movement from selection, intent, pending work, or renderer text."
    evidence: "Confirmed-state publication and pending-retention tests pass; judgment-tier sign-off remains required."
  - statement: "Normal product actions must remain keyboard- and VoiceOver-usable without a separate degraded accessibility mode."
    evidence: "Accessibility contracts and approved native checkpoint evidence support this; judgment-tier sign-off remains required."
---

# Phase 03: Native Mac Listening Experience Verification Report

**Phase Goal:** Subscribers can use a cohesive native macOS player and library while one shared playback session continues correctly across app and system control surfaces.
**Verified:** 2026-08-22T14:09:58Z
**Status:** gaps_found
**Re-verification:** No — initial verification

## Goal Achievement

The user-facing Phase 3 behavior is implemented and exercised. The status is not `passed` because one declared artifact is a real stub/orphan rather than the file its plan promised. This is a delivery-artifact gap, not evidence that the shared-session queue behavior is absent.

### Observable Truths

| # | Truth | Status | Evidence |
| --- | --- | --- | --- |
| 1 | One compact player shows confirmed channel, metadata, favorite state, failure recovery, and live controls. | ✓ VERIFIED | `CompactPlayerPresentation` maps confirmed semantic state; `CompactPlayerView` renders fixed 400 × 288 controls; presentation/accessibility tests and approved rendered checkpoint cover populated, pending, error, long-text, and empty states. |
| 2 | A separate native library browses entitled channels/categories and exposes Favorites and Recents. | ✓ VERIFIED | `LibraryView` implements Channels/Categories/Favorites/Recents, selected-tab filtering, search, explicit tune, clear recents, and recovery states; `LibraryStoreTests` and `PlaybackQueueTests` pass. |
| 3 | Both windows share exactly one session/player; lifecycle, deterministic navigation, reveal, and cancellation remain correct. | ✓ VERIFIED | `SiriusMacApp` holds one `ListeningSessionController`; its retained composition owns the coordinator. `ListeningSessionControllerTests` plus `PlaybackInstallationOrderTests` cover single ownership, no-yield navigation, request-scoped cancellation, stale publications, item failures, publication order, and synchronous Stop revocation. |
| 4 | Favorites and ordered confirmed-listen recents are local and secret-safe. | ✓ VERIFIED | `LibraryStore` persists only stable ID/name/number/category/rank/timestamp and bounded preferences; confirmed `.playing` observation alone records recents. Store tests cover idempotency, ordering, cap, clear, and allow-list behavior. |
| 5 | Background/library-close playback, system media, routing, keyboard, VoiceOver, focus, announcements, contrast, and Reduce Motion work through the same session. | ✓ VERIFIED | `SystemMediaController` exposes only live-appropriate commands and confirmed Now Playing; `AccessibilityAnnouncer` and UI commands are wired to the controller. Focused contracts, the final 182-test app suite, and approved native checkpoint evidence cover the platform-only paths. |

**Score:** 84/84 plan and roadmap truth clauses verified; 0 present-but-behavior-unverified.

### Required Artifacts

| Artifact | Expected | Status | Details |
| --- | --- | --- | --- |
| `SiriusMac/App/ListeningSessionController.swift` | App-lifetime session and semantic fan-out | ✓ VERIFIED | Substantive, compiled, and injected into both scene roots. |
| `SiriusMac/Library/LibraryStore.swift` | Local favorites/recents/preference boundary | ✓ VERIFIED | Substantive SwiftData facade with allow-listed records, compiled and consumed by controller/views. |
| `SiriusMac/Library/PlaybackQueue.swift` | Captured queue implementation | ✗ STUB / ORPHANED | Comment-only file and not in Sources; actual implementation is in `LibraryStore.swift`. |
| `SiriusMac/Player/CompactPlayerPresentation.swift`, `CompactPlayerView.swift` | Closed compact semantic presentation and native renderer | ✓ VERIFIED | Compiled presentation/view seam with verified action closures and accessibility controls. |
| `SiriusMac/Windows/CompactWindowController.swift` | Window/lifecycle adapter | ✓ VERIFIED | Compiled narrow AppKit bridge attached to compact and library roots. |
| `SiriusMac/Listening/SystemMediaController.swift` | System command/Now Playing adapter | ✓ VERIFIED | Compiled, single-registration adapter using typed controller closures. |
| `SiriusMac/Accessibility/AccessibilityAnnouncer.swift` | Deduplicated native announcements | ✓ VERIFIED | Compiled/injected announcement boundary. |
| Phase 3 XCTest files | Behavioral regression coverage | ✓ VERIFIED | All expected tests are registered; independent full app run: 182 passed. |
| `03-08-CHECKPOINT-EVIDENCE.md` | Native-only manual acceptance | ✓ VERIFIED | Records user approval of lifecycle, system controls/routing, UI, VoiceOver, and Reduce Motion checks. |

### Key Link Verification

| From | To | Via | Status | Details |
| --- | --- | --- | --- | --- |
| `SiriusMacApp` | `ListeningSessionController` | One retained controller passed to compact/library roots | ✓ WIRED | No scene creates a composition or coordinator. |
| Controller | `PlaybackCoordinator` | Retained `AuthenticationComposition.playbackCoordinator` | ✓ WIRED | Windows, menus, compact controls, and system-media closures converge on controller commands. |
| Presentation model | Metadata model | Immutable confirmed coordinator publications | ✓ WIRED | Browse selection cannot change active metadata; only confirmed state selects/clears it. |
| Controller | `LibraryStore` | One app-owned `LibraryStore` | ✓ WIRED | Favorites and confirmed recents fan back to compact/library projections. |
| Controller | Queue | Captured IDs, entitlement filtering, reveal request | ✓ WIRED | Behavior is wired through the queue declarations in `LibraryStore.swift`; the planned file placement is the sole gap. |
| System media | Controller/queue | Typed Play/Pause/Previous/Next closures | ✓ WIRED | Unavailable commands return failure; unsupported live commands are disabled. |
| Native controls/menus | Controller | Shared semantic routes | ✓ WIRED | Library, compact, menu, keyboard, and media routes use the same command availability. |
| Accessibility announcer | Controller | Confirmed semantic event generation | ✓ WIRED | Closed events are deduplicated and no renderer/provider text is used. |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
| --- | --- | --- | --- | --- |
| Compact player | confirmed channel/metadata/favorite/transport | Coordinator publication + `MetadataPresentationModel` + `LibraryStore` | Confirmed semantic state, not browse selection or hardcoded display data | ✓ FLOWING |
| Library view | entitled channel snapshot, tab/search/favorites/recents | `ListeningPresentationModel.state` and app-owned `LibraryStore` | Current entitled catalog and local records | ✓ FLOWING |
| System media | Now Playing info and command enablement | Confirmed coordinator state and semantic metadata | Confirmed title/artist/program/channel only | ✓ FLOWING |
| Queue navigation | candidate and reveal identity | Captured stable IDs reconciled to current entitled lineup | Candidate routes through coordinator authorization | ✓ FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
| --- | --- | --- | --- |
| App-wide Phase 3 behavior | `xcodebuild test -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS' -derivedDataPath /tmp/sirius-mac-phase03-verification CODE_SIGNING_ALLOWED=NO` | 182 tests, 0 failures | ✓ PASS |
| Client catalog/metadata/playback boundary | `swift test` in `Packages/SiriusXMClient` | 91 tests, 0 failures | ✓ PASS |
| Final ordering/cancellation repair | Focused `ListeningSessionControllerTests` and `PlaybackInstallationOrderTests` recorded in `03-REVIEW.md` | 31 tests, 0 failures; independent review clean | ✓ PASS |
| Native-only lifecycle/system/accessibility | Bounded running-app checkpoint | User approved both Task 1 and Task 2; semantic evidence recorded | ✓ PASS |

### Requirements Coverage

| Requirement | Source Plans | Status | Evidence |
| --- | --- | --- | --- |
| LIBR-01 | 03-02, 03-08 | ✓ SATISFIED | Stable-ID desired-state favorites in one local store, projected across surfaces. |
| LIBR-02 | 03-02, 03-03, 03-08 | ✓ SATISFIED | Confirmed-only, unique, ordered, capped recents; deterministic queue tests. |
| LIBR-03 | 03-02, 03-08 | ✓ SATISFIED (source/test evidence) | Allow-listed SwiftData records; no secret/session/stream fields. Human prohibition sign-off remains flagged below. |
| MAC-01 | 03-01, 03-05, 03-08 | ✓ SATISFIED | App-lifetime controller plus approved close/reopen/background checkpoint. |
| MAC-02 | 03-06, 03-08 | ✓ SATISFIED | Single supported media-command registration plus system checkpoint. |
| MAC-03 | 03-06, 03-08 | ✓ SATISFIED | Confirmed-state Now Playing with pending retention/terminal clearing tests. |
| MAC-04 | 03-01, 03-06, 03-08 | ✓ SATISFIED | Sole AVFoundation runtime, no custom routing engine, approved system-routing check. |
| UI-01 | 03-04, 03-05, 03-07, 03-08 | ✓ SATISFIED | Fixed compact semantic renderer and accepted legibility/accessibility evidence. |
| UI-02 | 03-03, 03-07, 03-08 | ✓ SATISFIED | Separate four-tab native library, search, rows, favorites, recents, and state handling. |
| UI-03 | 03-01, 03-04, 03-05, 03-08 | ✓ SATISFIED | Shared controller identity and native lifecycle evidence. |
| UI-04 | 03-03, 03-06, 03-08 | ✓ SATISFIED | No-wrap captured queue, current-entitlement filtering, fallback, reveal, shared system routes. |
| ACCS-01 | 03-07, 03-08 | ✓ SATISFIED | Keyboard/menu/focus/labels/announcements/Reduce Motion contracts plus approved VoiceOver check. |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
| --- | --- | --- | --- | --- |
| `SiriusMac/Library/PlaybackQueue.swift` | 1 | Comment-only declared implementation file | 🛑 Blocker | The plan artifact is not substantive or wired into the target, despite working equivalent code in `LibraryStore.swift`. |

### Human Review Flags

The native platform checks are already user-approved in `03-08-CHECKPOINT-EVIDENCE.md`; no new live-account or UI walkthrough is required for the implemented behavior.

Three plan-declared judgment-tier prohibitions cannot be silently greenlit by automated evidence. The source and tests support them, but a developer must explicitly accept the local-only privacy, confirmed-state truthfulness, and normal-product accessibility guarantees if a fully clean verifier status is required.

### Gaps Summary

The shared listening experience itself is present, wired, data-flowing, and independently tested. The blocking report is narrowly about an acknowledged plan artifact deviation: `PlaybackQueue.swift` is a no-op placeholder while the actual queue is co-located in `LibraryStore.swift`. No later phase clearly schedules this file-placement cleanup.

This looks intentional. To accept the alternative implementation without moving the declarations, add this override and re-verify:

```yaml
overrides:
  - must_have: "SiriusMac/Library/PlaybackQueue.swift provides captured, no-wrap, runtime-filtered previous/next navigation"
    reason: "The semantic queue is intentionally co-located in LibraryStore.swift with the local stable-ID boundary; all consumers and tests use the compiled implementation."
    accepted_by: "<developer>"
    accepted_at: "<ISO timestamp>"
```

---

_Verified: 2026-08-22T14:09:58Z_
_Verifier: the agent (gsd-verifier)_
