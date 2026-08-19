---
status: resolved
trigger: "The live selected-channel tune checkpoint reported human-verification-required even though the adapter mapped nearly every unexpected HTTP 4xx response to that label."
created: 2026-08-19T20:28:00Z
updated: 2026-08-19T17:29:00Z
---

## Current Focus

hypothesis: Resolved — the tune checkpoint was classifying ordinary client-side status outcomes as human verification solely from an overbroad HTTP range; the unit-test host could also execute the production launch-restoration scene; later browser evidence identified the native tune request and response-shape drift.
test: Added privacy-safe exact-status, inert-test-host, and browser-proven request mutation/revert regression tests; then ran offline suites only.
expecting: The next separately authorized native tune may use the current fixed body and non-secret logical-clock header, then stop at the existing resource-policy decision without follow-on fetching.
next_action: Await explicit authorization before any native live request; preserve the browser session and Keychain state.
bug_class: compatibility classification and request-contract drift
reasoning_checkpoint: Current first-party public code defines the logical-clock representation, while the authenticated browser observation confirms the additional Boolean request field and nested resource wrapper. Browser-only telemetry remains deliberately absent because no safe non-browser value is source-derived.
tdd_checkpoint: null

## Symptoms

expected: A tune failure is classified by the narrowest truthful non-secret status/control atom; only an actual recognized provider verification control is labeled human-verification-required.
actual: An exact tune request returned an unexpected 4xx and the adapter labeled it human-verification-required solely from the broad status range.
errors: "Tune check stopped safely: human-verification-required"
timeline: First observed during the selected-channel tune checkpoint on 2026-08-19.
reproduction: Launch the isolated compatibility app, restore the Keychain session, complete the catalog check, then run the one selected-channel tune check.

## Evidence

- timestamp: 2026-08-19T16:31:00Z
  source: adapter inspection
  finding: The former protection classifier mapped every 400...499 response except the explicit authorization, forbidden, and rate-limit statuses to human verification.
- timestamp: 2026-08-19T16:35:00Z
  source: current first-party public playback bundle
  finding: The selected channel-linear request defaults already match the current public implementation. Optional diagnostic headers are not required, no channel-linear media-format addition is specified, and no tune-failure verification-control response schema is published.
- timestamp: 2026-08-19T16:40:00Z
  source: isolated authorized compatibility check
  finding: Automatic Keychain restoration reached ready state; the single catalog check completed and the single selected-channel tune check returned only the fixed non-secret atom tune-http-400. No follow-on media, key, or unknown-host request occurred.
- timestamp: 2026-08-19T16:43:00Z
  source: automated verification
  finding: The package suite passed 45 tests and the macOS project suite passed 75 tests after the classification change.
- timestamp: 2026-08-19T16:45:00Z
  source: final isolated relaunch and application lifecycle inspection
  finding: The restored session was absent after an app-hosted unit-test run. The test target uses the production application as its host, and the production launch scene previously initiated automatic restoration in that host.
- timestamp: 2026-08-19T16:48:00Z
  source: automated verification
  finding: A guarded test-host scene regression passed, followed by the full macOS project suite passing 76 tests. The test host now omits the authentication scene and therefore cannot read, authenticate with, or erase the production Keychain session.
- timestamp: 2026-08-19T17:22:00Z
  source: authenticated browser observation
  finding: A successful first-party tune used one additional fixed Boolean request field and continued only through expected provider operations. Its successful tune result wrapped candidate resources in a nested array; the native checkpoint does not retain or request those resources.
- timestamp: 2026-08-19T17:24:00Z
  source: current first-party public playback module
  finding: The non-secret clock header is an in-memory logical epoch/counter pair. The native checkpoint reproduces only that bounded representation and intentionally omits browser-only telemetry and client headers whose values are not source-derived for native use.
- timestamp: 2026-08-19T17:28:00Z
  source: red-green regression verification
  finding: The focused suite first failed on the missing Boolean, missing logical-clock header, and outdated nested-resource parser, then passed after correction. Package tests passed 45/45 and macOS tests passed 77/77; no native live request occurred.

## Eliminated

- A genuine verification-control classification: no source-derived, allow-listed tune-response control shape was available, so opaque provider content was not inspected or retained.
- Browser-only telemetry and client context: names without a source-derived native value are not sufficient authority to add them to the closed native request.

## Resolution

root_cause: An overbroad 4xx range promoted unsupported client-status outcomes to human-verification-required without evidence of a user-mediated control; the app-hosted unit-test process could run the production automatic-restoration path and erase a rejected stored session; the native tune contract omitted a browser-proven Boolean and logical-clock header and expected an outdated resource wrapper.
fix: Added fixed atoms for 400, 404, 409, and 422 and classify them as unknown-contract; retained strict terminal handling for 401, 403, 429, redirects, and all other unknown responses; made the XCTest app host inert before it can construct the authentication scene; added the exact Boolean, a bounded in-memory logical clock, and the observed nested resource wrapper.
verification: Synthetic mutation/revert coverage passed; package suite 45/45; macOS suite 77/77; no native live request was made after the browser evidence.
files_changed:
  - SiriusMac/SiriusMacApp.swift
  - SiriusMacTests/AuthenticationPresentationModelTests.swift
  - SiriusMac/Listening/ClosedLiveObservationAdapter.swift
  - SiriusMac/Authentication/AuthenticationView.swift
  - SiriusMacTests/ListeningCompositionTests.swift
  - .planning/debug/resolved/tune-4xx-misclassified.md

## Blameless Postmortem

why_not_caught: The earlier tests covered explicit protected statuses but did not assert that ordinary 4xx responses require source-derived verification evidence; the test-host executable had no guard against creating the production authentication scene; the exact tune body and nested response wrapper were inferred from public code rather than compared to a successful browser operation.
guard: `testTuneRunClassifiesKnownClientStatusAtomsWithoutAssumingHumanVerification` fixes the supported client-status vocabulary; `testLaunchModeIdentifiesOnlyTheXCTestHostEnvironment` keeps the app-hosted unit-test process inert before any Keychain restore can begin; `testTuneContractRejectsMutatedBrowserProvenBodyAndClockThenAcceptsTheOriginal` proves the corrected contract rejects mutation and accepts restoration.

## Live Result

Before the test-host incident, authentication restoration and catalog access were confirmed. The bounded tune attempt stopped at the next sanitized semantic gate: unknown-contract with the fixed client-status atom. New browser evidence identifies the request correction, but this update intentionally made no native live request. Any future retest must be separately authorized and must stop before media, key, or unknown-host fetching.
