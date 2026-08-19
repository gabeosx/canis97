---
status: resolved
trigger: "I am willing to login again, but you need to figure out why we're suddenly signed out"
created: 2026-08-19T13:05:00Z
updated: 2026-08-19T15:33:00Z
---

## Current Focus

hypothesis: Confirmed — Use Logged-In Session is an in-process WebView-cookie extraction, not a cross-relaunch restore. The launch shell neither invokes the app-owned Keychain restoration path nor suppresses the fresh WebView action, so a relaunch can select the empty nonpersistent WebView store instead of running the persisted credential through the native authentication and entitlement transaction.
test: Complete — agent-authored synthetic launch-restore tests ran red before the production APIs existed, green after the minimal implementation, red again with only the scoped hunk reverted, and green after reapplication.
expecting: observed
next_action: Offline implementation and verification are complete; the scoped source/test changes were committed as 0ea1f6c. No live verification was performed under this session's constraints.
bug_class: bohrbug
reasoning_checkpoint:
  hypothesis: "The fresh-process UI bypasses the reusable Keychain source because launch has no automatic restore entry point and initially exposes the WebView session action; a guarded launch restore that routes only through the credential source will use the native transaction exactly once without WebView reads."
  confirming_evidence:
    - "The recorded action trace shows only prepareForExplicitSignIn reads Keychain while Use Logged-In Session calls the nonpersistent WebView bridge directly."
    - "The existing synthetic restore test proves the Keychain-backed native transaction can succeed with zero cookie reads when it is invoked."
  falsification_test: "A synthetic launch restore with a stored credential causes a WebView cookie read, web sign-in load, or more than one client transaction; or a missing/terminal stored credential falls through to the WebView path."
  fix_rationale: "A separate automatic-restore flow can map missing material to signed-out, staged material to the existing client transaction, and unusable/terminal material to existing fail-closed outcomes without calling beginUserOperatedSignIn or useLoggedInSession."
  blind_spots: "Offline tests cannot prove a real Keychain item survived the consumed compatibility launcher; no live credential, app, or network access is permitted in this session."
  candidate_causes:
    - "code: launch composition lacks an automatic Keychain restoration call and starts in a WebView-ready presentation state."
    - "environment: relaunch necessarily discards the intentionally nonpersistent WebView store, but does not alter the app-owned Keychain code path."
  and_gate: "no — the missing launch restore path alone fully explains the symptom; WebView store replacement merely makes the incorrect UI action's terminal result deterministic."
tdd_checkpoint: null

## Symptoms

expected: A previously authenticated and entitled Sirius Mac session remains reusable after the app is quit, rebuilt, or relaunched, so the Phase 02 compatibility checkpoint can use it without another login.
actual: The checkpoint launcher rebuilt and relaunched Sirius Mac into the signed-out shell. Selecting Use Logged-In Session immediately produced the closed Sign-in flow unsupported state.
errors: "Sign-in flow unsupported. This sign-in flow is unsupported. No workaround was attempted."
timeline: The WebView credential handoff, native authentication, and entitlement had succeeded during the prior live trace on 2026-08-18/2026-08-19. The reusable session was unavailable after the Phase 02 checkpoint launcher killed, rebuilt, and relaunched the app on 2026-08-19.
reproduction: Complete a successful authenticated and entitled run, quit the app or invoke script/live_compatibility_checkpoint.sh (which calls script/build_and_run.sh), relaunch, and select Use Logged-In Session without completing a new WebView login.

## Eliminated

- hypothesis: The checkpoint launcher signs out or deletes the persisted Keychain credential.
  evidence: script/live_compatibility_checkpoint.sh only runs offline tests then delegates to build_and_run.sh; build_and_run.sh kills the app process and rebuilds but contains no Keychain, sign-out, residue-cleanup, or credential-deletion call.
  timestamp: 2026-08-19T14:25:00Z
- hypothesis: The reported unsupported result proves the Keychain item was missing, unreadable, or under a different item identity after rebuild.
  evidence: The reported UI action bypasses KeychainCredentialStore.loadStoredCredentialForAuthentication entirely. Its terminal outcome occurs inside WebAuthenticationBridge before the native client can be called, so no Keychain load result can have caused that specific outcome.
  timestamp: 2026-08-19T14:25:00Z

## Evidence

- timestamp: 2026-08-19T14:15:00Z
  checked: SessionCoordinator persistence path
  found: After native authentication and entitlement both succeed, SessionCoordinator saves the same opaque credential through the app-owned CredentialStore before returning the active outcome; save failure is separately classified and does not cause the session to be reported as signed out.
  implication: A successful entitled transaction invokes the persistence boundary. The observed post-relaunch unsupported result alone is not evidence that no save was attempted.
- timestamp: 2026-08-19T14:15:00Z
  checked: Production AuthenticationComposition and RestorableAuthenticationCredentialSource
  found: Each launch creates one KeychainCredentialStore and one combined credential source. prepareForExplicitSignIn reads the stored credential first, while a missing item alone starts the WebView branch.
  implication: The production composition contains an explicit, separate Keychain restoration path; it is not automatic at launch.
- timestamp: 2026-08-19T14:15:00Z
  checked: UI action routing and WebAuthenticationBridge
  found: The Sign In button calls prepareForExplicitSignIn. The Use Logged-In Session button calls bridge.useLoggedInSession directly, whose only credential input is its current cookie store. That store is constructed with WKWebsiteDataStore.nonPersistent(), so a newly launched bridge has no prior WebView cookie state.
  implication: The reproduction step selects a different, knowingly volatile source than the Keychain restore source. On a fresh process it deterministically reaches auth-cookie-missing and the public unsupported state.
- timestamp: 2026-08-19T14:15:00Z
  checked: Checkpoint and build scripts plus target identity
  found: The checkpoint runs tests and invokes build_and_run.sh --telemetry. The launcher kills the process and rebuilds with CODE_SIGNING_ALLOWED=NO, but neither script signs out nor calls Keychain deletion; the Debug target continues to use product bundle identifier com.siriusmac.player, which is the Keychain service default.
  implication: The documented launcher behavior explains replacement of in-memory/WebView state but supplies no offline evidence of deletion or changing the Keychain item identity.
- timestamp: 2026-08-19T14:15:00Z
  checked: Existing fresh-restore and terminal-WebView composition tests
  found: testFreshRestoreConsumesOneStoredCredentialBeforeOrderedNativeTransaction specifies an entitled fresh restore with zero cookie reads. testTerminalBridgeAndClientResultsDoNotOfferFallbackOrRetry specifies that an empty current WebView produces unsupported with no native client call.
  implication: The codebase already encodes the differential prediction needed to distinguish the two actions offline.
- timestamp: 2026-08-19T14:25:00Z
  checked: Focused offline test run: SelectedAuthenticationCompositionTests/testFreshRestoreConsumesOneStoredCredentialBeforeOrderedNativeTransaction and /testTerminalBridgeAndClientResultsDoNotOfferFallbackOrRetry
  found: Both tests passed with synthetic credentials only. The first completed a fresh Keychain-backed entitled transaction with zero WebView cookie reads. The second returned unsupported from an empty WebView with no native-client call.
  implication: The observed relaunch-plus-Use action is a deterministic state-routing result, not evidence of a deleted or non-reusable Keychain session. SBFL was skipped because no test fails under the reported deterministic condition.
- timestamp: 2026-08-19T14:48:00Z
  checked: Offline red run: SiriusMacTests/AuthenticationPresentationModelTests and /SelectedAuthenticationCompositionTests
  found: Compilation failed because AuthenticationPresentationModel.restoreStoredCredentialOnLaunch and ComposedAuthenticationPresentationFlow.restoreStoredCredential do not exist. The new tests specify one guarded launch attempt, zero cookie reads/WebView loads, signed-out missing material, and fail-closed invalid/rejected material.
  implication: The failure directly confirms the missing launch restoration entry point. No application process, live credential, or network request was used.
- timestamp: 2026-08-19T15:31:00Z
  checked: Offline green run: SiriusMacTests/AuthenticationPresentationModelTests and /SelectedAuthenticationCompositionTests
  found: All 24 selected tests passed. The automatic success path read the injected app-owned credential exactly once, performed the native authentication then entitlement transaction, and made zero WebView cookie reads or sign-in loads. Missing data returned signed-out; invalid, unavailable, and rejected material remained terminal with no fallback or retry.
  implication: The launch flow now distinguishes durable app-owned credentials from the volatile current-WebView source and preserves fail-closed terminal behavior.
- timestamp: 2026-08-19T15:31:00Z
  checked: Revert-and-reconfirm and adjacent offline verification
  found: Reversing only the three production hunks caused build-for-testing to fail because the focused tests could not find the required launch-restore APIs; reapplying the exact hunks restored all 24 selected tests. `swift test --scratch-path /tmp/siriusxmclient-debug-scratch` passed 45 client tests, and build-only `xcodebuild ... build` succeeded. No web sign-in, compatibility runner, live credential, or network interaction was initiated.
  implication: The scoped implementation—not unrelated worktree changes—causes the launch-restore regression tests to pass, while adjacent native-client behavior remains green.

## Resolution

root_cause: The app exposed two different credential sources under ambiguous action names. “Use Logged-In Session” called WebAuthenticationBridge.useLoggedInSession(), which is intentionally limited to the current nonpersistent WKWebView cookie store; a rebuilt/relaunched app has a new empty store, so it emits auth-cookie-missing and displays unsupported. The reusable Keychain credential was only read by the Sign In action through RestorableAuthenticationCredentialSource.prepareForExplicitSignIn(), so launch never attempted it.
fix: AuthenticationView now invokes one guarded launch restoration attempt. AuthenticationPresentationModel and ComposedAuthenticationPresentationFlow route only the app-owned Keychain source through the existing native authentication and entitlement transaction. Missing material settles signed-out, while malformed, unavailable, and rejected material retains the existing erase/fail-closed outcomes without WebView fallback. The WebView mounts only after explicit Sign In, and the fresh-process-hidden action is renamed “Use This Window’s Session.”
oracle_type: specified
verification:
  target_test:
    result: pass
    suites_run:
      - "SiriusMacTests/AuthenticationPresentationModelTests"
      - "SiriusMacTests/SelectedAuthenticationCompositionTests"
    detail: "24 focused synthetic tests passed after reapplying the scoped hunk."
  mutation_check:
    result: skipped
    reason_if_skipped: "No Stryker or equivalent mutation-test configuration exists in this Swift project."
    mutant_killed: null
  no_op_deletion:
    result: pass
    deletion_justified_by_rca: false
    detail: "The diff adds a guarded restoration path and assertions; it does not remove or short-circuit authentication behavior."
  adjacent_tests:
    result: pass
    suites_run:
      - "swift test --scratch-path /tmp/siriusxmclient-debug-scratch (45 tests)"
      - "xcodebuild -project SiriusMac.xcodeproj -scheme SiriusMac ... build"
  revert_and_reconfirm:
    result: pass
    bug_returned_on_revert: true
    fixed_on_reapply: true
    detail: "Reverting only the three production hunks made build-for-testing fail on the missing launch-restore APIs; reapplying restored the 24 focused tests."
  guardrail_verdict: accepted
files_changed:
  - SiriusMac/Authentication/AuthenticationPresentationModel.swift
  - SiriusMac/Authentication/AuthenticationView.swift
  - SiriusMac/Authentication/RestorableAuthenticationCredentialSource.swift
  - SiriusMacTests/AuthenticationPresentationModelTests.swift
  - SiriusMacTests/SelectedAuthenticationCompositionTests.swift
