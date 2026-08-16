# Architecture Research

**Domain:** Native macOS live SiriusXM player with an Apple-platform client library
**Researched:** 2026-08-16
**Confidence:** MEDIUM — macOS platform decisions come from current Apple documentation; the SiriusXM protocol boundary is necessarily based on public, unsupported interoperability evidence and must be verified against a subscriber account during implementation.

## Recommendation in One Sentence

Build two Swift packages and one app target: a small, public `SiriusXMKit` library whose only job is safe, testable SiriusXM interoperability, and a `SiriusMac` app that owns Keychain access, playback, SwiftUI/AppKit presentation, skins, persistence, diagnostics, and release packaging.

## Standard Architecture

### System Overview

```
┌────────────────────────────────── SiriusMac.app ──────────────────────────────────┐
│ SwiftUI scenes                                                                    │
│  Compact Player `Window`       Library `WindowGroup`       Settings/About         │
│          │                              │                                      │
│          └─────────────── AppController (@MainActor) ─────────────────────────┐   │
│                                                                                  │   │
│  App services                                                                    │   │
│  PlaybackCoordinator ── AVPlayer ── MediaSession (media keys / Now Playing)    │   │
│  LocalLibraryStore (favorites, recents)     SkinStore + SkinRenderer            │   │
│  KeychainCredentialStore    RedactingDiagnostics                                │   │
│          │                                                                       │   │
│          └────────────────────── SiriusClientFacade ────────────────────────────┘   │
└──────────────────────────────────────┬────────────────────────────────────────────┘
                                       │ stable public API only
┌──────────────────────────────────────▼────────────────────────────────────────────┐
│                                SiriusXMKit (SwiftPM)                               │
│ Public domain API: Session, ChannelCatalog, LiveStreamResolver, SiriusXMError     │
│                                                                                     │
│ SessionCoordinator (actor) → CatalogService / MetadataService / StreamResolver    │
│             │                                                                       │
│   injected: HTTPTransport, Clock, CredentialSource, CookieStore, DiagnosticsSink   │
│             │                                                                       │
│ Internal volatile adapters: AuthWireAdapter, ExperienceWireAdapter, HLSWireAdapter │
│             │                                                                       │
└─────────────┴─────────────────────────────────────────────────────────────────────┘
              │ direct TLS requests only; no proxy and no credential telemetry
              ▼
        SiriusXM endpoints and HLS/CDN (unsupported, volatile)
```

Apple explicitly supports a SwiftUI app that embeds AppKit where needed, and its current scene model supports both groups of windows and a unique single-instance `Window`. Use that division: a unique compact player window and a `WindowGroup` library browser. Do not build an all-AppKit application or a custom window manager merely for the skin. [SwiftUI framework integration](https://developer.apple.com/documentation/swiftui), [Windows](https://developer.apple.com/documentation/swiftui/windows) (HIGH confidence).

### Component Responsibilities

| Component | Responsibility | Typical implementation / direction |
|---|---|---|
| `SiriusXMKit` public module | Stable subscriber-facing domain API and typed errors; no UI, AVFoundation, Keychain, or app preferences | SwiftPM library target. Depends only on Foundation, Security-compatible protocol types if needed, and injected abstractions. |
| `SessionCoordinator` | Establish, refresh, invalidate, and serialize a SiriusXM session | `actor`; owns only in-memory session/cookie material. Depends on internal adapters and injected collaborators. |
| Volatile wire adapters | Encode requests, decode responses, extract endpoint configuration, and resolve short-lived HLS locators | Internal types; no adapter type appears in public API. One small adapter per behavior to localize protocol repairs. |
| `SiriusClientFacade` | App-facing orchestration: reads credentials, invokes library, publishes semantic events | App target. Maps library output into view and playback commands; never gives views wire objects. |
| `PlaybackCoordinator` | One active live stream: resolve, assign `AVPlayerItem`, observe failures/buffering, bounded recovery | `@MainActor` observable service. Only this component imports AVFoundation. |
| `MediaSession` | Media keys, Control Center/Now Playing fields, artwork update | App adapter around MediaPlayer. Commands call `PlaybackCoordinator`, not the library. |
| `LocalLibraryStore` | Favorites and recents owned by this app, separate from upstream channel data | SwiftData or a small local persistence repository; store stable channel identifiers plus presentation snapshots. |
| `KeychainCredentialStore` | Persist credentials and optionally a session only if implementation proves it is safe/useful | App-owned `SecItem` wrapper. Library receives a short-lived credential value through a protocol, never calls Keychain itself. |
| `SkinStore` / `SkinRenderer` | Locate, validate, select, and render bundled or user skin packages | Data-only manifest plus asset URLs. SwiftUI rendering, with a narrow `NSWindow` bridge only for window-level behavior. |
| `RedactingDiagnostics` | Structured, correlation-friendly local logs and an explicit sanitized diagnostic export | App and library `DiagnosticsSink`; redact by construction before values reach `Logger`. |

### Dependency Rule

Dependencies point inward toward stable domain types:

```
SwiftUI/AppKit views → AppController / coordinators → SiriusXMKit public API
AVFoundation / MediaPlayer adapters ────────────────┘
SiriusXMKit public API → session actor → internal wire adapters → HTTPTransport
tests/fixtures ────────────────────────┘
```

Neither a view nor `AVPlayer` may import a wire adapter. `SiriusXMKit` must not import SwiftUI, AppKit, AVFoundation, MediaPlayer, SwiftData, or use an application singleton. This is the real reusable-library boundary; it is more useful than a cross-platform abstraction layer.

## Recommended Project Structure

```
SiriusMac/
├── Package.swift                         # workspace SwiftPM package / shared build settings
├── Sources/
│   ├── SiriusXMKit/                      # public, semantic Apple-platform library
│   │   ├── Public/                       # Client, models, errors, protocols
│   │   ├── Session/                      # SessionCoordinator actor and renewal policy
│   │   ├── Adapters/                     # internal auth/catalog/metadata/stream protocol code
│   │   ├── Transport/                    # URLSession transport and cookie handling
│   │   └── Diagnostics/                  # redacting event contracts
│   ├── SiriusMacApp/                     # app composition root and SwiftUI scenes
│   │   ├── AppState/                     # AppController and view state projection
│   │   ├── Playback/                     # AVPlayer, MediaPlayer, recovery
│   │   ├── Credentials/                  # SecItem wrapper
│   │   ├── Library/                      # favorites / recents persistence
│   │   ├── Skins/                        # manifest validator, resources, rendering
│   │   ├── Windows/                      # AppKit bridges only when SwiftUI lacks a window hook
│   │   └── Diagnostics/                  # local log + export policy
│   └── SiriusSkinSchema/                 # Codable manifest model/validator shared by app tests
├── Tests/
│   ├── SiriusXMKitTests/                 # deterministic unit and contract tests
│   ├── SiriusXMKitFixtures/              # sanitized response/playlist fixture resources
│   ├── SiriusMacAppTests/                # coordinator and persistence tests
│   ├── SiriusSkinSchemaTests/            # malicious/invalid package tests
│   └── SiriusMacUITests/                 # compact window/library/media-key acceptance flows
├── Skins/                                # signed/bundled declarative skin packages
├── Scripts/                              # release validation: archive, sign, notarize, staple, assess
└── .github/workflows/                    # CI, fixtures, release and Homebrew cask update automation
```

Keep `SiriusSkinSchema` separate only if fixtures or a future skin validator need to read manifests without loading the app. Do not make every app service a package on day one; `SiriusXMKit` is the product boundary, and the app folders are enough until a genuine reuse case appears.

## Library Public API and Volatile Adapter Contract

The public API exposes *meaning*, not a request path, cookie name, token, endpoint URL, media playlist contents, or browser/device emulation detail. Public source evidence shows that existing unofficial clients depend on dynamically supplied configuration, cookie-backed session state, token parameters, a short session lifetime, and HLS playlist resolution; it also documents expiry and multiple-login recovery behavior. That supports a strict adapter boundary, not a copied protocol contract. [sxm-client source](https://sxm-client.readthedocs.io/en/stable/_modules/sxm/client.html) (MEDIUM confidence).

```swift
public struct SiriusXMClient: Sendable {
    public init(
        transport: any HTTPTransport,
        credentials: any CredentialSource,
        clock: any Clock<Duration>,
        diagnostics: any DiagnosticsSink = NoopDiagnosticsSink()
    )

    public func signIn() async throws -> AccountSession
    public func signOut() async
    public func channels(forceRefresh: Bool = false) async throws -> [LiveChannel]
    public func nowPlaying(for channel: ChannelID) async throws -> ProgramMetadata
    public func resolveLiveStream(for channel: ChannelID) async throws -> ResolvedLiveStream
}

public struct ResolvedLiveStream: Sendable {
    public let url: URL                 // ephemeral, never persist or log
    public let expiresAt: ContinuousClock.Instant?
    public let channel: LiveChannel
}

public enum SiriusXMError: Error, Sendable {
    case credentialsRejected, unsupportedAuthentication, accessNotEntitled
    case sessionExpired, upstreamChanged, rateLimited, transport(TransportFailure)
    case playbackAuthorizationFailed, malformedResponse
}
```

The signatures illustrate the rule, not a promise to lock v1 into an elaborate abstraction: begin with a `URLSession`-backed `HTTPTransport`, one `CredentialSource`, and a controllable `Clock`. Apple documents `URLSession` async request APIs; injecting it at this narrow edge makes protocol behavior deterministic under test without wrapping every Foundation type. [URLSession](https://developer.apple.com/documentation/foundation/urlsession) (HIGH confidence).

`CredentialSource` supplies credentials only to the authentication action; it should return a scoped value, not publish it through application state. The app composes it from `KeychainCredentialStore`. Apple describes Keychain Services as encrypted storage for small user secrets and recommends Keychain rather than application-managed encryption. Prefer `SecItem` rather than old `SecKeychain` APIs; macOS has several historical Keychain APIs and their backing behavior differs. [Keychain Services](https://developer.apple.com/documentation/security/keychain-services), [TN3137](https://developer.apple.com/documentation/technotes/tn3137-on-mac-keychains) (HIGH confidence).

### Session State Machine

```
signedOut
  └─ signIn with Keychain-provided credentials ─→ authenticating
authenticating ─ valid account + session ───────→ ready(session in memory)
authenticating ─ rejected/MFA/CAPTCHA/unknown ──→ needsUserAction (fail closed)
ready ─ resolve metadata/catalog/stream ────────→ ready
ready ─ recognized expiry ──────────────────────→ renewing (one serialized attempt)
renewing ─ success ─────────────────────────────→ ready
renewing ─ rejected/unknown/access-control ─────→ needsUserAction
any ─ user sign-out ────────────────────────────→ signedOut (clear Keychain and memory)
```

Only `SessionCoordinator` can transition the state and it coalesces concurrent requests. Retry transport failures with bounded, jittered backoff only for idempotent reads. A 401/403, unknown response shape, device-limit response, CAPTCHA/MFA indicator, or repeated renewal failure stops recovery and asks the user to complete the official experience; it never scrapes, proxies, persists a bypass, or pretends playback is available. Do not persist ephemeral stream URLs, cookies, authorization headers, or playlist/key URLs.

## Data Flow

### Login, Browse, and Playback

```
Login view → AppController → KeychainCredentialStore → CredentialSource
    → SiriusXMKit.SessionCoordinator → AuthWireAdapter → SiriusXM (TLS)
    ← typed AccountSession / typed failure ←───────────────────────────

Library window → AppController → `channels()` / `nowPlaying()` → library
    ← [LiveChannel], ProgramMetadata → LocalLibraryStore joins favorites/recents
    → immutable `LibraryViewState` → SwiftUI

Select channel → PlaybackCoordinator → `resolveLiveStream(channel)`
    ← ResolvedLiveStream (memory only)
    → AVPlayer.replaceCurrentItem(AVPlayerItem) → speakers
    → MediaSession publishes title/artwork/rate → macOS media keys / Now Playing
```

AVFoundation owns the HLS bytes once given a valid ephemeral stream locator. Apple states `AVPlayer` plays remote media and HLS, and HLS itself handles live delivery, bitrate adaptation, media encryption, and user authentication. Keep any request-normalization or playlist authorization issue inside stream resolution; do not reimplement an HLS client, download segments, or add an audio proxy. [AVPlayer](https://developer.apple.com/documentation/avfoundation/avplayer), [HTTP Live Streaming](https://developer.apple.com/documentation/http-live-streaming) (HIGH confidence).

On playback failure, `PlaybackCoordinator` classifies AVFoundation observations into user-facing states (`connecting`, `playing`, `buffering`, `reconnecting`, `paused`, `failed`) and asks the library for one fresh resolution at most per recovery window. The library owns whether a session renewal is legitimate; the player owns only its `AVPlayer` lifecycle. This keeps an upstream repair from becoming an audio-engine rewrite.

### App State and Windows

One `@MainActor` `AppController` is the composition root for app-wide state: account session status, selected/current channel, compact-player status, library load state, selected skin, and non-secret error presentation. It observes service streams and exposes small immutable feature states to views. Views issue intents; they never mutate models or call `URLSession`.

Use SwiftUI for both primary scenes. The compact window is a single `Window` so there is one player surface; the library is a `WindowGroup` for normal macOS browsing and restoration behavior. Keep a small AppKit adapter limited to capabilities SwiftUI cannot expose cleanly (for example, exact nonstandard window chrome/drag regions or minimum-size behavior); pass a `WindowPresentation` value in and events out. No `NSWindow` reference belongs in `SiriusXMKit` or in persistent app state. Apple’s scene/window documentation confirms a single `Window` and a multi-instance `WindowGroup` are distinct native constructs. [Scenes](https://developer.apple.com/documentation/swiftui/scenes), [Windows](https://developer.apple.com/documentation/swiftui/windows) (HIGH confidence).

For system transport surfaces, `MediaSession` maps semantic play/pause/toggle commands into `PlaybackCoordinator` intents and publishes a metadata snapshot after every relevant player or program update. `MPNowPlayingSession` contains both a Now Playing info center and a remote command center; use it rather than inventing a global-media-key event tap. [MPNowPlayingSession](https://developer.apple.com/documentation/mediaplayer/mpnowplayingsession) (HIGH confidence).

## Compatibility Fixtures and Contracts

Treat fixtures as a first-class compatibility warning system, not a record/replay implementation.

| Contract | Fixture contents | Assertion | Rotation rule |
|---|---|---|---|
| Authentication shape | sanitized request/response *shape*, status classification, no usernames/cookies/tokens | known success/rejection/unsupported state maps to typed state | refresh manually after a verified upstream change; redact before commit |
| Configuration/catalog | minimal JSON containing fields the decoder requires plus unknown extra fields | decode needed channel/metadata fields; tolerate additions; fail safely on required-field loss | record schema version and source date |
| Stream resolution | sanitized semantic response and synthetic HLS URLs/playlists, never live URL/query/key | outputs a locator or typed `sessionExpired`/`upstreamChanged`; no leaks in diagnostics | use synthetic expiry and authorization failures |
| Session recovery | scripted transport sequence: ready → expiry → renewal success/failure | one serialized renewal, bounded retry, no request storm | test with injected `Clock` |
| Public API | compile-time client of released public symbols plus DocC examples | app can update wire adapters without changing client source | semantic-version public changes only |
| Skin package | valid, missing, oversized, path-traversal, unknown-field and disallowed-asset examples | validator accepts only declared resources and returns actionable error | fuzz manifest decoder and archive extraction |

Store fixtures under source control only after a scrubber rejects credentials, cookies, authorization headers, account IDs, HLS token query values, absolute endpoint paths if sensitive, and user metadata. Provide a developer-only recorder that writes outside the repository, requires explicit confirmation, and runs the scrubber before a human can promote a fixture. Do not run live SiriusXM contract tests in public CI; use a local opt-in smoke test with user-owned credentials, whose logs are redacted and never uploaded.

## Skins and Package Validation

A skin is a directory or archive with a versioned `skin.json` manifest and image/font assets. The manifest can specify named color, spacing, typography, bitmap, and layout-slot values only. It cannot name Swift types, JavaScript, shell commands, arbitrary URLs, dynamic libraries, a code signature bypass, or a resource path outside its root.

`SkinValidator` performs: bounded archive extraction into an app-controlled temporary directory; canonical-path containment; maximum compressed/uncompressed size and file count; allow-listed extensions/MIME types; schema/version validation; resource existence and dimensions; then atomic move to the app support skins directory. `SkinRenderer` consumes the validated value model and exposes fixed player layout slots; it does not interpret arbitrary view trees. Bundle default skins as SwiftPM/Xcode resources and validate those with the same validator in CI. This preserves nostalgic variation without a plugin architecture or a hardened-runtime exception.

## Diagnostics and Privacy

Emit structured event names and numeric classifications such as `auth.transition`, `catalog.decodeFailed`, `stream.resolveFailed`, `player.stalled`, and `skin.rejected`. Mark every dynamic string/private identifier—username, account data, cookie, token, URL query, response body, device fingerprint, and metadata that could identify the listener—as private before it reaches OSLog; use a per-process hash only when correlation is necessary. Apple’s `OSLogPrivacy` documentation explicitly provides private/sensitive redaction and masking options. [OSLogPrivacy](https://developer.apple.com/documentation/os/oslogprivacy), [Generating Log Messages](https://developer.apple.com/documentation/os/generating-log-messages-from-your-code) (HIGH confidence).

The user-visible diagnostic export is a separate generated report: app version/build, macOS version, capability flags, failure classifications, timestamps rounded as appropriate, and redacted correlation IDs. It must never be a raw log archive or network trace. Make redaction a value type at the boundary, not a convention in callers.

## Distribution Architecture

The release pipeline builds an archive, runs unit/UI/skin fixture tests, validates bundled skins, checks no test credentials/resources are present, signs every nested code item with Developer ID and Hardened Runtime, notarizes, staples, and runs `spctl` assessment on the shipped artifact. Publish the notarized DMG or ZIP with checksums and release notes to GitHub Releases; the Homebrew Cask refers to that immutable release artifact and checksum. Apple requires hardened runtime for notarization and documents Developer ID signing, notarization tickets, and stapling for direct macOS distribution. [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution), [Preparing your app for distribution](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution) (HIGH confidence).

Use App Sandbox only after its networking and storage behavior is validated against the live service. It is mandatory for the Mac App Store but optional for Developer-ID-notarized distribution; v1’s canonical GitHub/Homebrew route must not claim sandbox compatibility without a tested entitlement set. Keep hardened-runtime exceptions at zero: declarative skins eliminate the most likely reason to weaken library validation or executable-memory protections.

## Build Order

1. **Foundation and contracts:** create `SiriusXMKit` public models/errors, transport/clock/diagnostics injection points, fixture scrubber, and deterministic decoder/session tests. This is the repair seam.
2. **Fail-closed sign-in and catalog:** implement Keychain-backed app credential store, session state machine, catalog/metadata adapter, typed UI errors, and a manual local smoke-test harness. Verify no secrets reach test artifacts or OSLog.
3. **Live playback and system integration:** add stream resolver, `PlaybackCoordinator`, AVPlayer observation/recovery, and MediaPlayer commands/Now Playing. Test stream expiry with fakes before connecting it to the compact player.
4. **Native UI and local library:** ship compact `Window`, library `WindowGroup`, favorites/recents, state restoration, and accessibility. Use AppKit only for a measured windowing gap.
5. **Safe skins as v1 behavior:** deliver schema/validator, bundled skins, user import flow, renderer, and hostile-package test corpus—before polishing skin authoring.
6. **Release hardening:** archive/sign/notarize/staple/assessment CI, GitHub Release workflow, Homebrew Cask, diagnostic export audit, and an opt-in live compatibility verification run.

This ordering produces a usable library and safe end-to-end listening path before investing in presentation. It also prevents the player UI from becoming the place where an upstream SiriusXM change must be repaired.

## Anti-Patterns

### Letting UI or AVPlayer Know SiriusXM Protocol Details

**What people do:** put login cookies, request construction, playlist parsing, or retry code in view models or an `AVAssetResourceLoader`.

**Why it is wrong:** every upstream change touches the UI/audio path, secrets spread across app objects, and tests require a live account.

**Do this instead:** expose typed operations from `SiriusXMKit`; keep all protocol code internal to narrowly scoped adapters and test it against sanitized fixtures.

### Building a Local HLS Proxy or Segment Downloader

**What people do:** proxy HLS locally to work around auth/playlist behavior or to make it easier to inspect/record bytes.

**Why it is wrong:** it expands secret exposure, bypass risk, distribution/security complexity, and conflicts with the live-only/no-downloading scope. Apple already provides HLS-capable playback through AVFoundation.

**Do this instead:** resolve an authorized ephemeral live locator in the library and hand it directly to AVPlayer. If AVFoundation cannot consume a future supported stream form without a noncompliant workaround, fail clearly and investigate the upstream adapter.

### General-Purpose Protocol/Plugin/Design-System Frameworks

**What people do:** create a generic media-provider hierarchy, reactive architecture framework, executable skin plugins, or cross-platform networking layer before a second consumer exists.

**Why it is wrong:** it obscures the actual volatile boundary and pressures hardened-runtime/security exceptions.

**Do this instead:** use simple Swift protocols only at collaboration/testing seams (`HTTPTransport`, `CredentialSource`, `Clock`, `DiagnosticsSink`) and a declared skin manifest. Add an abstraction only after a concrete second adapter or platform consumer forces it.

### Logging for Debuggability Without a Privacy Boundary

**What people do:** print URL requests/responses or `Error` descriptions wholesale during reverse engineering.

**Why it is wrong:** tokens, cookies, account information, and signed playlist URLs leak into Console, crash reports, CI, or Git history.

**Do this instead:** log only semantic events and explicitly private values; make the diagnostic export generated from a redacted event model.

## Scaling Considerations

| Scale | Architecture adjustment |
|---|---|
| 0–1k users / v1 | One app process, one `AVPlayer`, local persistence, sanitized fixture suite, release CI. The bottleneck is upstream compatibility, not server scale. |
| 1k–100k users | Expand fixture corpus and compatibility telemetry only with opt-in, redacted reports; automate fixture decoder regression checks and Homebrew release verification. Do not introduce a central proxy/service, which would violate the direct-request privacy boundary. |
| 100k+ users | Keep protocol updates as independent `SiriusXMKit` releases with clear compatibility notes, add staged rollout/revocation guidance, and consider a separate status site containing no user data. The player stays a local native app. |

## Sources

- [Apple: SwiftUI windows](https://developer.apple.com/documentation/swiftui/windows) — HIGH confidence, crawled 2026-08-16
- [Apple: AVPlayer](https://developer.apple.com/documentation/avfoundation/avplayer) and [HTTP Live Streaming](https://developer.apple.com/documentation/http-live-streaming) — HIGH confidence, crawled 2026-08-16
- [Apple: Keychain Services](https://developer.apple.com/documentation/security/keychain-services) and [TN3137: On Mac keychains](https://developer.apple.com/documentation/technotes/tn3137-on-mac-keychains) — HIGH confidence, crawled 2026-08-16
- [Apple: OSLogPrivacy](https://developer.apple.com/documentation/os/oslogprivacy) — HIGH confidence, crawled 2026-08-16
- [Apple: Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) — HIGH confidence, crawled 2026-08-16
- [sxm-client public interoperability source](https://sxm-client.readthedocs.io/en/stable/_modules/sxm/client.html) — MEDIUM confidence; unsupported client, inspected 2026-08-16; evidence of volatility, not an API contract

---
*Architecture research for: Sirius Mac*
*Researched: 2026-08-16*
