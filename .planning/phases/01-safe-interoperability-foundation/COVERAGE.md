# API Coverage — SiriusXM Phase 1

> Phase 1 implements the settled WebView-token/native-request authentication path. No row authorizes access-control bypass, a second sign-in method, or Phase 0 feasibility work.

| capability | decision | owning plans |
|---|---|---|
| nonpersistent-WebView-authentication | INTEGRATE | 01-05, 01-06, 01-07, 01-08 |
| exact-first-party-token-extraction | INTEGRATE | 01-06, 01-08 |
| native-authentication-verification | INTEGRATE | 01-02, 01-03, 01-07, 01-08 |
| native-entitlement-confirmation | INTEGRATE | 01-02, 01-07, 01-08 |
| atomic-session-establishment | INTEGRATE | 01-02, 01-07, 01-08 |
| sign-out-and-token/credential-clear | INTEGRATE | 01-04, 01-06, 01-07, 01-08 |
| explicit-terminal-outcomes | INTEGRATE | 01-02, 01-05, 01-07, 01-08 |
| redacted-authentication-diagnostics | INTEGRATE | 01-03, 01-05, 01-08 |
| independent-SwiftPM-client | INTEGRATE | 01-01, 01-08 |
| catalog-browse-and-refresh | OPT-OUT | Phase 2 |
| channel-metadata | OPT-OUT | Phase 2 |
| live-stream-resolution/playback | OPT-OUT | Phase 2 |
| favorites/recents/media-controls | OPT-OUT | Phase 3 |
| declarative-skin-management | OPT-OUT | Phase 4 |
| support-export/release-distribution | OPT-OUT | Phase 5 |

## Architecture realization

- Plan 01-01 creates the native app and semantic `SiriusXMClient` boundary immediately; no Phase 0 file is read or validated.
- Plan 01-02 makes the runtime the sole authority for authentication, entitlement, and atomic session activation. It cannot consume caller-authored success claims.
- Plan 01-03 performs only exact native HTTPS requests through a client-owned ephemeral session and structurally excludes secrets from diagnostics.
- Plan 01-04 supplies Keychain lifecycle and memory-first cleanup.
- Plan 01-05 supplies the one native WebView sign-in surface and complete typed compatibility states.
- Plan 01-06 owns the exact shared cookie predicate for extraction and sign-out, including all accepted first-party subdomains; its test targets compile unconditionally.
- Plan 01-07 composes one runtime-owned flow: explicit user extraction → native authentication → native entitlement → atomic session publication.
- Plan 01-08 blocks Phase 2 readiness on synthetic regression coverage for every legitimate `00-REVIEW.md` finding.

## Continuation contract

Phase 1 is ready to execute now. Phase 2 readiness depends only on the Phase 1 package/app test suites and the Phase 1 completion summary. Phase 0 evidence, selection, owner-result, decision, GO/NO-GO, cooldown, and proof-run artifacts are historical and have no continuation authority.
