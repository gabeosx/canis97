# Roadmap: Sirius Mac

## Overview

Sirius Mac moves from a safe, repairable proof of authorized SiriusXM interoperability to a dependable native live-radio experience, then completes its distinctive declarative skinning and public release path. Each phase preserves the central boundary: SiriusXM protocol behavior can change behind the reusable client library, while the Mac app remains secure, native, and clear about unsupported upstream conditions.

## Phases

**Phase Numbering:**

- Phase 0: prerequisite feasibility work that must finish before product implementation
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 0: Authentication Feasibility Gate** - Maintainers obtain a safe, evidence-backed GO or NO-GO decision before production investment.
- [ ] **Phase 1: Safe Interoperability Foundation** - Subscribers get a fail-closed, private authorization foundation and a reusable client boundary.
- [ ] **Phase 2: Authorized Live Listening** - Subscribers can browse entitled linear channels and listen reliably with truthful playback and metadata states.
- [ ] **Phase 3: Native Mac Listening Experience** - Subscribers control one shared listening session through native windows, local library features, and macOS media controls.
- [ ] **Phase 4: Safe Skins & Accessible Recovery** - Subscribers can personalize the player with bundled or validated local skins without compromising safety or access.
- [ ] **Phase 5: Public Release & Compatibility Support** - Subscribers can install trusted public releases and receive privacy-safe compatibility help.

## Phase Details

### Phase 0: Authentication Feasibility Gate

**Goal**: Determine whether exactly one safe SiriusXM authentication path can complete two account-owner authorized-and-entitled proof runs with clean sign-out, before building the production application foundation.
**Mode:** mvp
**Depends on**: Nothing (prerequisite phase)
**Requirements**: FEAS-01, FEAS-02, FEAS-03, FEAS-04, FEAS-05
**Success Criteria** (what must be TRUE):

  1. Public first-party evidence and a bounded account-owner check either establish a clean app-bound browser return or rule it out without reading authenticated browser state.
  2. Only when browser return is ruled out, a minimal honest native path is evaluated without browser/client spoofing, alternate methods, automatic retry, or access-control workarounds.
  3. A supported candidate completes two separate account-owner initiated sign-in → authenticated-and-entitled → clean sign-out runs, with one attempt in flight and a conservative human-controlled cooldown.
  4. Every protected, challenged, rate-limited, redirected, suspicious, or ambiguous outcome stops immediately, retains no secret evidence, and produces `NO-GO unsupported`.
  5. A sanitized feasibility artifact contains exactly one decision: `GO browser-return`, `GO native-direct`, or `NO-GO unsupported`; only a GO decision permits Phase 1 execution.

**Plans**: 11/12 plans executed

Plans:

- [x] 00-14-PLAN.md
- [x] 00-15-PLAN.md
- [ ] 00-16-PLAN.md

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

**Historical execution note:** The user selected replan-from-scratch on 2026-08-17. Plans and summaries 00-01 through 00-04 remain immutable historical records only and are not the active inventory. See `00-SUPERSESSION.md`; Plans 00-05 through 00-13 are the sole active replacement set, and Phase 1 remains blocked until their finalization contract succeeds.

**Scope fence:** Phase 0 may create only a minimal isolated feasibility harness and sanitized evidence contract. It does not build the production app shell, public client API, Keychain persistence, catalog, playback, skins, or release infrastructure.

### Phase 1: Safe Interoperability Foundation

**Goal**: Subscribers can establish or end an authorized SiriusXM session without exposing secrets or weakening access controls, through a reusable Apple-platform client boundary.
**Mode:** mvp
**Depends on**: Phase 0 (GO result required)
**Requirements**: AUTH-01, AUTH-02, AUTH-03, SECR-01, SECR-02, SECR-03, CLNT-01, CLNT-02, CLNT-03, CLNT-04
**Success Criteria** (what must be TRUE):

  1. A subscriber can sign in directly to SiriusXM and receives an explicit success, rejection, challenge, unsupported-flow, or entitlement outcome.
  2. When the authorized flow is unknown, changed, or requires a prohibited access-control workaround, the subscriber receives an explicit unsupported result and the attempt stops without a bypass.
  3. A subscriber can sign out, after which active session material and stored SiriusXM credentials are cleared.
  4. Subscriber credentials are Keychain-backed, session and resolved-stream data are ephemeral and direct-to-SiriusXM only, and no secret or raw sensitive response appears in diagnostics, fixtures, tests, or local app data.
  5. A native Apple-platform developer can consume the `SiriusXMClient` SwiftPM product and use typed async capabilities without depending on SiriusXM endpoints, cookies, headers, or raw schemas.

**Plans**: 8 plans

**Execution gate:** Do not execute any Phase 1 plan unless Phase 0 completed with `GO browser-return` or `GO native-direct` after both required proof runs. A `NO-GO unsupported` result ends production implementation. Existing Phase 1 plans are preserved but must consume the Phase 0 decision rather than repeat feasibility work.

Plans:
**Wave 1**

- [ ] 01-01-PLAN.md — Prove the native app-to-client compatibility tracer and public SwiftPM boundary.

**Wave 2** *(blocked on Wave 1 completion)*

- [ ] 01-02-PLAN.md — Build fail-closed semantic classification and one-attempt session state.
- [ ] 01-03-PLAN.md — Enforce ephemeral direct-host transport and redaction-by-construction.

**Wave 3** *(blocked on Wave 2 completion)*

- [ ] 01-04-PLAN.md — Add app-owned Keychain lifecycle and memory-first sign-out.
- [ ] 01-05-PLAN.md — Deliver the complete native unsupported-authentication experience.

**Wave 4** *(blocked on Wave 3 completion)*

- [ ] 01-06-PLAN.md — Revalidate and consume the sole Phase 0 GO path without repeating feasibility or live proof.

**Wave 5** *(blocked on Wave 4 completion)*

- [ ] 01-07-PLAN.md — Implement only the recorded selected result or the no-live-adapter unsupported state.

**Wave 6** *(blocked on Wave 5 completion)*

- [ ] 01-08-PLAN.md — Complete production synthetic authentication/cleanup acceptance and record Phase 2 readiness without repeating live proof.

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

**Plans**: TBD

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

**Plans**: TBD
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

**Plans**: TBD
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
Phases execute in numeric order: 0 → 1 → 2 → 3 → 4 → 5

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 0. Authentication Feasibility Gate | 11/12 | In Progress|  |
| 1. Safe Interoperability Foundation | 0/8 | Not started | - |
| 2. Authorized Live Listening | 0/TBD | Not started | - |
| 3. Native Mac Listening Experience | 0/TBD | Not started | - |
| 4. Safe Skins & Accessible Recovery | 0/TBD | Not started | - |
| 5. Public Release & Compatibility Support | 0/TBD | Not started | - |
