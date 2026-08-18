---
phase: 1
slug: safe-interoperability-foundation
status: planned
nyquist_compliant: true
wave_0_complete: false
created: 2026-08-16
updated: 2026-08-17
---

# Phase 1 — Validation Strategy

## Test infrastructure

| Property | Value |
|---|---|
| Framework | Swift Testing; XCTest for app/WebKit/Keychain integration |
| Package command | `swift test --package-path Packages/SiriusXMClient` |
| App command | `xcodebuild -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS' test` |
| Live provider activity | None; Phase 1 validation uses synthetic collaborators |

Full Xcode is an execution prerequisite for app tests. Authentication feasibility, Phase 0 artifact validation, and duplicate owner proof runs are explicitly outside this strategy.

## Sampling rate

- After every task: run the focused test command in that task.
- After every wave: run the complete package suite and the app suite once the scheme exists.
- Before phase verification: run both full suites and the static stale-gate scan from Plan 01-08.
- Mutable `.planning` artifacts must never control whether WebKit/authentication sources or deterministic tests compile.

## Per-task verification map

| Task | Secure behavior | Automated command |
|---|---|---|
| 01-01-01 | Native app/package walking skeleton exists with no Phase 0 gate | `xcodebuild ... -only-testing:SiriusMacTests/CompatibilityTracerTests test` |
| 01-01-02 | Independent consumer uses semantic APIs and sees no wire/token details | `swift test --package-path Packages/SiriusXMClient --filter PublicConsumerTests` |
| 01-02-01 | Native auth and entitlement responses map to distinct fail-closed outcomes | `swift test --package-path Packages/SiriusXMClient --filter AuthenticationOutcomeTests` |
| 01-02-02 | One actor owns one attempt; only runtime verification atomically activates session | `swift test --package-path Packages/SiriusXMClient --filter SessionCoordinatorTests` |
| 01-03-01 | Ephemeral exact-host transport rejects redirect drift and secret forwarding | `swift test --package-path Packages/SiriusXMClient --filter EphemeralSessionTests` |
| 01-03-02 | Closed diagnostics exclude credential/token/cookie/response canaries | `swift test --package-path Packages/SiriusXMClient --filter RedactionTests` |
| 01-04-01 | Keychain CRUD is isolated and save occurs only after entitled success | `xcodebuild ... -only-testing:SiriusMacTests/KeychainCredentialStoreTests test` |
| 01-04-02 | Sign-out is memory-first and cleanup failure is explicit | `swift test --package-path Packages/SiriusXMClient --filter SignOutTests` |
| 01-05-01 | One WebView sign-in surface renders every semantic state | `xcodebuild ... -only-testing:SiriusMacTests/AuthenticationPresentationModelTests test` |
| 01-05-02 | Explicit user action permits one attempt and no fallback/retry | same focused app suite |
| 01-06-01 | Extraction accepts exactly one current first-party token via one shared predicate | `xcodebuild ... -only-testing:SiriusMacTests/WebAuthenticationBridgeTests test` |
| 01-06-02 | Sign-out applies that predicate across apex/subdomains and tests always compile | same focused app suite plus build-graph assertions |
| 01-07-01 | Runtime sequence performs authentication then entitlement before session publication | `swift test --package-path Packages/SiriusXMClient --filter WebTokenAuthenticationTests` |
| 01-07-02 | Native app composes WebView credential source to the client with no alternate path | `xcodebuild ... -only-testing:SiriusMacTests/SelectedAuthenticationCompositionTests test` |
| 01-08-01 | `00-REVIEW` regressions are covered synthetically | focused package/app regression suites |
| 01-08-02 | Full suites pass and Phase 2 readiness contains no Phase 0 authority | full package/app suites plus stale-gate scan |

`...` in the table abbreviates only the stable Xcode prefix shown in the app command; each plan contains the exact runnable command.

## `00-REVIEW.md` acceptance mapping

| Finding | Phase 1 blocking acceptance |
|---|---|
| CR-01 untrusted owner-result | No file or caller can assert success; only runtime-observed native auth plus entitlement activates a session. |
| CR-02 entitlement not wired | The single production sequence always performs native entitlement verification after authentication and before persistence/session publication. |
| CR-03 subdomain token survives sign-out | Extraction and cleanup share one exact cookie predicate across apex and accepted SiriusXM subdomains; any remaining or ambiguous match fails cleanup. |
| WR-01 non-atomic quartet | Phase 1 consumes no quartet; `SessionCoordinator` publishes one immutable active-session value only after the complete sequence succeeds. |
| WR-02 tests silently excluded | Browser bridge and deterministic tests are unconditional build-graph members and cannot be disabled by `.planning` contents. |

## Manual-only verification

None. A normal user sign-in after implementation is product use, not an authentication experiment or Phase 1 acceptance gate.

## Sign-off

- [x] Every task has automated verification.
- [x] No three consecutive tasks lack feedback.
- [x] No Phase 0 artifact or GO string is an execution prerequisite.
- [x] All legitimate Phase 0 review findings have blocking regression coverage.
- [x] Phase 1 is ready to execute at Plan 01-01.
