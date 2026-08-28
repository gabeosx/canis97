# Repairing an Upstream Compatibility Change

Restore one known semantic contract without widening the integration or capturing subscriber material.

## Identify the failing stage

Start with Canis97's Compatibility & Support window. It classifies authentication, entitlement, catalog, stream resolution, metadata, and native playback independently. Reproduce only the first unavailable stage; do not issue speculative requests to later stages.

Use the existing closed diagnostic labels and local test failures. Do not ask users for passwords, cookies, tokens, stream URLs, authenticated response bodies, or raw support logs.

## Capture a safe fixture

Prefer a hand-written fixture containing only the smallest structural fields needed by the adapter. If an authorized live observation is necessary, perform exactly one owner-approved operation and transform it before it enters the repository:

1. Remove headers, cookies, authorization values, URLs, account identifiers, device identifiers, request identifiers, timestamps tied to an account, and media keys.
2. Replace provider IDs and display text with obvious synthetic values.
3. Keep only the fields required to reproduce parsing or classification.
4. Run the fixture redaction tests and inspect the diff manually.

Never commit a raw capture and then attempt to redact it in a later commit; Git history is durable.

## Repair the narrow adapter

Change the internal adapter for the failing stage. Preserve the public semantic result unless the intended user-facing capability genuinely changed. Unknown shapes must fail closed as an existing unavailable or unsupported classification.

Add a regression test using the sanitized fixture. Include the previous supported shape when practical so a repair does not silently drop compatibility.

## Verify

Run the package suite in an isolated scratch directory:

```sh
swift test \
  --package-path Packages/SiriusXMClient \
  --scratch-path "$(mktemp -d /tmp/canis97-client-tests.XXXXXX)"
```

Then compile the app and app-unit bundle without launching UI automation. A live compatibility check is a separate, serialized, owner-approved step; it is never part of normal CI.

Review the final diff for provider material before publishing a patch release.
