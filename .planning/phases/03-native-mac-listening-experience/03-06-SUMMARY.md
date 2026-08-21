---
phase: 03-native-mac-listening-experience
plan: 06
subsystem: media-integration
tags: [macos, mediaplayer, now-playing, remote-commands, avfoundation]
requires:
  - phase: 03-05
    provides: app-lifetime listening-session and native window lifecycle ownership
provides:
  - one composition-owned MediaPlayer remote-command registration
  - confirmed-state Now Playing publication with semantic metadata fallbacks
  - injected media command and info-center adapters for deterministic tests
affects: [03-07-accessibility, 03-08-native-verification]
actuals:
  tokens: 9623
  tasks: 2
  commits: 5
tech-stack:
  added: [MediaPlayer]
  patterns: [composition-owned system adapter, confirmed semantic state projection, injectable global framework adapters]
key-files:
  created:
    - SiriusMac/Listening/SystemMediaController.swift
    - SiriusMacTests/SystemMediaControllerTests.swift
  modified:
    - SiriusMac/App/ListeningSessionController.swift
    - SiriusMac/SiriusMacApp.swift
    - SiriusMac/Metadata/MetadataPresentationModel.swift
    - SiriusMac.xcodeproj/project.pbxproj
key-decisions:
  - Keep MPRemoteCommandCenter registration at app composition scope and route it through the existing listening session.
  - Publish only bounded semantic metadata derived from confirmed playback, never browse or renderer state.
  - Retain the prior system item during pending replacement tunes and clear it for terminal/no-active states.
metrics:
  duration: 14m
  completed: 2026-08-21
status: complete
---

# Phase 03 Plan 06: Native System Media Integration Summary

One app-owned MediaPlayer bridge now delivers live-appropriate controls and truthful confirmed Now Playing metadata without adding a second audio or routing stack.

## Accomplishments

- Added an injectable `SystemMediaController` that registers exactly Play/Pause, Previous, and Next once, disables seek/scrub/skip/Stop, and removes retained targets on shutdown.
- Routed system actions through the existing `ListeningSessionController`, `PlaybackCoordinator`, and filtered `PlaybackQueue` paths.
- Added a closed `NowPlayingSemanticMetadata` projection and mapped confirmed title, artist, current-program fallback, channel context, bounded artwork, live state, and rate to `MPNowPlayingInfoCenter`.
- Kept previous confirmed system metadata while a replacement tune is pending; clear metadata and supported commands for terminal or no-active state.
- Added deterministic fake MediaPlayer tests for lifecycle, command routing, fallback precedence, Unicode preservation, artwork context, pending retention, and terminal clearing.

## Task Commits

1. **Task 1 RED — remote command tests** — `f295606` (`test`)
2. **Task 1 GREEN — system command routing** — `cab5594` (`feat`)
3. **Task 2 RED — Now Playing metadata tests** — `f28bc34` (`test`)
4. **Task 2 GREEN — confirmed Now Playing publication** — `f786003` (`feat`)

## Verification

- `xcodebuild test -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS' -only-testing:SiriusMacTests/SystemMediaControllerTests` — passed (5 tests).
- `xcodebuild test -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS'` — passed (153 tests).
- Plan 03-08 remains the designated live macOS media-key, Control Center, and audio-routing evidence step; no manual system-surface claim is made here.

## Decisions Made

- Keep MediaPlayer ownership at application composition scope, so window lifecycle cannot duplicate or remove global remote-command targets.
- Derive system metadata from confirmed semantic state only; browse selection, command intent, renderer text, skins, provider responses, stream URLs, and credentials cannot reach Now Playing.
- Use a paused live rate of `0` and a playing live rate of `1`, while retaining prior confirmed content during an in-flight tune.

## Deviations from Plan

### Auto-fixed Issues

1. **[Rule 1 - Bug] Corrected newly introduced MediaPlayer and project-reference compile issues**
   - **Found during:** Tasks 1 and 2
   - **Issue:** Initial source registration and MediaPlayer adapter calls contained malformed identifiers and API/type mismatches.
   - **Fix:** Repaired the project references, used the current `MPMediaItemArtwork` initializer, and made semantic projection optionals explicit.
   - **Files modified:** `SiriusMac.xcodeproj/project.pbxproj`, `SiriusMac/Listening/SystemMediaController.swift`, `SiriusMac/Metadata/MetadataPresentationModel.swift`
   - **Commit:** `cab5594`, `f786003`

2. **[Rule 2 - Missing critical functionality] Started the system controller from application composition**
   - **Found during:** Task 1
   - **Issue:** Constructing injectable adapters without starting the app-owned controller would leave production MediaPlayer integration inactive.
   - **Fix:** Start system controls once from `SiriusMacApp` after the app-lifetime session controller is created.
   - **Files modified:** `SiriusMac/SiriusMacApp.swift`
   - **Commit:** `cab5594`

## Known Stubs

None.

## Self-Check: PASSED

All listed source/test/project files exist and all four task commits are present in Git history.
