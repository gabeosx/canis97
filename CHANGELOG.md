# Changelog

Notable user-facing changes are recorded here. This project follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and stable
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.1] - 2026-09-05

### Fixed

- Update notices use a separate native window so their buttons and keyboard controls work independently of the borderless, always-on-top player.
- Download Update opens the matching disk image in the browser and provides clear replacement instructions, with separate Homebrew guidance. Missing or unexpected download links lead to the installation page.

## [0.2.0] - 2026-09-05

### Added

- Five bundled animated appearances: Orbit Deck, Signal Garden, Exit97, Quartz Deck + Quartz Link, and Abyssal 97 — Living Ocean.
- Safe declarative sprite scenes, articulated pose atlases, and deterministic encounters with quiet intervals and repeat cooldowns.
- Separate song-heart and channel-star reactions with persistent keepsakes, static Reduce Motion fallbacks, and visibility-aware suspension.

### Improved

- Exit97 uses registered cockpit gestures and articulated skywhale journeys, with stable painted lighting and continuous roadside travel cues.
- Abyssal 97 brings an extended repertoire of swimming, drifting, and exploring ocean visitors.
- Canis97.com previews Exit97 using the native scene repertoire, with pause and reduced-motion support.

## [0.1.4] - 2026-09-01

### Fixed

- Restored channel icons in the library by encoding SiriusXM browse image keys through the fixed, bounded image service contract.

## [0.1.3] - 2026-09-01

### Changed

- Existing 0.1.2 sessions require one fresh SiriusXM sign-in after upgrading because the previous release did not save the long-lived session cookie. Canis97 0.1.3 saves and rotates it for subsequent automatic restores.

### Fixed

- Restored automatic sign-in by renewing expired SiriusXM sessions through the current long-lived session credential and persisting each rotated replacement in Keychain.
- Loaded the complete paginated SiriusXM channel catalog instead of silently presenting only the first subset of channels.
- Expanded the support report with redacted credential-load, renewal-attempt, native-authentication, and partial-lineup diagnostics so authentication and catalog failures are actionable.

## [0.1.2] - 2026-08-31

### Changed

- Direct downloads and Homebrew now use the signed, notarized, and stapled branded DMG with its drag-to-Applications layout.

### Fixed

- Release validation now runs Apple's application-bundle distribution check against Canis97.app instead of passing it the outer DMG.

## [0.1.1] - 2026-08-31

No public artifacts were published for this version.

## [0.1.0] - 2026-08-29

### Added

- Native SiriusXM sign-in with Keychain-backed session restoration.
- Live channel catalog browsing, search, favorites, recents, and Favorite Songs.
- Native playback with media keys, Control Center, live metadata, and artwork.
- A compact always-on-top player with six bundled appearances, including the generated Vintage Cassette Deck, and safe local skin imports.
- Native selection of system, Bluetooth, USB, HDMI, and AirPlay audio outputs from the compact player and Player menu.
- An installable `canis97-skin-creator` agent skill with standalone validation and packaging helpers.
- Accessibility labels, keyboard navigation, reduced-motion behavior, and global player commands.
- A privacy-preserving GitHub Releases update checker with manual and daily checks.
- A compatibility status window and reviewed, allowlisted support-bundle export.
- GitHub Actions validation, signed/notarized release automation, checksums, and an SPDX SBOM.
- Homebrew Cask generation and optional tap publishing.

[Unreleased]: https://github.com/gabeosx/canis97/compare/v0.2.1...HEAD
[0.2.1]: https://github.com/gabeosx/canis97/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/gabeosx/canis97/releases/tag/v0.2.0
[0.1.4]: https://github.com/gabeosx/canis97/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/gabeosx/canis97/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/gabeosx/canis97/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/gabeosx/canis97/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/gabeosx/canis97/releases/tag/v0.1.0
