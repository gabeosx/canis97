---
phase: 1
slug: safe-interoperability-foundation
status: planned
nyquist_compliant: true
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
- **Before `$gsd-verify-work`:** Strict validation of all four Phase 0 artifacts plus fresh selection/decision derivation and byte comparison must establish an exact GO+unlocked bundle; raw decision text or a partial closure generation is non-authoritative. The full Phase 1 package/native synthetic suite must also be green.
- **Max feedback latency:** 120 seconds for automated tests; Phase 1 performs no live authentication or repeated proof run.

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 01-01-01 | 01-01 | 1 | CLNT-01, CLNT-02, CLNT-04 | T-01-01, T-01-02, T-01-05 | Full Phase 0 chain freshly derives exact GO+unlocked before any production file; native Retry then reaches safe unavailable default with zero live attempts | preflight + tracer/app | Exact command in `01-01-PLAN.md` Task 01-01-01 and reconciliation block below | ❌ pre-execution | ⬜ pending |
| 01-01-02 | 01-01 | 1 | CLNT-01, CLNT-02, CLNT-04 | T-01-05 | Independent consumer compiles/awaits typed authentication, entitlement, catalog, metadata, and live-stream-resolution contracts; content operations are typed unavailable with zero transport calls and no public wire-detail fields | compile/API | `swift test --package-path Packages/SiriusXMClient --filter PublicConsumerTests` | ❌ pre-execution | ⬜ pending |
| 01-02-01 | 01-02 | 2 | AUTH-01, AUTH-02, CLNT-02, CLNT-03 | T-01-02, T-01-05 | Synthetic known and terminal shapes map to strict semantic outcomes | unit/contract | `swift test --package-path Packages/SiriusXMClient --filter AuthenticationOutcomeTests` | ❌ pre-execution | ⬜ pending |
| 01-02-02 | 01-02 | 2 | AUTH-02, SECR-02, CLNT-04 | T-01-04, T-01-05 | One actor permits one in-flight attempt and no retry/fallback | unit/concurrency | `swift test --package-path Packages/SiriusXMClient --filter SessionCoordinatorTests` | ❌ pre-execution | ⬜ pending |
| 01-03-01 | 01-03 | 2 | AUTH-02, SECR-02, CLNT-03, CLNT-04 | T-01-01, T-01-03, T-01-05 | Ephemeral transport rejects all hosts before evidence and validates redirects | unit | `swift test --package-path Packages/SiriusXMClient --filter EphemeralSessionTests` | ❌ pre-execution | ⬜ pending |
| 01-03-02 | 01-03 | 2 | SECR-03, CLNT-04 | T-01-03, T-01-06 | Closed diagnostics and structural redaction exclude synthetic canaries | unit/fixture | `swift test --package-path Packages/SiriusXMClient --filter RedactionTests` | ❌ pre-execution | ⬜ pending |
| 01-04-01 | 01-04 | 3 | SECR-01, CLNT-04 | T-01-03, T-01-06 | App-owned Keychain adapter performs isolated CRUD and post-success-only save | app integration | `xcodebuild -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS' -only-testing:SiriusMacTests/KeychainCredentialStoreTests test` | ❌ pre-execution | ⬜ pending |
| 01-04-02 | 01-04 | 3 | AUTH-03, SECR-02 | T-01-03, T-01-04 | Sign-out clears memory before deletion and reports cleanup failure | unit | `swift test --package-path Packages/SiriusXMClient --filter SignOutTests` | ❌ pre-execution | ⬜ pending |
| 01-05-01 | 01-05 | 3 | AUTH-01, AUTH-02, SECR-03, CLNT-01 | T-01-01, T-01-02, T-01-06 | Dedicated unsupported UI renders typed safe state with no player shell | app model/UI | `xcodebuild -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS' -only-testing:SiriusMacTests/AuthenticationPresentationModelTests test` | ❌ pre-execution | ⬜ pending |
| 01-05-02 | 01-05 | 3 | AUTH-01, AUTH-02, SECR-03 | T-01-01, T-01-04, T-01-06 | Explicit Retry is single-attempt and official-site navigation is one-way | app model/UI | `xcodebuild -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS' -only-testing:SiriusMacTests/AuthenticationPresentationModelTests test` | ❌ pre-execution | ⬜ pending |
| 01-06-01 | 01-06 | 4 | AUTH-01, AUTH-02 | T-01-01, T-01-02, T-01-05 | Strictly revalidate/re-derive Phase 0 and accept exact GO+unlocked only; no live/evidence work repeats | automated phase gate | Exact command in `01-06-PLAN.md` Task 01-06-01 and reconciliation block below | ❌ pre-execution | ⬜ pending |
| 01-06-02 | 01-06 | 4 | AUTH-01, AUTH-02 | T-01-02, T-01-05, T-01-06 | Normalized browser-return/native-direct handoff matches validated Phase 0 decision exactly | automated handoff | Exact command in `01-06-PLAN.md` Task 01-06-02 and reconciliation block below | ❌ pre-execution | ⬜ pending |
| 01-07-01 | 01-07 | 5 | AUTH-01, AUTH-02, AUTH-03, SECR-02, SECR-03, CLNT-02, CLNT-03, CLNT-04 | T-01-01..T-01-06 | Phase 0, handoff, and selected implementation path match; invalid state preserves unavailable default | phase gate + unit/contract | Exact command in `01-07-PLAN.md` Task 01-07-01 and reconciliation block below | ❌ pre-execution | ⬜ pending |
| 01-07-02 | 01-07 | 5 | AUTH-01, AUTH-02, AUTH-03, SECR-01, SECR-03, CLNT-01, CLNT-04 | T-01-01..T-01-06 | App exposes one selected surface or complete unsupported state and clean sign-out | app integration | `xcodebuild -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS' -only-testing:SiriusMacTests/SelectedAuthenticationCompositionTests test` | ❌ pre-execution | ⬜ pending |
| 01-08-01 | 01-08 | 6 | AUTH-01, AUTH-02, AUTH-03, SECR-01, SECR-02, SECR-03, CLNT-02, CLNT-03, CLNT-04 | T-01-01..T-01-06 | Matching Phase 0/01-06/01-07 path passes synthetic auth, entitlement, stop, redaction, and cleanup acceptance | automated package acceptance | Exact command in `01-08-PLAN.md` Task 01-08-01 and reconciliation block below | ❌ pre-execution | ⬜ pending |
| 01-08-02 | 01-08 | 6 | AUTH-01, AUTH-02, AUTH-03, SECR-01, SECR-02, SECR-03, CLNT-01, CLNT-04 | T-01-01..T-01-06 | Native composition matches selected path and summary records production acceptance with no repeated live proof | automated app acceptance | Exact command in `01-08-PLAN.md` Task 01-08-02 and reconciliation block below | ❌ pre-execution | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

Threat references:

- `T-01-01`: browser cookie or storage extraction
- `T-01-02`: CAPTCHA, MFA, anti-bot, device-limit, or other control circumvention
- `T-01-03`: credential, token, fixture, or diagnostic disclosure
- `T-01-04`: concurrent or automatic retry request storm
- `T-01-05`: protocol drift accepted as authenticated or leaked through the public API

---

## Changed-Task Exact Automated Command Reconciliation

These blocks are copied verbatim from the changed tasks' `<automated>` elements and are the canonical commands for the rows above.

### 01-01-01

```sh
evidence=.planning/phases/00-authentication-feasibility-gate/00-EVIDENCE.md; selection=.planning/phases/00-authentication-feasibility-gate/00-SELECTION.md; owner=.planning/phases/00-authentication-feasibility-gate/00-OWNER-RESULT.md; decision_file=.planning/phases/00-authentication-feasibility-gate/00-DECISION.md; derived_selection=$(mktemp) || exit 1; derived_decision=$(mktemp) || { rm -f "$derived_selection"; exit 1; }; trap 'rm -f "$derived_selection" "$derived_decision"' EXIT; swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility validate-evidence "$evidence" &amp;&amp; swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility derive-selection --evidence "$evidence" --output "$derived_selection" &amp;&amp; cmp -s "$derived_selection" "$selection" &amp;&amp; swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility validate-selection "$selection" &amp;&amp; swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility validate-owner-result "$owner" &amp;&amp; swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility derive-decision --selection "$selection" --evidence "$evidence" --owner-result "$owner" --output "$derived_decision" &amp;&amp; cmp -s "$derived_decision" "$decision_file" &amp;&amp; swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility validate-decision "$decision_file" &amp;&amp; decision=$(sed -n 's/^Feasibility decision: //p' "$decision_file") &amp;&amp; continuation=$(sed -n 's/^Phase 1 continuation: //p' "$decision_file") &amp;&amp; case "$decision:$continuation" in 'GO browser-return:unlocked'|'GO native-direct:unlocked') true;; *) false;; esac &amp;&amp; xcodebuild -version &gt;/dev/null &amp;&amp; xcodebuild -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS' -only-testing:SiriusMacTests/CompatibilityTracerTests test
```

### 01-06-01

```sh
evidence=.planning/phases/00-authentication-feasibility-gate/00-EVIDENCE.md; selection=.planning/phases/00-authentication-feasibility-gate/00-SELECTION.md; owner=.planning/phases/00-authentication-feasibility-gate/00-OWNER-RESULT.md; decision_file=.planning/phases/00-authentication-feasibility-gate/00-DECISION.md; derived_selection=$(mktemp) || exit 1; derived_decision=$(mktemp) || { rm -f "$derived_selection"; exit 1; }; trap 'rm -f "$derived_selection" "$derived_decision"' EXIT; swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility validate-evidence "$evidence" &amp;&amp; swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility derive-selection --evidence "$evidence" --output "$derived_selection" &amp;&amp; cmp -s "$derived_selection" "$selection" &amp;&amp; swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility validate-selection "$selection" &amp;&amp; swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility validate-owner-result "$owner" &amp;&amp; swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility derive-decision --selection "$selection" --evidence "$evidence" --owner-result "$owner" --output "$derived_decision" &amp;&amp; cmp -s "$derived_decision" "$decision_file" &amp;&amp; swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility validate-decision "$decision_file" &amp;&amp; decision=$(sed -n 's/^Feasibility decision: //p' "$decision_file") &amp;&amp; continuation=$(sed -n 's/^Phase 1 continuation: //p' "$decision_file") &amp;&amp; case "$decision:$continuation" in 'GO browser-return:unlocked'|'GO native-direct:unlocked') true;; *) false;; esac
```

### 01-06-02

```sh
decision_file=.planning/phases/00-authentication-feasibility-gate/00-DECISION.md; summary=.planning/phases/01-safe-interoperability-foundation/01-06-SUMMARY.md; [ -r "$summary" ] &amp;&amp; [ "$(rg -c '^Selected authentication result:' "$summary")" -eq 1 ] &amp;&amp; [ "$(rg -c '^Phase 0 continuation consumed:' "$summary")" -eq 1 ] &amp;&amp; selected=$(sed -n 's/^Selected authentication result: //p' "$summary") &amp;&amp; decision=$(sed -n 's/^Feasibility decision: GO //p' "$decision_file") &amp;&amp; consumed=$(sed -n 's/^Phase 0 continuation consumed: //p' "$summary") &amp;&amp; [ "$selected" = "$decision" ] &amp;&amp; [ "$consumed" = unlocked ] &amp;&amp; case "$selected" in browser-return|native-direct) true;; *) false;; esac
```

### 01-07-01

```sh
evidence=.planning/phases/00-authentication-feasibility-gate/00-EVIDENCE.md; selection=.planning/phases/00-authentication-feasibility-gate/00-SELECTION.md; owner=.planning/phases/00-authentication-feasibility-gate/00-OWNER-RESULT.md; decision_file=.planning/phases/00-authentication-feasibility-gate/00-DECISION.md; handoff=.planning/phases/01-safe-interoperability-foundation/01-06-SUMMARY.md; derived_selection=$(mktemp) || exit 1; derived_decision=$(mktemp) || { rm -f "$derived_selection"; exit 1; }; trap 'rm -f "$derived_selection" "$derived_decision"' EXIT; swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility validate-evidence "$evidence" &amp;&amp; swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility derive-selection --evidence "$evidence" --output "$derived_selection" &amp;&amp; cmp -s "$derived_selection" "$selection" &amp;&amp; swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility validate-selection "$selection" &amp;&amp; swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility validate-owner-result "$owner" &amp;&amp; swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility derive-decision --selection "$selection" --evidence "$evidence" --owner-result "$owner" --output "$derived_decision" &amp;&amp; cmp -s "$derived_decision" "$decision_file" &amp;&amp; swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility validate-decision "$decision_file" &amp;&amp; phase0_path=$(sed -n 's/^Feasibility decision: GO //p' "$decision_file") &amp;&amp; handoff_path=$(sed -n 's/^Selected authentication result: //p' "$handoff") &amp;&amp; consumed=$(sed -n 's/^Phase 0 continuation consumed: //p' "$handoff") &amp;&amp; [ "$phase0_path" = "$handoff_path" ] &amp;&amp; [ "$consumed" = unlocked ] &amp;&amp; case "$phase0_path" in browser-return|native-direct) true;; *) false;; esac &amp;&amp; swift test --package-path Packages/SiriusXMClient --filter SelectedAuthenticationPathTests
```

### 01-08-01

```sh
evidence=.planning/phases/00-authentication-feasibility-gate/00-EVIDENCE.md; selection=.planning/phases/00-authentication-feasibility-gate/00-SELECTION.md; owner=.planning/phases/00-authentication-feasibility-gate/00-OWNER-RESULT.md; decision_file=.planning/phases/00-authentication-feasibility-gate/00-DECISION.md; handoff=.planning/phases/01-safe-interoperability-foundation/01-06-SUMMARY.md; implementation=.planning/phases/01-safe-interoperability-foundation/01-07-SUMMARY.md; derived_selection=$(mktemp) || exit 1; derived_decision=$(mktemp) || { rm -f "$derived_selection"; exit 1; }; trap 'rm -f "$derived_selection" "$derived_decision"' EXIT; swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility validate-evidence "$evidence" &amp;&amp; swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility derive-selection --evidence "$evidence" --output "$derived_selection" &amp;&amp; cmp -s "$derived_selection" "$selection" &amp;&amp; swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility validate-selection "$selection" &amp;&amp; swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility validate-owner-result "$owner" &amp;&amp; swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility derive-decision --selection "$selection" --evidence "$evidence" --owner-result "$owner" --output "$derived_decision" &amp;&amp; cmp -s "$derived_decision" "$decision_file" &amp;&amp; swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility validate-decision "$decision_file" &amp;&amp; phase0_path=$(sed -n 's/^Feasibility decision: GO //p' "$decision_file") &amp;&amp; handoff_path=$(sed -n 's/^Selected authentication result: //p' "$handoff") &amp;&amp; implemented_path=$(sed -n 's/^Implemented authentication result: //p' "$implementation") &amp;&amp; readiness=$(sed -n 's/^Continuation readiness: //p' "$implementation") &amp;&amp; [ "$phase0_path" = "$handoff_path" ] &amp;&amp; [ "$phase0_path" = "$implemented_path" ] &amp;&amp; [ "$readiness" = production-selected-path-tested ] &amp;&amp; swift test --package-path Packages/SiriusXMClient --filter SelectedAuthenticationPathTests &amp;&amp; swift test --package-path Packages/SiriusXMClient --filter SignOutTests &amp;&amp; swift test --package-path Packages/SiriusXMClient --filter RedactionTests
```

### 01-08-02

```sh
summary=.planning/phases/01-safe-interoperability-foundation/01-08-SUMMARY.md; decision_file=.planning/phases/00-authentication-feasibility-gate/00-DECISION.md; xcodebuild -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS' -only-testing:SiriusMacTests/SelectedAuthenticationCompositionTests test &amp;&amp; [ "$(rg -c '^Phase 0 path consumed:' "$summary")" -eq 1 ] &amp;&amp; [ "$(rg -c '^Production authentication acceptance:' "$summary")" -eq 1 ] &amp;&amp; [ "$(rg -c '^Live proof repeated:' "$summary")" -eq 1 ] &amp;&amp; [ "$(rg -c '^Phase 2 readiness:' "$summary")" -eq 1 ] &amp;&amp; consumed=$(sed -n 's/^Phase 0 path consumed: //p' "$summary") &amp;&amp; phase0=$(sed -n 's/^Feasibility decision: GO //p' "$decision_file") &amp;&amp; [ "$consumed" = "$phase0" ] &amp;&amp; rg -q '^Production authentication acceptance: passed$' "$summary" &amp;&amp; rg -q '^Live proof repeated: no$' "$summary" &amp;&amp; rg -q '^Phase 2 readiness: ready-for-authorized-live-listening$' "$summary"
```


## Wave 0 / Plan 01-01 Requirements

- [ ] `Packages/SiriusXMClient/Package.swift` — Plan 01-01 creates the `SiriusXMClient` library product and test targets.
- [ ] `Packages/SiriusXMClient/Tests/SiriusXMClientTests/` — scripted transport, clock, and serialized session tests.
- [ ] `Packages/SiriusXMClient/Tests/FixtureTests/` — synthetic fixture scrubber and canary-secret tests.
- [ ] `Packages/SiriusXMClient/Tests/PublicAPITests/` — independent-consumer compile/API tests.
- [ ] Full Xcode installation and active developer directory — required before native app-target tests can run.

---

## Manual-Only Verifications

None in Phase 1. Public-evidence qualification and exactly two owner-operated live proof runs occur only in Phase 0. Phase 1 consumes the deterministic Phase 0 GO artifact and uses synthetic collaborators for production acceptance.

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies.
- [ ] Sampling continuity: no 3 consecutive tasks without automated verification.
- [ ] Wave 0 covers all missing references.
- [ ] No watch-mode flags.
- [ ] Feedback latency is below 120 seconds once infrastructure exists.
- [x] Phase 1 contains no authorized smoke test, live browser/account checkpoint, cooldown, or repeated proof run.
- [x] `nyquist_compliant: true` reflects the reconciled plan/task map; execution statuses remain pending.

**Approval:** ready for plan verification
