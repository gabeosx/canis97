---
status: partial
phase: 01-safe-interoperability-foundation
source: ["01-01-SUMMARY.md", "01-02-SUMMARY.md", "01-03-SUMMARY.md", "01-04-SUMMARY.md", "01-05-SUMMARY.md", "01-06-SUMMARY.md", "01-07-SUMMARY.md", "01-08-SUMMARY.md", "01-09-SUMMARY.md", "01-10-SUMMARY.md", "01-11-SUMMARY.md", "01-12-SUMMARY.md", "01-13-SUMMARY.md", "01-14-SUMMARY.md", "01-15-SUMMARY.md", "01-16-SUMMARY.md"]
started: 2026-08-18T22:58:14Z
updated: 2026-08-18T23:08:00Z
---

## Current Test

[testing paused — 1 item outstanding]

## Tests

### 1. Native compatibility presentation starts in a typed waiting state without background retries.
expected: Native compatibility presentation starts in a typed waiting state without background retries.
result: pass
source: automated
coverage_id: D1
coverage_summary: 01-01-SUMMARY.md

### 2. Independent consumers import the public SwiftPM product and receive semantic unavailable outcomes.
expected: Independent consumers import the public SwiftPM product and receive semantic unavailable outcomes.
result: pass
source: automated
coverage_id: D2
coverage_summary: 01-01-SUMMARY.md

### 3. Client package tests compile independently of mutable planning artifacts.
expected: Client package tests compile independently of mutable planning artifacts.
result: pass
source: automated
coverage_id: D3
coverage_summary: 01-01-SUMMARY.md

### 4. Native authentication and entitlement responses are independently classified and control or ambiguous shapes fail closed.
expected: Native authentication and entitlement responses are independently classified and control or ambiguous shapes fail closed.
result: pass
source: automated
coverage_id: D1
coverage_summary: 01-02-SUMMARY.md

### 5. The actor serializes one credential-bound attempt, requires entitlement before activation or persistence, and clears cancelled or unentitled work.
expected: The actor serializes one credential-bound attempt, requires entitlement before activation or persistence, and clears cancelled or unentitled work.
result: pass
source: automated
coverage_id: D2
coverage_summary: 01-02-SUMMARY.md

### 6. The public client boundary continues to expose only semantic results while raw native response data remains internal.
expected: The public client boundary continues to expose only semantic results while raw native response data remains internal.
result: pass
source: automated
coverage_id: D3
coverage_summary: 01-02-SUMMARY.md

### 7. Client-owned ephemeral transport restricts authorization to the settled request contract and cancels redirects.
expected: Client-owned ephemeral transport restricts authorization to the settled request contract and cancels redirects.
result: pass
source: automated
coverage_id: D1
coverage_summary: 01-03-SUMMARY.md

### 8. Closed diagnostics and fixture promotion structurally exclude secret-bearing keys and canary values.
expected: Closed diagnostics and fixture promotion structurally exclude secret-bearing keys and canary values.
result: pass
source: automated
coverage_id: D2
coverage_summary: 01-03-SUMMARY.md

### 9. The full reusable client package remains deterministic and free of planning-artifact runtime dependencies.
expected: The full reusable client package remains deterministic and free of planning-artifact runtime dependencies.
result: pass
source: automated
coverage_id: D3
coverage_summary: 01-03-SUMMARY.md

### 10. Keychain-Backed Session Restore
expected: |
  How to test:
  1. In Terminal, from /Users/gabe/sirius-mac, run:
     xcodebuild -project SiriusMac.xcodeproj -scheme SiriusMac -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/sirius-mac-uat build
     open -n /tmp/sirius-mac-uat/Build/Products/Debug/SiriusMac.app
  2. On the first launch, click Sign In. Sign in inside the embedded SiriusXM area if prompted; enter credentials only there, never in this chat.
  3. When the embedded site shows that you are logged in, click Use Logged-In Session. Wait for “Ready to listen.”
  4. Quit Sirius Mac with Command-Q.
  5. Relaunch it with the same open command, then click Sign In once. Do not click Use Logged-In Session on this launch.
  Pass if the app uses the stored session, shows “Verifying sign-in,” then “Checking subscription,” and reaches “Ready to listen” without reopening the website sign-in flow. If setup never reaches “Ready to listen,” report the exact title and message shown instead.
result: issue
reported: "I signed in, then clicked \"use logged-in session\" and it gave me: \"Sign-in flow unsupported. This sign-in flow is unsupported. No workaround was attempted.\""
severity: blocker

### 11. Memory-First Local Session Cleanup
expected: |
  How to test from the “Sign-in flow unsupported” screen you have now:
  1. Click Clear Local Session once.
  2. Wait for the operation to finish; do not click Retry Sign In.
  3. Observe the title, message, and available buttons.
  Pass if the app shows “Signed out” (or “Signed out with cleanup warning” if cleanup was incomplete) and does not automatically start another sign-in. Report the exact title/message if anything else happens.
result: pass

### 12. Semantic authentication, entitlement, terminal, and cleanup presentation states remain distinct and expose continuation only for entitled sessions.
expected: Semantic authentication, entitlement, terminal, and cleanup presentation states remain distinct and expose continuation only for entitled sessions.
result: pass
source: automated
coverage_id: D1
coverage_summary: 01-05-SUMMARY.md

### 13. Explicit sign-in, session-use, retry, and sign-out actions are single-flight and use semantic cleanup results without automatic follow-up work.
expected: Explicit sign-in, session-use, retry, and sign-out actions are single-flight and use semantic cleanup results without automatic follow-up work.
result: pass
source: automated
coverage_id: D2
coverage_summary: 01-05-SUMMARY.md

### 14. Explicit native WebView consent selects only one current first-party token and emits one opaque volatile credential.
expected: Explicit native WebView consent selects only one current first-party token and emits one opaque volatile credential.
result: pass
source: automated
coverage_id: D1
coverage_summary: 01-06-SUMMARY.md

### 15. Sign-out deletes matching apex and subdomain tokens with a post-delete rescan, and bridge tests remain unconditionally compiled.
expected: Sign-out deletes matching apex and subdomain tokens with a post-delete rescan, and bridge tests remain unconditionally compiled.
result: pass
source: automated
coverage_id: D2
coverage_summary: 01-06-SUMMARY.md

### 16. A client-owned transaction performs native authentication followed by entitlement and persists only after confirmed entitlement.
expected: A client-owned transaction performs native authentication followed by entitlement and persists only after confirmed entitlement.
result: pass
source: automated
coverage_id: D1
coverage_summary: 01-07-SUMMARY.md

### 17. Native Authentication State Flow
expected: |
  How to test from the “Signed out” screen you have now:
  1. Click Retry Sign In once.
  2. Complete the embedded website sign-in if needed, then click Use Logged-In Session once.
  3. While the progress indicator is visible, try clicking an action a second time and watch the native heading.
  4. Wait for the final screen; do not click Retry again.
  Pass this presentation-state check if the app moves through one state at a time, prevents a second overlapping action, and stops on one clearly worded final state with no automatic retry. The already-observed “Sign-in flow unsupported” result still fails Test 10; here it is acceptable only as evidence that the terminal state is presented safely. Report any overlapping action, automatic retry, or unclear final screen.
result: blocked
blocked_by: other
reason: "User declined further SiriusXM sign-in attempts until sufficient privacy-safe logging is added, because repeated logins could increase bot-detection or account-blocking risk."

### 18. Phase 0 authentication-review findings are enforced by deterministic native and package regressions.
expected: Phase 0 authentication-review findings are enforced by deterministic native and package regressions.
result: pass
source: automated
coverage_id: D1
coverage_summary: 01-08-SUMMARY.md

### 19. Phase 1 has no active Phase 0 authority or alternate authentication-selection dependency.
expected: Phase 1 has no active Phase 0 authority or alternate authentication-selection dependency.
result: pass
source: automated
coverage_id: D2
coverage_summary: 01-08-SUMMARY.md

### 20. An accepted WebView credential remains single-consumption within one attempt and stale unconsumed material is erased before an explicit re-arm.
expected: An accepted WebView credential remains single-consumption within one attempt and stale unconsumed material is erased before an explicit re-arm.
result: pass
source: automated
coverage_id: D1
coverage_summary: 01-09-SUMMARY.md

### 21. Explicit retry after a terminal native authentication result completes a newly armed bridge-to-client transaction without automatic retry.
expected: Explicit retry after a terminal native authentication result completes a newly armed bridge-to-client transaction without automatic retry.
result: pass
source: automated
coverage_id: D2
coverage_summary: 01-09-SUMMARY.md

### 22. Explicit new login after sign-out completes native authentication and entitlement using one fresh credential handoff.
expected: Explicit new login after sign-out completes native authentication and entitlement using one fresh credential handoff.
result: pass
source: automated
coverage_id: D3
coverage_summary: 01-09-SUMMARY.md

### 23. Fresh and sequential explicit cleanup retires actor state, invokes Keychain and browser cleaners truthfully, coalesces overlap, and permits only explicit retries.
expected: Fresh and sequential explicit cleanup retires actor state, invokes Keychain and browser cleaners truthfully, coalesces overlap, and permits only explicit retries.
result: pass
source: automated
coverage_id: D1
coverage_summary: 01-10-SUMMARY.md

### 24. A fresh native composition removes randomized synthetic Keychain and matching browser residue without authentication or entitlement requests.
expected: A fresh native composition removes randomized synthetic Keychain and matching browser residue without authentication or entitlement requests.
result: pass
source: automated
coverage_id: D2
coverage_summary: 01-10-SUMMARY.md

### 25. Fresh cleanup failures remain signed out and expose another explicit cleanup action without automatic retry.
expected: Fresh cleanup failures remain signed out and expose another explicit cleanup action without automatic retry.
result: pass
source: automated
coverage_id: D3
coverage_summary: 01-10-SUMMARY.md

### 26. Consolidated native Xcode test graph with one active SiriusMacTests target and canonical source membership.
expected: Consolidated native Xcode test graph with one active SiriusMacTests target and canonical source membership.
result: pass
source: automated
coverage_id: D1
coverage_summary: 01-11-SUMMARY.md

### 27. Overlapping explicit WebView selections read cookies once and transfer one opaque credential.
expected: Overlapping explicit WebView selections read cookies once and transfer one opaque credential.
result: pass
source: automated
coverage_id: D1
coverage_summary: 01-12-SUMMARY.md

### 28. Cancellation and malformed pre-commit paths release only the uncommitted reservation, while post-commit cancellation remains consumed.
expected: Cancellation and malformed pre-commit paths release only the uncommitted reservation, while post-commit cancellation remains consumed.
result: pass
source: automated
coverage_id: D2
coverage_summary: 01-12-SUMMARY.md

### 29. Injected cookie-store and handoff-disposal controls reproduce race and re-arm boundaries without timing tolerances.
expected: Injected cookie-store and handoff-disposal controls reproduce race and re-arm boundaries without timing tolerances.
result: pass
source: automated
coverage_id: D3
coverage_summary: 01-12-SUMMARY.md

### 30. Internal profile-v4 and subscription-v1 decoders establish an active actor-owned session only after exact settled evidence.
expected: Internal profile-v4 and subscription-v1 decoders establish an active actor-owned session only after exact settled evidence.
result: pass
source: automated
coverage_id: D1
coverage_summary: 01-13-SUMMARY.md

### 31. Redirect, status, content, control, malformed, and ambiguous responses stay terminal without fallback.
expected: Redirect, status, content, control, malformed, and ambiguous responses stay terminal without fallback.
result: pass
source: automated
coverage_id: D2
coverage_summary: 01-13-SUMMARY.md

### 32. Shared invented fixtures and internal schema types do not leak provider detail or sensitive material to consumers.
expected: Shared invented fixtures and internal schema types do not leak provider detail or sensitive material to consumers.
result: pass
source: automated
coverage_id: D3
coverage_summary: 01-13-SUMMARY.md

### 33. The real URLSession redirect delegate records each attempt before it cancels every follow-up request.
expected: The real URLSession redirect delegate records each attempt before it cancels every follow-up request.
result: pass
source: automated
coverage_id: D1
coverage_summary: 01-14-SUMMARY.md

### 34. Redirect handling keeps authorization material ephemeral by retaining only a scalar count and no active request state.
expected: Redirect handling keeps authorization material ephemeral by retaining only a scalar count and no active request state.
result: pass
source: automated
coverage_id: D2
coverage_summary: 01-14-SUMMARY.md

### 35. Secure, exact apex/www token selection rejects insecure, expired, lookalike, unsupported-path, and unapproved-subdomain cookies in both bridge paths.
expected: Secure, exact apex/www token selection rejects insecure, expired, lookalike, unsupported-path, and unapproved-subdomain cookies in both bridge paths.
result: pass
source: automated
coverage_id: D1
coverage_summary: 01-15-SUMMARY.md

### 36. Sign-out requires successful exact delete/rescan evidence and nonpersistent website-session retirement, while every partial failure remains explicit.
expected: Sign-out requires successful exact delete/rescan evidence and nonpersistent website-session retirement, while every partial failure remains explicit.
result: pass
source: automated
coverage_id: D2
coverage_summary: 01-15-SUMMARY.md

### 37. A fresh nonpersistent configuration and WebView replace the retired browser child without exposing unrelated browser state.
expected: A fresh nonpersistent configuration and WebView replace the retired browser child without exposing unrelated browser state.
result: pass
source: automated
coverage_id: D3
coverage_summary: 01-15-SUMMARY.md

### 38. Explicit bounded Keychain restore stages one opaque credential and reaches entitlement only through ordered native authentication and entitlement.
expected: Explicit bounded Keychain restore stages one opaque credential and reaches entitlement only through ordered native authentication and entitlement.
result: pass
source: automated
coverage_id: D1
coverage_summary: 01-16-SUMMARY.md

### 39. Missing, unavailable, malformed, and rejected stored material fails closed, is erased where possible, and never falls through in the same attempt.
expected: Missing, unavailable, malformed, and rejected stored material fails closed, is erased where possible, and never falls through in the same attempt.
result: pass
source: automated
coverage_id: D2
coverage_summary: 01-16-SUMMARY.md

### 40. Explicit sign-out after restored success clears Keychain material and exact WebView residue through the existing client cleanup pipeline.
expected: Explicit sign-out after restored success clears Keychain material and exact WebView residue through the existing client cleanup pipeline.
result: pass
source: automated
coverage_id: D3
coverage_summary: 01-16-SUMMARY.md

## Summary

total: 40
passed: 38
issues: 1
pending: 0
skipped: 0
blocked: 1

## Gaps

- gap_id: G-01-10
  truth: "A user can transfer the embedded SiriusXM login into native authentication, reach entitlement, and later restore the stored session."
  status: failed
  reason: "User reported: after signing in and clicking Use Logged-In Session, the app displayed 'Sign-in flow unsupported. This sign-in flow is unsupported. No workaround was attempted.'"
  severity: blocker
  test: 10
  artifacts: []
  missing: []
