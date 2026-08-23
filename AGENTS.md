<!-- GSD:project-start source:PROJECT.md -->

## Project

**Sirius Mac**

Sirius Mac is a public, open-source, native macOS SiriusXM player for subscribers who want a dependable desktop listening experience instead of a website-shaped application. It combines reliable live-channel playback and proper macOS integration with a compact, quirky, nostalgic, skinnable interface inspired by the spirit of Winamp.

The application is built on a first-class reusable SiriusXM client library, similar in architectural intent to the relationship between libghostty and Ghostty. The library isolates reverse-engineered authentication, catalog, metadata, and stream behavior so SiriusXM protocol changes can be repaired without destabilizing the player.

**Core Value:** Subscribers can reliably start and control a live SiriusXM stream from a delightful native Mac player, even as the unsupported SiriusXM integration evolves underneath it.

### Constraints

- **Platform**: Target the current macOS release only — freely use current SwiftUI, AppKit, media, security, and window-management APIs without legacy fallbacks.
- **Implementation**: The player must be a genuine native macOS application, not a wrapper around the SiriusXM website.
- **Upstream stability**: Treat all reverse-engineered SiriusXM endpoints, schemas, authentication flows, and playback details as volatile — contain them behind repairable adapters and compatibility-focused tests.
- **Authentication safety**: Credentials and session tokens remain on the user's Mac except for direct SiriusXM requests; secrets use Keychain-backed storage, diagnostics are redacted, and unknown auth behavior fails closed.
- **Access controls**: Do not bypass CAPTCHA, MFA, subscription or device limits, anti-bot controls, DRM, or other service protections.
- **Skin safety**: User-created skins are declarative data and assets only; they cannot execute code.
- **Distribution**: Public binaries must be signed and notarized, with GitHub Releases as the canonical release channel and a Homebrew Cask as an installation path.
- **Portability**: Optimize the reusable library for native Apple-platform consumers; cross-platform abstractions are unnecessary.
- **Dependency strategy**: Adopt well-maintained third-party or system solutions for non-core functionality before building custom replacements.

<!-- GSD:project-end -->

<!-- GSD:stack-start source:research/STACK.md -->

## Technology Stack

## Recommendation in One Sentence

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

### Supporting Libraries

| Library | Version | Purpose | When to use |
|---|---:|---|---|
| [swift-dependencies](https://github.com/pointfreeco/swift-dependencies) | **1.10.0** | Controlled live, preview, and test dependencies | Use **inside the app target only** for the playback coordinator, persistence facade, and feature models where deterministic previews/tests are valuable. Do not expose `DependencyKey` or library types in `SiriusXMClient`’s public API; its API uses ordinary protocols and initializer injection. |
| Swift Testing | Swift 6.3 / OS toolchain | Unit, parameterized, async and failure-path tests | Default for package and app logic. Test the client with recorded, redacted fixtures and fake clock/session/network collaborators. Use XCTest only where Apple tooling still requires it, notably UI tests. |
| XCTest / XCUITest | Xcode 26.6 | End-to-end app and window/media-control smoke tests | Use for launch, login UI, library browsing, compact-player windows, and manual/external-system integration boundaries; do not force a third-party UI test framework. |
| `OSLog.Logger` | OS-bundled | Structured local diagnostics | Use a dedicated subsystem/category per app and client layer. Mark all values private by default; log error class, status family, endpoint name, and opaque request IDs — never passwords, cookies, authorization headers, session IDs, resolved stream URLs, or response bodies. |
| `Codable` + `JSONDecoder` | OS-bundled | Skin manifest decoding | Use a versioned JSON manifest with strict enum/value decoding, a fixed asset allowlist, file-size/dimension caps, and no executable code. A hand-sized validator is safer than a generic plug-in or scripting runtime. |

### Development and Release Tools

| Tool | Purpose | Notes |
|---|---|---|
| `swift test` + `xcodebuild test` | Package and app verification | Run strict-concurrency warnings as errors in CI. Keep live upstream compatibility probes separate, opt-in, rate-limited, and credential-free in normal PR CI. |
| DocC | SDK reference and protocol-repair documentation | Generate docs for the public package product; document supported Apple platforms, semver policy, error behavior, and the fact that SiriusXM interoperability can change without notice. |
| GitHub Actions + GitHub Releases | CI and canonical binary releases | Use protected semver tags (`vMAJOR.MINOR.PATCH`), build from that tag, attach notarized artifacts plus checksums/SBOM, and create the GitHub Release from the same immutable commit. Pin third-party Actions to full commit SHAs, not floating tags. |
| `codesign`, `notarytool`, `stapler`, `spctl` | Direct-distribution signing/notarization verification | Archive with Developer ID Application identity, hardened runtime, secure timestamp, notarize via `notarytool`, staple the ticket, and verify in a clean VM/runner before publishing. Keep Apple credentials in protected release-environment secrets; never package them into artifacts. |
| Homebrew Cask in a project-owned tap | `brew install --cask` path | Ship a signed/notarized `.zip` containing `Sirius Mac.app` (and optionally a DMG for direct downloads). Automation updates a cask with the GitHub Release URL, exact `sha256`, `version`, and `app` stanza. Start with an owned tap; submit to `homebrew/cask` only after naming, policy, and maintenance expectations are satisfied. |

## Installation / Project Shape

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

- Use `AVPlayer` with an `AVPlayerItem`, observing item/player status and stall/failure notifications in a single `@MainActor` playback coordinator.
- Treat the resolved URL as short-lived secret-adjacent data: hold it in memory only, never log/persist it, and resolve again through the client for recovery.
- Use a versioned internal protocol adapter and record/replay redacted fixtures to reproduce the change.
- Fail closed with a typed compatibility error; do not guess headers, browser behavior, DRM handling, or access-control workarounds.
- Provide a `SessionStore` implementation at the app boundary while retaining the same `SiriusXMClient` public API.
- Do not add a universal credentials plug-in system; Apple Keychain Services are the supported default and application signing/access-group decisions belong to the consumer.
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

<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->

## Conventions

Conventions not yet established. Will populate as patterns emerge during development.
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->

## Architecture

Architecture not yet mapped. Follow existing patterns found in the codebase.
<!-- GSD:architecture-end -->

<!-- GSD:skills-start source:skills/ -->

## Project Skills

No project skills found. Add skills to any of: `.claude/skills/`, `.agents/skills/`, `.cursor/skills/`, `.github/skills/`, or `.codex/skills/` with a `SKILL.md` index file.
<!-- GSD:skills-end -->

<!-- GSD:workflow-start source:Codex-first project policy -->

## Codex-First Development Workflow

Direct Codex/ChatGPT implementation is the default. GSD commands are optional and are never a prerequisite for editing this repository.

Before changing files:

- Read this file, inspect `git status` and the relevant diff, then read only the current roadmap goal and directly relevant source/tests.
- Do not preload the full `.planning/` corpus. Treat `PROJECT.md` and roadmap success criteria as binding; detailed plans are advisory.
- Preserve existing dirty work. Never reset, clean, restore, or revert changes that are not yours.

For normal feature and bug work:

1. State a compact implementation approach in chat.
2. Implement one coherent vertical slice.
3. Add or update focused tests alongside the implementation.
4. Run the narrowest safe validation first.
5. Commit code and tests together when commits are requested or are part of the active workflow.
6. Run full suites, one independent review, and human UAT once at the phase or release boundary.

Do not generate research, context, discussion-log, UI-specification, validation, review-fix, and per-task summary artifacts by default. Update `.planning/ROADMAP.md` and `.planning/STATE.md` once at a real phase transition. Keep any phase summary concise.

Use targeted security review for authentication, Keychain, provider adapters, skin import, support-bundle export, signing, notarization, and release work. GSD may be invoked only when the user explicitly requests it or when a bounded high-risk audit materially helps.

## Safe Parallel Development

Parallelize independent work, not shared state.

- Up to three read-only agents may inspect distinct subsystems concurrently. Give each one a bounded question and reuse its findings.
- At most two implementation workers may edit concurrently, with explicit non-overlapping file ownership. Workers must not stage, commit, or revert; one integrator owns Git and the combined diff.
- The integrator exclusively owns `project.pbxproj`, shared schemes, `SiriusMacApp.swift`, package manifests, this file, and `.planning` coordination files.
- Do not parallelize changes to the same public type, actor, persistence model, app composition root, playback/session coordinator, or authentication lifecycle.
- Finish and integrate a changed `SiriusXMClient` public interface before parallel app work consumes it.

Every concurrent compiler lane must use unique temporary paths. Never share DerivedData, SwiftPM scratch directories, module caches, result bundles, or logs.

- Allow at most one `xcodebuild` process at a time.
- One isolated `swift test` package lane may run beside one Xcode build-only lane.
- Pure offline script tests using `mktemp` and injected fake hooks may run concurrently.
- Serialize every `script/build_and_run.sh` invocation; its default build/cache/launcher paths and launch lock are shared.
- Stop parallel editing before final validation so tests run against one reviewed snapshot.

## Test and Live-Operation Safety

The shared `SiriusMac` scheme contains both `SiriusMacTests` and `SiriusMacUITests`. An unqualified `xcodebuild test -scheme SiriusMac` can therefore launch UI automation.

After the 2026-08-22 loginwindow incident:

- Do not run `xcodebuild test`, `test-without-building`, `xctest`, `XCUIApplication.launch()`, a UI-test runner, or the SiriusMac app/test host until the user separately authorizes a safety review and that review establishes a safe execution environment. Isolated `SiriusXMClient` SwiftPM tests remain allowed.
- `xcodebuild build-for-testing` is allowed because it compiles without launching tests or the app.
- After the block is lifted, app-unit runs must select `-only-testing:SiriusMacTests` and disable test parallelism. UI tests remain a separate, serialized, explicitly authorized lane.
- Never run `build_and_run.sh`, UI tests, app-hosted tests, or `live_compatibility_checkpoint.sh` concurrently.
- Never parallelize authentication, Keychain, provider compatibility, catalog, tune, playback, telemetry, or other live SiriusXM checks.
- Live activity requires explicit owner authorization, exactly one in-flight attempt, no automatic retry, and immediate stop on an unknown or unsafe state.

Do not use blind sleep/poll jobs, duplicate agents investigating the same question, speculative abstractions, or repeated full-suite runs after small edits.
<!-- GSD:workflow-end -->

<!-- GSD:profile-start -->

## Developer Profile

> Profile not yet configured. Run `/gsd-profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
