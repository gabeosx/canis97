# Phase 03 Plan 08 — Native Checkpoint Evidence

This record contains semantic acceptance outcomes only. It intentionally excludes
credentials, tokens, cookies, stream URLs, account details, raw provider payloads,
and sensitive screenshots.

## Task 1 — Native window lifecycle, system media surfaces, and audio routing

**Status:** approved by the user on 2026-08-21.

The user confirmed every Task 1 lifecycle, MediaPlayer, and system-audio-routing
acceptance item:

- The library can close and reopen without interrupting the single active listening
  session or compact-player state; `Command-L` focuses the existing library surface.
- Closing the compact player terminates the app and ends playback normally.
- Media keys and Control Center expose only Play/Pause, Previous, and Next; their
  confirmed state and metadata mirror the app.
- System output-device changes route the existing audio normally, without an
  app-owned routing surface or second audio engine.
- The bounded exact-process check completed with cleanup after the observations.

## Task 2 — Rendered states, keyboard focus, VoiceOver, and Reduce Motion

**Status:** remediation built; manual reinspection required / not approved.

**Blocking observation:** The compact player is not legible.

This was a failing rendered-state and visual-legibility observation for Task 2's
400 × 288 compact-player acceptance contract. The fallback compact canvas used
`#111111` while inheriting the light SwiftUI appearance, so semantic `.primary`
and default button foregrounds resolved black on black.

**Remediation:** commit `3f31d77` adds a declarative dark system-foreground
scheme to `NativeCompactPlayerStyle.fallback`. `CompactPlayerView` applies that
scheme and semantic `.primary` foreground styling at its root, so it covers
empty, pending, unavailable/error, and confirmed/fallback content without
hard-coding fragile text colors or changing compact actions, accessibility,
fixed sizing, Reduce Motion behavior, or the Phase 04 style seam. A regression
contract requires both the dark fallback token and the root-level semantic
foreground/color-scheme application.

**Automated remediation evidence (2026-08-21):**

- Focused `CompactPlayerPresentationTests` plus `AccessibilityContractTests`:
  12 tests, zero failures.
- Full `xcodebuild test -project SiriusMac.xcodeproj -scheme SiriusMac
  -destination 'platform=macOS'`: 157 tests, zero failures.
- Standalone `xcodebuild build -project SiriusMac.xcodeproj -scheme SiriusMac
  -destination 'platform=macOS'`: succeeded.

Do not count the compact long-text backstop, native focus/high-contrast
inspection, VoiceOver/keyboard checks, or the Task 2 checkpoint as approved
until the fixed build is re-rendered at 400 × 288 and the full Task 2 checklist
is rerun.

**Automated baseline:** `xcodebuild test -project SiriusMac.xcodeproj -scheme
SiriusMac -destination 'platform=macOS'` passed on 2026-08-21 after remediation
(157 tests, zero failures). This automated result does not replace the required
rendered-state inspection.
