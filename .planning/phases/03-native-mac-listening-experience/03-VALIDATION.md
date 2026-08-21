---
phase: 03
slug: native-mac-listening-experience
status: approved
nyquist_compliant: true
wave_0_complete: true
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

## Executable Wave 0 Strategy (Planning State)

Phase 3 uses distributed, just-in-time Wave 0 scaffolding because every behavior-producing task is TDD-marked, names its owning test file, and has an immediate focused `<automated>` command. There is no separate implementation wave that may run without tests: each owning task must create/register its test scaffold and reach a failing RED assertion before changing the production behavior named in that task. Plan 03-01 is the tracer gate; Plan 03-02 cannot start until both Plan 03-01 focused commands and the full suite pass and `03-01-SUMMARY.md` exists.

Lifecycle flags remain honest during planning:

- `wave_0_complete` stays `false` until all six planned test scaffolds below exist in the `SiriusMacTests` target and each has demonstrated its first RED assertion before the corresponding production behavior. The earliest possible flip is during `03-07-T1`, after `AccessibilityContractTests.swift` joins the five earlier scaffolds.
- `nyquist_compliant` stays `false` until `wave_0_complete` is true, every mapped focused command and per-task full-suite sample through Plan 03-07 is green, and both Plan 03-08 native/manual checkpoints have recorded passing evidence. Only then may execution update both frontmatter flags to `true` and change Approval to approved.
- Unchecked boxes and `pending` rows below describe planned prerequisites, not completed execution.

---

## Per-Task Verification Map

The planner assigns final plan/task IDs. Every mapped behavior below must appear in at least one task's automated or manual verification contract.

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 03-02-T1 | 03-02 | 2 | LIBR-01 | 03-02/T-03-01,T-03-04 | Favorite snapshots contain allow-listed local fields keyed by stable channel ID. | unit + schema contract | `xcodebuild test -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS'` | ✅ `LibraryStoreTests.swift` | ✅ green |
| 03-02-T2; 03-03-T2 | 03-02; 03-03 | 2; 3 | LIBR-02 | 03-02/T-03-03; 03-03/T-03-04 | Recents are inserted only after confirmed playback, deduplicated, ordered, capped at 50, clearable, and rendered in rank order. | unit + UI state | `xcodebuild test -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS'` | ✅ `LibraryStoreTests.swift` | ✅ green |
| 03-02-T1 | 03-02 | 2 | LIBR-03 | 03-02/T-03-01 | Persistence excludes credentials, sessions, tokens, cookies, stream URLs, artwork resources, and raw provider objects. | unit + source/schema scan | `xcodebuild test -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS'` | ✅ `LibraryStoreTests.swift` | ✅ green |
| 03-01-T1; 03-05-T1; 03-08-T1 | 03-01; 03-05; 03-08 | 1; 5; 8 | MAC-01 | 03-01/T-03-03; 03-05/T-03-03 | Closing/reopening the library and backgrounding preserve exactly one healthy playback owner; compact close performs normal shutdown. | integration + native manual | `xcodebuild test -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS'` | ✅ `ListeningSessionControllerTests.swift` | ✅ green |
| 03-06-T1; 03-08-T1 | 03-06; 03-08 | 6; 8 | MAC-02 | 03-06/T-03-03 | One remote-command registration exposes Play/Pause and Previous/Next only. | unit + integration + native manual | `xcodebuild test -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS'` | ❌ created first by 03-06-T1 | ⬜ pending |
| 03-06-T2; 03-08-T1 | 03-06; 03-08 | 6; 8 | MAC-03 | 03-06/T-03-04 | System Now Playing is published only from confirmed playback and metadata state. | unit + native manual | `xcodebuild test -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS'` | ❌ scaffold created first by 03-06-T1 | ⬜ pending |
| 03-01-T1; 03-06-T1/T2; 03-08-T1 | 03-01; 03-06; 03-08 | 1; 6; 8 | MAC-04 | 03-01/T-03-03; 03-06/T-03-03 | The existing AVFoundation coordinator remains the sole audio-output path and MediaPlayer adds no routing engine. | source scan + integration + native manual | `xcodebuild test -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS'` | ✅ existing partial + ❌ planned owner tests | ⬜ pending |
| 03-04-T1/T2; 03-05-T1; 03-08-T2 | 03-04; 03-05; 03-08 | 4; 5; 8 | UI-01 | 03-04/T-03-03,T-03-04; 03-05/T-03-04 | The 400 × 288 pt fixed compact window renders semantic slots and primary controls from shared confirmed state. | UI state + policy + rendered manual | `xcodebuild test -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS'` | ❌ compact scaffold created first by 03-04-T1 | ⬜ pending |
| 03-03-T2; 03-08-T2 | 03-03; 03-08 | 3; 8 | UI-02 | 03-03/T-03-04 | Library tab, filter, selection, favorite, explicit tune, and state rendering obey the UI contract. | unit + UI state + rendered manual | `xcodebuild test -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS'` | ❌ queue/library scaffold created first by 03-03-T1 | ⬜ pending |
| 03-01-T1; 03-05-T1; 03-08-T1 | 03-01; 03-05; 03-08 | 1; 5; 8 | UI-03 | 03-01/T-03-03; 03-05/T-03-03 | Both singleton scenes reuse one app-owned coordinator and closing the library does not interrupt playback. | identity integration + native manual | `xcodebuild test -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS'` | ❌ controller scaffold created first by 03-01-T1 | ⬜ pending |
| 03-03-T1/T2; 03-06-T1; 03-08-T1 | 03-03; 03-06; 03-08 | 3; 6; 8 | UI-04 | 03-03/T-03-02,T-03-03 | Captured queue traversal is deterministic, entitlement-filtered, bounded, shared with system controls, and revealable without replacing browse selection. | unit + integration + native manual | `xcodebuild test -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS'` | ❌ created first by 03-03-T1 | ⬜ pending |
| 03-07-T1/T2; 03-08-T2 | 03-07; 03-08 | 7; 8 | ACCS-01 | 03-07/T-03-01,T-03-04 | Essential controls expose native keyboard, menu, focus, VoiceOver, announcement, contrast, and Reduce Motion behavior. | source/behavior contract + manual VoiceOver | `xcodebuild test -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS'` | ❌ created first by 03-07-T1 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `SiriusMacTests/ListeningSessionControllerTests.swift` — owner `03-01-T1` (Wave 1); create/register and make the identity/confirmed-state tracer RED before app-session production wiring. Plan 03-05 extends this existing scaffold before window-policy behavior.
- [ ] `SiriusMacTests/LibraryStoreTests.swift` — owner `03-02-T1` (Wave 2); create/register and make the favorite/schema contract RED before SwiftData/store behavior. `03-02-T2` extends it before recents behavior.
- [ ] `SiriusMacTests/PlaybackQueueTests.swift` — owner `03-03-T1` (Wave 3); create/register and make queue/filter/reveal behavior RED before queue production code. `03-03-T2` extends it before library behavior.
- [ ] `SiriusMacTests/CompactPlayerPresentationTests.swift` — owner `03-04-T1` (Wave 4); create/register and make the semantic renderer contract RED before compact production code. `03-04-T2` extends it before state completion.
- [ ] `SiriusMacTests/SystemMediaControllerTests.swift` — owner `03-06-T1` (Wave 6); create/register and make command registration RED before MediaPlayer wiring. `03-06-T2` extends it before Now Playing publication.
- [ ] `SiriusMacTests/AccessibilityContractTests.swift` — owner `03-07-T1` (Wave 7); create/register and make announcement contracts RED before announcer production code. `03-07-T2` extends it before command/focus/accessibility behavior.
- [ ] Phase 3 manual acceptance checklist — owners `03-08-T1` and `03-08-T2` (Wave 8); compact close quits, library close preserves audio, reopening reuses state, media keys and Control Center, normal output routing, rendered backstops, VoiceOver, and Reduce Motion. Execute only after the full automated suite passes.

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

- [x] All tasks have run their `<automated>` verification after the owning RED-first scaffold step.
- [x] Compact legibility remediation automated verification — focused compact/accessibility scope (12 tests), full suite (157 tests), and standalone app build all passed on 2026-08-21; see `03-08-CHECKPOINT-EVIDENCE.md` and commit `3f31d77`.
- [x] Sampling continuity: no three consecutive tasks lack automated verification.
- [x] Wave 0 covers all MISSING references.
- [x] No watch-mode flags are used.
- [x] Automated feedback latency remains below 15 seconds on the supported development machine.
- [x] Manual Phase 3 acceptance checklist passes.
- [x] `wave_0_complete: true` is set only after all six scaffolds have met the lifecycle condition above.
- [x] `nyquist_compliant: true` is set only after all mapped automated and native/manual evidence is green.

**Approval:** approved

## Plan 03-08 Checkpoint Status

- [x] Task 1 native window lifecycle, system media surfaces, and audio routing — user-approved semantic evidence is recorded in `03-08-CHECKPOINT-EVIDENCE.md`.
- [x] Task 2 rendered states, keyboard focus, VoiceOver, and Reduce Motion — user-approved semantic evidence is recorded in `03-08-CHECKPOINT-EVIDENCE.md`; the fixed 400 × 288 state and required accessibility checks are accepted.
