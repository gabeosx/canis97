---
phase: 00
slug: authentication-feasibility-gate
status: planned
nyquist_compliant: true
wave_0_complete: false
created: 2026-08-16
updated: 2026-08-16
---

# Phase 00 — Validation Strategy

> Every automated check is synthetic, static, or build-only. No automated command opens a browser, contacts SiriusXM, inspects browser/session state, invokes the candidate, uses account data, waits a cooldown, retries, or polls.

## Test Infrastructure

| Property | Value |
|---|---|
| **Framework** | Swift Testing in an isolated dependency-free SwiftPM package |
| **Config file** | `Spikes/AuthenticationFeasibility/Package.swift` — Plan 00-01 creates it |
| **Quick run command** | `swift test --package-path Spikes/AuthenticationFeasibility` |
| **Full suite command** | `swift test --package-path Spikes/AuthenticationFeasibility` |
| **Estimated runtime** | ~10 seconds |

## Sampling Rate

- After every autonomous task: run the task’s exact `<automated>` command below.
- After every wave: run `swift test --package-path Spikes/AuthenticationFeasibility` plus the wave’s artifact validator/static gate.
- Before any human checkpoint: the preceding automated gate must pass. Unsupported branches bypass candidate/live checkpoints rather than weakening their precondition.
- Before `$gsd-verify-work`: run the full synthetic suite and `auth-feasibility validate-decision` against `00-DECISION.md`.
- Maximum automated feedback latency: 10 seconds after the SwiftPM package exists.

The two proof runs are manual owner actions, not test sampling. They never run in tests, CI, timers, retry loops, browser automation, or agent-operated tools.

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirements | Threat refs | Automated command | Human-only behavior |
|---|---:|---:|---|---|---|---|
| 00-01-01 | 01 | 1 | FEAS-01, FEAS-05 | T-00-01, T-00-05 | `swift package --package-path Spikes/AuthenticationFeasibility describe && swift test --package-path Spikes/AuthenticationFeasibility --filter ContractTracerTests` | None |
| 00-01-02 | 01 | 1 | FEAS-02, FEAS-03, FEAS-04, FEAS-05 | T-00-02, T-00-03, T-00-04 | `swift test --package-path Spikes/AuthenticationFeasibility && ! rg -n 'URLSession\|ASWebAuthenticationSession\|WKWebView\|HTTPCookieStorage\|User-Agent\|URLCredentialStorage\|http://\|https://' Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityCore` | None |
| 00-02-01 | 02 | 2 | FEAS-01, FEAS-02, FEAS-04 | T-00-01, T-00-02, T-00-04 | `swift test --package-path Spikes/AuthenticationFeasibility` | Account owner reviews public first-party evidence only and returns one closed classification plus public URLs. |
| 00-02-02 | 02 | 2 | FEAS-01, FEAS-02, FEAS-05 | T-00-02, T-00-05 | Strict `validate-evidence` → `derive-selection` → byte comparison → `validate-selection` command from Plan 00-02 Task 02. | None |
| 00-03-01 | 03 | 3 | FEAS-01, FEAS-02, FEAS-04 | T-00-01..T-00-05 | Strict full-chain validation, fresh selection/decision derivation and byte comparison, canonical unsupported closure, and branch command from Plan 00-03 Task 01; browser selection additionally requires offline `xcodebuild -version`. | None; partial closure is invalid and only a fully validated unsupported chain bypasses the checkpoint. |
| 00-03-02 | 03 | 3 | FEAS-02, FEAS-03, FEAS-04 | T-00-01..T-00-05 | Full synthetic suite/build plus exact selected-source cardinality command from Plan 00-03 Task 02. | None; this task builds but never invokes the candidate. |
| 00-03-03 | 03 | 3 | FEAS-02, FEAS-04 | T-00-01..T-00-05 | Full synthetic suite/build and exact runbook disposition command from Plan 00-03 Task 03. | For supported selection only, owner reviews source/runbook safety without authenticating; unsupported bypasses the pause. |
| 00-04-01 | 04 | 4 | FEAS-03, FEAS-04, FEAS-05 | T-00-03..T-00-05 | Strict evidence/selection derivation plus conditional proof-ready-or-validated-zero-run-owner-result command from Plan 00-04 Task 01. | None; unsupported writes and validates zero-run owner result. |
| 00-04-02 | 04 | 4 | FEAS-03, FEAS-04 | T-00-01, T-00-03, T-00-04 | Branch-aware command from Plan 00-04 Task 02: unsupported requires no proof-ready and validates the zero-run owner result; supported requires proof-ready. | For supported selection only, owner performs exactly run-1, cooldown, run-2 or stops once; unsupported bypasses the task. |
| 00-04-03 | 04 | 4 | FEAS-03, FEAS-04, FEAS-05 | T-00-01, T-00-03..T-00-05 | Strict `validate-owner-result` → `derive-decision` → byte comparison → `validate-decision` command from Plan 00-04 Task 03. | None |

## Exact Automated Command Reconciliation

The following blocks are copied verbatim from each task's `<automated>` element and are the canonical validation commands. This prevents the task map from drifting while keeping long shell programs outside Markdown table cells.

### 00-01-01

```sh
swift package --package-path Spikes/AuthenticationFeasibility describe &amp;&amp; swift test --package-path Spikes/AuthenticationFeasibility --filter ContractTracerTests
```

### 00-01-02

```sh
swift test --package-path Spikes/AuthenticationFeasibility &amp;&amp; ! rg -n 'URLSession|ASWebAuthenticationSession|WKWebView|HTTPCookieStorage|User-Agent|URLCredentialStorage|http://|https://' Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityCore
```

### 00-02-01

```sh
swift test --package-path Spikes/AuthenticationFeasibility
```

### 00-02-02

```sh
evidence=.planning/phases/00-authentication-feasibility-gate/00-EVIDENCE.md; selection=.planning/phases/00-authentication-feasibility-gate/00-SELECTION.md; owner=.planning/phases/00-authentication-feasibility-gate/00-OWNER-RESULT.md; decision_file=.planning/phases/00-authentication-feasibility-gate/00-DECISION.md; derived_selection=$(mktemp) || exit 1; derived_decision=$(mktemp) || { rm -f "$derived_selection"; exit 1; }; trap 'rm -f "$derived_selection" "$derived_decision"' EXIT; closed=0; if ! swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility validate-evidence "$evidence" || ! swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility derive-selection --evidence "$evidence" --output "$derived_selection" || ! cmp -s "$derived_selection" "$selection" || ! swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility validate-selection "$selection"; then swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility close-unsupported --reason invalid-artifact --evidence "$evidence" --selection "$selection" --owner-result "$owner" --decision "$decision_file" &amp;&amp; closed=1; fi &amp;&amp; swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility validate-evidence "$evidence" &amp;&amp; swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility derive-selection --evidence "$evidence" --output "$derived_selection" &amp;&amp; cmp -s "$derived_selection" "$selection" &amp;&amp; swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility validate-selection "$selection" &amp;&amp; { [ "$closed" -eq 0 ] || { swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility validate-owner-result "$owner" &amp;&amp; swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility derive-decision --selection "$selection" --evidence "$evidence" --owner-result "$owner" --output "$derived_decision" &amp;&amp; cmp -s "$derived_decision" "$decision_file" &amp;&amp; swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility validate-decision "$decision_file"; }; } &amp;&amp; [ "$(rg -c '^Selected candidate:' "$selection")" -eq 1 ] &amp;&amp; [ "$(rg -c '^Live attempt permitted:' "$selection")" -eq 1 ]
```

### 00-03-01

```sh
evidence=.planning/phases/00-authentication-feasibility-gate/00-EVIDENCE.md; selection=.planning/phases/00-authentication-feasibility-gate/00-SELECTION.md; owner=.planning/phases/00-authentication-feasibility-gate/00-OWNER-RESULT.md; decision_file=.planning/phases/00-authentication-feasibility-gate/00-DECISION.md; runbook=.planning/phases/00-authentication-feasibility-gate/00-RUNBOOK.md; derived_selection=$(mktemp) || exit 1; derived_decision=$(mktemp) || { rm -f "$derived_selection"; exit 1; }; trap 'rm -f "$derived_selection" "$derived_decision"' EXIT; closed=0; if ! swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility validate-evidence "$evidence" || ! swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility derive-selection --evidence "$evidence" --output "$derived_selection" || ! cmp -s "$derived_selection" "$selection" || ! swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility validate-selection "$selection"; then swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility close-unsupported --reason invalid-artifact --evidence "$evidence" --selection "$selection" --owner-result "$owner" --decision "$decision_file" &amp;&amp; closed=1; fi &amp;&amp; if [ "$closed" -eq 0 ]; then selected=$(sed -n 's/^Selected candidate: //p' "$selection"); case "$selected" in unsupported) swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility close-unsupported --reason unsupported-selection --evidence "$evidence" --selection "$selection" --owner-result "$owner" --decision "$decision_file" &amp;&amp; closed=1;; browser-return) if ! xcodebuild -version &gt;/dev/null; then swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility close-unsupported --reason browser-tooling-unavailable --evidence "$evidence" --selection "$selection" --owner-result "$owner" --decision "$decision_file" &amp;&amp; closed=1; fi;; native-direct) true;; *) false;; esac; fi &amp;&amp; swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility validate-evidence "$evidence" &amp;&amp; swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility derive-selection --evidence "$evidence" --output "$derived_selection" &amp;&amp; cmp -s "$derived_selection" "$selection" &amp;&amp; swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility validate-selection "$selection" &amp;&amp; { [ "$closed" -eq 0 ] || { swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility validate-owner-result "$owner" &amp;&amp; swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility derive-decision --selection "$selection" --evidence "$evidence" --owner-result "$owner" --output "$derived_decision" &amp;&amp; cmp -s "$derived_decision" "$decision_file" &amp;&amp; swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility validate-decision "$decision_file"; }; } &amp;&amp; selected=$(sed -n 's/^Selected candidate: //p' "$selection") &amp;&amp; case "$selected" in unsupported) [ ! -e Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityBrowserCandidate/BrowserCandidate.swift ] &amp;&amp; [ ! -e Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityNativeCandidate/NativeCandidate.swift ] &amp;&amp; rg -q '^Live operation: prohibited$' "$runbook";; browser-return) xcodebuild -version &gt;/dev/null;; native-direct) true;; *) false;; esac
```

### 00-03-02

```sh
swift test --package-path Spikes/AuthenticationFeasibility &amp;&amp; swift build --package-path Spikes/AuthenticationFeasibility &amp;&amp; selected=$(sed -n 's/^Selected candidate: //p' .planning/phases/00-authentication-feasibility-gate/00-SELECTION.md) &amp;&amp; case "$selected" in unsupported) [ ! -e Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityBrowserCandidate/BrowserCandidate.swift ] &amp;&amp; [ ! -e Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityNativeCandidate/NativeCandidate.swift ];; browser-return) [ -f Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityBrowserCandidate/BrowserCandidate.swift ] &amp;&amp; [ ! -e Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityNativeCandidate/NativeCandidate.swift ];; native-direct) [ -f Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityNativeCandidate/NativeCandidate.swift ] &amp;&amp; [ ! -e Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityBrowserCandidate/BrowserCandidate.swift ];; *) false;; esac
```

### 00-03-03

```sh
swift test --package-path Spikes/AuthenticationFeasibility &amp;&amp; swift build --package-path Spikes/AuthenticationFeasibility &amp;&amp; rg -q '^Live operation: (owner-only|prohibited)$' .planning/phases/00-authentication-feasibility-gate/00-RUNBOOK.md
```

### 00-04-01

```sh
evidence=.planning/phases/00-authentication-feasibility-gate/00-EVIDENCE.md; selection=.planning/phases/00-authentication-feasibility-gate/00-SELECTION.md; owner=.planning/phases/00-authentication-feasibility-gate/00-OWNER-RESULT.md; decision_file=.planning/phases/00-authentication-feasibility-gate/00-DECISION.md; proof=.planning/phases/00-authentication-feasibility-gate/00-PROOF-READY.md; runbook=.planning/phases/00-authentication-feasibility-gate/00-RUNBOOK.md; derived_selection=$(mktemp) || exit 1; derived_decision=$(mktemp) || { rm -f "$derived_selection"; exit 1; }; trap 'rm -f "$derived_selection" "$derived_decision"' EXIT; swift test --package-path Spikes/AuthenticationFeasibility || exit 1; swift build --package-path Spikes/AuthenticationFeasibility || exit 1; closed=0; if ! swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility validate-evidence "$evidence" || ! swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility derive-selection --evidence "$evidence" --output "$derived_selection" || ! cmp -s "$derived_selection" "$selection" || ! swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility validate-selection "$selection"; then swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility close-unsupported --reason invalid-artifact --evidence "$evidence" --selection "$selection" --owner-result "$owner" --decision "$decision_file" &amp;&amp; closed=1; fi &amp;&amp; swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility validate-evidence "$evidence" &amp;&amp; swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility derive-selection --evidence "$evidence" --output "$derived_selection" &amp;&amp; cmp -s "$derived_selection" "$selection" &amp;&amp; swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility validate-selection "$selection" &amp;&amp; selected=$(sed -n 's/^Selected candidate: //p' "$selection") &amp;&amp; case "$selected" in unsupported) if ! swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility validate-owner-result "$owner" || ! swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility derive-decision --selection "$selection" --evidence "$evidence" --owner-result "$owner" --output "$derived_decision" || ! cmp -s "$derived_decision" "$decision_file" || ! swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility validate-decision "$decision_file"; then swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility close-unsupported --reason unsupported-selection --evidence "$evidence" --selection "$selection" --owner-result "$owner" --decision "$decision_file"; fi &amp;&amp; [ ! -e "$proof" ] &amp;&amp; swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility validate-owner-result "$owner" &amp;&amp; swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility derive-decision --selection "$selection" --evidence "$evidence" --owner-result "$owner" --output "$derived_decision" &amp;&amp; cmp -s "$derived_decision" "$decision_file" &amp;&amp; swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility validate-decision "$decision_file" &amp;&amp; rg -q '^Live operation: prohibited$' "$runbook";; browser-return|native-direct) [ "$closed" -eq 0 ] &amp;&amp; test -r "$proof" &amp;&amp; rg -q '^Live operation: owner-only$' "$runbook";; *) false;; esac
```

### 00-04-02

```sh
evidence=.planning/phases/00-authentication-feasibility-gate/00-EVIDENCE.md; selection=.planning/phases/00-authentication-feasibility-gate/00-SELECTION.md; owner=.planning/phases/00-authentication-feasibility-gate/00-OWNER-RESULT.md; decision_file=.planning/phases/00-authentication-feasibility-gate/00-DECISION.md; proof=.planning/phases/00-authentication-feasibility-gate/00-PROOF-READY.md; derived_selection=$(mktemp) || exit 1; derived_decision=$(mktemp) || { rm -f "$derived_selection"; exit 1; }; trap 'rm -f "$derived_selection" "$derived_decision"' EXIT; swift test --package-path Spikes/AuthenticationFeasibility || exit 1; closed=0; if ! swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility validate-evidence "$evidence" || ! swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility derive-selection --evidence "$evidence" --output "$derived_selection" || ! cmp -s "$derived_selection" "$selection" || ! swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility validate-selection "$selection"; then swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility close-unsupported --reason invalid-artifact --evidence "$evidence" --selection "$selection" --owner-result "$owner" --decision "$decision_file" &amp;&amp; closed=1; fi &amp;&amp; selected=$(sed -n 's/^Selected candidate: //p' "$selection") &amp;&amp; case "$selected" in unsupported) if ! swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility validate-owner-result "$owner" || ! swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility derive-decision --selection "$selection" --evidence "$evidence" --owner-result "$owner" --output "$derived_decision" || ! cmp -s "$derived_decision" "$decision_file" || ! swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility validate-decision "$decision_file"; then swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility close-unsupported --reason unsupported-selection --evidence "$evidence" --selection "$selection" --owner-result "$owner" --decision "$decision_file"; fi &amp;&amp; [ ! -e "$proof" ] &amp;&amp; swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility validate-evidence "$evidence" &amp;&amp; swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility derive-selection --evidence "$evidence" --output "$derived_selection" &amp;&amp; cmp -s "$derived_selection" "$selection" &amp;&amp; swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility validate-owner-result "$owner" &amp;&amp; swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility derive-decision --selection "$selection" --evidence "$evidence" --owner-result "$owner" --output "$derived_decision" &amp;&amp; cmp -s "$derived_decision" "$decision_file" &amp;&amp; swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility validate-decision "$decision_file";; browser-return|native-direct) [ "$closed" -eq 0 ] &amp;&amp; test -r "$proof";; *) false;; esac
```

### 00-04-03

```sh
evidence=.planning/phases/00-authentication-feasibility-gate/00-EVIDENCE.md; selection=.planning/phases/00-authentication-feasibility-gate/00-SELECTION.md; owner=.planning/phases/00-authentication-feasibility-gate/00-OWNER-RESULT.md; decision_file=.planning/phases/00-authentication-feasibility-gate/00-DECISION.md; derived_selection=$(mktemp) || exit 1; derived_decision=$(mktemp) || { rm -f "$derived_selection"; exit 1; }; trap 'rm -f "$derived_selection" "$derived_decision"' EXIT; closed=0; if ! swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility validate-evidence "$evidence" || ! swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility derive-selection --evidence "$evidence" --output "$derived_selection" || ! cmp -s "$derived_selection" "$selection" || ! swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility validate-selection "$selection" || ! swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility validate-owner-result "$owner" || ! swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility derive-decision --selection "$selection" --evidence "$evidence" --owner-result "$owner" --output "$derived_decision" || ! cmp -s "$derived_decision" "$decision_file" || ! swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility validate-decision "$decision_file"; then swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility close-unsupported --reason invalid-artifact --evidence "$evidence" --selection "$selection" --owner-result "$owner" --decision "$decision_file" &amp;&amp; closed=1; fi &amp;&amp; swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility validate-evidence "$evidence" &amp;&amp; swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility derive-selection --evidence "$evidence" --output "$derived_selection" &amp;&amp; cmp -s "$derived_selection" "$selection" &amp;&amp; swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility validate-selection "$selection" &amp;&amp; swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility validate-owner-result "$owner" &amp;&amp; swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility derive-decision --selection "$selection" --evidence "$evidence" --owner-result "$owner" --output "$derived_decision" &amp;&amp; cmp -s "$derived_decision" "$decision_file" &amp;&amp; swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility validate-decision "$decision_file" &amp;&amp; [ "$(rg -c '^Feasibility decision:' "$decision_file")" -eq 1 ] &amp;&amp; [ "$(rg -c '^Phase 1 continuation:' "$decision_file")" -eq 1 ] &amp;&amp; decision=$(sed -n 's/^Feasibility decision: //p' "$decision_file") &amp;&amp; continuation=$(sed -n 's/^Phase 1 continuation: //p' "$decision_file") &amp;&amp; case "$decision:$continuation" in 'GO browser-return:unlocked'|'GO native-direct:unlocked') [ "$closed" -eq 0 ];; 'NO-GO unsupported:blocked') true;; *) false;; esac
```


## Wave 0 Requirements
- [ ] `Spikes/AuthenticationFeasibility/Package.swift` — isolated core/executable/test targets with zero third-party dependencies and no product-target reference.
- [ ] `ContractTracerTests.swift` — incomplete evidence, exact three-decision schema, decision/continuation consistency, unknown-key rejection, secret-canary exclusion, and no-default-live-command coverage.
- [ ] `CandidateSelectionTests.swift` — zero/multiple candidate rejection, browser-first order, native-after-rule-out only, and no retained alternate.
- [ ] `DecisionGateTests.swift` — exact two distinct ordered same-path proofs; 0/1/>2, duplicate, out-of-order, mixed-path, missing cooldown, missing entitlement, and missing sign-out rejection.
- [ ] `StopConditionTests.swift` — every terminal stop/unknown/ambiguous class selects blocked NO-GO after one signal and offers no retry/fallback transition.
- [ ] CLI contract tests cover strict evidence/selection/owner/decision validation, deterministic canonical selection/decision derivation, fresh-output byte equivalence, non-public evidence rejection, every ordered rename-failure point, rejection by both Phase 0 and Phase 1 complete-chain gates, and idempotent unsupported-closure retry.
- [ ] Synthetic inputs contain no SiriusXM endpoint/host, provider identifier, credential, token, cookie, account value, callback URL, raw payload, precise time, or authenticated browser material.

## Manual-Only Verifications

| Gate | Requirements | Owner action | Automated pre/post gate |
|---|---|---|---|
| Public evidence eligibility | FEAS-01, FEAS-02 | Review only public first-party references against every exact predicate; browser first, native only after explicit rule-out; return one closed token and public URLs. | Full suite before; `validate-selection` after. |
| Candidate safety review | FEAS-02, FEAS-04 | Supported branch only: inspect the sole candidate and runbook without authenticating; unsupported bypasses. | Full suite/build/source-cardinality before and after. |
| Two-run proof | FEAS-03, FEAS-04 | Supported branch only: operate run-1, confirm authenticated+entitled+sign-out, choose/complete cooldown, separately operate run-2; return exact success record or one stop token. | Full suite/selection/proof-ready before; `validate-decision` after. |

## Security Controls

| Threat ref | Threat | Required control |
|---|---|---|
| T-00-01 | Browser/account/callback/transport material leaks into source, log, proof, or decision. | No browser-state interface; interactive in-memory boundary; closed semantic artifacts and secret-canary tests. |
| T-00-02 | Candidate impersonates another identity, guesses provider facts, or retains a fallback. | Public first-party exact evidence; system/default honest identity; exactly one conditional target. |
| T-00-03 | Concurrency, retry, duplicate/partial proof, or automated cooldown creates false GO. | One in flight; owner-controlled cooldown; exact two ordered distinct same-path proofs; all other shapes block. |
| T-00-04 | One protected, challenged, rate-limited, suspicious, unknown, or ambiguous state triggers continued probing. | First stop is terminal; cancel/invalidate; NO-GO; no retry threshold, tolerance, alternate path, or third run. |
| T-00-05 | Malformed/secret-bearing/conflicting artifact unlocks Phase 1. | Strict allow-list, exact decision cardinality, consistent continuation, and fail-closed Phase 1 handoff. |

## Validation Sign-Off

- [x] Every planned task has an exact automated verification; human-only tasks have pre/post automated gates.
- [x] No automated verification invokes a live candidate, browser, SiriusXM, account, retry, poll, timer, or cooldown.
- [x] Wave 0 tests cover all FEAS requirements and all 11 spec-less edge candidates.
- [x] Unsupported is a fully validated zero-live-run branch, not a missing test path.
- [x] Full feedback loop targets under 10 seconds on the installed Swift 6.3.3 command-line toolchain.
- [x] `nyquist_compliant: true` reflects exact plan/task reconciliation; `wave_0_complete` remains false until Plan 00-01 executes.

**Approval:** ready for plan verification
