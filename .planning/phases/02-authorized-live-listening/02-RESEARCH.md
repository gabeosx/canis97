# Phase 02: Authorized Live Listening - Research

**Researched:** 2026-08-19
**Domain:** Native macOS live-audio playback over a volatile, authorized SiriusXM integration
**Confidence:** MEDIUM

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

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| CAT-01 | Browse only the entitled standard and app-only `channel-linear` lineup. [VERIFIED: .planning/REQUIREMENTS.md:47] | Internal fixed-contract catalog adapter, strict content filter, typed snapshot, and safe live-contract checkpoint. |
| CAT-02 | Expose stable identity plus available presentation, entitlement, and freshness values. [VERIFIED: .planning/REQUIREMENTS.md:48] | Immutable semantic channel records and a timestamped catalog snapshot; missing fields remain optional. |
| CAT-03 | Surface catalog/entitlement failure without treating cached presence as playback authorization. [VERIFIED: .planning/REQUIREMENTS.md:49] | Catalog freshness state remains separate from tune-time entitlement and resolution. |
| PLAY-01 | Tune, start, pause, resume, and stop one entitled live stream. [VERIFIED: .planning/REQUIREMENTS.md:53] | A single `@MainActor` AVFoundation coordinator with live-edge semantics and explicit confirmation. |
| PLAY-02 | One coordinator serializes all application control surfaces. [VERIFIED: .planning/REQUIREMENTS.md:54] | One composition-owned coordinator and generation-based cancellation; Phase 3 attaches additional controls to it. |
| PLAY-03 | Use bounded, cancellation-aware recovery for expiry, network, sleep/wake, and stalls. [VERIFIED: .planning/REQUIREMENTS.md:55] | Classified recovery policy, `NWPathMonitor`, workspace sleep/wake notifications, and player/item observations. |
| PLAY-04 | Show distinct actionable failure states. [VERIFIED: .planning/REQUIREMENTS.md:56] | Closed public failure taxonomy and safe diagnostic operations rather than raw errors. |
| META-01 | Show active channel, current program/song text, and best available artwork. [VERIFIED: .planning/REQUIREMENTS.md:60] | Separate metadata fetch actor/task and precedence determined by the discovered provider contract. |
| META-02 | Keep metadata independent; render stale or unavailable honestly. [VERIFIED: .planning/REQUIREMENTS.md:61] | Metadata snapshot has fresh/stale/unavailable presentation state and cannot change audio state. |

## Project Constraints (from AGENTS.md)

- Target the current macOS release; no legacy API fallback layer. [VERIFIED: AGENTS.md]
- Keep a genuine native macOS application; do not wrap the SiriusXM website. [VERIFIED: AGENTS.md]
- Keep volatile SiriusXM wire behavior behind repairable compatibility adapters and tests. [VERIFIED: AGENTS.md]
- Keep credentials/tokens local and direct-to-SiriusXM only; Keychain stores secrets and diagnostics are redacted. [VERIFIED: AGENTS.md]
- Do not bypass CAPTCHA, MFA, subscription/device limits, anti-bot controls, DRM, or other service protections. [VERIFIED: AGENTS.md]
- Prefer maintained third-party or system solutions before a custom replacement. [VERIFIED: AGENTS.md]
- Use the GSD workflow for repository changes; this research is produced by the active planning workflow. [VERIFIED: AGENTS.md]

The root shim names `.agents/AGENTS.md` as canonical, but that file is absent in this checkout. [VERIFIED: .planning/phases/00-authentication-feasibility-gate/.continue-here.md:95-101]

## Summary

Phase 02 should be built around two containment boundaries. `SiriusXMClient` owns a fixed, internal, fail-closed provider adapter that produces semantic catalog, metadata, and ephemeral stream-resolution results. A single app-owned `@MainActor` playback coordinator owns the one `AVPlayer`, serializes every command, and converts observations into user-facing state. This matches Apple’s model: an `AVPlayer` manages only one media asset at a time and reuses the instance by replacing its current item. [CITED: https://developer.apple.com/documentation/avfoundation/avplayer]

The existing client intentionally stops at session verification. Its current internal contract contains only `case authentication` and `case entitlement`, and the public catalog, metadata, and live-stream methods return only `.unavailable`. [VERIFIED: Packages/SiriusXMClient/Sources/SiriusXMClient/InternalAdapters/SiriusXMRequestContract.swift:6-25] `public func catalog() -> CatalogAvailability { .unavailable }`, `public func metadata() -> MetadataAvailability { .unavailable }`, and `public func resolveLiveStream() -> LiveStreamResolutionAvailability { .unavailable }`. [VERIFIED: Packages/SiriusXMClient/Sources/SiriusXMClient/Public/SiriusXMClient.swift:80-93] Therefore no provider URL, response shape, metadata cadence, or media-key authorization mechanism may be guessed into production code.

Prior owner-authorized evidence says an issued session worked for account, tuning, manifest, and playback-key requests from an honest native-style client; it also records that the exact raw evidence was deleted. [VERIFIED: .planning/phases/00-authentication-feasibility-gate/.continue-here.md:29-48] No new live request was made during this research: the current code has no catalog/tune request contract, and a raw capture, browser-storage inspection, or improvised endpoint probing would violate the project’s secret and no-bypass boundary. The first execution plan must instead make one owner-visible, bounded discovery probe through the existing session, retain only an allow-listed semantic schema report, and stop on every protected-control signal. [VERIFIED: .planning/phases/00-authentication-feasibility-gate/.continue-here.md:86-107]

**Primary recommendation:** Implement a tracer-first, fixed-contract catalog → one selected channel → resolve → one `AVPlayerItem` flow, guarded by a human live-contract checkpoint; add recovery and independent metadata only after that exact path is confirmed.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Entitled linear catalog | API / Backend | Browser / Client | The client adapter decodes/provider-filters the authorized response; SwiftUI renders only semantic snapshots. [VERIFIED: .planning/phases/02-authorized-live-listening/02-CONTEXT.md] |
| Tune authorization and stream resolution | API / Backend | Browser / Client | Provider contract, session, entitlement, and ephemeral resource handling belong in the actor-owned client boundary. [VERIFIED: Packages/SiriusXMClient/Sources/SiriusXMClient/Session/SessionCoordinator.swift:3-8] |
| One live player and user controls | Browser / Client | API / Backend | `AVPlayer` is a main-actor media controller; the app owns its lifecycle while the client only supplies authorized ephemeral input. [CITED: https://developer.apple.com/documentation/avfoundation/avplayer] |
| Recovery | Browser / Client | API / Backend | The coordinator observes player/network/workspace events and asks the client to re-resolve only when a bounded policy permits it. [CITED: https://developer.apple.com/documentation/network/nwpathmonitor] |
| Current metadata | API / Backend | Browser / Client | Provider adapter refreshes semantic metadata independently; UI renders channel identity plus fresh/stale/unavailable information. [VERIFIED: .planning/phases/02-authorized-live-listening/02-CONTEXT.md] |

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Swift / Xcode | Swift 6.3.3 / Xcode 26.6 | Current package/app build and concurrency model | Installed toolchain targets `arm64-apple-macosx26.0`. [VERIFIED: `xcodebuild -version`; VERIFIED: `swift --version`] |
| Foundation `URLSession` | OS-bundled | Client-owned, ephemeral catalog/tune/metadata transport | Existing transport disables cookie and credential stores and uses reload-only caching. [VERIFIED: Packages/SiriusXMClient/Sources/SiriusXMClient/Transport/EphemeralURLSessionTransport.swift:31-37] |
| AVFoundation `AVPlayer` / `AVPlayerItem` | OS-bundled | One authorized live-media item, state observation, stall/failure signals | Apple supports local/remote file media and HLS; one player manages one media asset and can replace its item. [CITED: https://developer.apple.com/documentation/avfoundation/avplayer] |
| Network `NWPathMonitor` | OS-bundled | Network-path change signal for recovery eligibility | Apple documents a monitor with a path-update handler, explicit start queue, and cancellation. [CITED: https://developer.apple.com/documentation/network/nwpathmonitor] |
| AppKit `NSWorkspace` | OS-bundled | Sleep/wake recovery trigger | Apple provides `willSleep` and `didWake` workspace notifications; observers register with the workspace notification center. [CITED: https://developer.apple.com/documentation/appkit/nsworkspace/didwakenotification] |
| Swift Testing / XCTest | Swift 6.3 / Xcode 26.6 | Deterministic library and app-composition tests | The package already has independent test targets; the app already has an XCTest target. [VERIFIED: Packages/SiriusXMClient/Package.swift:5-16; VERIFIED: SiriusMac.xcodeproj/project.pbxproj:57-60] |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `OSLog.Logger` | OS-bundled | Closed semantic diagnostics | Extend the existing allow-listed operation/outcome sink; never put raw player error descriptions, stream references, headers, or response data in it. [VERIFIED: Packages/SiriusXMClient/Sources/SiriusXMClient/Diagnostics/SafeDiagnosticEvent.swift:3-75] |
| SwiftUI Observation | OS-bundled | Minimal Phase 02 browsing/listening presentation | Use an observable presentation model fed by confirmed coordinator/client state; do not make views issue provider requests. [ASSUMED] |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `AVPlayer` | VLC/libmpv/FFmpeg engine | Do not add an engine before the authorized stream is tested. A second engine does not solve an unverified provider authorization/key-loading contract and adds signing/security surface. [VERIFIED: AGENTS.md; VERIFIED: .planning/phases/00-authentication-feasibility-gate/.continue-here.md:58-60] |
| Fixed internal request operations | Open URL/request builder | Reject arbitrary provider URLs, headers, or redirects. Existing transport already validates an exact request contract and cancels redirects. [VERIFIED: Packages/SiriusXMClient/Sources/SiriusXMClient/Transport/DirectHostPolicy.swift:3-35; VERIFIED: Packages/SiriusXMClient/Sources/SiriusXMClient/Transport/EphemeralURLSessionTransport.swift:85-96] |
| One reused `AVPlayer` | Player-per-tune or `AVQueuePlayer` | One player is the required one-channel live-radio model; queues belong to a different product behavior. [CITED: https://developer.apple.com/documentation/avfoundation/avplayer] |

**Installation:** No external package installation is recommended for Phase 02. [VERIFIED: AGENTS.md]

## Architecture Patterns

### System Architecture Diagram

```text
Existing authenticated session
             |
             v
+-------------------------------+
| SiriusXMClient actor          |
| fixed internal adapters       |
+-------------------------------+
   | catalog snapshot     | selected channel
   v                      v
Native browse state   entitlement + stream resolution
   |                      |
   |                      v
   |                opaque, in-memory media resource
   |                      |
   +------------+---------+
                v
 +-------------------------------------------+
 | @MainActor PlaybackCoordinator             |
 | one AVPlayer / one current AVPlayerItem    |
 | command generation + bounded recovery task |
 +-----------+----------------+---------------+
             |                |
             v                v
    confirmed playback   independent metadata task
       state/UI              fresh -> stale -> unavailable
             ^                |
             |                v
       NWPath + sleep/wake + player/item observations
```

### Recommended Project Structure

```text
Packages/SiriusXMClient/
├── Sources/SiriusXMClient/
│   ├── Public/                 # semantic channel/catalog/metadata/playback results
│   ├── InternalAdapters/       # discovered, fixed provider request/decoder contracts
│   ├── Transport/              # ephemeral, direct-host transport and strict policy
│   └── Diagnostics/            # closed operation/outcome classifications
└── Tests/
    ├── SiriusXMClientTests/    # adapters, filters, retry-policy collaborators
    └── FixtureTests/           # invented/sanitized shapes only
SiriusMac/
├── Listening/                  # one playback coordinator and AVFoundation observers
├── Catalog/                    # presentation model and minimal browse screen
└── Metadata/                   # independent presentation state
```

This is a proposed implementation map, not a claim that these directories already exist. [ASSUMED]

### Pattern 1: Discover once, encode a fixed compatibility contract

**What:** Begin execution with a checkpointed, redacted discovery attempt using the active app session. Permit the resulting adapter only if it can state the operation purpose, request method/host policy, required non-secret request shape, response field types, and safe outcome classes without retaining raw values. [VERIFIED: .planning/phases/00-authentication-feasibility-gate/.continue-here.md:42-48; VERIFIED: .planning/phases/00-authentication-feasibility-gate/.continue-here.md:86-93]

**When to use:** Before adding catalog, tune, metadata, or resource-loading operations. A `403`, `429`, CAPTCHA/MFA/bot/control signal, unknown redirect, DRM ambiguity, or unrecognized schema is terminal for the probe and produces no workaround. [VERIFIED: .planning/phases/00-authentication-feasibility-gate/.continue-here.md:55-60; VERIFIED: .planning/phases/00-authentication-feasibility-gate/.continue-here.md:88-93]

**Implementation rule:** Extend the current two-operation allowlist only with individually named, tested operations. Do not refactor it into a request-builder API. The current transport uses `URLSessionConfiguration.ephemeral`, disables cookie and credential storage, and cancels every redirect; Phase 02 operations must preserve those properties. [VERIFIED: Packages/SiriusXMClient/Sources/SiriusXMClient/Transport/EphemeralURLSessionTransport.swift:3-37; VERIFIED: Packages/SiriusXMClient/Sources/SiriusXMClient/Transport/EphemeralURLSessionTransport.swift:75-96]

### Pattern 2: One coordinator, command generation, confirmed state

**What:** Place `AVPlayer`, the current item, KVO/notification tokens, the active resolution/recovery tasks, and a monotonically advancing command generation in one `@MainActor` coordinator. Every tune, stop, pause, resume, sleep, and sign-out invalidates obsolete asynchronous work before starting replacement work. [ASSUMED]

**When to use:** For all Phase 02 controls and for later Phase 3 windows/media controls. `AVPlayer` and `AVPlayerItem` are main-actor types in current documentation, and Apple describes item replacement as immediate. [CITED: https://developer.apple.com/documentation/avfoundation/avplayer] [CITED: https://developer.apple.com/documentation/avfoundation/avplayer/replacecurrentitem%28with%3A%29]

**Example:**

```swift
@MainActor
func installResolvedItem(_ item: AVPlayerItem) {
    removeObserversForCurrentItem()
    observeStatusBeforeAssociating(item)
    player.replaceCurrentItem(with: item)
}
```

Observe a player item before associating it with the player; Apple says association begins media loading, and item status becomes ready or failed through observation. [CITED: https://developer.apple.com/documentation/avfoundation/controlling-the-transport-behavior-of-a-player]

### Pattern 3: Separate observation from recovery policy

**What:** Treat player/item status, `timeControlStatus`, playback-stalled notification, network path changes, and sleep/wake notifications as inputs to a classified policy—not as direct retry commands. [CITED: https://developer.apple.com/documentation/avfoundation/avplayer/timecontrolstatus-swift.enum] [CITED: https://developer.apple.com/documentation/avfoundation/avplayeritem/playbackstallednotification] [CITED: https://developer.apple.com/documentation/network/nwpathmonitor] [CITED: https://developer.apple.com/documentation/appkit/nsworkspace/didwakenotification]

**When to use:** Always for recovery. Apple says a stall notification means media did not arrive in time, and streaming playback can continue after enough data arrives; therefore a stall alone is not proof that a new stream resource is needed. [CITED: https://developer.apple.com/documentation/avfoundation/avplayeritem/playbackstallednotification]

**Policy:** Wait through a bounded, observed buffering period; re-resolve only after a classified failure, expiry evidence, or policy timeout. Cancel recovery when the user changes channel/stops/signs out, the network remains unavailable, authorization/entitlement is lost, or budget is exhausted. Exact numbers must be discovered and injected into tests. [ASSUMED]

### Pattern 4: Metadata is a sibling task, never an audio dependency

**What:** Start a channel-generation-bound metadata task after a channel is selected. It may publish only if its generation still matches the active channel; it moves independently through fresh, stale, and unavailable presentation state. [ASSUMED]

**When to use:** While an entitled channel is selected, including when playback is buffering or terminally failed if a safe, authorized metadata refresh is still allowed. Audio transitions never await metadata. [VERIFIED: .planning/phases/02-authorized-live-listening/02-CONTEXT.md]

### Anti-Patterns to Avoid

- **Browser-presentation scraping:** The web player’s DOM is not the provider contract. Use a bounded semantic adapter probe or fail closed. [VERIFIED: .planning/phases/02-authorized-live-listening/02-CONTEXT.md]
- **Direct provider calls from SwiftUI:** This races views, leaks volatile details, and bypasses the existing client authority. [VERIFIED: Packages/SiriusXMClient/Sources/SiriusXMClient/Session/SessionCoordinator.swift:3-8]
- **Timer-driven blind retries:** A timer may convert a protected-control or entitlement loss into account activity. Recover only from classified, cancellation-aware causes. [VERIFIED: .planning/phases/02-authorized-live-listening/02-CONTEXT.md]
- **Treating `pause()` as a DVR feature:** The user decision promises only current-live-edge resume; provider-specific seeking/time-shift behavior remains unproven. [VERIFIED: .planning/phases/02-authorized-live-listening/02-CONTEXT.md]
- **Publishing AVFoundation error text:** Error/access logs can contain resource details. Map them immediately to a closed diagnostic/failure class. [ASSUMED]
- **Reusing the Phase 0 `AVContentKeySession` proof as the production design:** historical notes identify an AES-128 HLS key-authorization question, while the proof bridge constructs a FairPlay content-key session. That mismatch requires a live compatibility result; do not infer one protection scheme from the other. [VERIFIED: .planning/phases/00-authentication-feasibility-gate/.continue-here.md:58-60; VERIFIED: Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityCore/AuthorizedPlaybackProbe.swift:47-90]

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Media engine | Custom HLS parser, decoder, or alternate engine | `AVPlayer` / `AVPlayerItem` | Apple provides media control, HLS support, item replacement, state observation, and stall/failure signals. [CITED: https://developer.apple.com/documentation/avfoundation/avplayer] |
| Network reachability | Socket polling | `NWPathMonitor` | It emits path updates and has an explicit lifecycle. [CITED: https://developer.apple.com/documentation/network/nwpathmonitor] |
| Sleep detection | Polling wall-clock deltas | `NSWorkspace` workspace notifications | macOS emits sleep/wake environment notifications. [CITED: https://developer.apple.com/documentation/appkit/nsworkspace] |
| Authorization/entitlement inference | Catalog-cache heuristics | Current session plus per-tune adapter result | Cached records cannot prove current authorization under the locked decision. [VERIFIED: .planning/phases/02-authorized-live-listening/02-CONTEXT.md] |
| Provider parser framework | Permissive dynamic JSON mapper | Small versioned `Codable`/manual strict decoder in the internal adapter | Unknown or changed provider structure must fail closed and remain repairable. [VERIFIED: AGENTS.md] |

**Key insight:** Playback reliability comes from a small, observable state machine around system media APIs and a repairable provider adapter—not from attempting to make all upstream failures look like generic network errors. [CITED: https://developer.apple.com/documentation/avfoundation/avplayeritem/playbackstallednotification] [ASSUMED]

## Common Pitfalls

### Pitfall 1: A stable catalog becomes an implicit entitlement cache

**What goes wrong:** The user sees a cached channel and the UI implies it can still play. [VERIFIED: .planning/phases/02-authorized-live-listening/02-CONTEXT.md]

**How to avoid:** Keep catalog freshness, current session entitlement, and tune/stream authorization as three separate results; only the final resolution enables playback. [VERIFIED: .planning/phases/02-authorized-live-listening/02-CONTEXT.md]

### Pitfall 2: Recovery races a newer command

**What goes wrong:** A stale re-resolution attaches after the user has changed channels or pressed stop. [ASSUMED]

**How to avoid:** Cancel old tasks and observer tokens, increment a command generation, and check it after every `await` before publishing or replacing an item. [ASSUMED]

### Pitfall 3: Treating `waitingToPlayAtSpecifiedRate` as an immediate failure

**What goes wrong:** The app replaces a still-recovering item and causes needless request churn. [CITED: https://developer.apple.com/documentation/avfoundation/avplayer/timecontrolstatus-swift.enum]

**How to avoid:** Surface buffering first, inspect observed status/reason, and allow only a bounded policy to choose re-resolution. [CITED: https://developer.apple.com/documentation/avfoundation/avplayer/timecontrolstatus-swift.enum] [ASSUMED]

### Pitfall 4: Metadata task controls playback

**What goes wrong:** A malformed or slow metadata response interrupts healthy audio. [VERIFIED: .planning/phases/02-authorized-live-listening/02-CONTEXT.md]

**How to avoid:** Give metadata its own task, generation, freshness timestamp, and cancellation path; it may update only presentation state. [ASSUMED]

### Pitfall 5: Stream protection is assumed from a historical spike

**What goes wrong:** A FairPlay-oriented proof is promoted even though the historical note flags a separate AES-128 key authorization question. [VERIFIED: .planning/phases/00-authentication-feasibility-gate/.continue-here.md:58-60; VERIFIED: Spikes/AuthenticationFeasibility/Sources/AuthFeasibilityCore/AuthorizedPlaybackProbe.swift:47-90]

**How to avoid:** Test one authorized item with `AVPlayer` at the discovery checkpoint. If it cannot obtain required authorized media without a prohibited workaround, publish unsupported playback and stop; do not introduce a fallback engine. [VERIFIED: AGENTS.md] [ASSUMED]

## Code Examples

Verified patterns from official sources:

### Observe item readiness before installing it

```swift
statusObservation = item.observe(\.status, options: [.initial, .new]) { item, _ in
    Task { @MainActor in
        // Map ready/failed to a semantic coordinator state.
    }
}
player.replaceCurrentItem(with: item)
```

Apple’s playback guidance says to establish item-status observation before association because association triggers loading; present usable playback state only after readiness. [CITED: https://developer.apple.com/documentation/avfoundation/controlling-the-transport-behavior-of-a-player]

### Treat path changes as signals, not authorization

```swift
monitor.pathUpdateHandler = { path in
    Task { @MainActor in
        coordinator.handleNetworkPathChange(path)
    }
}
monitor.start(queue: monitorQueue)
```

`NWPathMonitor` delivers path updates after `start(queue:)`; application policy still decides whether recovery is appropriate. [CITED: https://developer.apple.com/documentation/network/nwpathmonitor]

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Legacy global AVPlayer notification spellings | Type-scoped `AVPlayerItem` notifications | Current Apple documentation | Use `AVPlayerItem.playbackStalledNotification` and `AVPlayerItem.failedToPlayToEndTimeNotification`; current docs mark the legacy failed-to-end spelling deprecated. [CITED: https://developer.apple.com/documentation/avfoundation/avplayeritem/failedtoplaytoendtimenotification] |
| Callback-only workspace observation | Notification or current Swift-concurrency workspace messages | Current Apple documentation | A Phase 02 implementation may use the clearer current-concurrency message form if it fits the project, but no additional framework is required. [CITED: https://developer.apple.com/documentation/appkit/nsworkspace] |

**Deprecated/outdated:** Do not use the deprecated global `AVPlayerItemFailedToPlayToEndTime` spelling; Apple directs clients to the type-scoped notification. [CITED: https://developer.apple.com/documentation/foundation/nsnotification/name-swift.struct/avplayeritemfailedtoplaytoendtime]

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | A command-generation check is the most suitable local cancellation pattern. | Architecture Patterns | A different existing concurrency/composition pattern may be preferable. |
| A2 | Metadata can be represented as fresh, stale, then unavailable with an independently cancelled task. | Architecture Patterns | Provider semantics could require a different cadence or fallback rule. |
| A3 | AVFoundation error/access-log text may expose resource detail and should never enter public diagnostics. | Anti-Patterns | Over-redaction is safe; insufficient redaction risks secret disclosure. |
| A4 | Buffer duration, retry budget/backoff, polling cadence, and stale thresholds need empirical tuning and injectable configuration. | Recovery / Metadata | Wrong values cause unnecessary listener activity or poor recovery. |
| A5 | An app-integration-only opaque stream handoff is preferable to a public raw URL. | Open Questions | A library-consumer playback API may need a differently bounded semantic surface. |

## Open Questions

1. **What are the current fixed catalog, tune, stream, metadata, artwork, and key-authorization contracts?**
   - What we know: Historical owner-authorized evidence records native account/tune/manifest/playback-key feasibility, while the exact raw capture was intentionally deleted. [VERIFIED: .planning/phases/00-authentication-feasibility-gate/.continue-here.md:32-48]
   - What's unclear: Current paths, payload field types, provider outcome mapping, service hosts, expiry semantics, and metadata cadence.
   - Recommendation: Make this the tracer’s first owner-visible `checkpoint:human-verify`. Reuse the authenticated app session, make the smallest read-only/minimally stateful request sequence, record only semantic shape/outcome information, and stop immediately on protected-control signals. [VERIFIED: .planning/phases/00-authentication-feasibility-gate/.continue-here.md:86-107]

2. **Can AVFoundation obtain and play the authorized stream without a prohibited custom authorization mechanism?**
   - What we know: Apple supports HLS in `AVPlayer`; historical notes separately flag AES-128 HLS key authorization as unresolved. [CITED: https://developer.apple.com/documentation/avfoundation/avplayer] [VERIFIED: .planning/phases/00-authentication-feasibility-gate/.continue-here.md:58-60]
   - What's unclear: Whether the discovered resource’s authorization can be passed to AVFoundation safely and whether it resumes at the desired live edge.
   - Recommendation: Play one owner-visible authorized item, then immediately stop/clear it. Do not promise or build a fallback media engine without this result. [VERIFIED: AGENTS.md]

3. **Which public API safely hands a resolved resource to an app playback layer?**
   - What we know: The library’s public surface must stay semantic while token/resource material stays ephemeral. [VERIFIED: .planning/REQUIREMENTS.md:18-20; VERIFIED: .planning/REQUIREMENTS.md:24-27]
   - What's unclear: Whether a public opaque resource, an app-integration SPI closure, or an Apple-platform playback-session protocol is the smallest safe contract.
   - Recommendation: Decide after the live-resource mechanism is known; keep URL/header/key material out of ordinary model descriptions, persistence, and diagnostics. [ASSUMED]

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|-------------|-----------|---------|----------|
| Xcode | app build/test and AVFoundation | ✓ | 26.6 | — [VERIFIED: `xcodebuild -version`] |
| Swift | package build/test | ✓ | 6.3.3 | — [VERIFIED: `swift --version`] |
| AVFoundation / Network / AppKit | playback and recovery | ✓ | OS-bundled current macOS SDK | — [VERIFIED: `xcodebuild -version`] |
| Existing authorized SiriusXM session | checkpointed contract validation | Not probed in this research session | — | Synthetic contract tests until owner-visible probe [VERIFIED: .planning/phases/01-safe-interoperability-foundation/01-UAT.md:78-89] |

**Missing dependencies with no fallback:** None for implementation/test work. Authorized live compatibility remains a human-visible checkpoint, not a CI dependency. [ASSUMED]

**Missing dependencies with fallback:** No provider contract fixture currently exists; use invented/sanitized fixtures for deterministic tests until the checkpoint yields safe semantic classifications. [VERIFIED: .planning/phases/01-safe-interoperability-foundation/01-CONTEXT.md:42-52]

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Swift Testing in the Swift package; XCTest in the macOS app target. [VERIFIED: Packages/SiriusXMClient/Package.swift:11-16; VERIFIED: SiriusMac.xcodeproj/project.pbxproj:57-60] |
| Config file | `Packages/SiriusXMClient/Package.swift`; no separate test-plan file found. [VERIFIED: Packages/SiriusXMClient/Package.swift:1-16] |
| Quick run command | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/SiriusXMClient` |
| Full suite command | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project SiriusMac.xcodeproj -scheme SiriusMac -destination 'platform=macOS'` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CAT-01 | Fixed adapter filters only entitled linear entries. | unit/contract | `swift test --package-path Packages/SiriusXMClient` | ❌ Wave 0 |
| CAT-02 | Channel snapshots preserve identity/optionals/freshness. | unit | `swift test --package-path Packages/SiriusXMClient` | ❌ Wave 0 |
| CAT-03 | Stale catalog never enables tune. | unit/app composition | package + `xcodebuild test` | ❌ Wave 0 |
| PLAY-01 | Commands lead to confirmed one-player states. | unit/app composition | package + `xcodebuild test` | ❌ Wave 0 |
| PLAY-02 | Concurrent/superseded commands serialize. | unit | `swift test --package-path Packages/SiriusXMClient` | ❌ Wave 0 |
| PLAY-03 | Recovery budget/cancellation/sleep/network/stall handling. | unit | `swift test --package-path Packages/SiriusXMClient` | ❌ Wave 0 |
| PLAY-04 | Every required failure domain maps to safe actionable state. | unit | `swift test --package-path Packages/SiriusXMClient` | ❌ Wave 0 |
| META-01 | Best metadata/artwork selection for active generation. | unit | `swift test --package-path Packages/SiriusXMClient` | ❌ Wave 0 |
| META-02 | Metadata failure leaves audio state intact and becomes stale/unavailable. | unit/app composition | package + `xcodebuild test` | ❌ Wave 0 |

### Sampling Rate

- **Per task commit:** quick package test command.
- **Per wave merge:** full app suite plus package suite.
- **Phase gate:** all deterministic tests green, then one owner-visible live smoke test that records only safe outcome classes. [ASSUMED]

### Wave 0 Gaps

- [ ] `Packages/SiriusXMClient/Tests/SiriusXMClientTests/LiveCatalogAdapterTests.swift` — covers CAT-01, CAT-02, CAT-03 with invented/sanitized inputs.
- [ ] `Packages/SiriusXMClient/Tests/SiriusXMClientTests/LivePlaybackCoordinatorTests.swift` — covers PLAY-01 through PLAY-04 using fake resolver/player/event collaborators.
- [ ] `Packages/SiriusXMClient/Tests/SiriusXMClientTests/MetadataRefreshCoordinatorTests.swift` — covers META-01 and META-02 with injected clock/metadata transport.
- [ ] `SiriusMacTests/ListeningCompositionTests.swift` — proves one app composition-owned coordinator and no optimistic presentation transition.
- [ ] Explicit human checkpoint specification for the one bounded live contract and AVFoundation smoke test.

## Security Domain

### Applicable ASVS Categories

OWASP’s current developer guide lists V2 Authentication, V3 Session Management, V4 Access Control, V5 Validation/Sanitization/Encoding, and V6 Stored Cryptography among ASVS categories. [CITED: https://devguide.owasp.org/en/03-requirements/05-asvs/]

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | yes | Reuse the existing typed, fail-closed session authority; no new sign-in path. [VERIFIED: Packages/SiriusXMClient/Sources/SiriusXMClient/Session/SessionCoordinator.swift:3-8] |
| V3 Session Management | yes | Keep tokens and resolved media resources in memory; cancel work on sign-out/channel supersession. [VERIFIED: .planning/REQUIREMENTS.md:18-20] |
| V4 Access Control | yes | Filter catalog by current entitlement and require tune-time authorization; cached channel presence does not authorize playback. [VERIFIED: .planning/phases/02-authorized-live-listening/02-CONTEXT.md] |
| V5 Input Validation | yes | Strict versioned internal decoders, host allowlist, content-type/status/control classification, and no dynamic request builder. [VERIFIED: Packages/SiriusXMClient/Sources/SiriusXMClient/Transport/DirectHostPolicy.swift:3-35] |
| V6 Stored Cryptography | yes | Continue existing Keychain boundary; do not introduce custom cryptography or persist stream/key material. [VERIFIED: AGENTS.md] |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Token-bearing stream/resource reaches a log, fixture, or disk cache | Information Disclosure | Opaque ephemeral handoff, closed diagnostics, invented fixtures, and explicit teardown. [VERIFIED: .planning/REQUIREMENTS.md:18-20] |
| Redirect or provider contract drift sends authorization to an unexpected destination | Information Disclosure / Tampering | Fixed per-operation host policy and redirect cancellation. [VERIFIED: Packages/SiriusXMClient/Sources/SiriusXMClient/Transport/DirectHostPolicy.swift:3-35; VERIFIED: Packages/SiriusXMClient/Sources/SiriusXMClient/Transport/EphemeralURLSessionTransport.swift:85-96] |
| Retry loop amplifies a control/rate-limit response | Denial of Service / Repudiation | Bounded classified recovery that immediately stops on protected-control or terminal authorization results. [VERIFIED: .planning/phases/02-authorized-live-listening/02-CONTEXT.md] |
| Provider JSON/image references alter UI or transport behavior | Tampering | Strict semantic adapter and allow-listed media/artwork route; no raw provider objects in UI. [ASSUMED] |

## Sources

### Primary (HIGH confidence)

- Local source of truth: `Packages/SiriusXMClient/Sources/SiriusXMClient/` — current public placeholders, actor session authority, ephemeral transport, strict host policy, and closed diagnostics. [VERIFIED: source files cited inline]
- Local phase context: `02-CONTEXT.md` and `REQUIREMENTS.md` — locked scope and requirement behavior. [VERIFIED: source files cited inline]

### Secondary (MEDIUM confidence)

- [AVPlayer](https://developer.apple.com/documentation/avfoundation/avplayer) — one-asset model, item replacement, HLS, control/state APIs.
- [Controlling the transport behavior of a player](https://developer.apple.com/documentation/avfoundation/controlling-the-transport-behavior-of-a-player) — observe item status before association.
- [AVPlayerItem playback-stalled notification](https://developer.apple.com/documentation/avfoundation/avplayeritem/playbackstallednotification) — stall semantics.
- [NWPathMonitor](https://developer.apple.com/documentation/network/nwpathmonitor) — network monitoring lifecycle.
- [NSWorkspace did-wake notification](https://developer.apple.com/documentation/appkit/nsworkspace/didwakenotification) — workspace notification routing.
- [OWASP ASVS developer guide](https://devguide.owasp.org/en/03-requirements/05-asvs/) — applicable category names.

### Tertiary (LOW confidence)

- No public SiriusXM provider API documentation was treated as implementation authority. Provider-specific facts remain limited to sanitized historical project evidence and the future live checkpoint. [VERIFIED: .planning/phases/00-authentication-feasibility-gate/.continue-here.md:29-48]

## Metadata

**Confidence breakdown:**

- Standard stack: HIGH — OS frameworks and installed toolchain are directly verified; no new package is required.
- Architecture: MEDIUM — one-player/client-boundary design is supported by current Apple docs and existing code, while the provider resource handoff remains unverified.
- Pitfalls: MEDIUM — Apple playback behavior and project safety boundaries are verified; provider expiry/key semantics still need the checkpoint.

**Research date:** 2026-08-19
**Valid until:** 2026-08-26 for provider-contract findings; Apple framework guidance remains stable but should be rechecked before an SDK bump.
