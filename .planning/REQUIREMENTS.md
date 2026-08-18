# Requirements: Sirius Mac

**Defined:** 2026-08-16
**Core Value:** Subscribers can reliably start and control a live SiriusXM stream from a delightful native Mac player, even as the unsupported SiriusXM integration evolves underneath it.

## v1 Requirements

Requirements for the initial public release. Each requirement maps to exactly one roadmap phase.

### Authentication Feasibility

Phase 0 is historical. FEAS-01 records the accepted architecture; FEAS-02/03/05 are retired experiment/gate requirements and have no authority over product execution. FEAS-04's safety behavior continues under AUTH-02 and the Phase 1 acceptance plans.

- [x] **FEAS-01**: After the owner explicitly clicks a control in this app's nonpersistent `WKWebView`, the app may select only the one current first-party `AUTH_TOKEN` cookie, decode only `session.accessToken`, and pass it once in volatile memory to exact native SiriusXM HTTPS verifiers. Broad cookie/storage enumeration, arbitrary JavaScript extraction, developer tools, shared-browser state, persistence, diagnostics, fixtures, and raw artifacts remain prohibited.
- [x] **FEAS-02 (superseded)**: The alternative-path investigation is retired; the settled WebView-token/native-request path is the sole production architecture.
- [x] **FEAS-03 (superseded)**: Duplicate owner proof runs are not a Phase 1 or downstream execution gate.
- [x] **FEAS-04**: Any challenge, CAPTCHA, MFA requirement, HTTP 403 or 429, rate-limit signal, unexpected redirect, suspected bot response, protected-control behavior, or ambiguous entitlement evidence immediately stops the attempt and records no secrets or raw sensitive response data.
- [x] **FEAS-05 (superseded)**: Historical GO/NO-GO artifacts are retained for provenance only; Phase 1 executes from the architecture locked in ROADMAP.md and `01-CONTEXT.md`.

### Authentication

- [ ] **AUTH-01**: Subscriber can sign in directly against SiriusXM and receives explicit success, rejection, challenge, unsupported-flow, and entitlement outcomes.
- [ ] **AUTH-02**: Authentication fails closed when SiriusXM returns an unknown or changed flow without attempting to bypass CAPTCHA, MFA, device, geographic, anti-bot, DRM, or subscription controls.
- [ ] **AUTH-03**: Subscriber can sign out and the app clears active session material and its stored SiriusXM credentials.

### Security & Privacy

- [ ] **SECR-01**: Subscriber credentials are stored through a macOS Keychain-backed app adapter and are never persisted in preferences, SwiftData, fixtures, or other local application data.
- [ ] **SECR-02**: Session tokens and resolved stream resources remain ephemeral and leave the Mac only in direct requests to SiriusXM.
- [ ] **SECR-03**: Logs, fixtures, tests, crash context, compatibility reports, and support exports redact or exclude credentials, authorization material, token-bearing URLs, and raw sensitive responses by construction.

### Reusable Client Library

- [ ] **CLNT-01**: Other native Apple-platform software can consume a documented SwiftPM `SiriusXMClient` product independently of the Sirius Mac application.
- [ ] **CLNT-02**: Client consumers use typed async APIs, domain models, capabilities, and errors for authentication, entitlement, catalog, metadata, and live-stream resolution without depending on endpoints, cookies, headers, or raw wire schemas.
- [ ] **CLNT-03**: SiriusXM endpoint, schema, authentication, and stream-resolution details remain in internal replaceable adapters that do not leak into the library's public API.
- [ ] **CLNT-04**: The library accepts injected transport, clock, credential-source, and redacted-diagnostics collaborators where needed for deterministic testing and app-owned secret handling.
- [ ] **CLNT-05**: The public library has DocC documentation, semantic-versioning policy, sanitized contract fixtures, compatibility tests, and an adapter-repair runbook.

### Compatibility Diagnostics

- [ ] **COMP-01**: User can see whether authentication, entitlement, catalog, stream resolution, metadata, or playback compatibility is currently failing.
- [ ] **COMP-02**: User can export an explicitly reviewed support bundle containing app/library versions and allow-listed diagnostic classifications without secrets or raw upstream payloads.

### Live Catalog

- [ ] **CAT-01**: Subscriber can refresh and browse the entitled standard and app-only `channel-linear` lineup without exposing Xtra, replay, or on-demand entities as v1 channels.
- [ ] **CAT-02**: Each channel record provides a stable SiriusXM entity identity plus available number, name, description, category, artwork reference, entitlement state, and freshness timestamp.
- [ ] **CAT-03**: Catalog and entitlement failures are visible and do not imply that cached channel presence authorizes playback.

### Live Playback

- [ ] **PLAY-01**: Subscriber can tune an entitled linear channel and start, pause, resume, or stop its live stream from any application control surface.
- [ ] **PLAY-02**: One playback coordinator owns the active player and serializes commands from windows, menus, keyboard shortcuts, and system media controls.
- [ ] **PLAY-03**: Playback performs bounded cancellation-aware recovery and stream re-resolution for recoverable expiry, network, sleep/wake, and stall conditions without infinite retry or synthesized listener activity.
- [ ] **PLAY-04**: Subscriber sees distinct actionable states for authentication, entitlement, catalog, resolution, network, decoder, buffering, and unsupported-upstream failures.

### Channel Metadata

- [ ] **META-01**: Subscriber can see the active channel, current program or song text, and best available artwork while listening.
- [ ] **META-02**: Metadata refresh is independent from healthy audio playback and presents last-known information with explicit stale or unavailable state instead of inventing values.

### Local Library

- [ ] **LIBR-01**: Subscriber can add or remove a channel as a local favorite using its stable channel identity.
- [ ] **LIBR-02**: Subscriber can return to an ordered list of recently and successfully tuned channels.
- [ ] **LIBR-03**: Favorites and recents store only non-secret channel identity and presentation snapshots, never credentials, session material, or stream URLs.

### macOS Media Integration

- [ ] **MAC-01**: Live audio continues correctly while the app is backgrounded or its library window is closed.
- [ ] **MAC-02**: Subscriber can control live-appropriate playback actions through Mac media keys and system Now Playing surfaces.
- [ ] **MAC-03**: System Now Playing information reflects confirmed player state and current metadata rather than optimistic UI state.
- [ ] **MAC-04**: Subscriber can use appropriate system audio-device and routing behavior without the app implementing a custom audio-output stack.

### Desktop Experience

- [ ] **UI-01**: Subscriber can use a single-instance compact player window for channel identity, current metadata, favorite state, and primary playback controls.
- [ ] **UI-02**: Subscriber can use a separate native library window to browse entitled channels and categories and access favorites and recents.
- [ ] **UI-03**: Compact and library windows observe the same session and playback state, and opening or closing either window never creates another player or interrupts healthy audio.
- [ ] **UI-04**: Subscriber can move deterministically to the previous or next channel in the active entitled lineup and reveal the selected channel in the library.

### Accessibility

- [ ] **ACCS-01**: All essential player and library actions are usable with keyboard navigation and expose accurate VoiceOver labels, values, focus order, and state announcements.
- [ ] **ACCS-02**: Skin customization cannot remove semantic controls, minimum hit targets, readable focus/state indicators, or access to an unskinned native fallback.

### Skins

- [ ] **SKIN-01**: Subscriber can select between at least two bundled, complete, tested player skins.
- [ ] **SKIN-02**: Subscriber can import, validate, select, and remove local user-created skin packages defined only by versioned declarative data and local assets.
- [ ] **SKIN-03**: Skin packages cannot execute code, fetch remote content, contain active URLs, read arbitrary files, or control networking, playback, authentication, persistence, or accessibility semantics.
- [ ] **SKIN-04**: Skin validation rejects unknown schema, unsafe paths, traversal, symlinks, disallowed file types, and packages exceeding defined file-count, archive-size, decoded-asset, image-dimension, or processing-time budgets.
- [ ] **SKIN-05**: Invalid or failed skins leave the previous valid appearance intact and provide a reliable built-in recovery path.

### Public Distribution

- [ ] **REL-01**: Each public app release is a hardened, Developer-ID-signed, notarized, stapled, immutable GitHub Release artifact with published checksum and clean-machine Gatekeeper verification.
- [ ] **REL-02**: User can install and upgrade the canonical public release through a project-owned Homebrew Cask pinned to the immutable release artifact.
- [ ] **REL-03**: The app passively checks the latest published GitHub Release, tells the user when the installed version is outdated, and directs Homebrew users to run `brew upgrade` without downloading, staging, or installing an update itself.

## v2 Requirements

Deferred until the core live-listening and public-release path is validated.

### Resilience

- **RSLN-01**: User can browse cached favorites and last-known channel information during a catalog outage, with playback disabled until current authorization and stream resolution succeed.

### Skin Authoring

- **SAUT-01**: Skin creator can preview a package, inspect validation failures and resource budgets, and migrate a supported older manifest version.

### Discovery

- **DISC-01**: User can sort and filter the live lineup with richer browse controls beyond the v1 category and tuner experience.
- **DISC-02**: User can search eligible SiriusXM content after each content type's entitlement and playback semantics are independently defined.

### Additional Content

- **CONT-01**: Subscriber can play eligible SiriusXM Xtra channels with playback semantics distinct from linear radio.
- **CONT-02**: Subscriber can browse and play eligible on-demand shows, episodes, and replay content after separate authorization and playback research.

## Out of Scope

Explicit exclusions prevent unsafe behavior and uncontrolled scope growth.

| Feature | Reason |
|---------|--------|
| Cross-platform app or client-library support | The project intentionally optimizes for current macOS and native Apple-platform consumers. |
| Classic Winamp skin import | Legacy formats are an unbounded compatibility target; Sirius Mac defines a safe declarative format. |
| Remote, executable, or network-enabled skins/plugins | They create unacceptable code-execution, privacy, and supply-chain risks. |
| Recording, downloading, or offline audio playback | The project is a live player and will not expand the legal and technical risk surface. |
| Access-control bypasses | CAPTCHA, MFA, device, geographic, anti-bot, subscription, and DRM controls fail closed rather than being circumvented. |
| Aggressive keepalive or synthesized listener activity | The player respects upstream inactivity behavior and never hides it with automation. |
| Cloud synchronization of credentials, tokens, favorites, or diagnostics | Secrets and listening state remain local; upstream profile management stays on first-party surfaces. |
| Personalized recommendations and Pandora-style stations | They are outside the focused live-channel listening experience. |
| In-app automatic updater | GitHub Releases and Homebrew remain authoritative; the app only reports that an update exists. |
| Formal compatibility, policy, or legal release gate | The owner explicitly chose build and packaging readiness as the publication threshold; runtime authentication and entitlement behavior still fail closed. |

## Traceability

Every v1 requirement maps to exactly one delivery phase in `.planning/ROADMAP.md`.

| Requirement | Phase | Status |
|-------------|-------|--------|
| FEAS-01 | Phase 0 | Architecture accepted |
| FEAS-02 | Phase 0 | Superseded |
| FEAS-03 | Phase 0 | Superseded |
| FEAS-04 | Phase 0 | Carried into AUTH-02 |
| FEAS-05 | Phase 0 | Superseded |
| AUTH-01 | Phase 1 | Pending |
| AUTH-02 | Phase 1 | Pending |
| AUTH-03 | Phase 1 | Pending |
| SECR-01 | Phase 1 | Pending |
| SECR-02 | Phase 1 | Pending |
| SECR-03 | Phase 1 | Pending |
| CLNT-01 | Phase 1 | Pending |
| CLNT-02 | Phase 1 | Pending |
| CLNT-03 | Phase 1 | Pending |
| CLNT-04 | Phase 1 | Pending |
| CLNT-05 | Phase 5 | Pending |
| COMP-01 | Phase 5 | Pending |
| COMP-02 | Phase 5 | Pending |
| CAT-01 | Phase 2 | Pending |
| CAT-02 | Phase 2 | Pending |
| CAT-03 | Phase 2 | Pending |
| PLAY-01 | Phase 2 | Pending |
| PLAY-02 | Phase 2 | Pending |
| PLAY-03 | Phase 2 | Pending |
| PLAY-04 | Phase 2 | Pending |
| META-01 | Phase 2 | Pending |
| META-02 | Phase 2 | Pending |
| LIBR-01 | Phase 3 | Pending |
| LIBR-02 | Phase 3 | Pending |
| LIBR-03 | Phase 3 | Pending |
| MAC-01 | Phase 3 | Pending |
| MAC-02 | Phase 3 | Pending |
| MAC-03 | Phase 3 | Pending |
| MAC-04 | Phase 3 | Pending |
| UI-01 | Phase 3 | Pending |
| UI-02 | Phase 3 | Pending |
| UI-03 | Phase 3 | Pending |
| UI-04 | Phase 3 | Pending |
| ACCS-01 | Phase 3 | Pending |
| ACCS-02 | Phase 4 | Pending |
| SKIN-01 | Phase 4 | Pending |
| SKIN-02 | Phase 4 | Pending |
| SKIN-03 | Phase 4 | Pending |
| SKIN-04 | Phase 4 | Pending |
| SKIN-05 | Phase 4 | Pending |
| REL-01 | Phase 5 | Pending |
| REL-02 | Phase 5 | Pending |
| REL-03 | Phase 5 | Pending |

**Coverage:**

- v1 requirements: 48 total
- Mapped to phases: 48
- Unmapped: 0 ✓
- Duplicate mappings: 0 ✓

---
*Requirements defined: 2026-08-16*
*Last updated: 2026-08-17 after settling the WebView-token/native-request architecture and retiring the Phase 0 artifact gate*
