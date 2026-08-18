# Walking Skeleton — Sirius Mac

**Phase:** 1
**Generated:** 2026-08-16

## Capability Proven End-to-End

A subscriber can launch a native macOS application, invoke its authentication entry action, and receive an explicit fail-closed compatibility outcome supplied through the reusable `SiriusXMClient` boundary without a live account request.

## Architectural Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Framework | Swift 6.3, SwiftUI app target, and a local SwiftPM `SiriusXMClient` library product | This is a genuine native macOS stack and preserves the reusable library as an independently consumable artifact. |
| Data layer | No database; app-owned Security.framework Keychain CRUD is the sole Phase 1 persistence integration | Phase 1 has no ordinary application data model. Credentials require Keychain storage, while session material remains memory-only. |
| Authentication | One user-operated nonpersistent WKWebView extracts exactly one current first-party `AUTH_TOKEN`; the client then performs native authentication and entitlement requests | This is the settled architecture, with no selector, fallback, shared-browser access, Phase 0 gate, or access-control workaround. |
| Deployment target | Local native macOS build/run only in Phase 1 | No server or deployment service belongs in this native foundation. Public packaging and distribution are Phase 5 work. |
| Directory layout | `Packages/SiriusXMClient/` for the reusable library, `SiriusMac/` for app composition/UI/security, and separate package/app tests | Volatile SiriusXM behavior remains behind internal adapters while the app owns platform presentation and Keychain access. |

## Stack Touched in Phase 1

- [ ] Project scaffold — Xcode macOS app target, local SwiftPM library, Swift Testing/XCTest targets, strict Swift concurrency, and shared scheme.
- [ ] Native scene — one SwiftUI authentication/compatibility scene hosts the nonpersistent WKWebView and consumes typed client state.
- [ ] Secure persistence — no database is introduced; Keychain add/read/update/delete is exercised through the app-owned adapter.
- [ ] UI interaction — explicit Sign In/Retry drives the single WebView-token/native-request path without automatic requests or fallback.
- [ ] Local build/run — after full Xcode is installed and selected: `xcodebuild -project SiriusMac.xcodeproj -scheme SiriusMac -configuration Debug -derivedDataPath .build/xcode build`, then `open .build/xcode/Build/Products/Debug/SiriusMac.app`.

## Out of Scope (Deferred to Later Slices)

- Entitled catalog, channel metadata, stream resolution, audio playback, recovery, and Now Playing behavior.
- Favorites, recents, library window, compact player chrome, and media-key behavior.
- Declarative skin manifests, bundled/user skins, and skin recovery.
- Support-bundle export, signing, notarization, GitHub Releases, Homebrew Cask, and update notices.
- Xtra, on-demand, replay, recording, download, offline playback, browser-state extraction, or any access-control workaround.

## Subsequent Slice Plan

Each later phase adds a vertical slice on top of this skeleton without crossing the established client/app/security boundaries:

- Phase 2: entitled linear catalog, metadata, stream resolution, and reliable live playback.
- Phase 3: compact and library windows, local favorites/recents, and macOS media integration.
- Phase 4: bounded declarative skins with accessibility and native recovery.
- Phase 5: compatibility support, signed/notarized release artifacts, and Homebrew distribution.

## Artifacts this phase produces

The phase creates the Xcode app scaffold, the `SiriusXMClient` SwiftPM product, semantic authentication/session models, the internal session actor and compatibility adapters, ephemeral direct-host transport, allow-listed diagnostics, the app-owned `KeychainCredentialStore`, native authentication/unsupported presentation, deterministic package/app tests, and the manual selection/viability summaries. Public symbols are limited to `SiriusXMClient`, semantic authentication/entitlement/sign-out values, safe capability/error values, and narrow credential/diagnostic collaborator protocols. Internal symbols contain `SessionCoordinator`, adapter result/wire types, direct-host policy, ephemeral transport, redactor/logger implementations, Keychain query details, and app presentation state.
