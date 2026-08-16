# Domain Pitfalls

**Domain:** Public native macOS SiriusXM live player with a reusable Apple-platform client library
**Researched:** 2026-08-16
**Overall confidence:** MEDIUM — macOS, security, privacy, and distribution findings are based on current Apple/Homebrew primary documentation; SiriusXM-specific interoperability evidence is necessarily limited, indirect, and volatile.

## Critical Pitfalls

### Pitfall 1: Treating an undocumented upstream integration as a stable API

**Confidence:** MEDIUM for the architectural consequence; LOW for any particular current upstream behavior.

**What goes wrong:** A player or public library spreads endpoint shapes, request identifiers, response decoding, and entitlement assumptions through UI, persistence, and playback code. An upstream change then turns into an app-wide outage, or a rushed release ships brittle compatibility work.

**Why it happens:** A live demo works against one subscriber/session, so implicit protocol details look like product invariants. Public unofficial-client material also shows hard-coded client metadata, schema parsing, session-lifetime assumptions, and error handling that exposes response bodies—evidence of fragility, not a contract to copy. Do not make endpoints, headers, device emulation, keys, or access-control workarounds part of public API or fixtures.

**How to avoid:** Put all SiriusXM wire behavior behind an internal transport/adapter boundary in `SiriusXMKit`; expose stable domain models and typed failure reasons to app consumers. Make each decoder tolerant of additive unknown fields but strict about required fields and entitlement state. Version fixture *contracts*, maintain captured-data provenance/redaction notes, and use a kill switch that disables affected integration capability rather than guessing or falling back to a weaker auth flow. Keep protocol repair commits isolated from UI changes.

**Warning signs:** Endpoint constants appear outside the adapter; a SwiftUI view decodes upstream JSON; tests assert an entire response blob; compatibility patches require changes across multiple targets; a 2xx response with a changed body causes a crash.

**Detection:** Contract tests against curated, redacted fixtures for success, malformed, missing-field, changed-enum, expired-session, denied-entitlement, and rate-limit cases. Add a scheduled authorized-subscriber smoke test that reports only coarse capability outcomes (login/catalog/tune) and alerts on structural change—not request/response bodies.

**Phase to address:** **Protocol foundation and compatibility seam**, before app UI and before public beta.

---

### Pitfall 2: Failing open when authentication, entitlement, or device policy changes

**Confidence:** MEDIUM.

**What goes wrong:** The client retries an unknown auth challenge indefinitely, mislabels a subscription/device-limit denial as a network issue, stores a partial session, or adds imitation/bypass behavior to “restore” playback. This risks an account, violates project scope, and produces unrecoverable user confusion.

**Why it happens:** Authentication, catalog access, and stream authorization are treated as one boolean. Reverse-engineered clients often conflate transient errors, bad credentials, expired state, and access controls.

**How to avoid:** Model an explicit auth state machine: signed out, authenticating, authenticated, refresh-required, access-denied, unsupported-challenge, and signed-out-after-revocation. Only direct requests to SiriusXM may receive subscriber credentials/tokens. On an unknown challenge, CAPTCHA/MFA/device rule, entitlement denial, or suspicious response: stop, clear only the unusable session material, preserve no raw evidence, show an honest action the subscriber can take in the official service, and do not attempt a workaround. Separate retry eligibility from user-facing state.

**Warning signs:** A generic “login failed” covers all errors; authentication retries exceed a small bounded budget; the app says “playing” before stream authorization succeeds; callers can access raw credential/session fields; error handling changes device identity or geo claims.

**Detection:** Unit-test every state transition and verify that denied/unknown access-control cases make no additional speculative request. Integration tests use a dedicated authorized test account only, never production credentials. Record a privacy-safe counter by failure class and alert on a new class or sudden increase.

**Phase to address:** **Credential/authentication boundary and compatibility seam**, first implementation phase.

---

### Pitfall 3: Leaking subscriber secrets through diagnostics, fixtures, source control, or community support

**Confidence:** HIGH for the underlying risk and prevention; Apple documents that unified logs can be retained and that sensitive values should be private/sensitive.

**What goes wrong:** Passwords, session cookies, authorization values, stream URLs, account identifiers, or raw upstream bodies land in `Logger`, crash reports, test recordings, screenshots, Git history, CI artifacts, GitHub issues, Homebrew scripts, or support bundles. Public source makes a one-user incident permanently replicable.

**Why it happens:** “Temporary” debug logging and copy/paste fixtures are fast; default redaction is misunderstood; reviewers see a test account and assume it is harmless. Apple’s `Logger` redacts dynamic strings by default, but that is not a substitute for a deliberately safe event schema or for avoiding unsafe custom logs/export paths.

**How to avoid:** Define a library-wide `SafeDiagnosticEvent` vocabulary of static codes, timing, HTTP class, adapter version, and a per-process correlation ID—never a URL, body, header, account value, channel personalized field, or error `description`. Explicitly mark any unavoidable dynamic user-related data `.private`/`.sensitive`; prefer allow-listed public fields over redaction regexes. Keep fixtures synthetic or manually minimized/redacted, with automated secret scanning on commits, PRs, releases, docs, issue templates, test artifacts, and binary strings. Provide a support-bundle generator that cannot include Keychain data, raw responses, or stream locators.

**Warning signs:** `response.text`, `data`, URL strings, `Authorization`, `Cookie`, `error.localizedDescription`, or an interpolated model appears in logs; fixtures came from a proxy dump; GitHub issue templates ask for “full logs”; CI uploads all test output.

**Detection:** Pre-commit and CI secret scanners plus custom tests that intentionally inject canary tokens into every error path and assert the output/diagnostic bundle does not contain them. Review GitHub Actions logs/artifacts and release archives on every release candidate. Have a documented rotation/revocation response before the first beta.

**Phase to address:** **Security boundary and observability**, before any real account test and continuously.

---

### Pitfall 4: Assuming a resolved stream URL remains valid or that playback has one “playing” state

**Confidence:** MEDIUM. Apple documents `AVPlayer` waiting/time-control state and stalled-item notification; the exact upstream expiry behavior is not a supported contract.

**What goes wrong:** Playback stalls silently after a token/session expires, retries a stale locator forever, resolves a fresh stream while the old player still emits callbacks, or exposes conflicting UI/Now Playing state. A user sees Play, hears nothing, and remote controls act on the wrong item.

**Why it happens:** Developers equate `AVPlayer.play()` with audible playback and use a URL cache without an expiry/ownership model. Network, server, authorization, and player-item failures are flattened.

**How to avoid:** Own playback in one serial actor/controller with generation IDs. Maintain domain states such as idle, resolving, buffering, playing, paused-by-user, recovering, blocked-auth, failed, and stopped; derive UI and media-session data from that single source of truth. Treat every stream locator as short-lived/opaque and resolve only through the adapter when needed. Use bounded, jittered recovery for clearly recoverable failures; replace player items atomically; cancel stale tasks/observers; never auto-retry a denied entitlement or unsupported auth condition. Offer an explicit “Try again” and preserve the selected channel.

**Warning signs:** More than one `AVPlayer` owner; KVO/notification callbacks have no generation check; `isPlaying` is inferred from button intent; retry loops do not distinguish authorization from transport; old artwork/title returns after a channel change.

**Detection:** Deterministic tests with a fake clock/stream resolver for expiry, 401/403-like authorization result, delay, stall, cancellation, rapid channel switching, sleep/wake, and offline/online transitions. In manual testing, compare audible output, UI, remote-command response, and Now Playing across those transitions.

**Phase to address:** **Playback core and recovery state machine**, before library-browser polish.

---

### Pitfall 5: Letting catalog and now-playing metadata drift corrupt product state

**Confidence:** MEDIUM.

**What goes wrong:** Channel IDs are treated as display numbers, channel names/artwork are used as identifiers, optional/current-program fields crash decoding, stale artwork is reused for a new program, or favorites/recents become unplayable after a lineup change.

**Why it happens:** A snapshot has stable-looking values. Live radio metadata is asynchronous, partial, delayed, and may change independently of channel availability or entitlement.

**How to avoid:** Persist only a stable internal channel reference plus last-seen presentation fields; reconcile it against the current catalog at tune time. Keep catalog, current-program, and image loaders independently cancellable and cache with TTL/ETag-style semantics where supported. Use placeholders and “metadata unavailable” states rather than inventing values. Never make playback dependent on artwork or current-song information. Validate all externally supplied URLs/types/sizes before use.

**Warning signs:** Favorites use a channel name as primary key; metadata completion overwrites the currently selected channel without identity check; a decoder assumes song/artist/artwork are non-null; image cache keys omit channel/program identity.

**Detection:** Fixture matrix for renamed, removed, duplicate display-number, unavailable, newly added, partial-metadata, and out-of-order responses. UI tests that switch channels faster than metadata arrivals. Monitor only aggregate schema/field-presence changes, never the content itself.

**Phase to address:** **Catalog, metadata, favorites, and recents**, after the protocol seam but before public beta.

---

### Pitfall 6: Treating macOS media integration as a UI feature rather than a lifecycle owner

**Confidence:** HIGH for platform behavior. Apple says macOS media apps should register the shared remote command center, handle only desired commands, and receive external player events only after becoming Now Playing.

**What goes wrong:** Media keys/Control Center intermittently control the app, commands are registered more than once as windows appear, remote pause fails to update the compact player, Now Playing lies after a stall, or the app continues/restarts audio unexpectedly around sleep, device/output changes, and app termination.

**Why it happens:** Remote commands, Now Playing metadata, AVPlayer notifications, window lifetime, and app lifecycle are each implemented by separate views.

**How to avoid:** One app-lifetime `MediaSessionCoordinator` subscribes to playback state and owns `MPRemoteCommandCenter` registration/removal plus Now Playing updates. Enable only commands Sirius Mac can execute correctly for a live stream; return failures for inapplicable seek/skip operations. Update Now Playing only from confirmed player-state transitions, clear it on terminal stop, and ensure app quit/sleep/wake/output change route through the same playback controller. Keep this coordinator out of the reusable protocol library.

**Warning signs:** Command handlers are installed in `.onAppear`; remote command closures capture views; multiple observers accumulate after opening/closing the library window; “paused” is displayed while `AVPlayer` is waiting; quitting leaves a process/audio session alive.

**Detection:** An automated lifecycle harness plus manual release checklist: media keys, Control Center, fast user switching, close compact window, close library window, sleep/wake, Bluetooth/output changes, interruption by another media app, network loss, quit/relaunch. Assert exactly one active command handler set and a single current player generation.

**Phase to address:** **Playback core and macOS media integration**, before skin/performance work.

---

### Pitfall 7: Misusing Keychain or coupling secrets to a build/signing identity without migration planning

**Confidence:** HIGH for Keychain capability; MEDIUM for project-specific migration choices.

**What goes wrong:** Credentials live in `UserDefaults` or a local file; an update cannot read existing items after bundle/team/access-group changes; logout removes favorites but leaves a session; background refresh fails because accessibility was selected without lifecycle testing; a reinstall or signing change produces mysterious login loops.

**Why it happens:** Keychain is treated as an opaque key/value dictionary and only tested on the developer machine. Apple documents access control and item accessibility as deliberate choices, and distribution signing authorizes sensitive entitlement claims such as keychain access groups.

**How to avoid:** Wrap Keychain in a narrow `CredentialStore` protocol with item names/versioning, atomic replace/delete, and typed errors. Store minimum necessary credential/session material; do not synchronize or share it unless an explicit supported Apple-platform requirement demands it. Document the bundle ID, signing team, access group, and migration policy before a shipped beta. Design logout, authentication failure, account switch, and “clear local data” as separate, tested operations. Treat a Keychain-access failure as a user-visible reauthentication requirement—not a reason to persist a fallback copy.

**Warning signs:** `UserDefaults` contains auth values; keychain queries use broad/ambiguous matching; access group differs between debug/release; CI tests never exercise a clean login keychain; “reset” cannot state what it removes.

**Detection:** Clean-account, app-upgrade, account-switch, logout, locked-keychain, missing-item, and signing-identity migration tests on a separate macOS user. Release inspection verifies actual entitlements and contains no development-only access groups.

**Phase to address:** **Credential storage and release identity**, before external testing.

---

### Pitfall 8: Making user skins executable by accident or accepting hostile packages as ordinary assets

**Confidence:** HIGH for the risk; MEDIUM for implementation specifics.

**What goes wrong:** A “skin” can trigger scripts/web content, escape its package through `../` paths or symlinks, consume disk/memory via decompression or giant images, abuse malformed vector/image decoders, or override labels to impersonate trusted UI. This also conflicts with notarization/hardened-runtime assumptions if a plugin-like architecture emerges.

**Why it happens:** Skins begin as a convenience archive and rendering loads arbitrary paths/URLs or evaluates template logic. A developer validates only that a happy-path skin looks right.

**How to avoid:** Specify a small, versioned declarative manifest and allow-list only local, normalized resource identifiers, supported MIME/types, exact layout tokens, bounded dimensions, per-file/count/total compressed and expanded byte limits, and no URLs, scripts, custom fonts/code, symlinks, or runtime reflection. Parse and validate before extraction/rendering; extract to a unique temporary directory after canonical-path containment checks; render from an immutable validated model. Bundle first-party skins through normal app resources and treat external skin failures as nonfatal with safe fallback.

**Warning signs:** Manifest has arbitrary key/value passthrough; skin fields accept a URL; use of `URL(fileURLWithPath:)` with untrusted strings; archive extraction has no size/count limits; a skin controls action identifiers or window behavior beyond declared tokens.

**Detection:** Property/fuzz tests for malformed manifests; test corpus for traversal, absolute path, symlink, duplicate name, zip-bomb ratio, oversized image, unsupported media, unknown version, and accidental executable content. Inspect the final app to confirm no runtime code-loading entitlement/plugin mechanism was introduced for skins.

**Phase to address:** **Skin format, validator, and renderer**, before accepting community packages.

---

### Pitfall 9: Discovering supply-chain and distribution failures only after announcing a release

**Confidence:** HIGH for Apple/Homebrew distribution requirements.

**What goes wrong:** A release passes local launch but fails Gatekeeper/notarization, has an invalid nested signature or debug entitlement, ships a mutable asset that no longer matches its Cask SHA-256, or makes users trust an overly broad third-party Homebrew tap. A dependency update may silently add telemetry, incompatible entitlements, or malicious code.

**Why it happens:** “Archive succeeds” substitutes for delivered-artifact validation. Direct distribution, a reusable library, GitHub actions, and Homebrew introduce separate trust boundaries. Apple requires hardened runtime for notarization and calls for valid signatures/timestamps; Homebrew Casks require version, URL, SHA-256, and artifact stanzas and current nonofficial tap policy explicitly treats tap definitions as executable Ruby.

**How to avoid:** Use a release pipeline that starts from a clean, pinned Xcode/Swift/dependency resolution, generates SBOM/dependency review data, signs every nested executable with Developer ID and hardened runtime, submits with supported notarization tooling, staples/verifies the ticket, and publishes an immutable GitHub Release asset/checksum. Pin/approve dependencies and review updates; avoid binary dependencies unless their provenance/checksum and privacy manifests are verified. Own the initial tap, scope user trust to the Cask where possible, and run `brew audit` plus fresh-install/uninstall tests. Never store Apple signing/notary credentials in the repository or release asset.

**Warning signs:** Release is built from a dirty worktree; `get-task-allow` is present; a plugin/library-validation exception appears without a written need; Cask uses `:no_check` for a versioned artifact; the GitHub Release asset can be replaced; `Package.resolved` changes without review; release automation prints secrets.

**Detection:** CI gates on signature/entitlements/notary status/staple verification, checksum reproducibility, dependency diff and known-vulnerability review, secret scan, and a disposable-Mac/VM Gatekeeper + `brew install --cask` smoke test. Save only redacted notary logs and artifact attestations.

**Phase to address:** **Release engineering and supply-chain hardening**, begun early and completed before first public binary.

---

### Pitfall 10: Publishing a public integration without an operational/legal risk gate

**Confidence:** HIGH that the current SiriusXM Customer Agreement reserves broad restrictions and may alter service/access; this is not legal advice.

**What goes wrong:** The project markets itself as official, publishes protocol-repair detail or copyrighted/service-derived material unnecessarily, invites requests for recording/account-sharing/access-control workarounds, or keeps shipping after service terms or compatibility posture materially changes. A public repository amplifies takedown, account, and user-safety risk.

**Why it happens:** “Open source” is mistaken for permission, and technical interoperability is mistaken for a stable authorization. The current agreement states personal-use limits, prohibits manipulation/reverse engineering of service technology, prohibits compromising security, reserves the ability to change access/features, and says the posted agreement controls. Those facts require an explicit owner decision; they do not answer legal questions here.

**How to avoid:** Establish a pre-publication review with project owner/counsel as appropriate: naming/trademark/disclaimer review, contributor policy, issue/PR moderation policy, takedown/disable procedure, acceptable-use statement, and a release gate that verifies only authorized subscriber use and fail-closed behavior. Clearly state the app is independent/not affiliated, requires an eligible subscriber account, does not bypass protections, and may stop working. Reject/lock issues seeking CAPTCHA/MFA/DRM/device/geolocation/account-sharing bypasses, recording, or credential sharing; do not publish acquisition techniques or secret-bearing fixtures.

**Warning signs:** README calls the client “official” or promises permanent access; issues request a new device identity/limit workaround; repository includes service JavaScript dumps/keys or content catalog; release notes celebrate defeating an upstream control.

**Detection:** Maintainer release checklist and periodic terms/repository-policy review; automated scans for protected tokens/secrets; triage labels/reporting for prohibited requests; a tested remote configuration/kill-switch policy that only disables the app integration, not service safeguards.

**Phase to address:** **Public-project governance and beta readiness**, before opening the repository/releasing binaries.

---

### Pitfall 11: Turning privacy-safe observability into either blind operation or user surveillance

**Confidence:** HIGH for Apple logging/privacy-manifest requirements; MEDIUM for telemetry design choices.

**What goes wrong:** No diagnostics exist when an upstream drift occurs, so maintainers ask users for secret-bearing logs; or a “temporary analytics” SDK sends account-linked listening activity, channels, stream details, or stable device identifiers off-device without a documented basis.

**Why it happens:** Observability is added late, after code has inconsistent logs, or generic analytics is adopted without data inventory. The reusable library accidentally imports app analytics, contaminating every consumer. Apple’s privacy-manifest guidance makes data collection and third-party SDK behavior a package/release concern, not a marketing checkbox.

**How to avoid:** Make the library telemetry-free by default and expose an opt-in, caller-owned `DiagnosticsSink` carrying only structured safe events. For the app, default to local logs and user-initiated, redacted support export. If any remote error reporting is proposed, require a written data inventory, purpose, retention, vendor review, opt-in/consent decision, privacy-manifest assessment, and a separate product decision; do not send credentials, tokens, stream locators, raw metadata, account identifiers, or a listening history. Add privacy manifests correctly to framework/package resources where applicable.

**Warning signs:** A third-party telemetry SDK appears in the library target; event names include user/channel/song; an identifier is described as “anonymous” without rotation/retention; a privacy manifest is missing/mispackaged; remote reporting happens before user action.

**Detection:** Network tests that prove login/playback sends traffic only to SiriusXM unless the user explicitly activates support reporting; archive inspection for `PrivacyInfo.xcprivacy`; dependency/license/manifest review; a privacy test fixture that asserts secret fields cannot serialize into diagnostic payloads.

**Phase to address:** **Observability, privacy, and reusable-library packaging**, before beta.

---

### Pitfall 12: Treating protocol repair as an emergency code change instead of a maintained product capability

**Confidence:** MEDIUM.

**What goes wrong:** An upstream break triggers ad hoc reverse engineering, risky hotfixes, and users sharing credentials/logs in issues. The public library’s semantic versioning and app release become entangled; maintainers cannot tell whether a failure is auth, catalog, stream, player, or distribution.

**Why it happens:** There is no compatibility ownership, runbook, fixture update policy, release channel, or deprecation strategy. Tests only prove the last happy path.

**How to avoid:** Write and exercise a maintenance runbook: triage taxonomy; safety rules (never ask for passwords/tokens/raw requests); initial containment/kill-switch actions; repro with authorized test account; fixture sanitization/review; adapter-only repair; compatibility matrix; package semver/release notes; app pin/update policy; rollback; subscriber communication; and post-incident cleanup. Assign ownership and a time-bounded decision path for unsupported/upstream policy changes. Keep protocol fixtures private/sanitized as required and document what cannot be published.

**Warning signs:** Issues are the only incident tracker; no owner can name supported macOS/library/app versions; the app consumes an unbounded `main` package dependency; a hotfix changes both protocol and UI with no targeted tests; “send HAR/full logs” is the default support reply.

**Detection:** Tabletop drill before public beta: simulated schema drift, token failure, entitlement denial, metadata outage, bad skin, revoked signing certificate, and leaked-test-token report. Verify a maintainer can disable the affected feature, release/revert safely, and communicate without requesting secrets.

**Phase to address:** **Operations, release readiness, and ongoing maintenance**, before public launch and at every release.

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|---|---|---|---|
| Put upstream request/response logic in app views | Fast first demo | Every protocol drift becomes a UI rewrite and leaks into public API | Never |
| Save auth/session data in preferences or test JSON | Easy inspection | Plaintext leaks, migration debt, accidental commit | Never |
| Log full failed response/URL | Faster debugging | Permanent secret and account-data exposure | Never |
| Treat current stream URL as durable | Fewer resolver calls | Silent stalls and invalid recovery loops | Never |
| Make skin packages permissive archives | Easy creator onboarding | Code/path/resource attack surface and support burden | Never |
| Skip Gatekeeper/Cask clean-machine test | Faster release | Users become the distribution test suite | Never for public release |
| Delay a remote telemetry decision | Avoids policy work | Later secret-bearing support collection or accidental tracking | Only if diagnostics remain local-only and safe by design |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|---|---|---|
| SiriusXM compatibility adapter | Assume observed endpoints/schemas are a contract | Isolate, fixture-test, monitor coarse outcomes, fail closed on unknown security/access behavior |
| Subscriber auth | Retry or alter client claims on every failure | Typed auth states; bounded retry only for known transient failures; no bypass behavior |
| AVFoundation / `AVPlayer` | Drive UI from a button flag | Drive it from serialized player/recovery state plus item-generation checks |
| `MPRemoteCommandCenter` / Now Playing | Register handlers per view appearance | One app-lifetime coordinator, command allow-list, idempotent registration/removal |
| Keychain | Treat it as a generic cache | Narrow credential-store interface, minimum data, explicit logout/migration/accessibility tests |
| User skin files | Trust archive paths and file sizes | Validate manifest first, canonicalize/contain paths, enforce asset budgets, no executable/remote content |
| GitHub Releases / Homebrew | Upload a mutable artifact and update a Cask manually | Immutable signed/notarized asset, exact checksum, audit, fresh install, rollback procedure |

## Performance and Reliability Traps

| Trap | Symptoms | Prevention | When It Breaks |
|---|---|---|---|
| Unbounded metadata/image fetches on rapid browsing | Memory/network churn, stale artwork | Cancel by channel/generation, cache with size/TTL, decode off main actor | Immediately with fast channel browsing or poor network |
| Multiple player/observer generations | Duplicate audio, crashed KVO callbacks, wrong Now Playing | Single owner actor; cancel/replace atomically; observer lifecycle tests | First rapid channel switch/sleep-wake |
| Infinite recovery/re-auth retry | Battery/network churn, accidental account stress, UI appears hung | Failure classification, bounded backoff, explicit user action | First long outage or expired session |
| Unbounded skin archives/assets | Hangs, disk pressure, render crash | Compressed/expanded byte, count, dimension, and decode-time budgets | First malicious or merely huge community skin |
| Full raw diagnostics | Huge artifacts and privacy incident | Structured allow-listed events, support-bundle budget | First upstream failure users report publicly |

## Security and Privacy Mistakes

| Mistake | Risk | Prevention |
|---|---|---|
| Credentials/tokens leave direct SiriusXM requests | Third-party exposure and account compromise | Architecture test/network allow-list; no proxy/analytics in library auth path |
| Raw transport errors become public diagnostics | Token/account/stream leakage | Safe diagnostic schema, explicit private logging, canary secret tests |
| Unknown auth/access-control behavior is “worked around” | Account/service-policy and security risk | Fail closed; direct the user to official resolution; prohibit bypass contributions |
| Keychain fallback to disk/preferences | Recoverable auth failure becomes durable disclosure | No fallback secret storage; typed reauthentication error |
| Skin archive trusts paths, symlinks, or unlimited assets | Local file overwrite/read or resource exhaustion | Declarative allow-list + containment and resource limits |
| Dependency/release automation is unreviewed | Supply-chain compromise or broken public binary | Lock/pin/review dependencies, least-privilege CI, signing/notary/cask verification |
| Remote telemetry carries listening/account data | Privacy harm and reusable-library contamination | Local-first diagnostics, opt-in only after data review, privacy manifest validation |

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---|---|---|
| Call every failure “network error” | User cannot fix password, entitlement, service change, or offline state | Distinguish safe, actionable categories without exposing upstream detail |
| Show Play while player is resolving/waiting/stalled | User thinks audio works when it does not | Present explicit resolving/buffering/recovering state and retry action |
| Let stale metadata overwrite current selection | Wrong artwork/title erodes trust | Gate all async updates by stable identity and generation |
| Remote controls behave differently from the UI | Media keys feel unreliable | Route both through the same playback intents/state machine |
| Reject a bad skin by crashing or silently falling back | Creators/users cannot diagnose package issue | Nonfatal validation report, retain built-in skin, clear safe error |
| Ask users to paste logs/raw requests into GitHub | Turns help into a privacy incident | Safe local support export and documented redaction guidance |

## "Looks Done But Isn't" Checklist

- [ ] **Authentication:** Every auth/entitlement/challenge state is typed, fail-closed, and tested; no credentials or session strings are logged, stored outside Keychain, or sent to any non-SiriusXM host.
- [ ] **Reusable library:** Public API contains domain models/errors only; protocol constants/decoders are internal, documented, semantically versioned, and contract-tested with sanitized fixtures.
- [ ] **Playback:** Stream expiry/stall/recovery, rapid channel changes, sleep/wake, output change, offline/online, and cancellation have deterministic tests and one authoritative state machine.
- [ ] **Metadata/favorites:** Removed/renamed/partial/out-of-order data cannot crash, mislabel the active channel, or make saved channels irrecoverable.
- [ ] **macOS integration:** Exactly one command-center registration exists, inappropriate live-stream commands are disabled, and Now Playing follows confirmed playback—not UI intent.
- [ ] **Skins:** Manifest, paths, symlinks, unknown fields, archive expansion, asset dimensions/types/counts, and renderer failures are validated/fuzzed; no executable/remote behavior exists.
- [ ] **Diagnostics:** Canary secrets cannot escape unified logs, crash reports, fixtures, CI artifacts, support bundles, Git history, or issue templates.
- [ ] **Release:** The exact GitHub artifact is Developer-ID signed, hardened, notarized, stapled, Gatekeeper-tested, checksum-pinned in Cask, audited, and fresh-installed from an isolated environment.
- [ ] **Public operation:** README/repo policy does not imply affiliation or authorization; prohibited bypass/recording/account-sharing requests have a moderation response; incident runbook was exercised.

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---|---|---|
| Upstream schema/auth drift | MEDIUM–HIGH | Disable affected capability; classify with safe telemetry; reproduce only with authorized test account; patch adapter/fixtures; ship library then app update; publish safe status note |
| Stream expiry/stall loop | MEDIUM | Stop stale generation; retain channel selection; one bounded re-resolve if eligible; show user retry; investigate coarse failure class |
| Secret committed/logged | HIGH | Immediately revoke/rotate affected account/session/release credential; remove public artifact and invalidate CI outputs; assess history/caches; notify affected owner; add regression scanner/test |
| Malicious/broken skin | LOW–MEDIUM | Reject/quarantine package, retain bundled skin, capture only validation code, tighten validator/test corpus, publish safe creator guidance |
| Notarization/Cask release failure | MEDIUM | Withdraw bad asset/cask update, inspect redacted notary/audit output, fix signing/package pipeline, cut immutable replacement, test clean install before reannounce |
| Terms/policy or maintainer-risk change | HIGH | Pause public distribution/integration if needed; obtain owner/counsel direction; communicate scope change; do not attempt technical circumvention |

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---|---|---|
| Protocol volatility and schema drift | Protocol foundation / reusable-library seam | Contract fixtures, adapter-only integration test, scheduled coarse smoke check |
| Auth, session, entitlement boundaries | Credential/authentication boundary | State-machine tests; network allow-list; unknown-control cases make no workaround request |
| Secrets in logs/tests/issues | Security and observability baseline | Canary-token test; CI/repo/artifact secret scan; safe support-bundle review |
| Stream expiry and player race conditions | Playback core/recovery | Fake-clock expiry, stall, cancellation, rapid-switch, offline and wake tests |
| Metadata/catalog drift | Catalog/favorites/recents | Identity/reconciliation fixture matrix and out-of-order UI tests |
| Media keys/Now Playing/lifecycle | macOS media integration | Manual lifecycle matrix plus one handler/generation instrumentation assertion |
| Keychain update/logout behavior | Credential storage and release identity | Clean user, upgrade, sign-identity, account-switch, logout and missing-item tests |
| Declarative skin safety | Skin format/validator/renderer | Fuzz/corpus validation; asset budget tests; no script/URL/plugin capability review |
| Supply chain, signing, notarization, Cask | Release engineering | CI signed/notarized/stapled/Gatekeeper/audit/fresh-Cask install gates |
| Public-project/ToS risk | Governance and beta readiness | Owner review, disclaimer/policy review, prohibited-request moderation procedure |
| Privacy/telemetry and runbooks | Operations/readiness | Network/privacy-manifest tests and tabletop incident drill |

## Sources

Primary sources (current pages checked 2026-08-16):

- [Apple: Keychain services](https://developer.apple.com/documentation/security/keychain-services) and [restricting Keychain item accessibility](https://developer.apple.com/documentation/security/restricting-keychain-item-accessibility) — HIGH confidence for Keychain storage/accessibility concepts.
- [Apple: `AVPlayer`](https://developer.apple.com/documentation/avfoundation/avplayer), [playback stalled notification](https://developer.apple.com/documentation/avfoundation/avplayeritem/playbackstallednotification), and [handling external player events](https://developer.apple.com/documentation/mediaplayer/handling-external-player-events-notifications) — HIGH confidence for player/remote-command lifecycle concepts.
- [Apple: unified `Logger`](https://developer.apple.com/documentation/os/logger) and [generating log messages](https://developer.apple.com/documentation/os/generating-log-messages-from-your-code) — HIGH confidence for logging privacy guidance.
- [Apple: privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files) and [adding a privacy manifest to an app or third-party SDK](https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk) — HIGH confidence for package/framework privacy-manifest packaging.
- [Apple: notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution), [Hardened Runtime](https://developer.apple.com/documentation/security/hardened-runtime), and [creating distribution-signed macOS code](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac) — HIGH confidence for direct-distribution requirements.
- [Apple: Swift package binary-target checksum](https://developer.apple.com/documentation/packagedescription/target/checksum) — HIGH confidence for remote binary checksum behavior.
- [Homebrew: Cask Cookbook](https://docs.brew.sh/Cask-Cookbook) and [Tap Trust](https://github.com/Homebrew/brew/blob/main/docs/Tap-Trust.md) — HIGH confidence for Cask artifact/checksum and current third-party-tap trust considerations.
- [SiriusXM Customer Agreement](https://www.siriusxm.com/customer-agreement) — HIGH confidence that current published terms contain broad service/technology, personal-use, and access-change language; implications for this project require owner/counsel review, not an automated legal conclusion.
- [Public `sxm-client` source documentation](https://sxm-client.readthedocs.io/en/stable/_modules/sxm/client.html) — LOW confidence, unendorsed interoperability context only; used to justify treating all observed protocol/session details as volatile and potentially sensitive, not as implementation instructions.

---

*Pitfalls research for: Sirius Mac authorized-subscriber live SiriusXM player and reusable Apple-platform library*
*Researched: 2026-08-16*
