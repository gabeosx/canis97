# Phase 1: Safe Interoperability Foundation - Research

**Researched:** 2026-08-16  
**Domain:** Safe authorized-session interoperability, SwiftPM library boundary, Keychain-backed credential handling  
**Confidence:** MEDIUM

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

#### Single authentication path

- Authentication is selected by evidence, not by a predetermined UI preference.
- Investigate a clean first-party browser authentication return first. If it works safely and reliably, that is the sole shipped sign-in path.
- If browser authentication cannot provide a clean supported return, investigate a native direct-to-SiriusXM flow. If that works safely and reliably, that is the sole shipped sign-in path.
- Do not ship both paths, a method selector, or a fallback from one method to the other.
- Do not scrape browser cookies or storage, spoof a user agent, solve challenges, bypass access controls, or conceal the app's identity.
- If neither path works within these constraints, authentication is unsupported and the project does not proceed to later phases.
- **Reversibility:** Costly. The selected sign-in surface affects the public client contract, app shell, security model, and downstream architecture.

#### Unsupported-authentication experience

- Present a dedicated compatibility screen when safe authentication is unavailable.
- State clearly that authentication is unsupported.
- Explain that no credentials were retained and no workaround was attempted.
- Offer Retry, a link to the official SiriusXM site, and safe redacted diagnostics.
- Fail closed. Do not expose a partially authenticated app shell or imply playback should work.

#### Required viability proof

- Authentication is a hard continuation gate for Phases 2–5.
- Complete two separate, manually initiated authorized smoke-test runs using the one selected sign-in path.
- Each run must sign in, receive a confirmed authenticated and entitled response, and sign out cleanly.
- The proof is not an automated loop and is not part of routine CI.
- Permit only one attempt in flight. Do not automatically retry, probe concurrently, or repeat rapidly.
- Stop immediately on CAPTCHA, an interstitial challenge, HTTP 403 or 429, an explicit rate-limit signal, an unexpected redirect, or any suspected bot-detection response.
- Browser authentication must use the user's real browser. Native authentication must identify the app honestly.
- If either run fails or produces ambiguous evidence, document authentication as unsupported and halt work on Phases 2–5.
- **Reversibility:** Costly. Relaxing this gate later would invalidate the project's safety and viability assumptions.

### the agent's Discretion

- Exact internal protocol, type, and module names within the public-library boundary.
- Shape of the manual smoke-test harness and the non-secret evidence it records.
- Conservative timing and cooldown choices for manually initiated tests.
- Redacted diagnostic categories and wording, provided no credential, token, cookie, account, or sensitive request data is exposed.
- Unit and integration test organization, provided the manual two-run gate remains separate from routine CI.

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within Phase 1 scope.
</user_constraints>

## Project Constraints (from AGENTS.md)

- Target the current macOS release only; use current SwiftUI, AppKit, media, security, and window-management APIs without legacy fallbacks.
- Deliver a genuine native macOS application, not a website wrapper.
- Treat SiriusXM endpoints, schemas, authentication flows, and playback details as volatile; contain them behind repairable adapters and compatibility-focused tests.
- Keep credentials and session tokens on-device except for direct SiriusXM requests; use Keychain-backed storage, redact diagnostics, and fail closed on unknown authentication behavior.
- Do not bypass CAPTCHA, MFA, subscription or device limits, anti-bot controls, DRM, or other service protections.
- Prefer maintained third-party or system solutions for non-core functionality; the existing stack decision specifically selects Foundation, Security.framework, SwiftPM, Swift Testing, and OSLog rather than speculative third-party dependencies. [VERIFIED: AGENTS.md]
- Public-library portability is for native Apple-platform consumers; cross-platform abstraction is not a Phase 1 goal. [VERIFIED: AGENTS.md]
- This greenfield repository has no project-local skills or implementation patterns to preserve. [VERIFIED: `rg --files -g 'SKILL.md'`; `rg --files`]

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| AUTH-01 | “Subscriber can sign in directly against SiriusXM and receives explicit success, rejection, challenge, unsupported-flow, and entitlement outcomes.” [VERIFIED: .planning/REQUIREMENTS.md:12] | Typed semantic result/error surface, selected-path decision gate, manual smoke-test evidence. |
| AUTH-02 | “Authentication fails closed when SiriusXM returns an unknown or changed flow without attempting to bypass CAPTCHA, MFA, device, geographic, anti-bot, DRM, or subscription controls.” [VERIFIED: .planning/REQUIREMENTS.md:13] | Stop policy, allow-listed known outcomes, unsupported compatibility state, and no retry/alternate-path logic. |
| AUTH-03 | “Subscriber can sign out and the app clears active session material and its stored SiriusXM credentials.” [VERIFIED: .planning/REQUIREMENTS.md:14] | Idempotent sign-out that first discards in-memory session material and then deletes Keychain items. |
| SECR-01 | “Subscriber credentials are stored through a macOS Keychain-backed app adapter and are never persisted in preferences, SwiftData, fixtures, or other local application data.” [VERIFIED: .planning/REQUIREMENTS.md:18] | App-owned `SecItem` adapter; no library disk fallback; fixtures contain synthetic data only. |
| SECR-02 | “Session tokens and resolved stream resources remain ephemeral and leave the Mac only in direct requests to SiriusXM.” [VERIFIED: .planning/REQUIREMENTS.md:19] | Client-owned ephemeral `URLSession`, memory-only session object, direct host allow-list at the transport boundary. |
| SECR-03 | “Logs, fixtures, tests, crash context, compatibility reports, and support exports redact or exclude credentials, authorization material, token-bearing URLs, and raw sensitive responses by construction.” [VERIFIED: .planning/REQUIREMENTS.md:20] | Safe diagnostic event schema, `OSLog` private interpolation, fixture scrubber, and canary-secret tests. |
| CLNT-01 | “Other native Apple-platform software can consume a documented SwiftPM `SiriusXMClient` product independently of the Sirius Mac application.” [VERIFIED: .planning/REQUIREMENTS.md:24] | Standalone local SwiftPM library product and compile-only consumer test. |
| CLNT-02 | “Client consumers use typed async APIs, domain models, capabilities, and errors for authentication, entitlement, catalog, metadata, and live-stream resolution without depending on endpoints, cookies, headers, or raw wire schemas.” [VERIFIED: .planning/REQUIREMENTS.md:25] | Public semantic protocols/models only; unstable wire types remain internal. |
| CLNT-03 | “SiriusXM endpoint, schema, authentication, and stream-resolution details remain in internal replaceable adapters that do not leak into the library's public API.” [VERIFIED: .planning/REQUIREMENTS.md:26] | Internal adapter protocol and contract fixtures; public API compile test rejects accidental dependency leakage. |
| CLNT-04 | “The library accepts injected transport, clock, credential-source, and redacted-diagnostics collaborators where needed for deterministic testing and app-owned secret handling.” [VERIFIED: .planning/REQUIREMENTS.md:27] | Narrow injected collaborator protocols plus scripted transport and controllable clock test doubles. |

## Summary

Phase 1 should establish a library-first, fail-closed interoperability seam before making any claim that SiriusXM authentication is supportable. The reusable `SiriusXMClient` SwiftPM product owns semantic session orchestration and internal volatile adapters; the native app owns presentation, Keychain storage, and user-initiated manual verification. SwiftPM library and test targets are the standard package shape, while Apple Keychain Services provides encrypted storage for small secrets. [CITED: https://github.com/swiftlang/swift-package-manager/blob/main/Sources/PackageManagerDocs/Documentation.docc/GettingStarted.md] [CITED: https://developer.apple.com/documentation/security/keychain-services]

The phase has a deliberately asymmetric outcome. Deterministic code, fixtures, diagnostics, and fail-closed UI can be implemented without touching a subscriber account. The continuation gate cannot: it requires exactly one selected path to complete two separately initiated, human-authorized sign-in → authenticated-and-entitled → sign-out runs. The project’s locked stop conditions make this a human checkpoint, not a CI test or agent action. [VERIFIED: .planning/phases/01-safe-interoperability-foundation/01-CONTEXT.md]

SiriusXM’s public help currently describes multiple sign-in forms, including password, one-time verification code, and passkey-capable device sign-in. That confirms authentication behavior is not safely reducible to a fixed credential form. The consulted official sources do not provide an app registration, OAuth/OIDC authorization-server contract, or a documented app-bound callback for this project; that is not proof none exists, but it means the browser-return route must be rejected unless the manual spike produces explicit first-party evidence for such a return. [CITED: https://www.siriusxm.com/help/one-time-verification] [CITED: https://listenercare.siriusxm.com/prweb/autoredirect/app/ExternalKM/help/SupportCenter/article/KC-234216/Why-is-a-password-optional%3F]

**Primary recommendation:** Build one local SwiftPM `SiriusXMClient` product with an internal compatibility adapter, an app-owned Keychain credential store, redaction-by-construction, and a dedicated unsupported state; unlock later phases only after a single evidence-selected path passes the two manual authorized smoke tests.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| User-entered credentials / real-browser initiation | Browser / Client | Frontend Server — | The user owns sign-in initiation; the app must never inspect browser storage or conceal itself. [VERIFIED: .planning/phases/01-safe-interoperability-foundation/01-CONTEXT.md] |
| Native session orchestration and result classification | API / Backend | Browser / Client | The reusable client serializes attempts, maps known outcomes, and stops on unknown/control-protected flows. [VERIFIED: .planning/REQUIREMENTS.md:12-13] |
| Secret persistence and deletion | Browser / Client | Database / Storage | The native app owns an app-scoped Keychain adapter; the public library accepts an injected credential source. [VERIFIED: .planning/REQUIREMENTS.md:18,27] |
| Ephemeral session material and direct requests | API / Backend | Browser / Client | The client keeps this state in memory and uses its owned transport only for direct SiriusXM requests. [VERIFIED: .planning/REQUIREMENTS.md:19] |
| Compatibility / unsupported-authentication screen | Browser / Client | API / Backend | UI presents only typed, non-secret state emitted by the client; it does not decide protocol behavior. [VERIFIED: .planning/phases/01-safe-interoperability-foundation/01-CONTEXT.md] |
| Fixture scrubbing and diagnostics | API / Backend | Browser / Client | Library defines safe semantic events; app routes them to private local logs and never exports raw wire data. [VERIFIED: .planning/REQUIREMENTS.md:20,27] |

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftPM / `SiriusXMClient` library product | Swift 6.3.3 installed | Independently consumable Apple-platform client, targets, and package tests | SwiftPM’s official package structure exposes a library product and a test target without a third-party package manager. [CITED: https://github.com/swiftlang/swift-package-manager/blob/main/Sources/PackageManagerDocs/Documentation.docc/GettingStarted.md] [VERIFIED: `swift --version`] |
| Foundation `URLSession` | OS-bundled | Direct network transport behind an injected protocol | `.ephemeral` does not persist caches, cookies, credential stores, or session data to disk. [CITED: https://developer.apple.com/documentation/foundation/urlsessionconfiguration/ephemeral] |
| Security.framework Keychain Services | OS-bundled | App-owned encrypted credential storage and explicit deletion | Apple documents Keychain Services for encrypted small-secret storage and the `SecItem` lifecycle for add, lookup, update, and delete. [CITED: https://developer.apple.com/documentation/security/using-the-keychain-to-manage-user-secrets] |
| `OSLog.Logger` | OS-bundled | Local, structured, privacy-aware diagnostics | `Logger` supports privacy controls for interpolated values; static event names plus private dynamic data support safe diagnostics. [CITED: https://developer.apple.com/documentation/os/logger] [CITED: https://developer.apple.com/documentation/os/oslogprivacy] |
| Swift Testing | Swift 6.3 toolchain | Deterministic unit and contract tests | It supports asynchronous, parameterized tests and serialized suites for the one-attempt state machine. [CITED: https://developer.apple.com/xcode/swift-testing/] [CITED: https://github.com/swiftlang/swift-testing/blob/main/Sources/Testing/Testing.docc/Parallelization.md] |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `AuthenticationServices` / `ASWebAuthenticationSession` | OS-bundled | Narrow feasibility reference only | Use only if SiriusXM supplies an explicit app-bound callback and the user’s locked real-browser requirement is satisfied; do not substitute it for a real-browser return. Apple’s API itself requires a callback strategy and presentation anchor. [CITED: https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession/init%28url%3Acallback%3Acompletionhandler%3A%29-6nut7] |
| `Clock` protocol / `ContinuousClock` | Swift standard library | Deterministic cooldown and timeout behavior | Inject into session orchestration tests; production uses the standard clock. [ASSUMED] |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| App-owned `SecItem` adapter | Keychain wrapper dependency | Do not add one in this phase: the required surface is the four-operation Keychain lifecycle and the project stack already selects direct Security.framework. [VERIFIED: AGENTS.md] |
| Client-owned ephemeral `URLSession` | Shared/default session | Do not use a shared/default session: `.ephemeral` is explicitly designed not to persist session data. [CITED: https://developer.apple.com/documentation/foundation/urlsessionconfiguration/ephemeral] |
| One selected authentication path | Browser/native selector or automatic fallback | Prohibited by the locked decision because it obscures supportability and expands the public/security surface. [VERIFIED: .planning/phases/01-safe-interoperability-foundation/01-CONTEXT.md] |
| Real browser only for browser return | `ASWebAuthenticationSession` as a convenience substitute | Rejected by the locked requirement; Apple’s web-auth API is relevant only when a provider provides a valid callback contract. [VERIFIED: .planning/phases/01-safe-interoperability-foundation/01-CONTEXT.md] [CITED: https://developer.apple.com/documentation/authenticationservices/authenticating-a-user-through-a-web-service] |

**Installation:** No external package installation is recommended for Phase 1. Use OS-bundled frameworks and the installed Swift toolchain. [VERIFIED: `swift --version`]

## Architecture Patterns

### System Architecture Diagram

```text
                         manually initiated by account owner
                                      |
                                      v
             +---------------- Real Browser / Native App ----------------+
             |                                                           |
 browser-only| first-party documented return             native direct flow| honest app identity
             |                                                           |
             +--------------------+----------------------+---------------+
                                  | explicit, expected return / response
                                  v
                  +-----------------------------------+
                  | SiriusXMClient public API          |
                  | Session actor: one attempt in flight|
                  +----------------+------------------+
                                   | typed outcome
              +--------------------+----------------------------+
              |                     |                            |
              v                     v                            v
     authenticated + entitled   rejected / transient        challenge, 403/429,
              |                 (no automatic retry)       redirect drift, unknown
              v                     |                            |
    memory-only session             v                            v
              |            explicit user action       unsupported; discard input;
              v            / safe explanation         no workaround or app shell
  direct SiriusXM requests
              |
              v
  app Keychain adapter stores only a validated reusable credential, if the selected path needs one
              |
  user sign-out ---> clear memory ---> SecItemDelete ---> signed out
```

The decision point is the boundary. Browser authentication is eligible only when the first party supplies a clean, documented, app-bound return—not when an app can observe cookies, browser storage, or a copied token. Native authentication is eligible only when it completes with honest client identity and no challenge or control-protection response. Anything else produces the unsupported result. This is a prescriptive consequence of the locked constraints, not an inference about what SiriusXM will allow. [VERIFIED: .planning/phases/01-safe-interoperability-foundation/01-CONTEXT.md]

### Recommended Project Structure

```text
Packages/
└── SiriusXMClient/                 # standalone local SwiftPM package
    ├── Package.swift                # public library product and test targets
    ├── Sources/
    │   └── SiriusXMClient/          # public semantic API plus internal adapters
    │       ├── Public/              # models, capabilities, typed outcomes/errors
    │       ├── Session/             # serialized session actor
    │       ├── Transport/           # injected protocol and URLSession implementation
    │       ├── Diagnostics/         # allow-listed event types/redactor
    │       └── InternalAdapters/    # protocol-specific wire details; internal only
    └── Tests/
        ├── SiriusXMClientTests/     # scripted transport / clock state-machine tests
        ├── FixtureTests/            # sanitizer and decoder contract tests
        └── PublicAPITests/          # compile/use test as an independent consumer
SiriusMac/
├── Security/KeychainCredentialStore.swift  # app-owned SecItem adapter
├── Authentication/                         # UI state / compatibility screen only
└── Tests/                                  # app composition and logout tests
```

This is a proposed Phase 1 structure, not a description of existing files. [ASSUMED]

### Pattern 1: Stable semantic façade; volatile internal adapter

**What:** Export typed async operations, typed capabilities/outcomes, and small injected collaborator protocols. Keep endpoint paths, header/cookie names, body schemas, and redirect parsing in `internal` adapter code.

**When to use:** Always. The public contract is the repair boundary required by CLNT-01 through CLNT-04. [VERIFIED: .planning/REQUIREMENTS.md:24-27]

**Implementation rules:**

- The client’s public sign-in operation returns a semantic success or semantic outcome; it never exposes `URLRequest`, `HTTPURLResponse`, cookie containers, raw JSON, header maps, or response bytes. [VERIFIED: .planning/REQUIREMENTS.md:25-26]
- The public boundary also defines typed async catalog, metadata, and live-stream-resolution domain APIs, capability values, and errors required by CLNT-02. Phase 1 implementations report semantic unavailable without making a provider request; catalog fetching, metadata loops, stream resolution, and playback remain assigned to Phase 2. [VERIFIED: .planning/REQUIREMENTS.md:25] [VERIFIED: .planning/ROADMAP.md:36-48]
- The library takes injected transport, clock, credential-source, and diagnostics collaborators only at the seams where deterministic tests or app-owned secrets require them. [VERIFIED: .planning/REQUIREMENTS.md:27]
- The URLSession-backed transport is an internal live implementation configured with `.ephemeral`, and its request policy allows only the verified direct SiriusXM host(s) selected during the manual spike. Do not hard-code any host until evidence exists. [CITED: https://developer.apple.com/documentation/foundation/urlsessionconfiguration/ephemeral] [ASSUMED]

### Pattern 2: Serialized, fail-closed authentication state machine

**What:** A single actor owns the active attempt and all session transitions. Its initial supported state is signed out; unknown protocol conditions are terminal unsupported results that clear transient material.

**When to use:** Sign-in, session renewal, and sign-out only; catalog/playback are Phase 2 work. [VERIFIED: .planning/ROADMAP.md:23-34]

**Required behavior:**

1. Reject a second in-flight attempt locally; do not send it to SiriusXM. [VERIFIED: .planning/phases/01-safe-interoperability-foundation/01-CONTEXT.md]
2. Recognize only the outcome classes needed by AUTH-01; map everything else to unsupported. [VERIFIED: .planning/REQUIREMENTS.md:12-13]
3. On challenge, suspected bot defense, 403, 429, unexpected redirect, or ambiguous output: stop without retry, clear transient input, record only a redacted classification, and offer official-site navigation. [VERIFIED: .planning/phases/01-safe-interoperability-foundation/01-CONTEXT.md]
4. On sign-out: cancel/retire the live session, erase memory-held material, attempt Keychain deletion, and surface a safe storage failure rather than claiming sign-out completed. Apple documents `SecItemDelete` as the operation that removes a stored password entirely. [CITED: https://developer.apple.com/documentation/security/using-the-keychain-to-manage-user-secrets]

### Pattern 3: Store only a validated, app-owned credential

**What:** Keep user-entered data in a short-lived UI value; call `SecItemAdd` only after a selected, authorized flow succeeds and only if the selected path requires a reusable credential. Look up with `SecItemCopyMatching`, replace a known existing item with `SecItemUpdate`, and delete on sign-out with `SecItemDelete`. [CITED: https://developer.apple.com/documentation/security/using-the-keychain-to-manage-user-secrets]

**When to use:** The app target only. The public library obtains a scoped credential through an injected source and must never import app state, SwiftData, preferences, or a disk fallback. [VERIFIED: .planning/REQUIREMENTS.md:18,27]

**Verified Keychain pattern:**

```swift
// Source: https://developer.apple.com/documentation/security/adding-a-password-to-the-keychain
let status = SecItemAdd(query as CFDictionary, nil)
guard status == errSecSuccess else {
    throw KeychainError.unhandledError(status: status)
}
```

Apple documents checking `OSStatus` and using `SecItemUpdate` rather than adding a duplicate primary-key item; it documents `SecItemDelete` for the explicit forget/sign-out action. [CITED: https://developer.apple.com/documentation/security/updating-and-deleting-keychain-items] [CITED: https://developer.apple.com/documentation/security/using-the-keychain-to-manage-user-secrets]

### Pattern 4: Diagnostic data is structured and allow-listed

**What:** Diagnostics begin as a small internal event value containing only a capability/operation classification, a safe outcome class, and a non-identifying correlation handle. The live sink writes static text and marks every dynamic value `.private` or `.sensitive`; fixtures and support evidence use a separate redactor, not the log string itself. [CITED: https://developer.apple.com/documentation/os/oslogprivacy]

**When to use:** Every Phase 1 failure path and every fixture promotion step. [VERIFIED: .planning/REQUIREMENTS.md:20]

### Anti-Patterns to Avoid

- **Browser cookie/token harvesting:** It violates the locked real-browser and no-scraping constraint; reject the route instead. [VERIFIED: .planning/phases/01-safe-interoperability-foundation/01-CONTEXT.md]
- **Automatic auth retries or a browser/native fallback:** This creates a request storm and masks the evidence that determines supportability. [VERIFIED: .planning/phases/01-safe-interoperability-foundation/01-CONTEXT.md]
- **Persist-before-proof:** Do not insert credentials in Keychain before a successful selected path; unsupported auth must retain nothing. [VERIFIED: .planning/phases/01-safe-interoperability-foundation/01-CONTEXT.md] [CITED: https://developer.apple.com/documentation/security/using-the-keychain-to-manage-user-secrets]
- **Public raw transport types:** A `URL`, endpoint, header, cookie, or decoder type in public API makes protocol drift a breaking application change. [VERIFIED: .planning/REQUIREMENTS.md:25-26]
- **Raw-response diagnostics or “sanitized later”:** Redaction must happen before a value can reach logs, fixtures, test reports, or support output. [VERIFIED: .planning/REQUIREMENTS.md:20]

## Authentication Feasibility Decision Procedure

### Candidate order and hard stop

1. **Browser return feasibility:** Inspect only first-party, public documentation and the result of a human-initiated real-browser attempt for an explicit, expected return that the app can receive without reading browser cookies/storage or copying a token. A valid return must have a fixed, app-bound callback contract and enough first-party evidence to exchange/verify it directly with SiriusXM. [VERIFIED: .planning/phases/01-safe-interoperability-foundation/01-CONTEXT.md] [CITED: https://developer.apple.com/documentation/authenticationservices/authenticating-a-user-through-a-web-service]
2. **If that evidence is absent, native direct-flow feasibility:** Use only a genuine native request implementation that identifies the app honestly and makes no attempt to emulate a browser. Test only under the manual one-attempt policy. [VERIFIED: .planning/phases/01-safe-interoperability-foundation/01-CONTEXT.md]
3. **If either test sees a stop condition or has ambiguous entitlement evidence:** record only the safe classification, mark authentication unsupported, delete/avoid credentials, and halt Phase 2–5 authorization-dependent work. [VERIFIED: .planning/phases/01-safe-interoperability-foundation/01-CONTEXT.md]

Do not treat the presence of `ASWebAuthenticationSession` as evidence that the browser-return path exists. Apple documents that API as a callback-based web-service mechanism; its availability cannot create a provider return contract. [CITED: https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession/init%28url%3Acallback%3Acompletionhandler%3A%29-6nut7]

### Manual smoke-test protocol (separate from CI)

| Stage | Owner | Permitted action | Record (safe only) | Immediate stop |
|-------|-------|------------------|--------------------|----------------|
| Prepare | Account owner | Select the evidence-backed one path; ensure no attempt is in flight. | Build/app version, path label, UTC date rounded to day, run identifier. [ASSUMED] | No evidence-backed path — unsupported. |
| Run 1 | Account owner | Initiate one sign-in through the selected path; observe one authenticated-and-entitled outcome; sign out. | `success`, `rejected`, `challenge`, `unsupported`, or `ambiguous`; cleanup result. [ASSUMED] | CAPTCHA, challenge/interstitial, 403/429, rate-limit, redirect drift, bot-detection signal, ambiguity. [VERIFIED: .planning/phases/01-safe-interoperability-foundation/01-CONTEXT.md] |
| Cooldown | Account owner | Wait before initiating another test; no background retry/polling. | Only that cooldown was observed. [ASSUMED] | Any automatic request. [VERIFIED: .planning/phases/01-safe-interoperability-foundation/01-CONTEXT.md] |
| Run 2 | Account owner | Repeat independently and sign out cleanly. | Same safe fields, no link to account identity. [ASSUMED] | Same stop conditions. [VERIFIED: .planning/phases/01-safe-interoperability-foundation/01-CONTEXT.md] |
| Decision | Maintainer | Declare supported only if both runs pass exactly; otherwise present unsupported compatibility state and halt downstream authorization work. | Signed-off decision and no-secret evidence summary. [ASSUMED] | Failed/ambiguous run. [VERIFIED: .planning/phases/01-safe-interoperability-foundation/01-CONTEXT.md] |

The exact cooldown duration is deliberately not locked here; it must be a conservative human choice recorded in the plan, never a background scheduler. [ASSUMED]

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Secret encryption / password vault | Custom cryptography or encrypted file store | Security.framework Keychain Services | Apple supplies encrypted keychain storage and the needed CRUD API. [CITED: https://developer.apple.com/documentation/security/keychain-services] |
| HTTP stack and cookie persistence | Custom socket/cookie system | Foundation `URLSession` with `.ephemeral` configuration | The OS API already avoids persistent caches, cookies, and credentials for the session. [CITED: https://developer.apple.com/documentation/foundation/urlsessionconfiguration/ephemeral] |
| Browser automation / challenge handling | WebView scraper, cookie exporter, CAPTCHA/MFA solver, UA spoofing | No implementation; explicit unsupported outcome | These behaviours are prohibited by locked project constraints. [VERIFIED: .planning/phases/01-safe-interoperability-foundation/01-CONTEXT.md] |
| Logging redaction | Ad hoc `String.replacing` calls at individual log sites | Typed safe diagnostic events plus `OSLog` privacy interpolation | Allow-listing data before logging is testable; Apple provides explicit privacy controls. [CITED: https://developer.apple.com/documentation/os/oslogprivacy] |
| Test scheduler | Custom test runner | Swift Testing async/parameterized tests and `.serialized` suite trait | The framework integrates concurrency tests and serialized suites. [CITED: https://developer.apple.com/xcode/swift-testing/] [CITED: https://github.com/swiftlang/swift-testing/blob/main/Sources/Testing/Testing.docc/Parallelization.md] |

**Key insight:** The only custom code should be the narrowly scoped, repairable compatibility adapter and semantic state machine; using custom credential storage, browser automation, or diagnostics plumbing would make the high-risk boundary larger rather than safer. [VERIFIED: .planning/REQUIREMENTS.md:18-20,25-27]

## Common Pitfalls

### Pitfall 1: Mistaking a visible website sign-in for an app integration contract

**What goes wrong:** The team treats a user-visible page, form, cookie, or redirect as permission to implement browser extraction or an undocumented callback.

**Why it happens:** `ASWebAuthenticationSession` supports callback URLs, but it does not establish that a given provider offers or authorizes one. [CITED: https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession/init%28url%3Acallback%3Acompletionhandler%3A%29-6nut7]

**How to avoid:** Require explicit first-party return evidence for the browser path; otherwise test a single honest native path or fail unsupported. Never inspect a browser profile. [VERIFIED: .planning/phases/01-safe-interoperability-foundation/01-CONTEXT.md]

**Warning signs:** A design needs a WebView, copied DevTools data, browser cookies, a spoofed user agent, a challenge solver, or two sign-in methods.

### Pitfall 2: Persisting secrets before the path has proved supportable

**What goes wrong:** A password/token ends up in Keychain, a fixture, preferences, a test failure, or a retained UI value even though the auth flow is unsupported.

**Why it happens:** Storage is implemented as part of form submission instead of the success transition.

**How to avoid:** Make the Keychain write a post-success effect only; make unsupported/rejected/challenge paths zeroize in-memory input and assert the Keychain query returns no item. Apple’s documented normal flow stores after successful authentication and deletes when disconnecting. [CITED: https://developer.apple.com/documentation/security/using-the-keychain-to-manage-user-secrets]

**Warning signs:** Any write to `UserDefaults`, SwiftData, file fixtures, or test snapshots; `SecItemAdd` before a validated semantic success. [VERIFIED: .planning/REQUIREMENTS.md:18]

### Pitfall 3: “Redacted” logs that contain a raw upstream value first

**What goes wrong:** A raw error, URL, response body, token, or cookie reaches an interpolation or `Error` description before a caller remembers to redact it.

**Why it happens:** Redaction is a convention rather than a typed boundary.

**How to avoid:** Do not pass raw response/error values into diagnostics interfaces. Use static event codes and `OSLog` `.private`/`.sensitive` dynamic fields only after structural redaction. Apple notes that numeric dynamic values are not automatically redacted, so every dynamic field must be classified deliberately. [CITED: https://developer.apple.com/documentation/os/generating-log-messages-from-your-code]

**Warning signs:** `print`, `debugPrint`, raw `Error.localizedDescription`, URL string interpolation, JSON snapshots, or golden fixtures sourced from a live account.

### Pitfall 4: Test doubles that hide the single-attempt requirement

**What goes wrong:** Happy-path tests pass while two concurrent `signIn` calls create two transports, or retries continue after a challenge/rate-limit result.

**Why it happens:** The state machine is spread across UI and transport code or asynchronous tests run against shared mutable state in parallel.

**How to avoid:** Place all transitions in one actor; test scripted sequences with injected transport/clock; serialize the session suite when it intentionally exercises shared state. [VERIFIED: .planning/REQUIREMENTS.md:27] [CITED: https://github.com/swiftlang/swift-testing/blob/main/Sources/Testing/Testing.docc/Parallelization.md]

**Warning signs:** More than one request recorded for one action, a retry timer in the authentication path, or a second attempt after a stop condition.

### Pitfall 5: Letting the app depend on volatile public API details

**What goes wrong:** UI code imports adapter types or a public error includes endpoint/header/cookie details.

**Why it happens:** A first implementation exposes whatever the transport already has.

**How to avoid:** Write an independent-consumer compile test that imports only `SiriusXMClient` and cannot name internal adapter modules. Keep fixture decoder tests inside the package. [VERIFIED: .planning/REQUIREMENTS.md:24-27]

**Warning signs:** App target imports Foundation networking only to sign in; a public `URLRequest`, `HTTPURLResponse`, JSON dictionary, cookie name, or raw status body appears in the library API.

## Code Examples

Verified platform patterns from official sources:

### Ephemeral direct-request session

```swift
// Source: https://developer.apple.com/documentation/foundation/urlsessionconfiguration/ephemeral
let configuration = URLSessionConfiguration.ephemeral
let session = URLSession(configuration: configuration)
```

Use this only inside the live transport implementation. Apple documents that this configuration uses no persistent cache, cookie, or credential storage. [CITED: https://developer.apple.com/documentation/foundation/urlsessionconfiguration/ephemeral]

### Private dynamic diagnostic value

```swift
// Source: https://developer.apple.com/documentation/os/oslogprivacy
Logger().info("Authentication outcome: \(outcome, privacy: .private)")
```

For Phase 1, `outcome` must itself already be a safe semantic classification, not a raw response or URL. The latter rule is the project’s secure-design requirement. [CITED: https://developer.apple.com/documentation/os/oslogprivacy] [VERIFIED: .planning/REQUIREMENTS.md:20]

### Serialized suite for shared session orchestration

```swift
// Source: https://github.com/swiftlang/swift-testing/blob/main/Sources/Testing/Testing.docc/Parallelization.md
import Testing

@Suite(.serialized) struct SessionCoordinatorTests {
    @Test func concurrentAttemptsProduceOneLiveAttempt() async throws {
        // Assert against a scripted injected transport.
    }
}
```

The test name and injected transport are proposed project code, not established API. [ASSUMED]

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Persisted/default URL session state | Client-owned `.ephemeral` URL session for private session handling | Current Apple API | Keeps caches, cookies, credential stores, and session data in RAM rather than the disk-backed session store. [CITED: https://developer.apple.com/documentation/foundation/urlsessionconfiguration/ephemeral] |
| Ad hoc test assertion framework patterns | Swift Testing async, parameterized tests, and traits | Current installed Swift 6.3.3 toolchain | Use the standard Swift test framework for package code; serialize only the shared-state suite. [CITED: https://developer.apple.com/xcode/swift-testing/] [VERIFIED: `swift --version`] |
| “Private by default” assumed from logging types | Explicit `OSLogPrivacy` classification for every dynamic value | Current Apple logging API | String/object values have privacy behavior, but non-string dynamic data needs deliberate handling; the project should never depend on defaults for secrets. [CITED: https://developer.apple.com/documentation/os/generating-log-messages-from-your-code] |

**Deprecated/outdated:**

- Legacy Keychain APIs such as `SecKeychainItem` are not the planned storage surface; use the modern `SecItem` API family Apple documents for add, query, update, and delete. [CITED: https://developer.apple.com/documentation/security/keychain-items] [CITED: https://developer.apple.com/documentation/security/using-the-keychain-to-manage-user-secrets]
- Using `ASWebAuthenticationSession` to infer a provider callback is not valid; use it only if a provider supplies the callback contract and all locked browser requirements remain satisfied. [CITED: https://developer.apple.com/documentation/authenticationservices/authenticating-a-user-through-a-web-service] [VERIFIED: .planning/phases/01-safe-interoperability-foundation/01-CONTEXT.md]

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | A `Clock`/`ContinuousClock` injection is the right concrete API for cooldown and timeout tests. | Standard Stack | Only the collaborator’s exact type needs revision; the deterministic-clock requirement remains. |
| A2 | `Packages/SiriusXMClient` plus `SiriusMac/` is the best initial monorepo layout. | Architecture Patterns | File locations may change; product/module boundary must not. |
| A3 | A build version, path label, rounded UTC day, and run identifier are sufficient manual evidence fields. | Manual smoke-test protocol | Evidence may need a maintainer-approved safe field or omit a field; no account/session data may be added casually. |
| A4 | The manual cooldown can be chosen conservatively in the plan rather than locked in research. | Manual smoke-test protocol | A provider or maintainer policy may require a longer/no-repeat period. |
| A5 | The proposed session test names and injected transport type are suitable initial project code. | Code Examples | Names may change; tests must still prove one in-flight attempt and zero retry after stop conditions. |

## Open Questions (RESOLVED)

1. **Does SiriusXM offer a first-party, app-bound browser-return contract for this use case?**
   - What we know: Apple supports callback-based web authentication, but public SiriusXM help confirms varied consumer sign-in methods rather than a documented third-party app callback. [CITED: https://developer.apple.com/documentation/authenticationservices/authenticating-a-user-through-a-web-service] [CITED: https://www.siriusxm.com/help/one-time-verification]
   - Safe planning disposition: The contract remains unknown and browser return is unsupported by default. Only the Plan 01-06 allow-listed evidence gate may change that disposition, and only when it receives exact authorized first-party evidence for a fixed app-bound return without browser-state extraction. No such evidence is claimed here.

2. **Can an honest native direct-to-SiriusXM path produce a confirmed entitled result without any stop condition?**
   - What we know: SiriusXM presently supports multiple authentication factors/forms; the project may not bypass any control. [CITED: https://listenercare.siriusxm.com/prweb/autoredirect/app/ExternalKM/help/SupportCenter/article/KC-234216/Why-is-a-password-optional%3F] [VERIFIED: .planning/phases/01-safe-interoperability-foundation/01-CONTEXT.md]
   - Safe planning disposition: The authorized native contract remains unknown and native direct is unsupported by default. Plan 01-06 may consider it only after browser return is ruled out and may select it only from exact authorized, non-secret evidence for an honest direct contract and strict entitlement predicate; it does not authorize a native live sign-in. Every terminal, ambiguous, or access-control classification remains unsupported.

3. **What specific safe semantic outcome proves entitlement?**
   - What we know: AUTH-01 requires entitlement as an explicit outcome, and the manual gate requires a confirmed authenticated-and-entitled response. [VERIFIED: .planning/REQUIREMENTS.md:12] [VERIFIED: .planning/phases/01-safe-interoperability-foundation/01-CONTEXT.md]
   - Safe planning disposition: The predicate remains unknown, so no response can be treated as authenticated-and-entitled by default. Only exact authorized evidence accepted through Plan 01-06 may define a narrow adapter-local predicate; until then the result is unsupported, and the public surface exposes only the semantic capability/error rather than upstream evidence.

These questions are resolved for planning by the same fail-closed rule: unknown remains unsupported until the bounded Plan 01-06 evidence gate records exact authorized evidence. This section does not assert that browser-return, native-direct, or entitlement evidence exists.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|-------------|-----------|---------|----------|
| Swift toolchain | SwiftPM library, unit tests | ✓ | Swift 6.3.3 | — [VERIFIED: `swift --version`] |
| Xcode application toolchain | Native macOS app target and `xcodebuild` tests | ✗ — command is installed but active developer directory is Command Line Tools, so `xcodebuild -version` fails | — | Install/select full Xcode before app-target execution. [VERIFIED: `xcodebuild -version`] |
| Security.framework | Keychain adapter at runtime | ✓ as macOS framework assumed by current Swift target; CLI probing is not a runtime API test. [ASSUMED] | OS-bundled | No secure disk fallback; unavailable Keychain is a typed storage failure. |
| Live SiriusXM account/session | Two manual viability runs only | Not probed by this research | — | No fallback; unsupported outcome halts later phases. [VERIFIED: .planning/phases/01-safe-interoperability-foundation/01-CONTEXT.md] |

**Missing dependencies with no fallback:**

- A full Xcode installation/selected developer directory is required before building the native app target or running `xcodebuild` verification. [VERIFIED: `xcodebuild -version`]
- A human-authorized, evidence-backed authentication path is required before Phase 2–5 continuation. [VERIFIED: .planning/phases/01-safe-interoperability-foundation/01-CONTEXT.md]

**Missing dependencies with fallback:** None.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Swift Testing from the installed Swift 6.3.3 toolchain. [VERIFIED: `swift --version`] |
| Config file | None — greenfield SwiftPM package must create `Package.swift` in Wave 0. [VERIFIED: `rg --files`] |
| Quick run command | `swift test --package-path Packages/SiriusXMClient` [ASSUMED] Proposed package path. |
| Full suite command | `swift test --package-path Packages/SiriusXMClient && xcodebuild test -scheme SiriusMac` after full Xcode/app scheme exist. [ASSUMED] Proposed target and scheme. |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| AUTH-01 | Maps scripted success, rejection, challenge, unsupported, and entitlement responses to semantic results. | unit / contract | `swift test --package-path Packages/SiriusXMClient --filter AuthenticationOutcomeTests` [ASSUMED] Proposed suite. | ❌ Wave 0 |
| AUTH-02 | Unknown shape and stop signals perform no alternate/second request and return unsupported. | unit | `swift test --package-path Packages/SiriusXMClient --filter FailClosedAuthenticationTests` [ASSUMED] Proposed suite. | ❌ Wave 0 |
| AUTH-03 | Sign-out clears actor state and app Keychain item; failed deletion is explicit. | unit / app integration | `swift test --package-path Packages/SiriusXMClient --filter SignOutTests` [ASSUMED] Proposed suite. | ❌ Wave 0 |
| SECR-01 | No production credential store writes outside injected app Keychain adapter. | unit / static review | `swift test --package-path Packages/SiriusXMClient --filter KeychainCredentialStoreTests` [ASSUMED] Proposed suite. | ❌ Wave 0 |
| SECR-02 | Ephemeral configuration and direct-host policy; session is not serializable/persisted. | unit | `swift test --package-path Packages/SiriusXMClient --filter EphemeralSessionTests` [ASSUMED] Proposed suite. | ❌ Wave 0 |
| SECR-03 | Canary credential/token/URL data cannot appear in diagnostic event, fixture, test failure, or exported evidence. | unit / fixture | `swift test --package-path Packages/SiriusXMClient --filter RedactionTests` [ASSUMED] Proposed suite. | ❌ Wave 0 |
| CLNT-01 | External consumer compiles using only public SwiftPM product symbols. | compile / integration | `swift test --package-path Packages/SiriusXMClient --filter PublicConsumerTests` [ASSUMED] Proposed suite. | ❌ Wave 0 |
| CLNT-02 | Independent consumer compiles and awaits typed authentication, entitlement, catalog, metadata, and live-stream-resolution domain APIs; the three content operations report typed unavailable without transport and expose no wire data. | compile / API review | `swift test --package-path Packages/SiriusXMClient --filter PublicConsumerTests` [ASSUMED] Proposed suite. | ❌ Wave 0 |
| CLNT-03 | Internal adapter types cannot be imported by consumer test. | compile / API review | `swift test --package-path Packages/SiriusXMClient --filter PublicConsumerTests` [ASSUMED] Proposed suite. | ❌ Wave 0 |
| CLNT-04 | Scripted transport, clock, credential source, and diagnostics make state tests deterministic. | unit | `swift test --package-path Packages/SiriusXMClient --filter SessionCoordinatorTests` [ASSUMED] Proposed suite. | ❌ Wave 0 |

The two authorized smoke-test runs are deliberately manual-only and must never be converted into this command set, routine CI, a scheduled job, or a credential-bearing artifact. [VERIFIED: .planning/phases/01-safe-interoperability-foundation/01-CONTEXT.md]

### Sampling Rate

- **Per task commit:** `swift test --package-path Packages/SiriusXMClient` after Wave 0 creates the package. [ASSUMED] Proposed path.
- **Per wave merge:** Full package suite; app-target tests only once full Xcode and app scheme are available. [VERIFIED: `xcodebuild -version`] [ASSUMED] Proposed app target.
- **Phase gate:** Full automated suite green **and** two separately initiated manual authorized smoke-test runs with clean sign-out. [VERIFIED: .planning/phases/01-safe-interoperability-foundation/01-CONTEXT.md]

### Wave 0 Gaps

- [ ] `Packages/SiriusXMClient/Package.swift` — library product and test targets. [ASSUMED] Proposed path.
- [ ] `Packages/SiriusXMClient/Tests/SiriusXMClientTests/` — scripted transport/clock/session tests. [ASSUMED] Proposed path.
- [ ] `Packages/SiriusXMClient/Tests/FixtureTests/` — scrubber and canary-secret corpus. [ASSUMED] Proposed path.
- [ ] `Packages/SiriusXMClient/Tests/PublicAPITests/` — independent consumer compile test. [ASSUMED] Proposed path.
- [ ] Full Xcode installation/selection — required before adding/running app-target tests. [VERIFIED: `xcodebuild -version`]

## Security Domain

The config quote is `"security_enforcement": true` and `"security_asvs_level": 1`. [VERIFIED: .planning/config.json:47-48] Therefore security enforcement is enabled at ASVS Level 1. OWASP ASVS 5.0’s current category names differ from the legacy category labels in the standard research template; the table retains the template labels while mapping the controls to the Phase 1 native-client threat model. [CITED: https://owasp.org/www-project-application-security-verification-standard/]

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | yes | Evidence-selected single path, semantic outcome mapping, one-attempt actor, and explicit challenge/unsupported result. [VERIFIED: .planning/REQUIREMENTS.md:12-13] |
| V3 Session Management | yes | Memory-only session state, `.ephemeral` session transport, sign-out clearing, and no cookie harvesting. [CITED: https://developer.apple.com/documentation/foundation/urlsessionconfiguration/ephemeral] [VERIFIED: .planning/REQUIREMENTS.md:14,19] |
| V4 Access Control | yes | Entitlement is an explicit capability outcome; never infer it from cached/visible content and never defeat upstream controls. [VERIFIED: .planning/REQUIREMENTS.md:12-13] |
| V5 Input Validation | yes | Strict internal adapter decoding, known-return allow-list, redactor validation, and unsupported result for malformed/changed protocol data. [VERIFIED: .planning/REQUIREMENTS.md:13,20,26] |
| V6 Cryptography | yes | Use Keychain Services for encrypted small-secret storage; do not implement custom secret encryption. [CITED: https://developer.apple.com/documentation/security/keychain-services] |
| V7 Error Handling and Logging | yes | Static diagnostic classifications and `OSLog` private/sensitive dynamic values; raw response exclusion. [CITED: https://developer.apple.com/documentation/os/oslogprivacy] [VERIFIED: .planning/REQUIREMENTS.md:20] |
| V8 Data Protection | yes | Keychain-only stored credentials, ephemeral tokens, synthetic fixtures, no telemetry/export in Phase 1. [VERIFIED: .planning/REQUIREMENTS.md:18-20] |
| V9 Communication | yes | Client-owned direct TLS requests only to the approved SiriusXM host(s) once selected; no proxy. [VERIFIED: .planning/REQUIREMENTS.md:19] [ASSUMED] Host allow-list implementation. |

### Known Threat Patterns for native Swift session client

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Browser cookie/storage extraction | Information Disclosure / Elevation of Privilege | Do not inspect browser state; require an explicit first-party app-bound return or fail unsupported. [VERIFIED: .planning/phases/01-safe-interoperability-foundation/01-CONTEXT.md] |
| CAPTCHA/MFA/anti-bot/device-limit circumvention | Elevation of Privilege / Tampering | Detect known stop classifications, end the attempt, clear transient state, and direct the user to official SiriusXM resolution. [VERIFIED: .planning/phases/01-safe-interoperability-foundation/01-CONTEXT.md] |
| Credential/token persistence or fixture leakage | Information Disclosure | Keychain-only post-success storage; synthetic fixtures; canary scans; diagnostics do not accept raw values. [VERIFIED: .planning/REQUIREMENTS.md:18-20] |
| Concurrent/retry request storm | Denial of Service / Repudiation | Single actor, one attempt in flight, no automatic authentication retry, manual cooldown. [VERIFIED: .planning/phases/01-safe-interoperability-foundation/01-CONTEXT.md] |
| Protocol drift accepted as authenticated | Spoofing / Tampering | Internal strict adapter maps unknown/malformed/redirect-changed outputs to unsupported. [VERIFIED: .planning/REQUIREMENTS.md:13,26] |
| Sensitive diagnostic export | Information Disclosure | Static allow-listed classification schema and OSLog privacy controls; no raw log archive. [CITED: https://developer.apple.com/documentation/os/generating-log-messages-from-your-code] [VERIFIED: .planning/REQUIREMENTS.md:20] |

## Planner-Ready Phase Decomposition

1. **Wave 0 — Package and test foundation:** Create the local SwiftPM library product, source/test targets, public-consumer compile test, and a no-network scripted transport. This establishes CLNT-01 and the test harness before protocol work. [VERIFIED: .planning/REQUIREMENTS.md:24-27]
2. **Wave 1 — Stable semantic boundary:** Add public authentication/entitlement capabilities and typed outcomes/errors plus endpoint-free catalog, metadata, and live-stream-resolution APIs/capabilities/errors whose Phase 1 implementations report unavailable without provider work; add injected collaborators, one-attempt session actor, internal adapter protocol, redacted diagnostics, and synthetic contract fixtures. Verify every fail-closed state with Swift Testing. [VERIFIED: .planning/REQUIREMENTS.md:12-13,20,25-27]
3. **Wave 2 — Native security boundary:** Add the app-owned `SecItem` credential store, post-success persistence only, idempotent sign-out cleanup, dedicated unsupported-authentication presentation model, and Keychain/redaction canary tests. Do not add catalog/playback UI. [VERIFIED: .planning/REQUIREMENTS.md:14,18-20] [VERIFIED: .planning/phases/01-safe-interoperability-foundation/01-CONTEXT.md]
4. **Wave 3 — Human compatibility checkpoint:** Execute the strictly manual evidence procedure: browser-return feasibility first, then native direct feasibility only if browser return cannot meet the contract. Select exactly one path or explicitly publish unsupported state. [VERIFIED: .planning/phases/01-safe-interoperability-foundation/01-CONTEXT.md]
5. **Phase gate — Two-run proof:** If the selected path completes two separate human-initiated authenticated-and-entitled runs with clean sign-out, record only safe evidence and unlock Phase 2 planning/execution. Otherwise retain unsupported compatibility UI and halt Phases 2–5 authorization-dependent work. [VERIFIED: .planning/phases/01-safe-interoperability-foundation/01-CONTEXT.md]

## Sources

### Primary (HIGH confidence)

- [Apple Keychain Services](https://developer.apple.com/documentation/security/keychain-services) — encrypted small-secret storage.
- [Apple: Using the keychain to manage user secrets](https://developer.apple.com/documentation/security/using-the-keychain-to-manage-user-secrets) — post-authentication add, lookup, update, and delete lifecycle.
- [Apple: URLSessionConfiguration.ephemeral](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/ephemeral) — no persistent cache/cookie/credential/session storage.
- [Apple: OSLogPrivacy](https://developer.apple.com/documentation/os/oslogprivacy) and [Generating Log Messages](https://developer.apple.com/documentation/os/generating-log-messages-from-your-code) — privacy controls and dynamic-value caveats.
- [Apple: ASWebAuthenticationSession](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession/init%28url%3Acallback%3Acompletionhandler%3A%29-6nut7) — callback-based web-auth session contract.
- [SwiftPM Getting Started](https://github.com/swiftlang/swift-package-manager/blob/main/Sources/PackageManagerDocs/Documentation.docc/GettingStarted.md) — library product/test-target shape.
- [Swift Testing](https://developer.apple.com/xcode/swift-testing/) and [serialized test suites](https://github.com/swiftlang/swift-testing/blob/main/Sources/Testing/Testing.docc/Parallelization.md) — async, parameterized, and serialized tests.

### Secondary (MEDIUM confidence)

- [SiriusXM: one-time verification code](https://www.siriusxm.com/help/one-time-verification) — current consumer login factor information.
- [SiriusXM: why a password is optional](https://listenercare.siriusxm.com/prweb/autoredirect/app/ExternalKM/help/SupportCenter/article/KC-234216/Why-is-a-password-optional%3F) — password, passkey, and verification-code variability.
- [SiriusXM Customer Agreement](https://www.siriusxm.com/content/dam/sxm-com/pdf/corporate-pdf/Customer-Agreement-ENG-app.pdf) — access restrictions; not a legal determination.
- [OWASP ASVS](https://owasp.org/www-project-application-security-verification-standard/) — current ASVS 5.0 category reference.

### Tertiary (LOW confidence)

- None. All non-verified recommendations are explicitly listed in the Assumptions Log.

## Metadata

**Confidence breakdown:**

- Standard stack: MEDIUM — official Apple/Swift sources verify the platform capabilities; exact project module layout remains discretionary.
- Architecture: MEDIUM — locked requirements tightly determine dependency direction and stop behavior; the actual provider-supported authentication path is unproven.
- Pitfalls: HIGH — they are direct consequences of locked no-bypass/no-leak requirements plus Keychain, ephemeral-session, and OSLog documentation.

**Research date:** 2026-08-16  
**Valid until:** 2026-08-23 for SiriusXM authentication feasibility; 2026-09-15 for Apple/Swift platform guidance.
