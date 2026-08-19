---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
current_phase: 02
current_phase_name: Authorized Live Listening
status: blocked
stopped_at: "Halted 02-02-PLAN.md: unknown-contract blocks provider-dependent plans"
last_updated: "2026-08-19T13:01:50.987Z"
last_activity: 2026-08-18
last_activity_desc: Accepted Phase 1 verification-staleness exception after 40/40 UAT and advanced to Phase 2
progress:
  total_phases: 3
  completed_phases: 2
  total_plans: 35
  completed_plans: 30
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-08-18)

**Core value:** Subscribers can reliably start and control a live SiriusXM stream from a delightful native Mac player, even as the unsupported SiriusXM integration evolves underneath it.
**Current focus:** Phase 02 — Authorized Live Listening

## Current Position

Phase: 02 (Authorized Live Listening) — HALTED
Plan: 3 of 7
Status: Blocked by halted Plan 02-02 (`unknown-contract`)
Last activity: 2026-08-18 — Phase 02 execution started

Progress: [█████████░] 86%

## Performance Metrics

**Velocity:**

- Total plans completed: 16
- Average duration: —
- Total execution time: 0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01 | 16 | - | - |

**Recent Trend:**

- Last 5 plans: —
- Trend: —

*Updated after each plan completion*
**Per-Plan Metrics:**

| Plan | Duration | Tasks | Files |
|------|----------|-------|-------|
| Phase 00 P01 | 8 min | 2 tasks | 10 files |
| Phase 00 P02 | 14h 41m | 2 tasks | 4 files |
| Phase 00 P03 | 2min | 3 tasks | 2 files |
| Phase 00 P04 | 4m | 3 tasks | 1 files |
| Phase 00 P05 | 15 min | 2 tasks | 11 files |
| Phase 00-authentication-feasibility-gate P06 | 8min | 2 tasks | 4 files |
| Phase 00 P07 | 8min | 2 tasks | 2 files |
| Phase 00 P08 | 9m | 2 tasks | 6 files |
| Phase 00-authentication-feasibility-gate P09 | 8min | 2 tasks | 10 files |
| Phase 00-authentication-feasibility-gate P10 | 6min | 2 tasks | 16 files |
| Phase 00-authentication-feasibility-gate P11 | 3min | 2 tasks | 4 files |
| Phase 00 P12 | 4min | 1 tasks | 2 files |
| Phase 00 P13 | 4min | 2 tasks | 4 files |
| Phase 00-authentication-feasibility-gate P14 | 8min | 2 tasks | 12 files |
| Phase 00 P15 | 29m | 1 tasks | 9 files |
| Phase 00-authentication-feasibility-gate P16 | 15 min | 2 tasks | 11 files |
| Phase 01 P01 | 12min | 2 tasks | 10 files |
| Phase 01 P02 | 4min | 2 tasks | 6 files |
| Phase 01 P03 | 6min | 2 tasks | 10 files |
| Phase 01 P04 | 10min | 2 tasks | 7 files |
| Phase 01 P05 | 13min | 2 tasks | 7 files |
| Phase 01 P06 | 15min | 2 tasks | 6 files |
| Phase 01 P07 | 12min | 2 tasks | 11 files |
| Phase 01 P08 | 25 min | 2 tasks | 5 files |
| Phase 01-safe-interoperability-foundation P09 | 5min | 1 tasks | 4 files |
| Phase 01 P10 | 4 min | 1 tasks | 5 files |
| Phase 01 P11 | 13 min | 1 tasks | 2 files |
| Phase 01-safe-interoperability-foundation P12 | 6min | 1 tasks | 2 files |
| Phase 01 P13 | 6 min | 2 tasks | 6 files |
| Phase 01 P14 | 2 min | 1 tasks | 2 files |
| Phase 01 P15 | 8 min | 2 tasks | 4 files |
| Phase 01 P16 | 10 min | 2 tasks | 7 files |
| Phase 02 P01 | 23m | 2 tasks | 9 files |
| Phase 02 P02 | 9h 9m | 2 tasks | 7 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md. Active decisions affecting current work:

- Phase 1: WebView token extraction and native authenticated requests are proven and settled; execution starts at Plan 01-01 without a Phase 0 artifact gate or repeated authentication experiment.
- Phase 1: The sole path is a user-operated nonpersistent WKWebView, exact first-party `AUTH_TOKEN` extraction after explicit consent, and native SiriusXM authentication plus entitlement requests.
- Phase 1: A runtime-owned sequence must verify authentication and entitlement before atomically publishing an active session or saving allowed reusable material; caller-authored success records cannot authorize state.
- Phase 1: Token extraction and sign-out share one exact first-party cookie predicate across the apex and accepted subdomains; incomplete cleanup is reported.
- Phase 1: App-owned Keychain is the only persistent secret store, session material stays ephemeral, and diagnostics/fixtures exclude secrets by construction.
- Phase 1: Deterministic WebView/native-request tests compile unconditionally and never depend on `.planning` artifact contents.
- Phase 3: One playback coordinator owns the active player across native windows and system media controls.
- Phase 4: Skins are declarative local data/assets only and preserve accessible native semantics and recovery.

All earlier Phase 0 feasibility-selection, proof-run, quartet, GO/NO-GO, and callback/native-path decisions are historical and superseded for product execution.

- [Phase ?]: Use a local SwiftPM product as the app's sole SiriusXM integration boundary.
- [Phase ?]: Keep pre-composition and Phase 1 content operations as typed unavailable results with no provider work.
- [Phase ?]: Use opaque redacted credential handoff and app-bound storage seams.
- [Phase ?]: Classify only exact internal native JSON responses; redirects, controls, malformed payloads, and ambiguity are terminal outcomes.
- [Phase ?]: Keep the active session local until authentication and entitlement both pass, then publish it with one actor-state assignment.
- [Phase ?]: Do not expose raw native response details or caller-authored authorization claims through public models.
- [Phase ?]: Restrict authorization to the two settled GET request contracts and cancel every redirect after validation.
- [Phase ?]: Keep credential material opaque to public consumers through a scoped internal request-construction closure.
- [Phase ?]: Reject sensitive fixture structures and values before promotion; diagnostics accept only closed semantic events.
- [Phase ?]: Keep app Keychain access behind one generic-password identity and safe classifications with no OSStatus or secret detail.
- [Phase ?]: Expose material to the app-owned Keychain adapter only through an SPI-scoped closure, never through the ordinary public client API.
- [Phase ?]: Retire actor state before starting both local cleaners and report their aggregate outcome without retrying cleanup.
- [Phase ?]: Keep authentication presentation semantic and main-actor single-flight; WebKit/token details remain behind an injected flow.
- [Phase ?]: Retry only restarts the settled native WebView path; unsupported has no player/library composition or alternate method.
- [Phase ?]: Use one root-path, expiry-aware, boundary-correct SiriusXM cookie predicate for extraction and cleanup.
- [Phase ?]: Keep the WebView credential handoff opaque and single-consumption through the client seam.
- [Phase ?]: Compose the app only through the opaque WebView bridge and runtime-owned SiriusXMClient transaction.
- [Phase ?]: Repaired the native XCTest target with explicit app-host linkage and unconditional source membership.
- [Phase ?]: Phase 2 readiness derives only from synthetic Phase 1 acceptance and static authority scans.
- [Phase ?]: Only an explicit user-operated new sign-in attempt may discard and re-arm the volatile WebView credential handoff.
- [Phase ?]: Every explicit cleanup request retires actor state then runs both idempotent cleaners; only overlapping requests share a result.
- [Phase ?]: Fresh composition exposes cleanup-only UI and never reads or restores a stored credential.
- [Phase ?]: Retained the E4/E1 test graph as the sole SiriusMacTests configuration.
- [Phase ?]: Reserve WebView credential selection before cookie-store suspension and commit consumption before credential delivery.
- [Phase ?]: Only explicit user-operated sign-in may re-arm a consumed WebView credential handoff.
- [Phase 01]: Profile-v4 authentication accepts only a non-empty JSON object after existing transport and control preflight, without inventing a profile field. — Preserves the settled Phase 0 predicate while allowing representative unrelated fields.
- [Phase 01]: Subscription-v1 entitlement uses `/subscription/v1/subscriptions` and classifies only recognized `items[].state` values (`active` or `finished`); missing, malformed, empty, or unknown evidence fails closed. — Matches the successful live contract while containing volatile provider schema details internally.
- [Phase ?]: Redirect instrumentation exposes only an internal scalar attempt count and never retains redirect or credential-bearing request data.
- [Phase ?]: Accept one current root-path AUTH_TOKEN from siriusxm.com or any label-boundary-safe subdomain independent of WebKit's Secure flag; continue rejecting expired, path-mismatched, duplicate, and suffix-lookalike cookies.
- [Phase ?]: Cleanup succeeds only after an exact-token rescan is clean and bridge-owned nonpersistent WebKit session retirement succeeds.
- [Phase ?]: WebKit retirement bulk-removes only the app-owned nonpersistent store without enumerating, exporting, logging, or persisting browser records.
- [Phase ?]: A Keychain restore is a one-shot opaque CredentialSource input, never a second sign-in method or authorization claim.
- [Phase ?]: Only missing stored material reaches the existing user-operated WebView branch; unavailable, malformed, and erase-failed material remains terminal.
- [Phase ?]: All restored non-entitled outcomes erase the stored item before presentation; an erase failure is surfaced as an explicit cleanup failure.
- [Phase ?]: Keep Wave 0 listening seams semantic and provider-neutral until the owner-visible contract checkpoint.
- [Phase ?]: Treat catalog snapshots as browse-only; playback requires separate current authorization confirmation.
- [Phase ?]: Use generation checks and finite recovery budgets to reject stale, superseded, and cancelled listening work.
- [Phase 02]: Treat unknown-contract as the terminal first failure domain; do not infer provider or AVFoundation contracts from an unexercised run. — The restored session reached ready state, then the single authorized run stopped before an unallow-listed content request.

### Pending Todos

None yet.

### Blockers/Concerns

- Phase 1: The SiriusXM WebView/token/native-request contract remains volatile; drift must fail closed behind replaceable adapters, never trigger a new authentication-method experiment during execution.
- Phase 5: Verify signing, notarization, stapling, immutable release, Gatekeeper, and Homebrew Cask behavior against the current release toolchain before publishing.
- Plan 02-02 halted: the restored existing session stopped at unknown-contract before content observation; Plans 02-03 through 02-07 are blocked.

### Quick Tasks Completed

| # | Description | Date | Commit | Directory |
|---|-------------|------|--------|-----------|
| 260817-v8g | Align Phase 1 with settled WebView-token/native-request architecture and carry Phase 0 review findings into acceptance | 2026-08-17 | b306027 | [260817-v8g-treat-webview-token-extraction-and-nativ](./quick/260817-v8g-treat-webview-token-extraction-and-nativ/) |
| 260818-c4r | Update only Phase 1's Goal line in .planning/ROADMAP.md | 2026-08-18 | fd464e6 | [260818-c4r-update-only-phase-1-goal-line-in-plannin](./quick/260818-c4r-update-only-phase-1-goal-line-in-plannin/) |
| 260818-tf1 | Improve sign-in window with responsive WebView sizing and subtler border | 2026-08-18 | e469deb | [260818-tf1-improve-sign-in-window-with-responsive-w](./quick/260818-tf1-improve-sign-in-window-with-responsive-w/) |
| 260818-tn3 | Make one live auth attempt fully diagnosable with secret-free native reason labels | 2026-08-18 | 2b51d30 | [260818-tn3-make-one-live-auth-attempt-fully-diagnos](./quick/260818-tn3-make-one-live-auth-attempt-fully-diagnos/) |

### Roadmap Evolution

- Phase 0 retained as historical feasibility work; its GO artifacts no longer gate Phase 1.
- Phase 1 replanned to consume the settled WKWebView token-extraction and native authenticated-request architecture directly.

## Deferred Items

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| v2 | Cached-outage browse, richer discovery, Xtra/on-demand playback, and skin-authoring tools | Deferred | 2026-08-16 |

## Session Continuity

Last session: 2026-08-19T13:01:50.520Z
Stopped at: Halted 02-02-PLAN.md: unknown-contract blocks provider-dependent plans
Resume file: None
