# Repairing an Upstream Compatibility Change

Restore one known semantic contract without widening the integration or capturing subscriber material.

## Identify the failing stage

Start with Canis97's Compatibility & Support window. It reports the current session in this fixed order: authentication, entitlement, catalog, stream resolution, metadata, and native playback. It distinguishes a stage that is unavailable from one that has not run. Opening it is a read-only projection: do not issue speculative requests, create another session, or create another playback owner.

Use the existing closed diagnostic labels and local test failures. Do not ask users for passwords, cookies, tokens, stream URLs, authenticated response bodies, or raw support logs.

## Capture a safe fixture

Prefer a hand-written fixture containing only the smallest structural fields needed by the adapter. If an authorized live observation is necessary, perform exactly one owner-approved operation and transform it before it enters the repository:

1. Remove endpoints, headers, cookies, authorization values, URLs, account identifiers, device identifiers, request identifiers, timestamps tied to an account, raw response envelopes, and media keys.
2. Replace provider IDs and display text with obvious synthetic values.
3. Keep only the fields required to reproduce parsing or classification.
4. Run the fixture redaction tests before writing the fixture and inspect the diff manually.

Never commit a raw capture and then attempt to redact it in a later commit; Git history is durable.

## Repair the narrow adapter

Change only the internal adapter for the failing stage. Preserve the public semantic result unless the intended user-facing capability genuinely changed. Unknown shapes must fail closed as an existing unavailable or unsupported classification; do not make provider endpoints, headers, cookies, or wire types part of the public API.

Add a regression test using the sanitized fixture. Include the previous supported shape when practical so a repair does not silently drop compatibility.

## Playlist-selected playback keys

Treat the tuning response's encryption-key identity as a prefetch hint, not a
promise that every audio segment uses that key. The HLS playlist determines
which key applies to each segment and may change it during playback
([RFC 8216, sections 4.3.2.4 and 8.3](https://www.rfc-editor.org/rfc/rfc8216.html#section-4.3.2.4)).
Pinning the resource loader to the prefetched identity can leave a different
playlist key to AVFoundation's unauthenticated HTTP handling, producing an
authentication error even when session verification and tuning both succeeded.

The adapter authorizes playlist-selected keys only through its fixed HTTPS
provider key endpoint, under the session generation that performed the tune.
It serializes misses, coalesces duplicate requests, bounds the in-memory cache,
and rejects late bytes after cancellation or session replacement. Unknown key
paths and content types fail closed. Preserve the precise network, entitlement,
protection, or authentication failure through AVFoundation rather than reporting
every key failure as a decoder or sign-in problem.

Run `PlaylistPlaybackKeyTests` and `LivePlaybackCoordinatorTests` when changing
this path. Cover a playlist key different from the prefetch, subsequent key
changes, duplicate and concurrent requests, cache eviction, denied requests,
cancellation, session replacement, sixteen-byte key validation, and partial
reads. AVFoundation can request content information without requesting bytes;
that request must also be completed by the loader.

During an authorized muted native check, confirm `playlist-selected playback
key authorized`, `item-ready`, and `playing-confirmed`. These fixed labels are
sufficient evidence; never record the key identities, key bytes, or media URLs.

## Verify

Run the package suite in an isolated scratch directory:

```sh
swift test \
  --package-path Packages/SiriusXMClient \
  --scratch-path "$(mktemp -d /tmp/canis97-client-tests.XXXXXX)"
```

Then compile the app and app-unit bundle without launching UI automation. A live compatibility check is a separate, serialized, owner-approved step; it is never part of normal CI.

Review the final diff for provider material before publishing a patch release. The support handoff should include only the six ordered area/classification pairs and the reviewed product, version, build, operating-system, and architecture fields; it must not become a log dump.
