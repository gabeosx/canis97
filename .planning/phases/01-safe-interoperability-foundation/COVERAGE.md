# API Coverage — SiriusXM Phase 1

> Full coverage by default. This matrix names semantic capabilities because no undocumented endpoint contract is assumed. Opt-outs are explicit, reasoned decisions, and no row authorizes bypassing a provider control.

| capability | decision | reason |
|---|---|---|
| authentication-initiation | INTEGRATE | |
| explicit-authentication-outcome-classification | INTEGRATE | |
| entitlement-confirmation | INTEGRATE | |
| session-establishment | INTEGRATE | |
| sign-out-and-local-credential-clear | INTEGRATE | |
| stop-and-unsupported-handling | INTEGRATE | |
| redacted-authentication-diagnostics | INTEGRATE | |
| catalog-browse-and-refresh | OPT-OUT | Phase 2 owns entitled linear-channel catalog behavior after authentication passes the Phase 1 continuation gate. |
| channel-metadata | OPT-OUT | Phase 2 owns current channel and program metadata after authorization is proven. |
| live-stream-resolution | OPT-OUT | Phase 2 owns entitled linear-stream resolution after the safe session boundary exists. |
| live-playback | OPT-OUT | Phase 2 owns AVFoundation playback and recovery; Phase 1 performs no media requests. |
| xtra-on-demand-and-replay | OPT-OUT | These content types are explicitly deferred beyond the live-channel milestone requirements. |
| favorites-and-recents-mutation | OPT-OUT | Phase 3 owns non-secret local library state after live listening works. |
| media-keys-and-now-playing | OPT-OUT | Phase 3 owns native system media controls and shared playback state. |
| declarative-skin-management | OPT-OUT | Phase 4 owns bounded local skin import, validation, selection, and recovery. |
| support-bundle-export | OPT-OUT | Phase 5 owns explicitly reviewed diagnostic export; Phase 1 exposes only allow-listed local classifications. |
| release-update-and-distribution | OPT-OUT | Phase 5 owns signed, notarized releases, Homebrew Cask distribution, and passive update notices. |

## Coverage interpretation

- `INTEGRATE` means Phase 1 implements and verifies the semantic capability whether the final compatibility result is supported or explicitly unsupported.
- Authentication support is not presumed by Phase 1. It begins only after Phase 0's deterministic artifact chain yields one exact GO+unlocked path; missing, malformed, mismatched, or NO-GO state blocks before production files.
- Catalog, stream, playback, and later application capabilities remain unreachable until Phase 0 GO is consumed and Phase 1 production composition passes synthetic acceptance.

## Plan realization

- `authentication-initiation` — owning plans: 01-01, 01-05, 01-06, 01-07. Plan 01-01 gates all production work on deterministic Phase 0 GO; Plan 01-07 compiles only the matching Phase 0 path and retains unavailable as the non-selectable fail-closed default.
- `explicit-authentication-outcome-classification` — owning plans: 01-02, 01-05, 01-07. Known semantic results remain distinct and every unknown/control-protected/ambiguous result is terminal unsupported.
- `entitlement-confirmation` — owning plans: 01-02, 01-07, 01-08. Entitlement uses the Phase 0-proven strict semantic predicate and Phase 1 verifies it with synthetic production acceptance rather than repeating live proof.
- `session-establishment` — owning plans: 01-02, 01-03, 01-07, 01-08. Session material is actor-owned and ephemeral; Phase 1 acceptance uses scripted transport and performs no live proof.
- `sign-out-and-local-credential-clear` — owning plans: 01-04, 01-07, 01-08. Memory clears before Keychain deletion and production acceptance proves ordering/failure semantics synthetically.
- `stop-and-unsupported-handling` — owning plans: 01-02, 01-05, 01-06, 01-07, 01-08. Every locked stop signal ends the attempt, records unsupported safely, and blocks Phases 2–5.
- `redacted-authentication-diagnostics` — owning plans: 01-03, 01-05, 01-06, 01-07, 01-08. Only allow-listed classifications cross test, UI, evidence, and summary boundaries.

## Continuation contract

- Plan 01-01 blocks before any production file unless Phase 0 evidence, selection, owner result, and decision freshly derive byte-identical exact `GO browser-return|GO native-direct` plus `unlocked`.
- Plan 01-06 revalidates that chain and records only the matching browser-return/native-direct production handoff; it performs no evidence review or live action.
- Plan 01-07 implements only that result. Missing exact selected-path evidence halts with the unavailable default unchanged.
- Plan 01-08 performs package/app synthetic acceptance only and records that live proof was not repeated. Phase 2 readiness requires the already validated Phase 0 GO plus passing Phase 1 production tests.
