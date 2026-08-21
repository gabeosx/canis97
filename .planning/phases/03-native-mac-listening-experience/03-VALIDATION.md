---
phase: 03
slug: native-mac-listening-experience
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-08-21
---

# Phase 03 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest via Xcode 26.6 |
| **Config file** | `SiriusMac.xcodeproj/xcshareddata/xcschemes/SiriusMac.xcscheme` |
| **Quick run command** | `xcodebuild test -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS'` |
| **Full suite command** | `xcodebuild test -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS'` |
| **Estimated runtime** | ~7 seconds (113-test Phase 3 research baseline) |

---

## Sampling Rate

- **After every task commit:** Run `xcodebuild test -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS'`
- **After every plan wave:** Run `xcodebuild test -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS'`
- **Before `$gsd-verify-work`:** The full Xcode suite must be green, followed by the Phase 3 manual acceptance checklist.
- **Max feedback latency:** 15 seconds for the automated suite; manual platform checks run at the phase gate.

---

## Per-Task Verification Map

The planner assigns final plan/task IDs. Every mapped behavior below must appear in at least one task's automated or manual verification contract.

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| TBD | TBD | 0+ | LIBR-01 | T-03-01 | Favorite snapshots contain allow-listed local fields keyed by stable channel ID. | unit | `xcodebuild test -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS'` | ❌ W0 | ⬜ pending |
| TBD | TBD | 0+ | LIBR-02 | Recents are inserted only after confirmed playback, deduplicated, ordered, capped at 50, and clearable. | unit | `xcodebuild test -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS'` | ❌ W0 | ⬜ pending |
| TBD | TBD | 0+ | LIBR-03 | Persistence excludes credentials, sessions, tokens, cookies, stream URLs, and raw provider objects. | unit + source scan | `xcodebuild test -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS'` | ❌ W0 | ⬜ pending |
| TBD | TBD | 0+ | MAC-01 | Closing/reopening the library and backgrounding preserve exactly one healthy playback owner. | integration + manual | `xcodebuild test -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS'` | ❌ W0 | ⬜ pending |
| TBD | TBD | 0+ | MAC-02 | One remote-command registration exposes Play/Pause and Previous/Next only. | unit + integration | `xcodebuild test -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS'` | ❌ W0 | ⬜ pending |
| TBD | TBD | 0+ | MAC-03 | System Now Playing is published only from confirmed playback and metadata state. | unit | `xcodebuild test -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS'` | ❌ W0 | ⬜ pending |
| TBD | TBD | 0+ | MAC-04 | The existing AVFoundation coordinator remains the sole audio-output path. | source scan + manual | `xcodebuild test -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS'` | ✅ partial | ⬜ pending |
| TBD | TBD | 0+ | UI-01 | The 400 × 288 pt fixed compact window renders semantic slots and primary controls from shared confirmed state. | UI state + manual | `xcodebuild test -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS'` | ❌ W0 | ⬜ pending |
| TBD | TBD | 0+ | UI-02 | Library tab, filter, selection, favorite, and explicit tune interactions obey the UI contract. | unit + UI state + manual | `xcodebuild test -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS'` | ❌ W0 | ⬜ pending |
| TBD | TBD | 0+ | UI-03 | Both singleton scenes reuse one app-owned coordinator and closing the library does not interrupt playback. | integration + manual | `xcodebuild test -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS'` | ❌ W0 | ⬜ pending |
| TBD | TBD | 0+ | UI-04 | Captured queue traversal is deterministic, entitlement-filtered, bounded, and revealable without replacing browse selection. | unit | `xcodebuild test -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS'` | ❌ W0 | ⬜ pending |
| TBD | TBD | 0+ | ACCS-01 | Essential controls expose native keyboard, menu, focus, VoiceOver, announcement, contrast, and Reduce Motion behavior. | source contract + manual VoiceOver | `xcodebuild test -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS'` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `SiriusMacTests/LibraryStoreTests.swift` — favorites; confirmed, deduplicated, 50-item recents; clear; persistence secret allow-list.
- [ ] `SiriusMacTests/PlaybackQueueTests.swift` — captured ordering, bounds, entitlement filtering, full-lineup fallback, and reveal payload.
- [ ] `SiriusMacTests/SystemMediaControllerTests.swift` — confirmed publishing, supported command enablement, and exactly-once registration behavior.
- [ ] `SiriusMacTests/ListeningSessionControllerTests.swift` — single-composition fan-out, singleton window lifecycle, and browse-selection/active-metadata separation.
- [ ] `SiriusMacTests/AccessibilityContractTests.swift` — keyboard/menu identifiers, labels, values, focus, announcements, and native-semantic source contracts.
- [ ] Phase 3 manual acceptance checklist — compact close quits; library close preserves audio; reopening reuses state; media keys and Control Center; normal output routing; VoiceOver; Reduce Motion.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Compact close terminates the app while library close preserves healthy audio and reopening reconnects to existing state. | MAC-01, UI-03 | Final `NSWindow`/application lifecycle behavior requires a running app. | Authenticate, start playback, close library, confirm audio and compact state continue, reopen with Command-L, then close compact and confirm normal app shutdown/audio end. |
| Media keys and Control Center expose only Play/Pause and Previous/Next and mirror confirmed state. | MAC-02, MAC-03 | System media surfaces are not fully observable through XCTest. | Start playback, exercise each supported system command, confirm shared UI state, and verify seek/scrub/Stop are absent. |
| macOS audio routing remains system-managed. | MAC-04 | Output-device behavior depends on host hardware and system routing. | Switch the system output while playing and confirm audio follows without an app-owned routing UI or second audio engine. |
| Compact/library controls are keyboard- and VoiceOver-usable, with correct focus and announcements. | ACCS-01 | End-user assistive-technology output requires human evaluation. | Enable VoiceOver; traverse both windows; test arrow keys, Return, Space, Command-F, Command-L, favorite actions, state announcements, and Reduce Motion. |
| Fixed and resizable layouts satisfy the approved UI contract across empty, loading, error, populated, overflow, and long-text states. | UI-01, UI-02 | Visual hierarchy, truncation, tooltips, and native focus require rendered inspection. | Inspect the 400 × 288 compact player and 980 × 700 / 760 × 540 library states with long channel and metadata fixtures. |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verification or explicit Wave 0 dependencies.
- [ ] Sampling continuity: no three consecutive tasks lack automated verification.
- [ ] Wave 0 covers all MISSING references.
- [ ] No watch-mode flags are used.
- [ ] Automated feedback latency remains below 15 seconds on the supported development machine.
- [ ] Manual Phase 3 acceptance checklist passes.
- [ ] `nyquist_compliant: true` is set in frontmatter.

**Approval:** pending
