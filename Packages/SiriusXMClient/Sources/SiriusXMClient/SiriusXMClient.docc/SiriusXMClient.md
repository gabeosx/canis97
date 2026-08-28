# ``SiriusXMClient``

An Apple-platform client that exposes SiriusXM authentication, entitlement, catalog, metadata, and live-listening results as semantic Swift values.

## Overview

`SiriusXMClient` contains the reverse-engineered integration behind Canis97. Its public boundary deliberately excludes HTTP requests, cookies, authorization headers, provider response bodies, and resolved stream URLs. Apps receive closed outcomes and bounded display models while credential and media material stay inside the client.

The package targets macOS 26 or later and uses Swift concurrency. Create one client for an application session, keep it behind an app-owned coordinator, and treat every upstream operation as independently fallible.

## Integration rules

- Pass credentials only through ``AuthenticationCredential``. Never log, encode, persist, or render credential material.
- Use ``AuthenticationOutcome`` and ``EntitlementAvailability`` as separate gates. Successful authentication does not imply an active subscription.
- Treat ``CatalogAvailability`` snapshots as browse-only data. A catalog item does not authorize playback.
- Resolve live media for each tune and retain the resulting handoff only in memory.
- Handle closed compatibility failures without guessing provider behavior or bypassing CAPTCHA, MFA, DRM, subscription checks, or device limits.
- Keep fixtures synthetic and redacted. Never commit an authenticated response or subscriber data.

## Versioning

The package follows Semantic Versioning and currently shares Canis97's repository tag:

- Patch releases repair an existing supported protocol or fix behavior without changing the public contract.
- Minor releases add backward-compatible public capability.
- Major releases may remove or incompatibly change public API or persisted semantic data.

Public releases use immutable `vMAJOR.MINOR.PATCH` Git tags. Unsupported upstream protocol changes can require a patch release even when SiriusXM changed and the package API did not.

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

### Maintenance

- <doc:CompatibilityRepair>
