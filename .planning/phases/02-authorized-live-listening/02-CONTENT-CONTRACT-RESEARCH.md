# Phase 02: Authorized Live Listening — Content Contract Research

**Researched:** 2026-08-19  
**Scope:** Read-only discovery from the current unauthenticated SiriusXM public player bundle, Apple documentation, and public OSS source. No account, Keychain, cookies, tokens, app session, raw traffic, or provider content request was accessed.  
**Overall confidence:** MEDIUM — the current public bundle establishes exact service routes and client behavior, but it cannot establish a subscriber-specific response or stream-CDN host.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Expose only entitled standard and app-only `channel-linear` entries as the Phase 02 lineup. Xtra, replay, on-demand, and ambiguously classified entities do not appear as playable v1 channels.
- **D-02:** Give the lineup a predictable channel-number and category organization. Missing presentation fields may degrade gracefully, but stable SiriusXM entity identity remains authoritative.
- **D-03:** Preserve the last valid catalog for browsing when refresh fails, with explicit freshness or stale state. Cached presence never proves current entitlement or playback authorization; tuning must use current session and authorization state.
- **D-04:** Treat playback as live radio. Pause suspends audible playback; resume rejoins the current live edge and does not promise rewind, replay, or durable time-shifting.
- **D-05:** Stop ends active playback. A channel switch cancels obsolete resolution, metadata, and recovery work and replaces the active item through the one playback coordinator; it never creates a second player.
- **D-06:** User-facing state reflects confirmed player and authorization state rather than optimistic commands. Start, pause, resume, stop, and tune requests are serialized by the coordinator.
- **D-07:** Keep the subscriber's selected channel during recoverable failure. Recovery may re-resolve the stream and recreate the player item, but it must not silently switch channels or synthesize listener activity.
- **D-08:** Recovery is bounded, cancellation-aware, and classified by failure domain. It must stop on cancellation, superseding user commands, authentication or entitlement loss, unsupported upstream behavior, protected-control signals, or exhaustion of its retry budget.
- **D-09:** Authentication, entitlement, catalog, stream resolution, network, buffering/stall, decoder, and unsupported-upstream failures remain distinct and actionable. Terminal failure preserves enough non-secret state for the user to understand what failed and retry safely.
- **D-10:** Metadata refresh runs independently from audio playback. Metadata delay, malformed data, or refresh failure never interrupts otherwise healthy audio.
- **D-11:** Show the active channel and best available current program or song text and artwork. Retain last-known metadata with an explicit stale state, then show unavailable rather than inventing or indefinitely presenting current-looking values.
- **D-12:** Channel identity is the stable fallback when richer metadata is missing. Artwork and text selection may degrade independently.

### the agent's Discretion

- Discover the current provider catalog, tune/authorization, stream-resolution, and metadata contracts through bounded, owner-authorized, redacted interoperability work. Do not infer them from the SiriusXM website's presentation or ask the owner to supply provider expertise.
- Validate the actual authorized stream format and behavior with AVFoundation before selecting any fallback playback engine or promising pause behavior beyond rejoining the live edge.
- Choose exact retry counts, backoff, timeouts, stall thresholds, sleep/wake triggers, metadata polling cadence, and stale-to-unavailable timing from observed behavior and platform guidance. These values must remain bounded, injectable/testable where appropriate, and repairable without changing the public semantic API.
- Choose exact minimal Phase 02 browsing/playback presentation, copy, type names, and internal adapter boundaries consistent with existing native patterns. Full multi-window visual design remains Phase 3.
- Choose the best artwork/text precedence from fields that are actually available, while preserving the explicit stale and unavailable semantics above.

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.
</user_constraints>

## Summary

[FIRST-PARTY OBSERVED] The current unauthenticated SiriusXM web-player page serves a versioned public JavaScript bundle whose embedded client configuration declares the authorization-bearing content, playback, key, metadata, and artwork route templates below. This is current route evidence, not a captured subscriber request or response. The original `unknown-contract` stop was therefore correct at the time: the app had no concrete content route allowlist. [Current player page](https://www.siriusxm.com/player) and [current entry bundle](https://cdn.web-cloud.siriusxm.com/sxm-player-web/shared/assets/index-DzOYWl_q.js).

[INFERENCE] Phase 02 can now replace the blanket `unknown-contract` refusal with an exact, narrow contract for catalog and tune confirmation. It must still stop before AVFoundation handoff when a returned HLS resource host, redirect, key mode, or response shape is not the closed value described here. The public bundle does not establish a subscriber-specific HLS host or prove AVFoundation compatibility.

**Primary recommendation:** Permit exactly the catalog and tune calls in the candidate allowlist, parse only their closed semantic results, and treat any resource/key/DRM variation outside that allowlist as a terminal compatibility result rather than probing it.

## Existing Closed Boundary

[INFERENCE — in-repo source-of-truth] The current observation sink supports semantic capabilities including `"catalog-refresh"`, `"tune-authorization"`, `"resource-resolution"`, `"media-key-authorization"`, `"metadata-text"`, and `"artwork"`; it has only a `"GET"` method enum and a `"first-party-authenticated"` host-policy label. The values are quoted verbatim from [LiveContractObservation.swift](/Users/gabe/sirius-mac/SiriusMac/Listening/LiveContractObservation.swift:2) and [LiveContractObservation.swift](/Users/gabe/sirius-mac/SiriusMac/Listening/LiveContractObservation.swift:31). The content contract must add a closed `POST` representation before tune can be recorded truthfully.

[INFERENCE — in-repo source-of-truth] `ClosedLiveObservationAdapter` is intentionally unable to send content: it records `"unknown-contract"` with no request contract before a catalog request. [ClosedLiveObservationAdapter.swift](/Users/gabe/sirius-mac/SiriusMac/Listening/ClosedLiveObservationAdapter.swift:33).

[INFERENCE — in-repo source-of-truth] The native session already has an exact bearer-token transport pattern for `"api.edge-gateway.siriusxm.com"`: request `"Accept"` is `"application/json"` and `"Authorization"` is `"Bearer <opaque credential>"`. [SiriusXMRequestContract.swift](/Users/gabe/sirius-mac/Packages/SiriusXMClient/Sources/SiriusXMClient/InternalAdapters/SiriusXMRequestContract.swift:10). The app does not need to copy WebView cookies into content requests.

## Current Candidate Contract

<!-- DATA_8F6D2C1A_START -->
| Capability | Exact current candidate | Required non-secret request semantics | Accepted semantic response shape | Status |
|---|---|---|---|---|
| Catalog | `GET https://browse-at-edge.siriusxm.com/v2/all-channels` | `Authorization: Bearer <opaque access token>`; no request body; current bundle declares a 15-second timeout. | One catalog document containing many entities. Admit only entities whose stable type is `channel-linear`; require one stable string identity per admitted entity. Title, number, category, images, and entitlement presentation are optional until the one confirmation response fixes their field paths. | [FIRST-PARTY OBSERVED] route/method/header. [INFERENCE] closed parser/cardinality. |
| Tune | `POST https://api.edge-gateway.siriusxm.com/playback/play/v1/tuneSource` | `Authorization: Bearer <opaque access token>` and JSON content type. Current player constructs a one-source body with `id`, `type`, `hlsVersion: V3`, `manifestVariant: WEB` for `channel-linear`, and `mtcVersion: V2`; it also recognizes optional request-context header names `x-sxm-action-id`, `x-sxm-source-timestamp`, `x-sxm-forwarded-host`, and `x-sxm-listener-id`. Do not invent or populate those optional headers for v1. | One tune-source object, with matching `id` and `type`, and many `streams`. A playable result must contain at least one stream with one candidate resource URL. For a linear channel the current consumer reads `metadata.live.items` (many), optional `metadata.live.episodes` (many), and channel presentation fields. | [FIRST-PARTY OBSERVED] route/method/current consumer fields. [INFERENCE] acceptance cardinality. |
| Resource handoff | HTTPS HLS resource URL returned by the tune response; exact host/path are not published in the bundle. | No pre-approved external host exists in this research. Do not follow redirects, use a wildcard CDN allowlist, or allow arbitrary response-supplied hosts. | One HTTPS resource URL is necessary before an `AVURLAsset` can be created; URL value and host remain secret-adjacent and transient. | [STALE/UNCERTAIN] legacy OSS names an Akamai host, but that source is too old to authorize it. |
| Key authorization | `GET https://api.edge-gateway.siriusxm.com/playback/key/v1/{keyId}` | `Authorization: Bearer <opaque access token>`. The current player recognizes an HLS key URI with this path, replaces any source host with the configured API base plus its path, and adds the bearer header. | One protected key response; its material must remain in memory only and never be logged, persisted, or exposed as a semantic value. | [FIRST-PARTY OBSERVED] route and host-normalization behavior. |
| Live metadata | `POST https://api.edge-gateway.siriusxm.com/playback/play/v1/liveUpdate` | `Authorization: Bearer <opaque access token>` and a body with `channelId`, `startTimestamp`, and optional `endTimestamp`. | One update document; consumer code reads `items` (many) and merges it into the current linear-channel timeline. Malformed or absent metadata is non-fatal to audio. | [FIRST-PARTY OBSERVED] route/method/body names/consumer field. |
| Artwork | `GET https://imgsrv-sxm-prod-device.streaming.siriusxm.com/{encodedImageParams}` | The current image configuration declares no authorization header. Only a valid content-derived image parameter may be used; never follow a host supplied by an unvalidated response. | One image asset, optional independently of text. | [FIRST-PARTY OBSERVED] base URL/header absence. [INFERENCE] strict validation policy. |
<!-- DATA_8F6D2C1A_END -->

### What the Current First-Party Bundle Proves

[FIRST-PARTY OBSERVED] Its embedded configuration exposes the exact `browse-at-edge`, edge-gateway content, playback, key, live-update, and image templates above, all carrying the semantic authorization header name `Authorization` where authentication is required. It also marks `channel-linear` as an encrypted playback source. [Current entry bundle](https://cdn.web-cloud.siriusxm.com/sxm-player-web/shared/assets/index-DzOYWl_q.js).

[FIRST-PARTY OBSERVED] The current player invokes tune with a linear source identity, derives `V3` HLS and `V2` metadata/timeline settings, and consumes a tune response as one source with many streams. It reads a linear stream's current cuts from `metadata.live.items`, optional episodes from `metadata.live.episodes`, and channel presentation data. [Current playback bundle](https://cdn.web-cloud.siriusxm.com/sxm-player-web/shared/assets/src-Bae9Jwco.js).

[FIRST-PARTY OBSERVED] For a key URI matching the `playback/key/v1` path, the player discards the URI's host, preserves only its path, targets the configured playback base, and sends the opaque bearer authorization. This is the decisive reason the native adapter must not follow a key URL to an arbitrary CDN host. [Current playback bundle](https://cdn.web-cloud.siriusxm.com/sxm-player-web/shared/assets/src-Bae9Jwco.js).

[FIRST-PARTY OBSERVED] The public player uses HLS implementation assets and an explicit key-loading path; that supports HLS as the candidate media format. It does **not** establish that the subscriber's exact manifest uses an AVFoundation-compatible encryption/key mode. [Current player page](https://www.siriusxm.com/player).

## Host Policy and One-Run Allowlist

[INFERENCE] The narrowest safe policy is a fixed operation-to-host map, not the existing broad `*.siriusxm.com` cookie-domain predicate. The latter accepts the first-party cookie issuer domain but is not an authorization policy for provider destinations. [FirstPartyTokenCookiePolicy.swift](/Users/gabe/sirius-mac/SiriusMac/Authentication/FirstPartyTokenCookiePolicy.swift:71).

| Operation | Allowed method | Exact allowed host | Exact path policy | Stop before sending when |
|---|---|---|---|---|
| Catalog confirmation | GET | `browse-at-edge.siriusxm.com` | `/v2/all-channels` only | URL, method, redirect, content type, or response semantic shape differs. |
| Selected linear tune | POST | `api.edge-gateway.siriusxm.com` | `/playback/play/v1/tuneSource` only | selected identity is not a catalog-admitted `channel-linear`, request would add undeclared headers, or body cannot be built from the exact fields above. |
| HLS key, if and only if a confirmed manifest asks for it | GET | `api.edge-gateway.siriusxm.com` | `/playback/key/v1/{validated key identifier}` only | key URI does not normalize to that path; redirect, other host, unexpected key mode, challenge, 401/403/429, or malformed content occurs. |
| Live metadata, after a confirmed selected tune | POST | `api.edge-gateway.siriusxm.com` | `/playback/play/v1/liveUpdate` only | body cannot be derived from the selected channel and local clock, or the response is malformed. |
| Artwork, after a validated content image reference | GET | `imgsrv-sxm-prod-device.streaming.siriusxm.com` | one validated encoded-image path only | host, scheme, redirect, content type, or size limit differs. |

[INFERENCE] Do **not** put an HLS/CDN host into the initial allowlist. The tune response is the only current source that can name it, and no public bundle configuration fixes that host. The first confirmation can classify an unrecognized resource host as `unknown-host-or-redirect` without requesting it. This preserves the project's no-probing boundary.

## Tune, Resource, Key, and DRM Decision Tree

```text
catalog GET succeeds and has admitted channel-linear identity
  -> selected tune POST succeeds and has usable stream candidate
      -> returned resource host is pre-approved? no -> terminal unknown-host-or-redirect
      -> manifest arrives through approved resource path
          -> no protected key -> attempt AVFoundation HLS handoff once
          -> playback/key/v1 -> use exact edge-gateway key policy; no arbitrary key URL
          -> FairPlay or unrecognized protection -> terminal drm-or-access-control-ambiguous
```

[FIRST-PARTY OBSERVED] `channel-linear` is named among encrypted sources in the current configuration, and its browser implementation performs authenticated key handling. Therefore encryption/key authorization is expected, not an exceptional afterthought. [Current entry bundle](https://cdn.web-cloud.siriusxm.com/sxm-player-web/shared/assets/index-DzOYWl_q.js).

[FIRST-PARTY OBSERVED — Apple documentation] AVFoundation supports HLS playback; Apple exposes `AVAssetResourceLoader`/its delegate for resource requests and separately documents `AVContentKeySession` for FairPlay-protected content. Apple’s current HLS update says `AVAssetResourceLoader`-based key loading is deprecated for content keys and directs new FairPlay work to `AVContentKeySession`. [AVAssetResourceLoader](https://developer.apple.com/documentation/avfoundation/avassetresourceloader), [Streaming and AirPlay](https://developer.apple.com/documentation/avfoundation/streaming-and-airplay), [What’s new in HLS](https://developer.apple.com/streaming/Whats-new-HLS-2024.pdf).

[INFERENCE] AVFoundation/HLS feasibility remains **unverified**. A normal unprotected HLS stream may work with `AVPlayer`; a protected stream that demands the web player's bearer-header key normalization or FairPlay-specific exchange cannot be assumed to work. Do not add a fallback media engine, replay workaround, DRM workaround, or automatic reauthentication path. Classify it and stop.

## Metadata and Artwork Semantics

[FIRST-PARTY OBSERVED] The current playback code independently refreshes a linear channel with `channelId`, a start timestamp, and an optional end timestamp, then merges returned `items` into the live timeline. This supports Phase 02's requirement that metadata refresh is separate from audio state. [Current playback bundle](https://cdn.web-cloud.siriusxm.com/sxm-player-web/shared/assets/src-Bae9Jwco.js).

[OSS-IMPLEMENTED] The actively maintained Music Assistant provider treats SiriusXM output as HLS/AAC with seeking disabled and updates title, artist, and album artwork from live channel updates, falling back from current-cut artwork to channel artwork. Its implementation is useful corroboration of the semantic model but routes playback through its own local proxy and depends on the dated `sxm` client, so it is not authorization to copy its transport design. [Music Assistant provider](https://github.com/music-assistant/server/blob/dev/music_assistant/providers/siriusxm/__init__.py).

[STALE/UNCERTAIN] The older `sxm-client`/`andrew0` implementations use the historical `player.siriusxm.com/rest` contract and an older HLS handoff. Do not add those hosts, paths, cookie names, request parameters, or decryption behavior to the Phase 02 allowlist. [Legacy implementation](https://github.com/andrew0/SiriusXM/blob/master/sxm.py).

## Implementation Guidance for the Next Plan

1. Add a private `ContentRequestContract` distinct from `SiriusXMRequestContract`, with exact operation enums for catalog GET, tune POST, key GET, live-update POST, and artwork GET. It must not expose arbitrary URL/header/body construction.
2. Extend the observation model to represent `POST` as a closed fact before recording the tune or metadata operation. Retain only the existing semantic aliases and cardinalities; do not store URLs, header values, raw JSON, key IDs, stream URLs, or artwork URLs.
3. Make the first live run sequential: catalog → select one admitted `channel-linear` → tune. Stop immediately on a protected-control response, redirect, unknown host, malformed response, or any required field outside the parser's contract.
4. Do not hand a returned stream to `AVPlayer` until the resource host and manifest protection mode have themselves passed fixed validation. If they do, perform one AVFoundation attempt; otherwise record the appropriate terminal semantic protection and leave audio untested.
5. Keep `liveUpdate` and artwork in separately cancellable tasks. Their failure must update only metadata/artwork freshness, never the successful audio state.

## Security Domain

| Concern | Required control |
|---|---|
| Authentication/session (ASVS V2/V3) | Use only the already-established opaque Keychain credential in the existing native bearer request path; no cookie export, browser session reuse, or automatic login. |
| Access control (ASVS V4) | Re-check authorization through the exact catalog/tune service responses; a cached channel is never playback authorization. |
| Input validation (ASVS V5) | Validate every method, HTTPS host, fixed path, redirect absence, content type, cardinality, entity classification, and size before use. Treat all stream/key/artwork URL material as untrusted input. |
| Cryptography / DRM (ASVS V6) | Do not decode, persist, log, or adapt key material. If protection is not the confirmed supported mode, return `drm-or-access-control-ambiguous` and stop. |
| Diagnostics | Retain only `LiveContractObservation` semantic facts. The source explicitly closes terminal observations and permits no raw traffic or secrets. [LiveContractObservation.swift](/Users/gabe/sirius-mac/SiriusMac/Listening/LiveContractObservation.swift:137). |

## Open Questions That Require the One Authorized Confirmation

1. **What is the actual catalog document field layout and entitlement indicator?**
   - [FIRST-PARTY OBSERVED] The route and authorization header are current.
   - [INFERENCE] The app should accept only many `channel-linear` records with stable identities, but the exact JSON paths are not public contract documentation.

2. **Which HLS resource host and manifest protection mode does this subscriber receive?**
   - [FIRST-PARTY OBSERVED] The tune route and browser key normalization are current.
   - [STALE/UNCERTAIN] No current public source fixes the returned HLS CDN hostname.
   - [INFERENCE] An unknown host/mode must halt rather than broaden the allowlist.

3. **Can AVFoundation complete the protected HLS handoff?**
   - [FIRST-PARTY OBSERVED — Apple documentation] HLS is supported; FairPlay requires the supported Apple content-key path.
   - [INFERENCE] This cannot be proven without one actual entitled stream after the preceding gates pass.

## Sources

### Current first-party observations

- [SiriusXM public player](https://www.siriusxm.com/player) — current versioned bundle discovery, fetched 2026-08-19 without authentication.
- [SiriusXM current entry bundle](https://cdn.web-cloud.siriusxm.com/sxm-player-web/shared/assets/index-DzOYWl_q.js) — embedded content, playback, key, live-update, and image configuration.
- [SiriusXM current playback bundle](https://cdn.web-cloud.siriusxm.com/sxm-player-web/shared/assets/src-Bae9Jwco.js) — tune request construction, response consumption, metadata updates, and authenticated key-host normalization.

### Platform documentation

- [Apple AVAssetResourceLoader](https://developer.apple.com/documentation/avfoundation/avassetresourceloader)
- [Apple Streaming and AirPlay](https://developer.apple.com/documentation/avfoundation/streaming-and-airplay)
- [Apple What’s New in HLS](https://developer.apple.com/streaming/Whats-new-HLS-2024.pdf)

### OSS corroboration

- [Music Assistant SiriusXM provider](https://github.com/music-assistant/server/blob/dev/music_assistant/providers/siriusxm/__init__.py) — current maintained integration, labeled OSS-implemented.
- [andrew0 SiriusXM implementation](https://github.com/andrew0/SiriusXM/blob/master/sxm.py) — historical only, labeled stale/uncertain.

## Research Integrity

- [INFERENCE] No production code, existing contract artifact, coverage artifact, or tracking artifact was modified.
- [INFERENCE] No external package is recommended or installed, so no package-legitimacy audit applies.
- [INFERENCE] The attempted Context7 lookup did not return Apple’s AVFoundation documentation; Apple primary documentation was used instead.
- [INFERENCE] The final research-cache write for the Apple digest was blocked by sandbox permissions outside the workspace; this does not affect the committed artifact or its source links.
