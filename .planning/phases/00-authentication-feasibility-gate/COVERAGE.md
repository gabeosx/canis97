# API Coverage — SiriusXM Phase 0 (Corrected Authority)

> Phase 0 integrates only enough bounded behavior to answer the corrected
> authentication gate. Every retained value is an allow-listed semantic outcome.

| capability | decision | reason |
|---|---|---|
| player-webview-owner-login-surface | INTEGRATE | The owner alone performs the real sign-in interaction in the nonpersistent WKWebView. |
| narrow-current-auth-token-extraction | INTEGRATE | Only the named current first-party `AUTH_TOKEN` may be consumed once in memory after owner action. |
| profile-authentication-classification | INTEGRATE | Profile success proves authentication only, never entitlement. |
| bounded-entitlement-classification | INTEGRATE | A canonical contract reports supported or unsupported without recording raw provider data. |
| visible-sign-out-and-cleanup | INTEGRATE | Both runs require semantic sign-out absence and verified cleanup. |
| v3-evidence-ledger-and-decision-gate | INTEGRATE | Exact ordered cardinality and canonical bytes derive GO/NO-GO without owner testimony. |
| provider-issued-session-renewal | OPT-OUT | Not an owner observation or Phase 0 GO condition under D-20. |
| tune-manifest-key-authorization | OPT-OUT | Phase 2 owns tuning and key authorization under D-21. |
| audible-playback | OPT-OUT | Phase 2 owns AVFoundation playback under D-21. |
| catalog-and-metadata | OPT-OUT | Phase 2 owns entitled catalog and metadata behavior. |
| keychain-and-production-client | OPT-OUT | Phase 1 owns durable credentials and the reusable production client after GO. |
| native-direct-fallback | OPT-OUT | Not applicable after verified browser-return; no alternate owner-visible closure exists. |
| persistent-secret-state-and-raw-capture | OPT-OUT | No artifact or diagnostic may carry cookie, token, header, identity, response, or stream value. |

## Decision Boundary

- A supported entitlement contract plus exactly two complete ordered v3 runs is
  the only path to `GO browser-return`.
- An unsupported entitlement contract produces `NO-GO unsupported` with zero
  owner runs and no provider/UI work.
- Partial, malformed, stale-v2, duplicate, mixed-path, terminal, or tampered
  input fails closed and cannot overwrite the current quartet.
- Renewal, tune/key, playback, catalog, Keychain, and production-client rows
  are intentionally excluded rather than silently left untested.
