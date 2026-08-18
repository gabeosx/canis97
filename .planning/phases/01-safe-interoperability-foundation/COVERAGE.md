# API Coverage — SiriusXM Phase 1

> Phase 1 implements the settled WebView-token/native-request authentication path. No row authorizes access-control bypass, a second sign-in method, or Phase 0 feasibility work.

| capability | decision | owning plans |
|---|---|---|
| nonpersistent-WebView-authentication | INTEGRATE | 01-05, 01-06, 01-07, 01-08, 01-15 |
| secure-evidence-backed-token-issuer-policy | INTEGRATE | 01-06, 01-15 |
| exact-first-party-token-extraction-and-cleanup | INTEGRATE | 01-06, 01-08, 01-15 |
| nonpersistent-WebKit-session-retirement | INTEGRATE | 01-06, 01-15 |
| native-authentication-verification | INTEGRATE | 01-02, 01-03, 01-07, 01-08, 01-13, 01-16 |
| versioned-profile-v4-response-classification | INTEGRATE | 01-13 |
| native-entitlement-confirmation | INTEGRATE | 01-02, 01-07, 01-08, 01-13, 01-16 |
| versioned-subscription-v1-status-classification | INTEGRATE | 01-13 |
| representative-sanitized-response-regressions | INTEGRATE | 01-13 |
| atomic-session-establishment | INTEGRATE | 01-02, 01-07, 01-08, 01-13, 01-16 |
| bounded-Keychain-session-restore | INTEGRATE | 01-04, 01-16 |
| sign-out-and-token/credential-clear | INTEGRATE | 01-04, 01-06, 01-07, 01-08, 01-15, 01-16 |
| redirects-disabled-at-delegate-callback | INTEGRATE | 01-03, 01-14 |
| explicit-terminal-outcomes | INTEGRATE | 01-02, 01-05, 01-07, 01-08, 01-13, 01-16 |
| redacted-authentication-diagnostics | INTEGRATE | 01-03, 01-05, 01-08, 01-13, 01-14, 01-16 |
| independent-SwiftPM-client | INTEGRATE | 01-01, 01-08, 01-13, 01-14 |
| catalog-browse-and-refresh | OPT-OUT | Phase 2 owns catalog adapters; Phase 1 makes no catalog request. |
| channel-metadata | OPT-OUT | Phase 2 owns metadata adapters; Phase 1 retains authentication/session scope. |
| live-stream-resolution/playback | OPT-OUT | Phase 2 owns resolution/playback; Phase 1 neither resolves nor persists stream URLs. |
| favorites/recents/media-controls | OPT-OUT | Phase 3 owns local player state and media controls. |
| declarative-skin-management | OPT-OUT | Phase 4 owns declarative skins and asset validation. |
| support-export | OPT-OUT | Phase 5 owns support diagnostics/export; Phase 1 exposes no response body or secret. |
| release-signing/notarization/distribution | OPT-OUT | Phase 5 REL-01 owns signing and notarization; CR-01 is explicitly deferred and Phase 1 must not alter signing settings. |

## Architecture realization

- Plan 01-01 creates the native app and semantic `SiriusXMClient` boundary immediately; no Phase 0 file is read or validated.
- Plan 01-02 makes the runtime the sole authority for authentication, entitlement, and atomic session activation. It cannot consume caller-authored success claims.
- Plan 01-03 performs only exact native HTTPS requests through a client-owned ephemeral session and structurally excludes secrets from diagnostics.
- Plan 01-04 supplies Keychain lifecycle and memory-first cleanup.
- Plan 01-05 supplies the one native WebView sign-in surface and complete typed compatibility states.
- Plan 01-06 owns the exact shared cookie predicate for extraction and sign-out; Plan 01-15 narrows that predicate to Secure cookies from the evidence-backed apex and production sign-in host, then rotates the entire bridge-owned nonpersistent WebKit session during cleanup.
- Plan 01-07 composes one runtime-owned flow: explicit user extraction → native authentication → native entitlement → atomic session publication.
- Plan 01-08 blocks Phase 2 readiness on synthetic regression coverage for every legitimate `00-REVIEW.md` finding.
- Plans 01-09 through 01-12 close the earlier atomic credential-selection and composition gaps without adding an authentication method.
- Plan 01-13 replaces one-field success claims with versioned profile/subscription decoders, sanitized representative multi-field fixtures, and end-to-end native authentication-to-entitlement transactions.
- Plan 01-14 proves the production redirect delegate callback increments observable attempts and cancels every follow-up request.
- Plan 01-16 makes previously approved Keychain material a bounded one-attempt source on explicit sign-in, then subjects it to the same native transaction and erases every invalid or rejected restore.

## Continuation contract

Phase 1 is ready to execute through closure Plans 01-13 through 01-16. Phase 2 readiness depends on the full Phase 1 package/app suites, closure-matrix disposition, and the Phase 1 completion summary. Phase 0 source-grounded response evidence remains design evidence only: it is encoded into internal decoders and sanitized fixtures, never loaded by production code. Selection, owner-result, decision, GO/NO-GO, cooldown, and proof-run artifacts remain historical and have no continuation authority.
