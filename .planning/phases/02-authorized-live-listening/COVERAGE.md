# Phase 02 API Capability Coverage

**Phase:** 02 — Authorized Live Listening
**Scope:** Current project evidence and the v1 live-listening contract
**Status:** Planning baseline; provider-agnostic Plan 02-01 leaves every live row pending. The bounded live checkpoint in Plan 02-02 is the first Phase 02 provider touch and must replace each `PENDING LIVE CHECKPOINT` result with `SUPPORTED`, `NOT REQUIRED`, or `UNSUPPORTED`. Plan 02-03 may encode fixed operations/decoders only from a top-level supported canonical result.

This matrix is not a claim about SiriusXM's exhaustive private API surface. It enumerates only capabilities implicated by the current code, Phase 02 requirements, sanitized historical evidence, and the v1 product boundary. Execution may not silently add provider operations beyond these rows.

## Integrated dependencies — do not duplicate

- **Authentication:** Phase 01's `SiriusXMClient` runtime-owned native transaction remains the owner. Phase 02 reuses the already-integrated authenticated session and adds no sign-in path, token extraction, credential entry, or authentication retry.
- **Subscription entitlement:** Phase 01's native entitlement verifier and `SessionCoordinator` remain the entry gate. Phase 02 still rechecks current authorization at tune/resource resolution because a catalog cache is never authority.

## Capability decision matrix

| Capability | Decision | Reason |
|---|---|---|
| Catalog refresh and entity filtering | INTEGRATE | Pending live checkpoint. Refresh through a fixed internal adapter; expose only entitled standard and app-only `channel-linear` entities as semantic channel snapshots. |
| Catalog freshness and last-valid browse snapshot | INTEGRATE | Provider-independent. Preserve a last valid snapshot with explicit fresh/stale state; refresh failure remains visible and cached presence cannot authorize tuning. |
| Tune authorization | INTEGRATE | Pending live checkpoint. Re-check current session, entitlement, and provider tune authorization for one selected stable channel identity. |
| Stream/manifest/resource resolution | INTEGRATE | Pending live checkpoint. Resolve one ephemeral authorized live resource behind an opaque app-integration handoff; do not expose or persist resource locations. |
| Required media-key authorization | INTEGRATE | Pending live checkpoint. Contain any supported required key authorization in the fixed adapter; otherwise report unsupported playback and stop. |
| AVFoundation compatibility for one authorized live resource | INTEGRATE | Pending live checkpoint. Validate one owner-selected channel with one `AVPlayer`; do not select or add a fallback engine from assumption. |
| Current program/song metadata text | INTEGRATE | Pending live checkpoint. Decode best available current text into semantic metadata independently of audio state. |
| Channel/program artwork | INTEGRATE | Pending live checkpoint. Resolve only allow-listed provider artwork, validate type and size, and return bounded semantic image data without exposing provider URLs. |
| Stream re-resolution during bounded recovery | INTEGRATE | Pending live checkpoint. Permit same-channel re-resolution only for classified recoverable expiry/network/wake/stall outcomes and within an injected finite budget. |
| Closed semantic diagnostics for catalog/resolution/metadata/playback | INTEGRATE | Provider-independent. Extend allow-listed operation/outcome enums only; raw provider and AVFoundation error material is never diagnostic data. |
| Xtra entities as v1 channels | OPT-OUT | D-01 and CAT-01 restrict the Phase 02 lineup to entitled standard and app-only `channel-linear` entries; ambiguous/Xtra entities are excluded. |
| Replay/time-shift programs | OPT-OUT | D-04 defines live-edge radio semantics and the project scopes replayable programs out of v1. |
| On-demand shows or episodes | OPT-OUT | The project is intentionally live-channel-only for v1. |
| Recording or offline download | OPT-OUT | The project explicitly excludes recording/download and must not retain media resources. |
| SiriusXM-wide search | OPT-OUT | v1 discovery is predictable channel-number/category browsing; SiriusXM-wide search is out of scope. |
| Arbitrary provider request builder | OPT-OUT | Volatile operations remain individually named behind exact host/method/response contracts; a generic request surface would defeat containment and host authorization. |
| Alternate playback engine | OPT-OUT | AVFoundation is the required first validation target. A fallback engine is not selected in this phase; unsupported protected behavior stops safely. |

## Live checkpoint refinement contract

Plan 02-02 performs exactly one owner-visible catalog observation and one owner-selected tune through the app's existing authenticated session. It creates `02-LIVE-CONTRACT.md` as the canonical sanitized, non-exhaustive evidence artifact. It may retain only the following evidence in that artifact, this file, and the plan summary:

- whether each pending capability is `SUPPORTED`, `NOT REQUIRED`, or `UNSUPPORTED`;
- closed failure-domain and protection/control classifications;
- invented/sanitized field names and type/cardinality shapes sufficient to write deterministic fixtures;
- fixed request method, authorized-host-policy identifier, and path template facts strictly required to create individually named operations after a supported gate;
- whether one authorized resource became audibly playable through AVFoundation and whether pause/resume/stop matched live-edge semantics.

The checkpoint must not retain raw requests/responses, arbitrary or unapproved destinations, tokens, cookies, authorization headers, stream/manifest/key locations or values, HAR/browser storage, account identifiers, AVFoundation access/error logs, or secret-bearing errors. Unknown redirects, CAPTCHA/MFA/control challenges, `403`, `429`, rate-limit/bot signals, DRM/access-control ambiguity, or any need for spoofing/bypass immediately set the affected capability to `UNSUPPORTED`, write `Execution: HALT`, and end the probe without a follow-up request. No downstream provider-dependent plan may execute unless `02-LIVE-CONTRACT.md` says `Gate Result: SUPPORTED`.
