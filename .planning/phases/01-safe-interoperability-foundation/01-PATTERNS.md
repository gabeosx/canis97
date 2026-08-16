# Phase 1: Safe Interoperability Foundation - Pattern Map

**Mapped:** 2026-08-16  
**Files analyzed:** 14 planned files / file groups  
**Analogs found:** 0 / 14

> This is a greenfield repository. The source scan found only planning artifacts; there are no `*.swift` files, `Package.swift`, Xcode project, existing tests, or application target to copy. Consequently, no source-code analogs or line-numbered project excerpts exist. Every convention below is explicitly planning-derived from `01-CONTEXT.md`, `01-RESEARCH.md`, and the cited project requirements—not an established implementation pattern.

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `Packages/SiriusXMClient/Package.swift` | config | batch | — | no analog |
| `Packages/SiriusXMClient/Sources/SiriusXMClient/Public/SiriusXMClient.swift` | service | request-response | — | no analog |
| `Packages/SiriusXMClient/Sources/SiriusXMClient/Public/AuthenticationOutcome.swift` | model | transform | — | no analog |
| `Packages/SiriusXMClient/Sources/SiriusXMClient/Session/SessionCoordinator.swift` | service | event-driven | — | no analog |
| `Packages/SiriusXMClient/Sources/SiriusXMClient/Transport/SessionTransport.swift` | service | request-response | — | no analog |
| `Packages/SiriusXMClient/Sources/SiriusXMClient/Transport/EphemeralURLSessionTransport.swift` | service | request-response | — | no analog |
| `Packages/SiriusXMClient/Sources/SiriusXMClient/InternalAdapters/AuthenticationFlowAdapter.swift` | service | transform | — | no analog |
| `Packages/SiriusXMClient/Sources/SiriusXMClient/Diagnostics/SafeDiagnosticEvent.swift` | model | event-driven | — | no analog |
| `Packages/SiriusXMClient/Sources/SiriusXMClient/Diagnostics/DiagnosticRedactor.swift` | utility | transform | — | no analog |
| `Packages/SiriusXMClient/Tests/SiriusXMClientTests/SessionCoordinatorTests.swift` | test | event-driven | — | no analog |
| `Packages/SiriusXMClient/Tests/FixtureTests/RedactionTests.swift` | test | transform | — | no analog |
| `Packages/SiriusXMClient/Tests/PublicAPITests/PublicConsumerTests.swift` | test | request-response | — | no analog |
| `SiriusMac/Security/KeychainCredentialStore.swift` | service | CRUD | — | no analog |
| `SiriusMac/Authentication/UnsupportedAuthenticationView.swift` and presentation model | component / provider | event-driven | — | no analog |

### Scope notes

- File paths other than `Package.swift` and `SiriusMac/Security/KeychainCredentialStore.swift` are recommended organizational names inferred from the research structure. The planner may refine names, but must retain the stated public/library, internal-adapter, app-security, and test boundaries.
- The “presentation model” may be a separate `@Observable` type or live with the SwiftUI view. It must consume typed client state only; it must not choose, retry, or inspect an authentication protocol.
- No catalog, playback, skins, or normal player shell files belong in this phase.

## Pattern Assignments

### `Packages/SiriusXMClient/Package.swift` (config, batch)

**Analog:** None — create the first SwiftPM package manifest.

**Planning-derived convention:** Declare the independently consumable `SiriusXMClient` library product and isolated source/test targets. Keep the SDK’s public surface Foundation-oriented and do not add third-party dependencies for Phase 1.

**Source:** `01-RESEARCH.md` “Recommended Project Structure” (lines 171-194) and “Standard Stack” (lines 102-120).

### `.../Public/SiriusXMClient.swift` (service, request-response)

**Analog:** None — create the stable semantic façade.

**Planning-derived convention:** Export typed async authentication/session operations, capabilities, outcomes, and safe errors. Do not expose `URLRequest`, `HTTPURLResponse`, URL/endpoint values, header maps, cookie containers, raw JSON, response bytes, or adapter decoder types.

**Source:** `01-RESEARCH.md` “Pattern 1” (lines 196-207); requirements `CLNT-01`–`CLNT-04`.

### `.../Public/AuthenticationOutcome.swift` (model, transform)

**Analog:** None — create domain-only result models.

**Planning-derived convention:** Model explicit semantic outcomes needed by `AUTH-01`: authenticated-and-entitled success, rejection, challenge/control-protection, unsupported flow, and safe entitlement state. Unknown/malformed protocol data must map to unsupported rather than a generic successful response or raw transport error.

**Source:** `01-CONTEXT.md` “Single authentication path” and “Required viability proof” (lines 17-46); `01-RESEARCH.md` “Pattern 2” (lines 208-220).

### `.../Session/SessionCoordinator.swift` (service, event-driven)

**Analog:** None — create the actor-owned state machine.

**Planning-derived convention:** A single actor owns active attempt and memory-only session state. It rejects a second attempt locally, makes no automatic retry/fallback, clears transient data on stop conditions, and performs explicit sign-out cleanup. Challenge, CAPTCHA/interstitial, 403, 429, redirect drift, suspected bot detection, ambiguity, and unknown shapes are terminal unsupported outcomes.

**Source:** `01-RESEARCH.md` “Pattern 2” (lines 208-220) and “Authentication Feasibility Decision Procedure” (lines 253-272).

### `.../Transport/SessionTransport.swift` and `.../Transport/EphemeralURLSessionTransport.swift` (service, request-response)

**Analog:** None — create injected transport seam and internal live implementation.

**Planning-derived convention:** Keep the protocol injectable for scripted tests and make the production implementation internal, client-owned, and `URLSessionConfiguration.ephemeral`. Permit direct requests only to evidence-verified SiriusXM host(s); do not hard-code speculative endpoint/host details before the manual feasibility work proves them.

**Research reference pattern** (`01-RESEARCH.md`, lines 343-350; not project code):

```swift
let configuration = URLSessionConfiguration.ephemeral
let session = URLSession(configuration: configuration)
```

### `.../InternalAdapters/AuthenticationFlowAdapter.swift` (service, transform)

**Analog:** None — create the replaceable volatile-protocol boundary.

**Planning-derived convention:** Confine paths, headers/cookies, body schemas, redirect parsing, raw decoding, and strict known-shape classification to `internal` adapter code. Return semantic adapter results only; malformed or changed upstream output is unsupported. Never emulate a browser, harvest browser state, spoof app identity, or bypass service controls.

**Source:** `01-RESEARCH.md` “Pattern 1” (lines 196-207) and anti-patterns (lines 245-250).

### `.../Diagnostics/SafeDiagnosticEvent.swift` and `.../Diagnostics/DiagnosticRedactor.swift` (model/utility, event-driven/transform)

**Analog:** None — create diagnostic safety at the type boundary.

**Planning-derived convention:** Accept only allow-listed operation/capability classifications, safe outcome classes, and non-identifying correlation handles. Do not let raw responses, URLs, cookies, headers, credentials, tokens, or arbitrary `Error` descriptions enter the event API. Fixtures and support evidence use separate structural redaction with synthetic data.

**Research reference pattern** (`01-RESEARCH.md`, lines 353-360; not project code):

```swift
Logger().info("Authentication outcome: \(outcome, privacy: .private)")
```

The interpolated value must already be a safe semantic classification.

### `.../Tests/SiriusXMClientTests/SessionCoordinatorTests.swift` (test, event-driven)

**Analog:** None — create deterministic actor-state tests.

**Planning-derived convention:** Use Swift Testing with scripted injected transport, clock, credential source, and diagnostic sink. Test success/rejection/challenge/unsupported/entitlement mappings, a locally rejected concurrent attempt, and zero transport retry after every stop condition. Serialize only the suite that intentionally shares session orchestration state.

**Research reference pattern** (`01-RESEARCH.md`, lines 362-374; not project code):

```swift
import Testing

@Suite(.serialized) struct SessionCoordinatorTests {
    @Test func concurrentAttemptsProduceOneLiveAttempt() async throws {
        // Assert against a scripted injected transport.
    }
}
```

### `.../Tests/FixtureTests/RedactionTests.swift` (test, transform)

**Analog:** None — create canary-based safety tests.

**Planning-derived convention:** Use synthetic fixtures only. Place credential/token/tokenized-URL canaries in test input and assert they cannot occur in diagnostic events, fixture output, failure descriptions, or exported evidence. Decoder/adapter tests remain package-internal; public tests must not name adapter types.

**Source:** requirements `SECR-03`, `CLNT-03`; `01-RESEARCH.md` “Validation Architecture” (lines 444-469).

### `.../Tests/PublicAPITests/PublicConsumerTests.swift` (test, request-response)

**Analog:** None — create independent-consumer compile/use coverage.

**Planning-derived convention:** Import only the `SiriusXMClient` product and exercise the public typed async API. The target must demonstrate that a consumer neither needs nor can depend on volatile adapter/transport wire types.

**Source:** requirements `CLNT-01`–`CLNT-03`; `01-RESEARCH.md` “Validation Architecture” (lines 454-456).

### `SiriusMac/Security/KeychainCredentialStore.swift` (service, CRUD)

**Analog:** None — create the app-owned Keychain boundary.

**Planning-derived convention:** Implement narrowly with Security.framework `SecItemAdd`, `SecItemCopyMatching`, `SecItemUpdate`, and `SecItemDelete`. Persist only a validated reusable credential after selected-path success when required; never persist credentials in library code, preferences, SwiftData, files, fixtures, or diagnostic output. Sign-out must clear memory first, then delete the Keychain item and surface deletion failure safely.

**Research reference pattern** (`01-RESEARCH.md`, lines 221-237; not project code):

```swift
let status = SecItemAdd(query as CFDictionary, nil)
guard status == errSecSuccess else {
    throw KeychainError.unhandledError(status: status)
}
```

### `SiriusMac/Authentication/UnsupportedAuthenticationView.swift` and presentation model (component/provider, event-driven)

**Analog:** None — create the first application presentation boundary.

**Planning-derived convention:** Show a dedicated compatibility state—not a partially authenticated player shell—when the selected path is unavailable. State that authentication is unsupported, no credentials were retained, and no workaround was attempted. Provide explicit user Retry, official SiriusXM-site navigation, and only safe redacted diagnostics. Retry must be an explicit user action and never choose an alternate path or trigger an automatic retry.

**Source:** `01-CONTEXT.md` “Unsupported-authentication experience” (lines 27-33) and “Single authentication path” (lines 17-25).

## Shared Patterns

### Public library boundary

**Apply to:** Every `Packages/SiriusXMClient/Sources/SiriusXMClient/Public/` file.

- Public types are semantic/domain-oriented and support typed async operations.
- Internal adapters contain all upstream wire details and must not leak through public signatures.
- Collaborator injection is limited to transport, clock, credential source, and diagnostics seams required for app ownership and deterministic tests.

### Fail-closed authentication

**Apply to:** Session actor, adapter, transport, UI presentation model, and tests.

- Exactly one evidence-selected authentication path may ship; no selector and no browser/native fallback.
- At most one attempt can be in flight; do not send a second attempt, automatically retry, or rapidly probe.
- On a control-protection or ambiguous signal, stop, clear transient material, return unsupported, and retain no credentials.

### Secret handling and session isolation

**Apply to:** App Keychain store, client transport, state machine, fixtures, diagnostics, and tests.

- Keychain writes are post-success app effects only; client package takes a scoped injected credential source.
- Session material is memory-only; network uses a client-owned ephemeral URL session for direct SiriusXM requests only.
- Never log or persist credentials, authorization material, session IDs, cookies, raw response bodies, or token-bearing URLs.

### Diagnostics and fixtures

**Apply to:** Every error/failure path and every test fixture.

- Use static, allow-listed event classes and privacy-qualified OSLog values.
- Redact structurally before data reaches a log, test failure, fixture, compatibility report, or support export.
- Use synthetic, redacted fixture data; manual two-run viability evidence is not routine CI and must contain no account/session data.

### Verification boundary

**Apply to:** Phase plan acceptance criteria.

- Automated Swift Testing covers semantic outcomes, one-attempt behavior, sign-out, ephemeral session configuration, redaction canaries, and public-consumer compilation.
- The two authorized smoke tests are human-initiated, separately run, manual-only, and a hard gate for Phases 2–5. They are not scripts, scheduled jobs, or credential-bearing test artifacts.

## No Analog Found

All planned implementation files have no codebase analog because the repository is greenfield. The planner must use the planning-derived conventions above and must not cite any existing source file as precedent.

## Metadata

**Analog search scope:** repository root excluding `.git`; searched Swift package/app conventions and all tracked files  
**Files scanned:** 26 planning/instruction artifacts; 0 source files  
**Pattern extraction date:** 2026-08-16
