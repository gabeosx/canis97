---
phase: 1
slug: safe-interoperability-foundation
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-08-16
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Swift Testing from Swift 6.3.3; XCTest/XCUITest only for app integration where required |
| **Config file** | `Packages/SiriusXMClient/Package.swift` — Plan 01-01 creates it |
| **Quick run command** | `swift test --package-path Packages/SiriusXMClient` |
| **Full suite command** | `swift test --package-path Packages/SiriusXMClient && xcodebuild test -scheme SiriusMac` |
| **Estimated runtime** | ~30–120 seconds after the app scheme exists |

The full native-app command is unavailable until full Xcode is installed and selected. This is an execution prerequisite, not permission to weaken or omit app-bound security verification.

---

## Sampling Rate

- **After every task commit:** Run `swift test --package-path Packages/SiriusXMClient` once Plan 01-01 creates the package.
- **After every plan wave:** Run the complete package suite; add `xcodebuild test -scheme SiriusMac` after the app scheme and full Xcode are available.
- **Before `$gsd-verify-work`:** The full automated suite must be green and the separate manual two-run authentication gate must have an explicit result.
- **Max feedback latency:** 120 seconds for automated tests; the authorized smoke tests are never part of this sampling loop.

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 01-01-01 | 01-01 | 1 | CLNT-01, CLNT-02, CLNT-04 | T-01-01, T-01-02, T-01-05 | Native Retry reaches typed unsupported with zero live attempts | tracer/app | `xcodebuild -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS' -only-testing:SiriusMacTests/CompatibilityTracerTests test` | ❌ pre-execution | ⬜ pending |
| 01-01-02 | 01-01 | 1 | CLNT-01, CLNT-02, CLNT-04 | T-01-05 | Independent consumer compiles/awaits typed authentication, entitlement, catalog, metadata, and live-stream-resolution contracts; content operations are typed unavailable with zero transport calls and no public wire-detail fields | compile/API | `swift test --package-path Packages/SiriusXMClient --filter PublicConsumerTests` | ❌ pre-execution | ⬜ pending |
| 01-02-01 | 01-02 | 2 | AUTH-01, AUTH-02, CLNT-02, CLNT-03 | T-01-02, T-01-05 | Synthetic known and terminal shapes map to strict semantic outcomes | unit/contract | `swift test --package-path Packages/SiriusXMClient --filter AuthenticationOutcomeTests` | ❌ pre-execution | ⬜ pending |
| 01-02-02 | 01-02 | 2 | AUTH-02, SECR-02, CLNT-04 | T-01-04, T-01-05 | One actor permits one in-flight attempt and no retry/fallback | unit/concurrency | `swift test --package-path Packages/SiriusXMClient --filter SessionCoordinatorTests` | ❌ pre-execution | ⬜ pending |
| 01-03-01 | 01-03 | 2 | AUTH-02, SECR-02, CLNT-03, CLNT-04 | T-01-01, T-01-03, T-01-05 | Ephemeral transport rejects all hosts before evidence and validates redirects | unit | `swift test --package-path Packages/SiriusXMClient --filter EphemeralSessionTests` | ❌ pre-execution | ⬜ pending |
| 01-03-02 | 01-03 | 2 | SECR-03, CLNT-04 | T-01-03, T-01-06 | Closed diagnostics and structural redaction exclude synthetic canaries | unit/fixture | `swift test --package-path Packages/SiriusXMClient --filter RedactionTests` | ❌ pre-execution | ⬜ pending |
| 01-04-01 | 01-04 | 3 | SECR-01, CLNT-04 | T-01-03, T-01-06 | App-owned Keychain adapter performs isolated CRUD and post-success-only save | app integration | `xcodebuild -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS' -only-testing:SiriusMacTests/KeychainCredentialStoreTests test` | ❌ pre-execution | ⬜ pending |
| 01-04-02 | 01-04 | 3 | AUTH-03, SECR-02 | T-01-03, T-01-04 | Sign-out clears memory before deletion and reports cleanup failure | unit | `swift test --package-path Packages/SiriusXMClient --filter SignOutTests` | ❌ pre-execution | ⬜ pending |
| 01-05-01 | 01-05 | 3 | AUTH-01, AUTH-02, SECR-03, CLNT-01 | T-01-01, T-01-02, T-01-06 | Dedicated unsupported UI renders typed safe state with no player shell | app model/UI | `xcodebuild -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS' -only-testing:SiriusMacTests/AuthenticationPresentationModelTests test` | ❌ pre-execution | ⬜ pending |
| 01-05-02 | 01-05 | 3 | AUTH-01, AUTH-02, SECR-03 | T-01-01, T-01-04, T-01-06 | Explicit Retry is single-attempt and official-site navigation is one-way | app model/UI | `xcodebuild -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS' -only-testing:SiriusMacTests/AuthenticationPresentationModelTests test` | ❌ pre-execution | ⬜ pending |
| 01-06-01 | 01-06 | 4 | AUTH-01, AUTH-02 | T-01-01, T-01-02, T-01-04, T-01-05 | Account owner alone supplies browser-first safe evidence disposition | manual checkpoint | `swift test --package-path Packages/SiriusXMClient && xcodebuild -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS' test` | ❌ pre-execution | ⬜ pending |
| 01-06-02 | 01-06 | 4 | AUTH-01, AUTH-02 | T-01-02, T-01-05, T-01-06 | Exactly one browser-return, native-direct, or unsupported result is mechanically mapped from the closed safe classification vocabulary | automated decision | `summary=.planning/phases/01-safe-interoperability-foundation/01-06-SUMMARY.md; [ -r "$summary" ] && total=$(rg -c '^Selected authentication result:' "$summary") && candidate=$(sed -n 's/^Selected authentication result: //p' "$summary") && [ "$total" -eq 1 ] && case "$candidate" in browser-return) true;; native-direct) true;; unsupported) true;; *) false;; esac` | ❌ pre-execution | ⬜ pending |
| 01-07-01 | 01-07 | 5 | AUTH-01, AUTH-02, AUTH-03, SECR-02, SECR-03, CLNT-02, CLNT-03, CLNT-04 | T-01-01..T-01-06 | Only the recorded result compiles; unsupported has no live adapter | unit/contract | `swift test --package-path Packages/SiriusXMClient --filter SelectedAuthenticationPathTests` | ❌ pre-execution | ⬜ pending |
| 01-07-02 | 01-07 | 5 | AUTH-01, AUTH-02, AUTH-03, SECR-01, SECR-03, CLNT-01, CLNT-04 | T-01-01..T-01-06 | App exposes one selected surface or complete unsupported state and clean sign-out | app integration | `xcodebuild -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS' -only-testing:SiriusMacTests/SelectedAuthenticationCompositionTests test` | ❌ pre-execution | ⬜ pending |
| 01-08-01 | 01-08 | 6 | AUTH-01, AUTH-02 | T-01-02, T-01-05 | Unsupported and any missing, unreadable, duplicate, malformed, mismatched, or ambiguous Plan 01-07 state require exactly one each of Selected path: unsupported, Run 1: not-attempted, Cooldown observed: not-applicable, Run 2: not-attempted, and Phase continuation: blocked, plus zero Phase continuation: unlocked lines; only an exact supported pair reaches Run 1 | automated gate | `upstream=.planning/phases/01-safe-interoperability-foundation/01-07-SUMMARY.md; summary=.planning/phases/01-safe-interoperability-foundation/01-08-SUMMARY.md; blocked_summary_valid() { [ -r "$summary" ] && awk '/^Selected path:/ { selected_total++ } $0 == "Selected path: unsupported" { selected_closed++ } /^Run 1:/ { run1_total++ } $0 == "Run 1: not-attempted" { run1_closed++ } /^Cooldown observed:/ { cooldown_total++ } $0 == "Cooldown observed: not-applicable" { cooldown_closed++ } /^Run 2:/ { run2_total++ } $0 == "Run 2: not-attempted" { run2_closed++ } /^Phase continuation:/ { continuation_total++ } $0 == "Phase continuation: blocked" { blocked_total++ } $0 == "Phase continuation: unlocked" { unlocked_total++ } END { exit !(selected_total == 1 && selected_closed == 1 && run1_total == 1 && run1_closed == 1 && cooldown_total == 1 && cooldown_closed == 1 && run2_total == 1 && run2_closed == 1 && continuation_total == 1 && blocked_total == 1 && unlocked_total == 0) }' "$summary"; }; implemented_total=0; readiness_total=0; implemented=; readiness=; if [ -r "$upstream" ]; then implemented_total=$(awk '/^Implemented authentication result:/ { count++ } END { print count + 0 }' "$upstream") && readiness_total=$(awk '/^Continuation readiness:/ { count++ } END { print count + 0 }' "$upstream") && implemented=$(sed -n 's/^Implemented authentication result: //p' "$upstream") && readiness=$(sed -n 's/^Continuation readiness: //p' "$upstream"); fi && swift test --package-path Packages/SiriusXMClient && xcodebuild -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS' test && case "$implemented_total:$readiness_total:$implemented:$readiness" in 1:1:unsupported:blocked-unsupported) blocked_summary_valid;; 1:1:browser-return:supported-selected-path) true;; 1:1:native-direct:supported-selected-path) true;; *) blocked_summary_valid;; esac` | ❌ pre-execution | ⬜ pending |
| 01-08-02 | 01-08 | 6 | AUTH-01, AUTH-02, AUTH-03, SECR-01, SECR-02, SECR-03 | T-01-01..T-01-06 | Account owner alone completes Run 1 authenticated, entitled, and cleanly signed out | manual checkpoint | `swift test --package-path Packages/SiriusXMClient --filter SignOutTests && swift test --package-path Packages/SiriusXMClient --filter RedactionTests` | ❌ pre-execution | ⬜ pending |
| 01-08-03 | 01-08 | 6 | AUTH-01, AUTH-02, AUTH-03, SECR-01, SECR-02, SECR-03 | T-01-01..T-01-06 | Owner-controlled cooldown precedes separate Run 2; exactly two clean passes plus owner-confirmed cooldown unlock, while every other closed state requires one blocked continuation and no unlocked continuation | manual checkpoint + automated final gate | `summary=.planning/phases/01-safe-interoperability-foundation/01-08-SUMMARY.md; allowed_run() { case "$1" in pass-authenticated-entitled-signed-out) return 0;; not-attempted) return 0;; blocked-rejected) return 0;; blocked-not-entitled) return 0;; blocked-captcha) return 0;; blocked-challenge) return 0;; blocked-403) return 0;; blocked-429) return 0;; blocked-rate-limit) return 0;; blocked-unexpected-redirect) return 0;; blocked-bot-signal) return 0;; blocked-cleanup) return 0;; blocked-ambiguous) return 0;; *) return 1;; esac; }; [ -r "$summary" ] && swift test --package-path Packages/SiriusXMClient --filter SelectedAuthenticationPathTests && swift test --package-path Packages/SiriusXMClient --filter SignOutTests && swift test --package-path Packages/SiriusXMClient --filter RedactionTests && selected_total=$(rg -c '^Selected path:' "$summary") && run1_total=$(rg -c '^Run 1:' "$summary") && cooldown_total=$(rg -c '^Cooldown observed:' "$summary") && run2_total=$(rg -c '^Run 2:' "$summary") && continuation_total=$(rg -c '^Phase continuation:' "$summary") && selected=$(sed -n 's/^Selected path: //p' "$summary") && run1=$(sed -n 's/^Run 1: //p' "$summary") && cooldown=$(sed -n 's/^Cooldown observed: //p' "$summary") && run2=$(sed -n 's/^Run 2: //p' "$summary") && continuation=$(sed -n 's/^Phase continuation: //p' "$summary") && [ "$selected_total" -eq 1 ] && [ "$run1_total" -eq 1 ] && [ "$cooldown_total" -eq 1 ] && [ "$run2_total" -eq 1 ] && [ "$continuation_total" -eq 1 ] && case "$selected" in browser-return) true;; native-direct) true;; unsupported) true;; *) false;; esac && allowed_run "$run1" && allowed_run "$run2" && case "$cooldown" in owner-confirmed) true;; not-applicable) true;; *) false;; esac && case "$continuation" in unlocked) true;; blocked) true;; *) false;; esac && { if [ "$selected" = unsupported ]; then [ "$run1" = not-attempted ] && [ "$cooldown" = not-applicable ] && [ "$run2" = not-attempted ] && [ "$continuation" = blocked ]; elif [ "$run1" = pass-authenticated-entitled-signed-out ] && [ "$cooldown" = owner-confirmed ] && [ "$run2" = pass-authenticated-entitled-signed-out ]; then [ "$continuation" = unlocked ]; else [ "$continuation" = blocked ]; fi; }` | ❌ pre-execution | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

Threat references:

- `T-01-01`: browser cookie or storage extraction
- `T-01-02`: CAPTCHA, MFA, anti-bot, device-limit, or other control circumvention
- `T-01-03`: credential, token, fixture, or diagnostic disclosure
- `T-01-04`: concurrent or automatic retry request storm
- `T-01-05`: protocol drift accepted as authenticated or leaked through the public API

---

## Wave 0 / Plan 01-01 Requirements

- [ ] `Packages/SiriusXMClient/Package.swift` — Plan 01-01 creates the `SiriusXMClient` library product and test targets.
- [ ] `Packages/SiriusXMClient/Tests/SiriusXMClientTests/` — scripted transport, clock, and serialized session tests.
- [ ] `Packages/SiriusXMClient/Tests/FixtureTests/` — synthetic fixture scrubber and canary-secret tests.
- [ ] `Packages/SiriusXMClient/Tests/PublicAPITests/` — independent-consumer compile/API tests.
- [ ] Full Xcode installation and active developer directory — required before native app-target tests can run.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Ordered result selection (Tasks 01-06-01/02) | AUTH-01, AUTH-02 | Provider support and access-control signals cannot be inferred safely or tested in routine CI | Account owner alone evaluates real-browser evidence first; native-direct evidence is considered only after browser return is ruled out. The executor receives only safe disposition/public references and records exactly one result. |
| Authorized smoke run 1 (Task 01-08-02) | AUTH-01, AUTH-03, SECR-01, SECR-02, SECR-03 | Requires the account owner and live subscriber authorization | Only for a supported Plan 01-07 result, the owner manually initiates once, requires authenticated-and-entitled, signs out cleanly, and reports one allow-listed safe code. Any stop signal blocks Run 2. |
| Conservative cooldown and smoke run 2 (Task 01-08-03) | AUTH-01, AUTH-03, SECR-01, SECR-02, SECR-03 | Must be a separate human initiation and cannot be an agent/app timer or retry loop | After the owner independently chooses and completes a conservative cooldown, they initiate the same selected path once and sign out cleanly. No scheduling, polling, browser/account operation, or automation by the executor. |
| Phase continuation decision (Task 01-08-03/output) | AUTH-01, AUTH-02 | This is the product viability gate | Unsupported records blocked without auth. A supported path unlocks Phases 2–5 only when both separate runs are authenticated-and-entitled with clean sign-out; every stop, failure, or ambiguity records blocked. |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies.
- [ ] Sampling continuity: no 3 consecutive tasks without automated verification.
- [ ] Wave 0 covers all missing references.
- [ ] No watch-mode flags.
- [ ] Feedback latency is below 120 seconds once infrastructure exists.
- [ ] Authorized smoke tests remain manual, separately initiated, one attempt in flight, and absent from CI.
- [ ] `nyquist_compliant: true` set in frontmatter after execution validation.

**Approval:** pending
