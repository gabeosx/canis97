---
phase: 00
slug: authentication-feasibility-gate
status: planned
nyquist_compliant: true
wave_0_complete: false
created: 2026-08-17
updated: 2026-08-17
---

# Phase 00 — Validation Strategy

> Validation contract for replacement plans 00-05 through 00-13. Live provider operations are never automated; every automated branch uses synthetic/public inputs and must prove that ineligible states have no protected-surface constructor.

## Test Architecture

| Layer | Framework | Role |
|---|---|---|
| Command-line safety core | Swift Testing via SwiftPM | Canonical evidence, experiment readiness, candidate, finalization, and stop-state invariants under Command Line Tools. |
| Toolchain preflight | Shell plus Swift parser tests | Exact selected Xcode 26.6/macOS 26.5 SDK/framework-import readiness without a fixed installation path. |
| Conditional macOS harness | Swift Testing with current Xcode SDK | Browser-return, AVFoundation, native-direct, source-graph, and cleanup tests only when exact current-SDK readiness validates. |
| Incomplete/terminal branches | Command-line Swift tests | Proves no GUI/live source or command exists and distinguishes fixed incomplete status from canonical terminal `NO-GO unsupported`. |
| Owner protocol | Blocking decision/action checkpoints | Bounded-experiment approval and the two live proof runs; pre/post automation validates only closed artifacts. |
| Supersession authority | Shell field checks plus finalizer tests | Proves 00-01..00-04 remain historical, 00-05..00-13 are active, Phase 1 stays blocked during execution, and authority changes only after a newly generated quartet validates. |

Quick command-line loop:

```sh
swift test --package-path Spikes/AuthenticationFeasibility
```

Conditional current-SDK loop:

```sh
bash Spikes/AuthenticationFeasibility/Scripts/verify-current-xcode.sh --require-ready-or-closed
xcrun swift test --package-path Spikes/AuthenticationFeasibility
```

No validation command opens provider content, accepts account input, performs a live request, retries, polls, schedules work, or controls the human cooldown.

## Task-to-Verification Map

| Wave | Task | Type | Automated verification | Human/conditional assertion | Threat refs |
|---:|---|---|---|---|---|
| 1 | 00-05-01 | tracer/TDD | `supersession=.planning/phases/00-authentication-feasibility-gate/00-SUPERSESSION.md; test -r "$supersession" && rg -q '^Schema: phase-0-supersession-v1$' "$supersession" && rg -q '^Status: replacement-planned$' "$supersession" && rg -q '^Active plan range: 00-05\.\.00-13$' "$supersession" && rg -q '^Replacement execution complete: no$' "$supersession" && rg -q '^Phase 1 continuation: blocked$' "$supersession" && swift test --package-path Spikes/AuthenticationFeasibility --filter ToolchainGateTests` | Supersession authorizes only the replacement set; toolchain gaps produce environment-pending/incomplete, not a provider NO-GO. | T-00-05-01, T-00-05-04, T-00-05-SC |
| 1 | 00-05-02 | TDD | `supersession=.planning/phases/00-authentication-feasibility-gate/00-SUPERSESSION.md; test -r "$supersession" && rg -q '^Status: replacement-planned$' "$supersession" && rg -q '^Active plan range: 00-05\.\.00-13$' "$supersession" && rg -q '^Replacement execution complete: no$' "$supersession" && rg -q '^Phase 1 continuation: blocked$' "$supersession" && swift test --package-path Spikes/AuthenticationFeasibility --filter ContractTracerTests` | Historical quartet cannot be copied or hand-edited into replacement authority. | T-00-05-03, T-00-05-04 |
| 2 | 00-06-01 | TDD | `swift test --package-path Spikes/AuthenticationFeasibility --filter PublicAuthContractTests` | Closed safe-construction/native-purpose schema accepts no raw, secret-bearing, or browser-state evidence and treats documentation-open as non-dispositive. | T-00-06-01, T-00-06-02, T-00-06-04 |
| 2 | 00-06-02 | TDD | `swift test --package-path Spikes/AuthenticationFeasibility --filter PublicAuthContractTests` | Exact safe construction may create a browser experiment even with open third-party docs; native purpose qualification alone cannot select. | T-00-06-02 through T-00-06-04 |
| 3 | 00-07-01 | auto | `swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility validate-auth-experiment-contract .planning/phases/00-authentication-feasibility-gate/00-PUBLIC-AUTH-CONTRACT.md && swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility derive-experiment-readiness .planning/phases/00-authentication-feasibility-gate/00-TOOLCHAIN.md .planning/phases/00-authentication-feasibility-gate/00-PUBLIC-AUTH-CONTRACT.md` | Safe bounds plus documentation-open produce experiment-ready; missing safety inputs produce incomplete and no owner/live command. | T-00-07-01 through T-00-07-04 |
| 3 | 00-07-02 | checkpoint:decision | `swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility validate-experiment-approval .planning/phases/00-authentication-feasibility-gate/00-PUBLIC-AUTH-CONTRACT.md .planning/phases/00-authentication-feasibility-gate/00-PUBLIC-AUTH-CONTRACT-APPROVAL.md` | Owner approves/rejects exact construction, provenance, semantic observation, and stop bounds; incomplete records `not-presented`. | T-00-07-01 through T-00-07-03 |
| 4 | 00-08-01 | TDD | `bash Spikes/AuthenticationFeasibility/Scripts/verify-current-xcode.sh --check-conditional .planning/phases/00-authentication-feasibility-gate/00-TOOLCHAIN.md .planning/phases/00-authentication-feasibility-gate/00-PUBLIC-AUTH-CONTRACT.md .planning/phases/00-authentication-feasibility-gate/00-PUBLIC-AUTH-CONTRACT-APPROVAL.md && xcrun swift test --package-path Spikes/AuthenticationFeasibility --filter BrowserReturnContractTests` | Experiment-ready configuration has one owner-operated WKWebView; every blocked row has no GUI/browser source. | T-00-08-01, T-00-08-02, T-00-08-SC |
| 4 | 00-08-02 | TDD | `bash Spikes/AuthenticationFeasibility/Scripts/verify-current-xcode.sh --check-conditional .planning/phases/00-authentication-feasibility-gate/00-TOOLCHAIN.md .planning/phases/00-authentication-feasibility-gate/00-PUBLIC-AUTH-CONTRACT.md .planning/phases/00-authentication-feasibility-gate/00-PUBLIC-AUTH-CONTRACT-APPROVAL.md && xcrun swift test --package-path Spikes/AuthenticationFeasibility --filter BrowserReturnContractTests` | Explicit return material collapses to semantics; no browser store/state is enumerated, and no-clean-return remains incomplete absent D-09 proof. | T-00-08-02 through T-00-08-04 |
| 5 | 00-09-01 | TDD | `bash Spikes/AuthenticationFeasibility/Scripts/verify-current-xcode.sh --require-ready-or-closed && xcrun swift test --package-path Spikes/AuthenticationFeasibility --filter AuthorizedPlaybackProbeTests && xcrun swift test --package-path Spikes/AuthenticationFeasibility --filter RenewalObserverTests` | Blocked is incomplete/not-applicable; renewal absence is incomplete, never terminal. | T-00-09-01 through T-00-09-03 |
| 5 | 00-09-02 | TDD | `bash Spikes/AuthenticationFeasibility/Scripts/verify-current-xcode.sh --require-ready-or-closed && xcrun swift test --package-path Spikes/AuthenticationFeasibility --filter CleanupCoordinatorTests && xcrun swift test --package-path Spikes/AuthenticationFeasibility --filter BrowserProofPreflightTests` | Every exit reaches idempotent cleanup; blocked branches perform no provider work. | T-00-09-02 through T-00-09-04 |
| 6 | 00-10-01 | checkpoint:human-action | `bash Spikes/AuthenticationFeasibility/Scripts/verify-current-xcode.sh --require-ready-or-closed && swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility validate-browser-launch-gate .planning/phases/00-authentication-feasibility-gate/00-TOOLCHAIN.md .planning/phases/00-authentication-feasibility-gate/00-PUBLIC-AUTH-CONTRACT.md .planning/phases/00-authentication-feasibility-gate/00-PUBLIC-AUTH-CONTRACT-APPROVAL.md && swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility validate-live-result --candidate browser-return .planning/phases/00-authentication-feasibility-gate/00-BROWSER-PROBE.md` | Owner alone performs ready runs; no-clean-return/renewal gaps are incomplete, locked protected classes terminal, and D-09 rule-out exact. | T-00-10-01 through T-00-10-03 |
| 6 | 00-10-02 | checkpoint:decision | `swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility validate-native-approval .planning/phases/00-authentication-feasibility-gate/00-PUBLIC-AUTH-CONTRACT.md .planning/phases/00-authentication-feasibility-gate/00-BROWSER-PROBE.md .planning/phases/00-authentication-feasibility-gate/00-NATIVE-DIRECT-APPROVAL.md` | Decision appears only for strict WebKit rule-out plus native-purpose-qualified allowable sanitized evidence. | T-00-10-02, T-00-10-04 |
| 7 | 00-11-01 | TDD | `bash Spikes/AuthenticationFeasibility/Scripts/verify-current-xcode.sh --require-ready-or-closed && swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility validate-native-approval .planning/phases/00-authentication-feasibility-gate/00-PUBLIC-AUTH-CONTRACT.md .planning/phases/00-authentication-feasibility-gate/00-BROWSER-PROBE.md .planning/phases/00-authentication-feasibility-gate/00-NATIVE-DIRECT-APPROVAL.md && xcrun swift test --package-path Spikes/AuthenticationFeasibility --filter NativeFallbackGateTests` | Eligible source graph contains native-direct only; incomplete and terminal rows contain no native source. | T-00-11-01, T-00-11-03 |
| 7 | 00-11-02 | TDD | `bash Spikes/AuthenticationFeasibility/Scripts/verify-current-xcode.sh --require-ready-or-closed && xcrun swift test --package-path Spikes/AuthenticationFeasibility --filter NativeDirectPreflightTests` | Missing safe purpose-contract value blocks before request; authorized synthetic path clears volatile input. | T-00-11-02 through T-00-11-04 |
| 8 | 00-12-01 | auto | `bash Spikes/AuthenticationFeasibility/Scripts/verify-current-xcode.sh --require-ready-or-closed && swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility validate-native-launch-gate .planning/phases/00-authentication-feasibility-gate/00-TOOLCHAIN.md .planning/phases/00-authentication-feasibility-gate/00-PUBLIC-AUTH-CONTRACT.md .planning/phases/00-authentication-feasibility-gate/00-BROWSER-PROBE.md .planning/phases/00-authentication-feasibility-gate/00-NATIVE-DIRECT-APPROVAL.md` | Every ineligible row produces precise incomplete/not-applicable or terminal NO-GO without credential UI. | T-00-12-02, T-00-12-03 |
| 8 | 00-12-02 | checkpoint:human-action | `swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility validate-live-result --candidate native-direct .planning/phases/00-authentication-feasibility-gate/00-NATIVE-PROBE.md` | Owner alone performs the eligible two-run protocol; first unsafe state stops. | T-00-12-01, T-00-12-03, T-00-12-04 |
| 9 | 00-13-01 | TDD | `swift test --package-path Spikes/AuthenticationFeasibility --filter FinalizationGateTests` | Exhaustive table covers prerequisite/no-return/renewal/native-contract incomplete, browser/native GO, and locked terminal NO-GO. | T-00-13-01 through T-00-13-03 |
| 9 | 00-13-02 | auto | `evidence=.planning/phases/00-authentication-feasibility-gate/00-EVIDENCE.md; selection=.planning/phases/00-authentication-feasibility-gate/00-SELECTION.md; owner=.planning/phases/00-authentication-feasibility-gate/00-OWNER-RESULT.md; decision_file=.planning/phases/00-authentication-feasibility-gate/00-DECISION.md; supersession=.planning/phases/00-authentication-feasibility-gate/00-SUPERSESSION.md; swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility validate-bundle "$evidence" "$selection" "$owner" "$decision_file" && rg -q '^Status: replacement-finalized$' "$supersession" && rg -q '^Replacement execution complete: yes$' "$supersession" && rg -Fxq 'Current status authority: canonical-quartet+00-SUPERSESSION.md' "$supersession" && decision=$(sed -n 's/^Feasibility decision: //p' "$decision_file") && continuation=$(sed -n 's/^Phase 1 continuation: //p' "$decision_file") && supersession_continuation=$(sed -n 's/^Phase 1 continuation: //p' "$supersession") && case "$decision:$continuation:$supersession_continuation" in 'GO browser-return:unlocked:unlocked'|'GO native-direct:unlocked:unlocked') swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility require-phase-one-go "$evidence" "$selection" "$owner" "$decision_file";; 'NO-GO unsupported:blocked:blocked') ! swift run --package-path Spikes/AuthenticationFeasibility auth-feasibility require-phase-one-go "$evidence" "$selection" "$owner" "$decision_file";; *) false;; esac` | A newly generated canonical quartet closes supersession and transfers current authority; GO passes the independent Phase 1 gate, NO-GO fails it closed, and every incomplete class leaves replacement-planned/blocked. | T-00-13-01 through T-00-13-04 |

## Conditional Branch Matrix

| Toolchain | Browser experiment contract | Experiment approval | Browser result | Native purpose contract | Native approval | Native result | Expected behavior | Live surfaces permitted |
|---|---|---|---|---|---|---|---|---|
| unavailable/mismatch | any | not-presented | absent | any | not-applicable | absent | incomplete `environment-pending`; Phase 1 blocked | none |
| ready | safe bounds missing | not-presented | absent | any | not-applicable | absent | incomplete `browser-experiment-incomplete`; Phase 1 blocked | none |
| ready | experiment-ready + documentation-open | rejected | absent | any | not-applicable | absent | canonical `NO-GO unsupported` for explicit owner rejection | none |
| ready | experiment-ready + documentation-open | approved | complete | any | not-applicable | not-applicable | `GO browser-return` | owner browser proof only |
| ready | experiment-ready + documentation-open | approved | no-clean-return without D-09 proof | any | not-applicable | absent | incomplete; no native unlock or terminal decision | owner browser proof only |
| ready | experiment-ready + documentation-open | approved | renewal-pending | any | not-applicable | absent | incomplete; no terminal decision | owner browser proof only |
| ready | experiment-ready + documentation-open | approved | protected/challenged/rate/403/429/bot/access-control/suspicious/ambiguous | any | not-applicable | absent | canonical `NO-GO unsupported` | no further live activity |
| ready | experiment-ready + documentation-open | approved | strict-webkit-ruleout | incomplete | not-applicable | absent | incomplete; no native surface | none |
| ready | experiment-ready + documentation-open | approved | strict-webkit-ruleout | purpose-qualified | rejected | not-applicable | canonical `NO-GO unsupported` | no native surface |
| ready | experiment-ready + documentation-open | approved | strict-webkit-ruleout | purpose-qualified | approved | complete | `GO native-direct` | owner native proof only |
| ready | experiment-ready + documentation-open | approved | strict-webkit-ruleout | purpose-qualified | approved | renewal-pending | incomplete; no terminal decision | owner native proof only |
| ready | experiment-ready + documentation-open | approved | strict-webkit-ruleout | purpose-qualified | approved | terminal-stop | canonical `NO-GO unsupported` | no further live activity |

Any row not listed above is contradictory/unknown and must fail validation without creating a candidate or decision.

## Wave 0 Test Requirements

- [ ] `00-SUPERSESSION.md` validates as replacement-planned with active range 00-05..00-13, historical range 00-01..00-04, replacement incomplete, and Phase 1 blocked before any replacement task.
- [ ] `ToolchainGateTests.swift` invokes `verify-current-xcode.sh` with injected and real command results and covers exact versions, selected-tool discovery, framework imports, every failure point, artifact canonicalization, and environment-pending incomplete routing.
- [ ] `ContractTracerTests.swift` covers revision migration, canonical bytes, exact decision set, two-run cardinality/order, renewal, cooldown, cleanup, terminal stops, and unchanged Phase 1 signature.
- [ ] `PublicAuthContractTests.swift` covers safe construction with documentation-open, missing/unsafe bounds, sanitized-preliminary provenance, native purpose qualification, duplicate, conflicting, raw/private, non-first-party-entry, and unrecognized input.
- [ ] `BrowserReturnContractTests.swift` proves explicit in-memory app-bound return behavior, ordinary no-clean-return, no authenticated-browser state query/enumeration API, and no GUI/live target, command, constructor, or provider activity for blocked branches.
- [ ] `AuthorizedPlaybackProbeTests.swift`, `RenewalObserverTests.swift`, `CleanupCoordinatorTests.swift`, and `BrowserProofPreflightTests.swift` cover the fixed full run and every incomplete/terminal cleanup path.
- [ ] `NativeFallbackGateTests.swift` covers every predicate flip, native purpose-contract requirement, source-graph replacement, and no-selector invariant.
- [ ] `NativeDirectPreflightTests.swift` covers ineligible source absence, owner-only volatile input, allowable-sanitized purpose-operation binding, stop handling, and full-chain parity.
- [ ] `FinalizationGateTests.swift` covers the complete conditional branch matrix, sensitive-field rejection, atomic/canonical artifacts, and Phase 1 GO/NO-GO/incomplete behavior.
- [ ] Synthetic fixtures contain no provider endpoint, account value, callback value, response content, authorization material, media URL, key material, or precise time.

## Manual Checkpoints

| Task | Gate | Owner action | Automated pre/post condition |
|---|---|---|---|
| 00-07-02 | Experiment contract approval | Review first-party entry/provenance, sanitized expectation classes, app-bound observation allowlist, and terminal stop bounds; approve/reject the exact digest. | `validate-experiment-approval`; incomplete branch is `not-presented`. |
| 00-10-01 | Browser proof | Eligible branch only: operate two browser runs, confirm audio, sign-out/cleanup, and cooldown. | `validate-browser-launch-gate` before; `validate-live-result` after. |
| 00-10-02 | Native disclosure | Strict-rule-out plus native-purpose-qualified branch only: approve/reject the disclosed password boundary. | `validate-native-approval`; other branches are incomplete, not-applicable, or terminal NO-GO as classified. |
| 00-12-02 | Native proof | Exact eligible branch only: operate two native runs, confirm audio, sign-out/cleanup, and cooldown. | `validate-native-launch-gate` before; `validate-live-result` after. |

## Security Verification

| Plan | Threat focus | Required evidence |
|---|---|---|
| 00-05 | Status spoofing, toolchain spoofing, contract tampering, premature candidate creation | Exact supersession fields; exact-version/import tests; environment-pending distinction; no GUI target in command-line package. |
| 00-06 | Construction-provenance spoofing, tampering, premature candidate creation | Strict schema, first-party entry/provenance, sanitized-expectation labels, documentation-open test, deterministic digest. |
| 00-07 | Provenance spoofing and approval tampering | Canonical experiment contract and owner decision bound to exact bytes and observation bounds. |
| 00-08 | Conditional-source elevation and browser disclosure | Source-graph absence tests, exact app-bound return tests, no authenticated-state query API. |
| 00-09 | Playback/renewal disclosure and cleanup tampering | Bounded AV tests, legitimate renewal tests, one-attempt teardown and absence proof. |
| 00-10 | Owner-boundary disclosure and fallback elevation | Launch conjunction, fixed resume classes, no decision prompt outside eligible rows. |
| 00-11 | Native source elevation, credential disclosure, client spoofing | Full eligibility table, honest native purpose contract from allowable sanitized evidence, volatile-input clearing, one-live-path source graph. |
| 00-12 | Unauthorized native launch and repeated attempts | Ineligible not-applicable/NO-GO proof, owner stop boundary, exact two-run validator. |
| 00-13 | Supersession/artifact tampering, disclosure, Phase 1 elevation | Atomic fresh quartet generation, post-write byte validation, derived supersession closure, and unchanged `auth-feasibility` GO gate in all outcome classes. |

## Feedback Cadence

- After every task: run its focused command from the map above.
- After every wave: run `swift test --package-path Spikes/AuthenticationFeasibility`; when the branch is current-SDK-ready, also run the full `xcrun swift test` suite.
- Before either live checkpoint: full synthetic suite plus the exact conditional launch validator; no test may launch provider content.
- Final phase gate: full suite, finalization truth table, canonical bundle validation, and unchanged Phase 1 gate in GO/NO-GO/incomplete cases.
- Supersession gate: every fixed incomplete class retains replacement-planned/blocked; terminal GO/NO-GO changes status only after the newly generated quartet passes installed-byte validation.

## Validation Sign-Off

- [x] Every current task in plans 00-05 through 00-13 maps to an automated command.
- [x] All four human checkpoints have automated pre/post conditions and explicit ineligible branches.
- [x] Toolchain/current-SDK absence is a tested canonical incomplete non-live state, not a provider-feasibility conclusion.
- [x] Public first-party entry/provenance plus sanitized D-02 expectations and owner-approved bounds precede every browser/native source or launch action.
- [x] Missing public third-party documentation is non-dispositive; missing safe inputs remain incomplete without endpoint inference, while locked terminal outcomes alone produce canonical `NO-GO unsupported`.
- [x] Historical summaries/quartet cannot establish replacement completion; `00-SUPERSESSION.md` keeps Phase 1 blocked until Plan 00-13 atomically regenerates and validates the exact canonical quartet.
- [x] FEAS-01 through FEAS-05, all 17 locked decisions, every plan threat register, and all conditional branches have mapped verification.
- [x] `nyquist_compliant: true` reflects the replacement plans; `wave_0_complete` remains false until Plan 00-05 creates and passes the listed tests.

**Approval:** ready for plan verification
