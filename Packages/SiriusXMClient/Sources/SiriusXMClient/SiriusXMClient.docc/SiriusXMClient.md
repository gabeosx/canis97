# ``SiriusXMClient``

An Apple-platform client that exposes SiriusXM authentication, entitlement, catalog, metadata, and live-listening results as semantic Swift values.

## Overview

`SiriusXMClient` contains the reverse-engineered integration behind Canis97. Its public boundary deliberately exposes semantic domain models and closed outcomes instead of provider endpoints, request headers, response envelopes, or resolved stream URLs. Apps receive bounded display models while credential and media material stay inside the client.

The package targets macOS 26 or later and uses Swift concurrency. Create one client for an application session, keep it behind an app-owned coordinator, and treat every upstream operation as independently fallible.

## Integration rules

- Pass credentials only through ``AuthenticationCredential``. Never log, encode, persist, or render credential material.
- Use ``AuthenticationOutcome`` and ``EntitlementAvailability`` as separate gates. Successful authentication does not imply an active subscription.
- Treat ``CatalogAvailability`` snapshots as browse-only data. A catalog item does not authorize playback.
- Resolve live media for each tune and retain the resulting handoff only in memory.
- Handle closed compatibility failures without guessing provider behavior or bypassing CAPTCHA, MFA, DRM, subscription checks, or device limits.
- Keep fixtures synthetic and redacted. Never commit an authenticated response, subscriber data, device identifier, media key, or raw provider structure.

## Versioning

The package follows Semantic Versioning and currently shares Canis97's repository tag:

- A patch release repairs an existing supported adapter or fixes behavior without changing the public semantic API, documented behavior, or persisted semantic data.
- A minor release adds backward-compatible public capability.
- A major release is required when the public semantic API, documented behavior, or persisted semantic data becomes incompatible.

Public releases use immutable `vMAJOR.MINOR.PATCH` Git tags. Unsupported upstream protocol changes can require a patch release even when SiriusXM changed and the package API did not.

## Compatibility maintenance

Use the package as a semantic SwiftPM product from an Apple-platform app; keep app UI, playback ownership, and provider mechanics outside its public interface. Repair upstream drift only in `InternalAdapters`, then prove the result with a synthetic structural fixture and an existing typed outcome. The fixture-promotion gate rejects raw/provider-sensitive structures before they enter a repository or Git history.

For the repair sequence and isolated verification command, see <doc:CompatibilityRepair>.

## Topics

### Authentication and entitlement

- ``AuthenticationCredential``
- ``AuthenticationOutcome``
- ``EntitlementAvailability``
- ``SignOutOutcome``

### Listening

- ``CatalogAvailability``
- ``LiveCatalogSnapshot``
- ``LiveChannel``
- ``LivePlaybackState``
- ``LiveListeningFailure``
- ``MetadataAvailability``

### Bulk live metadata

- <doc:BulkLiveMetadata>
- ``SiriusXMClient/liveNow(for:)``
- ``LiveNowSnapshot``
- ``LiveNowChannel``
- ``LiveNowChannelState``
- ``LiveNowProgram``
- ``LiveNowContentKind``
- ``LiveNowAvailability``
- ``LiveNowFailure``
- ``LiveNowMonitor``
- ``LiveNowFreshness``

### Maintenance

- <doc:CompatibilityRepair>
