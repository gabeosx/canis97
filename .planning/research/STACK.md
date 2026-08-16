# Stack Research

**Domain:** Public, native macOS live-radio player plus reusable Apple-platform SiriusXM client library
**Researched:** 2026-08-16
**Confidence:** MEDIUM — platform and distribution choices are backed by current primary documentation; the SiriusXM protocol is intentionally unverified and volatile.

## Recommendation in One Sentence

Build a current-macOS app with **Xcode 26.6 / Swift 6.3 / macOS 26**, using SwiftUI with small, deliberate AppKit seams, AVFoundation and MediaPlayer for all playback integration, Security.framework Keychain Services for secrets, SwiftData for app-local library state, and a separately versioned SwiftPM `SiriusXMClient` source package that contains protocol behavior but no UI or media code.

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why recommended |
|---|---:|---|---|
| Xcode + Swift | **Xcode 26.6, Swift 6.3** | Build, test, sign, archive, and distribute app and package | Current Xcode 26.6 ships Swift 6.3 and the macOS 26.5 SDK. Use current toolchains and enable Swift 6 language mode plus complete concurrency checking; the client has network/session state that benefits directly from actor isolation. |
| Deployment target | **macOS 26.0+** | Product baseline | The project explicitly targets current macOS only. Set `MACOSX_DEPLOYMENT_TARGET = 26.0`; test on the current 26.5 SDK. This removes legacy availability branches and allows current SwiftUI/Observation/window APIs. |
| SwiftUI + narrow AppKit interop | OS-bundled | App scene lifecycle, library window, settings, state-driven UI; AppKit for compact player window/panel behavior and exact window control | SwiftUI owns product UI. Use `NSWindow`/`NSPanel` only through focused representables/controllers for chrome, always-on-top/mini-player behavior, frame persistence, and menu-bar/window actions that SwiftUI does not expose cleanly. This remains a genuine Mac app rather than a web shell. |
| Foundation | OS-bundled | `URLSession`, `URLRequest`, `Codable`, `URLComponents`, file coordination, async streams | Apple-maintained transport and serialization APIs are enough for a JSON/HLS-like remote service. Keep all SiriusXM request construction, response decoding, error mapping, and retry decisions behind the client package; do not add Alamofire. |
| AVFoundation | OS-bundled | Live stream playback with `AVPlayer` / `AVPlayerItem` and player status observation | `AVPlayer` supports remote media and HTTP Live Streaming and is the macOS-native transport controller. One player is appropriate for one live channel; replacement of the current item is the controlled channel-switch mechanism. |
| MediaPlayer | OS-bundled | Now Playing data and Mac media-key/Control Center commands | Drive `MPNowPlayingInfoCenter` from the playback coordinator and register only supported `MPRemoteCommandCenter` commands (play/pause/stop and, if product semantics allow it, next/previous favorite). Set macOS `playbackState` whenever player state changes. |
| Security.framework Keychain Services | OS-bundled | Encrypted storage of password/session/refresh tokens | Use direct `SecItemAdd`, `SecItemCopyMatching`, `SecItemUpdate`, and `SecItemDelete`, wrapped once in a small app-owned `KeychainCredentialStore`. This has the best platform fit and avoids a security-critical dependency whose maintenance is not required for a four-operation wrapper. |
| SwiftData | OS-bundled | App-local favorites, recents, selected skin, and small UI preferences | It is sufficient for a single-user current-macOS library state. Model only local player data; **never** put credentials, access tokens, raw upstream responses, or stream URLs in SwiftData. No CloudKit sync in v1. |
| Swift Package Manager | Swift 6.3 / Xcode 26.6 | Build and publish reusable client as source package | SwiftPM natively supports library products, internal targets, test targets, platform declarations, DocC, and semantic-version Git tags. It keeps the reusable artifact independently consumable without forcing a separate repository or binary framework too early. |

### Package and Module Boundary — the libghostty-like decision

Adopt a **monorepo with a first-class, source-distributed SwiftPM package**, not an internal framework target and not a platform-neutral rewrite:

```text
SiriusMac.xcodeproj                     # macOS app; presentation and platform ownership
Packages/SiriusXMClient/                # independently testable + versioned SwiftPM package
  Sources/SiriusXMClient/               # sole public product: typed API, models, errors
  Sources/SiriusXMClientProtocol/       # internal endpoint/auth/catalog/stream adapters
  Tests/SiriusXMClientTests/             # fixtures, contract + compatibility tests
  Tests/SiriusXMClientIntegrationTests/  # opt-in, secret-free smoke probes
```

Publish one product initially:

```swift
.library(name: "SiriusXMClient", targets: ["SiriusXMClient"])
```

`SiriusXMClient` exposes typed async operations (`authenticate`, `channels`, `nowPlaying`, `resolveLiveStream`, `invalidateSession`) and a stable, documented error taxonomy. Its public initializer receives narrow collaborators such as `URLSessionProtocol`, `Clock`, and `SessionStore`; production values use `URLSession`, `ContinuousClock`, and the app's Keychain store. The concrete endpoint/schema/authentication adapters remain internal implementation details.

This is the useful part of the libghostty analogy: an independently versioned, documented, testable library protects the app from integration churn and lets other Apple-native clients reuse it. Do **not** make it cross-platform for its own sake, introduce a C ABI, ship a binary XCFramework, or split every endpoint into a package. The supported consumer set is native Apple-platform Swift apps, and source SwiftPM delivery preserves auditability and fast repairs when upstream changes.

The app retains ownership of all `SwiftUI`, `AppKit`, `AVFoundation`, `MediaPlayer`, `SwiftData`, and concrete Keychain integration. The package must never import them. That prevents a SiriusXM compatibility patch from changing window behavior or media-key handling.

### Supporting Libraries

| Library | Version | Purpose | When to use |
|---|---:|---|---|
| [swift-dependencies](https://github.com/pointfreeco/swift-dependencies) | **1.10.0** | Controlled live, preview, and test dependencies | Use **inside the app target only** for the playback coordinator, persistence facade, and feature models where deterministic previews/tests are valuable. Do not expose `DependencyKey` or library types in `SiriusXMClient`’s public API; its API uses ordinary protocols and initializer injection. |
| Swift Testing | Swift 6.3 / OS toolchain | Unit, parameterized, async and failure-path tests | Default for package and app logic. Test the client with recorded, redacted fixtures and fake clock/session/network collaborators. Use XCTest only where Apple tooling still requires it, notably UI tests. |
| XCTest / XCUITest | Xcode 26.6 | End-to-end app and window/media-control smoke tests | Use for launch, login UI, library browsing, compact-player windows, and manual/external-system integration boundaries; do not force a third-party UI test framework. |
| `OSLog.Logger` | OS-bundled | Structured local diagnostics | Use a dedicated subsystem/category per app and client layer. Mark all values private by default; log error class, status family, endpoint name, and opaque request IDs — never passwords, cookies, authorization headers, session IDs, resolved stream URLs, or response bodies. |
| `Codable` + `JSONDecoder` | OS-bundled | Skin manifest decoding | Use a versioned JSON manifest with strict enum/value decoding, a fixed asset allowlist, file-size/dimension caps, and no executable code. A hand-sized validator is safer than a generic plug-in or scripting runtime. |

There is deliberately **no** third-party Keychain wrapper, HTTP client, media engine, database, logging facade, web runtime, or auto-updater in v1. System APIs meet all of those needs with a smaller supply chain. `swift-dependencies` is the one justified convenience package because it makes the many volatile/external collaborators controllable in previews and tests without contaminating the public SDK.

### Development and Release Tools

| Tool | Purpose | Notes |
|---|---|---|
| `swift test` + `xcodebuild test` | Package and app verification | Run strict-concurrency warnings as errors in CI. Keep live upstream compatibility probes separate, opt-in, rate-limited, and credential-free in normal PR CI. |
| DocC | SDK reference and protocol-repair documentation | Generate docs for the public package product; document supported Apple platforms, semver policy, error behavior, and the fact that SiriusXM interoperability can change without notice. |
| GitHub Actions + GitHub Releases | CI and canonical binary releases | Use protected semver tags (`vMAJOR.MINOR.PATCH`), build from that tag, attach notarized artifacts plus checksums/SBOM, and create the GitHub Release from the same immutable commit. Pin third-party Actions to full commit SHAs, not floating tags. |
| `codesign`, `notarytool`, `stapler`, `spctl` | Direct-distribution signing/notarization verification | Archive with Developer ID Application identity, hardened runtime, secure timestamp, notarize via `notarytool`, staple the ticket, and verify in a clean VM/runner before publishing. Keep Apple credentials in protected release-environment secrets; never package them into artifacts. |
| Homebrew Cask in a project-owned tap | `brew install --cask` path | Ship a signed/notarized `.zip` containing `Sirius Mac.app` (and optionally a DMG for direct downloads). Automation updates a cask with the GitHub Release URL, exact `sha256`, `version`, and `app` stanza. Start with an owned tap; submit to `homebrew/cask` only after naming, policy, and maintenance expectations are satisfied. |

## Installation / Project Shape

Use Xcode for the application plus a local SwiftPM package dependency. The package stays source-open and independently buildable:

```swift
// Packages/SiriusXMClient/Package.swift
// swift-tools-version: 6.3
import PackageDescription

let package = Package(
  name: "SiriusXMClient",
  platforms: [.macOS(.v26), .iOS(.v26), .tvOS(.v26)],
  products: [.library(name: "SiriusXMClient", targets: ["SiriusXMClient"])],
  targets: [
    .target(name: "SiriusXMClient", dependencies: ["SiriusXMClientProtocol"]),
    .target(name: "SiriusXMClientProtocol"),
    .testTarget(name: "SiriusXMClientTests", dependencies: ["SiriusXMClient"])
  ]
)
```

Add the one non-system dependency only to the app target (not to `SiriusXMClient`):

```swift
.package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.10.0")
```

Build-time policy:

```text
SWIFT_VERSION = 6.0                 # Swift 6 language mode
MACOSX_DEPLOYMENT_TARGET = 26.0
SWIFT_STRICT_CONCURRENCY = complete
SWIFT_TREAT_WARNINGS_AS_ERRORS = YES  # CI at minimum
```

`SiriusXMClient` should tag releases independently using SemVer. Before `1.0`, communicate that a minor release may break its public API; after `1.0`, endpoint breakage is repaired behind the stable surface whenever possible. The **app** may depend on a local package path in the monorepo during development but releases must record the package version/commit they contain.

## Alternatives Considered

| Recommended | Alternative | When to use the alternative |
|---|---|---|
| SwiftUI with contained AppKit bridges | AppKit-first UI | Use AppKit-first only if the compact player needs pervasive custom drawing, responder-chain behavior, and window manipulation that would make most SwiftUI views awkward. That is not established yet; keep SwiftUI as the default. |
| AVFoundation `AVPlayer` | VLC/libmpv/FFmpeg engine | Use only after a reproducible, authorized stream format cannot play through AVFoundation. A second media engine increases signing, update, codec, and security burden, so it is a research gate — not a speculative dependency. |
| Direct Keychain Services wrapper | KeychainAccess / Valet | Use a wrapper only if a concrete Apple-platform sharing/access-control requirement proves the small in-house adapter insufficient. Direct `SecItem` calls are auditable and preserve precise error behavior; maintenance evidence for KeychainAccess is weaker than for the platform API. |
| SwiftData | GRDB/SQLite | Choose GRDB only if required queries, migrations, or corruption recovery exceed the small favorites/recents/settings model. Do not add a database framework preemptively. |
| Plain protocol + initializer injection in SDK; `swift-dependencies` private to app | Public TCA/Dependencies-based SDK | Never expose a state-management or DI framework through this reusable client; it would constrain all downstream apps. TCA may be considered later for a complex app feature graph, not as a v1 requirement. |
| Source SwiftPM library product | XCFramework / dynamic framework / separate service | Use an XCFramework only if compile time or binary distribution becomes a measured problem. Use a separate repository only when independent contributor/release cadence creates real friction. Neither improves API volatility containment today. |
| GitHub Release + own Cask tap | Sparkle auto-update | Consider Sparkle after v1 only if in-app background update UX becomes a supported product feature. GitHub Releases plus Homebrew already satisfy distribution without an updater security surface. |

## What NOT to Use

| Avoid | Why | Use instead |
|---|---|---|
| Electron, Tauri, WKWebView, or an embedded SiriusXM site | Violates native-product intent; weakens media/window integration and couples UI directly to an unsupported website flow. | SwiftUI/AppKit plus the isolated Swift client. |
| Direct calls to SiriusXM from views or playback classes | Every upstream change would leak into UI, diagnostics, and playback recovery, making safe repair slow. | `SiriusXMClient` public API and internal compatibility adapters. |
| Persisting secrets in `UserDefaults`, SwiftData, files, logs, crash reports, or skin manifests | These are not a Keychain substitute and turn routine debugging/state persistence into credential exposure. | `Security` Keychain Services via a minimal credential-store wrapper. |
| Web cookies, `HTTPCookieStorage.shared`, or a globally shared `URLSession` as the session model | Cookie/session behavior becomes invisible and hard to clear, test, redact, or fail closed. | Client-owned ephemeral `URLSessionConfiguration`, explicit header/session handling, scoped actor state, and explicit logout/delete. |
| Any CAPTCHA/MFA/DRM/device-limit workaround | Out of scope and unsafe; it risks account security and service-policy violations. | Detect the response, redact it, surface an actionable unsupported-auth error, and stop. |
| JavaScript/Lua skin scripts, arbitrary HTML/CSS, dynamic plug-ins, or imported Winamp skins | They expand the executable attack surface and make a public desktop player difficult to review and notarize. | Versioned JSON skin manifest + verified local image assets only. |
| Alamofire, KeychainAccess, Realm, CocoaPods, Carthage, or a custom HTTP/media stack by default | Each duplicates a platform capability or adds a supply-chain/build burden before a real gap exists. | URLSession, Security, SwiftData, SwiftPM, AVFoundation, and system logging. |
| `swift-log` as the default macOS logger | It is a good cross-platform logging API, but needs a backend and adds abstraction where `OSLog.Logger` is native, privacy-aware, and enough. | `OSLog.Logger`; reconsider only if the client later supports non-Apple processes. |

## Stack Patterns by Variant

**If SiriusXM serves an AVFoundation-supported HLS/file-based stream:**

- Use `AVPlayer` with an `AVPlayerItem`, observing item/player status and stall/failure notifications in a single `@MainActor` playback coordinator.
- Treat the resolved URL as short-lived secret-adjacent data: hold it in memory only, never log/persist it, and resolve again through the client for recovery.

**If the upstream playback response changes or fails validation:**

- Use a versioned internal protocol adapter and record/replay redacted fixtures to reproduce the change.
- Fail closed with a typed compatibility error; do not guess headers, browser behavior, DRM handling, or access-control workarounds.

**If a consuming Apple-platform app needs different credential policy:**

- Provide a `SessionStore` implementation at the app boundary while retaining the same `SiriusXMClient` public API.
- Do not add a universal credentials plug-in system; Apple Keychain Services are the supported default and application signing/access-group decisions belong to the consumer.

**If skins need more visual expressiveness:**

- Extend the JSON schema with bounded, declarative properties (metrics, colors, image references, text styles, state-specific assets) and migrate by manifest version.
- Do not introduce executable behavior or a general-purpose layout language; rendering remains native SwiftUI/AppKit code.

## Version Compatibility

| Package / platform | Compatible with | Notes |
|---|---|---|
| Xcode 26.6 | Swift 6.3, macOS 26.5 SDK | Current primary-source verified toolchain. Pin CI to this release; review Xcode release notes before bumping. |
| App target macOS 26.0+ | SwiftUI, AppKit, AVFoundation, MediaPlayer, Security, SwiftData | Current-OS-only stance allows direct use of current APIs and no fallback shims. |
| `SiriusXMClient` SwiftPM package | Apple platform apps on declared macOS/iOS/tvOS 26+ | Keep Foundation-only at the public/core boundary. It should not require UI, playback, or app-state frameworks. |
| `swift-dependencies` 1.10.0 | App target, Swift 6.3 | Use as an implementation detail. Keep its version out of the SDK’s public types so client consumers do not inherit the dependency. |
| GitHub Release Cask artifact | Homebrew Cask | Cask must match release `version`, immutable asset URL, and exact SHA-256; test both fresh `brew install --cask` and direct Gatekeeper launch. |

## Sources

- [Xcode 26.6 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-26_6-release-notes?language=objc) — Swift 6.3 and macOS 26.5 SDK pairing. **MEDIUM** (official primary source; current release details).
- [Swift 6.3 release announcement](https://www.swift.org/blog/swift-6.3-released/) — SwiftPM, Swift Testing, and language/toolchain capabilities. **MEDIUM** (official primary source).
- [Swift Package Manager documentation](https://github.com/swiftlang/swift-package-manager/blob/main/Sources/PackageManagerDocs/Documentation.docc/ReleasingPublishingAPackage.md) — library products, test targets, Swift tools version, SemVer tag publication. **MEDIUM** (official source via Context7).
- [AVPlayer](https://developer.apple.com/documentation/avfoundation/avplayer) and [Media playback](https://developer.apple.com/documentation/avfoundation/media-playback) — AVFoundation playback model and HLS/file-based media. **MEDIUM** (official primary source).
- [MPNowPlayingInfoCenter](https://developer.apple.com/documentation/mediaplayer/mpnowplayinginfocenter) and [MPRemoteCommandCenter](https://developer.apple.com/documentation/mediaplayer/mpremotecommandcenter) — Now Playing metadata, macOS playback state, and remote commands. **MEDIUM** (official primary source).
- [Keychain Services](https://developer.apple.com/documentation/security/keychain-services) and [Adding a password to the keychain](https://developer.apple.com/documentation/security/adding-a-password-to-the-keychain) — encrypted small-secret storage and `SecItem` use. **MEDIUM** (official primary source).
- [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) and [Creating distribution-signed code for macOS](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac) — Developer ID, hardened runtime, timestamp, notarization, and stapling requirements. **MEDIUM** (official primary sources).
- [GitHub Releases documentation](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases) and [Homebrew Cask Cookbook](https://docs.brew.sh/Cask-Cookbook) — tag-backed releases and Cask artifact requirements. **MEDIUM** (official primary sources).
- [swift-dependencies repository](https://github.com/pointfreeco/swift-dependencies) and [1.10.0 release](https://github.com/pointfreeco/swift-dependencies/releases) — injectable live/preview/test collaborators and verified version. **MEDIUM** (upstream source).

## Open Verification Items

- Validate the actual authorized SiriusXM stream format against AVFoundation before declaring any fallback media engine; never infer DRM/stream behavior from the web client.
- Confirm the public package's minimum Apple platforms after the first non-macOS consumer exists; macOS is v1's only required runtime.
- Perform a real signed/notarized test release before committing to the exact artifact extension/name and Cask automation.
- Review App Sandbox versus direct-distribution entitlements during release engineering. Hardened Runtime is mandatory for notarization; App Sandbox is optional for direct distribution and must not accidentally block the required Keychain/network behavior.

---
*Stack research for: Sirius Mac*
*Researched: 2026-08-16*
