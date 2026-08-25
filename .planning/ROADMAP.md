# Roadmap: Sirius Mac

## Overview

Sirius Mac moves from a settled authentication architecture to a dependable native live-radio experience, then completes its distinctive declarative skinning and public release path. The production authentication baseline is fixed: a user-operated, nonpersistent WKWebView yields one current first-party `AUTH_TOKEN`; its access token crosses once in volatile memory into `SiriusXMClient`, which performs native authenticated and entitlement requests. SiriusXM protocol behavior remains repairable behind the reusable client boundary.

## Phases

**Phase Numbering:**

- Phase 0: prerequisite feasibility work that must finish before product implementation
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 0: Authentication Feasibility Gate** - Historical feasibility work that informed the accepted WebView-token/native-request architecture.
- [x] **Phase 1: Safe Interoperability Foundation** - Subscribers get a fail-closed, private authorization foundation and a reusable client boundary. (completed 2026-08-18)
- [x] **Phase 2: Authorized Live Listening** - Subscribers can browse entitled linear channels and listen reliably with truthful playback and metadata states. (completed 2026-08-20)
- [x] **Phase 3: Native Mac Listening Experience** - Subscribers control one shared listening session through native windows, local library features, and macOS media controls. (completed 2026-08-24)
- [ ] **Phase 4: Safe Skins & Accessible Recovery** - Subscribers can personalize the player with bundled or validated local skins without compromising safety or access.
- [ ] **Phase 5: Public Release & Compatibility Support** - Subscribers can install trusted public releases and receive privacy-safe compatibility help.

## Phase Details

### Phase 0: Authentication Feasibility Gate

**Goal**: Preserve the historical feasibility work that led to the accepted WebView-token/native-request production architecture.
**Mode:** mvp
**Depends on**: Nothing
**Requirements**: FEAS-01, FEAS-02, FEAS-03, FEAS-04, FEAS-05
**Historical Success Criteria** (retained for provenance; no item gates Phase 1):

  1. Public first-party evidence and a bounded account-owner check either establish a clean app-bound browser return or rule it out without reading authenticated browser state.
  2. Only when browser return is ruled out, a minimal honest native path is evaluated without browser/client spoofing, alternate methods, automatic retry, or access-control workarounds.
  3. A supported candidate completes two separate account-owner initiated sign-in → authenticated-and-entitled → clean sign-out runs, with one attempt in flight and a conservative human-controlled cooldown.
  4. Every protected, challenged, rate-limited, redirected, suspicious, or ambiguous outcome stops immediately, retains no secret evidence, and produces `NO-GO unsupported`.
  5. The historical harness recorded a sanitized feasibility decision; that artifact now has no authority over Phase 1 execution.

**Plans**: 12/12 plans executed

Plans:

- [x] 00-14-PLAN.md
- [x] 00-15-PLAN.md
- [x] 00-16-PLAN.md

**Wave 1**

- [x] 00-05-PLAN.md — Establish the safe terminal tracer, exact toolchain preflight, and canonical empirical proof contract.

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 00-06-PLAN.md — Define and enforce the public-first-party provider contract for browser and conditional native qualification.

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 00-07-PLAN.md — Resolve the public provider contract and obtain digest-bound owner approval or close unsupported.

**Wave 4** *(blocked on Wave 3 completion)*

- [x] 00-08-PLAN.md — Build the qualified app-bound browser-return construction and semantic handoff.

**Wave 5** *(blocked on Wave 4 completion)*

- [x] 00-09-PLAN.md — Complete bounded playback, renewal, sign-out, cleanup, and synthetic browser preflight.

**Wave 6** *(blocked on Wave 5 completion)*

- [x] 00-10-PLAN.md — Run the owner-controlled browser proof and decide whether the qualified native boundary may be exposed.

**Wave 7** *(blocked on Wave 6 completion)*

- [x] 00-11-PLAN.md — Enforce one-live-path replacement and conditionally compose the approved native-direct runtime.

**Wave 8** *(blocked on Wave 7 completion)*

- [x] 00-12-PLAN.md — Close the ineligible native branch or run the owner-controlled native proof.

**Wave 9** *(blocked on Wave 8 completion)*

- [x] 00-13-PLAN.md — Atomically regenerate and validate the canonical Phase 0 quartet and enforce the Phase 1 gate.

**Historical execution note:** Phase 0 artifacts and harness code are retained as implementation reference and review evidence only. On 2026-08-17 the owner settled the production architecture as WKWebView token extraction followed by native authenticated requests. No Phase 0 evidence/selection/owner-result/decision artifact, GO string, or proof-run command authorizes or blocks Phase 1.

**Scope fence:** Phase 0 may create only a minimal isolated feasibility harness and sanitized evidence contract. It does not build the production app shell, public client API, Keychain persistence, catalog, playback, skins, or release infrastructure.

### Phase 1: Safe Interoperability Foundation

**Goal**: As a SiriusXM subscriber, I want to establish or end an authorized session, so that I can listen safely on my Mac.
**Mode:** mvp
**Depends on**: None — the authentication architecture is already settled and recorded here.
**Requirements**: AUTH-01, AUTH-02, AUTH-03, SECR-01, SECR-02, SECR-03, CLNT-01, CLNT-02, CLNT-03, CLNT-04
**Success Criteria** (what must be TRUE):

  1. A subscriber can sign in through the app's nonpersistent WKWebView; after explicit user confirmation, the app extracts exactly one current first-party `AUTH_TOKEN`, decodes only `session.accessToken`, and transfers it once in volatile memory to the client.
  2. When the authorized flow is unknown, changed, or requires a prohibited access-control workaround, the subscriber receives an explicit unsupported result and the attempt stops without a bypass.
  3. Authentication success is created only by a runtime-owned native sequence that verifies the token, confirms entitlement, and atomically activates session state; caller-authored success claims and planning artifacts cannot create an authenticated session.
  4. A subscriber can sign out, after which actor-held session material, Keychain material, and every cookie matching the exact extraction predicate across accepted SiriusXM domains are cleared or cleanup failure is reported explicitly.
  5. Subscriber credentials are Keychain-backed, session and resolved-stream data are ephemeral and direct-to-SiriusXM only, and no secret or raw sensitive response appears in diagnostics, fixtures, tests, or local app data.
  6. A native Apple-platform developer can consume the `SiriusXMClient` SwiftPM product and use typed async capabilities without depending on SiriusXM endpoints, cookies, headers, or raw schemas.
  7. Deterministic WebView-bridge, native-authentication, entitlement, sign-out, and redaction tests always compile and run independently of mutable `.planning` artifacts.

**Plans**: 16/16 plans executed

**Execution baseline:** Phase 1 consumes the settled WKWebView-token/native-request architecture directly. Do not run authentication feasibility experiments, regenerate a Phase 0 quartet, inspect GO/NO-GO artifacts, or request duplicate owner proof runs. Phase 0 review findings are production acceptance requirements in Plans 01-02, 01-06, 01-07, and 01-08.

Plans:
**Wave 1**

- [x] 01-01-PLAN.md — Build the native app-to-client walking skeleton and public SwiftPM boundary without a Phase 0 gate.

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 01-02-PLAN.md — Build runtime-owned authentication/entitlement classification and one-attempt session state.
- [x] 01-03-PLAN.md — Enforce ephemeral native authenticated transport and redaction-by-construction.

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 01-04-PLAN.md — Add app-owned Keychain lifecycle and memory-first sign-out.
- [x] 01-05-PLAN.md — Deliver the typed native sign-in, unsupported, entitlement, and cleanup experience.

**Wave 4** *(blocked on Wave 3 completion)*

- [x] 01-06-PLAN.md — Productionize the nonpersistent WKWebView token bridge and symmetric cookie cleanup.

**Wave 5** *(blocked on Wave 4 completion)*

- [x] 01-07-PLAN.md — Compose WebView token extraction with native authentication and entitlement requests.

**Wave 6** *(blocked on Wave 5 completion)*

- [x] 01-08-PLAN.md — Close the Phase 0 review regressions with production acceptance and record Phase 2 readiness.

**Wave 7** *(blocked on Wave 6 completion)*

- [x] 01-09-PLAN.md — Restore explicit WebView retry and re-login while preserving one credential transfer per attempt.

**Wave 8** *(blocked on Wave 7 completion)*

- [x] 01-10-PLAN.md — Make Keychain and browser-residue cleanup reachable after a fresh app composition.

**Wave 9** *(blocked on Wave 8 completion)*

- [x] 01-11-PLAN.md — Consolidate the detached Xcode test graph while preserving the active SiriusMacTests target.

**Wave 10** *(blocked on Wave 9 completion)*

- [x] 01-12-PLAN.md — Make WebView credential selection atomic across suspension and prove exactly one transfer under concurrent explicit selections.

**Wave 11** *(blocked on Wave 10 completion)*

- [x] 01-13-PLAN.md — Decode representative profile/subscription responses and prove the complete native authorization transaction.
- [x] 01-14-PLAN.md — Instrument the production redirect callback and prove every follow-up request is cancelled.
- [x] 01-15-PLAN.md — Enforce the Secure evidence-backed cookie predicate and retire the complete nonpersistent WebKit session.

**Wave 12** *(blocked on Wave 11 completion)*

- [x] 01-16-PLAN.md — Restore bounded Keychain material through the same native transaction and erase every invalid or rejected restore.

### Phase 2: Authorized Live Listening

**Goal**: Subscribers can find their entitled linear SiriusXM channels and reliably listen to one live stream with clear state and current metadata.
**Mode:** mvp
**Depends on**: Phase 1
**Requirements**: CAT-01, CAT-02, CAT-03, PLAY-01, PLAY-02, PLAY-03, PLAY-04, META-01, META-02
**Success Criteria** (what must be TRUE):

  1. A subscriber can refresh and browse only their entitled standard and app-only `channel-linear` lineup, with each channel's identity, available presentation details, entitlement, and freshness visible.
  2. A subscriber can tune an entitled linear channel and start, pause, resume, or stop its live stream.
  3. Catalog, authorization, entitlement, stream-resolution, network, decoder, buffering, and unsupported-upstream failures remain distinct and actionable; cached channel presence never implies playback authorization.
  4. Recoverable stream expiry, network interruption, sleep/wake, and stalls make bounded, cancellation-aware recovery attempts without infinite retry or synthesized listener activity.
  5. While listening, a subscriber sees the active channel, best available artwork, and current program or song text; unavailable or stale metadata is explicit and does not interrupt healthy audio.

**Plans**: 18/18 plans executed

- [x] 02-08-PLAN.md
- [x] 02-09-PLAN.md
- [x] 02-10-PLAN.md
- [x] 02-11-PLAN.md

**Wave 1 — Provider-agnostic Validation Wave 0**

- [x] 02-01-PLAN.md — Create all four offline contract suites and reversible semantic app seams without live provider work.

**Wave 2 — Owner-visible live gate** *(completed: sanitized supported provider contract; AVFoundation verification deferred to Wave 5)*

- [x] 02-02-PLAN.md — Run the first bounded authenticated provider/AVFoundation checkpoint and record sanitized supported or unsupported evidence.

**Wave 3 — Evidence-backed compatibility contract** *(ready)*

- [x] 02-03-PLAN.md — Resolve the research questions and encode only supported fixed operations, strict decoders, and the ephemeral media handoff.

**Wave 4 — Entitled catalog** *(depends on Wave 3)*

- [x] 02-04-PLAN.md — Deliver the deterministic freshness-aware entitled linear lineup and native selection surface.

**Wave 5 — Confirmed live playback** *(depends on Wave 4; performs the required native AVFoundation verification)*

- [x] 02-05-PLAN.md — Resolve a selected channel through current authorization and control one confirmed AVFoundation player.

**Wave 6 — Bounded recovery** *(blocked on Wave 5)*

- [x] 02-06-PLAN.md — Add cancellation-safe same-channel recovery with finite incident budgets and distinct failures.

**Wave 7 — Independent metadata** *(blocked on Wave 6)*

- [x] 02-07-PLAN.md — Present current text/artwork with independent fresh, stale, and unavailable states.

**Wave 11 — Offline auth and launcher gaps** *(depends on completed Plan 02-11)*

- [x] 02-12-PLAN.md — Make native auth stages and persistence truthfully diagnosable with a synthetic package matrix.
- [x] 02-15-PLAN.md — Enforce one exact telemetry-first SiriusMac process through a tested atomic launcher.

**Wave 12 — Native auth presentation and fresh WebView** *(depends on Plan 02-12)*

- [x] 02-13-PLAN.md — Complete the no-host auth matrix and wire fixed local/web/native/persistence/restore states.

**Wave 13 — Session cleanup blocker closure** *(depends on Plans 02-13 and 02-15)*

- [x] 02-14-PLAN.md — Serialize explicit cleanup before later authentication so a new credential survives.

**Wave 14 — Authentication-only live checkpoint** *(depends on Plans 02-14 and 02-15; halts Phase 02 unless durable authentication succeeds)*

- [x] 02-17-PLAN.md — Run one owner-authorized fresh sign-in/handoff and prove native authentication, entitlement, and credential persistence without listening work.

**Wave 15 — Playback blocker closure** *(depends on successful Plan 02-17)*

- [x] 02-16-PLAN.md — Handle already-ready AVFoundation items and repair the dangling Xcode test reference offline with zero app-host leakage.

**Wave 16 — Automatic restore and listening checkpoint** *(depends on successful Plans 02-17 and 02-16; no second login)*

- [x] 02-18-PLAN.md — Run one separately authorized exact-build relaunch, prove automatic restoration, then exercise one bounded listening and current-metadata path.

### Phase 3: Native Mac Listening Experience

**Goal**: Subscribers can use a cohesive native macOS player and library while one shared playback session continues correctly across app and system control surfaces.
**Mode:** mvp
**Depends on**: Phase 2
**Requirements**: LIBR-01, LIBR-02, LIBR-03, MAC-01, MAC-02, MAC-03, MAC-04, UI-01, UI-02, UI-03, UI-04, ACCS-01
**Success Criteria** (what must be TRUE):

  1. A subscriber can use one compact player window to see channel identity, current metadata, favorite state, and primary live-playback controls.
  2. A subscriber can use a separate native library window to browse entitled channels and categories and reach favorites and recents.
  3. Compact and library windows display the same session and playback state; opening or closing either never creates another player or interrupts healthy audio, and previous/next navigation selects a deterministic entitled channel and reveals it in the library.
  4. A subscriber can add or remove favorites and return to an ordered list of successfully tuned recent channels, with neither feature retaining credentials, session material, or stream URLs.
  5. Audio continues while backgrounded or with the library closed; media keys and system Now Playing reflect confirmed player and metadata state, system routing works normally, and essential player/library actions remain keyboard- and VoiceOver-usable.

**Plans**: 9/9 plans executed

Plans:
**Wave 1**

- [x] 03-01-PLAN.md — Prove one app-owned listening session across singleton compact and library surfaces.

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 03-02-PLAN.md — Add secret-safe shared favorites and confirmed-listen recents.

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 03-03-PLAN.md — Deliver the four-tab native library, captured queue, and reveal flow.

**Wave 4** *(blocked on Wave 3 completion)*

- [x] 03-04-PLAN.md — Build the fixed compact player and renderer-independent semantic style seam.

**Wave 5** *(blocked on Wave 4 completion)*

- [x] 03-05-PLAN.md — Enforce native window lifecycle, frame restoration, and Always on Top.

**Wave 6** *(blocked on Wave 5 completion)*

- [x] 03-06-PLAN.md — Route confirmed playback through macOS media keys and Now Playing.

**Wave 7** *(blocked on Wave 6 completion)*

- [x] 03-07-PLAN.md — Complete keyboard, menu, focus, VoiceOver, announcements, and Reduce Motion.

**Wave 8** *(blocked on Wave 7 completion)*

- [x] 03-08-PLAN.md — Verify native windows, system media, audio routing, rendered states, and accessibility.

**Wave 9 — UAT gap closure** *(blocked on Wave 8 completion)*

- [x] 03-09-PLAN.md — Fix compact-window excess chrome and delayed library selection with credential-free launched-app UI automation.

**UI hint**: yes

### Phase 4: Safe Skins & Accessible Recovery

**Goal**: Subscribers can give the player a nostalgic local appearance while every skin remains declarative, bounded, accessible, and recoverable.
**Mode:** mvp
**Depends on**: Phase 3
**Requirements**: ACCS-02, SKIN-01, SKIN-02, SKIN-03, SKIN-04, SKIN-05
**Success Criteria** (what must be TRUE):

  1. A subscriber can choose between at least two complete, tested bundled player skins.
  2. A subscriber can import, validate, select, and remove a local user-created package that consists only of versioned declarative data and local assets.
  3. A package that attempts executable code, remote content, active URLs, arbitrary-file access, or control of networking, playback, authentication, persistence, or accessibility semantics is rejected without altering the player.
  4. A package with an unknown schema, unsafe/traversal/symlink path, disallowed file type, or excessive file, archive, decoded-asset, image, or processing budget is rejected safely.
  5. A failed or invalid skin preserves the prior valid appearance and offers a built-in recovery path; custom appearance cannot remove semantic controls, usable hit targets, readable focus/state indicators, or the unskinned native fallback.

**Plans**: 1/3 plans executed

Plans:

**Wave 1**

- [x] 04-01-PLAN.md — Deliver the selected-appearance tracer, metadata-only persistence, permanent Native fallback, and two bundled skins through one closed renderer contract.

**Wave 2** *(blocked on Wave 1 completion)*

- [ ] 04-02-PLAN.md — Import hostile local `.siriusskin` packages through strict archive, path, manifest, image, budget, cancellation, and atomic managed-storage validation.

**Wave 3** *(blocked on Wave 2 completion)*

- [ ] 04-03-PLAN.md — Complete accessible appearance management, safe imported-skin removal, and package-independent Player-menu Native recovery.

**UI hint**: yes

### Phase 5: Public Release & Compatibility Support

**Goal**: Subscribers and Apple-platform developers can use a maintained, diagnosable client and install a trusted public Sirius Mac release.
**Mode:** mvp
**Depends on**: Phase 4
**Requirements**: CLNT-05, COMP-01, COMP-02, REL-01, REL-02, REL-03
**Success Criteria** (what must be TRUE):

  1. An Apple-platform developer can consult the public library's DocC documentation, semantic-versioning policy, sanitized contract fixtures, compatibility tests, and adapter-repair runbook when integrating or maintaining it.
  2. A subscriber can open a compatibility view that identifies whether authentication, entitlement, catalog, stream resolution, metadata, or playback is currently failing.
  3. A subscriber can explicitly review and export a support bundle containing only app/library versions and allow-listed diagnostic classifications, with no secrets or raw upstream payloads.
  4. A subscriber can download an immutable GitHub Release artifact that is hardened, Developer-ID-signed, notarized, stapled, checksummed, and verified by Gatekeeper on a clean Mac.
  5. A subscriber can install or upgrade the canonical immutable release through the project-owned Homebrew Cask and receives a passive update notice that directs Homebrew installations to `brew upgrade` without in-app downloading or installation.

**Plans**: TBD
**UI hint**: yes

## Progress

**Execution Order:**
Active product execution proceeds 1 → 2 → 3 → 4 → 5. Phase 0 is retained historical work, not an execution dependency.

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 0. Authentication Feasibility Gate | 12/12 | Complete (historical) | 2026-08-17 |
| 1. Safe Interoperability Foundation | 16/16 | Complete    | 2026-08-18 |
| 2. Authorized Live Listening | 18/18 | Complete    | 2026-08-20 |
| 3. Native Mac Listening Experience | 8/8 | In Progress|  |
| 4. Safe Skins & Accessible Recovery | 1/3 | In Progress|  |
| 5. Public Release & Compatibility Support | 0/TBD | Not started | - |
