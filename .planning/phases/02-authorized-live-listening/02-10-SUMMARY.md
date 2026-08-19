---
phase: 02-authorized-live-listening
plan: "10"
subsystem: metadata-presentation
tags: [swift, swiftui, appkit, urlsession, xctest, swift-testing]
requires:
  - "02-08 operation-scoped live-material and redirect isolation"
  - "02-09 synchronous playback invalidation at session end"
provides:
  - "Semantic List selection that starts one metadata generation without playback authority"
  - "Validated ArtworkData rendering through a native AppKit/SwiftUI boundary"
  - "Generation-invalidatable metadata/artwork fetches and finite metadata transport"
  - "Independent 30/90/300-second metadata freshness scheduling"
affects: [02-11, native-control-surfaces, metadata, authentication-lifecycle]
tech-stack:
  added: []
  patterns:
    - "Generation-bound metadata, artwork, polling, and expiry tasks"
    - "Injected clock and sleeper seams for deterministic freshness tests"
    - "Opaque artwork references resolved only to bounded ArtworkData before UI rendering"
key-files:
  created: []
  modified:
    - Packages/SiriusXMClient/Sources/SiriusXMClient/Public/LiveListeningModels.swift
    - Packages/SiriusXMClient/Sources/SiriusXMClient/Public/SiriusXMClient.swift
    - Packages/SiriusXMClient/Sources/SiriusXMClient/InternalAdapters/LiveListeningAdapter.swift
    - Packages/SiriusXMClient/Tests/SiriusXMClientTests/MetadataRefreshCoordinatorTests.swift
    - SiriusMac/Metadata/MetadataPresentationModel.swift
    - SiriusMac/Catalog/ListeningPresentationModel.swift
    - SiriusMac/Catalog/ListeningView.swift
    - SiriusMacTests/MetadataPresentationTests.swift
key-decisions:
  - "SwiftUI selection writes only through explicit select/clear semantic methods and never tunes playback."
  - "Metadata and artwork are independently generation-bound; session retirement invalidates both before cleanup."
  - "Freshness is enforced by a separate injected expiry schedule rather than waiting for the next network result."
requirements-completed: [META-01, META-02]
actuals:
  tokens: 10114
  tasks: 3
  commits: 3
metrics:
  duration: "~10 min"
  completed: "2026-08-19"
status: complete
---

# Phase 02 Plan 10: Selected Metadata Lifecycle Summary

Semantic channel selection now produces native, validated artwork and truthful metadata freshness while remaining completely independent from playback state.

## Tasks Completed

1. **Trace one List selection to current text and native artwork**
   - Routed list selection through a testable semantic binding and made the selected identity read-only outside select/clear methods.
   - Replaced artwork labels with `ArtworkData`, fetched artwork separately after accepted text, and decoded only bounded bytes at the native image boundary.
   - Commit: `59db851`.

2. **Invalidate metadata/artwork on switch and sign-out with bounded transport time**
   - Added explicit metadata invalidation before client session cleanup and generation checks around every metadata/artwork await.
   - Added a private cookie-free, credential-free, cache-free ephemeral URLSession configuration with 15-second request/resource limits.
   - Commit: `e56503c`.

3. **Expire current metadata while the next refresh is still blocked**
   - Split initial fetch, polling, artwork, and expiry into independently cancellable generation-bound tasks.
   - Added injected clock/sleeper test seams and verified stale at 90 seconds plus fallback/unavailable at five minutes during a blocked refresh.
   - Commit: `4db1314`.

## Verification

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS' -only-testing:SiriusMacTests/MetadataPresentationTests CODE_SIGNING_ALLOWED=NO` — passed, 6 focused tests.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/SiriusXMClient --filter MetadataRefreshCoordinatorTests` — passed, 11 focused tests.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/SiriusXMClient --filter SignOutTests` — passed, 9 focused tests.
- Tests use only in-memory metadata flows, controllable time, invented artwork bytes, and synthetic session collaborators; they do not access Keychain, WebKit, AVFoundation playback, provider transports, or live services.

## Decisions Made

- Keep all selection writes semantic so metadata lifecycle work cannot be bypassed by a projected SwiftUI binding.
- Treat artwork bytes as a separate, generation-scoped presentation result and never pass its source reference to SwiftUI.
- Enforce the documented freshness ceilings independently of request completion; metadata failure never alters healthy audio.

## Deviations from Plan

None - plan executed exactly as written.

## Known Stubs

None.

## Self-Check: PASSED

- All eight required source/test artifacts exist.
- Task commits `59db851`, `e56503c`, and `4db1314` are present in history.
- No tracked file deletions were introduced by this plan.
