# API Coverage — SiriusXM Phase 0

> Full coverage by default. This phase conditionally reaches a SiriusXM authentication surface only after a public first-party contract qualifies exactly one path. The matrix names semantic capabilities rather than undocumented endpoints. Every non-integrated capability is an explicit, reasoned opt-out; no row authorizes guessing, inspection, replay, spoofing, fallback, retry, or access-control bypass.

| capability | decision | reason |
|---|---|---|
| public-first-party-evidence-qualification | INTEGRATE | |
| browser-return-candidate-qualification | INTEGRATE | |
| native-direct-candidate-qualification | INTEGRATE | |
| sole-owner-authentication-initiation | INTEGRATE | |
| explicit-authentication-outcome-classification | INTEGRATE | |
| entitlement-confirmation | INTEGRATE | |
| clean-sign-out-and-transient-cleanup | INTEGRATE | |
| protected-control-and-ambiguity-stop | INTEGRATE | |
| redacted-semantic-proof-record | INTEGRATE | |
| final-feasibility-and-phase-continuation-decision | INTEGRATE | |
| production-siriusxm-client-and-app-integration | OPT-OUT | Phase 1 owns the production reusable client and native app boundary after a validated Phase 0 GO; the disposable spike must not be imported by them. |
| persistent-credential-or-session-storage | OPT-OUT | Phase 0 persists no credentials, tokens, cookies, or sessions. Phase 1 owns app-controlled Keychain storage only after GO. |
| browser-cookie-storage-profile-or-developer-tools-inspection | OPT-OUT | This is prohibited evidence, not an integration technique; browser-return may use only an app-bound system callback established by a public first-party contract. |
| alternate-authentication-method-or-fallback | OPT-OUT | Exactly one browser-first evidence-selected path may proceed. Unsupported or the first stop is terminal and cannot switch methods. |
| automated-live-probing-retry-polling-or-ci | OPT-OUT | All live attempts are owner-initiated, one at a time, exactly twice for GO, with a human-controlled cooldown and no automated sampling. |
| catalog-browse-and-refresh | OPT-OUT | Phase 2 owns entitled linear-channel catalog behavior after authentication productionization. |
| channel-metadata | OPT-OUT | Phase 2 owns current channel/program metadata; Phase 0 proves authentication feasibility only. |
| live-stream-resolution | OPT-OUT | Phase 2 owns entitled live-stream resolution after the safe production client exists. |
| live-playback | OPT-OUT | Phase 2 owns AVFoundation playback and recovery; Phase 0 makes no media request. |
| favorites-recents-and-macos-media-integration | OPT-OUT | Phase 3 owns local library state and native media controls after live listening works. |
| declarative-skin-management | OPT-OUT | Phase 4 owns bounded declarative skin import, selection, validation, and recovery. |
| support-export-release-update-and-distribution | OPT-OUT | Phase 5 owns support bundles, signed/notarized releases, Homebrew distribution, and passive update notice. |

## Coverage interpretation

- `INTEGRATE` means the Phase 0 harness validates the semantic capability in its supported and unsupported branches. It does not presume an eligible SiriusXM contract exists.
- Browser-return eligibility requires every fixed app-bound callback and verification predicate from public first-party evidence. Missing or ambiguous evidence rules the branch out before session creation.
- Native-direct eligibility is evaluated only after explicit browser rule-out and requires a complete public first-party honest-client/request/authentication/entitlement/sign-out contract.
- Unsupported is a successful terminal Phase 0 result: no candidate is created, no owner checkpoint is presented, and `NO-GO unsupported` blocks Phase 1.

## Plan realization

- `public-first-party-evidence-qualification` — plans 00-01 and 00-02 validate the closed exact predicate schema and owner-reviewed public references.
- `browser-return-candidate-qualification` — plans 00-02 and 00-03 enforce full callback-contract evidence, system authentication-session use, and zero browser-state access.
- `native-direct-candidate-qualification` — plans 00-02 and 00-03 enforce prior browser rule-out, complete honest contract evidence, and one ephemeral Foundation session.
- `sole-owner-authentication-initiation` — plans 00-03 and 00-04 require explicit owner acknowledgement and fixed run labels; tests/default/CI cannot invoke a candidate.
- `explicit-authentication-outcome-classification` — plans 00-01, 00-03, and 00-04 expose only closed semantic pass/stop labels.
- `entitlement-confirmation` — plans 00-01 and 00-04 require explicit entitlement in each of exactly two GO proofs.
- `clean-sign-out-and-transient-cleanup` — plans 00-01, 00-03, and 00-04 require each GO run to sign out and all stop paths to cancel/invalidate transient state.
- `protected-control-and-ambiguity-stop` — every plan treats the first protected, challenged, rate-limited, suspicious, unknown, or ambiguous signal as terminal NO-GO.
- `redacted-semantic-proof-record` — plans 00-01, 00-02, and 00-04 use allow-listed fields and synthetic canaries; no raw browser/account/provider value is representable.
- `final-feasibility-and-phase-continuation-decision` — plan 00-04 writes exactly one validated decision and unlocks Phase 1 only for the exact same-path two-run GO predicate.

## Continuation contract

- `00-SELECTION.md` contains exactly one `browser-return`, `native-direct`, or `unsupported` candidate disposition.
- `unsupported` skips all candidate and live work and produces `NO-GO unsupported` with `Phase 1 continuation: blocked`.
- A supported selection compiles only that branch. The account owner alone performs run-1, chooses/completes the cooldown, and performs run-2; one stop ends the protocol.
- `00-DECISION.md` contains exactly one of `GO browser-return`, `GO native-direct`, or `NO-GO unsupported`, plus exactly one consistent `unlocked`/`blocked` continuation value.
- Phase 1 consumes only the validated Phase 0 decision. Phase 0 does not execute or duplicate the production work already planned there.
