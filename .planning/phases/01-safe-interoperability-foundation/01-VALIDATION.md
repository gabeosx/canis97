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
| **Config file** | `Packages/SiriusXMClient/Package.swift` — Wave 0 creates it |
| **Quick run command** | `swift test --package-path Packages/SiriusXMClient` |
| **Full suite command** | `swift test --package-path Packages/SiriusXMClient && xcodebuild test -scheme SiriusMac` |
| **Estimated runtime** | ~30–120 seconds after the app scheme exists |

The full native-app command is unavailable until full Xcode is installed and selected. This is an execution prerequisite, not permission to weaken or omit app-bound security verification.

---

## Sampling Rate

- **After every task commit:** Run `swift test --package-path Packages/SiriusXMClient` once Wave 0 creates the package.
- **After every plan wave:** Run the complete package suite; add `xcodebuild test -scheme SiriusMac` after the app scheme and full Xcode are available.
- **Before `$gsd-verify-work`:** The full automated suite must be green and the separate manual two-run authentication gate must have an explicit result.
- **Max feedback latency:** 120 seconds for automated tests; the authorized smoke tests are never part of this sampling loop.

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 01-W0-01 | TBD | 0 | CLNT-01, CLNT-04 | T-01-05 | Public package and injected seams compile without live network access | compile/unit | `swift test --package-path Packages/SiriusXMClient` | ❌ W0 | ⬜ pending |
| 01-AUTH-01 | TBD | TBD | AUTH-01, CLNT-02 | T-01-05 | Known scripted responses map only to typed semantic outcomes | unit/contract | `swift test --package-path Packages/SiriusXMClient --filter AuthenticationOutcomeTests` | ❌ W0 | ⬜ pending |
| 01-AUTH-02 | TBD | TBD | AUTH-02, CLNT-03 | T-01-02, T-01-04, T-01-05 | Unknown, challenge, 403/429, and redirect-drift cases stop with no retry or fallback | unit | `swift test --package-path Packages/SiriusXMClient --filter FailClosedAuthenticationTests` | ❌ W0 | ⬜ pending |
| 01-AUTH-03 | TBD | TBD | AUTH-03 | T-01-03 | Sign-out clears memory and stored credentials; deletion failure remains explicit | unit/app integration | `swift test --package-path Packages/SiriusXMClient --filter SignOutTests` | ❌ W0 | ⬜ pending |
| 01-SECR-01 | TBD | TBD | SECR-01 | T-01-03 | Credentials persist only through the app-owned Keychain adapter after validated success | unit/app integration | `swift test --package-path Packages/SiriusXMClient --filter KeychainCredentialStoreTests` | ❌ W0 | ⬜ pending |
| 01-SECR-02 | TBD | TBD | SECR-02 | Transport is ephemeral, direct-host constrained, and session material is memory-only | unit | `swift test --package-path Packages/SiriusXMClient --filter EphemeralSessionTests` | ❌ W0 | ⬜ pending |
| 01-SECR-03 | TBD | TBD | SECR-03 | Canary secrets cannot appear in diagnostics, fixtures, evidence, or failures | unit/fixture | `swift test --package-path Packages/SiriusXMClient --filter RedactionTests` | ❌ W0 | ⬜ pending |
| 01-CLNT-01 | TBD | TBD | CLNT-01, CLNT-02, CLNT-03 | T-01-05 | An independent consumer imports only stable public symbols and cannot name wire adapters | compile/API | `swift test --package-path Packages/SiriusXMClient --filter PublicConsumerTests` | ❌ W0 | ⬜ pending |
| 01-CLNT-04 | TBD | TBD | CLNT-04 | T-01-04 | Scripted transport, clock, credential source, and diagnostics yield deterministic tests | unit | `swift test --package-path Packages/SiriusXMClient --filter SessionCoordinatorTests` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

Threat references:

- `T-01-01`: browser cookie or storage extraction
- `T-01-02`: CAPTCHA, MFA, anti-bot, device-limit, or other control circumvention
- `T-01-03`: credential, token, fixture, or diagnostic disclosure
- `T-01-04`: concurrent or automatic retry request storm
- `T-01-05`: protocol drift accepted as authenticated or leaked through the public API

---

## Wave 0 Requirements

- [ ] `Packages/SiriusXMClient/Package.swift` — `SiriusXMClient` library product and test targets.
- [ ] `Packages/SiriusXMClient/Tests/SiriusXMClientTests/` — scripted transport, clock, and serialized session tests.
- [ ] `Packages/SiriusXMClient/Tests/FixtureTests/` — synthetic fixture scrubber and canary-secret tests.
- [ ] `Packages/SiriusXMClient/Tests/PublicAPITests/` — independent-consumer compile/API tests.
- [ ] Full Xcode installation and active developer directory — required before native app-target tests can run.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Select the sole authentication path | AUTH-01, AUTH-02 | Provider support and access-control signals cannot be inferred safely or tested in routine CI | Investigate a clean first-party real-browser return first. If absent, investigate one honest native path. Never inspect browser storage, spoof identity, or fall back automatically. |
| Authorized smoke run 1 | AUTH-01, AUTH-03 | Requires the account owner and live subscriber authorization | Manually initiate the selected path once; require authenticated-and-entitled evidence; sign out; record only the safe outcome and cleanup result. Stop immediately on every locked stop signal. |
| Authorized smoke run 2 | AUTH-01, AUTH-03 | Must be a separate human initiation, never a retry loop | After a conservative human-controlled cooldown, repeat once and sign out cleanly. Do not schedule, parallelize, or automate the attempt. |
| Phase continuation decision | AUTH-01, AUTH-02 | This is the product viability gate | Continue to Phases 2–5 only when both runs pass unambiguously. Otherwise record authentication unsupported and preserve the fail-closed compatibility experience. |

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
