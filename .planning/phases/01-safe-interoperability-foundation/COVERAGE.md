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
- Authentication support is not presumed. Exactly one evidence-selected path may be implemented; absent adequate evidence, `authentication-initiation` terminates in the explicit unsupported outcome.
- Catalog, stream, playback, and later application capabilities remain unreachable until both manual viability runs pass unambiguously.

## Plan realization

- `authentication-initiation` — owning plans: 01-01, 01-05, 01-06, 01-07. Plan 01-07 compiles only the Plan 01-06 result; unsupported has no live adapter and supported has one evidence-defined surface.
- `explicit-authentication-outcome-classification` — owning plans: 01-02, 01-05, 01-07. Known semantic results remain distinct and every unknown/control-protected/ambiguous result is terminal unsupported.
- `entitlement-confirmation` — owning plans: 01-02, 01-07, 01-08. Entitlement uses one strict evidence-defined semantic predicate; both manual proof runs must confirm authenticated and entitled.
- `session-establishment` — owning plans: 01-02, 01-03, 01-07, 01-08. Session material is actor-owned and ephemeral; live proof is permitted only for a supported selected path.
- `sign-out-and-local-credential-clear` — owning plans: 01-04, 01-07, 01-08. Memory clears before Keychain deletion; each proof run ends with confirmed clean sign-out.
- `stop-and-unsupported-handling` — owning plans: 01-02, 01-05, 01-06, 01-07, 01-08. Every locked stop signal ends the attempt, records unsupported safely, and blocks Phases 2–5.
- `redacted-authentication-diagnostics` — owning plans: 01-03, 01-05, 01-06, 01-07, 01-08. Only allow-listed classifications cross test, UI, evidence, and summary boundaries.

## Continuation contract

- Plan 01-06 outputs exactly one selected result: browser-return, native-direct, or unsupported.
- Plan 01-07 implements only that result. Missing exact supported-path evidence halts before callback, host, endpoint, or request implementation.
- Plan 01-08 performs no live authentication for unsupported. For a supported result, the account owner alone performs two separate runs with a conservative human-controlled cooldown, explicit authenticated-and-entitled evidence, and clean sign-out.
- Only Phase continuation: unlocked from two unambiguous passes permits authorization-dependent work in Phases 2–5. Every other result is Phase continuation: blocked.
