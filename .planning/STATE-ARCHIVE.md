# STATE Archive

Pruned entries from STATE.md. Recoverable but no longer loaded into agent context.

## Pruned 2026-08-26 (phases 1-2, kept recent 3)

### Decisions

- [Phase 01]: Profile-v4 authentication accepts only a non-empty JSON object after existing transport and control preflight, without inventing a profile field. — Preserves the settled Phase 0 predicate while allowing representative unrelated fields.
- [Phase 01]: Subscription-v1 entitlement uses `/subscription/v1/subscriptions` and classifies only recognized `items[].state` values (`active` or `finished`); missing, malformed, empty, or unknown evidence fails closed. — Matches the successful live contract while containing volatile provider schema details internally.
- [Phase 02]: Treat ordinary tune HTTP 4xx outcomes as closed native failures that preserve Keychain material; only explicit Sign Out or Clear Local Session erases local session state.
- [Phase 02]: Runtime catalog, tune, metadata, key, enforcement, and live-activity operations are fixed direct authenticated JSON APIs. A one-time official-player DOM interaction was research only and is never shipped architecture.
- [Phase 02]: Sanitized provider-contract evidence supports Plan 02-03's strict opaque media handoff and fixtures, while AVFoundation audibility and controls remain unobserved until Plan 02-05.
- [Phase 02-authorized-live-listening]: Require exact executable-path identity and an atomic lock for bounded SiriusMac launch safety. — A matching process name cannot distinguish stale or duplicate builds.

### Performance Metrics

| 01 | 16 | - | - |
| 02 | 18 | - | - |
