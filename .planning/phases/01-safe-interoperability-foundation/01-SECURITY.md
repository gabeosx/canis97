---
phase: 01
slug: safe-interoperability-foundation
status: verified
threats_open: 0
asvs_level: 1
created: 2026-08-18
updated: 2026-08-18
---

# Phase 01 — Security

> ASVS L1 verification of the authored Phase 1 threat register. The blocking threshold is `high`.

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| WebView → credential handoff | One explicit action may select one approved cookie from an app-owned nonpersistent session. | Secret access token, volatile only |
| Credential source → native client | WebView or bounded Keychain material enters the same one-attempt native verification transaction. | Opaque credential |
| SiriusXM response → internal adapters | Untrusted status, headers, redirects, and JSON become closed semantic outcomes. | Untrusted provider bytes |
| Session actor → app presentation | Only authenticated plus entitled evidence may publish an active session. | Semantic state only |
| Sign-out → app-owned storage | Memory, Keychain material, exact token cookies, and nonpersistent WebKit state are retired. | Secret-bearing local state |
| Xcode metadata → build/test tooling | Project membership determines which authentication and regression sources execute. | Build graph metadata |

## Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation / evidence | Status |
|-----------|----------|-----------|----------|-------------|-----------------------|--------|
| T-01-09-01 | Information Disclosure | Web credential handoff | high | mitigate | Single volatile handoff; redacted credential representation; bridge regression coverage. | closed |
| T-01-09-02 | Tampering | Web credential selection | high | mitigate | Exact-cookie selection and one-consumption state machine in `WebAuthenticationBridge`. | closed |
| T-01-09-03 | DoS / Repudiation | Presentation attempts | medium | mitigate | Single-flight presentation work and fixed semantic outcomes. | closed |
| T-01-09-04 | Elevation of Privilege | Session activation | high | mitigate | `SessionCoordinator` requires native authentication then entitlement before active publication. | closed |
| T-01-10-01 | Information Disclosure | Clear-local-session path | high | mitigate | Cleanup-only presentation path does not read Keychain material. | closed |
| T-01-10-02 | Tampering | Sign-out ordering | high | mitigate | Actor memory retires before concurrent external cleaners run. | closed |
| T-01-10-03 | DoS / Repudiation | Repeated cleanup | medium | mitigate | Actor-owned cleanup task coalesces overlapping calls and allows later explicit retry. | closed |
| T-01-10-04 | Elevation of Privilege | Clear-local-session action | high | mitigate | Action delegates only to sign-out and cannot establish a session. | closed |
| T-01-10-05 | Spoofing | Cleanup result | high | mitigate | Keychain and browser failures map to closed aggregate cleanup outcomes. | closed |
| T-01-11-01 | Tampering | Xcode target/source graph | high | mitigate | One active graph with canonical source and test memberships; structural assertions pass. | closed |
| T-01-11-02 | Denial of Service | Xcode project parsing/build | medium | mitigate | Project lint/list, macOS build, app tests, and package tests pass. | closed |
| T-01-11-03 | Repudiation | Detached Xcode graph | medium | mitigate | Detached records were removed in Plan 01-11. Plan 01-16 deliberately reused two object identifiers for the current canonical restore-source membership; the active graph is unique and validated, so the earlier literal-ID absence assertion is superseded while the substantive duplicate-graph risk remains closed. | closed |
| T-01-11-04 | Information Disclosure / Elevation of Privilege | Xcode metadata edit | low | accept | Metadata-only work reads no credentials and adds no executable input surface. See R-01. | closed |
| T-01-12-01 | Tampering / Elevation of Privilege | Selection latch | high | mitigate | Synchronous `.selecting` reservation rejects overlapping selectors. | closed |
| T-01-12-02 | Information Disclosure | Credential delivery | high | mitigate | `.consumed` commits before awaiting the credential consumer and never rolls back. | closed |
| T-01-12-03 | DoS / Repudiation | Pre-commit selection | medium | mitigate | Only uncommitted selection failures reset; controlled suspension regressions pass. | closed |
| T-01-12-04 | Spoofing | Synthetic concurrency fixture | low | accept | Invented values exercise scheduler/cardinality only and make no provider-compatibility claim. See R-02. | closed |
| T-01-13-01 | Spoofing / Tampering | Response decoders | high | mitigate | Redirect/content/status/control preflight and versioned fail-closed decoders. | closed |
| T-01-13-02 | Elevation of Privilege | Session coordinator | high | mitigate | Exact auth→entitlement order precedes one active assignment and persistence. | closed |
| T-01-13-03 | Information Disclosure | Fixtures and diagnostics | high | mitigate | Recursive sensitive-data rejection, opaque credentials, and invented sanitized fixtures. | closed |
| T-01-13-04 | Denial of Service | JSON parsing | medium | mitigate | Bounded response decoding; malformed or unknown evidence terminates without retry. | closed |
| T-01-13-05 | Repudiation | Compatibility evidence | medium | mitigate | Explicit internal decoder versions and named sanitized fixtures identify the enforced contract. | closed |
| T-01-14-01 | Information Disclosure / Elevation of Privilege | Redirect delegate | high | mitigate | Production delegate records entry and always completes with `nil`; regression exercises the callback. | closed |
| T-01-14-02 | Tampering | Redirect counter | medium | mitigate | Counter mutation and reads are lock-protected. | closed |
| T-01-14-03 | Repudiation | Redirect evidence | medium | mitigate | Delegate records the actual callback; no test-only counter shortcut remains. | closed |
| T-01-14-04 | Denial of Service | Redirect/cancellation behavior | high | mitigate | Redirects never follow; blocked production `send()` cancellation clears state and schedules no retry. | closed |
| T-01-15-01 | Spoofing / Elevation of Privilege | Cookie issuer policy | high | mitigate | Exact Secure, root-path, current-cookie predicate permits only apex and `www.siriusxm.com`. | closed |
| T-01-15-02 | Information Disclosure | WebKit residue | high | mitigate | Entire bridge-owned nonpersistent store is removed and replaced without exporting state. | closed |
| T-01-15-03 | Tampering | Extraction/cleanup policy | high | mitigate | Both operations call the same `FirstPartyTokenCookiePolicy.matchingCookies`. | closed |
| T-01-15-04 | Repudiation | Cleanup completion | high | mitigate | Exact deletion/rescan and website-session retirement are aggregated into one truthful result. | closed |
| T-01-15-05 | Denial of Service | Retired WebView | medium | mitigate | Old WebView stops and a fresh nonpersistent configuration replaces it. | closed |
| T-01-16-01 | Spoofing / Elevation of Privilege | Keychain restore | high | mitigate | Explicit one-shot staging still traverses native authentication and entitlement. | closed |
| T-01-16-02 | Information Disclosure | Credential loader | high | mitigate | Bounded loader creates only an opaque credential; volatile bytes remain SPI-scoped. | closed |
| T-01-16-03 | Tampering | Invalid/rejected restore | high | mitigate | Invalid data and terminal restored credentials are erased before presentation. | closed |
| T-01-16-04 | DoS / Repudiation | Restore concurrency | medium | mitigate | Presentation single-flight plus one-consumption source prevents duplicate restore work. | closed |
| T-01-16-05 | Information Disclosure / Tampering | App composition | medium | mitigate | One production source membership; Xcode graph, build, and full app tests pass. | closed |

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| R-01 | T-01-11-04 | The Xcode graph edit is metadata-only, handles no credential material, and introduces no new runtime or dependency surface. | Project owner via approved autonomous Phase 1 plan | 2026-08-18 |
| R-02 | T-01-12-04 | Concurrency tests use invented values and assert only local scheduling/cardinality; they neither contact SiriusXM nor claim provider compatibility. | Project owner via approved autonomous Phase 1 plan | 2026-08-18 |

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-08-18 | 36 | 36 | 0 | `gsd-security-auditor`, ASVS L1 |

## Sign-Off

- [x] All threats have a disposition.
- [x] Accepted risks are documented.
- [x] `threats_open: 0` confirmed at the HIGH blocking threshold.
- [x] `status: verified` set in frontmatter.

**Approval:** verified 2026-08-18
