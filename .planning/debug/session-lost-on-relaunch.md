---
status: diagnosed
trigger: "I am willing to login again, but you need to figure out why we're suddenly signed out"
created: 2026-08-19T13:05:00Z
updated: 2026-08-19T14:25:00Z
---

## Current Focus

hypothesis: Confirmed — Use Logged-In Session is an in-process WebView-cookie extraction, not a cross-relaunch restore. The app starts in a neutral sign-in shell and only the Sign In action reaches the saved Keychain credential; selecting Use Logged-In Session after relaunch reads the newly constructed nonpersistent WebView store and deterministically produces the observed unsupported state.
test: Completed static action-path trace and two focused synthetic offline composition tests.
expecting: observed
next_action: Return the diagnose-only root-cause report; do not modify production or test code.
bug_class: bohrbug
reasoning_checkpoint: null
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

## Resolution

root_cause: The app exposes two different credential sources under ambiguous action names. “Use Logged-In Session” calls WebAuthenticationBridge.useLoggedInSession(), which is intentionally limited to the current nonpersistent WKWebView cookie store; a rebuilt/relaunched app has a new empty store, so it emits auth-cookie-missing and displays unsupported. The reusable Keychain credential is read only by the Sign In action through RestorableAuthenticationCredentialSource.prepareForExplicitSignIn(). The Phase 02 checkpoint used the former action after relaunch, so it never attempted the designed Keychain restore.
fix: diagnose-only
verification: Static source trace plus two focused offline synthetic composition tests passed; no app UI, live request, credential inspection, or compatibility-run retry was performed.
files_changed:
  - .planning/debug/session-lost-on-relaunch.md
