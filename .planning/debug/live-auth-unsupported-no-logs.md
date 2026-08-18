---
status: awaiting_human_verify
trigger: "I don't want to proceed with further testing that requires me signing-in to Sirius until you add sufficient logging to debug what is actually happening. The more times I login the more likely it becomes that Sirius will block me suspecting I am a bot"
created: 2026-08-18T23:08:00Z
updated: 2026-08-18T23:34:11Z
---

## Current Focus

hypothesis: Confirmed in code and regression tests: Phase 1 hardening replaced the previously working boundary-safe SiriusXM-subdomain rule with an apex/www-only allowlist and production drifted from /player to the marketing root.
test: Completed entirely offline: restored boundary-safe siriusxm.com/*.siriusxm.com acceptance, restored /player, added value-free first-party cookie-name inventory and rejection diagnostics, made injected bridge sign-in loading network-free, and ran focused/full suites plus build-only.
expecting: A future user-authorized attempt transfers the prior working AUTH_TOKEN shape. If it does not, logs show the first-party cookie names present and any exact issuer/path/Secure/expiry rejection without values.
next_action: Wait for the user to choose whether to perform one instrumented live attempt with ./script/build_and_run.sh --telemetry. Do not initiate another SiriusXM sign-in without that choice.
bug_class: bohrbug
reasoning_checkpoint:
  hypothesis: "The live bridge regressed the proven SiriusXM-subdomain token policy and the first telemetry pass collapsed all selector failures to auth-cookie-missing."
  confirming_evidence:
    - "The user-provided sequence stops at auth-cookie-missing before any native client event."
    - "The previously working policy accepted siriusxm.com and boundary-safe subdomains; c5d8e40 changed player.siriusxm.com into an explicit rejection."
    - "Production loaded the marketing root although the established browser contract uses /player."
  falsification_test: "The exact previously working player-subdomain cookie must transfer in a focused regression, lookalike domains must remain rejected, injected tests must make no network load, and diagnostic canaries must prove no cookie value reaches telemetry."
  fix_rationale: "Restore the proven registrable-domain boundary rather than a brittle host list, use the established player entry, and log only sanitized first-party names plus closed rejection reasons."
  blind_spots: "Only a future owner-authorized attempt can confirm the current SiriusXM site still emits the expected token and that the subsequent native endpoints remain compatible."
  candidate_causes:
    - "code: c5d8e40 rejects valid SiriusXM subdomains and production starts on the wrong entry surface"
    - "observability: auth-cookie-missing conceals present cookie names and selector rejection reasons"
  and_gate: "Yes: the restrictive selector produces the missing result, and insufficient telemetry conceals that regression. Both are repaired before another live attempt."
tdd_checkpoint: null

## Symptoms

expected: After a successful embedded website sign-in, Use Logged-In Session transfers one approved first-party credential, native authentication and entitlement complete, and the app reaches Ready to listen. If it fails, privacy-safe diagnostics identify the failing stage and semantic reason.
actual: The app displays Sign-in flow unsupported after Use Logged-In Session; the first instrumented run ended at auth-cookie-missing before credential transfer or any native client event.
errors: "Sign-in flow unsupported. This sign-in flow is unsupported. No workaround was attempted."
reproduction: Launch Sirius Mac, sign in inside the nonpersistent embedded SiriusXM WebView, then click Use Logged-In Session once.
started: First confirmed against the Phase 1 app during UAT on 2026-08-18. A prior WebView session extraction and native URLSession acceptance had succeeded before the Phase 1 regression.

## Eliminated

- hypothesis: SiriusXM rejected the transferred credential, rate-limited the app, or returned a bot-control/challenge response.
  evidence: No credential-transferred or SiriusXM client event occurred; the bridge stopped at auth-cookie-missing.
  timestamp: 2026-08-18T23:24:21Z
- hypothesis: The WebView-to-native handoff had never been proven and required discovery from scratch.
  evidence: The user-confirmed prior run extracted the authenticated WebView session in memory and SiriusXM accepted it through URLSession; git history preserves the corresponding boundary-safe subdomain predicate and player-subdomain regression.
  timestamp: 2026-08-18T23:24:21Z

## Evidence

- timestamp: 2026-08-18T23:08:00Z
  checked: User-provided UAT screenshots
  found: Embedded sign-in followed by Use Logged-In Session ends in the fixed unsupported state; Clear Local Session then reaches Signed out without automatic retry.
  implication: The app fails closed and cleanup works, but the authentication failure stage is not observable.
- timestamp: 2026-08-18T23:08:00Z
  checked: WebAuthenticationBridge.useLoggedInSession and ComposedAuthenticationPresentationFlow.useLoggedInSession
  found: Six bridge outcomes collapse to unsupported unless the credential is transferred, and no bridge telemetry records which outcome occurred.
  implication: A missing, ambiguous, malformed, cancelled, or already-consumed WebView credential is indistinguishable at runtime.
- timestamp: 2026-08-18T23:08:00Z
  checked: SiriusXMClient production composition and SessionCoordinator diagnostics
  found: SessionCoordinator has a closed diagnostic protocol, but production explicitly injects NoopSessionDiagnostics; an OSLogDiagnosticSink exists but is never wired.
  implication: Native authentication and entitlement outcomes are intentionally discarded in the live app.
- timestamp: 2026-08-18T23:08:00Z
  checked: NativeRequestVerifier and AuthenticationFlowAdapter
  found: Transport errors, unsupported status/content type, response-shape drift, redirects, rate limits, challenges, and bot controls ultimately collapse to public unsupported or challenge states without a live diagnostic sink.
  implication: The next live attempt cannot safely distinguish provider control responses from compatibility drift or local token-selection failure.
- timestamp: 2026-08-18T23:19:17Z
  checked: Package and app automated suites after telemetry wiring
  found: All 32 SiriusXMClient package tests and all 42 SiriusMac app tests passed without a live SiriusXM request.
  implication: The safe diagnostic classifications preserve existing behavior and are covered at both the client and WebView bridge boundaries.
- timestamp: 2026-08-18T23:19:17Z
  checked: Manual mutation checks for bridge and client diagnostic assertions
  found: Removing the auth-cookie-missing bridge event failed the focused app test; replacing unsupported-payload with generic unsupported failed the focused package test. Restoring each implementation made both focused tests pass.
  implication: The new tests depend on the implemented diagnostic behavior and are not no-op coverage.
- timestamp: 2026-08-18T23:19:17Z
  checked: Logger interpolation and redaction coverage
  found: Production logger calls interpolate only closed enum labels. Tests enumerate every SafeDiagnosticOutcome and reject a secret canary; no logger call interpolates tokens, cookies, authorization values, headers, bodies, URLs, account data, credentials, requests, responses, or raw errors.
  implication: The diagnostic surface is intentionally unable to copy live authentication material into logs.
- timestamp: 2026-08-18T23:19:17Z
  checked: script/build_and_run.sh --build-only and telemetry mode definition
  found: The actual SiriusMac app built successfully at /tmp/sirius-mac-derived-data/Build/Products/Debug/SiriusMac.app. The telemetry mode launches that app and streams only the authentication and client diagnostic categories.
  implication: The repository Run entry point no longer launches the obsolete Phase 0 harness, and one future attempt can be captured without broad log collection.
- timestamp: 2026-08-18T23:24:21Z
  checked: User-provided telemetry from the first instrumented attempt
  found: The sequence ended at web-sign-in-started, credential-selection-started, auth-cookie-missing. No credential-transferred or SiriusXM client event occurred.
  implication: The failure is entirely inside the WebView credential-selection boundary. No native authentication request, rejection, rate limit, challenge, or bot-control response occurred.
- timestamp: 2026-08-18T23:24:21Z
  checked: Production WebAuthenticationBridge entry URL against Phase 0 public auth contract
  found: Production loads https://www.siriusxm.com/ while the established first-party browser entry contract is https://www.siriusxm.com/player.
  implication: Production drifted from the previously proven player flow; this is a regression candidate, not evidence that the earlier handoff was unproven.
- timestamp: 2026-08-18T23:24:21Z
  checked: FirstPartyTokenCookiePolicy and current telemetry granularity
  found: The policy accepts only a current Secure root-path AUTH_TOKEN from normalized siriusxm.com or exact www.siriusxm.com, while auth-cookie-missing conflates absence of that cookie name with issuer, path, Secure, and expiry rejection.
  implication: The next attempt should retain the fail-closed policy but emit fixed rejection-class labels so one attempt is sufficient if the corrected player entry still differs from historical evidence.
- timestamp: 2026-08-18T23:24:21Z
  checked: User correction, prior empirical result, and git history from 4cb78c9 through c5d8e40
  found: A real WebView session had already been extracted in memory and accepted by SiriusXM through URLSession. The known-working policy accepted boundary-correct *.siriusxm.com cookies and its primary positive regression used .player.siriusxm.com. Commit c5d8e40 later replaced suffix-safe acceptance with [siriusxm.com, www.siriusxm.com] and rewrote player.siriusxm.com as an expected rejection.
  implication: The project did forget a proven interoperability fact during security hardening. The repair is to restore the original label-boundary-safe SiriusXM domain rule, not maintain a brittle host allowlist or re-investigate the handoff from scratch.
- timestamp: 2026-08-18T23:28:00Z
  checked: Diagnostic sufficiency of auth-cookie-missing
  found: The label conflates an absent AUTH_TOKEN name with issuer, path, Secure, and expiry rejection and provides no bounded inventory of the first-party cookie names that were actually present.
  implication: The first logging pass was not sufficient. A value-free, sanitized, capped first-party cookie-name inventory and closed rejection reasons are required before another login is reasonable; cookie values remain prohibited.
- timestamp: 2026-08-18T23:32:28Z
  checked: Focused WebAuthenticationBridgeTests after the regression repair
  found: All 21 tests passed. The suite proves /player loading through an injected no-network loader, accepts apex and true SiriusXM subdomains, rejects evil-siriusxm.com, logs only first-party names, excludes third-party names and value canaries, and distinguishes every selector rejection class.
  implication: The repair covers both the forgotten interoperability rule and the diagnostic insufficiency without weakening name, Secure, path, expiry, cardinality, cleanup, or lookalike protections.
- timestamp: 2026-08-18T23:32:28Z
  checked: Full app suite, package suite, and build-only verification
  found: All 45 SiriusMac tests and all 32 SiriusXMClient tests passed; script/build_and_run.sh --build-only produced the app without launching it.
  implication: The scoped repair integrates with the complete authentication/session graph and required no SiriusXM request or login.
- timestamp: 2026-08-18T23:34:11Z
  checked: Manual mutation of the repaired first-party domain predicate back to the regressed apex/www-only behavior
  found: The focused player-subdomain handoff test failed with authCookieMissing and zero credential transfers. Restoring boundary-safe subdomain matching made the same test pass.
  implication: The regression test specifically kills the prior c5d8e40 behavior and will prevent the project from forgetting this interoperability fact again.

## Resolution

root_cause: The original observability gap was only partially fixed. The live failure is a Phase 1 regression from the previously proven WebView handoff: c5d8e40 discarded boundary-safe SiriusXM-subdomain acceptance and explicitly made player.siriusxm.com fail as missing, while production also uses the marketing root instead of the established /player entry. The generic missing label then concealed both the rejected token shape and the first-party cookie names present.
fix: Restored the proven https://www.siriusxm.com/player entry and the boundary-safe siriusxm.com/*.siriusxm.com AUTH_TOKEN rule while retaining Secure, root-path, current, exact-cardinality, and suffix-lookalike checks. Added a capped, sanitized inventory of first-party cookie names and closed name-absent/issuer/path/Secure/expiry diagnostics; values are never recorded. Injected bridge tests now use a no-op/request-capture loader and cannot contact SiriusXM.
verification:
  target_test: pass
  mutation_check:
    result: pass
    mutant_killed: true
    method: "Manual focused mutations including restoration of the c5d8e40 apex/www-only regression because no mutation framework is configured"
  no_op_deletion: pass
  adjacent_tests:
    result: pass
    suites:
      - "SiriusXMClient package: 32 tests"
      - "SiriusMac app: 45 tests"
      - "WebAuthenticationBridge focused: 21 tests"
  revert_and_reconfirm:
    result: pass
    bug_returned_on_revert: true
    fixed_on_reapply: true
  build_only: pass
  secret_scan: pass
  guardrail_verdict: accepted
oracle_type: specified
files_changed:
  - Packages/SiriusXMClient/Sources/SiriusXMClient/Diagnostics/SafeDiagnosticEvent.swift
  - Packages/SiriusXMClient/Sources/SiriusXMClient/InternalAdapters/AuthenticationFlowAdapter.swift
  - Packages/SiriusXMClient/Sources/SiriusXMClient/Public/SiriusXMClient.swift
  - Packages/SiriusXMClient/Sources/SiriusXMClient/Session/SessionCoordinator.swift
  - Packages/SiriusXMClient/Sources/SiriusXMClient/Session/SessionState.swift
  - Packages/SiriusXMClient/Tests/FixtureTests/RedactionTests.swift
  - Packages/SiriusXMClient/Tests/SiriusXMClientTests/AuthenticationOutcomeTests.swift
  - Packages/SiriusXMClient/Tests/SiriusXMClientTests/SessionCoordinatorTests.swift
  - SiriusMac/Authentication/WebAuthenticationBridge.swift
  - SiriusMac/Authentication/FirstPartyTokenCookiePolicy.swift
  - SiriusMacTests/WebAuthenticationBridgeTests.swift
  - script/build_and_run.sh
  - .planning/phases/01-safe-interoperability-foundation/01-UAT.md
