---
status: passed
phase: 03-native-mac-listening-experience
source: ["03-01-SUMMARY.md", "03-02-SUMMARY.md", "03-03-SUMMARY.md", "03-04-SUMMARY.md", "03-05-SUMMARY.md", "03-06-SUMMARY.md", "03-07-SUMMARY.md", "03-08-SUMMARY.md"]
started: 2026-08-22T14:18:19Z
updated: 2026-08-28T23:47:18Z
---

## Current Test

[testing complete]

## Tests

### 1. Shared Listening Session
expected: Compact and library surfaces share one app-owned listening session and exact playback coordinator identity.
result: pass
source: automated
coverage_id: D1

### 2. Truthful Confirmed Metadata
expected: Browse selection cannot imply playback; metadata changes only after confirmed playing state and remains truthful through loading, pause, and reset.
result: pass
source: automated
coverage_id: D2

### 3. Confirmed Live Metadata
expected: During confirmed live playback, the compact player shows the real current title and artist. Browsing or selecting another library row does not replace that confirmed metadata before playback actually changes.
result: pass

### 4. Stable Favorites
expected: Stable-ID favorite state is idempotent, unique, and shared through the controller-owned local store.
result: pass
source: automated
coverage_id: D1

### 5. Confirmed-Only Recents
expected: Recents are recorded only after confirmed playback, ordered uniquely, capped at fifty, and clearable without changing favorites.
result: pass
source: automated
coverage_id: D2

### 6. Secret-Safe Local Records
expected: SwiftData records expose only the declared non-secret presentation allow-list.
result: pass
source: automated
coverage_id: D3

### 7. Four-Tab Native Library
expected: The separate library window provides Channels, Categories, Favorites, and Recents tabs; visible-tab search filters native rows, and Return or double-click explicitly tunes the selected entitled channel.
result: pass
source: authorized-live-app-run
notes: Native row highlighting followed keyboard selection immediately while SiriusXMU continued playing; selection no longer stalled the library.

### 8. Captured Queue Navigation
expected: Previous and Next traverse the captured entitled lineup without wrapping, skip channels no longer entitled, tune through the shared session, and reveal the resulting channel in the library.
result: pass

### 9. Closed Compact Presentation
expected: The compact presentation maps confirmed channel, metadata, artwork, favorite, and queue state through semantic slots.
result: pass
source: automated
coverage_id: D1

### 10. Compact Edge States
expected: In the fixed 400 x 288 player, empty, pending, recovery, fallback, and long-text states remain truthful, legible, and bounded without displacing primary controls.
result: pass

### 11. Native Window Policy
expected: Compact and library role policy, frame validation, close semantics, and preference persistence remain deterministic.
result: pass
source: automated
coverage_id: D1

### 12. Running-App Window Lifecycle
expected: Command-L focuses one existing library window; closing and reopening it does not interrupt playback or create another session; invalid off-screen frames recover; closing the compact player ends the app normally.
result: pass

### 13. System Media Integration
expected: Media keys and Control Center expose only Play/Pause, Previous, and Next; commands use the shared queue/session, Now Playing mirrors confirmed semantic metadata, pending replacement retains the prior confirmed item, terminal state clears it, and normal system output routing continues to work.
result: pass

### 14. Native Accessibility Announcements
expected: VoiceOver receives closed, deduplicated announcements for confirmed playback, favorite, failure, and metadata-freshness transitions without provider or renderer text leaking into announcements.
result: pass

### 15. Keyboard, Focus, and Accessibility
expected: Native menus, Command-L, Command-F, arrow navigation, Return/double-click tune, search-field Space handling, focus restoration, semantic labels, context menus, high-contrast rendering, and Reduce Motion remain usable in the normal product UI.
result: pass
source: automated-and-approved-native-evidence

### 16. Final Native Acceptance
expected: The approved native checkpoint remains representative: singleton window lifecycle, media integration, system audio routing, rendered compact states, keyboard interaction, VoiceOver, and Reduce Motion all behave as recorded in 03-08-CHECKPOINT-EVIDENCE.md.
result: pass
source: approved-native-evidence

### 17. Compact Window Chrome
expected: The fixed compact player window fits its 400 x 288 player canvas without an unintended large border or excess surrounding chrome.
result: pass
source: authorized-live-app-run
notes: The compact window matched the active skin canvas without excess surrounding chrome.

## Summary

total: 17
passed: 17
issues: 0
pending: 0
skipped: 0
blocked: 0

## Gaps

- gap_id: G-03-7
  truth: "Selecting a library channel immediately moves the native highlight to that row and does not briefly hang the UI."
  status: resolved
  reason: "User reported: clicking around the library doesn't seem to work correctly - the highlighting doesn't move to a newly selected channel, the UI seems to hang when you click on a station briefly"
  severity: major
  test: 7
  root_cause: "The selectable native List row also owns a SwiftUI double-click tap recognizer, which competes with and delays the List's single-click selection gesture."
  artifacts:
    - path: "SiriusMac/Catalog/ListeningView.swift"
      issue: "Each tagged selectable row installs .onTapGesture(count: 2), delaying or suppressing immediate native single-click selection."
    - path: "SiriusMacTests/LibraryStoreTests.swift"
      issue: "Library view contract tests do not exercise real row selection or activation; no XCUITest target exists."
  resolution: "Native List selection and AppKit double-action ownership are separated; the authorized SiriusXMU run confirmed immediate selection without interrupting playback."
  debug_session: ".planning/debug/library-selection-gesture-stall.md"

- gap_id: G-03-17
  truth: "The fixed compact player window fits its 400 x 288 player canvas without an unintended large border or excess surrounding chrome."
  status: resolved
  reason: "User reported: the compact player opens with a large boarder around the player"
  severity: cosmetic
  test: 17
  root_cause: "The compact scene starts at 760 x 620 and the window adapter accepts that current/autosaved frame unchanged; maximum-size policy does not shrink the already-large window around the fixed 400 x 288 canvas."
  artifacts:
    - path: "SiriusMac/SiriusMacApp.swift"
      issue: "The compact/authentication scene has a 760 x 620 default size."
    - path: "SiriusMac/Windows/CompactWindowController.swift"
      issue: "Compact restoration applies any intersecting saved frame and returns without enforcing the exact compact content size."
    - path: "SiriusMacTests/ListeningSessionControllerTests.swift"
      issue: "Window tests cover policy values but not the configured NSWindow content frame after attachment."
  resolution: "Compact restoration preserves a safe top-left position while reapplying the validated canvas size; AppKit tests and the authorized run confirmed the fitted window."
  debug_session: ".planning/debug/compact-window-excess-chrome.md"
