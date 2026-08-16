---
phase: 00
slug: authentication-feasibility-gate
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-08-16
---

# Phase 00 — Validation Strategy

> Phase 0 validates its safety and decision logic entirely with synthetic data before the account owner performs any live step. No automated command may open a browser, contact SiriusXM, inspect browser/session state, or use account data.

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Swift Testing in an isolated SwiftPM package |
| **Config file** | `Spikes/AuthenticationFeasibility/Package.swift` — Wave 0 creates it |
| **Quick run command** | `swift test --package-path Spikes/AuthenticationFeasibility` |
| **Full suite command** | `swift test --package-path Spikes/AuthenticationFeasibility` |
| **Estimated runtime** | ~10 seconds |

## Sampling Rate

- **After every autonomous task commit:** Run `swift test --package-path Spikes/AuthenticationFeasibility` once the Wave 0 package exists.
- **After every autonomous plan wave:** Run `swift test --package-path Spikes/AuthenticationFeasibility`.
- **Before the human proof checkpoint:** The full synthetic suite, decision-schema validator, and source safety scans must be green.
- **Before `$gsd-verify-work`:** The full synthetic suite must remain green and `00-DECISION.md` must pass the closed-schema gate.
- **Max automated feedback latency:** 10 seconds.

The two live proof runs are manual acceptance steps, not test sampling. They must never run in tests, CI, timers, retry loops, or agent-operated browser automation.

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 00-01-01 | 01 | 1 | FEAS-01, FEAS-04 | T-00-01 / T-00-04 | Public-evidence records have a closed schema and cannot represent browser/session secrets. | structure + unit | `swift package --package-path Spikes/AuthenticationFeasibility describe && swift test --package-path Spikes/AuthenticationFeasibility --filter EvidenceGateTests` | ❌ W0 | ⬜ pending |
| 00-01-02 | 01 | 1 | FEAS-02, FEAS-03, FEAS-04, FEAS-05 | T-00-02 / T-00-03 / T-00-05 | Candidate selection, stop states, proof cardinality, and the three terminal decisions are fail-closed. | unit | `swift test --package-path Spikes/AuthenticationFeasibility` | ❌ W0 | ⬜ pending |
| 00-02-01 | 02 | 2 | FEAS-01, FEAS-02 | T-00-01 / T-00-02 | Exactly one evidence-qualified path can be selected; native-direct is unreachable until browser-return is explicitly ruled out. | unit + source scan | `swift test --package-path Spikes/AuthenticationFeasibility --filter CandidateSelectionTests && ! rg -n 'WKWebView|HTTPCookieStorage|User-Agent|URLCredentialStorage|webView|evaluateJavaScript' Spikes/AuthenticationFeasibility/Sources` | ❌ W0 | ⬜ pending |
| 00-02-02 | 02 | 2 | FEAS-03, FEAS-04, FEAS-05 | T-00-03 / T-00-04 / T-00-05 | A GO requires exactly two same-path successes, owner-confirmed cooldown, and clean sign-out; malformed, duplicate, partial, or conflicting evidence blocks. | unit + contract | `swift test --package-path Spikes/AuthenticationFeasibility --filter DecisionGateTests && swift test --package-path Spikes/AuthenticationFeasibility --filter ArtifactSchemaTests` | ❌ W0 | ⬜ pending |
| 00-03-01 | 03 | 3 | FEAS-01, FEAS-02, FEAS-04 | T-00-01 / T-00-02 / T-00-04 | The owner runbook exposes no endpoint-guessing, browser-state inspection, spoofing, automatic retry, or fallback path. | static contract | `rg -q 'account owner' .planning/phases/00-authentication-feasibility-gate/00-RUNBOOK.md && rg -q 'NO-GO unsupported' .planning/phases/00-authentication-feasibility-gate/00-RUNBOOK.md && ! rg -n 'export cookie|copy token|DevTools|HAR|spoof|retry automatically|fallback method' .planning/phases/00-authentication-feasibility-gate/00-RUNBOOK.md` | ❌ W0 | ⬜ pending |
| 00-03-02 | 03 | 3 | FEAS-03, FEAS-04, FEAS-05 | T-00-03 / T-00-04 / T-00-05 | The final artifact contains exactly one locked decision and mechanically blocks Phase 1 unless two valid proof runs support one GO path. | contract | `swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility validate-decision .planning/phases/00-authentication-feasibility-gate/00-DECISION.md` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

## Wave 0 Requirements

- [ ] `Spikes/AuthenticationFeasibility/Package.swift` — isolated executable, core, and test targets with no third-party dependency or production target coupling.
- [ ] `Spikes/AuthenticationFeasibility/Tests/AuthFeasibilityCoreTests/EvidenceGateTests.swift` — complete/incomplete public-evidence boundaries and unrepresentable secret input.
- [ ] `Spikes/AuthenticationFeasibility/Tests/AuthFeasibilityCoreTests/CandidateSelectionTests.swift` — zero/multiple candidate rejection, browser-first ordering, and native eligibility only after explicit browser rejection.
- [ ] `Spikes/AuthenticationFeasibility/Tests/AuthFeasibilityCoreTests/DecisionGateTests.swift` — zero/one/two/duplicate/out-of-order/mixed-path proof sequences and all terminal stop classes.
- [ ] `Spikes/AuthenticationFeasibility/Tests/AuthFeasibilityCoreTests/ArtifactSchemaTests.swift` — exactly three decision strings, allow-listed fields, exact GO cardinality, blocked malformed input, and secret-canary rejection.
- [ ] Synthetic fixtures contain no SiriusXM endpoint, provider identifier, account value, secret, cookie, token, callback URL, raw payload, or authenticated browser material.

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Qualifying public first-party evidence identifies one precise candidate contract. | FEAS-01, FEAS-02 | Provider eligibility is a human evidence decision; automation must not infer it by inspecting an authenticated browser or guessing endpoints. | Account owner reviews public first-party references against the closed checklist. If browser-return cannot qualify, explicitly rule it out before reviewing native-direct. If neither qualifies, record `NO-GO unsupported` without a live attempt. |
| Sole selected path completes two separate authenticated-and-entitled runs and clean sign-out. | FEAS-03, FEAS-04 | Only the account owner may operate real account/browser surfaces, observe challenges, and confirm entitlement/sign-out semantics. | Follow `00-RUNBOOK.md`; initiate one run, stop on every protected or ambiguous outcome, confirm cleanup, choose a conservative cooldown, then separately initiate run two through the same path. Report only allow-listed semantic dispositions. |
| Sanitized terminal decision is accepted or blocks continuation. | FEAS-05 | A GO depends on the owner’s two live semantic confirmations. | Run the local decision validator. Confirm exactly one of `GO browser-return`, `GO native-direct`, or `NO-GO unsupported`, no sensitive fields, and `Phase 1 continuation: unlocked` only for a mechanically valid GO. |

## Security Controls

| Threat Ref | Threat | Required Control |
|------------|--------|------------------|
| T-00-01 | Browser state or callback material leaks into the harness/artifact. | No cookie/storage/profile/DevTools interfaces; closed semantic input and secret-canary tests. |
| T-00-02 | The harness impersonates a web/device/client identity or keeps a fallback path. | Honest system APIs only; exactly one evidence-qualified candidate; no user-agent/device/client override. |
| T-00-03 | Concurrency, retry, or partial proof creates a false GO. | One attempt in flight, human-controlled cooldown, exactly two same-path terminal successes, all other cardinalities blocked. |
| T-00-04 | CAPTCHA, MFA, 403/429, redirect, control, or ambiguity triggers continued probing. | Every protected/unknown semantic state terminates evaluation, cleans up transient state, and selects `NO-GO unsupported`. |
| T-00-05 | Malformed or secret-bearing evidence unlocks Phase 1. | Closed artifact schema, allow-listed fields, redaction by construction, exact decision cardinality, and fail-closed continuation reader. |

## Validation Sign-Off

- [ ] All autonomous tasks have an `<automated>` verification or Wave 0 dependency.
- [ ] Sampling continuity: no three consecutive autonomous tasks without automated verification.
- [ ] Wave 0 covers all missing test references.
- [ ] No watch-mode flags, live-provider tests, browser/account automation, automatic retries, or error suppression.
- [ ] Feedback latency is under 10 seconds.
- [ ] Manual-only steps are confined to the account-owner checkpoint after every automated safety gate passes.
- [ ] `nyquist_compliant: true` is set after final plan/task reconciliation.

**Approval:** pending plan verification
