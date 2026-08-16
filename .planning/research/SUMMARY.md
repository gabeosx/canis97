# Project Research Summary

**Project:** Sirius Mac
**Domain:** Public native macOS live-radio player and reusable Apple-platform SiriusXM interoperability library
**Researched:** 2026-08-16
**Confidence:** MEDIUM

## Executive Summary

Sirius Mac should be built as a current-macOS native application for existing SiriusXM subscribers, not as a web wrapper. Its core product is a dependable live-channel loop—sign in safely, browse an entitled lineup, start one live stream, and control it naturally through macOS—paired with a compact nostalgic player, a proper library window, and safe skins. Experts would use SwiftUI for most presentation, small AppKit seams only for Mac-specific window behavior, AVFoundation and MediaPlayer for audio/system integration, Keychain Services for secrets, and SwiftData for non-secret local state.

The decisive architecture is a first-class, source-distributed SwiftPM library with a stable typed public API and internal replaceable protocol adapters. The app owns Keychain, AVPlayer, media controls, persistence, skins, and windows; the library owns only SiriusXM authentication, catalog, metadata, session, stream-resolution, and redacted compatibility behavior. This boundary turns an unsupported and volatile integration into a repairable capability rather than letting upstream changes spread into the UI or player.

The highest risks are upstream authentication/schema changes, accidental credential leakage, unreliable stream recovery, hostile skin packages, and broken public distribution. Mitigate them with strict fail-closed typed states, direct-only SiriusXM requests, ephemeral in-memory session/stream data, sanitized fixtures and canary-secret tests, one serialized playback state machine, declarative asset-bounded skins, and a signed/notarized/stapled release pipeline with clean-machine Homebrew verification. Public release remains conditional on an explicit policy/legal and compatibility gate; this is risk management, not a conclusion that distribution is authorized.

## Key Findings

### Recommended Stack

Use Xcode 26.6 / Swift 6.3 with Swift 6 strict concurrency and a macOS 26.0 deployment target. SwiftUI is the default UI framework; focused AppKit bridges may own compact-player frame/level behavior that SwiftUI cannot express cleanly. Foundation `URLSession`, direct Security.framework Keychain Services, SwiftData, AVFoundation, MediaPlayer, `OSLog.Logger`, Swift Testing, XCTest/XCUITest, SwiftPM, DocC, GitHub Actions/Releases, and Homebrew Cask cover v1 without speculative third-party stacks. `swift-dependencies` 1.10.0 is acceptable only as an app-internal test/preview aid; it must not leak into the reusable library API.

**Core technologies:**

- **SwiftPM `SiriusXMClient` library:** documented, semantically versioned source product with typed async capabilities/errors—contains protocol churn and enables reuse by native Apple apps.
- **SwiftUI with narrow AppKit interop:** two native windows and state-driven views—keeps the app Mac-native while reserving exact window control for measured gaps.
- **Foundation / actor isolation:** explicit client-owned transport, session, clock, and diagnostics collaborators—makes volatile request/session behavior deterministic and testable.
- **Security.framework Keychain Services:** app-owned credential store—keeps passwords and tokens out of preferences, SwiftData, fixtures, logs, and the package.
- **AVFoundation + MediaPlayer:** one `AVPlayer` and one media-session owner—provides HLS/live playback, media keys, and truthful Now Playing state.
- **SwiftData:** favorites, recents, selected skin, and small UI preferences only—never secrets, raw responses, or stream URLs.
- **Developer ID signing, notarization, stapling, GitHub Releases, Homebrew Cask:** the required public-distribution path—ensures Gatekeeper-compatible immutable artifacts.

**Reconciliation:** STACK calls the library product `SiriusXMClient` with an internal protocol target, while ARCHITECTURE labels the conceptual module `SiriusXMKit`. Adopt **`SiriusXMClient`** as the initial public SwiftPM product and keep adapter targets internal; package/product naming must be finalized before the first public prerelease and then treated as SemVer API surface. Similarly, use an Xcode app plus a local SwiftPM package in a monorepo; do not prematurely package every app service. An optional internal `SiriusSkinSchema` target is justified only for validation reuse and tests.

### Expected Features

**Must have (table stakes):**

- Strict subscriber sign-in/sign-out, Keychain storage, entitlement-aware catalog, and fail-closed errors—every other SiriusXM capability depends on this safe foundation.
- Live stream resolution and playback with distinct auth, entitlement, catalog, resolver, network, and decoder failures—recovery is bounded and visible, never a bypass.
- Channel/program metadata and artwork with explicit staleness—metadata failure must not restart otherwise healthy audio.
- Local favorites and recents keyed by stable channel IDs—quick return to listening without syncing secrets or upstream profile data.
- Background audio, Mac media keys, and Now Playing—one playback authority handles only live-radio-appropriate commands.
- Compact player plus independent library window, keyboard/VoiceOver access, and a non-skinned recovery path—both views observe the same app state.
- At least two bundled skins and validated local declarative packages—appearance may vary, but cannot remove semantics, fetch remotely, or execute code.

**Should have after the core compatibility path is proven:**

- A versioned reusable client library with compatibility diagnostics and redacted support export.
- Offline/stale presentation of cached catalog data, richer category/sort/channel-jump browsing, skin inspection/preview/migration tools, and measured artwork-cache/accessibility refinements.

**Defer (v2+ or exclude):**

- On-demand/replay, global search, recommendations, profile sync, Siri/Shortcuts, notifications, and personalized discovery.
- Recording/downloading/offline audio, remote or executable plugins/skins, Winamp-skin import, cloud token/favorite sync, aggressive keepalive/retry behavior, and any CAPTCHA/MFA/device/geo/DRM/anti-bot workaround.
- In-app auto-update: GitHub Releases plus a project-owned Homebrew tap satisfy v1 distribution without adding updater attack surface.

### Architecture Approach

The product has one inward dependency direction: views and platform adapters call app coordinators, which call only the library’s stable semantic API; the library actor calls internal wire adapters and `URLSession`. `SiriusXMClient` must expose domain models and typed errors—not cookie names, endpoints, playlist details, views, AVFoundation, MediaPlayer, SwiftData, or Keychain. Treat all SiriusXM protocol observations as untrusted/volatile implementation data and repair adapter code with sanitized contract fixtures.

**Major components:**

1. **`SiriusXMClient` public module and session actor** — serializes sign-in/renewal/sign-out and exposes catalog, metadata, and ephemeral live-stream resolution through injected transport, clock, credential source, and diagnostics collaborators.
2. **Internal auth/catalog/metadata/HLS adapters** — isolate each changing upstream behavior; no adapter types or raw wire data cross the package boundary.
3. **App facade and Keychain credential store** — retrieves the minimum scoped secret at the app boundary, maps library events to UI states, and clears memory/Keychain on sign-out.
4. **PlaybackCoordinator and MediaSession** — sole owners of `AVPlayer`, item generations, bounded re-resolution, media-key handlers, and confirmed Now Playing state.
5. **LocalLibraryStore** — stores favorites/recents against canonical channel IDs plus non-secret cached presentation snapshots.
6. **SkinStore / SkinRenderer** — validates a versioned data-and-assets-only manifest, preserves the previous/built-in skin on failure, and renders semantic native controls.
7. **RedactingDiagnostics and release pipeline** — emits allow-listed local events and produces signed/notarized/stapled artifacts with audit and Cask verification.

### Critical Pitfalls

1. **Treating undocumented behavior as a stable API** — keep every endpoint/schema/auth/HLS detail in internal adapters; use sanitized fixtures, capability checks, SemVer, and an adapter-only repair runbook.
2. **Failing open on auth, entitlement, or access-control changes** — model rejected, unsupported, challenge, and renewal states explicitly; stop and direct users to official resolution rather than guessing or bypassing.
3. **Leaking secrets in logs, fixtures, support, or persistence** — Keychain only for credentials, ephemeral session/stream data, private OSLog fields, redaction-by-construction, canary-secret tests, and no raw traces/exports.
4. **Racy or stale live playback** — one `@MainActor` coordinator controls a single player, player-item generations, cancellation, expiry, sleep/wake, and bounded retry with fake-clock tests.
5. **Unsafe skins and release engineering treated as later polish** — reject archives/paths/symlinks/unknown fields/oversized assets and execute signing, notarization, stapling, Gatekeeper, artifact checksum, and clean Cask installation gates before public launch.

## Implications for Roadmap

### Phase 1: Library Contract, Security Baseline, and Compatibility Harness

**Rationale:** The repair seam and security boundary must exist before any UI can safely depend on an unsupported service.

**Delivers:** Local SwiftPM `SiriusXMClient` skeleton; public models/capabilities/errors; internal adapter seams; actor session state machine; injected transport/clock/credential/diagnostic contracts; sanitized fixture rules; Keychain app adapter; redacting logs; CI secret scans.

**Addresses:** First-class reusable library, strict sign-in prerequisite, compatibility status foundation.

**Avoids:** Protocol details in UI, plaintext/local secret leakage, undefined auth state, untestable live-account dependency.

### Phase 2: Authorized Catalog and Live Playback Core

**Rationale:** A reliable end-to-end authorized tune path is the product’s first proof point and supplies the state every desktop integration needs.

**Delivers:** Fail-closed sign-in/entitlement behavior; refreshable normalized live catalog; metadata/artwork freshness model; resolver; one `AVPlayer` PlaybackCoordinator; expiry/stall/cancellation/offline recovery; deterministic tests using synthetic HLS/expiry data.

**Addresses:** Entitled browse, live playback, safe error clarity, and best-effort now-playing metadata.

**Avoids:** Durable stream URL storage, infinite recovery, decoder ambiguity, and stale async updates overwriting active selection.

### Phase 3: Native Listening Experience and Local Library

**Rationale:** Once playback is authoritative, all UI surfaces can dispatch the same semantic intents without creating multiple player lifecycles.

**Delivers:** SwiftUI compact single-instance player, library `WindowGroup`, favorites/recents via SwiftData, accessibility/keyboard/system menu behavior, MediaSession with supported media-key commands and truthful Now Playing, focused AppKit window bridges where proven necessary.

**Addresses:** Compact/native library workflow, favorites/recents, background operation, media keys, system controls, accessibility.

**Avoids:** UI-driven playback flags, duplicate command-center handlers, media controls that disagree with the player, and catalog refresh interrupting audio.

### Phase 4: Declarative Skin System and Resilience UX

**Rationale:** Skinning is a v1 promise but can only be safe when semantic controls and a non-skinned fallback already exist.

**Delivers:** Versioned manifest/schema validator, bundled skins, local import/selection, path/asset/resource budgets, hostile-package corpus/fuzz tests, recovery UI, and explicit resolving/buffering/stale/error states.

**Addresses:** Bundled/user skins and the distinctive nostalgic player identity.

**Avoids:** Executable/remote skin behavior, accessibility loss, archive traversal/resource exhaustion, and silent/crashing skin failures.

### Phase 5: Public Release Readiness and Maintained Compatibility

**Rationale:** A public unsupported integration is only shippable when its operational, privacy, governance, and distribution boundaries are verifiable.

**Delivers:** DocC and SemVer policy; compatibility/incident runbook; audited redacted diagnostic export (if justified); signed, hardened, notarized, stapled GitHub release pipeline; SBOM/checksum; project-owned Homebrew Cask; fresh-machine Gatekeeper/Cask tests; explicit public policy/legal review gate.

**Addresses:** Public reusable-library delivery, subscriber-safe support, GitHub/Homebrew installation.

**Avoids:** publishing unverified mutable artifacts, telemetry creep, asking users for raw logs/secrets, and protocol repair as an emergency UI rewrite.

### Phase Ordering Rationale

- Protocol containment, secret safety, and fixture discipline come first because catalog, playback, and every subsequent UI feature depend on them.
- Catalog/resolution/playback precede windows and skins so the app’s visual surfaces cannot accumulate their own request, recovery, or media-control logic.
- System integration belongs with the authoritative playback coordinator; favorites/recents belong with stable catalog identities rather than stream URLs or names.
- Safe skins are sequenced after semantic controls but before beta because they are core v1 value and need a hostile-input test corpus, not end-stage styling.
- Release hardening closes the roadmap because it validates an already-real end-to-end flow, but signing/notarization, privacy, and policy constraints should inform implementation from Phase 1 onward.

### Research Flags

Phases likely needing deeper research during planning:

- **Phase 1:** Required. Validate the current authorized SiriusXM interoperability surface with an authorized test account, preserve no sensitive captures, and define the minimal stable API/fixture policy. This is inherently volatile and may reveal an unshippable access-control requirement.
- **Phase 2:** Required. Confirm AVFoundation compatibility with an authorized resolved live resource, exact expiry/recovery behavior, entitlement variants, and safe failure classifications without workarounds.
- **Phase 4:** Required. Select an archive/container boundary and concrete resource limits; fuzz path/symlink/size/unknown-field handling before accepting user packages.
- **Phase 5:** Required. Validate current Developer ID, notarization, Homebrew policy, privacy-manifest, GitHub release, and owner/counsel distribution requirements immediately before public beta.

Phases with standard patterns (skip research-phase unless implementation evidence contradicts assumptions):

- **Phase 3:** Mostly standard Apple patterns: SwiftUI scenes, SwiftData local state, AVFoundation/MediaPlayer integration, accessibility, and focused AppKit interop are documented. Plan with direct platform tests rather than broad exploratory research.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | MEDIUM | Apple platform/distribution guidance is primary and current; exact current Xcode/Swift version claims should be rechecked at implementation time. |
| Features | MEDIUM | Official SiriusXM product surfaces support listener expectations, but entitlement/catalog and public-client policy behavior are dynamic and not API contracts. |
| Architecture | MEDIUM | Strong Apple documentation supports the native boundaries; the volatile adapter design is sound, while exact SiriusXM protocol behavior needs authorized validation. |
| Pitfalls | HIGH | Keychain, logging, AV lifecycle, declarative-input, notarization, and Cask mitigations are grounded in primary sources; individual upstream behaviors remain uncertain. |

**Overall confidence:** MEDIUM. The platform plan is high confidence; the defining uncertainty is whether the current SiriusXM flow can be implemented and publicly distributed within the project’s fail-closed and no-bypass constraints.

### Gaps to Address

- **Authorized interoperability viability:** Verify authentication, entitlement, stream delivery, and inactivity behavior only with an authorized account; if CAPTCHA/MFA/device/DRM controls are required, surface `unsupportedAuthentication`/equivalent and halt rather than adding a workaround.
- **Public-distribution permission and risk:** The customer agreement establishes a material policy risk but does not itself supply legal advice. Require owner/counsel review, disclaimers/support policy, and a go/no-go gate before beta/release automation is enabled.
- **Concrete protocol and playback contract:** Do not promote observed URLs, headers, cookies, expiry values, or HLS details into public API. Produce sanitized semantic fixtures and test recovery only after validated observation.
- **Exact skin package limits:** Define archive format, symlink policy, size/count/dimension/decode-time limits, and allowed manifest schema during Phase 4; reject ambiguity by default.
- **Sandbox and update policy:** Developer-ID/notarized distribution does not require App Sandbox; evaluate sandbox entitlements against the real authorized service before claiming support. Reconsider Sparkle only after a measured v1 update-UX need.

## Sources

### Primary (HIGH confidence)

- Apple documentation for SwiftUI windows, AVFoundation/AVPlayer/HLS, MediaPlayer remote commands and Now Playing, Keychain Services, `OSLogPrivacy`, privacy manifests, Developer ID signing, hardened runtime, notarization, and stapling — native implementation and distribution constraints.
- Swift and SwiftPM documentation plus Xcode release notes — current Swift toolchain, testing, source-package, and SemVer guidance.
- Homebrew Cask Cookbook and Tap Trust guidance — immutable artifact/checksum and owned-tap release expectations.
- SiriusXM official help, channel guide, streaming behavior, and Customer Agreement — user-facing baseline expectations and public-distribution risk context, not an integration contract.

### Secondary (MEDIUM confidence)

- Public StarPlayrX and `sxm-client` interoperability evidence — validates demand and the need for isolation, but is unendorsed and must not be copied as a current protocol contract.

### Tertiary (LOW confidence)

- Any specific undocumented SiriusXM endpoint, cookie/header, device claim, token lifetime, stream locator, schema, or access-control behavior — validate only in controlled authorized testing and keep sensitive evidence out of the repository.

---
*Research completed: 2026-08-16*
*Ready for roadmap: yes, subject to the Phase 1 and Phase 5 gates above.*
