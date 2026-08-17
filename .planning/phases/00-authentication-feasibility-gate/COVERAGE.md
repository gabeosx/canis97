# API Coverage — SiriusXM Phase 0

> Full coverage by default. This phase reaches the owner-operated WKWebView surface only after safe first-party entry/provenance, sanitized D-02 expectations, observation bounds, and owner approval validate. Documentation completeness is not an eligibility gate. The matrix names semantic capabilities rather than endpoints; no row authorizes guessing, browser-state extraction, replay, spoofing, fallback, retry, or access-control bypass.

| capability | decision | reason |
|---|---|---|
| public-first-party-evidence-qualification | INTEGRATE | |
| browser-return-candidate-qualification | INTEGRATE | |
| native-direct-candidate-qualification | INTEGRATE | |
| sole-owner-authentication-initiation | INTEGRATE | |
| explicit-authentication-outcome-classification | INTEGRATE | |
| entitlement-confirmation | INTEGRATE | |
| provider-issued-session-renewal | INTEGRATE | |
| bounded-tune-manifest-and-key-authorization | INTEGRATE | |
| bounded-audible-avplayer-proof | INTEGRATE | |
| clean-sign-out-and-transient-cleanup | INTEGRATE | |
| protected-control-and-ambiguity-stop | INTEGRATE | |
| redacted-semantic-proof-record | INTEGRATE | |
| final-feasibility-and-phase-continuation-decision | INTEGRATE | |
| replacement-plan-supersession-authority | INTEGRATE | |
| production-siriusxm-client-and-app-integration | OPT-OUT | Phase 1 owns the production reusable client and native app boundary after a validated Phase 0 GO; the disposable spike must not be imported by them. |
| persistent-secret-or-session-state | OPT-OUT | Phase 0 persists no secret or active session material. Phase 1 owns app-controlled Keychain persistence only after GO. |
| authenticated-browser-state-inspection | OPT-OUT | WKWebView observes only allow-listed app-bound events and semantic transitions; browser stores, profiles, credentials, and raw session material remain inaccessible. |
| alternate-authentication-method-or-fallback | OPT-OUT | Native-direct requires exact WebKit-only rule-out plus separate owner approval and replaces the browser live runtime; every other stop is terminal. |
| automated-live-probing-retry-polling-or-ci | OPT-OUT | All live attempts are owner-initiated, one at a time, exactly twice for GO, with a human-controlled cooldown and no automated sampling. |
| catalog-browse-and-refresh | OPT-OUT | Phase 2 owns entitled linear-channel catalog behavior after authentication productionization. |
| channel-metadata | OPT-OUT | Phase 2 owns current channel/program metadata; Phase 0 proves authentication feasibility only. |
| production-live-stream-resolution | OPT-OUT | Phase 2 owns reusable catalog/channel stream resolution. Phase 0 integrates only one bounded tune/manifest/key authorization proof required by the feasibility finish line. |
| production-live-playback-and-recovery | OPT-OUT | Phase 2 owns reusable playback and recovery. Phase 0 integrates one bounded audible AVPlayer proof with AVContentKeySession, immediate stop, and no recording/cache/persistence. |
| favorites-recents-and-macos-media-integration | OPT-OUT | Phase 3 owns local library state and native media controls after live listening works. |
| declarative-skin-management | OPT-OUT | Phase 4 owns bounded declarative skin import, selection, validation, and recovery. |
| support-export-release-update-and-distribution | OPT-OUT | Phase 5 owns support bundles, signed/notarized releases, Homebrew distribution, and passive update notice. |

## Coverage interpretation

- `INTEGRATE` means the Phase 0 harness validates the semantic capability across ready, incomplete, strict-ruleout, GO, and locked terminal branches.
- Browser experiment readiness requires a public first-party entry surface, ordinary navigation/provenance allowlist, sanitized preliminary expectations, bounded semantic observation, and terminal stop policy. Missing third-party callback documentation remains open but does not prevent construction.
- A clean handoff consumes only material delivered explicitly through the matched app-bound return in memory. Ordinary no-clean-return without D-09 proof remains incomplete and cannot unlock native-direct.
- Native-direct eligibility is evaluated only after strict D-09 rule-out and requires an honest purpose contract derived from allowable sanitized evidence plus separate owner approval; missing public documentation alone is non-dispositive.
- Incomplete is a valid non-terminal Phase 0 state with no candidate/live surface and Phase 1 blocked. `NO-GO unsupported` is reserved for explicit owner rejection and locked protected/ambiguous terminal outcomes.

## Plan realization

- `public-first-party-evidence-qualification` — plans 00-05 through 00-07 validate the exact current Xcode/SDK, first-party entry/provenance, sanitized D-02 expectation classes, terminal stop bounds, canonical experiment record, and digest-bound owner approval before live-capable source exists; documentation-open remains allowed.
- `browser-return-candidate-qualification` — plans 00-08 through 00-10 conditionally construct, preflight, and run the bounded owner-operated WKWebView path; it observes only allow-listed app-bound events, consumes explicit return material in memory, records ordinary no-return as incomplete, and closes protected/ambiguous outcomes immediately.
- `native-direct-candidate-qualification` — plans 00-06, 00-07, and 00-10 through 00-12 require an honest purpose-scoped contract from allowable sanitized evidence in addition to prior normal browser success, one WebKit-only failure, secret-free local reproduction, and separate password-exposure approval.
- `sole-owner-authentication-initiation` — plans 00-10 and 00-12 stop executor interaction before account UI; tests, defaults, and CI cannot invoke live activity.
- `explicit-authentication-outcome-classification` — plans 00-05 through 00-13 expose only fixed ready, complete, incomplete/no-clean-return, renewal-pending, strict-ruleout, terminal, and not-applicable classes.
- `entitlement-confirmation` — plans 00-06 through 00-12 establish the semantic mapping from allowable sanitized evidence plus the bounded check and require explicit entitlement in each GO run; observed ambiguity is terminal.
- `provider-issued-session-renewal` — plans 00-09 through 00-12 accept only a naturally provider-issued, authenticated replacement through the approved documented contract; unobserved renewal remains incomplete.
- `bounded-tune-manifest-and-key-authorization` — plans 00-09 through 00-12 require a single bounded semantic tune/manifest/key proof in each GO run.
- `bounded-audible-avplayer-proof` — plans 00-09 through 00-12 use AVContentKeySession plus explicit owner audible confirmation, then stop and tear down.
- `clean-sign-out-and-transient-cleanup` — plans 00-09 through 00-12 require every run to sign out and verify volatile browser/session/key/URL/player state absent without enumerating the WebKit data store.
- `protected-control-and-ambiguity-stop` — every plan treats the first protected, challenged, rate-limited, suspicious, unknown, or ambiguous signal as terminal with no retry/path switch.
- `redacted-semantic-proof-record` — plans 00-05 through 00-13 use positive allowlists and synthetic canaries; no raw browser/account/provider value is representable.
- `final-feasibility-and-phase-continuation-decision` — plan 00-13 mechanically derives the canonical quartet and unlocks Phase 1 only for the exact same-path two-run GO predicate.
- `replacement-plan-supersession-authority` — `00-SUPERSESSION.md` records 00-01..00-04 as immutable history, 00-05..00-13 as the sole active set, and Phase 1 blocked until Plan 00-13 installs and validates newly derived quartet bytes; no stale quartet file may be copied or hand-edited into authority.

## Continuation contract

- `00-SUPERSESSION.md` is the planning-time status authority: `replacement-planned`, active plans `00-05..00-13`, replacement incomplete, and Phase 1 blocked. Historical summaries 00-01..00-04 and the existing fail-closed quartet do not establish replacement completion.
- `00-TOOLCHAIN.md` must validate exact current-Xcode/current-SDK readiness before any GUI/live-capable branch; an unavailable result is incomplete/environment-pending with Phase 1 blocked.
- `00-PUBLIC-AUTH-CONTRACT.md` and `00-PUBLIC-AUTH-CONTRACT-APPROVAL.md` must validate safe first-party entry/provenance, sanitized preliminary expectations, observation/stop bounds, and digest-bound owner approval before the WKWebView experiment can be constructed; public callback documentation may remain open.
- `00-SELECTION.md` contains exactly one `browser-return`, `native-direct`, or `unsupported` candidate disposition.
- `unsupported` may arise from an explicit owner rejection or locked protected/ambiguous terminal stop and produces `NO-GO unsupported` with `Phase 1 continuation: blocked`; environment, ordinary no-return, safe-contract, and renewal gaps remain incomplete instead.
- `native-direct` additionally requires native-purpose qualification from allowable sanitized evidence, strict WebKit-specific rule-out, browser live-source retirement, and separate owner approval; missing a concrete safe native value remains incomplete, while missing public documentation alone is non-dispositive.
- A supported selection compiles only that branch. The account owner alone performs run-1, chooses/completes the cooldown, and performs run-2; one stop ends the protocol.
- `00-DECISION.md` contains exactly one of `GO browser-return`, `GO native-direct`, or `NO-GO unsupported`, plus exactly one consistent `unlocked`/`blocked` continuation value.
- Plan 00-13 may change supersession to `replacement-finalized` only after atomically installing and validating a newly derived `00-EVIDENCE.md` + `00-SELECTION.md` + `00-OWNER-RESULT.md` + `00-DECISION.md` quartet. Any fixed incomplete class retains replacement-planned/blocked; NO-GO finalizes blocked; GO must pass the independent `auth-feasibility require-phase-one-go` validation before continuation is unlocked.
- Phase 1 consumes only the validated canonical Phase 0 quartet through the existing `auth-feasibility` executable. Phase 0 does not execute or duplicate the production work already planned there.
