---
phase: 02-authorized-live-listening
plan: "06"
subsystem: playback-recovery
tags: [swift, avfoundation, network, appkit, recovery, offline-tests]
requires:
  - "02-05 composition-owned AVPlayer coordinator and cancellation guards"
provides:
  - "Finite, same-channel recovery policy with synthetic-clock coverage"
  - "Network and workspace eligibility signals routed through one coordinator"
  - "Production-only system observer composition without test-host retention"
affects: [03-native-control-surfaces, playback]
tech-stack:
  added: []
  patterns:
    - "Injected sleeper and closed recovery signals"
    - "Generation-bound recovery incident with finite resolver budget"
key-files:
  created:
    - .planning/phases/02-authorized-live-listening/02-06-SUMMARY.md
  modified:
    - SiriusMac/Authentication/AuthenticationView.swift
    - SiriusMac/Listening/PlaybackCoordinator.swift
    - SiriusMacTests/ListeningCompositionTests.swift
decisions:
  - "Recovery may re-resolve only the currently selected identity, within one incident's two-attempt budget."
  - "Network and workspace callbacks are eligibility inputs only and never call the resolver directly."
  - "Only live app composition instantiates NWPathMonitor and NSWorkspace observers; generic coordinators use inert injected seams."
metrics:
  duration: "~22 min"
  completed: "2026-08-19"
status: complete
actuals:
  tokens: 6515
  tasks: 2
  commits: 8
---

# Phase 02 Plan 06: Bounded Playback Recovery Summary

The native coordinator now recovers only the current selected channel through one finite, cancellation-safe incident; provider resolution remains an explicit, opaque, one-attempt primitive.

## Tasks Completed

1. **Make re-resolution cancellation and terminal classes policy-safe**
   - Verified this task was already satisfied by the corrected 02-05 resolver: post-await cancellation and generation guards exist after tune, resource, and optional-key work; invalidation makes opaque handoffs unusable.
   - Added no duplicate code or test commit after the new intended RED cases correctly passed against that existing behavior.
   - Re-ran the focused package contract suite: 11 tests passed.

2. **Recover the current channel within one finite incident budget**
   - Added an injected recovery policy with an eight-second stall grace, one- then three-second backoffs, and at most two re-resolution attempts.
   - Coalesced duplicate signals into one incident, retained only the selected identity, and generation-guarded every delay, resolution, item observation, and state publication.
   - Made offline, sleep, stop, command supersession, and terminal authorization/protection outcomes cancel recovery before later provider work.
   - Added Network path and NSWorkspace sleep/wake adapters that supply eligibility signals only; they cannot resolve media or manipulate the player directly.
   - Follow-up coverage proves pause cancels an active recovery before it can install/play, and that one real offline-to-online transition begins one same-channel incident without needing a second stall signal.
   - System Network and workspace observers are now composed only in the live client branch. Generic coordinators—including unit-test and fake-client composition—use inert observer seams and cannot start those system services implicitly.
   - Commits: `7ee9117` (RED), `c6b1d9f` (GREEN), `0aa1acd` (signal-adapter correction), `3470dc8` (follow-up RED), `a7a4c11` (follow-up GREEN), `8f9b4f1` (production-observer RED), `64bec83` (production-only observer GREEN), `8614460` (teardown-test correction).

## Verification

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/SiriusXMClient --filter LivePlaybackCoordinatorTests` — passed, 11 tests.
- The focused Xcode suite ran under a 90-second process bound and exited `0`: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS' -only-testing:SiriusMacTests/ListeningCompositionTests` — passed, 30 tests; no `xcodebuild` or `SiriusMacTests` process remained.
- All behavior verification used synthetic resolver, player, and delay collaborators. No provider request, media load, live AVFoundation attempt, browser/DOM action, Keychain access, or user application session occurred.

## Deviations from Plan

### Auto-fixed Issues

1. **[Rule 1 - Lifecycle cleanup] Made observer teardown concurrency-safe.**
   - **Found during:** Task 2 signal-adapter compilation.
   - **Issue:** Swift 6 does not allow a nonisolated deinitializer to synchronously call main-actor observer cleanup.
   - **Fix:** Required observer seams to be Sendable and schedule only their token/monitor cancellation on the main actor after coordinator teardown.
   - **Files modified:** `SiriusMac/Listening/PlaybackCoordinator.swift`
   - **Commit:** `0aa1acd`

2. **[Rule 1 - Supersession and reconnect eligibility] Closed two recovery races found during manager review.**
   - **Found during:** Post-plan D-06/D-08 acceptance spot-check.
   - **Issue:** A pause could leave an active recovery task able to install/play a late item; a real reconnect needed a second stall signal before recovery began.
   - **Fix:** Pause cancels active/pending recovery and recovered-item callbacks require the current incident. An offline transition records one pending incident, consumed only by the next eligible reconnect; stop and channel switch clear it.
   - **Files modified:** `SiriusMac/Listening/PlaybackCoordinator.swift`, `SiriusMacTests/ListeningCompositionTests.swift`
   - **Commits:** `3470dc8`, `a7a4c11`

3. **[Rule 1 - Test teardown] Corrected the reconnect delay expected by the offline-stop test.**
   - **Found during:** Post-plan test-host lifecycle verification.
   - **Issue:** Reconnect correctly starts its pending incident at the one-second retry backoff, but the test waited forever for an eight-second stall grace that cannot occur on that path, leaving the focused Xcode host alive after the visible assertions.
   - **Fix:** The test now awaits the reconnect backoff, stops the coordinator before releasing that delay, and verifies no later resolver call can escape teardown. Separately, live system observers are explicitly composed at the production boundary and generic coordinator defaults are inert.
   - **Files modified:** `SiriusMacTests/ListeningCompositionTests.swift`, `SiriusMac/Listening/PlaybackCoordinator.swift`, `SiriusMac/Authentication/AuthenticationView.swift`
   - **Commits:** `8f9b4f1`, `64bec83`, `8614460`

### Plan Drift

- Task 1's intended RED tests passed immediately because the post-await cancellation and supersession safeguards were already delivered in Plan 02-05. The task was verified rather than duplicated.

## Known Stubs

None.

## Live Evidence Boundary

This plan is offline-complete only. AVFoundation playback/audibility remains **NOT OBSERVED** live; no additional provider action is authorized or implied by these tests.

## Self-Check: PASSED

- Required source, test, and summary artifacts exist.
- Task commits `7ee9117`, `c6b1d9f`, `0aa1acd`, `3470dc8`, `a7a4c11`, `8f9b4f1`, `64bec83`, and `8614460` are present in history.
