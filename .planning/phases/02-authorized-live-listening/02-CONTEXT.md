# Phase 02: Authorized Live Listening - Context

**Gathered:** 2026-08-19
**Status:** Ready for planning

<domain>
## Phase Boundary

Deliver the authorized live-listening core: retrieve and refresh the subscriber's entitled standard and app-only `channel-linear` lineup, present enough native browsing state to select a channel, resolve and control one live stream, recover safely from bounded playback failures, and show current channel/program metadata without coupling metadata health to audio health.

This phase does not build the finished compact player and library-window experience, favorites or recents, media-key and Now Playing integration, skins, diagnostics export, or release infrastructure. Those remain in Phases 3–5.

</domain>

<decisions>
## Implementation Decisions

### Lineup organization and freshness

- **D-01:** Expose only entitled standard and app-only `channel-linear` entries as the Phase 02 lineup. Xtra, replay, on-demand, and ambiguously classified entities do not appear as playable v1 channels.
- **D-02:** Give the lineup a predictable channel-number and category organization. Missing presentation fields may degrade gracefully, but stable SiriusXM entity identity remains authoritative.
- **D-03:** Preserve the last valid catalog for browsing when refresh fails, with explicit freshness or stale state. Cached presence never proves current entitlement or playback authorization; tuning must use current session and authorization state.

### Live control semantics

- **D-04:** Treat playback as live radio. Pause suspends audible playback; resume rejoins the current live edge and does not promise rewind, replay, or durable time-shifting.
- **D-05:** Stop ends active playback. A channel switch cancels obsolete resolution, metadata, and recovery work and replaces the active item through the one playback coordinator; it never creates a second player.
- **D-06:** User-facing state reflects confirmed player and authorization state rather than optimistic commands. Start, pause, resume, stop, and tune requests are serialized by the coordinator.

### Recovery experience

- **D-07:** Keep the subscriber's selected channel during recoverable failure. Recovery may re-resolve the stream and recreate the player item, but it must not silently switch channels or synthesize listener activity.
- **D-08:** Recovery is bounded, cancellation-aware, and classified by failure domain. It must stop on cancellation, superseding user commands, authentication or entitlement loss, unsupported upstream behavior, protected-control signals, or exhaustion of its retry budget.
- **D-09:** Authentication, entitlement, catalog, stream resolution, network, buffering/stall, decoder, and unsupported-upstream failures remain distinct and actionable. Terminal failure preserves enough non-secret state for the user to understand what failed and retry safely.

### Metadata freshness

- **D-10:** Metadata refresh runs independently from audio playback. Metadata delay, malformed data, or refresh failure never interrupts otherwise healthy audio.
- **D-11:** Show the active channel and best available current program or song text and artwork. Retain last-known metadata with an explicit stale state, then show unavailable rather than inventing or indefinitely presenting current-looking values.
- **D-12:** Channel identity is the stable fallback when richer metadata is missing. Artwork and text selection may degrade independently.

### the agent's Discretion

- Discover the current provider catalog, tune/authorization, stream-resolution, and metadata contracts through bounded, owner-authorized, redacted interoperability work. Do not infer them from the SiriusXM website's presentation or ask the owner to supply provider expertise.
- Validate the actual authorized stream format and behavior with AVFoundation before selecting any fallback playback engine or promising pause behavior beyond rejoining the live edge.
- Choose exact retry counts, backoff, timeouts, stall thresholds, sleep/wake triggers, metadata polling cadence, and stale-to-unavailable timing from observed behavior and platform guidance. These values must remain bounded, injectable/testable where appropriate, and repairable without changing the public semantic API.
- Choose exact minimal Phase 02 browsing/playback presentation, copy, type names, and internal adapter boundaries consistent with existing native patterns. Full multi-window visual design remains Phase 3.
- Choose the best artwork/text precedence from fields that are actually available, while preserving the explicit stale and unavailable semantics above.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Product and phase contract

- `.planning/PROJECT.md` — core value, native-app boundary, live-only v1 scope, secret handling, and no-bypass constraints.
- `.planning/REQUIREMENTS.md` — authoritative `CAT-01`–`CAT-03`, `PLAY-01`–`PLAY-04`, and `META-01`–`META-02` requirements.
- `.planning/ROADMAP.md` — Phase 02 goal, success criteria, dependency on Phase 1, and boundary with the Phase 3 desktop experience.

### Prior architecture and safety decisions

- `.planning/phases/01-safe-interoperability-foundation/01-CONTEXT.md` — settled authentication path, runtime-owned session authority, ephemeral secret handling, semantic client API, and fail-closed compatibility behavior.
- `.planning/research/ARCHITECTURE.md` — reusable-client boundary and containment of volatile upstream adapters.
- `.planning/research/STACK.md` — AVFoundation-first playback, Foundation transport, actor-owned playback coordination, and ephemeral resolved-resource guidance.
- `.planning/research/PITFALLS.md` — upstream compatibility, playback recovery, secret-handling, and protected-control risks to carry into research and planning.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- `Packages/SiriusXMClient/Sources/SiriusXMClient/Public/SiriusXMClient.swift`: existing actor and explicit `catalog()`, `metadata()`, and `resolveLiveStream()` placeholders provide the public integration seam for Phase 02 semantic APIs.
- `Packages/SiriusXMClient/Sources/SiriusXMClient/Public/AuthenticationModels.swift`: existing availability enums demonstrate the semantic, wire-schema-free public model style; Phase 02 should replace placeholders with typed domain results rather than expose endpoints or raw payloads.
- `Packages/SiriusXMClient/Sources/SiriusXMClient/Session/SessionCoordinator.swift`: existing actor-owned, cancellation-aware authentication and entitlement transaction is the authority Phase 02 must consult rather than treating catalog cache as authorization.
- `Packages/SiriusXMClient/Sources/SiriusXMClient/Transport/EphemeralURLSessionTransport.swift`: client-owned ephemeral transport is the established native request path for new internal catalog, authorization, and metadata adapters.

### Established Patterns

- Public APIs are typed, async, semantic, and isolated from endpoints, headers, cookies, and provider schemas.
- Internal adapters own fixed provider request contracts and fail closed on unknown response shapes or protected-control behavior.
- Actor isolation serializes mutable session authority; injected collaborators make time, transport, persistence, and diagnostics deterministic in tests.
- Diagnostics retain allow-listed semantic classifications and exclude credentials, authorization material, resolved stream URLs, and raw provider bodies.

### Integration Points

- Expand the existing unavailable catalog, metadata, and live-stream seams without leaking Phase 02 wire contracts into the public API.
- Introduce one playback coordinator above the reusable client and below every current or future app control surface; Phase 3 windows and system commands must later reuse it rather than create players.
- Replace the authentication-only root presentation in `SiriusMac/SiriusMacApp.swift` with the smallest native authorized-listening path needed for Phase 02 validation, while leaving the finished compact/library window architecture to Phase 3.
- Keep catalog refresh, stream resolution, player state, recovery, and metadata refresh independently observable so one failure domain does not masquerade as another.

</code_context>

<specifics>
## Specific Ideas

- The owner explicitly delegated provider-dependent behavior to empirical research because they are not expected to know or reproduce the SiriusXM online player's behavior.
- Prefer conservative live-radio semantics: predictable lineup organization, current-live-edge resume, bounded same-channel recovery, and stale-then-unavailable metadata that never interrupts healthy audio.
- Provider behavior must be observed safely; website behavior and planning assumptions are not evidence of an authorized native playback contract.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 02-authorized-live-listening*
*Context gathered: 2026-08-19*
