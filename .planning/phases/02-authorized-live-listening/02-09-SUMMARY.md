---
phase: 02-authorized-live-listening
plan: "09"
subsystem: playback-coordination
tags: [swift, avfoundation, xctest, playback, concurrency]
requires:
  - "02-05 single AVPlayer playback coordinator"
  - "02-06 generation-bound recovery policy"
  - "02-08 operation-scoped live resolution"
provides:
  - "Install-before-ready ordering for initial, resume, and recovery playback items"
  - "Observation-identity, generation, selection, and recovery-incident callback guards"
  - "Synchronous session-end playback invalidation before authentication cleanup"
affects: [03-native-control-surfaces, playback, authentication-lifecycle]
tech-stack:
  added: []
  patterns:
    - "Install-gated runtime doubles for deterministic AVFoundation ordering tests"
    - "One shared observe-install callback path for tune and recovery"
key-files:
  created:
    - SiriusMacTests/PlaybackInstallationOrderTests.swift
  modified:
    - SiriusMac/Listening/PlaybackCoordinator.swift
    - SiriusMac/Catalog/ListeningPresentationModel.swift
    - SiriusMac.xcodeproj/project.pbxproj
decisions:
  - "An AVPlayerItem is installed while current before its readiness observation may request play."
  - "Ready, playback, pause, and failure callbacks require the exact current observation identity in addition to generation and selected identity."
  - "Playback session invalidation is synchronous and remains separate from credential erasure."
metrics:
  duration: "~12 min"
  completed: "2026-08-19"
status: complete
actuals:
  tokens: 7552
  tasks: 2
  commits: 3
---

# Phase 02 Plan 09: Install-Before-Ready Playback Repair Summary

One shared coordinator path now installs a current item before readiness, prevents stale callbacks from requesting or publishing playback, and revokes pending media synchronously at session end.

## Tasks Completed

1. **Install one resolved item before accepting readiness**
   - Added an install-gated runtime double that cannot emit ready until the exact observed item has been installed.
   - Refactored initial tune and live-edge resume to observe, retain, mark installed, and install the current item before waiting for ready.
   - Kept `.playing` publication exclusively on a confirmed runtime playing callback.
   - Commits: `ccb9bd0`, `368623f`.

2. **Apply the same order to recovery and reject every late callback**
   - Routed recovery through the same observe-install path and preserved incident, selected-channel, generation, and observation-identity checks.
   - Made pause-before-ready supersede the pending item, and made repeated stop/session-end boundaries idempotent.
   - Added synchronous `invalidateForSessionEnd()` and called it from `ListeningPresentationModel.reset()` before asynchronous authentication cleanup can begin.
   - Commit: `fece4c2`.

## Verification

- `plutil -lint SiriusMac.xcodeproj/project.pbxproj` — passed.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS' -only-testing:SiriusMacTests/PlaybackInstallationOrderTests CODE_SIGNING_ALLOWED=NO` — passed, 7 focused tests.
- The focused suite uses only resolver/runtime/catalog doubles. It does not create `AuthenticationComposition`, `KeychainCredentialStore`, `AVFoundationPlaybackRuntime`, system recovery observers, a provider request, a media load, or a production app session.
- AVFoundation audibility and live controls remain **NOT OBSERVED**; offline ordering tests do not claim live playback success.

## Deviations from Plan

### Auto-fixed Issues

1. **[Rule 1 - Bug] Pause-before-ready needed an explicit play-requested guard.**
   - **Found during:** Task 2 late-callback regression.
   - **Issue:** Installation alone made `pause()` treat an item as active, so a subsequent ready callback could request playback after the pause.
   - **Fix:** Track the current generation for which playback was actually requested; pause supersedes an installed-but-not-yet-ready item.
   - **Files modified:** `SiriusMac/Listening/PlaybackCoordinator.swift`, `SiriusMacTests/PlaybackInstallationOrderTests.swift`.
   - **Commit:** `fece4c2`.

## Known Stubs

None.

## Self-Check: PASSED

- Required source, test, and project-registration artifacts exist.
- Task commits `ccb9bd0`, `368623f`, and `fece4c2` are present in history.
- No tracked file deletions were introduced by this plan.
