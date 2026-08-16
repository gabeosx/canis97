# Feature Research

**Domain:** Public, native current-macOS live SiriusXM player for existing subscribers
**Researched:** 2026-08-16
**Confidence:** MEDIUM

## Feature Landscape

### Table Stakes (Users Expect These)

The official SiriusXM experience already presents a Library for saved channels and ties listener profiles to favorites and listening history across its first-party surfaces. A desktop player needs the live-listening equivalent of that baseline, while treating every upstream response as volatile and entitlement-specific.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Strict subscriber sign-in and account lifecycle | A player cannot be useful without a subscriber session, and a public client must earn trust with credentials. | HIGH | Direct requests only to SiriusXM; Keychain-backed credentials/session material; redact diagnostics; do not attempt CAPTCHA, MFA, device-limit, geo, DRM, or anti-bot workarounds. Unknown or changed auth behavior must stop safely with an actionable status. |
| Entitlement-aware live channel lineup | SiriusXM’s official channel guide contains many categories and app-only channels; availability varies by plan and changes over time. | HIGH | Fetch and normalize a live catalog, category/grouping, number, name, description, artwork reference, availability, and volatility timestamp. Never hard-code the guide as the source of truth. |
| Start, stop, and recover live playback | This is the primary job of a radio player. Existing native clients explicitly focus on streaming with a valid subscription. | HIGH | Resolve a playable stream through the library, hand only the resolved media resource to the playback layer, and distinguish auth, entitlement, catalog, resolve, network, and decoder failures. Re-resolution after expiry or failure must be bounded and visible. |
| Now playing: channel, program/song metadata, and artwork | A listener needs confidence about what is playing; official SiriusXM surfaces present channel information and current-program artwork. | MEDIUM | Model metadata as best-effort and independently refreshable. Preserve last known data with staleness rather than inventing values. Use channel artwork when program artwork is absent. |
| Favorites and local recents | SiriusXM’s current Library/favorites and listener-profile history establish fast return-to-listening as baseline behavior. | MEDIUM | Keep an app-local, privacy-preserving ordered store keyed by stable channel identity. Favorites should work offline against cached channel records; recents record a successful user-initiated tune, not every metadata update. |
| Background playback, media keys, and system Now Playing | A Mac audio app should remain controllable after focus changes. Apple provides system remote-command/Now Playing facilities for this purpose. | MEDIUM | Publish title, channel, artwork, live state, and rate; register play/pause and only commands that have a clear live-radio meaning. Select one current Apple Now Playing API path in implementation; Apple warns against mixing framework generations for local playback. |
| Compact player and separate library window | The compact player supports habitual listening; a library window makes a large, changing lineup browseable without bloating the player. | MEDIUM | Both windows observe one playback/session state. Opening/closing the library must never interrupt audio; the compact window remains useful when catalog refresh is unavailable. |
| Bundled declarative skins plus safe local skin loading | The nostalgic skinnable identity is a core stated product promise, not optional polish. | HIGH | Ship tested bundled skins. User packages contain an allow-listed manifest, images, colors, layout metrics, and no executable code, remote fetches, URLs, scripts, or arbitrary file reads. Validate before use and retain the prior skin on failure. |
| Accessible native controls | A public desktop player needs keyboard operation, VoiceOver names, status announcements, contrast-resilient skins, and a non-skinned fallback. | MEDIUM | Skin data customizes appearance only; it cannot remove semantic labels, hit targets, focus order, or the accessible system menu/commands. Existing StarPlayrX explicitly treats VoiceOver support as a core feature, reinforcing this expectation. |

### Differentiators (Competitive Advantage)

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Versioned reusable `SiriusXMClient` library | Makes upstream breakage repairable and lets other native Apple apps reuse a documented integration boundary instead of copying app code. | HIGH | Treat it as a first-class product: stable public models/protocols, injected HTTP/credential/clock collaborators, fixtures, contract tests, semantic versioning, and redacted diagnostics. It exposes capabilities and errors—not UI views or secrets. |
| Explicit compatibility status and redacted support bundle | An unsupported, volatile integration is more trustworthy when users can tell whether sign-in, catalog, resolution, or playback is affected without leaking credentials. | MEDIUM | Provide a copy/export action only after review; include app/library version, endpoint capability outcome, timestamps, OS/playback state, and redacted error classifications. No authorization headers, cookies, URLs containing tokens, credentials, or raw response bodies. |
| Purpose-built live-radio interaction | A compact, keyboard-first channel tuner is faster than a website-shaped app for repeat listening. | MEDIUM | Channel up/down should be deterministic within the visible/in-entitled lineup; do not represent live radio as a seekable music library. Include favorite toggle and opening the selected channel in the library. |
| Nostalgic, safely portable skin format | Bundled personalities and user themes create identity without turning the player into an unreviewable plugin host. | HIGH | Publish a small schema and a skin validator/preview. Version manifests, constrain assets and total decoded size, and offer an unskinned recovery choice. Do not promise Winamp compatibility. |
| Graceful stale/offline library | Users can still see favorites, recents, and prior channel information while a catalog endpoint is unavailable. | MEDIUM | Cache non-secret catalog/artwork metadata with provenance and timestamp. Playback remains disabled until an authorized current stream can be resolved. |
| Real macOS ownership rather than a web wrapper | Native windows, media behavior, Keychain isolation, and system controls serve the product’s actual daily-use case. | HIGH | The app owns presentation/platform facilities; the client library owns protocol data. Keep web authentication or first-party handoff, if ever required, narrowly contained and non-exfiltrating. |

### Anti-Features (Commonly Requested, Often Problematic)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Any access-control bypass (CAPTCHA/MFA/device/geo/anti-bot/DRM) | It may appear to make a brittle client work more often. | Violates project safety boundaries and can compromise accounts, licensing, or service integrity. | Fail closed, explain the capability that failed without secrets, and require an authorized upstream path. |
| Recording, download, or offline playback | Listeners want replay and travel listening. | Outside v1, changes the legal/technical risk profile, and conflicts with the live-radio focus. | Live streaming only; retain local recents as references, never audio. |
| On-demand shows, episodes, search, recommendations, or Pandora-style stations in v1 | They resemble first-party breadth. | They multiply catalog, entitlement, UI, and playback semantics before dependable live listening exists. | Browse live categories, favorites, and recents; revisit only after the live compatibility contract is proven. |
| Remote or executable skins/plugins | Deep customization is attractive. | It creates code execution, privacy, supply-chain, and support risks in a public app. | Local declarative, schema-versioned packages with assets only and strict limits. |
| Winamp skin import | The aesthetic is appealing and an import sounds convenient. | Legacy formats are an unbounded compatibility target and may encode assumptions unsafe for a SwiftUI/AppKit layout. | A documented Sirius Mac manifest plus conversion guidance outside the app, if community demand emerges. |
| Cloud sync of credentials, tokens, favorites, or diagnostics | Cross-device continuity feels convenient. | Tokens/secrets must remain local; cloud sync introduces account exposure and contention with upstream listener profiles. | Keychain-local secrets and local favorites/recents; user may manage first-party profile data in SiriusXM’s own supported surfaces. |
| Aggressive automatic retries/keepalive automation | It might conceal transient errors or inactivity stops. | Can mask an upstream policy change, generate loops, or subvert listener-presence controls. SiriusXM documents an inactivity prompt after long continuous listening. | Bounded retry with exponential backoff, one transparent user action when interaction is required, and a clear stopped state. |
| Distribution before compatibility/legal release gate | GitHub Releases and Homebrew offer easy install. | Current SiriusXM terms reserve broad restrictions around service technology and can change access; public distribution magnifies the risk. | Keep library protocol research/test fixtures non-secret and ship public binaries only after legal/authorization review and stable fail-closed behavior are established. |

## Feature Dependencies

```text
Authorized sign-in + Keychain storage
    └──requires──> session/entitlement capability
                            ├──requires──> live catalog refresh
                            │                    ├──enables──> library browsing + channel artwork
                            │                    └──enables──> favorites/recents resolution
                            └──requires──> stream resolution
                                                 └──requires──> AV playback state
                                                                      ├──enables──> metadata/artwork refresh
                                                                      ├──enables──> media keys + Now Playing
                                                                      └──drives──> compact player + library windows

Declarative skin schema + validator
    └──requires──> semantic compact-player component model
    └──enhances──> bundled and user-created skins
    └──must not control──> playback, accessibility, networking, or code execution

Versioned reusable client library
    └──owns──> auth, catalog, metadata, stream resolution, compatibility diagnostics
    └──is consumed by──> app presentation + playback coordinator
```

### Dependency Notes

- **Live playback requires verified entitlement and fresh stream resolution:** A channel’s presence in cached catalog data never proves that a subscriber may play it. The app must ask the client library for the currently authorized resource immediately before playback.
- **Metadata/artwork requires a successful catalog and/or now-playing capability, but playback must not:** Audio can continue with stale visual metadata if a metadata refresh fails; never restart a live stream merely to refresh artwork.
- **Favorites and recents require stable channel identifiers:** Save canonical library IDs plus a cached presentation snapshot, not display names or a stream URL.
- **System controls require a single playback authority:** The compact window, library window, menu/keyboard actions, and media keys all dispatch to one coordinator to avoid duplicate player instances or conflicting Now Playing state.
- **User skins require semantic components before layout freedom:** Define named parts and state tokens first (display, artwork well, transport button, focused/disabled/error state), then permit only bounded declarative placement and style.
- **Library reuse requires a hard app/protocol boundary:** Any platform UI, Keychain wrapper, AV player, or skin object in the library API would make independent testing and future Apple-platform reuse materially harder.

## MVP Definition

### Launch With (v1)

- [ ] Strict, fail-closed subscriber sign-in with local Keychain-backed secret storage, explicit sign-out, and redacted error reporting — essential prerequisite for every SiriusXM interaction.
- [ ] Independently testable, documented, versioned SiriusXM client library with injected collaborators and capability/error models — contains upstream volatility and is a stated product artifact.
- [ ] Refreshable entitled live lineup with categories, channel artwork, current metadata where available, cached timestamp, and clear unavailable states — makes live listening discoverable without pretending static data is current.
- [ ] Live tune/play/pause/stop using a single playback coordinator, bounded recovery, and no bypass behavior — validates the product’s core promise.
- [ ] Local favorites and recents — gives the fastest return path and matches established first-party listening expectations.
- [ ] Media keys, background audio, and system Now Playing with live-appropriate commands — makes it a Mac player rather than a foreground-only stream window.
- [ ] Compact player and library window, both accessible and backed by the same state — delivers the intended daily interaction model.
- [ ] At least two bundled skins plus validated local declarative skin packages, an explicit safe schema, and an unskinned recovery path — skinning is core v1 value, not deferred decoration.
- [ ] Release gate: documented compatibility/legal review, signed/notarized build readiness, and a public issue/support policy that never requests secrets — public distribution is conditional on this gate.

### Add After Validation (v1.x)

- [ ] Richer channel browse affordances (sorting, category filters, keyboard channel jump) — add after the live catalog model proves stable across real subscriber plans.
- [ ] Skin preview, package inspector, and schema migration tooling — add once the base manifest is stable and user authors need feedback beyond validation errors.
- [ ] Opt-in redacted diagnostic export and compatibility-status view — add when actual beta failures show which data is useful without risking privacy.
- [ ] Local artwork cache management and richer accessibility tuning — add after measuring memory/disk use and validating VoiceOver across bundled skins.

### Future Consideration (v2+)

- [ ] First-party-authorized account/profile synchronization — only if SiriusXM exposes a supported authorization route and it can avoid token export.
- [ ] On-demand and replay content — defer until its entitlement/playback model is independently researched and live playback is demonstrably dependable.
- [ ] Siri/Shortcuts, notification rules, personalized features, and broader discovery — defer because they add policy and privacy surface without improving the basic live-radio loop.

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Fail-closed auth, Keychain, and client capability model | HIGH | HIGH | P1 |
| Live catalog and entitlement-aware channel browse | HIGH | HIGH | P1 |
| Live stream resolution, AV playback, failure recovery | HIGH | HIGH | P1 |
| Current metadata and artwork | HIGH | MEDIUM | P1 |
| Favorites and recents | HIGH | MEDIUM | P1 |
| Media keys, Now Playing, and background operation | HIGH | MEDIUM | P1 |
| Compact player plus library window | HIGH | MEDIUM | P1 |
| Bundled and declarative user skins | HIGH | HIGH | P1 |
| Accessibility and non-skinned recovery | HIGH | MEDIUM | P1 |
| Redacted diagnostics export | MEDIUM | MEDIUM | P2 |
| Advanced browse/filtering and skin-author tools | MEDIUM | MEDIUM | P2 |
| On-demand/search/recommendations | MEDIUM | HIGH | P3 |
| Recording/offline downloads/executable extensions | LOW | HIGH | Exclude |

**Priority key:**

- P1: Must have for launch
- P2: Should have after core compatibility validates
- P3: Future consideration

## Competitor and Interoperability Feature Analysis

| Feature | Official SiriusXM surfaces | Public client/libraries observed | Sirius Mac approach |
|---------|----------------------------|----------------------------------|--------------------|
| Saved content and history | The official Library replaces Favorites; listener profiles link favorites and listening history across supported first-party surfaces. | No reusable, documented public Apple-native library was found in this research pass. | Keep local, channel-only favorites/recents as a fast live-listening feature; do not claim or manipulate first-party profile state. |
| Channel lineup | Official channel guide has large, dynamic, plan-dependent and app-only inventory. | Public players demonstrate the concept but cannot make a static guide dependable. | Refresh via replaceable library adapters, cache presentation data with a timestamp, and filter on observed entitlement. |
| Native macOS playback | First-party web/player experience is not a dedicated native Mac app. | StarPlayrX is a public macOS native client that requires a valid SiriusXM subscription and separates `StarPlayrRadioKit` from app code; its README also flags distribution restrictions. | Deliver a genuinely native current-macOS player with an independently versioned client library; do not adopt unverified third-party protocol code as a dependency. |
| Media controls/accessibility | Official web/app experiences provide broad listening functionality. | StarPlayrX lists VoiceOver support, showing native accessibility is an active community expectation. | Treat VoiceOver, keyboard access, media keys, background audio, and system Now Playing as launch requirements and preserve them regardless of skin. |
| Playback continuity | SiriusXM documents that continuous streaming can require user confirmation after extended inactivity. | No public source found that establishes a safe alternative policy. | Respect upstream listener confirmation: do not synthesize activity; surface the requirement and stop safely if the upstream service requires it. |
| Account/technology policy | The current customer agreement says SiriusXM can modify availability and places strong limits on service technology use and security tampering. | Existing code proves demand, not authorization or durability. | Make authorized access and legal compatibility a release gate; no account sharing, scraping, reverse-engineering automation, DRM removal, or access-control bypass is a product feature. |

## Sources

- [SiriusXM: saving/removing favorites in the Library](https://www.siriusxm.com/help/favorite-online) — official, current crawl; MEDIUM confidence for product-surface expectations.
- [SiriusXM Listener Profiles FAQ](https://www.siriusxm.com/help/profiles-2?desktop=yes) — official, current crawl; MEDIUM confidence for cross-surface favorites/history behavior.
- [SiriusXM channel guide PDF](https://www.siriusxm.com/sxm/pdf/sirius/channelguide.pdf) — official; MEDIUM confidence because the guide is dynamic and not an API contract.
- [SiriusXM streaming inactivity behavior](https://www.siriusxm.com/help/streaming-listening) — official, current crawl; MEDIUM confidence.
- [SiriusXM Customer Agreement](https://www.siriusxm.com/customer-agreement) — official, current crawl; MEDIUM confidence. This is a product-risk finding, not legal advice.
- [Apple: `MPRemoteCommandCenter`](https://developer.apple.com/documentation/mediaplayer/mpremotecommandcenter) and [Apple: Now Playing](https://developer.apple.com/documentation/NowPlaying) — official, current crawl; MEDIUM confidence on current API selection details; validate exact current-macOS API availability during implementation.
- [Apple TN3137: On Mac keychains](https://developer.apple.com/documentation/Technotes/tn3137-on-mac-keychains) — official; MEDIUM confidence on macOS-specific Keychain behavior.
- [StarPlayrX public repository](https://github.com/macOS26/StarPlayrX) — public third-party source, current crawl; MEDIUM confidence. Used only as ecosystem evidence, not as a protocol implementation or authorization source.
- [node-sonos-http-api SiriusXM endpoint documentation](https://github.com/jishi/node-sonos-http-api) — public third-party source, current crawl; LOW confidence for SiriusXM interoperability specifics; it merely corroborates that other integrations expose tuning by channel, not a recommended implementation.

## Research Gaps and Release Implication

No official public SiriusXM API or explicit third-party-client authorization was located. The current customer agreement’s restrictions and the observed volatility mean the project must not treat a successful prototype as sufficient for public binary distribution. A release candidate needs a separate legal/authorization decision and live-account validation that uses only a consenting subscriber’s direct requests, retains no secrets in logs/fixtures, and fails closed when upstream controls require first-party interaction.

---

*Feature research for: Sirius Mac live SiriusXM player*
*Researched: 2026-08-16*
