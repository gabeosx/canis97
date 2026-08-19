# Phase 02 Live Compatibility Contract

**Phase:** 02 — Authorized Live Listening
**Checkpoint:** 02-02
**Scope:** Sanitized, non-exhaustive provider-contract evidence. This document contains no credentials, sessions, account data, request or response bodies, media locations, key material, identifiers, header values, or raw browser/network evidence.

## Gate Result: SUPPORTED

**Execution:** Proceed with fixed, fail-closed compatibility work.
**AVFoundation:** NOT OBSERVED — Plan 02-05 must perform the native player verification before any claim of audible playback, pause, resume, stop, or live-edge behavior.

The former `human-verification-required` halt was superseded after the ordinary native tune failure was correctly classified as `tune-http-400`, and separately collected owner-authorized, semantically redacted official-player evidence established the provider contract below. This is evidence for fixed adapter work, not permission for additional discovery, request variation, runtime DOM manipulation, or an access-control workaround.

## Supported Provider Roles and Closed Results

| Role | Host class | Format | Sanitized supported result |
| --- | --- | --- | --- |
| Catalog and channel peek | Provider API gateway | JSON | Authorized catalog and current-channel metadata operations return ordinary success and provide linear-channel semantic data. |
| Tune authorization | Provider playback gateway | JSON | An authorized linear-channel tune operation returns ordinary success and a structured live-stream result. |
| Live resource delivery | Provider media-delivery service | HLS playlist and AAC media | Primary and secondary encrypted live resources resolve through standard HLS playlists and AAC segments. |
| Playback-key authorization | Provider playback gateway | JSON | A fixed playback-key operation returns the required two-string opaque authorization shape. |
| Stream enforcement | Provider API gateway | JSON | Enforcement status can be queried as an ordinary success result. |
| Live activity update | Provider API gateway | JSON | A bounded periodic live-activity operation accepts channel/time-window semantics and returns ordinary success. |

## Semantic Shapes for the Fixed Adapter

- **Tune result:** a top-level linear-channel discriminator and exactly one-or-more stream records.
- **Stream record:** one-or-more opaque resource references, one opaque key-reference field, current live metadata, and opaque tracking metadata.
- **Resource delivery:** HLS playlist content with AAC media segments; encrypted delivery requires the separate playback-key authorization role.
- **Playback-key result:** a two-required-string shape. The values are opaque, short-lived, memory-only, and never diagnostic or persistent data.
- **Metadata:** current program/song information is available from both the tune result and the current-channel metadata role. Artwork availability is supported as provider metadata, with UI precedence and stale/unavailable presentation deferred to Plan 02-07.

## Fixed Operation Mapping (Approved 2026-08-19)

These are the complete non-sensitive operation facts approved for compatibility scaffolding. They authorize fixed semantic mapping only; they do not authorize a live request, request variation, credential/session access, browser operation, response capture, or playback attempt.

| Capability | Method | Exact host | Exact path or template | Non-secret fixed semantics |
| --- | --- | --- | --- | --- |
| Catalog/channels | `GET` | `api.edge-gateway.siriusxm.com` | `/browse/v1/pages/curated-grouping/403ab6a5-d3c9-4c2a-a722-a94a6a5fd056` | No query or body. |
| Tune | `POST` | `api.edge-gateway.siriusxm.com` | `/playback/play/v1/tuneSource` | `type=channel-linear`, `hlsVersion=V3`, `manifestVariant=WEB`, `mtcVersion=V2`, `trackResumeSupported=false`, plus a non-secret logical `x-sxm-clock` `[epoch,counter]`. |
| Playback key | `GET` | `api.edge-gateway.siriusxm.com` | `/playback/key/v1/{keyId}` | Exact response shape `{keyId,key}`; values are opaque and memory-only. |
| Live activity | `POST` | `api.edge-gateway.siriusxm.com` | `/playback/play/v1/liveUpdate` | Body shape `{channelId,startTimestamp,endTimestamp}`. |
| Channel peek | `GET` | `api.edge-gateway.siriusxm.com` | `/channel-guide/v1/channel/{channelId}/peek` | Fixed template only. |
| Stream enforcement | `GET` | `api.edge-gateway.siriusxm.com` | `/playback/stream-enforcement/v1/status` | No query or body. |
| Media resource | `GET` | `live-akc-prod-device.streaming.siriusxm.com` | Opaque signed path | SPI handoff only: never a normal request builder, fixture, log, persistent value, or public accessor. |

Browser-only telemetry operations and headers are omitted. The known catalog/tune/peek/live-activity values above do not supply any additional provider response field names; strict production decoding remains limited to explicitly recorded shapes, and unknown/malformed/control input terminates unsupported.

## Selected Apple Media Handoff

Plan 02-03 selects a `SiriusXMAppleMediaHandoff` SPI protocol that can create an `AVPlayerItem` without exposing resource, header, key, or URL material through the ordinary public API. The concrete opaque values remain inside a future internal adapter and memory only. This selects the Apple integration seam; it does **not** claim that AVFoundation loading, audibility, transport controls, or live-edge behavior works. Those observations remain exclusively for Plan 02-05.

## Safety and Implementation Limits

- Runtime catalog, tune, metadata, key, enforcement, and live-activity operations are direct authenticated JSON APIs. Shipped code must not manipulate a DOM, inspect browser storage, or automate the official player.
- Use individually named operations, direct-host allowlists, ephemeral session handling, strict decoding, and closed failure classifications. Unknown hosts, redirects, malformed shapes, protected controls, authentication/entitlement loss, and unrecognized status outcomes fail closed.
- Preserve existing Keychain material for ordinary tune HTTP 4xx outcomes. Only explicit Sign Out or Clear Local Session may erase local session material.
- Keep resource references and playback-key material in memory only. Never log, persist, fixture, display, or export them.
- The observed live-activity role is periodic in the official client; exact cadence remains an implementation decision for a bounded, injectable policy rather than a durable provider fact.

## Deferred Native Playback Proof

The provider transport, resource, key, and metadata contracts are supported enough for Plan 02-03 to create strict decoders, sanitized fixtures, and an opaque media handoff. Native AVFoundation acceptance remains deliberately deferred: Plan 02-05 must verify one authorized handoff with the app's `AVPlayer` before the project can claim audibility or any player-control semantics.
