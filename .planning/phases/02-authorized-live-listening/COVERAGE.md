# Phase 02 API Capability Coverage

**Phase:** 02 — Authorized Live Listening
**Scope:** Non-exhaustive, sanitized compatibility evidence for the v1 live-listening contract.
**Status:** The canonical [02-LIVE-CONTRACT.md](02-LIVE-CONTRACT.md) is `Gate Result: SUPPORTED`. Its [approved fixed operation mapping](02-LIVE-CONTRACT.md#fixed-operation-mapping-approved-2026-08-19) permits offline Plan 02-03 compatibility scaffolding only; AVFoundation remains explicitly unobserved until Plan 02-05.

This matrix is not a claim about the provider's exhaustive private API surface. It enumerates only capabilities implicated by Phase 02. Execution may not silently add operations beyond these rows.

## Integrated dependencies — do not duplicate

- **Authentication and entitlement:** Phase 01's runtime-owned native transaction remains the sole authority. Phase 02 adds no sign-in path, token extraction, credential entry, or authentication retry.
- **Direct native operations:** Catalog, tune, metadata, key, enforcement, and live-activity work use fixed authenticated JSON operations. The official-player DOM interaction was research-only and is not product architecture.

## Capability decision matrix

| Capability | Decision | Evidence boundary / next owner |
| --- | --- | --- |
| Catalog refresh and entitled linear filtering | SUPPORTED | One fixed GET decodes only the approved initial-page envelope and admits a standard or app-only `channel-linear` item solely through exact closed entity/connectivity/content-label/integral-number/matching-Play capability checks; `channel-xtra` is excluded. `isAvailable` is not entitlement evidence. |
| Catalog freshness and last-valid browse snapshot | INTEGRATE | Provider-independent; cached presence remains browse-only and cannot authorize tuning. |
| Tune authorization | SUPPORTED | Fixed authorized tune role returns a structured live-stream result; Plan 02-03 owns strict decoding. |
| Stream/manifest/resource resolution | SUPPORTED | Standard HLS playlist and AAC media delivery is supported through the provider media-delivery host class. |
| Required playback-key authorization | SUPPORTED | A fixed JSON key-authorization role returns the required opaque two-string shape; Plan 02-03 owns the memory-only handoff. |
| AVFoundation compatibility for one authorized live resource | NOT OBSERVED | Plan 02-05 must prove native `AVPlayer` loading and control behavior. |
| Current program/song metadata text | SUPPORTED | Fixed authenticated lookaround GET admits only the selected channel's first ordered cut: required name/validFrom and optional artistName; empty or drift is unavailable/closed. |
| Channel/program artwork | SUPPORTED | First-cut optional relative image resolves only to the fixed artwork host without authorization forwarding; JPEG/PNG plus product 5-MiB/4096 bounds are admitted independently. |
| Stream re-resolution during bounded recovery | NOT OBSERVED | Plan 02-06 must add and test bounded recovery after one native playback path is proven. |
| Stream enforcement status | SUPPORTED | Provider API gateway JSON supports a fixed enforcement-status role. |
| Live activity update | SUPPORTED | Provider API gateway JSON supports bounded channel/time-window activity updates; cadence remains policy, not a captured contract. |
| Closed semantic diagnostics | INTEGRATE | Only allow-listed operation/outcome enums; no raw provider or AVFoundation error material. |
| Xtra entities as v1 channels | OPT-OUT | D-01 restricts v1 to entitled standard and app-only `channel-linear` entries. |
| Replay/time-shift, on-demand, recording, download, or provider-wide search | OPT-OUT | Outside the Phase 02 live-radio product boundary. |
| Arbitrary provider request builder or alternate playback engine | OPT-OUT | Individually named fixed operations and AVFoundation remain the only supported architecture. |

## Contract and safety rules

Only semantic roles, host classes, formats, closed result classes, and invented type/cardinality descriptions may appear in planning artifacts and fixtures. Do not retain or introduce raw traffic, credentials, session material, identifiers, bodies, media locations, key material, header values, browser storage, or free-form errors. Unknown redirects/hosts, protected controls, rate limits, authorization loss, malformed contracts, and DRM ambiguity remain terminal closed outcomes.

Plan 02-03 may implement the fixed opaque handoff and fixture contract. It must not claim AVFoundation success, add runtime DOM behavior, or broaden provider operations.
