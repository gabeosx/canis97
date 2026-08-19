---
status: resolved
trigger: "The live selected-channel tune checkpoint reported human-verification-required even though the adapter mapped nearly every unexpected HTTP 4xx response to that label."
created: 2026-08-19T20:28:00Z
updated: 2026-08-19T16:44:00Z
---

## Current Focus

hypothesis: Resolved — the tune checkpoint was classifying ordinary client-side status outcomes as human verification solely from an overbroad HTTP range; the unit-test host could also execute the production launch-restoration scene.
test: Added privacy-safe exact-status and inert-test-host regression tests, then rebuilt and ran the authorized compatibility check.
expecting: Exact client-status atoms stop as unknown contract failures unless a future public source defines an exact, allowed verification-control shape.
next_action: Closed; preserve the status atom for repair without retaining provider content.
bug_class: compatibility classification
reasoning_checkpoint: Current first-party public playback code corroborates the existing selected-channel request defaults and does not define a tune-response verification-control schema.
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

## Eliminated

- A source-supported tune-request correction: the current public implementation corroborates the existing selected-channel body and does not require an additional channel-linear field or optional header.
- A genuine verification-control classification: no source-derived, allow-listed tune-response control shape was available, so opaque provider content was not inspected or retained.

## Resolution

root_cause: An overbroad 4xx range promoted unsupported client-status outcomes to human-verification-required without evidence of a user-mediated control; the app-hosted unit-test process could run the production automatic-restoration path and erase a rejected stored session.
fix: Added fixed atoms for 400, 404, 409, and 422 and classify them as unknown-contract; retained strict terminal handling for 401, 403, 429, redirects, and all other unknown responses; made the XCTest app host inert before it can construct the authentication scene.
verification: Synthetic regression coverage passed; package suite 45/45; macOS suite 76/76; the authorized catalog/tune live check completed before the test-host incident without requesting media or key resources.
files_changed:
  - SiriusMac/SiriusMacApp.swift
  - SiriusMacTests/AuthenticationPresentationModelTests.swift
  - SiriusMac/Listening/ClosedLiveObservationAdapter.swift
  - SiriusMac/Authentication/AuthenticationView.swift
  - SiriusMacTests/ListeningCompositionTests.swift
  - .planning/debug/resolved/tune-4xx-misclassified.md

## Blameless Postmortem

why_not_caught: The earlier tests covered explicit protected statuses but did not assert that ordinary 4xx responses require source-derived verification evidence; the test-host executable had no guard against creating the production authentication scene.
guard: `testTuneRunClassifiesKnownClientStatusAtomsWithoutAssumingHumanVerification` fixes the supported client-status vocabulary, and `testLaunchModeIdentifiesOnlyTheXCTestHostEnvironment` keeps the app-hosted unit-test process inert before any Keychain restore can begin.

## Live Result

Before the test-host incident, authentication restoration and catalog access were confirmed. The bounded tune attempt stopped at the next sanitized semantic gate: unknown-contract with the fixed atom tune-http-400. No materially different request was source-supported, so no live retry was made. The session item is now absent and requires a new user-operated login; no further authenticated action was attempted.
