# Sirius Mac

## What This Is

Sirius Mac is a public, open-source, native macOS SiriusXM player for subscribers who want a dependable desktop listening experience instead of a website-shaped application. It combines reliable live-channel playback and proper macOS integration with a compact, quirky, nostalgic, skinnable interface inspired by the spirit of Winamp.

The application is built on a first-class reusable SiriusXM client library, similar in architectural intent to the relationship between libghostty and Ghostty. The library isolates reverse-engineered authentication, catalog, metadata, and stream behavior so SiriusXM protocol changes can be repaired without destabilizing the player.

## Core Value

Subscribers can reliably start and control a live SiriusXM stream from a delightful native Mac player, even as the unsupported SiriusXM integration evolves underneath it.

## Requirements

### Validated

- [x] A subscriber can authenticate against SiriusXM through a strict, fail-closed flow without credentials or session tokens leaving the Mac except in direct requests to SiriusXM. — Validated in Phase 1: Safe Interoperability Foundation.
- [x] Secrets are stored through macOS Keychain-backed credential storage and never exposed in application diagnostics. — Validated in Phase 1: Safe Interoperability Foundation.

### Active

- [ ] A subscriber can browse the live channel lineup and see available channel artwork and current-program metadata.
- [ ] A subscriber can start a live channel stream and the player handles recoverable network, playback, session, and upstream API failures clearly.
- [ ] A subscriber can save favorite channels and return to recently played channels.
- [ ] Playback integrates correctly with background audio, macOS media keys, and system Now Playing surfaces.
- [ ] The app provides a compact skinnable player window plus a larger native library window for browsing, metadata, favorites, and recents.
- [ ] The app ships with multiple bundled skins and can load user-created local skin packages through a safe declarative format with no executable skin code.
- [ ] The SiriusXM integration is delivered as a documented, versioned, independently testable, reusable library consumed by the app.
- [ ] SiriusXM authentication, catalog, metadata, stream resolution, compatibility behavior, and redacted diagnostics are isolated behind replaceable integration boundaries.
- [ ] Public releases are signed, notarized, published through GitHub Releases, and installable through a Homebrew Cask.

### Out of Scope

- On-demand shows, episodes, and replayable programs — v1 is focused on dependable live-channel listening.
- SiriusXM-wide search — channel browsing, favorites, and recents are sufficient for the initial live-listening workflow.
- Cross-platform support — the app and reusable library may optimize for current Apple platforms, with no Windows, Linux, or web mandate.
- Classic Winamp skin import compatibility — v1 defines its own safe declarative skin format.
- CAPTCHA, MFA, device-limit, anti-bot, DRM, or other access-control bypasses — unsupported upstream behavior must fail safely rather than weaken account security.
- Recording or offline downloading of SiriusXM streams — not required for the live-player value proposition and introduces unnecessary legal and technical risk.

## Context

- The official SiriusXM experience feels non-native, requires too much interface for routine listening, and lacks the personality of classic desktop media players.
- SiriusXM will not authorize this application. Authentication and media APIs must therefore be discovered through interoperability-focused reverse engineering and assumed to change without notice.
- The project will be publicly available on GitHub for SiriusXM subscribers rather than kept as a personal or private tool.
- The library is a core product artifact, not merely an internal folder. Its exact package boundary should be informed by research, but it must be independently testable, documented, versioned, and reusable by other native Apple-platform software.
- The app should own macOS presentation and platform integration. The library should own SiriusXM protocol knowledge and accept injected collaborators where doing so materially improves isolation, testing, or safe secret handling.
- Non-core capabilities should follow an adopt-before-build mentality. Mature libraries and platform facilities should be preferred when they meet the requirements without compromising the core experience.
- The first usable release must deliver reliable listening, correct desktop integration, and the nostalgic skinnable experience together; none is merely post-v1 polish.

## Constraints

- **Platform**: Target the current macOS release only — freely use current SwiftUI, AppKit, media, security, and window-management APIs without legacy fallbacks.
- **Implementation**: The player must be a genuine native macOS application, not a wrapper around the SiriusXM website.
- **Upstream stability**: Treat all reverse-engineered SiriusXM endpoints, schemas, authentication flows, and playback details as volatile — contain them behind repairable adapters and compatibility-focused tests.
- **Authentication safety**: Credentials and session tokens remain on the user's Mac except for direct SiriusXM requests; secrets use Keychain-backed storage, diagnostics are redacted, and unknown auth behavior fails closed.
- **Access controls**: Do not bypass CAPTCHA, MFA, subscription or device limits, anti-bot controls, DRM, or other service protections.
- **Skin safety**: User-created skins are declarative data and assets only; they cannot execute code.
- **Distribution**: Public binaries must be signed and notarized, with GitHub Releases as the canonical release channel and a Homebrew Cask as an installation path.
- **Portability**: Optimize the reusable library for native Apple-platform consumers; cross-platform abstractions are unnecessary.
- **Dependency strategy**: Adopt well-maintained third-party or system solutions for non-core functionality before building custom replacements.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Build a native macOS application rather than a web wrapper | Native media, security, windowing, and desktop behavior are central to the product | — Pending |
| Make reliable playback, macOS integration, and nostalgic skinning all part of v1 | The project's value comes from the combination, not any one feature in isolation | — Pending |
| Publish for general subscriber use on GitHub | The project is intended as a public tool and reusable reference implementation | — Pending |
| Enforce strict, fail-closed authentication boundaries | An unsanctioned public client must not compromise subscriber credentials or bypass service protections | ✓ Validated — Phase 1 |
| Scope v1 content to live channels, favorites, recents, and channel metadata | Establish the core listening workflow before adding on-demand content or search | — Pending |
| Use a compact player plus a larger library window | Preserves the always-available classic-player feel while giving discovery a native desktop workspace | — Pending |
| Support bundled and declarative user-created skins | Skinning is a core product capability while executable extensions would create avoidable risk | — Pending |
| Deliver the SiriusXM layer as a first-class reusable library | Protocol volatility and public reuse both require separation from application UI | — Pending |
| Avoid a cross-platform mandate | The project can prioritize excellent current-macOS and Apple-platform architecture | — Pending |
| Distribute signed and notarized releases through GitHub and Homebrew | Public users should be able to install normally without bypassing Gatekeeper | — Pending |
| Use the live-tested `/subscription/v1/subscriptions` contract behind an internal adapter | The earlier gateway response assumption drifted; the current endpoint and `items[].state` classifier completed native authentication and entitlement in a controlled live UAT | ✓ Validated — Phase 1 |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `$gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `$gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-08-18 after Phase 1 completion*
